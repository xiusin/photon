module core

// factory_bean.v - FactoryBean (Spring FactoryBean inspired)
//
// Provides a way to delegate bean creation to a factory object.
// This is essential for creating complex objects that need
// programmatic construction rather than simple instantiation.
//
// Spring equivalent: org.springframework.beans.factory.FactoryBean
// Laravel equivalent: Binding with closure (singleton / bind)
//
// Usage:
//   @[component]
//   pub struct DatabaseConnectionFactory {
//       @[autowired]
//       config &DatabaseConfig
//   }
//
//   pub fn (f &DatabaseConnectionFactory) create() !voidptr {
//       return unsafe { new_connection(f.config) }
//   }
//
// The container will call create() instead of directly instantiating the bean.

import sync

// ── FactoryBean ──

// FactoryBean is the interface for beans that produce other objects.
// When a FactoryBean is registered, the container will use its create()
// method to produce the actual bean instance.
//
// This is the Photon equivalent of Spring's FactoryBean<T>.
pub interface FactoryBean {
	// create produces a new bean instance.
	// The returned voidptr is the actual object to be stored in the container.
	create() !voidptr

	// bean_type returns the type name of the object this factory produces.
	// This allows the container to register the factory's output by type.
	bean_type() string

	// is_singleton returns true if the factory produces a singleton.
	// Default: true (most factories produce singletons).
	is_singleton() bool
}

// ── FactoryBeanDefinition ──

// FactoryBeanDefinition wraps a FactoryBean with its metadata.
// Used internally by the container to track factory beans.
pub struct FactoryBeanDefinition {
pub:
	factory_type_name string // the FactoryBean struct name
	output_type_name  string // the type this factory produces
	is_singleton_     bool   // whether the output is a singleton
	factory          &FactoryBean = unsafe { nil }
}

// new_factory_bean_definition creates a FactoryBeanDefinition.
pub fn new_factory_bean_definition(factory_type_name string, factory &FactoryBean) FactoryBeanDefinition {
	return FactoryBeanDefinition{
		factory_type_name: factory_type_name
		output_type_name: factory.bean_type()
		is_singleton_: factory.is_singleton()
		factory: unsafe { factory }
	}
}

// ── FactoryBeanRegistry ──

// FactoryBeanRegistry manages FactoryBean instances and their products.
// It is embedded in the Container for transparent factory bean support.
@[heap]
pub struct FactoryBeanRegistry {
pub mut:
	factories       map[string]FactoryBeanDefinition // output_type → definition
	factory_outputs map[string]voidptr               // output_type → cached output
mut:
	mu sync.RwMutex
}

// new_factory_bean_registry creates an empty FactoryBeanRegistry.
pub fn new_factory_bean_registry() &FactoryBeanRegistry {
	return &FactoryBeanRegistry{
		factories: map[string]FactoryBeanDefinition{}
		factory_outputs: map[string]voidptr{}
	}
}

// register_factory registers a FactoryBean.
pub fn (mut r FactoryBeanRegistry) register_factory(def FactoryBeanDefinition) {
	r.mu.@lock()
	defer { r.mu.unlock() }
	r.factories[def.output_type_name] = def
}

// has_factory checks if a factory exists for the given output type.
pub fn (mut r FactoryBeanRegistry) has_factory(output_type_name string) bool {
	r.mu.rlock()
	defer { r.mu.runlock() }
	return output_type_name in r.factories
}

// get_from_factory resolves a bean from a factory.
// For singleton factories, the output is cached after first creation.
// For prototype factories, a new instance is created each time.
//
// Thread-safety: Uses proper write-lock for singleton creation to prevent
// the TOCTOU race condition where two goroutines could both miss the cache
// and create duplicate singleton instances.
pub fn (mut r FactoryBeanRegistry) get_from_factory(output_type_name string) !voidptr {
	r.mu.rlock()
	def := r.factories[output_type_name] or {
		r.mu.runlock()
		return error('no factory for type "${output_type_name}"')
	}
	r.mu.runlock()

	// Check singleton cache (fast path — read lock only)
	if def.is_singleton_ {
		r.mu.rlock()
		if cached := r.factory_outputs[output_type_name] {
			r.mu.runlock()
			return cached
		}
		r.mu.runlock()

		// Slow path: acquire write lock for singleton creation
		r.mu.@lock()
		// Double-check after acquiring write lock
		// (another thread may have created the instance while we waited)
		if cached := r.factory_outputs[output_type_name] {
			r.mu.unlock()
			return cached
		}

		// Create new instance under write lock
		if isnil(def.factory) {
			r.mu.unlock()
			return error('factory is nil for type "${output_type_name}"')
		}
		instance := def.factory.create() or {
			r.mu.unlock()
			return error('factory create failed for "${output_type_name}": ${err}')
		}

		// Cache under write lock — guaranteed single creation
		r.factory_outputs[output_type_name] = instance
		r.mu.unlock()
		return instance
	}

	// Prototype: no caching needed
	if isnil(def.factory) {
		return error('factory is nil for type "${output_type_name}"')
	}
	instance := def.factory.create() or {
		return error('factory create failed for "${output_type_name}": ${err}')
	}

	return instance
}

// factory_count returns the number of registered factories.
pub fn (mut r FactoryBeanRegistry) factory_count() int {
	r.mu.rlock()
	defer { r.mu.runlock() }
	return r.factories.len
}
