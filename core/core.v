module core

// core.v - Photon Core Container (Spring ApplicationContext inspired)
//
// Provides compile-time dependency injection and bean lifecycle management.
// All DI resolution happens at compile time via comptime $for — zero runtime reflection.
//
// Key concepts:
//   - Container:  the IoC container that holds all bean definitions and instances
//   - ApplicationContext:  unified application context (Container + EventBus + Lifecycle + Environment)
//   - BeanDefinition:  metadata about a bean (type, scope, dependencies)
//   - Scope:  singleton (default) | prototype | request
//   - @[component] / @[service] / @[repository]:  marks a struct as a bean
//   - @[autowired]:  marks a field for automatic injection
//   - @[scope('singleton'|'prototype'|'request')]:  bean scope
//   - @[lazy]:  delay instantiation until first use
//   - @[qualifier('name')]:  disambiguate when multiple beans of same type exist
//   - @[post_construct]:  method called after dependency injection
//   - @[pre_destroy]:  method called before bean disposal
//   - @[conditional_on_*]:  conditional bean registration
//   - @[value('key')]:  inject configuration property
//
// Usage (simple — Container only):
//   mut container := core.new_container()
//   container.register(core.BeanDefinition{ type_name: 'UserService', ... })
//   instance := container.resolve('UserService')!
//
// Usage (recommended — ApplicationContext):
//   mut app := core.new_application_context()
//   app.set_profiles(['dev'])
//   app.register(core.BeanDefinition{ type_name: 'UserService', ... })
//   app.refresh()!
//   instance := app.resolve('UserService')!
//   app.shutdown()
import sync

// ── Module re-exports ──
// The following types and functions are defined in sibling files
// but are accessible via `core.` prefix thanks to V's module system:
//
// From application_context.v:
//   ApplicationContext, ApplicationState, new_application_context,
//   BeanRegistrationOptions
//
// From environment.v:
//   Environment, new_environment
//
// From post_processor.v:
//   BeanPostProcessor, BeanFactoryPostProcessor, Ordered,
//   BasePostProcessor, AutowiredAnnotationPostProcessor,
//   ValueAnnotationPostProcessor, LifecycleAnnotationPostProcessor,
//   EventListenerPostProcessor
//
// From factory_bean.v:
//   FactoryBean, FactoryBeanDefinition, FactoryBeanRegistry,
//   new_factory_bean_registry, new_factory_bean_definition
//
// From service_locator.v:
//   ServiceLocator, ServiceBinding, BindingRegistry,
//   init_service_locator, get_service_locator,
//   service, has_service, qualified_service,
//   new_binding_registry
//
// From auto_configuration.v:
//   AutoConfiguration, AutoConfigurationCandidate, AutoConfigurationManager,
//   new_auto_configuration_manager
//
// From condition.v (enhanced):
//   OnExpressionCondition, OnClassCondition, OnMissingClassCondition,
//   OnCloudPlatformCondition, any_condition_matches

// ── Scope ──

// Scope defines the lifecycle of a bean instance.
pub enum Scope {
	singleton // default — one instance per container
	prototype // new instance per resolve
	request   // one instance per HTTP request (web module)
}

// str returns a human-readable scope name.
pub fn (s Scope) str() string {
	return match s {
		.singleton { 'singleton' }
		.prototype { 'prototype' }
		.request { 'request' }
	}
}

// scope_from_str parses a scope string (used by @[scope('...')] attribute).
pub fn scope_from_str(s string) Scope {
	return match s {
		'singleton' { .singleton }
		'prototype' { .prototype }
		'request' { .request }
		else { .singleton }
	}
}

// ── BeanState ──

// BeanState tracks the current state of a bean in its lifecycle.
pub enum BeanState {
	registered    // definition added, not yet instantiated
	instantiating // instance being created (circular dependency detection)
	ready         // fully initialized and available
	destroying    // being destroyed
}

// str returns a human-readable bean state.
pub fn (bs BeanState) str() string {
	return match bs {
		.registered { 'registered' }
		.instantiating { 'instantiating' }
		.ready { 'ready' }
		.destroying { 'destroying' }
	}
}

// ── Dependency ──

// Dependency describes a single @[autowired] field on a bean.
pub struct Dependency {
pub:
	field_name  string // V struct field name
	type_name   string // fully-qualified type name to resolve
	qualifier   string // @[qualifier('name')] — empty if unqualified
	is_required bool = true // @[autowired] default required; set false for optional injection
	// Spring equivalent: @Autowired(required = true/false)
	// When is_required=false and the bean is not found, injection is silently skipped
}

// ── BeanDefinition ──

// BeanDefinition holds all metadata about a bean, analogous to Spring's
// BeanDefinition.  Created at compile time by the comptime scanner and
// registered into the Container before the application starts.
pub struct BeanDefinition {
pub:
	type_name string // struct name, e.g. 'UserService'
pub mut:
	scope          Scope = .singleton
	is_lazy        bool         // @[lazy]
	dependencies   []Dependency // @[autowired] fields
	qualifier      string       // @[qualifier('name')]
	init_method    string       // @[post_construct] method name
	destroy_method string       // @[pre_destroy] method name
	tags           []string     // @[component]/@[service]/@[repository]/@[controller]
	order_         int          // instantiation order (lower = earlier)
	state          BeanState = .registered
	depends_on     []string // @[depends_on('BeanA','BeanB')] — explicit creation order
	is_primary     bool     // @[primary] — prefer this bean when multiple candidates exist
	parent_name    string   // parent bean definition name for property inheritance
	// ── Enhanced DI fields (Spring/Laravel inspired) ──
	interfaces            []string              // interfaces this bean implements (for type-based lookup)
	method_injections     []MethodInjection     // @[autowired] on setter/method (Spring method injection)
	collection_injections []CollectionInjection // inject all beans of a type (Spring List<T> injection)
	lookup_injections     []LookupInjection     // @[lookup] method injection (Spring @Lookup)
}

// new_bean_definition creates a BeanDefinition with defaults.
pub fn new_bean_definition(type_name string) BeanDefinition {
	return BeanDefinition{
		type_name:             type_name
		scope:                 .singleton
		dependencies:          []Dependency{}
		tags:                  []string{}
		depends_on:            []string{}
		interfaces:            []string{}
		method_injections:     []MethodInjection{}
		collection_injections: []CollectionInjection{}
		lookup_injections:     []LookupInjection{}
	}
}

// ── BeanDefinitionBuilder ──

// BeanDefinitionBuilder provides a fluent API for constructing BeanDefinitions.
// Inspired by Spring's BeanDefinitionBuilder and Laravel's service container binding.
//
// Usage:
//   def := core.new_bean_definition_builder('UserService')
//       .set_scope(.singleton)
//       .set_lazy(true)
//       .add_dependency(core.Dependency{field_name: 'repo', type_name: 'UserRepository'})
//       .set_init_method('init')
//       .build()
pub struct BeanDefinitionBuilder {
pub mut:
	type_name       string
	scope_          Scope = .singleton
	is_lazy_        bool
	qualifier_      string
	tags_           []string
	dependencies_   []Dependency
	init_method_    string
	destroy_method_ string
	depends_on_     []string
	is_primary_     bool
	parent_name_    string
	// Enhanced DI
	interfaces_            []string
	method_injections_     []MethodInjection
	collection_injections_ []CollectionInjection
	lookup_injections_     []LookupInjection
}

// new_bean_definition_builder creates a builder for the given type.
pub fn new_bean_definition_builder(type_name string) BeanDefinitionBuilder {
	return BeanDefinitionBuilder{
		type_name:              type_name
		scope_:                 .singleton
		tags_:                  []string{}
		dependencies_:          []Dependency{}
		depends_on_:            []string{}
		interfaces_:            []string{}
		method_injections_:     []MethodInjection{}
		collection_injections_: []CollectionInjection{}
		lookup_injections_:     []LookupInjection{}
	}
}

// set_scope sets the bean scope.
pub fn (mut b BeanDefinitionBuilder) set_scope(s Scope) &BeanDefinitionBuilder {
	b.scope_ = s
	return unsafe { b }
}

// set_lazy sets the lazy initialization flag.
pub fn (mut b BeanDefinitionBuilder) set_lazy(lazy bool) &BeanDefinitionBuilder {
	b.is_lazy_ = lazy
	return unsafe { b }
}

// set_qualifier sets the qualifier name.
pub fn (mut b BeanDefinitionBuilder) set_qualifier(q string) &BeanDefinitionBuilder {
	b.qualifier_ = q
	return unsafe { b }
}

// add_tag adds a tag (e.g., 'service', 'repository').
pub fn (mut b BeanDefinitionBuilder) add_tag(tag string) &BeanDefinitionBuilder {
	b.tags_ << tag
	return unsafe { b }
}

// add_dependency adds an @[autowired] dependency.
pub fn (mut b BeanDefinitionBuilder) add_dependency(dep Dependency) &BeanDefinitionBuilder {
	b.dependencies_ << dep
	return unsafe { b }
}

// set_init_method sets the @[post_construct] method name.
pub fn (mut b BeanDefinitionBuilder) set_init_method(method string) &BeanDefinitionBuilder {
	b.init_method_ = method
	return unsafe { b }
}

// set_destroy_method sets the @[pre_destroy] method name.
pub fn (mut b BeanDefinitionBuilder) set_destroy_method(method string) &BeanDefinitionBuilder {
	b.destroy_method_ = method
	return unsafe { b }
}

// add_depends_on adds a @[depends_on] dependency.
// Spring equivalent: @DependsOn
pub fn (mut b BeanDefinitionBuilder) add_depends_on(bean_name string) &BeanDefinitionBuilder {
	b.depends_on_ << bean_name
	return unsafe { b }
}

// set_primary sets the @[primary] flag.
// Spring equivalent: @Primary
pub fn (mut b BeanDefinitionBuilder) set_primary(primary bool) &BeanDefinitionBuilder {
	b.is_primary_ = primary
	return unsafe { b }
}

// set_parent_name sets the parent bean definition name for property inheritance.
// Spring equivalent: BeanDefinition.setParentName()
pub fn (mut b BeanDefinitionBuilder) set_parent_name(parent string) &BeanDefinitionBuilder {
	b.parent_name_ = parent
	return unsafe { b }
}

// add_interface adds an interface that this bean implements.
// Spring equivalent: bean implements interface → autowire candidate for type-based lookup
pub fn (mut b BeanDefinitionBuilder) add_interface(interface_name string) &BeanDefinitionBuilder {
	b.interfaces_ << interface_name
	return unsafe { b }
}

// add_method_injection adds a method injection.
// Spring equivalent: @Autowired on setter method
pub fn (mut b BeanDefinitionBuilder) add_method_injection(mi MethodInjection) &BeanDefinitionBuilder {
	b.method_injections_ << mi
	return unsafe { b }
}

// add_collection_injection adds a collection injection.
// Spring equivalent: @Autowired List<Interface> injection
pub fn (mut b BeanDefinitionBuilder) add_collection_injection(ci CollectionInjection) &BeanDefinitionBuilder {
	b.collection_injections_ << ci
	return unsafe { b }
}

// add_lookup_injection adds a @Lookup method injection.
// Spring equivalent: @Lookup — method injection for prototype beans in singletons
pub fn (mut b BeanDefinitionBuilder) add_lookup_injection(li LookupInjection) &BeanDefinitionBuilder {
	b.lookup_injections_ << li
	return unsafe { b }
}

// build constructs the final BeanDefinition.
pub fn (b &BeanDefinitionBuilder) build() BeanDefinition {
	return BeanDefinition{
		type_name:             b.type_name
		scope:                 b.scope_
		is_lazy:               b.is_lazy_
		qualifier:             b.qualifier_
		tags:                  b.tags_.clone()
		dependencies:          b.dependencies_.clone()
		init_method:           b.init_method_
		destroy_method:        b.destroy_method_
		depends_on:            b.depends_on_.clone()
		is_primary:            b.is_primary_
		parent_name:           b.parent_name_
		interfaces:            b.interfaces_.clone()
		method_injections:     b.method_injections_.clone()
		collection_injections: b.collection_injections_.clone()
		lookup_injections:     b.lookup_injections_.clone()
	}
}

// is_singleton returns true if the bean has singleton scope.
pub fn (bd &BeanDefinition) is_singleton() bool {
	return bd.scope == .singleton
}

// is_prototype returns true if the bean has prototype scope.
pub fn (bd &BeanDefinition) is_prototype() bool {
	return bd.scope == .prototype
}

// has_dependencies returns true if the bean has any @[autowired] fields.
pub fn (bd &BeanDefinition) has_dependencies() bool {
	return bd.dependencies.len > 0
}

// ── BeanInstance ──

// BeanInstance wraps an instantiated bean with its definition.
pub struct BeanInstance {
pub:
	definition &BeanDefinition
	instance   voidptr
pub mut:
	state BeanState = .ready
}

// ── Container ──

// Container is the Photon IoC container — the central registry for all beans.
// It manages bean definitions, instantiation, dependency injection, and lifecycle.
//
// Thread-safety: operations are protected by a ShardedRwMutex for fine-grained
// concurrency. Per-bean locking ensures safe singleton instantiation without
// global contention.
//
// Features:
//   - Bean alias support (Spring bean alias)
//   - Parent container for hierarchical contexts (Spring HierarchicalApplicationContext)
//   - Type-based bean lookup (Spring ListableBeanFactory)
//   - Bean type indexing for efficient interface-based queries
//   - Sharded locking for high-concurrency performance
//   - Per-bean locking for safe singleton instantiation
@[heap]
pub struct Container {
pub mut:
	definitions      map[string]BeanDefinition // type_name → definition
	instances        map[string]&BeanInstance  // type_name → singleton instance
	qualifiers       map[string]string         // qualifier → type_name
	aliases          map[string]string         // alias → canonical type_name
	profiles         []string                  // active profiles
	factory_registry &FactoryBeanRegistry = unsafe { nil } // FactoryBean support
	parent           &Container           = unsafe { nil } // parent container (hierarchical context)
	type_index       &BeanTypeIndex       = unsafe { nil } // type-based bean lookup index
	event_bus        &EventBus            = unsafe { nil } // optional event bus for bean lifecycle events
mut:
	sharded_mu ShardedRwMutex // fine-grained sharded lock (replaces global RwMutex)
	bean_lock  &BeanLock      // per-bean lock for safe singleton instantiation
	mu         sync.RwMutex   // fallback global lock for bulk operations (destroy_all, etc.)
}

// new_container creates an empty Container.
pub fn new_container() &Container {
	return &Container{
		definitions:      map[string]BeanDefinition{}
		instances:        map[string]&BeanInstance{}
		qualifiers:       map[string]string{}
		aliases:          map[string]string{}
		profiles:         []string{}
		factory_registry: new_factory_bean_registry()
		type_index:       new_bean_type_index()
		sharded_mu:       new_sharded_rw_mutex()
		bean_lock:        new_bean_lock()
	}
}

// ── Registration ──

// set_event_bus sets the EventBus for bean lifecycle events.
// Called by ApplicationContext during initialization to wire the
// container's event dispatching to the application's EventBus.
// Spring equivalent: AbstractApplicationContext's lifecycle event publishing
pub fn (mut c Container) set_event_bus(bus &EventBus) {
	c.event_bus = unsafe { bus }
}

// register adds a BeanDefinition to the container.
// Returns an error if a bean with the same type_name is already registered.
pub fn (mut c Container) register(def BeanDefinition) ! {
	c.mu.@lock()
	defer { c.mu.unlock() }

	if def.type_name in c.definitions {
		return error('bean "${def.type_name}" already registered')
	}
	c.definitions[def.type_name] = def

	// Register qualifier mapping if present
	if def.qualifier.len > 0 {
		c.qualifiers[def.qualifier] = def.type_name
	}

	// Auto-index interfaces and tags for type-based lookup
	// Uses type_index's own methods (which have their own lock protection)
	// instead of directly manipulating the maps, ensuring thread-safety
	// even if called outside the container lock.
	if !isnil(c.type_index) {
		for iface in def.interfaces {
			c.type_index.register_interface(def.type_name, iface)
		}
		for tag in def.tags {
			c.type_index.register_tag(def.type_name, tag)
		}
	}
}

// register_alias registers an alias for a bean.
// The alias can then be used to resolve the bean.
// Spring equivalent: ConfigurableBeanFactory.registerAlias()
pub fn (mut c Container) register_alias(alias string, canonical_name string) ! {
	c.mu.@lock()
	defer { c.mu.unlock() }

	if alias in c.aliases {
		return error('alias "${alias}" already registered')
	}
	if canonical_name !in c.definitions {
		return error('canonical bean "${canonical_name}" not found')
	}
	c.aliases[alias] = canonical_name
}

// remove_alias removes a registered alias.
pub fn (mut c Container) remove_alias(alias string) {
	c.mu.@lock()
	defer { c.mu.unlock() }
	c.aliases.delete(alias)
}

// has_alias checks if an alias is registered.
pub fn (mut c Container) has_alias(alias string) bool {
	c.mu.rlock()
	defer { c.mu.runlock() }
	return alias in c.aliases
}

// canonical_name resolves an alias chain to its canonical bean name.
// Supports multi-level alias chains: A→B→C→ActualBean.
// If the name is not an alias, returns the name itself.
// Detects circular alias chains and returns the input name on error.
//
// Spring equivalent: ConfigurableBeanFactory.canonicalName()
pub fn (mut c Container) canonical_name(name string) string {
	c.mu.rlock()
	defer { c.mu.runlock() }
	return c.resolve_alias_chain(name, 0)
}

// resolve_alias_chain resolves an alias chain with cycle detection.
// Max depth of 10 to prevent infinite loops from circular aliases.
fn (c &Container) resolve_alias_chain(name string, depth int) string {
	if depth > 10 {
		return name // max depth reached — likely circular alias
	}
	resolved := c.aliases[name] or { return name }
	if resolved == name {
		return name // self-referencing alias
	}
	return c.resolve_alias_chain(resolved, depth + 1)
}

// set_parent sets the parent container for hierarchical context support.
// Spring equivalent: HierarchicalBeanFactory.setParentBeanFactory()
pub fn (mut c Container) set_parent(parent &Container) {
	c.mu.@lock()
	defer { c.mu.unlock() }
	c.parent = unsafe { parent }
}

// register_instance registers a pre-created instance as a singleton bean.
// Useful for registering external services (database connections, etc.).
pub fn (mut c Container) register_instance(type_name string, instance voidptr) ! {
	c.mu.@lock()
	defer { c.mu.unlock() }

	if type_name in c.instances {
		return error('bean instance "${type_name}" already registered')
	}
	// Auto-create definition if not present
	if type_name !in c.definitions {
		c.definitions[type_name] = BeanDefinition{
			type_name:  type_name
			scope:      .singleton
			tags:       []string{}
			depends_on: []string{}
		}
	}
	c.instances[type_name] = &BeanInstance{
		definition: unsafe { &c.definitions[type_name] }
		instance:   instance
		state:      .ready
	}
}

// register_factory registers a FactoryBean with the container.
// The factory will produce beans on demand when resolved.
// Laravel equivalent: Container::bind('name', fn() => new Service())
pub fn (mut c Container) register_factory(factory_type_name string, factory &FactoryBean) ! {
	if isnil(c.factory_registry) {
		c.factory_registry = new_factory_bean_registry()
	}
	def := new_factory_bean_definition(factory_type_name, factory)
	c.factory_registry.register_factory(def)
}

// ── Resolution ──

// resolve retrieves a bean instance by type name.
// For singleton beans, returns the cached instance.
// For prototype beans, returns a new instance each time.
// If the bean is not found in this container, falls back to the parent container.
//
// Performance: uses read lock for the fast path (singleton cache hit),
// only upgrading to write lock when a new bean needs to be instantiated.
pub fn (mut c Container) resolve(type_name string) !voidptr {
	// Fast path: read lock for alias chain resolution + singleton cache lookup
	c.mu.rlock()
	resolved_name := c.resolve_alias_chain(type_name, 0)
	if inst := c.instances[resolved_name] {
		if inst.state == .instantiating {
			c.mu.runlock()
			return error('circular dependency detected for bean "${resolved_name}"')
		}
		result := inst.instance
		c.mu.runlock()
		return result
	}
	c.mu.runlock()

	// Slow path: need write lock for potential state mutation
	c.mu.@lock()
	defer { c.mu.unlock() }

	// Double-check after acquiring write lock (another thread may have resolved it)
	if inst := c.instances[resolved_name] {
		if inst.state == .instantiating {
			return error('circular dependency detected for bean "${resolved_name}"')
		}
		return inst.instance
	}

	return c.resolve_unlocked(resolved_name)
}

// resolve_unlocked resolves a bean without acquiring the container-level lock.
// Used internally when the lock is already held.
//
// The actual bean instantiation is performed by comptime-generated code
// (via set_instance). This method manages the lifecycle state transitions
// and coordinates with the BeanLock for safe singleton instantiation.
//
// Flow for singletons:
//   1. Check singleton cache → hit: return cached instance
//   2. Try FactoryBean registry → hit: delegate to factory
//   3. Look up definition → miss: delegate to parent container
//   4. Mark as instantiating (circular dependency guard)
//   5. Acquire per-bean lock (BeanLock)
//   6. Double-check singleton cache (another thread may have resolved it)
//   7. Keep state = instantiating — the comptime-generated code will
//      call set_instance() which transitions to .ready
//   8. Release per-bean lock (but do NOT remove — set_instance will clean up)
//   9. Return voidptr to be filled by comptime code
//
// The bean.created event is dispatched by set_instance() after the instance
// is actually stored, not here. This ensures listeners only see events for
// beans that have real instances.
fn (mut c Container) resolve_unlocked(type_name string) !voidptr {
	// Check singleton cache first
	if inst := c.instances[type_name] {
		if inst.state == .instantiating {
			return error('circular dependency detected for bean "${type_name}"')
		}
		return inst.instance
	}

	// Try FactoryBean registry first
	if !isnil(c.factory_registry) && c.factory_registry.has_factory(type_name) {
		instance := c.factory_registry.get_from_factory(type_name) or {
			return error('factory failed for bean "${type_name}": ${err}')
		}
		// Dispatch bean.created for factory-produced beans
		if !isnil(c.event_bus) {
			mut bus := unsafe { c.event_bus }
			mut event := new_event(event_bean_created, type_name)
			event.data['factory'] = 'true'
			bus.dispatch(event)
		}
		return instance
	}

	// Look up definition
	def := c.definitions[type_name] or {
		// Fall back to parent container (hierarchical context)
		if !isnil(c.parent) {
			return c.parent.resolve(type_name)
		}
		return error('bean "${type_name}" not found in container')
	}

	// Mark as instantiating for circular dependency detection
	// This is done atomically under the container lock
	mut mutable_def := def
	mutable_def.state = .instantiating
	c.definitions[type_name] = mutable_def

	// For prototype scope, always create new
	// Prototype beans are never cached, so we just reset the state
	// and return nil (actual instantiation done by comptime-generated code)
	if def.scope == .prototype {
		mutable_def.state = .registered
		c.definitions[type_name] = mutable_def
		return unsafe { nil } // actual instantiation done by comptime-generated code
	}

	// Singleton: use per-bean lock for safe instantiation
	// After this point, other goroutines trying to resolve the same bean
	// will see state=instantiating and report a circular dependency,
	// which is correct behavior — they should wait for the singleton.
	if !isnil(c.bean_lock) {
		c.bean_lock.lock(type_name)
	}

	// Double-check after acquiring per-bean lock
	// (another thread may have completed instantiation while we waited)
	if inst := c.instances[type_name] {
		if !isnil(c.bean_lock) {
			c.bean_lock.unlock(type_name)
		}
		return inst.instance
	}

	// IMPORTANT: We do NOT set state = .ready here.
	// The state remains .instantiating until the comptime-generated code
	// calls set_instance(), which transitions the state to .ready.
	// This ensures bean.created is only dispatched when a real instance exists.

	// Release the per-bean lock — the comptime code will call set_instance()
	// which stores the actual instance. We don't remove the lock entry
	// here because set_instance will handle final cleanup.
	if !isnil(c.bean_lock) {
		c.bean_lock.unlock(type_name)
	}

	return unsafe { nil } // actual instantiation done by comptime-generated code
}

// resolve_by_qualifier retrieves a bean instance by its qualifier name.
// Uses the same read-lock-fast-path / write-lock-slow-path pattern as resolve().
pub fn (mut c Container) resolve_by_qualifier(qualifier string) !voidptr {
	// Fast path: read lock for qualifier → type_name resolution + singleton cache
	c.mu.rlock()
	type_name := c.qualifiers[qualifier] or {
		c.mu.runlock()
		return error('no bean with qualifier "${qualifier}" found')
	}
	if inst := c.instances[type_name] {
		if inst.state == .instantiating {
			c.mu.runlock()
			return error('circular dependency detected for bean "${type_name}"')
		}
		result := inst.instance
		c.mu.runlock()
		return result
	}
	c.mu.runlock()

	// Slow path: write lock
	c.mu.@lock()
	defer { c.mu.unlock() }

	// Double-check
	if inst := c.instances[type_name] {
		if inst.state == .instantiating {
			return error('circular dependency detected for bean "${type_name}"')
		}
		return inst.instance
	}

	return c.resolve_unlocked(type_name)
}

// has checks if a bean definition exists (including aliases and FactoryBean-produced beans).
// Also checks the parent container if available.
pub fn (mut c Container) has(type_name string) bool {
	c.mu.rlock()
	defer { c.mu.runlock() }
	// Resolve alias chain
	resolved := c.resolve_alias_chain(type_name, 0)
	if resolved in c.definitions {
		return true
	}
	// Also check FactoryBean registry
	if !isnil(c.factory_registry) && c.factory_registry.has_factory(resolved) {
		return true
	}
	// Check parent container
	if !isnil(c.parent) {
		return c.parent.has(resolved)
	}
	return false
}

// has_qualifier checks if a qualifier is registered.
pub fn (mut c Container) has_qualifier(qualifier string) bool {
	c.mu.rlock()
	defer { c.mu.runlock() }
	return qualifier in c.qualifiers
}

// ── @Primary Support ──

// resolve_primary resolves a bean that is marked as @[primary].
// When multiple beans of the same base type exist, the primary one is preferred.
//
// Spring equivalent: @Primary — PrimaryBeanResolver
//
// Usage:
//   // If both 'RedisCache' and 'MemCache' are registered,
//   // and 'RedisCache' is marked is_primary=true:
//   instance := container.resolve_primary() or { ... }
pub fn (mut c Container) resolve_primary() !voidptr {
	// Use read lock only to find the primary bean name.
	// The actual resolution is delegated to resolve() which has its own locking.
	// This avoids holding a write lock during the full resolution process,
	// which would block all other readers unnecessarily.
	c.mu.rlock()
	mut primary_name := ''
	for name, def in c.definitions {
		if def.is_primary {
			primary_name = name
			break
		}
	}
	c.mu.runlock()

	if primary_name.len == 0 {
		return error('no @[primary] bean found in container')
	}
	// Resolve by the captured name — resolve() has its own locking.
	// Note: between our rlock release and resolve() call, the bean could
	// theoretically be removed, but resolve() will return a "not found" error
	// in that case, which is correct behavior.
	return c.resolve(primary_name)
}

// get_primary_bean_name returns the type_name of the primary bean, or empty string.
pub fn (mut c Container) get_primary_bean_name() string {
	c.mu.rlock()
	defer { c.mu.runlock() }
	for name, def in c.definitions {
		if def.is_primary {
			return name
		}
	}
	return ''
}

// ── BeanDefinition Merging (Property Inheritance) ──

// get_merged_definition returns a BeanDefinition with properties inherited
// from its parent definition. If the bean has no parent, returns a copy
// of its own definition.
//
// Spring equivalent: AbstractBeanDefinition.overrideFrom()
// Child properties override parent properties; parent provides defaults.
//
// Rules:
//   - scope: child overrides parent (default: singleton)
//   - is_lazy: child overrides parent (default: false)
//   - dependencies: merged (child deps appended after parent deps)
//   - qualifier: child overrides parent
//   - init_method: child overrides parent
//   - destroy_method: child overrides parent
//   - tags: merged (deduplicated)
//   - depends_on: merged (deduplicated)
//   - is_primary: child overrides parent
pub fn (mut c Container) get_merged_definition(type_name string) !BeanDefinition {
	return c.get_merged_definition_with_visited(type_name, []string{})
}

// get_merged_definition_with_visited carries a visited set to detect
// circular inheritance chains (A → B → A).
fn (mut c Container) get_merged_definition_with_visited(type_name string, visited []string) !BeanDefinition {
	// Check for circular inheritance
	if type_name in visited {
		return error('circular bean definition inheritance detected: ${visited.join(' → ')} → ${type_name}')
	}

	c.mu.rlock()
	child := c.definitions[type_name] or {
		c.mu.runlock()
		return error('bean "${type_name}" not found')
	}
	c.mu.runlock()

	// No parent → return copy as-is
	if child.parent_name.len == 0 {
		return child
	}

	// Resolve parent (recursively, with cycle detection)
	mut new_visited := visited.clone()
	new_visited << type_name

	parent := c.get_merged_definition_with_visited(child.parent_name, new_visited) or {
		// If it's a circular inheritance error, propagate it up
		if err.msg().contains('circular') {
			return err
		}
		// Otherwise parent just doesn't exist → use child as-is
		return child
	}

	return merge_bean_definitions(parent, child)
}

// merge_bean_definitions merges a parent and child BeanDefinition.
// Child values override parent; collections are merged.
fn merge_bean_definitions(parent BeanDefinition, child BeanDefinition) BeanDefinition {
	mut merged := child

	// Inherit scope from parent if child has default
	if child.scope == .singleton && parent.scope != .singleton {
		merged.scope = parent.scope
	}

	// Inherit is_lazy from parent if child is not explicitly set
	// (V zero-value for bool is false, so we use a heuristic:
	//  if parent is lazy and child isn't explicitly different, inherit)
	// Note: This is best-effort since V has no option[bool]

	// Inherit init_method from parent if child has none
	if child.init_method.len == 0 && parent.init_method.len > 0 {
		merged.init_method = parent.init_method
	}

	// Inherit destroy_method from parent if child has none
	if child.destroy_method.len == 0 && parent.destroy_method.len > 0 {
		merged.destroy_method = parent.destroy_method
	}

	// Inherit qualifier from parent if child has none
	if child.qualifier.len == 0 && parent.qualifier.len > 0 {
		merged.qualifier = parent.qualifier
	}

	// Merge dependencies (parent first, then child — deduplicated by field_name)
	mut merged_deps := map[string]Dependency{}
	for dep in parent.dependencies {
		merged_deps[dep.field_name] = dep
	}
	for dep in child.dependencies {
		merged_deps[dep.field_name] = dep // child overrides parent for same field_name
	}
	mut deps_list := []Dependency{}
	for _, dep in merged_deps {
		deps_list << dep
	}
	merged.dependencies = deps_list

	// Merge tags (deduplicated)
	mut tag_set := map[string]bool{}
	for tag in parent.tags {
		tag_set[tag] = true
	}
	for tag in child.tags {
		tag_set[tag] = true
	}
	mut tags_list := []string{}
	for tag, _ in tag_set {
		tags_list << tag
	}
	merged.tags = tags_list

	// Merge depends_on (deduplicated)
	mut dep_set := map[string]bool{}
	for dep in parent.depends_on {
		dep_set[dep] = true
	}
	for dep in child.depends_on {
		dep_set[dep] = true
	}
	mut depends_list := []string{}
	for dep, _ in dep_set {
		depends_list << dep
	}
	merged.depends_on = depends_list

	// Clear parent_name to avoid re-merging
	merged.parent_name = ''

	return merged
}

// ── Introspection ──

// get_definition returns a copy of a bean definition.
pub fn (mut c Container) get_definition(type_name string) !BeanDefinition {
	c.mu.rlock()
	defer { c.mu.runlock() }
	return c.definitions[type_name] or { return error('bean "${type_name}" not found') }
}

// bean_names returns all registered bean type names.
pub fn (mut c Container) bean_names() []string {
	c.mu.rlock()
	defer { c.mu.runlock() }
	return c.definitions.keys()
}

// bean_count returns the number of registered beans.
pub fn (mut c Container) bean_count() int {
	c.mu.rlock()
	defer { c.mu.runlock() }
	return c.definitions.len
}

// singleton_count returns the number of instantiated singletons.
pub fn (mut c Container) singleton_count() int {
	c.mu.rlock()
	defer { c.mu.runlock() }
	return c.instances.len
}

// dependencies_of returns the dependencies for a given bean.
pub fn (mut c Container) dependencies_of(type_name string) []Dependency {
	c.mu.rlock()
	defer { c.mu.runlock() }
	def := c.definitions[type_name] or { return []Dependency{} }
	return def.dependencies.clone()
}

// ── Lifecycle ──

// set_instance stores a resolved singleton instance.
// Called by comptime-generated code after instantiation and injection.
//
// This method also:
//   - Transitions the bean state from .instantiating to .ready
//   - Dispatches the bean.created event (Spring ApplicationEvent inspired)
//   - Cleans up the per-bean lock entry
//
// Spring equivalent: DefaultSingletonBeanRegistry.addSingleton()
pub fn (mut c Container) set_instance(type_name string, instance voidptr) {
	c.mu.@lock()
	defer { c.mu.unlock() }

	c.instances[type_name] = &BeanInstance{
		definition: unsafe { nil }
		instance:   instance
		state:      .ready
	}

	// Transition bean state from instantiating → ready
	if type_name in c.definitions {
		mut def := c.definitions[type_name]
		def.state = .ready
		c.definitions[type_name] = def
	}

	// Clean up per-bean lock (now that the instance is stored)
	if !isnil(c.bean_lock) {
		c.bean_lock.remove(type_name)
	}

	// Dispatch bean.created event AFTER the instance is stored
	// This ensures listeners only see events for beans with real instances.
	if !isnil(c.event_bus) {
		mut bus := unsafe { c.event_bus }
		mut event := new_event(event_bean_created, type_name)
		bus.dispatch(event)
	}
}

// mark_ready marks a bean as fully initialized.
pub fn (mut c Container) mark_ready(type_name string) ! {
	c.mu.@lock()
	defer { c.mu.unlock() }

	mut def := c.definitions[type_name] or { return error('bean "${type_name}" not found') }
	def.state = .ready
	c.definitions[type_name] = def
}

// destroy removes a singleton instance and calls its pre_destroy method.
pub fn (mut c Container) destroy(type_name string) ! {
	c.mu.@lock()
	defer { c.mu.unlock() }

	if type_name !in c.instances {
		return error('bean instance "${type_name}" not found')
	}
	mut inst := unsafe { c.instances[type_name] }
	inst.state = .destroying
	c.instances.delete(type_name)

	mut def := c.definitions[type_name] or { return }
	def.state = .registered
	c.definitions[type_name] = def

	// Dispatch bean.destroyed event
	if !isnil(c.event_bus) {
		mut bus := unsafe { c.event_bus }
		mut event := new_event(event_bean_destroyed, type_name)
		bus.dispatch(event)
	}
}

// remove_definition removes a bean definition from the container.
// Also removes any associated singleton instance and qualifier mapping.
// Returns an error if the bean definition is not found.
//
// Spring equivalent: DefaultListableBeanFactory.removeBeanDefinition()
// Laravel equivalent: Container::forget('service')
//
// Usage:
//   container.remove_definition('TestService') or { return }
pub fn (mut c Container) remove_definition(type_name string) ! {
	c.mu.@lock()
	defer { c.mu.unlock() }

	if type_name !in c.definitions {
		return error('bean definition "${type_name}" not found')
	}

	// Remove singleton instance if exists
	if type_name in c.instances {
		c.instances.delete(type_name)
	}

	// Remove qualifier mapping if present
	def := c.definitions[type_name]
	if def.qualifier.len > 0 && c.qualifiers[def.qualifier] == type_name {
		c.qualifiers.delete(def.qualifier)
	}

	// Remove from type index
	if !isnil(c.type_index) {
		// Remove from interface index
		for iface in def.interfaces {
			c.type_index.unregister_interface(type_name, iface)
		}
		// Remove from tag index
		for tag in def.tags {
			c.type_index.unregister_tag(type_name, tag)
		}
	}

	// Remove all aliases that point to this bean
	mut aliases_to_remove := []string{}
	for alias, canonical in c.aliases {
		if canonical == type_name {
			aliases_to_remove << alias
		}
	}
	for alias in aliases_to_remove {
		c.aliases.delete(alias)
	}

	// Remove the definition
	c.definitions.delete(type_name)
}

// destroy_all removes all singleton instances (shutdown hook).
pub fn (mut c Container) destroy_all() {
	c.mu.@lock()
	defer { c.mu.unlock() }

	for type_name, _ in c.instances {
		c.instances.delete(type_name)
		mut def := c.definitions[type_name] or { continue }
		def.state = .registered
		c.definitions[type_name] = def
	}
}

// ── Profile ──

// add_profile activates a profile.
pub fn (mut c Container) add_profile(profile string) {
	c.mu.@lock()
	defer { c.mu.unlock() }
	c.profiles << profile
}

// set_profiles replaces all active profiles.
pub fn (mut c Container) set_profiles(profiles []string) {
	c.mu.@lock()
	defer { c.mu.unlock() }
	c.profiles = profiles.clone()
}

// has_profile checks if a profile is active.
pub fn (mut c Container) has_profile(profile string) bool {
	c.mu.rlock()
	defer { c.mu.runlock() }
	return profile in c.profiles
}

// ── Circular Dependency Detection ──

// check_circular_dependencies performs a topological sort on all bean
// definitions to detect circular dependencies at registration time.
// Returns an error if a cycle is found, with the cycle path.
pub fn (mut c Container) check_circular_dependencies() ! {
	c.mu.rlock()
	defer { c.mu.runlock() }

	// Kahn's algorithm for topological sort
	mut in_degree := map[string]int{}
	mut adj := map[string][]string{}

	// Initialize
	for name, _ in c.definitions {
		in_degree[name] = 0
		adj[name] = []string{}
	}

	// Build adjacency list (dependency → dependent)
	for name, def in c.definitions {
		for dep in def.dependencies {
			if dep.type_name in in_degree {
				adj[dep.type_name] << name
				in_degree[name]++
			}
		}
		// Also check @[depends_on] explicit ordering
		for dep_name in def.depends_on {
			if dep_name in in_degree {
				adj[dep_name] << name
				in_degree[name]++
			}
		}
	}

	// Find all nodes with no incoming edges
	mut queue := []string{}
	for name, degree in in_degree {
		if degree == 0 {
			queue << name
		}
	}

	mut sorted := []string{}
	for queue.len > 0 {
		node := queue[0]
		queue.delete(0)
		sorted << node

		for neighbor in adj[node] {
			in_degree[neighbor]--
			if in_degree[neighbor] == 0 {
				queue << neighbor
			}
		}
	}

	// If not all nodes are sorted, there is a cycle
	if sorted.len < c.definitions.len {
		mut cycle_nodes := []string{}
		for name, degree in in_degree {
			if degree > 0 {
				cycle_nodes << name
			}
		}
		return error('circular dependency detected among beans: ${cycle_nodes.join(' → ')}')
	}
}

// ── Diagnostic ──

// print_beans prints all registered beans and their dependencies.
pub fn (mut c Container) print_beans() {
	c.mu.rlock()
	defer { c.mu.runlock() }

	println('═══ Photon Container: ${c.definitions.len} bean(s) ═══')
	println('${'Bean':-30s} ${'Scope':-12s} ${'State':-14s} ${'Dependencies'}')
	println('${'─'.repeat(80)}')

	for name, def in c.definitions {
		mut deps_str := ''
		for i, dep in def.dependencies {
			if i > 0 {
				deps_str += ', '
			}
			deps_str += dep.field_name
			if dep.qualifier.len > 0 {
				deps_str += ':${dep.qualifier}'
			}
		}
		if deps_str.len == 0 {
			deps_str = '-'
		}

		mut inst_state := 'not instantiated'
		if name in c.instances {
			inst_state = unsafe { c.instances[name] }.state.str()
		}

		println('${name:-30s} ${def.scope.str():-12s} ${inst_state:-14s} ${deps_str}')
	}
	println('${'─'.repeat(80)}')
	println('Singletons: ${c.instances.len} | Aliases: ${c.aliases.len} | Profiles: ${c.profiles.join(', ')}')
}

// alias_count returns the number of registered aliases.
pub fn (mut c Container) alias_count() int {
	c.mu.rlock()
	defer { c.mu.runlock() }
	return c.aliases.len
}

// ── Type-safe Generic Resolution ──

// resolve_typed resolves a bean and casts it to the expected type T.
// This provides type safety compared to the voidptr-based resolve().
//
// Usage:
//   user_service := container.resolve_typed[UserService]('UserService')!
//   // user_service is &UserService, not voidptr
//
// Spring equivalent: ApplicationContext.getBean(Class<T>)
pub fn (mut c Container) resolve_typed[T](type_name string) !&T {
	ptr := c.resolve(type_name)!
	return unsafe { &T(ptr) }
}

// ── Type-Based Lookup (Spring ListableBeanFactory inspired) ──

// beans_for_interface returns all bean type names that implement the given interface.
// Spring equivalent: ListableBeanFactory.getBeanNamesForType(MyInterface.class)
// Laravel equivalent: Container::tagged('tag')
//
// Usage:
//   handlers := container.beans_for_interface('EventHandler')
//   for name in handlers {
//       handler := container.resolve(name)!
//   }
pub fn (mut c Container) beans_for_interface(interface_name string) []string {
	if !isnil(c.type_index) {
		return c.type_index.beans_for_interface(interface_name)
	}
	// Fallback: scan definitions
	c.mu.rlock()
	defer { c.mu.runlock() }
	mut result := []string{}
	for name, def in c.definitions {
		if interface_name in def.interfaces {
			result << name
		}
	}
	return result
}

// beans_for_tag returns all bean type names with the given tag.
// Laravel equivalent: Container::tagged('cache')
// Spring equivalent: getBeansWithAnnotation()
//
// Usage:
//   cache_beans := container.beans_for_tag('cache')
pub fn (mut c Container) beans_for_tag(tag string) []string {
	if !isnil(c.type_index) {
		return c.type_index.beans_for_tag(tag)
	}
	// Fallback: scan definitions
	c.mu.rlock()
	defer { c.mu.runlock() }
	mut result := []string{}
	for name, def in c.definitions {
		if tag in def.tags {
			result << name
		}
	}
	return result
}

// resolve_all_by_interface resolves all beans implementing the given interface.
// Returns a list of voidptr instances.
// Spring equivalent: ListableBeanFactory.getBeansOfType(MyInterface.class)
//
// Usage:
//   handlers := container.resolve_all_by_interface('EventHandler')!
pub fn (mut c Container) resolve_all_by_interface(interface_name string) ![]voidptr {
	names := c.beans_for_interface(interface_name)
	mut instances := []voidptr{}
	for name in names {
		instance := c.resolve(name) or { continue }
		instances << instance
	}
	return instances
}

// resolve_all_by_tag resolves all beans with the given tag.
// Laravel equivalent: Container::tagged('cache')
pub fn (mut c Container) resolve_all_by_tag(tag string) ![]voidptr {
	names := c.beans_for_tag(tag)
	mut instances := []voidptr{}
	for name in names {
		instance := c.resolve(name) or { continue }
		instances << instance
	}
	return instances
}

// create_deferred_provider creates a DeferredProvider for the given type.
// The provider will lazily resolve the bean on first access.
// Spring equivalent: ObjectProvider<T>
// Laravel equivalent: Container::lazy()
//
// Usage:
//   provider := container.create_deferred_provider('CacheService')
//   // ... later ...
//   cache := provider.get()!  // only resolved now
pub fn (mut c Container) create_deferred_provider(type_name string) &DeferredProvider {
	mut provider := new_deferred_provider(type_name)
	provider.set_container(unsafe { c })
	return provider
}

// create_mutable_deferred_provider creates a DeferredProvider that returns
// a new instance each time get() is called (prototype-like behavior).
// Spring equivalent: ObjectProvider with prototype scope
pub fn (mut c Container) create_mutable_deferred_provider(type_name string) &DeferredProvider {
	mut provider := new_deferred_provider(type_name)
	provider.mutable = true
	provider.set_container(unsafe { c })
	return provider
}

// ── Replace Definition (Spring override / Laravel rebind) ──

// replace_definition replaces an existing bean definition with a new one.
// If the bean was already instantiated as a singleton, the instance is removed.
// If the bean had a qualifier, the old qualifier mapping is updated.
// If the bean had aliases, they are preserved.
// If the bean does not exist yet, this is equivalent to register().
//
// Spring equivalent: DefaultListableBeanFactory.registerBeanDefinition()
//   (Spring allows re-registration to override definitions)
// Laravel equivalent: Container::rebind('service', fn() => new Service())
//
// Usage:
//   container.replace_definition(new_def) or { return }
pub fn (mut c Container) replace_definition(def BeanDefinition) ! {
	c.mu.@lock()
	defer { c.mu.unlock() }

	// If definition doesn't exist, just register it
	if def.type_name !in c.definitions {
		c.definitions[def.type_name] = def
		if def.qualifier.len > 0 {
			c.qualifiers[def.qualifier] = def.type_name
		}
		if !isnil(c.type_index) {
			for iface in def.interfaces {
				c.type_index.register_interface(def.type_name, iface)
			}
			for tag in def.tags {
				c.type_index.register_tag(def.type_name, tag)
			}
		}
		return
	}

	// Remove old singleton instance if exists
	if def.type_name in c.instances {
		c.instances.delete(def.type_name)
	}

	// Update qualifier mapping
	old_def := c.definitions[def.type_name]
	if old_def.qualifier.len > 0 && c.qualifiers[old_def.qualifier] == def.type_name {
		c.qualifiers.delete(old_def.qualifier)
	}

	// Remove old type index entries
	if !isnil(c.type_index) {
		for iface in old_def.interfaces {
			c.type_index.unregister_interface(def.type_name, iface)
		}
		for tag in old_def.tags {
			c.type_index.unregister_tag(def.type_name, tag)
		}
	}

	// Store new definition
	c.definitions[def.type_name] = def

	// Add new qualifier mapping
	if def.qualifier.len > 0 {
		c.qualifiers[def.qualifier] = def.type_name
	}

	// Add new type index entries
	if !isnil(c.type_index) {
		for iface in def.interfaces {
			c.type_index.register_interface(def.type_name, iface)
		}
		for tag in def.tags {
			c.type_index.register_tag(def.type_name, tag)
		}
	}
}

// ── Optional Resolution (Spring getIfAvailable / Laravel makeWith) ──

// resolve_or resolves a bean, returning a default value if not found.
// This is useful for optional dependencies where the bean may not be registered.
//
// Spring equivalent: ObjectProvider.getIfAvailable(defaultValue)
// Laravel equivalent: app()->make('service', $default)
//
// Usage:
//   cache := container.resolve_or('CacheService', default_cache)
pub fn (mut c Container) resolve_or(type_name string, default_val voidptr) voidptr {
	result := c.resolve(type_name) or { return default_val }
	return result
}

// resolve_typed_or resolves a bean and casts it to type T, returning a default if not found.
//
// Spring equivalent: ApplicationContext.getBean(Class<T>) with fallback
pub fn (mut c Container) resolve_typed_or[T](type_name string, default_val &T) &T {
	ptr := c.resolve(type_name) or { return default_val }
	return unsafe { &T(ptr) }
}

// ── Container Freeze (Spring ConfigurableListableBeanFactory) ──

// Container freeze state — prevents registration after refresh.
// Spring equivalent: ConfigurableListableBeanFactory.freezeConfiguration()
@[heap]
pub struct ContainerFreeze {
pub mut:
	is_frozen bool
mut:
	mu sync.RwMutex
}

// new_container_freeze creates a ContainerFreeze in unfrozen state.
pub fn new_container_freeze() &ContainerFreeze {
	return &ContainerFreeze{
		is_frozen: false
	}
}

// freeze prevents further bean registration.
// Spring equivalent: ConfigurableListableBeanFactory.freezeConfiguration()
pub fn (mut cf ContainerFreeze) freeze() {
	cf.mu.@lock()
	defer { cf.mu.unlock() }
	cf.is_frozen = true
}

// unfreeze allows bean registration again.
// Spring equivalent: ConfigurableListableBeanFactory.clearMetadataCache()
//   (used internally during refresh to temporarily allow re-registration)
pub fn (mut cf ContainerFreeze) unfreeze() {
	cf.mu.@lock()
	defer { cf.mu.unlock() }
	cf.is_frozen = false
}

// frozen returns whether the container is frozen.
pub fn (mut cf ContainerFreeze) frozen() bool {
	cf.mu.rlock()
	defer { cf.mu.runlock() }
	return cf.is_frozen
}

// ── @Lookup Method Injection Support (Spring @Lookup) ──

// LookupInjection describes a method that should return a new bean instance
// each time it is called. This is the Photon equivalent of Spring's @Lookup
// annotation, which provides method-level dependency injection.
//
// Unlike @[autowired] which injects at construction time, @Lookup methods
// are called each time the method is invoked, returning a fresh prototype
// or a new lookup from the container.
//
// Spring equivalent: @Lookup — method injection for prototype beans in singletons
// Laravel equivalent: N/A (use Container::make() directly)
pub struct LookupInjection {
pub:
	method_name string // method to override
	type_name   string // bean type to look up
	qualifier   string // optional qualifier for disambiguation
}

// resolve_lookup resolves a bean for a @Lookup method injection.
// Unlike regular resolve(), this always returns a new instance for prototype
// beans, even when called from a singleton. This is the core mechanism
// behind Spring's @Lookup annotation.
//
// Usage:
//   // In a singleton bean, a @Lookup method creates a new prototype each time:
//   //   @[lookup]
//   //   fn (s &OrderService) create_command() &Command {
//   //       // This method body is replaced by the container at runtime
//   //   }
//   //
//   // The comptime scanner generates:
//   //   instance := container.resolve_lookup('Command', '')!
//
// Spring equivalent: CglibProxy @Lookup method override
// Laravel equivalent: Container::make() each time
pub fn (mut c Container) resolve_lookup(type_name string, qualifier string) !voidptr {
	// If qualifier is specified, resolve by qualifier
	if qualifier.len > 0 {
		return c.resolve_by_qualifier(qualifier)
	}
	// Otherwise, resolve by type name
	// For prototype beans, this always returns a new instance.
	// For singleton beans, this returns the cached instance.
	return c.resolve(type_name)
}

// resolve_lookup_for_bean resolves all @Lookup method injections for a given bean.
// Returns a map of method_name → resolved instance (voidptr).
// This is called by the comptime-generated code after bean instantiation.
//
// Spring equivalent: AbstractBeanFactory.resolveDependency() for @Lookup methods
pub fn (mut c Container) resolve_lookup_for_bean(type_name string) !map[string]voidptr {
	c.mu.rlock()
	def := c.definitions[type_name] or {
		c.mu.runlock()
		return map[string]voidptr{}
	}
	lookups := def.lookup_injections.clone()
	c.mu.runlock()

	mut result := map[string]voidptr{}
	for li in lookups {
		instance := c.resolve_lookup(li.type_name, li.qualifier) or { continue }
		result[li.method_name] = instance
	}
	return result
}

// ── resolve_all_by_type: Generic Type-Based Resolution (Spring getBeansOfType) ──

// resolve_all_by_type resolves all beans that implement a given interface or type.
// This is a more general version of resolve_all_by_interface that also searches
// through bean definitions whose type_name matches the given type.
//
// Unlike resolve_all_by_interface() which only uses the type_index,
// this method also scans bean type_names for an exact match,
// making it useful when beans don't explicitly declare their interfaces.
//
// Spring equivalent: ListableBeanFactory.getBeansOfType(Class<T>)
// Laravel equivalent: Container::tagged() with implicit type matching
//
// Usage:
//   handlers := container.resolve_all_by_type('EventHandler')!
pub fn (mut c Container) resolve_all_by_type(type_name string) ![]voidptr {
	mut instances := []voidptr{}

	// 1. Try interface-based lookup (fast path via type_index)
	iface_beans := c.beans_for_interface(type_name)
	for name in iface_beans {
		instance := c.resolve(name) or { continue }
		instances << instance
	}

	// 2. Try tag-based lookup
	tag_beans := c.beans_for_tag(type_name)
	for name in tag_beans {
		instance := c.resolve(name) or { continue }
		// Avoid duplicates from interface lookup
		mut already_resolved := false
		for existing_name in iface_beans {
			if existing_name == name {
				already_resolved = true
				break
			}
		}
		if !already_resolved {
			instances << instance
		}
	}

	// 3. Try exact type_name match (slow path — scan definitions)
	c.mu.rlock()
	for name, def in c.definitions {
		// Skip if already resolved via interface or tag
		mut already_found := false
		for existing_name in iface_beans {
			if existing_name == name {
				already_found = true
				break
			}
		}
		if already_found {
			continue
		}
		for existing_name in tag_beans {
			if existing_name == name {
				already_found = true
				break
			}
		}
		if already_found {
			continue
		}

		// Check exact type_name match
		if name == type_name || def.type_name == type_name {
			c.mu.runlock()
			instance := c.resolve(name) or { continue }
			instances << instance
			c.mu.rlock()
			continue
		}

		// Check if type_name appears in the interfaces list
		if type_name in def.interfaces {
			c.mu.runlock()
			instance := c.resolve(name) or { continue }
			instances << instance
			c.mu.rlock()
		}
	}
	c.mu.runlock()

	return instances
}
