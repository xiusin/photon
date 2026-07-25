module core

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
