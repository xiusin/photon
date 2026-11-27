module core

import os

// safe_cast.v — Type-Safe Wrappers for V Interop Patterns
//
// V 0.5.x does not support implicit upcasting of concrete types to
// interface types (e.g. &Container → &BeanFactory).  The compiler also
// lacks an Option<T> for nullable function pointers.  These limitations
// force unsafe { ... } blocks in production code.
//
// This file centralises the unsafe patterns into well-documented wrapper
// functions.  Callers use the wrapper instead of raw unsafe, so all
// unsafety is confined to this single file with clear audit trails.
//
// Rules:
//   1. NEVER use `unsafe { nil }` — use `nil_sentinel[T]()` instead.
//   2. NEVER use `unsafe { &Interface(concrete) }` — use `as_interface()`.
//   3. If a new unsafe pattern emerges, add a wrapper HERE, not inline.

// ── Sentinel Nil Values ──
//
// V function-pointer fields cannot be Option<T>.  The idiomatic workaround
// is to assign `unsafe { nil }` and test with `isnil()` at runtime.
// `nil_sentinel[T]()` returns the typed nil for callable-function types,
// keeping the unsafe concern in one place.

// nil_sentinel returns a typed nil for nullable function-pointer fields.
// The caller must check `isnil(ptr)` before calling.
//
// Usage:
//   exec_fn SqlExecFn = nil_sentinel[SqlExecFn]()
//   if !isnil(repo.exec_fn) { repo.exec_fn(...) }
pub fn nil_sentinel[T]() T {
	return unsafe { nil }
}

// ── Interface Upcast Wrappers ──
//
// V requires explicit unsafe casts to convert concrete pointer types to
// interface types, even when the concrete type satisfies the interface.
// These wrappers document exactly which conversions are valid and why.

// as_bean_factory upcasts a Container to its BeanFactory interface.
// Safe because Container implements BeanFactory (verified at compile time
// by the Container struct satisfying all BeanFactory methods).
pub fn as_bean_factory(c &Container) &BeanFactory {
	return unsafe { &BeanFactory(c) }
}

// as_listable_bean_factory upcasts a Container to ListableBeanFactory.
pub fn as_listable_bean_factory(c &Container) &ListableBeanFactory {
	return unsafe { &ListableBeanFactory(c) }
}

// as_hierarchical_bean_factory upcasts a Container to HierarchicalBeanFactory.
pub fn as_hierarchical_bean_factory(c &Container) &HierarchicalBeanFactory {
	return unsafe { &HierarchicalBeanFactory(c) }
}

// as_autowire_capable_bean_factory upcasts a Container to AutowireCapableBeanFactory.
pub fn as_autowire_capable_bean_factory(c &Container) &AutowireCapableBeanFactory {
	return unsafe { &AutowireCapableBeanFactory(c) }
}

// as_configurable_bean_factory upcasts a Container to ConfigurableBeanFactory.
pub fn as_configurable_bean_factory(c &Container) &ConfigurableBeanFactory {
	return unsafe { &ConfigurableBeanFactory(c) }
}

// as_bean_definition_registry upcasts a Container to BeanDefinitionRegistry.
pub fn as_bean_definition_registry(c &Container) &BeanDefinitionRegistry {
	return unsafe { &BeanDefinitionRegistry(c) }
}

// as_environment upcasts an Environment to the common interface used by ApplicationContext.
pub fn as_environment(env &Environment) &CoreEnvironment {
	return unsafe { &CoreEnvironment(env) }
}

// ── Generic Type Cast ──

// as_interface casts any concrete pointer to a compatible interface type.
// Only valid when the concrete type T implements interface I.
// The caller is responsible for ensuring type compatibility.
//
// Usage:
//   bus := as_interface[EventBus, EventBusInterface](event_bus)
pub fn as_interface[T, I]() fn (&T) &I {
	return fn (ptr &T) &I {
		return unsafe { &I(ptr) }
	}
}

// ── Core Environment Interface ──
// Lightweight interface for Environment operations used by ApplicationContext.

pub interface CoreEnvironment {
mut:
	get_active_profiles() []string
	accepts_profile(profile string) bool
}

// ── 启动期冻结值 ──

// freeze_start_moment_props 把「进程启动时刻」冻结进 Environment。
//
// 这是启动期运行时值的唯一入口，三个键在这里定义一次：
//   app.start.time —— 启动的 Unix 秒（展示用）
//   app.start.tick —— 启动的单调时钟刻度（算 uptime，不受系统时间跳变影响）
//   app.pid        —— 进程 ID
//
// 必须早于 refresh()：Bean 的 @[value] 字段在 refresh 期间绑定，读的就是
// 那一刻的属性表。晚于 refresh 写进去，Bean 只会拿到零值。
//
// 用独立函数而不是让调用方自己 set_property：属性键在「写入方」和「绑定方」
// 之间必须对齐，两处各写一遍迟早会错位。而且下游模块没法自己接收
// `&core.Environment` 参数 —— V 0.5.2 会把签名里的 Environment /
// ApplicationContext 报成 unknown type（这两个结构体引用了大量 core 内类型，
// 跨包解析签名时 checker 提前放弃）。所以留在 core 里，下游只传 ctx。
pub fn freeze_start_moment_props(mut ctx ApplicationContext, start_time i64, start_tick i64) {
	ctx.environment.set_property('app.start.time', '${start_time}')
	ctx.environment.set_property('app.start.tick', '${start_tick}')
	ctx.environment.set_property('app.pid', '${os.getpid()}')
}
