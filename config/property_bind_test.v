module config

// property_bind_test.v — @[value] / @[config_field] 属性绑定回归
//
// 覆盖三类历史缺陷：
//   1. comptime `field.attrs` 原文是 `value: 'key'`，不归一化就匹配不上；
//   2. bind_to_struct 一旦带了 Environment 就完全不再查 Config；
//   3. 嵌套结构的子键用错了前缀（app.inner.host 被拼成 app.db.host.host）。

// MapSource 是一个只读的内存属性源，测试里用作 Environment 的底座。
struct MapSource {
	name_str string = 'map'
mut:
	props map[string]string
}

fn (s &MapSource) name() string {
	return s.name_str
}

fn (mut s MapSource) get_property(key string) ?string {
	return s.props[key] or { none }
}

fn (mut s MapSource) contains_property(key string) bool {
	return key in s.props
}

fn (mut s MapSource) get_all_with_prefix(prefix string) map[string]string {
	mut result := map[string]string{}
	for key, value in s.props {
		if key.starts_with(prefix) {
			result[key] = value
		}
	}
	return result
}

fn env_with(props map[string]string) &Environment {
	mut env := new_environment()
	mut source := &MapSource{
		props: props
	}
	env.add_source(source)
	return env
}

// ── normalize_attrs ──

fn test_normalize_attrs_keeps_raw_comptime_form() {
	// V 的 comptime 原文就是 `name: 'arg'`，归一化后不应改变。
	assert normalize_attrs(["value: 'app.name'"]) == ["value: 'app.name'"]
	assert normalize_attrs(['component']) == ['component']
}

fn test_normalize_attrs_accepts_call_and_bare_forms() {
	assert normalize_attrs(["value('app.name')"]) == ["value: 'app.name'"]
	assert normalize_attrs(['value:app.name']) == ['value: app.name']
	assert normalize_attrs(['  component  ']) == ['component']
	assert normalize_attrs([]) == []
}

fn test_extract_value_works_on_raw_comptime_attrs() {
	// 真实 comptime 形态（带空格）
	attrs := ["value: 'db.host:5432'"]
	assert extract_value_key(attrs) == 'db.host'
	assert extract_value_default(attrs) == '5432'
	assert extract_value_expr_full(attrs) == 'db.host:5432'
}

// ── bind_to_struct ──

struct FlatConfig {
	host  string @[value: 'app.db.host']
	port  int    @[value: 'app.db.port:5432']
	ratio f64    @[value: 'app.db.ratio:0.5']
	debug bool   @[value: 'app.db.debug']
	plain string
}

fn test_bind_to_struct_honours_value_attrs() {
	mut cfg := new()
	cfg.set('app.db.host', 'localhost')
	cfg.set('app.db.port', '6543')
	cfg.set('app.db.ratio', '0.75')
	cfg.set('app.db.debug', 'true')
	cfg.set('plain', 'raw')

	binder := new_property_binder(cfg)
	bound := binder.bind_to_struct[FlatConfig]()!
	assert bound.host == 'localhost'
	assert bound.port == 6543
	assert bound.ratio == 0.75
	assert bound.debug == true
	assert bound.plain == 'raw'
}

fn test_bind_to_struct_uses_default_when_key_missing() {
	mut cfg := new()
	binder := new_property_binder(cfg)
	bound := binder.bind_to_struct[FlatConfig]()!
	assert bound.host == ''
	assert bound.port == 5432
	assert bound.ratio == 0.5
	assert bound.debug == false
}

fn test_bind_to_struct_reads_environment_when_config_misses() {
	mut cfg := new()
	cfg.set('plain', 'from-config')
	mut env := env_with({
		'app.db.host': 'from-env'
		'app.db.port': '7777'
	})
	binder := new_property_binder_with_env(cfg, env)
	bound := binder.bind_to_struct[FlatConfig]()!
	// Environment 补位；Config 已有的键不被覆盖。
	assert bound.host == 'from-env'
	assert bound.port == 7777
	assert bound.plain == 'from-config'
}

fn test_bind_to_struct_config_wins_over_environment() {
	mut cfg := new()
	cfg.set('app.db.host', 'from-config')
	mut env := env_with({
		'app.db.host': 'from-env'
	})
	binder := new_property_binder_with_env(cfg, env)
	bound := binder.bind_to_struct[FlatConfig]()!
	assert bound.host == 'from-config'
}

fn test_bind_to_struct_resolves_placeholders() {
	mut env := env_with({
		'base.host':   'backend'
		'app.db.host': '\${base.host}.local'
	})
	binder := new_property_binder_with_env(new(), env)
	bound := binder.bind_to_struct[FlatConfig]()!
	assert bound.host == 'backend.local'
}

fn test_bind_to_struct_empty_value_beats_default() {
	mut cfg := new()
	cfg.set('app.db.port', '')
	binder := new_property_binder(cfg)
	bound := binder.bind_to_struct[FlatConfig]()!
	// 显式配置空值必须压过默认值（用 has() 判断，不看长度）。
	assert bound.port == 0
}

// ── bind_configuration_properties ──

struct NestedDb {
	host string
	port int
}

struct AppConfig {
	inner NestedDb
	name  string
	up    string @[value: 'app.db.host']
}

struct DbConfig {
	host     string
	port     int
	timeout  f64
	ssl      bool
	replicas []string
	ports    []int
	flags    []bool
}

fn test_bind_configuration_properties_prefix_and_nesting() {
	mut env := env_with({
		'app.name':       'photon'
		'app.db.host':    'localhost'
		'app.inner.host': 'nested-host'
		'app.inner.port': '1212'
	})
	bound := bind_configuration_properties[AppConfig](mut env, 'app')!
	assert bound.name == 'photon'
	// 嵌套结构按字段地址取键：app.inner.host
	assert bound.inner.host == 'nested-host'
	assert bound.inner.port == 1212
	// @[value] 给出的是绝对属性地址，不该再被前缀二次拼接
	assert bound.up == 'localhost'
}

fn test_bind_configuration_properties_types_and_arrays() {
	mut env := env_with({
		'app.db.host':     'h'
		'app.db.port':     '5432'
		'app.db.timeout':  '1.5'
		'app.db.ssl':      'yes'
		'app.db.replicas': 'r1, r2 ,r3'
		'app.db.ports':    '80,443'
		'app.db.flags':    'true,0'
	})
	bound := bind_configuration_properties[DbConfig](mut env, 'app.db')!
	assert bound.host == 'h'
	assert bound.port == 5432
	assert bound.timeout == 1.5
	assert bound.ssl == true
	assert bound.replicas == ['r1', 'r2', 'r3']
	assert bound.ports == [80, 443]
	assert bound.flags == [true, false]
}

fn test_bind_configuration_properties_defaults_for_arrays() {
	mut env := env_with({
		'app.db.host': 'only'
	})
	bound := bind_configuration_properties[DbConfig](mut env, 'app.db')!
	assert bound.replicas.len == 0
	assert bound.ports.len == 0
	assert bound.flags.len == 0
}

struct WithConfigField {
	hostname string @[config_field: 'host']
	port     int    @[config_field: 'port:9090']
}

fn test_bind_configuration_properties_config_field_attr() {
	mut env := env_with({
		'net.host': 'cf-host'
		'net.port': '8080'
	})
	bound := bind_configuration_properties[WithConfigField](mut env, 'net')!
	assert bound.hostname == 'cf-host'
	assert bound.port == 8080
}
