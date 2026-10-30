module health

// health_aggregation_test.v — 三态聚合与「没配 ping_fn」的边界
//
// 老实现只看 DOWN，UNKNOWN 一律被算进 UP。探针回 200 不代表没事，
// 只代表没人在报坏事。
import os

struct UnknownIndicator {
	name_str string
}

struct UnknownUpIndicator {
	name_str string
}

fn (u &UnknownUpIndicator) name() string {
	return u.name_str
}

fn (u &UnknownUpIndicator) check() Health {
	return new_health(.up)
}

// 下面两个 helper 与 health_indicator_test.v 里的同名类型不同名，
// 免得一条 `v test health/` 把两个文件编进同一包时撞车。
struct UnknownDownIndicator {
	name_str  string
	error_msg string
}

fn (u &UnknownDownIndicator) name() string {
	return u.name_str
}

fn (u &UnknownDownIndicator) check() Health {
	mut h := new_health(.down)
	h.details['error'] = u.error_msg
	return h
}

fn (u &UnknownIndicator) name() string {
	return u.name_str
}

fn (u &UnknownIndicator) check() Health {
	return new_health(.unknown)
}

fn test_unknown_component_degrades_overall_to_unknown() {
	mut registry := new_health_registry()
	registry.register(&UnknownUpIndicator{ name_str: 'up-svc' })
	registry.register(&UnknownIndicator{ name_str: 'weird-svc' })
	agg := registry.check_all()
	assert agg.status == .unknown, 'a component that reports UNKNOWN must not be rounded up to UP'
	assert agg.components['weird-svc'].status == .unknown
}

fn test_down_outranks_unknown() {
	mut registry := new_health_registry()
	registry.register(&UnknownIndicator{ name_str: 'weird-svc' })
	registry.register(&UnknownDownIndicator{ name_str: 'down-svc', error_msg: 'fail' })
	agg := registry.check_all()
	assert agg.status == .down, 'DOWN is more severe than UNKNOWN'
}

fn test_all_unknown_returns_unknown() {
	mut registry := new_health_registry()
	registry.register(&UnknownIndicator{ name_str: 'a' })
	registry.register(&UnknownIndicator{ name_str: 'b' })
	assert registry.check_all().status == .unknown
}

fn test_db_indicator_without_ping_fn_is_unknown_not_crash() {
	// ping_fn 是 `fn () ! = unsafe { nil }`，不配就直接调会踩空指针。
	// 这种情况属于「配置漏了」，报 UNKNOWN 并带上原因。
	h := (&DbHealthIndicator{}).check()
	assert h.status == .unknown
	assert h.details['error'].contains('not configured')
}

fn test_cache_indicator_without_ping_fn_is_unknown_not_crash() {
	h := (&CacheHealthIndicator{}).check()
	assert h.status == .unknown
	assert h.details['error'].contains('not configured')
}

fn test_unconfigured_indicator_keeps_probe_from_reporting_up() {
	// 一个配了 Db 却忘了给 ping_fn 的应用：不能回 200。
	mut registry := new_health_registry()
	registry.register(&DbHealthIndicator{})
	registry.register(&DiskHealthIndicator{ path: os.temp_dir() })
	agg := registry.check_all()
	assert agg.status == .unknown, 'overall must reflect the unknown db component'
}

fn test_unknown_status_json_roundtrip() {
	mut registry := new_health_registry()
	registry.register(&UnknownIndicator{ name_str: 'weird-svc' })
	json := format_health_json(registry.check_all())
	assert json.contains('"status":"UNKNOWN"')
}
