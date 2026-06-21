module health

// health_indicator_test.v - Tests for the health check system (SubTask D3.4)
//
// Covers:
//   - Health model: UP/DOWN/UNKNOWN status, is_up/is_down, with_detail
//   - HealthStatus.str() string conversion
//   - HealthIndicator interface via test stubs (AlwaysUp/AlwaysDown)
//   - HealthRegistry: empty, single UP, single DOWN, mixed, multiple
//   - Built-in indicators: Db, Cache, Disk, Memory (UP and DOWN paths)
//   - AggregatedHealth: components map, overall status aggregation
//   - JSON formatting: status, components, details, escaping
//   - Concurrency: check_all under goroutine load, no race/crash

// ============================================================
// Test Stub Indicators
// ============================================================

// AlwaysUpIndicator always reports UP with a configurable detail.
struct AlwaysUpIndicator {
	name_str string
	detail_k string
	detail_v string
}

fn (a &AlwaysUpIndicator) name() string {
	return a.name_str
}

fn (a &AlwaysUpIndicator) check() Health {
	mut h := new_health(.up)
	if a.detail_k.len > 0 {
		h.details[a.detail_k] = a.detail_v
	}
	return h
}

// AlwaysDownIndicator always reports DOWN with an error detail.
struct AlwaysDownIndicator {
	name_str  string
	error_msg string
}

fn (a &AlwaysDownIndicator) name() string {
	return a.name_str
}

fn (a &AlwaysDownIndicator) check() Health {
	mut h := new_health(.down)
	h.details['error'] = a.error_msg
	return h
}

// ============================================================
// Health Model Tests
// ============================================================

fn test_health_up_status() {
	h := new_health(.up)
	assert h.status == .up
	assert h.is_up() == true
	assert h.is_down() == false
}

fn test_health_down_status() {
	h := new_health(.down)
	assert h.status == .down
	assert h.is_up() == false
	assert h.is_down() == true
}

fn test_health_unknown_status() {
	h := new_health(.unknown)
	assert h.status == .unknown
	assert h.is_up() == false
	assert h.is_down() == false
}

fn test_health_with_detail_adds_to_map() {
	mut h := new_health(.up)
	h.with_detail('database', 'connected')
	h.with_detail('latency_ms', '12')
	assert h.details.len == 2
	assert h.details['database'] == 'connected'
	assert h.details['latency_ms'] == '12'
}

fn test_health_new_starts_with_empty_details() {
	h := new_health(.up)
	assert h.details.len == 0
}

fn test_health_checked_at_is_set() {
	h := new_health(.up)
	// checked_at should be a valid time (not zero).
	assert h.checked_at.unix() > 0
}

// ============================================================
// HealthStatus.str() Tests
// ============================================================

fn test_health_status_str_up() {
	assert HealthStatus.up.str() == 'UP'
}

fn test_health_status_str_down() {
	assert HealthStatus.down.str() == 'DOWN'
}

fn test_health_status_str_unknown() {
	assert HealthStatus.unknown.str() == 'UNKNOWN'
}

// ============================================================
// Test Stub Indicator Tests
// ============================================================

fn test_always_up_indicator_check_returns_up() {
	indicator := &AlwaysUpIndicator{
		name_str: 'test-up'
		detail_k: 'test'
		detail_v: 'ok'
	}
	h := indicator.check()
	assert h.status == .up
	assert h.is_up() == true
	assert h.details['test'] == 'ok'
}

fn test_always_up_indicator_name() {
	indicator := &AlwaysUpIndicator{
		name_str: 'my-indicator'
	}
	assert indicator.name() == 'my-indicator'
}

fn test_always_down_indicator_check_returns_down() {
	indicator := &AlwaysDownIndicator{
		name_str:  'test-down'
		error_msg: 'connection refused'
	}
	h := indicator.check()
	assert h.status == .down
	assert h.is_down() == true
	assert h.details['error'] == 'connection refused'
}

fn test_always_down_indicator_name() {
	indicator := &AlwaysDownIndicator{
		name_str: 'failing-indicator'
	}
	assert indicator.name() == 'failing-indicator'
}

// ============================================================
// HealthRegistry Tests
// ============================================================

fn test_registry_empty_check_all_returns_up() {
	mut registry := new_health_registry()
	agg := registry.check_all()
	assert agg.status == .up
	assert agg.is_up() == true
	assert agg.components.len == 0
}

fn test_registry_count_starts_at_zero() {
	mut registry := new_health_registry()
	assert registry.count() == 0
}

fn test_registry_count_after_register() {
	mut registry := new_health_registry()
	registry.register(&AlwaysUpIndicator{ name_str: 'a' })
	assert registry.count() == 1
	registry.register(&AlwaysUpIndicator{ name_str: 'b' })
	assert registry.count() == 2
}

fn test_registry_one_up_indicator() {
	mut registry := new_health_registry()
	registry.register(&AlwaysUpIndicator{ name_str: 'svc', detail_k: 'test', detail_v: 'ok' })
	agg := registry.check_all()
	assert agg.status == .up
	assert agg.components.len == 1
	assert 'svc' in agg.components
	assert agg.components['svc'].status == .up
}

fn test_registry_one_down_indicator() {
	mut registry := new_health_registry()
	registry.register(&AlwaysDownIndicator{ name_str: 'svc', error_msg: 'fail' })
	agg := registry.check_all()
	assert agg.status == .down
	assert agg.is_down() == true
	assert agg.components.len == 1
	assert agg.components['svc'].status == .down
}

fn test_registry_mixed_up_and_down_returns_down() {
	mut registry := new_health_registry()
	registry.register(&AlwaysUpIndicator{ name_str: 'up-svc' })
	registry.register(&AlwaysDownIndicator{ name_str: 'down-svc', error_msg: 'fail' })
	agg := registry.check_all()
	// Any DOWN → overall DOWN
	assert agg.status == .down
	assert agg.components.len == 2
	assert agg.components['up-svc'].status == .up
	assert agg.components['down-svc'].status == .down
}

fn test_registry_multiple_up_returns_up() {
	mut registry := new_health_registry()
	registry.register(&AlwaysUpIndicator{ name_str: 'svc1' })
	registry.register(&AlwaysUpIndicator{ name_str: 'svc2' })
	registry.register(&AlwaysUpIndicator{ name_str: 'svc3' })
	agg := registry.check_all()
	assert agg.status == .up
	assert agg.components.len == 3
}

fn test_registry_multiple_down_returns_down() {
	mut registry := new_health_registry()
	registry.register(&AlwaysDownIndicator{ name_str: 'svc1', error_msg: 'fail1' })
	registry.register(&AlwaysDownIndicator{ name_str: 'svc2', error_msg: 'fail2' })
	agg := registry.check_all()
	assert agg.status == .down
	assert agg.components.len == 2
	assert agg.components['svc1'].status == .down
	assert agg.components['svc2'].status == .down
}

fn test_registry_components_contain_all_indicators() {
	mut registry := new_health_registry()
	registry.register(&AlwaysUpIndicator{ name_str: 'alpha' })
	registry.register(&AlwaysDownIndicator{ name_str: 'beta', error_msg: 'x' })
	registry.register(&AlwaysUpIndicator{ name_str: 'gamma' })
	agg := registry.check_all()
	assert agg.components.len == 3
	assert 'alpha' in agg.components
	assert 'beta' in agg.components
	assert 'gamma' in agg.components
}

fn test_registry_aggregated_checked_at_is_set() {
	mut registry := new_health_registry()
	registry.register(&AlwaysUpIndicator{ name_str: 'svc' })
	agg := registry.check_all()
	assert agg.checked_at.unix() > 0
}

fn test_registry_check_all_reflects_live_state() {
	mut registry := new_health_registry()
	registry.register(&AlwaysUpIndicator{ name_str: 'svc' })
	agg1 := registry.check_all()
	assert agg1.components.len == 1

	// Register another indicator and check again.
	registry.register(&AlwaysDownIndicator{ name_str: 'svc2', error_msg: 'fail' })
	agg2 := registry.check_all()
	assert agg2.components.len == 2
	assert agg2.status == .down
}

// ============================================================
// DbHealthIndicator Tests
// ============================================================

fn test_db_health_indicator_up() {
	indicator := &DbHealthIndicator{
		ping_fn: fn () ! {}
	}
	h := indicator.check()
	assert h.status == .up
	assert h.is_up() == true
	assert h.details['database'] == 'connected'
}

fn test_db_health_indicator_down_on_error() {
	indicator := &DbHealthIndicator{
		ping_fn: fn () ! {
			return error('connection refused')
		}
	}
	h := indicator.check()
	assert h.status == .down
	assert h.is_down() == true
	assert h.details['error'] == 'connection refused'
}

fn test_db_health_indicator_name() {
	indicator := &DbHealthIndicator{
		ping_fn: fn () ! {}
	}
	assert indicator.name() == 'db'
}

// ============================================================
// CacheHealthIndicator Tests
// ============================================================

fn test_cache_health_indicator_up() {
	indicator := &CacheHealthIndicator{
		ping_fn: fn () ! {}
	}
	h := indicator.check()
	assert h.status == .up
	assert h.is_up() == true
	assert h.details['cache'] == 'connected'
}

fn test_cache_health_indicator_down_on_error() {
	indicator := &CacheHealthIndicator{
		ping_fn: fn () ! {
			return error('redis timeout')
		}
	}
	h := indicator.check()
	assert h.status == .down
	assert h.is_down() == true
	assert h.details['error'] == 'redis timeout'
}

fn test_cache_health_indicator_name() {
	indicator := &CacheHealthIndicator{
		ping_fn: fn () ! {}
	}
	assert indicator.name() == 'cache'
}

// ============================================================
// DiskHealthIndicator Tests
// ============================================================

fn test_disk_health_indicator_up_for_existing_dir() {
	indicator := &DiskHealthIndicator{
		path: '/tmp'
	}
	h := indicator.check()
	assert h.status == .up
	assert h.is_up() == true
	assert h.details['path'] == '/tmp'
}

fn test_disk_health_indicator_down_for_missing_path() {
	indicator := &DiskHealthIndicator{
		path: '/nonexistent/path/that/should/not/exist'
	}
	h := indicator.check()
	assert h.status == .down
	assert h.is_down() == true
	assert h.details['error'].len > 0
}

fn test_disk_health_indicator_name() {
	indicator := &DiskHealthIndicator{
		path: '/tmp'
	}
	assert indicator.name() == 'disk'
}

// ============================================================
// MemoryHealthIndicator Tests
// ============================================================

fn test_memory_health_indicator_always_up() {
	indicator := &MemoryHealthIndicator{}
	h := indicator.check()
	assert h.status == .up
	assert h.is_up() == true
	assert h.details['status'] == 'ok'
}

fn test_memory_health_indicator_with_threshold() {
	indicator := &MemoryHealthIndicator{
		max_usage_percent: 90
	}
	h := indicator.check()
	assert h.status == .up
	assert h.details['threshold_percent'] == '90'
}

fn test_memory_health_indicator_name() {
	indicator := &MemoryHealthIndicator{}
	assert indicator.name() == 'memory'
}

// ============================================================
// JSON Formatting Tests
// ============================================================

fn test_format_health_json_empty_registry() {
	mut registry := new_health_registry()
	agg := registry.check_all()
	json_str := format_health_json(agg)
	assert json_str == '{"status":"UP","components":{}}'
}

fn test_format_health_json_single_up() {
	agg := AggregatedHealth{
		status:     .up
		components: {
			'db': new_health(.up)
		}
	}
	json_str := format_health_json(agg)
	assert json_str.contains('"status":"UP"')
	assert json_str.contains('"db"')
	assert json_str.contains('"components"')
}

fn test_format_health_json_with_details() {
	mut h := new_health(.up)
	h.details['database'] = 'connected'
	agg := AggregatedHealth{
		status:     .up
		components: {
			'db': h
		}
	}
	json_str := format_health_json(agg)
	assert json_str.contains('"details"')
	assert json_str.contains('"database":"connected"')
}

fn test_format_health_json_down_status() {
	agg := AggregatedHealth{
		status:     .down
		components: {
			'db': new_health(.down)
		}
	}
	json_str := format_health_json(agg)
	assert json_str.contains('"status":"DOWN"')
}

fn test_format_health_json_unknown_status() {
	agg := AggregatedHealth{
		status:     .unknown
		components: {}
	}
	json_str := format_health_json(agg)
	assert json_str.contains('"status":"UNKNOWN"')
}

fn test_json_escape_quotes() {
	assert json_escape('hello"world') == 'hello\\"world'
}

fn test_json_escape_backslash() {
	assert json_escape('path\\to\\file') == 'path\\\\to\\\\file'
}

fn test_json_escape_newline() {
	assert json_escape('line1\nline2') == 'line1\\nline2'
}

fn test_json_escape_empty_string() {
	assert json_escape('') == ''
}

fn test_json_escape_plain_string_unchanged() {
	assert json_escape('hello world') == 'hello world'
}

// ============================================================
// Concurrency Tests
// ============================================================

// check_all_worker repeatedly calls check_all from a goroutine.
fn check_all_worker(done chan bool, registry &HealthRegistry, n int) {
	for _ in 0 .. n {
		mut r := unsafe { registry }
		_ = r.check_all()
	}
	done <- true
}

fn test_concurrent_check_all_no_crash() {
	mut registry := new_health_registry()
	registry.register(&AlwaysUpIndicator{ name_str: 'svc1' })
	registry.register(&AlwaysDownIndicator{ name_str: 'svc2', error_msg: 'fail' })

	num_workers := 20
	iterations := 50
	done := chan bool{cap: num_workers}

	for _ in 0 .. num_workers {
		spawn check_all_worker(done, registry, iterations)
	}
	for _ in 0 .. num_workers {
		_ := <-done
	}
	// If we reach here without crashing/deadlocking, the test passes.
}

fn test_concurrent_register_and_check_all() {
	mut registry := new_health_registry()

	// Pre-populate with some indicators.
	registry.register(&AlwaysUpIndicator{ name_str: 'base' })

	num_workers := 10
	done := chan bool{cap: num_workers * 2}

	// Writers: register indicators concurrently.
	for w in 0 .. num_workers {
		spawn fn (done chan bool, registry &HealthRegistry, w int) {
			mut r := unsafe { registry }
			r.register(&AlwaysUpIndicator{ name_str: 'worker_${w}' })
			done <- true
		}(done, registry, w)
	}

	// Readers: call check_all concurrently while writers register.
	for _ in 0 .. num_workers {
		spawn fn (done chan bool, registry &HealthRegistry) {
			mut r := unsafe { registry }
			_ = r.check_all()
			done <- true
		}(done, registry)
	}

	for _ in 0 .. (num_workers * 2) {
		_ := <-done
	}

	// After all workers finish, the registry should have base + worker_0..9.
	agg := registry.check_all()
	assert agg.components.len >= 1
	assert 'base' in agg.components
}

fn test_concurrent_check_all_returns_consistent_status() {
	// All indicators are UP → every concurrent check_all must return UP.
	mut registry := new_health_registry()
	registry.register(&AlwaysUpIndicator{ name_str: 'svc1' })
	registry.register(&AlwaysUpIndicator{ name_str: 'svc2' })
	registry.register(&AlwaysUpIndicator{ name_str: 'svc3' })

	num_workers := 30
	done := chan bool{cap: num_workers}

	for _ in 0 .. num_workers {
		spawn fn (done chan bool, registry &HealthRegistry) {
			mut r := unsafe { registry }
			agg := r.check_all()
			assert agg.status == .up
			done <- true
		}(done, registry)
	}
	for _ in 0 .. num_workers {
		_ := <-done
	}
}
