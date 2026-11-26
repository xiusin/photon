module runtime

// runtime.v — 运行时值容器（ProcessRuntime）
//
// 启动时刻、启动耗时、进程 ID 这类值不属于业务配置，却是控制器和服务都会
// 用到的「运行时事实」。以前它们靠手工穿参：
//
//   start := time.ticks()
//   mut web_app := init_app(mut ctx, start)   // 穿进 App
//   home_ctrl.start_time = start_time          // 再穿进控制器
//
// 控制器已经由容器创建和注入，这层穿参就纯粹是胶水：新增一个需要 uptime 的
// Bean，就得再改一遍启动代码。这里把它做成一个普通 Bean，谁要谁 @[autowired]。
//
// 属性 vs Bean 的分界：
//   - 启动时刻本身（app.start.time / app.start.tick）走 Environment，
//     因为 bootstrap 里其它配置也从那儿读，且能被 --app.start.time 覆盖
//   - 由它推导出来的值（uptime、可读格式）留在这个 Bean 里算 —— Environment
//     只存字面量，不存可推导的东西
import os
import time

// ProcessRuntime 进程运行期信息。由容器创建并注入，全局单例。
//
// 不标 @[service] 是有原因的：V 0.5.2 下只要 example 模块里出现
// `core.scan_and_register[T]` / `core.scan_component_info[T]`，
// core/scanner.v 的 comptime `$for` 产物就解析不了，编译直接失败：
//
//   core/scanner.v:700:17: error: definition of `ast.SelectorExpr{...}
//                          is unknown at compile time
//
// 该缺陷与本模块的注解无关（`scan_component_info` 用来跨包扫组件，
// 而 generic 实例最终在 core 里展开，查找根不对）。所以注解只做文档用，
// 实际注册走 bootstrap 里的 register_factory + 外挂 annotation_binding。
pub struct ProcessRuntime {
pub:
	// start_time 进程启动的 Unix 秒
	start_time i64 @[value: 'app.start.time']
	// start_tick 进程启动的单调时钟刻度（ms），uptime 用它算，不受系统时间跳变影响
	start_tick i64 @[value: 'app.start.tick']
	// pid 进程 ID
	pid int @[value: 'app.pid']
}

// uptime_ms 进程已运行毫秒数
pub fn (r &ProcessRuntime) uptime_ms() i64 {
	if r.start_tick <= 0 {
		return 0
	}
	return time.ticks() - r.start_tick
}

// start_time_formatted 启动时刻的可读格式（本地时区）
pub fn (r &ProcessRuntime) start_time_formatted() string {
	if r.start_time <= 0 {
		return '-'
	}
	return time.unix(r.start_time).format_ss()
}

// ProcessRuntimeFactory 把「按类型创建」这一步交给容器接口。
//
// 用 FactoryBean 而不是 BeanDefinition + 泛型实例化：V 0.5.2 下 example 里调
// 核心的泛型 comptime 入口会踩到上面那个缺陷；FactoryBean 是纯运行时接口，
// 在这里能正常工作。
//
// 注意 create() 里并没有 time.ticks() —— 启动时刻来自启动时冻结进
// Environment 的属性，值什么时候取、取哪一份，都不该由「Bean 何时被建」决定。
// 绑定那一步（@[value]）由容器完成，见 bootstrap.v 的说明。
pub struct ProcessRuntimeFactory {}

pub fn (f &ProcessRuntimeFactory) create() !voidptr {
	mut r := &ProcessRuntime{}
	return voidptr(r)
}

pub fn (f &ProcessRuntimeFactory) bean_type() string {
	return 'ProcessRuntime'
}

pub fn (f &ProcessRuntimeFactory) is_singleton() bool {
	return true
}

// new_process_runtime_factory 构造工厂实例（供 register_factory 用）。
pub fn new_process_runtime_factory() &ProcessRuntimeFactory {
	return &ProcessRuntimeFactory{}
}

// new_with_moment 用给定的启动时刻直接构造实例，不经过容器。
// 只给测试/无容器场景用；生产路径走 freeze_start_moment + 容器注入，
// 那时 @[value] 字段会被绑定成同样的三个值。
pub fn new_with_moment(start_time i64, start_tick i64) &ProcessRuntime {
	return &ProcessRuntime{
		start_time: start_time
		start_tick: start_tick
		pid:        os.getpid()
	}
}
