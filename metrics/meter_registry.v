module metrics

// meter_registry.v - Metrics Meter Registry (Spring Actuator / Micrometer-inspired)
//
// Provides a metrics collection abstraction with three meter types:
//   - Counter: monotonically increasing value (request count, bytes sent, ...)
//   - Gauge:   instantaneous value that can go up or down (queue depth, temperature, ...)
//   - Timer:   duration statistics — count + total time (request latency, ...)
//
// The in-memory implementation is thread-safe:
//   - Each meter has its own sync.Mutex, so concurrent updates to different
//     meters never contend (no global lock per operation).
//   - The registry uses sync.RwMutex: meter lookup/creation uses read-lock for
//     the fast path (existing meter) and write-lock only for the rare
//     create-on-first-access path (double-checked locking).
//
// format_prometheus() emits the Prometheus text exposition format (version
// 0.0.4) suitable for scraping via the /metrics actuator endpoint.
import sync
import time
import strings

// ============================================================
// Meter Types
// ============================================================

// MeterType identifies the kind of meter.
pub enum MeterType {
	counter
	gauge
	timer
}

// ============================================================
// Interfaces (SubTask D1.1)
// ============================================================

// Counter tracks a monotonically increasing value.
// Increments are thread-safe; the value never decreases.
pub interface Counter {
	name() string
	tags() map[string]string
	value() i64
mut:
	increment()
	increment_by(n i64)
}

// Gauge tracks an instantaneous value that can go up or down.
pub interface Gauge {
	name() string
	tags() map[string]string
	value() f64
mut:
	set(value f64)
}

// Timer tracks duration statistics: number of recorded events and their
// cumulative duration. Use start()/record_sample() to measure elapsed time,
// or record() to record a pre-computed duration.
pub interface Timer {
	name() string
	tags() map[string]string
	start() TimerSample
	count() i64
	total_time() time.Duration
mut:
	record(duration time.Duration)
	record_sample(sample TimerSample)
}

// TimerSample holds a timer start timestamp returned by Timer.start().
// Pass it to Timer.record_sample() to record the elapsed duration.
pub struct TimerSample {
pub:
	started_at time.Time
}

// MeterRegistry manages a collection of meters, deduplicating by name + tags.
pub interface MeterRegistry {
	list_meters() []MeterInfo
	format_prometheus() string
mut:
	counter(name string, tags map[string]string) Counter
	gauge(name string, tags map[string]string) Gauge
	timer(name string, tags map[string]string) Timer
}

// MeterInfo describes a registered meter.
pub struct MeterInfo {
pub:
	name string
	typ  MeterType
	tags map[string]string
}

// ============================================================
// InMemoryCounter (SubTask D1.2)
// ============================================================

// InMemoryCounter is a thread-safe Counter backed by a sync.Mutex.
// The mutex is per-meter, so concurrent counters never contend.
pub struct InMemoryCounter {
pub:
	name_str string
	tags_str map[string]string
mut:
	mu  sync.Mutex
	val i64
}

// increment adds 1 to the counter.
pub fn (mut c InMemoryCounter) increment() {
	c.mu.@lock()
	c.val++
	c.mu.unlock()
}

// increment_by adds n to the counter. n may be negative.
pub fn (mut c InMemoryCounter) increment_by(n i64) {
	c.mu.@lock()
	c.val += n
	c.mu.unlock()
}

// value returns the current counter value.
// Takes an immutable receiver; the internal mutex is locked via unsafe so
// reads can be served from immutable references (e.g. map iteration).
pub fn (c &InMemoryCounter) value() i64 {
	unsafe {
		c.mu.@lock()
	}
	v := c.val
	unsafe {
		c.mu.unlock()
	}
	return v
}

// name returns the meter name.
pub fn (c &InMemoryCounter) name() string {
	return c.name_str
}

// tags returns the meter tags.
pub fn (c &InMemoryCounter) tags() map[string]string {
	return c.tags_str
}

// ============================================================
// InMemoryGauge
// ============================================================

// InMemoryGauge is a thread-safe Gauge backed by a sync.Mutex.
pub struct InMemoryGauge {
pub:
	name_str string
	tags_str map[string]string
mut:
	mu  sync.Mutex
	val f64
}

// set replaces the gauge value.
pub fn (mut g InMemoryGauge) set(value f64) {
	g.mu.@lock()
	g.val = value
	g.mu.unlock()
}

// value returns the current gauge value.
pub fn (g &InMemoryGauge) value() f64 {
	unsafe {
		g.mu.@lock()
	}
	v := g.val
	unsafe {
		g.mu.unlock()
	}
	return v
}

// name returns the meter name.
pub fn (g &InMemoryGauge) name() string {
	return g.name_str
}

// tags returns the meter tags.
pub fn (g &InMemoryGauge) tags() map[string]string {
	return g.tags_str
}

// ============================================================
// InMemoryTimer
// ============================================================

// InMemoryTimer is a thread-safe Timer backed by a sync.Mutex.
// Tracks count and cumulative duration (in nanoseconds, via time.Duration).
pub struct InMemoryTimer {
pub:
	name_str string
	tags_str map[string]string
mut:
	mu        sync.Mutex
	count_val i64
	total     time.Duration
}

// start returns a TimerSample capturing the current instant.
// The sample is immutable and can be passed to record_sample() later.
pub fn (t &InMemoryTimer) start() TimerSample {
	return TimerSample{
		started_at: time.now()
	}
}

// record adds a pre-computed duration to the timer statistics.
pub fn (mut t InMemoryTimer) record(duration time.Duration) {
	t.mu.@lock()
	t.count_val++
	t.total += duration
	t.mu.unlock()
}

// record_sample records the elapsed time since the sample was started.
pub fn (mut t InMemoryTimer) record_sample(sample TimerSample) {
	elapsed := time.since(sample.started_at)
	t.record(elapsed)
}

// count returns the number of recorded events.
pub fn (t &InMemoryTimer) count() i64 {
	unsafe {
		t.mu.@lock()
	}
	v := t.count_val
	unsafe {
		t.mu.unlock()
	}
	return v
}

// total_time returns the cumulative recorded duration.
pub fn (t &InMemoryTimer) total_time() time.Duration {
	unsafe {
		t.mu.@lock()
	}
	v := t.total
	unsafe {
		t.mu.unlock()
	}
	return v
}

// name returns the meter name.
pub fn (t &InMemoryTimer) name() string {
	return t.name_str
}

// tags returns the meter tags.
pub fn (t &InMemoryTimer) tags() map[string]string {
	return t.tags_str
}

// ============================================================
// InMemoryMeterRegistry (SubTask D1.2)
// ============================================================

// InMemoryMeterRegistry is a thread-safe MeterRegistry storing meters in
// memory. Meters are deduplicated by name + tags: the first call to
// counter()/gauge()/timer() for a given name+tags creates the meter; later
// calls return the same instance.
//
// Concurrency:
//   - mu (sync.RwMutex) protects the three maps.
//   - Meter lookup uses read-lock (fast path); creation uses write-lock with
//     double-check to avoid duplicate meters under races.
//   - Each meter has its own mutex, so meter operations do not contend on the
//     registry lock.
pub struct InMemoryMeterRegistry {
mut:
	mu       sync.RwMutex
	counters map[string]&InMemoryCounter
	gauges   map[string]&InMemoryGauge
	timers   map[string]&InMemoryTimer
}

// new_in_memory_registry creates and returns a new InMemoryMeterRegistry.
pub fn new_in_memory_registry() &InMemoryMeterRegistry {
	return &InMemoryMeterRegistry{
		counters: map[string]&InMemoryCounter{}
		gauges:   map[string]&InMemoryGauge{}
		timers:   map[string]&InMemoryTimer{}
	}
}

// meter_key generates a deterministic unique key from name + tags.
// Tags are sorted by key so that {a=1,b=2} and {b=2,a=1} map to the same meter.
fn meter_key(name string, tags map[string]string) string {
	if tags.len == 0 {
		return name
	}
	mut keys := []string{cap: tags.len}
	for k, _ in tags {
		keys << k
	}
	keys.sort()
	mut parts := []string{cap: keys.len}
	for k in keys {
		parts << '${k}=${tags[k]}'
	}
	return '${name}{${parts.join(',')}}'
}

// counter returns (creating if necessary) the Counter registered under name+tags.
pub fn (mut r InMemoryMeterRegistry) counter(name string, tags map[string]string) Counter {
	key := meter_key(name, tags)
	// Fast path: existing meter under read-lock.
	r.mu.@rlock()
	if key in r.counters {
		existing := unsafe { r.counters[key] }
		r.mu.runlock()
		return existing
	}
	r.mu.runlock()
	// Slow path: create under write-lock with double-check.
	r.mu.@lock()
	defer { r.mu.unlock() }
	if key in r.counters {
		return unsafe { r.counters[key] }
	}
	c := &InMemoryCounter{
		name_str: name
		tags_str: tags
	}
	r.counters[key] = c
	return c
}

// gauge returns (creating if necessary) the Gauge registered under name+tags.
pub fn (mut r InMemoryMeterRegistry) gauge(name string, tags map[string]string) Gauge {
	key := meter_key(name, tags)
	r.mu.@rlock()
	if key in r.gauges {
		existing := unsafe { r.gauges[key] }
		r.mu.runlock()
		return existing
	}
	r.mu.runlock()
	r.mu.@lock()
	defer { r.mu.unlock() }
	if key in r.gauges {
		return unsafe { r.gauges[key] }
	}
	g := &InMemoryGauge{
		name_str: name
		tags_str: tags
	}
	r.gauges[key] = g
	return g
}

// timer returns (creating if necessary) the Timer registered under name+tags.
pub fn (mut r InMemoryMeterRegistry) timer(name string, tags map[string]string) Timer {
	key := meter_key(name, tags)
	r.mu.@rlock()
	if key in r.timers {
		existing := unsafe { r.timers[key] }
		r.mu.runlock()
		return existing
	}
	r.mu.runlock()
	r.mu.@lock()
	defer { r.mu.unlock() }
	if key in r.timers {
		return unsafe { r.timers[key] }
	}
	t := &InMemoryTimer{
		name_str: name
		tags_str: tags
	}
	r.timers[key] = t
	return t
}

// list_meters returns a snapshot of all registered meters.
pub fn (r &InMemoryMeterRegistry) list_meters() []MeterInfo {
	unsafe {
		r.mu.@rlock()
	}
	defer {
		unsafe {
			r.mu.runlock()
		}
	}
	mut result := []MeterInfo{cap: r.counters.len + r.gauges.len + r.timers.len}
	for _, c in r.counters {
		result << MeterInfo{
			name: c.name_str
			typ:  .counter
			tags: c.tags_str
		}
	}
	for _, g in r.gauges {
		result << MeterInfo{
			name: g.name_str
			typ:  .gauge
			tags: g.tags_str
		}
	}
	for _, t in r.timers {
		result << MeterInfo{
			name: t.name_str
			typ:  .timer
			tags: t.tags_str
		}
	}
	return result
}

// format_prometheus emits all meters in Prometheus text exposition format
// (version 0.0.4). Counters emit `counter` type, gauges emit `gauge` type,
// and timers emit a `summary` with `_count` and `_sum` (in nanoseconds) lines.
//
// The registry read-lock is held only while snapshotting meter pointers; each
// meter's value is then read under its own per-meter lock, so a slow meter
// read never blocks meter creation.
pub fn (r &InMemoryMeterRegistry) format_prometheus() string {
	mut sb := strings.new_builder(1024)

	// Snapshot meter pointers under read-lock.
	unsafe {
		r.mu.@rlock()
	}
	mut cs := []&InMemoryCounter{cap: r.counters.len}
	for _, c in r.counters {
		cs << c
	}
	mut gs := []&InMemoryGauge{cap: r.gauges.len}
	for _, g in r.gauges {
		gs << g
	}
	mut ts := []&InMemoryTimer{cap: r.timers.len}
	for _, t in r.timers {
		ts << t
	}
	unsafe {
		r.mu.runlock()
	}

	// Format counters (sorted by name for deterministic output).
	cs.sort_with_compare(fn (a &&InMemoryCounter, b &&InMemoryCounter) int {
		if a.name_str < b.name_str {
			return -1
		}
		if a.name_str > b.name_str {
			return 1
		}
		return 0
	})
	for c in cs {
		name_str := c.name_str
		tag_str := format_tags(c.tags_str)
		sb.writeln('# HELP ${name_str} Counter')
		sb.writeln('# TYPE ${name_str} counter')
		sb.writeln('${name_str}${tag_str} ${c.value()}')
	}

	// Format gauges.
	gs.sort_with_compare(fn (a &&InMemoryGauge, b &&InMemoryGauge) int {
		if a.name_str < b.name_str {
			return -1
		}
		if a.name_str > b.name_str {
			return 1
		}
		return 0
	})
	for g in gs {
		name_str := g.name_str
		tag_str := format_tags(g.tags_str)
		sb.writeln('# HELP ${name_str} Gauge')
		sb.writeln('# TYPE ${name_str} gauge')
		sb.writeln('${name_str}${tag_str} ${g.value()}')
	}

	// Format timers as summaries.
	ts.sort_with_compare(fn (a &&InMemoryTimer, b &&InMemoryTimer) int {
		if a.name_str < b.name_str {
			return -1
		}
		if a.name_str > b.name_str {
			return 1
		}
		return 0
	})
	for t in ts {
		name_str := t.name_str
		tag_str := format_tags(t.tags_str)
		sb.writeln('# HELP ${name_str} Timer')
		sb.writeln('# TYPE ${name_str} summary')
		sb.writeln('${name_str}_count${tag_str} ${t.count()}')
		sb.writeln('${name_str}_sum${tag_str} ${t.total_time().nanoseconds()}')
	}

	return sb.str()
}

// format_tags renders tags in Prometheus label format: {key="value",...}.
// Keys are sorted for deterministic output. Returns '' when there are no tags.
fn format_tags(tags map[string]string) string {
	if tags.len == 0 {
		return ''
	}
	mut keys := []string{cap: tags.len}
	for k, _ in tags {
		keys << k
	}
	keys.sort()
	mut parts := []string{cap: keys.len}
	for k in keys {
		parts << '${k}="${tags[k]}"'
	}
	return '{${parts.join(',')}}'
}
