module main

// verify_runtime_bean.v — 「运行时值收进容器」的验证
//
// 覆盖三件新能力：
//   1. core.freeze_start_moment_props —— 启动时刻在 refresh 之前冻结进 Environment
//   2. AnnotationBindingPostProcessor —— 在「定义登记完成、Bean 实例化前」
//      把注解元数据写回 BeanDefinition（含手写定义 / FactoryBean 那条路径）
//   3. apply_value_bindings[T] —— 按定义上的 value_bindings 把值绑进实例
//
// 三者串起来的结论：启动代码里不再需要 `home_ctrl.start_time = start_time`
// 这种穿参，需要 uptime 的 Bean 自己从容器里拿。
import photon.core
import time

// RuntimeProbe 模拟示例里的 ProcessRuntime：字段靠 @[value] 绑定。
struct RuntimeProbe {
mut:
	start_time i64
	start_tick i64
	label      string
}

// RuntimeProbeFactory 用 FactoryBean 造实例 —— 与 example 里的做法一致，
// 这条路径拿不到 scan_and_register[T] 的元数据，正是后处理器存在的理由。
struct RuntimeProbeFactory {}

fn (f &RuntimeProbeFactory) create() !voidptr {
	return voidptr(&RuntimeProbe{})
}

fn (f &RuntimeProbeFactory) bean_type() string {
	return 'RuntimeProbe'
}

fn (f &RuntimeProbeFactory) is_singleton() bool {
	return true
}

// uptime_ms 从冻结的 ticks 算差值，与 ProcessRuntime 同口径。
fn (r &RuntimeProbe) uptime_ms() i64 {
	if r.start_tick <= 0 {
		return 0
	}
	return time.ticks() - r.start_tick
}

fn verify_runtime_bean(mut v Verifier) {
	v.section('运行时值收进容器 — freeze_start_moment + 注解绑定后处理器')

	mut ctx := core.new_application_context()

	// 1) 启动时刻冻结：必须在 refresh 之前写进 Environment
	now_sec := time.now().unix()
	now_tick := time.ticks()
	core.freeze_start_moment_props(mut ctx, now_sec, now_tick)
	v.check('freeze_start_moment_props 写入 app.start.time',
		ctx.get_property('app.start.time') == '${now_sec}')
	v.check('freeze_start_moment_props 写入 app.start.tick',
		ctx.get_property('app.start.tick') == '${now_tick}')
	v.check('freeze_start_moment_props 写入 app.pid', ctx.get_property('app.pid').int() > 0)
	// 启动时刻可被命令行/环境变量覆盖 —— 属性表是普通配置源，不是私房字段
	ctx.set_property('app.start.time', '${now_sec - 10}')
	v.check('启动时刻可被覆盖（属性源语义一致）',
		ctx.get_property('app.start.time') == '${now_sec - 10}')
	ctx.set_property('app.start.time', '${now_sec}')

	// 2) 手写定义 + 工厂造实例：模拟 example 的注册方式
	mut def := core.new_bean_definition('RuntimeProbe')
	def.value_bindings = [
		core.ValueBinding{
			field_name: 'start_time'
			expr:       'app.start.time'
		},
		core.ValueBinding{
			field_name: 'start_tick'
			expr:       'app.start.tick'
		},
		core.ValueBinding{
			field_name: 'label'
			expr:       'app.label'
		},
	]
	ctx.set_property('app.label', 'probe')
	ctx.register(def) or {
		v.check('注册手写 BeanDefinition', false)
		return
	}
	ctx.register_factory('RuntimeProbe', &RuntimeProbeFactory{}) or {
		v.check('注册 FactoryBean', false)
		return
	}

	// 3) 注解绑定后处理器：把元数据回填到定义（此处定义已有，验证不覆盖业务字段）
	ctx.add_registry_post_processor(core.annotation_binding(core.AnnotationBinding{
		type_name:      'RuntimeProbe'
		value_bindings: [
			core.ValueBinding{
				field_name: 'start_time'
				expr:       'app.start.time'
			},
			core.ValueBinding{
				field_name: 'start_tick'
				expr:       'app.start.tick'
			},
			core.ValueBinding{
				field_name: 'label'
				expr:       'app.label'
			},
		]
	}))
	ctx.refresh() or {
		v.check('refresh 成功', false)
		return
	}

	// 4) 绑定前：实例是零值（工厂没填任何东西）
	probe := ctx.resolve_typed[RuntimeProbe]('RuntimeProbe') or {
		v.check('resolve RuntimeProbe', false)
		ctx.shutdown()
		return
	}
	v.check('工厂创建的实例初始为零值', probe.start_tick == 0)

	// 5) 绑定后：三个字段都来自容器里的属性
	ctx.apply_value_bindings[RuntimeProbe]('RuntimeProbe')
	v.check('@[value] 绑定 i64 (start_time)', probe.start_time == now_sec)
	v.check('@[value] 绑定 i64 (start_tick)', probe.start_tick == now_tick)
	v.check('@[value] 绑定 string (label)', probe.label == 'probe')

	// 6) 同一实例（单例语义没被绑定步骤破坏）
	again := ctx.resolve_typed[RuntimeProbe]('RuntimeProbe') or {
		v.check('二次 resolve', false)
		ctx.shutdown()
		return
	}
	v.check('绑定后仍是同一个单例实例', unsafe { again == probe })
	v.check('二次 resolve 读到的也是绑定后的值', again.start_tick == now_tick)

	// 7) uptime 从冻结的刻度算，跟「Bean 什么时候被建」无关
	v.check('uptime_ms 由冻结刻度推导（>= 0）', probe.uptime_ms() >= 0)
	v.check('uptime_ms 不因实例化时刻而漂移', probe.uptime_ms() < 60_000)

	ctx.shutdown()
}
