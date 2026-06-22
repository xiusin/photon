module core

// service_locator.v - Service Locator Pattern (Laravel Container inspired)
//
// Provides a Service Locator that can retrieve services from the IoC container
// without direct dependency on the container itself. This is useful for:
//   - Legacy code that cannot use constructor injection
//   - Accessing services from non-managed objects
//   - Testing with mock services
//
// Spring equivalent: ServiceLocatorFactoryBean (less emphasized in Spring)
// Laravel equivalent: app() / resolve() helper functions
//
// Key differences from pure DI:
//   - DI: dependencies are pushed INTO the object (Inversion of Control)
//   - Service Locator: the object PULLS dependencies from a registry
//
// Photon encourages DI via @[autowired] but provides ServiceLocator
// as a fallback for edge cases.
import sync

// ── ServiceLocator ──

// ServiceLocator provides global access to services registered in the container.
// It holds a reference to the ApplicationContext and delegates lookups.
@[heap]
pub struct ServiceLocator {
pub mut:
	context &ApplicationContext = unsafe { nil }
	mu      sync.RwMutex
	cache   map[string]voidptr // Cache of resolved singletons for fast access
}

// ── Module-Level Convenience Functions ──
// These mirror Laravel's helper functions: app(), resolve(), app('service')

// service resolves a service by type name from the given ApplicationContext.
// Laravel equivalent: app('service_name')
pub fn service_from(mut ctx ApplicationContext, type_name string) !voidptr {
	return ctx.resolve(type_name)
}

// has_service checks if a service is registered.
pub fn has_service_from(mut ctx ApplicationContext, type_name string) bool {
	return ctx.has(type_name)
}

// qualified_service resolves a service by qualifier from the given ApplicationContext.
pub fn qualified_service_from(mut ctx ApplicationContext, qualifier string) !voidptr {
	return ctx.resolve_by_qualifier(qualifier)
}

// ── Instance Methods ──

// new_service_locator creates a ServiceLocator backed by an ApplicationContext.
pub fn new_service_locator(ctx &ApplicationContext) &ServiceLocator {
	return &ServiceLocator{
		context: unsafe { ctx }
		cache:   map[string]voidptr{}
	}
}

// resolve resolves a service by type name from the underlying ApplicationContext.
pub fn (mut sl ServiceLocator) resolve(type_name string) !voidptr {
	if isnil(sl.context) {
		return error('service locator has no application context')
	}
	return sl.context.resolve(type_name)
}

// has checks if a service is registered.
pub fn (mut sl ServiceLocator) has(type_name string) bool {
	if isnil(sl.context) {
		return false
	}
	return sl.context.has(type_name)
}

// resolve_by_qualifier resolves a service by its qualifier name.
pub fn (mut sl ServiceLocator) resolve_by_qualifier(qualifier string) !voidptr {
	if isnil(sl.context) {
		return error('service locator has no application context')
	}
	return sl.context.resolve_by_qualifier(qualifier)
}

// ── Service Binding (Laravel-style) ──

// ServiceBinding represents a binding in the service container.
// Inspired by Laravel's Container::bind() and Container::singleton().
pub struct ServiceBinding {
pub:
	type_name    string
	is_singleton bool
	factory      fn () !voidptr = unsafe { nil }
	instance     voidptr        = unsafe { nil }
}

// ── BindingRegistry ──

// BindingRegistry manages service bindings for the ServiceLocator.
// This allows registering services with factory functions, similar to
// Laravel's service container binding API.
@[heap]
pub struct BindingRegistry {
pub mut:
	bindings  map[string]ServiceBinding
	instances map[string]voidptr // cached singleton instances
mut:
	mu sync.RwMutex
}

// new_binding_registry creates an empty BindingRegistry.
pub fn new_binding_registry() &BindingRegistry {
	return &BindingRegistry{
		bindings:  map[string]ServiceBinding{}
		instances: map[string]voidptr{}
	}
}

// bind registers a service binding.
// If is_singleton is true, the factory is called once and the result is cached.
pub fn (mut r BindingRegistry) bind(type_name string, factory fn () !voidptr, is_singleton bool) {
	r.mu.@lock()
	defer { r.mu.unlock() }
	r.bindings[type_name] = ServiceBinding{
		type_name:    type_name
		is_singleton: is_singleton
		factory:      factory
	}
}

// bind_instance registers a pre-created instance as a singleton.
// Laravel equivalent: Container::instance('name', $instance)
pub fn (mut r BindingRegistry) bind_instance(type_name string, instance voidptr) {
	r.mu.@lock()
	defer { r.mu.unlock() }
	r.bindings[type_name] = ServiceBinding{
		type_name:    type_name
		is_singleton: true
		instance:     instance
	}
	r.instances[type_name] = instance
}

// resolve resolves a service from the binding registry.
// Thread-safety: Uses proper write-lock for singleton creation to prevent
// the TOCTOU race condition where two goroutines could both miss the cache
// and create duplicate singleton instances.
pub fn (mut r BindingRegistry) resolve(type_name string) !voidptr {
	r.mu.rlock()
	binding := r.bindings[type_name] or {
		r.mu.runlock()
		return error('service "${type_name}" not bound')
	}
	r.mu.runlock()

	// Return cached singleton if available (fast path)
	if binding.is_singleton {
		r.mu.rlock()
		if cached := r.instances[type_name] {
			r.mu.runlock()
			return cached
		}
		r.mu.runlock()

		// Slow path: acquire write lock for singleton creation
		r.mu.@lock()
		// Double-check after acquiring write lock
		// (another thread may have created the instance while we waited)
		if cached := r.instances[type_name] {
			r.mu.unlock()
			return cached
		}

		// Create new instance under write lock
		if isnil(binding.instance) && !isnil(binding.factory) {
			instance := binding.factory() or {
				r.mu.unlock()
				return error('factory failed for "${type_name}": ${err}')
			}

			// Cache — guaranteed single creation
			r.instances[type_name] = instance
			r.mu.unlock()
			return instance
		}
		r.mu.unlock()
	}

	// Return bound instance directly
	if !isnil(binding.instance) {
		return binding.instance
	}

	// Non-singleton: create new instance each time (prototype)
	if !isnil(binding.factory) {
		instance := binding.factory() or {
			return error('factory failed for "${type_name}": ${err}')
		}
		return instance
	}

	return error('service "${type_name}" has no factory or instance')
}

// has_binding checks if a binding exists.
pub fn (mut r BindingRegistry) has_binding(type_name string) bool {
	r.mu.rlock()
	defer { r.mu.runlock() }
	return type_name in r.bindings
}

// ── Global Service Locator ──
//
// A process-wide ServiceLocator instance for convenience.
// Set once during bootstrap, used anywhere.
//
// Spring equivalent: static ApplicationContext reference
// Laravel equivalent: global app() helper

__global g_service_locator &ServiceLocator

// set_global_service_locator sets the global ServiceLocator instance.
// Should be called once during application bootstrap.
pub fn set_global_service_locator(sl &ServiceLocator) {
	g_service_locator = sl
}

// locate_service resolves a bean by type T from the global ServiceLocator.
// This is the simplest API — no context needed, just call and get your service.
//
// Spring equivalent: SpringApplicationContext.getBean(MyService.class)
// Laravel equivalent: app(MyService::class)
//
// Usage:
//   svc := core.locate_service[UserService]()!
pub fn locate_service[T]() !&T {
	if isnil(g_service_locator) {
		return error('locate_service: global ServiceLocator not initialized / 全局服务定位器未初始化')
	}
	mut sl := g_service_locator
	instance := sl.resolve(T.name) or {
		return error('locate_service: failed to resolve ${T.name}: ${err} / 定位服务：解析 ${T.name} 失败: ${err}')
	}
	return unsafe { &T(instance) }
}

// locate_service_by_name resolves a bean by name from the global ServiceLocator.
pub fn locate_service_by_name(name string) !voidptr {
	if isnil(g_service_locator) {
		return error('locate_service_by_name: global ServiceLocator not initialized / 全局服务定位器未初始化')
	}
	mut sl := g_service_locator
	return sl.resolve(name)
}

// has_global_service checks if a bean exists in the global ServiceLocator.
pub fn has_global_service(name string) bool {
	if isnil(g_service_locator) {
		return false
	}
	mut sl := g_service_locator
	return sl.has(name)
}
