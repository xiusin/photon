module health

// health_indicator.v - Health Check System (Spring Boot Actuator-inspired)
//
// Provides a health-check abstraction for liveness/readiness probes and
// operational dashboards. Mirrors Spring Boot's HealthIndicator model:
//
//   - HealthIndicator: strategy interface — each subsystem (db, cache, disk,
//     memory, ...) implements `check() Health` to report its own status.
//   - HealthRegistry:  aggregates all registered indicators; overall status
//     is DOWN if ANY indicator is DOWN (Spring's default StatusAggregator).
//   - Health:          immutable status snapshot (UP/DOWN/UNKNOWN + details).
//
// The registry is thread-safe (sync.RwMutex): register() takes a write-lock,
// check_all() takes a read-lock and snapshots indicator pointers before
// invoking check() on each — so a slow indicator never blocks registration.
//
// Built-in indicators:
//   - DbHealthIndicator     — invokes a user-supplied ping fn () !void
//   - CacheHealthIndicator  — invokes a user-supplied ping fn () !void
//   - DiskHealthIndicator   — checks path exists via os.is_dir
//   - MemoryHealthIndicator — reports UP with usage details (placeholder)
//
// Usage:
//   import health
//
//   mut registry := health.new_health_registry()
//   registry.register(&health.DbHealthIndicator{ ping_fn: fn () !void { db.ping()! } })
//   registry.register(&health.DiskHealthIndicator{ path: '/var/data' })
//
//   agg := registry.check_all()
//   // agg.status == .up   → 200 OK
//   // agg.status == .down → 503 Service Unavailable
import sync
import time
import os
import strings

// ============================================================
// HealthStatus (SubTask D3.1)
// ============================================================

// HealthStatus is the tri-state health status used by all indicators.
pub enum HealthStatus {
	up
	down
	unknown
}

// str returns the canonical uppercase string representation used in JSON
// output and HTTP responses, matching Spring Boot's Status constants.
pub fn (s HealthStatus) str() string {
	return match s {
		.up { 'UP' }
		.down { 'DOWN' }
		.unknown { 'UNKNOWN' }
	}
}

// ============================================================
// Health Model (SubTask D3.1)
// ============================================================

// Health is a status snapshot returned by a HealthIndicator.
// The `details` map carries free-form diagnostic key/value pairs (e.g.
// "error": "connection refused", "database": "connected").
//
// Both `status` and `details` are `pub mut` so indicator implementations
// can build a Health via new_health(.up) and then mutate status/details
// on failure. Once returned from check(), callers should treat the Health
// as read-only.
pub struct Health {
pub:
	checked_at time.Time
pub mut:
	status  HealthStatus
	details map[string]string
}

// new_health creates a Health with the given status, an empty details map,
// and checked_at set to time.now().
pub fn new_health(status HealthStatus) Health {
	return Health{
		status:     status
		details:    map[string]string{}
		checked_at: time.now()
	}
}

// with_detail adds a key/value pair to the Health's details map and
// returns the modified Health for chaining. The receiver is mutated in
// place; use a mutable variable when chaining:
//   mut h := health.new_health(.up)
//   h.with_detail('database', 'connected')
//   h.with_detail('latency_ms', '12')
pub fn (mut h Health) with_detail(key string, value string) {
	h.details[key] = value
}

// is_up returns true when the status is UP.
pub fn (h Health) is_up() bool {
	return h.status == .up
}

// is_down returns true when the status is DOWN.
pub fn (h Health) is_down() bool {
	return h.status == .down
}

// ============================================================
// HealthIndicator Interface (SubTask D3.1)
// ============================================================

// HealthIndicator is the strategy interface for subsystem health checks.
// Each indicator reports a name (used as the key in aggregated output)
// and a Health snapshot via check().
//
// Implementations MUST be safe for concurrent access — check_all() may
// invoke check() on the same indicator from multiple goroutines.
pub interface HealthIndicator {
	name() string
	check() Health
}

// ============================================================
// AggregatedHealth (SubTask D3.1)
// ============================================================

// AggregatedHealth is the result of HealthRegistry.check_all(): the
// overall status (DOWN if any component is DOWN) plus per-component
// Health snapshots keyed by indicator name.
pub struct AggregatedHealth {
pub:
	status     HealthStatus
	components map[string]Health
	checked_at time.Time
}

// is_up returns true when the aggregated status is UP (all components UP).
pub fn (a AggregatedHealth) is_up() bool {
	return a.status == .up
}

// is_down returns true when the aggregated status is DOWN (any component DOWN).
pub fn (a AggregatedHealth) is_down() bool {
	return a.status == .down
}

// ============================================================
// HealthRegistry (SubTask D3.1)
// ============================================================

// HealthRegistry holds all registered HealthIndicators and aggregates
// their results via check_all().
//
// Concurrency:
//   - mu (sync.RwMutex) protects the indicators slice.
//   - register() takes a write-lock; check_all() takes a read-lock and
//     snapshots indicator pointers before invoking check() on each, so a
//     slow indicator never blocks registration.
pub struct HealthRegistry {
mut:
	mu         sync.RwMutex
	indicators []&HealthIndicator
}

// new_health_registry creates and returns an empty HealthRegistry.
pub fn new_health_registry() &HealthRegistry {
	return &HealthRegistry{
		indicators: []&HealthIndicator{}
	}
}

// register adds a HealthIndicator to the registry. Thread-safe.
pub fn (mut r HealthRegistry) register(indicator &HealthIndicator) {
	r.mu.@lock()
	r.indicators << indicator
	r.mu.unlock()
}

// count returns the number of registered indicators. Thread-safe.
pub fn (mut r HealthRegistry) count() int {
	r.mu.@rlock()
	defer { r.mu.runlock() }
	return r.indicators.len
}

// check_all invokes check() on every registered indicator and aggregates
// the results. The overall status is DOWN if ANY indicator is DOWN;
// otherwise UP (empty registry → UP).
//
// The read-lock is held only while snapshotting indicator pointers; each
// indicator's check() runs outside the lock so a slow indicator does not
// block registration or other checks.
pub fn (mut r HealthRegistry) check_all() AggregatedHealth {
	// Snapshot indicator pointers under read-lock.
	r.mu.@rlock()
	snapshot := r.indicators.clone()
	r.mu.runlock()

	mut components := map[string]Health{}
	mut overall_status := HealthStatus.up

	for indicator in snapshot {
		h := indicator.check()
		components[indicator.name()] = h
		if h.status == .down {
			overall_status = .down
		}
	}

	return AggregatedHealth{
		status:     overall_status
		components: components
		checked_at: time.now()
	}
}

// ============================================================
// Built-in Indicators (SubTask D3.2)
// ============================================================

// ── DbHealthIndicator ──

// DbHealthIndicator checks database connectivity by invoking a
// user-supplied ping function. UP when ping succeeds, DOWN with the
// error message when it fails.
pub struct DbHealthIndicator {
pub:
	ping_fn fn () ! = unsafe { nil }
}

// name returns the indicator's key in aggregated output.
pub fn (d &DbHealthIndicator) name() string {
	return 'db'
}

// check invokes the ping function and reports UP on success, DOWN with
// the error message on failure.
pub fn (d &DbHealthIndicator) check() Health {
	mut h := new_health(.up)
	d.ping_fn() or {
		h.status = .down
		h.details['error'] = err.msg()
		return h
	}
	h.details['database'] = 'connected'
	return h
}

// ── CacheHealthIndicator ──

// CacheHealthIndicator checks cache connectivity by invoking a
// user-supplied ping function. UP when ping succeeds, DOWN with the
// error message when it fails.
pub struct CacheHealthIndicator {
pub:
	ping_fn fn () ! = unsafe { nil }
}

// name returns the indicator's key in aggregated output.
pub fn (c &CacheHealthIndicator) name() string {
	return 'cache'
}

// check invokes the ping function and reports UP on success, DOWN with
// the error message on failure.
pub fn (c &CacheHealthIndicator) check() Health {
	mut h := new_health(.up)
	c.ping_fn() or {
		h.status = .down
		h.details['error'] = err.msg()
		return h
	}
	h.details['cache'] = 'connected'
	return h
}

// ── DiskHealthIndicator ──

// DiskHealthIndicator checks that a required filesystem path exists.
// UP when the path is a directory, DOWN with an error otherwise.
pub struct DiskHealthIndicator {
pub:
	path string
}

// name returns the indicator's key in aggregated output.
pub fn (d &DiskHealthIndicator) name() string {
	return 'disk'
}

// check verifies the configured path exists and is a directory.
pub fn (d &DiskHealthIndicator) check() Health {
	mut h := new_health(.up)
	if !os.is_dir(d.path) {
		h.status = .down
		h.details['error'] = 'path does not exist or is not a directory'
		h.details['path'] = d.path
		return h
	}
	h.details['path'] = d.path
	h.details['status'] = 'accessible'
	return h
}

// ── MemoryHealthIndicator ──

// MemoryHealthIndicator reports memory status. The current implementation
// always reports UP with a status detail — V's standard library does not
// expose cross-platform memory usage, so this serves as a placeholder
// that users can extend with platform-specific logic.
pub struct MemoryHealthIndicator {
pub:
	max_usage_percent int // optional threshold (reserved for future use)
}

// name returns the indicator's key in aggregated output.
pub fn (m &MemoryHealthIndicator) name() string {
	return 'memory'
}

// check reports memory status. Always UP in the base implementation.
pub fn (m &MemoryHealthIndicator) check() Health {
	mut h := new_health(.up)
	h.details['status'] = 'ok'
	if m.max_usage_percent > 0 {
		h.details['threshold_percent'] = m.max_usage_percent.str()
	}
	return h
}

// ============================================================
// JSON Formatting
// ============================================================

// format_health_json renders an AggregatedHealth as a JSON string
// following the Spring Boot /health response convention:
//
//   {"status":"UP","components":{"db":{"status":"UP","details":{"database":"connected"}}}}
//
// The overall status is always present; each component includes its
// status and (when non-empty) a details object. Keys are emitted in
// insertion order — no sorting is applied, matching V's map iteration.
pub fn format_health_json(agg AggregatedHealth) string {
	mut sb := strings.new_builder(256)
	sb.write_string('{"status":"')
	sb.write_string(agg.status.str())
	sb.write_string('","components":{')

	mut first := true
	for name, h in agg.components {
		if !first {
			sb.write_string(',')
		}
		first = false
		sb.write_string('"')
		sb.write_string(json_escape(name))
		sb.write_string('":{"status":"')
		sb.write_string(h.status.str())
		sb.write_string('"')
		if h.details.len > 0 {
			sb.write_string(',"details":{')
			mut dfirst := true
			for k, v in h.details {
				if !dfirst {
					sb.write_string(',')
				}
				dfirst = false
				sb.write_string('"')
				sb.write_string(json_escape(k))
				sb.write_string('":"')
				sb.write_string(json_escape(v))
				sb.write_string('"')
			}
			sb.write_string('}')
		}
		sb.write_string('}')
	}

	sb.write_string('}}')
	return sb.str()
}

// json_escape escapes a string for safe inclusion inside a JSON string
// literal. Handles the required escapes: ", \, and control characters
// (\n, \r, \t). Other characters are passed through unchanged.
pub fn json_escape(s string) string {
	if s.len == 0 {
		return ''
	}
	mut sb := strings.new_builder(s.len + 8)
	for ch in s {
		match ch {
			`"` { sb.write_string('\\"') }
			`\\` { sb.write_string('\\\\') }
			`\n` { sb.write_string('\\n') }
			`\r` { sb.write_string('\\r') }
			`\t` { sb.write_string('\\t') }
			else { sb.write_u8(u8(ch)) }
		}
	}
	return sb.str()
}
