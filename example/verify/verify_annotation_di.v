module main

// verify_annotation_di.v — 注解式依赖注入与解析（经 comptime 真实可用）
//
// 1) @[value('key')] 字段注入 —— ValueAnnotationPostProcessor 从 Environment
//    按注解的键把属性注入到结构体字段（string/int/bool/f64）。
// 2) @[configuration] + @[bean] 声明式 Bean —— 容器扫描 @[bean] 方法，
//    实例化并按类型在 Bean 之间注入依赖，再通过 resolve 解析取回。

import core

// ── @[value] 注入目标 ──
// 注：本机 V 0.5.1 下 @[value('key')] 括号形式解析失败，改用等价的冒号形式
// @[value: 'key']（框架的 core.extract_value_expr 同样支持两种形式）。
struct InjectedConfig {
mut:
	app_name  string @[value: 'app.name']
	port      int    @[value: 'app.port']
	debug     bool   @[value: 'app.debug']
	ratio     f64    @[value: 'app.ratio']
	untouched string // 无注解字段，应保持零值
}

// WideInjectedConfig 演示扩展的标量宽度与数组类型支持
struct WideInjectedConfig {
mut:
	max_conns  u16      @[value: 'pool.max']
	cache_size u64      @[value: 'cache.size']
	level      i8       @[value: 'log.level']
	origins    []string @[value: 'cors.origins']
	ports      []int    @[value: 'lb.ports']
	flags      []bool   @[value: 'feature.flags']
}

fn verify_value_injection(mut v Verifier) {
	v.section('注解式注入 — @[value] 字段注入 (框架真实 API)')

	// 1) 框架编译期提取 @[value] 注解键
	keys := core.value_keys[InjectedConfig]()
	v.check('value_keys 提取 4 个 @[value] 键', keys.len == 4)
	v.check('value_keys 含 app.name', 'app.name' in keys)

	// 2) 框架真实注入器 inject_values_for_bean（从 Environment 注入）
	mut env := core.new_environment()
	env.set_property('app.name', 'PhotonAPI')
	env.set_property('app.port', '8080')
	env.set_property('app.debug', 'true')
	env.set_property('app.ratio', '0.75')

	mut pp := core.ValueAnnotationPostProcessor{
		environment: env
	}
	mut cfg := InjectedConfig{}
	pp.inject_values_for_bean[InjectedConfig](mut cfg) or {
		v.check('inject_values_for_bean 执行', false)
		return
	}
	v.check('@[value] 注入 string', cfg.app_name == 'PhotonAPI')
	v.check('@[value] 注入 int', cfg.port == 8080)
	v.check('@[value] 注入 bool', cfg.debug == true)
	v.check('@[value] 注入 f64', cfg.ratio == 0.75)
	v.check('@[value] 无注解字段保持零值', cfg.untouched == '')

	// 3) 框架 bind_values（直接从 map 绑定）
	mut cfg_map := InjectedConfig{}
	pp.bind_values[InjectedConfig](mut cfg_map, {
		'app.name':  'FromMap'
		'app.port':  '7000'
		'app.debug': 'false'
		'app.ratio': '1.5'
	}) or {
		v.check('bind_values 从 map 绑定', false)
		return
	}
	v.check('bind_values 从 map 注入 string', cfg_map.app_name == 'FromMap')
	v.check('bind_values 从 map 注入 int', cfg_map.port == 7000)

	// 3.5) 扩展类型支持：标量宽度 (u16/u64/i8) + 数组 ([]string/[]int/[]bool)
	mut wide := WideInjectedConfig{}
	pp.bind_values[WideInjectedConfig](mut wide, {
		'pool.max':      '500'
		'cache.size':    '1073741824'
		'log.level':     '-2'
		'cors.origins':  'https://a.com, https://b.com'
		'lb.ports':      '8080,8081,8082'
		'feature.flags': 'true,0,1'
	}) or {
		v.check('bind_values 扩展类型', false)
		return
	}
	v.check('@[value] 注入 u16', wide.max_conns == u16(500))
	v.check('@[value] 注入 u64', wide.cache_size == u64(1073741824))
	v.check('@[value] 注入 i8', wide.level == i8(-2))
	v.check('@[value] 注入 []string (逗号分隔)', wide.origins == ['https://a.com', 'https://b.com'])
	v.check('@[value] 注入 []int (逗号分隔)', wide.ports == [8080, 8081, 8082])
	v.check('@[value] 注入 []bool (逗号分隔)', wide.flags == [true, false, true])

	// 4) 缺失键 → 可读错误
	mut pp2 := core.ValueAnnotationPostProcessor{
		environment: core.new_environment()
	}
	mut cfg2 := InjectedConfig{}
	mut errored := false
	pp2.inject_values_for_bean[InjectedConfig](mut cfg2) or {
		errored = true
	}
	v.check('@[value] 缺失键时返回错误', errored)
}

// ── @[configuration] + @[bean] 声明式 Bean ──
struct DataSourceBean {
pub mut:
	url string
}

struct UserServiceBean {
pub mut:
	name string
	ds   DataSourceBean
}

// AppBeans 是一个 @[configuration] 配置类，其 @[bean] 方法声明式地生产 Bean。
@[configuration]
struct AppBeans {}

// datasource 是 0 参 @[bean] 方法（容器实例化并以方法名 'datasource' 注册）。
@[bean]
pub fn (c AppBeans) datasource() DataSourceBean {
	return DataSourceBean{
		url: 'localhost:5432'
	}
}

// user_service 是 1 参 @[bean] 方法，依赖 DataSourceBean（容器按类型注入）。
@[bean]
pub fn (c AppBeans) user_service(ds DataSourceBean) UserServiceBean {
	return UserServiceBean{
		name: 'primary'
		ds:   ds
	}
}

fn verify_bean_methods(mut v Verifier) {
	v.section('注解式注入 — @[configuration] + @[bean] 声明式 Bean + 依赖注入')

	mut ctx := core.new_application_context()

	// 1) 扫描 @[bean] 方法并注册 BeanDefinition
	methods := ctx.register_configuration[AppBeans]() or {
		v.check('register_configuration[@[configuration]]', false)
		return
	}
	v.check('扫描到 2 个 @[bean] 方法', methods.len == 2)
	v.check('注册 datasource Bean 定义', ctx.has('datasource'))
	v.check('注册 user_service Bean 定义', ctx.has('user_service'))

	// 2) 实例化 0 参 @[bean]（datasource）
	ctx.register_bean_method_factory[AppBeans, DataSourceBean]() or {
		v.check('register_bean_method_factory(0参)', false)
		return
	}
	ds := ctx.resolve_typed[DataSourceBean]('datasource') or {
		v.check('resolve datasource Bean', false)
		return
	}
	v.check('@[bean] 实例化并 resolve (datasource.url)', ds.url == 'localhost:5432')

	// 3) 实例化 1 参 @[bean]（user_service），容器按类型注入 DataSourceBean 依赖
	ctx.register_bean_method_with_dep[AppBeans, UserServiceBean, DataSourceBean]() or {
		v.check('register_bean_method_with_dep(1参依赖注入)', false)
		return
	}
	us := ctx.resolve_typed[UserServiceBean]('user_service') or {
		v.check('resolve user_service Bean', false)
		return
	}
	v.check('@[bean] 方法间依赖注入 (user_service.name)', us.name == 'primary')
	v.check('@[bean] 依赖被正确注入 (user_service.ds.url)', us.ds.url == 'localhost:5432')

	// 4) 非 @[configuration] 类型被拒绝（契约校验）
	mut errored := false
	ctx.register_configuration[DataSourceBean]() or {
		errored = true
	}
	v.check('非 @[configuration] 类型被拒绝', errored)

	ctx.shutdown()
}
