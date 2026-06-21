module core

// value_injection_for_bean_test.v — 验证框架真实的 @[value] 注入入口
// inject_values_for_bean[T]（map 路径，规避 V 0.5.1 的 &&Environment 泛型 bug）。
// 使用 V 0.5.1 能解析的冒号形式 @[value: 'key']。

struct ForBeanConfig {
mut:
	app_name string @[value: 'app.name']
	port     int    @[value: 'app.port']
	debug    bool   @[value: 'app.debug']
	ratio    f64    @[value: 'app.ratio']
	plain    string // 无注解，应保持零值
}

fn test_inject_values_for_bean_real_api() {
	mut env := new_environment()
	env.set_property('app.name', 'Photon')
	env.set_property('app.port', '9090')
	env.set_property('app.debug', 'true')
	env.set_property('app.ratio', '0.5')

	mut pp := ValueAnnotationPostProcessor{
		environment: env
	}
	mut cfg := ForBeanConfig{}
	pp.inject_values_for_bean[ForBeanConfig](mut cfg)!

	assert cfg.app_name == 'Photon'
	assert cfg.port == 9090
	assert cfg.debug == true
	assert cfg.ratio == 0.5
	assert cfg.plain == ''
}

fn test_value_keys_extracts_annotation_keys() {
	keys := value_keys[ForBeanConfig]()
	// 4 个带 @[value] 注解的字段（plain 无注解）
	assert keys.len == 4
	assert 'app.name' in keys
	assert 'app.port' in keys
}

fn test_inject_values_for_bean_missing_key_errors() {
	mut pp := ValueAnnotationPostProcessor{
		environment: new_environment()
	}
	mut cfg := ForBeanConfig{}
	pp.inject_values_for_bean[ForBeanConfig](mut cfg) or {
		assert err.msg().contains('not found')
		return
	}
	assert false
}

fn test_bind_values_from_map() {
	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := ForBeanConfig{}
	props := {
		'app.name':  'MapPhoton'
		'app.port':  '7000'
		'app.debug': 'false'
		'app.ratio': '1.5'
	}
	pp.bind_values[ForBeanConfig](mut cfg, props)!
	assert cfg.app_name == 'MapPhoton'
	assert cfg.port == 7000
	assert cfg.debug == false
	assert cfg.ratio == 1.5
}

// WideConfig 覆盖扩展的标量宽度与数组类型
struct WideConfig {
mut:
	tiny   i8       @[value: 'n.tiny']
	small  i16      @[value: 'n.small']
	big    i64      @[value: 'n.big']
	ubyte  u8       @[value: 'n.ubyte']
	ushort u16      @[value: 'n.ushort']
	uint   u32      @[value: 'n.uint']
	ulong  u64      @[value: 'n.ulong']
	tags   []string @[value: 'n.tags']
	nums   []int    @[value: 'n.nums']
	rates  []f64    @[value: 'n.rates']
	flags  []bool   @[value: 'n.flags']
}

fn test_bind_values_wide_and_array_types() {
	mut pp := ValueAnnotationPostProcessor{}
	mut cfg := WideConfig{}
	props := {
		'n.tiny':   '-5'
		'n.small':  '1000'
		'n.big':    '9000000000'
		'n.ubyte':  '200'
		'n.ushort': '60000'
		'n.uint':   '4000000000'
		'n.ulong':  '18000000000000'
		'n.tags':   'a, b, c'
		'n.nums':   '1,2,3'
		'n.rates':  '0.5, 1.5'
		'n.flags':  'true,0,1'
	}
	pp.bind_values[WideConfig](mut cfg, props)!

	assert cfg.tiny == i8(-5)
	assert cfg.small == i16(1000)
	assert cfg.big == i64(9000000000)
	assert cfg.ubyte == u8(200)
	assert cfg.ushort == u16(60000)
	assert cfg.uint == u32(4000000000)
	assert cfg.ulong == u64(18000000000000)
	assert cfg.tags == ['a', 'b', 'c']
	assert cfg.nums == [1, 2, 3]
	assert cfg.rates == [0.5, 1.5]
	assert cfg.flags == [true, false, true]
}
