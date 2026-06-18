module core

// di_enhanced.v - Enhanced Dependency Injection (Spring DI + Laravel Container inspired)
//
// Extends the basic DI system with advanced features:
//   - Method injection / Setter injection (Spring @Autowired on methods)
//   - Optional injection (Spring @Autowired(required=false))
//   - Collection injection (Spring List/Map injection, Laravel tagged bindings)
//   - Deferred/Lazy provider (Spring ObjectProvider, Laravel contextual binding)
//   - Bean type indexing for type-based lookups
//
// Spring equivalents:
//   - ObjectProvider<T>          → DeferredProvider
//   - @Autowired(required=false) → Dependency.is_required = false
//   - List<Interface> injection  → CollectionInjection
//   - @Qualifier refinement      → enhanced qualifier matching
//
// Laravel equivalents:
//   - Container::tagged()        → CollectionInjection
//   - Container::when()          → contextual binding hints
//   - Container::build()         → DeferredProvider

import sync

// ── Method Injection ──

// MethodInjection describes a method that should be called after
// field injection to inject additional dependencies.
//
// Spring equivalent: @Autowired on setter methods
// Laravel equivalent: setter injection in Service Providers
//
// Usage (comptime-generated):
//   method_injections: [
//     MethodInjection{
//       method_name: 'set_cache'
//       params: [Dependency{type_name: 'CacheService'}]
//     }
//   ]
pub struct MethodInjection {
pub:
	method_name string       // method to call
	params      []Dependency // parameters to inject
}

// ── Collection Injection ──

// CollectionInjection describes an @[autowired] field that should
// receive ALL beans of a given type (interface/trait), not just one.
//
// Spring equivalent: @Autowired List<CacheService> — injects all beans
//   implementing the interface.
// Laravel equivalent: Container::tagged('cache') — tagged bindings.
//
// Usage:
//   @[autowired]
//   handlers &[]EventHandler  // inject all EventHandler beans
pub struct CollectionInjection {
pub:
	field_name    string   // V struct field name
	interface_name string  // interface/trait type to match
	tag           string   // optional tag filter (Laravel tagged binding)
}

// ── DeferredProvider ──

// DeferredProvider provides lazy resolution of a bean — the bean is
// not actually resolved until the first call to get().
// This is the Photon equivalent of Spring's ObjectProvider<T> and
// Laravel's lazy service binding.
//
// Spring equivalent: org.springframework.beans.factory.ObjectProvider<T>
// Laravel equivalent: Container::lazy() / deferred service provider
//
// Usage:
//   @[autowired]
//   cache_provider DeferredProvider  // not resolved until .get() is called
//
//   // Later:
//   cache := cache_provider.get() or { panic('no cache') }
@[heap]
pub struct DeferredProvider {
pub mut:
	type_name string
	mutable  bool // if true, returns a new instance each time (prototype-like)
	container  &Container = unsafe { nil}
	resolved   bool
	instance   voidptr = unsafe { nil}
mut:
	mu sync.RwMutex
}

// new_deferred_provider creates a DeferredProvider for the given type.
pub fn new_deferred_provider(type_name string) &DeferredProvider {
	return &DeferredProvider{
		type_name: type_name
		resolved: false
	}
}

// get resolves the bean on first access and caches it (unless mutable).
// Spring equivalent: ObjectProvider.getObject()
// Laravel equivalent: Container::make() (lazy)
pub fn (mut dp DeferredProvider) get() !voidptr {
	if dp.resolved && !dp.mutable {
		dp.mu.rlock()
		result := dp.instance
		dp.mu.runlock()
		return result
	}

	if isnil(dp.container) {
		return error('deferred provider has no container reference')
	}

	instance := dp.container.resolve(dp.type_name) or {
		return error('deferred provider: failed to resolve "${dp.type_name}": ${err}')
	}

	if !dp.mutable {
		dp.mu.@lock()
		dp.instance = instance
		dp.resolved = true
		dp.mu.unlock()
	}

	return instance
}

// get_or resolves the bean or returns a default value.
// Spring equivalent: ObjectProvider.getIfAvailable()
pub fn (mut dp DeferredProvider) get_or(default_val voidptr) voidptr {
	result := dp.get() or { return default_val }
	return result
}

// is_resolved returns whether the bean has been resolved at least once.
pub fn (mut dp DeferredProvider) is_resolved() bool {
	dp.mu.rlock()
	defer { dp.mu.runlock()}
	return dp.resolved
}

// set_container sets the container reference for deferred resolution.
// Called by the ApplicationContext during bean wiring.
pub fn (mut dp DeferredProvider) set_container(c &Container) {
	dp.mu.@lock()
	defer { dp.mu.unlock()}
	dp.container = unsafe { c}
}

// ── Bean Type Index ──

// BeanTypeIndex provides efficient type-based bean lookups.
// This enables Spring-style "find all beans of type T" queries,
// which is essential for collection injection and plugin architectures.
//
// Spring equivalent: ListableBeanFactory.getBeanNamesForType()
// Laravel equivalent: Container::tagged()
@[heap]
pub struct BeanTypeIndex {
pub mut:
	// Maps interface/trait name → list of bean type_names that implement it
	type_to_beans map[string][]string
	// Maps tag name → list of bean type_names with that tag
	tag_to_beans  map[string][]string
mut:
	mu sync.RwMutex
}

// new_bean_type_index creates an empty BeanTypeIndex.
pub fn new_bean_type_index() &BeanTypeIndex {
	return &BeanTypeIndex{
		type_to_beans: map[string][]string{}
		tag_to_beans: map[string][]string{}
	}
}

// register_interface maps a bean type to an interface it implements.
// Spring equivalent: bean implements interface → autowire candidate
pub fn (mut idx BeanTypeIndex) register_interface(bean_type_name string, interface_name string) {
	idx.mu.@lock()
	defer { idx.mu.unlock()}
	mut beans := idx.type_to_beans[interface_name] or { []string{} }
	if bean_type_name !in beans {
		beans << bean_type_name
	}
	idx.type_to_beans[interface_name] = beans
}

// register_tag maps a bean type to a tag.
// Laravel equivalent: Container::tag()
pub fn (mut idx BeanTypeIndex) register_tag(bean_type_name string, tag string) {
	idx.mu.@lock()
	defer { idx.mu.unlock()}
	mut beans := idx.tag_to_beans[tag] or { []string{} }
	if bean_type_name !in beans {
		beans << bean_type_name
	}
	idx.tag_to_beans[tag] = beans
}

// beans_for_interface returns all bean names that implement the given interface.
// Spring equivalent: ListableBeanFactory.getBeanNamesForType(MyInterface.class)
pub fn (mut idx BeanTypeIndex) beans_for_interface(interface_name string) []string {
	idx.mu.rlock()
	defer { idx.mu.runlock()}
	beans := idx.type_to_beans[interface_name] or { []string{} }
	return beans.clone()
}

// beans_for_tag returns all bean names with the given tag.
// Laravel equivalent: Container::tagged('cache')
pub fn (mut idx BeanTypeIndex) beans_for_tag(tag string) []string {
	idx.mu.rlock()
	defer { idx.mu.runlock()}
	beans := idx.tag_to_beans[tag] or { []string{} }
	return beans.clone()
}

// has_interface checks if any bean implements the given interface.
pub fn (mut idx BeanTypeIndex) has_interface(interface_name string) bool {
	idx.mu.rlock()
	defer { idx.mu.runlock()}
	beans := idx.type_to_beans[interface_name] or { []string{} }
	return beans.len > 0
}

// has_tag checks if any bean has the given tag.
pub fn (mut idx BeanTypeIndex) has_tag(tag string) bool {
	idx.mu.rlock()
	defer { idx.mu.runlock()}
	beans := idx.tag_to_beans[tag] or { []string{} }
	return beans.len > 0
}

// unregister_interface removes a bean from the interface index.
// Used by remove_definition to clean up stale index entries.
pub fn (mut idx BeanTypeIndex) unregister_interface(bean_type_name string, interface_name string) {
	idx.mu.@lock()
	defer { idx.mu.unlock() }
	mut beans := idx.type_to_beans[interface_name] or { []string{} }
	mut new_beans := []string{}
	for b in beans {
		if b != bean_type_name {
			new_beans << b
		}
	}
	if new_beans.len == 0 {
		idx.type_to_beans.delete(interface_name)
	} else {
		idx.type_to_beans[interface_name] = new_beans
	}
}

// unregister_tag removes a bean from the tag index.
// Used by remove_definition to clean up stale index entries.
pub fn (mut idx BeanTypeIndex) unregister_tag(bean_type_name string, tag string) {
	idx.mu.@lock()
	defer { idx.mu.unlock() }
	mut beans := idx.tag_to_beans[tag] or { []string{} }
	mut new_beans := []string{}
	for b in beans {
		if b != bean_type_name {
			new_beans << b
		}
	}
	if new_beans.len == 0 {
		idx.tag_to_beans.delete(tag)
	} else {
		idx.tag_to_beans[tag] = new_beans
	}
}

// interface_count returns the number of registered interfaces.
pub fn (mut idx BeanTypeIndex) interface_count() int {
	idx.mu.rlock()
	defer { idx.mu.runlock()}
	return idx.type_to_beans.len
}

// tag_count returns the number of registered tags.
pub fn (mut idx BeanTypeIndex) tag_count() int {
	idx.mu.rlock()
	defer { idx.mu.runlock()}
	return idx.tag_to_beans.len
}

// rebuild rebuilds the index from all bean definitions in a container.
// This is called after all beans are registered, before refresh.
// Rebuilds BOTH the interface index and the tag index.
pub fn (mut idx BeanTypeIndex) rebuild(mut c Container) {
	idx.mu.@lock()
	defer { idx.mu.unlock()}

	// Clear existing
	idx.type_to_beans = map[string][]string{}
	idx.tag_to_beans = map[string][]string{}

	// Rebuild from container definitions
	c.mu.rlock()
	for _, def in c.definitions {
		// Rebuild interface index
		for iface in def.interfaces {
			mut beans := idx.type_to_beans[iface] or { []string{} }
			if def.type_name !in beans {
				beans << def.type_name
			}
			idx.type_to_beans[iface] = beans
		}
		// Rebuild tag index
		for tag in def.tags {
			mut beans := idx.tag_to_beans[tag] or { []string{} }
			if def.type_name !in beans {
				beans << def.type_name
			}
			idx.tag_to_beans[tag] = beans
		}
	}
	c.mu.runlock()
}

// full_rebuild rebuilds the index from both the container's definitions
// and the parent container's definitions (if any).
// This ensures hierarchical context lookups include all ancestor beans.
//
// Spring equivalent: ListableBeanFactory.getBeanNamesForType() with parent fallback
pub fn (mut idx BeanTypeIndex) full_rebuild(mut c Container) {
	// First, rebuild from this container
	idx.rebuild(mut c)

	// Then, merge parent container's definitions if present
	if !isnil(c.parent) {
		idx.mu.@lock()
		mut parent := unsafe { c.parent }
		parent.mu.rlock()
		for _, def in parent.definitions {
			for iface in def.interfaces {
				mut beans := idx.type_to_beans[iface] or { []string{} }
				if def.type_name !in beans {
					beans << def.type_name
				}
				idx.type_to_beans[iface] = beans
			}
			for tag in def.tags {
				mut beans := idx.tag_to_beans[tag] or { []string{} }
				if def.type_name !in beans {
					beans << def.type_name
				}
				idx.tag_to_beans[tag] = beans
			}
		}
		parent.mu.runlock()
		idx.mu.unlock()
	}
}
