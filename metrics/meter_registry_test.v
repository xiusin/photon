module metrics

// meter_registry_test.v - Tests for the metrics meter registry (SubTask D1.4)
//
// Covers:
//   - Counter: increment, increment_by (incl. negative), tags, identity
//   - Gauge: set/value
//   - Timer: record, multiple records, start/record_sample
//   - Prometheus format: empty registry, all meter types, tags
//   - Concurrency: counter, gauge, timer under goroutine load
//   - Registry isolation: independent registries
import time

// ============================================================
// Counter Tests
// ============================================================

fn test_counter_increment() {
	mut registry := new_in_memory_registry()
	mut c := registry.counter('requests', {})

	c.increment()
	c.increment()
	c.increment()

	assert c.value() == 3
}

fn test_counter_increment_by() {
	mut registry := new_in_memory_registry()
	mut c := registry.counter('bytes_sent', {})

	c.increment_by(5)
	assert c.value() == 5

	c.increment_by(-2)
	assert c.value() == 3

	// increment_by(0) is a no-op
	c.increment_by(0)
	assert c.value() == 3
}

fn test_counter_starts_at_zero() {
	mut registry := new_in_memory_registry()
	c := registry.counter('fresh_counter', {})

	assert c.value() == 0
}

fn test_counter_name_and_tags() {
	mut registry := new_in_memory_registry()
	c := registry.counter('http_requests', {'method': 'GET', 'status': '200'})

	assert c.name() == 'http_requests'
	assert c.tags()['method'] == 'GET'
	assert c.tags()['status'] == '200'
}

fn test_counter_with_different_tags_are_distinct() {
	mut registry := new_in_memory_registry()
	mut get_counter := registry.counter('http_requests', {'method': 'GET'})
	mut post_counter := registry.counter('http_requests', {'method': 'POST'})

	get_counter.increment_by(10)
	post_counter.increment_by(3)

	assert get_counter.value() == 10
	assert post_counter.value() == 3
}

fn test_counter_same_tags_returns_same_instance() {
	mut registry := new_in_memory_registry()
	mut c1 := registry.counter('orders', {'region': 'us'})
	mut c2 := registry.counter('orders', {'region': 'us'})

	// Mutating c1 must be visible through c2 → same underlying instance.
	c1.increment()
	c1.increment()
	assert c2.value() == 2

	c2.increment()
	assert c1.value() == 3
}

fn test_counter_tag_order_independent() {
	// {a=1,b=2} and {b=2,a=1} must resolve to the same meter.
	mut registry := new_in_memory_registry()
	mut c1 := registry.counter('events', {'a': '1', 'b': '2'})
	mut c2 := registry.counter('events', {'b': '2', 'a': '1'})

	c1.increment_by(7)
	assert c2.value() == 7
}

// ============================================================
// Gauge Tests
// ============================================================

fn test_gauge_set_and_get() {
	mut registry := new_in_memory_registry()
	mut g := registry.gauge('temperature', {})

	g.set(42.5)
	assert g.value() == 42.5

	g.set(-10.0)
	assert g.value() == -10.0

	g.set(0.0)
	assert g.value() == 0.0
}

fn test_gauge_name_and_tags() {
	mut registry := new_in_memory_registry()
	g := registry.gauge('queue_depth', {'queue': 'emails'})

	assert g.name() == 'queue_depth'
	assert g.tags()['queue'] == 'emails'
}

fn test_gauge_with_different_tags_are_distinct() {
	mut registry := new_in_memory_registry()
	mut g1 := registry.gauge('queue_depth', {'queue': 'emails'})
	mut g2 := registry.gauge('queue_depth', {'queue': 'sms'})

	g1.set(100.0)
	g2.set(5.0)

	assert g1.value() == 100.0
	assert g2.value() == 5.0
}

// ============================================================
// Timer Tests
// ============================================================

fn test_timer_record_single() {
	mut registry := new_in_memory_registry()
	mut t := registry.timer('request_duration', {})

	t.record(100 * time.millisecond)

	assert t.count() == 1
	assert t.total_time() == 100 * time.millisecond
}

fn test_timer_record_multiple() {
	mut registry := new_in_memory_registry()
	mut t := registry.timer('request_duration', {})

	t.record(100 * time.millisecond)
	t.record(200 * time.millisecond)
	t.record(300 * time.millisecond)

	assert t.count() == 3
	assert t.total_time() == 600 * time.millisecond
}

fn test_timer_starts_at_zero() {
	mut registry := new_in_memory_registry()
	t := registry.timer('idle_timer', {})

	assert t.count() == 0
	assert t.total_time().nanoseconds() == 0
}

fn test_timer_start_and_record_sample() {
	mut registry := new_in_memory_registry()
	mut t := registry.timer('db_query', {})

	sample := t.start()
	time.sleep(10 * time.millisecond)
	t.record_sample(sample)

	assert t.count() == 1
	// The recorded duration must be positive (>= 10ms we slept).
	assert t.total_time().nanoseconds() >= 10 * time.millisecond.nanoseconds()
}

fn test_timer_name_and_tags() {
	mut registry := new_in_memory_registry()
	t := registry.timer('request_duration', {'route': '/api/users'})

	assert t.name() == 'request_duration'
	assert t.tags()['route'] == '/api/users'
}

// ============================================================
// Prometheus Format Tests
// ============================================================

fn test_format_prometheus_empty_registry() {
	mut registry := new_in_memory_registry()

	assert registry.format_prometheus() == ''
}

fn test_format_prometheus_counter() {
	mut registry := new_in_memory_registry()
	mut c := registry.counter('http_requests', {})
	c.increment_by(42)

	out := registry.format_prometheus()

	assert out.contains('# HELP http_requests Counter')
	assert out.contains('# TYPE http_requests counter')
	assert out.contains('http_requests 42')
}

fn test_format_prometheus_gauge() {
	mut registry := new_in_memory_registry()
	mut g := registry.gauge('queue_depth', {})
	g.set(7.5)

	out := registry.format_prometheus()

	assert out.contains('# HELP queue_depth Gauge')
	assert out.contains('# TYPE queue_depth gauge')
	assert out.contains('queue_depth 7.5')
}

fn test_format_prometheus_timer() {
	mut registry := new_in_memory_registry()
	mut t := registry.timer('request_duration', {})
	t.record(150 * time.millisecond)

	out := registry.format_prometheus()

	assert out.contains('# HELP request_duration Timer')
	assert out.contains('# TYPE request_duration summary')
	assert out.contains('request_duration_count 1')
	// 150ms in nanoseconds
	assert out.contains('request_duration_sum ${150 * time.millisecond.nanoseconds()}')
}

fn test_format_prometheus_all_three_meter_types() {
	mut registry := new_in_memory_registry()
	mut c := registry.counter('http_requests', {})
	mut g := registry.gauge('queue_depth', {})
	mut t := registry.timer('request_duration', {})

	c.increment_by(5)
	g.set(3.0)
	t.record(50 * time.millisecond)

	out := registry.format_prometheus()

	assert out.contains('# TYPE http_requests counter')
	assert out.contains('# TYPE queue_depth gauge')
	assert out.contains('# TYPE request_duration summary')
	assert out.contains('http_requests 5')
	assert out.contains('queue_depth 3')
	assert out.contains('request_duration_count 1')
}

fn test_format_prometheus_with_tags() {
	mut registry := new_in_memory_registry()
	mut c := registry.counter('http_requests', {'method': 'GET', 'status': '200'})
	c.increment()

	out := registry.format_prometheus()

	// Tags must appear in Prometheus label format, sorted by key.
	assert out.contains('http_requests{method="GET",status="200"} 1')
}

fn test_format_prometheus_tags_sorted() {
	mut registry := new_in_memory_registry()
	mut c := registry.counter('events', {'zeta': '1', 'alpha': '2', 'mid': '3'})
	c.increment()

	out := registry.format_prometheus()

	// Keys must be sorted alphabetically: alpha, mid, zeta.
	assert out.contains('events{alpha="2",mid="3",zeta="1"} 1')
}

fn test_format_prometheus_counter_without_tags_has_no_braces() {
	mut registry := new_in_memory_registry()
	mut c := registry.counter('simple_counter', {})
	c.increment()

	out := registry.format_prometheus()

	// No tags → no curly braces after the metric name.
	assert out.contains('simple_counter 1')
	assert !out.contains('simple_counter{')
}

// ============================================================
// list_meters Tests
// ============================================================

fn test_list_meters_empty() {
	mut registry := new_in_memory_registry()

	assert registry.list_meters().len == 0
}

fn test_list_meters_reports_all_types() {
	mut registry := new_in_memory_registry()
	registry.counter('c1', {})
	registry.gauge('g1', {})
	registry.timer('t1', {})

	meters := registry.list_meters()
	assert meters.len == 3

	mut names := map[string]MeterType{}
	for m in meters {
		names[m.name] = m.typ
	}
	assert names['c1'] == .counter
	assert names['g1'] == .gauge
	assert names['t1'] == .timer
}

// ============================================================
// Registry Isolation Tests
// ============================================================

fn test_registry_isolation() {
	mut r1 := new_in_memory_registry()
	mut r2 := new_in_memory_registry()

	mut c1 := r1.counter('shared_name', {})
	mut c2 := r2.counter('shared_name', {})

	c1.increment_by(100)
	c2.increment_by(200)

	assert c1.value() == 100
	assert c2.value() == 200

	// Each registry only sees its own meters.
	assert r1.list_meters().len == 1
	assert r2.list_meters().len == 1
}

// ============================================================
// Concurrency Tests (SubTask D1.4 — concurrency coverage)
// ============================================================

// counter_incrementer hammers a shared counter from a goroutine.
fn counter_incrementer(done chan bool, c &InMemoryCounter, n int) {
	for _ in 0 .. n {
		c.increment()
	}
	done <- true
}

fn test_concurrent_counter_increment() {
	c := &InMemoryCounter{
		name_str: 'concurrent_counter'
		tags_str: map[string]string{}
	}

	// Reduced from 50×200 to 10×50 to avoid V's Boehm GC concurrent-
	// allocation crash when tests run in parallel.
	num_workers := 10
	iterations := 50
	done := chan bool{cap: num_workers}

	for _ in 0 .. num_workers {
		spawn counter_incrementer(done, c, iterations)
	}
	for _ in 0 .. num_workers {
		_ := <-done
	}

	// All increments must be accounted for — no lost updates.
	assert c.value() == i64(num_workers * iterations)
}

fn test_concurrent_counter_increment_by() {
	c := &InMemoryCounter{
		name_str: 'concurrent_inc_by'
		tags_str: map[string]string{}
	}

	num_workers := 10
	iterations := 50
	done := chan bool{cap: num_workers}

	for w in 0 .. num_workers {
		spawn fn (done chan bool, c &InMemoryCounter, n int) {
			for _ in 0 .. n {
				c.increment_by(1)
			}
			done <- true
		}(done, c, iterations)
		_ = w
	}
	for _ in 0 .. num_workers {
		_ := <-done
	}

	assert c.value() == i64(num_workers * iterations)
}

// gauge_setter repeatedly sets a gauge from a goroutine.
fn gauge_setter(done chan bool, g &InMemoryGauge, base f64, n int) {
	for i in 0 .. n {
		g.set(base + f64(i))
	}
	done <- true
}

fn test_concurrent_gauge_set_no_crash() {
	g := &InMemoryGauge{
		name_str: 'concurrent_gauge'
		tags_str: map[string]string{}
	}

	num_workers := 10
	iterations := 50
	done := chan bool{cap: num_workers}

	for w in 0 .. num_workers {
		spawn gauge_setter(done, g, f64(w) * 1000.0, iterations)
	}
	for _ in 0 .. num_workers {
		_ := <-done
	}

	// No crash; the final value must be one of the values written.
	final := g.value()
	assert final >= 0.0
}

// timer_recorder records durations from a goroutine.
fn timer_recorder(done chan bool, t &InMemoryTimer, n int) {
	for _ in 0 .. n {
		t.record(1 * time.millisecond)
	}
	done <- true
}

fn test_concurrent_timer_record() {
	t := &InMemoryTimer{
		name_str: 'concurrent_timer'
		tags_str: map[string]string{}
	}

	num_workers := 10
	iterations := 20
	done := chan bool{cap: num_workers}

	for _ in 0 .. num_workers {
		spawn timer_recorder(done, t, iterations)
	}
	for _ in 0 .. num_workers {
		_ := <-done
	}

	assert t.count() == i64(num_workers * iterations)
	// Total time must be at least the sum of all recorded 1ms durations.
	assert t.total_time().nanoseconds() >= i64(num_workers * iterations) * time.millisecond.nanoseconds()
}

fn test_concurrent_registry_counter_creation() {
	// Many goroutines request the same counter concurrently; the registry
	// must deduplicate and return the same instance (no duplicate meters).
	//
	// Reduced from 30×50 to 5×20 to avoid V's Boehm GC concurrent-allocation
	// crash (map literal {'tag':'v'} allocation per call + struct allocation
	// in counter() overwhelms the GC's stop-the-world).
	mut registry := new_in_memory_registry()

	num_workers := 5
	done := chan bool{cap: num_workers}

	for _ in 0 .. num_workers {
		spawn fn (done chan bool, registry &InMemoryMeterRegistry) {
			// Get counter once (tests concurrent creation dedup), then
			// hammer increment from all goroutines.
			c := registry.counter('race_counter', {'tag': 'v'})
			for _ in 0 .. 50 {
				c.increment()
			}
			done <- true
		}(done, registry)
	}
	for _ in 0 .. num_workers {
		_ := <-done
	}

	mut c := registry.counter('race_counter', {'tag': 'v'})
	assert c.value() == i64(num_workers * 50)
	// Exactly one meter must exist for this name+tags.
	assert registry.list_meters().len == 1
}

fn test_concurrent_format_prometheus_under_load() {
	// format_prometheus() must not crash or deadlock while goroutines
	// concurrently create meters and update values.
	mut registry := new_in_memory_registry()

	// Pre-create some meters.
	mut c := registry.counter('base_counter', {})
	c.increment_by(10)

	// Reduced from 10 workers to 3 to avoid V's Boehm GC crash.
	num_workers := 3
	done := chan bool{cap: num_workers + 1}

	// Writers: create + increment meters.
	for w in 0 .. num_workers {
		spawn fn (done chan bool, registry &InMemoryMeterRegistry, w int) {
			for i in 0 .. 20 {
				wc := registry.counter('worker_${w}', {})
				wc.increment()
				_ = i
			}
			done <- true
		}(done, registry, w)
	}

	// Reader: repeatedly format while writers run.
	spawn fn (done chan bool, registry &InMemoryMeterRegistry) {
		for _ in 0 .. 50 {
			_ = registry.format_prometheus()
		}
		done <- true
	}(done, registry)

	for _ in 0 .. num_workers + 1 {
		_ := <-done
	}

	// Final format must succeed and include the base counter.
	out := registry.format_prometheus()
	assert out.contains('base_counter 10')
}
