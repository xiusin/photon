module core

// bean_definition.v - Bean Definition & Metadata Types
//
// Defines the core types for bean metadata: Scope, BeanState, Dependency,
// BeanDefinition, and BeanDefinitionBuilder (fluent builder API).
// Extracted from core.v for maintainability (original file was ~2000 lines).

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
	conditions            []&Condition          // @[conditional] — conditions that must pass for registration
	value_bindings        []ValueBinding        // @[value('key')] fields, filled by comptime scan
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
		conditions:            []&Condition{}
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
	conditions_            []&Condition
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
		conditions_:            []&Condition{}
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

// set_conditions sets the conditions that must be satisfied for the bean to be
// registered. If any condition returns false during register(), the bean is
// silently skipped (Spring @Conditional behavior).
//
// Spring equivalent: @Conditional
pub fn (mut b BeanDefinitionBuilder) set_conditions(conditions []&Condition) &BeanDefinitionBuilder {
	b.conditions_ = conditions
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
		conditions:            b.conditions_.clone()
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
