module core

// bean_factory.v - BeanFactory Interface Hierarchy (Spring-inspired)
//
// Defines the layered BeanFactory interface hierarchy that mirrors Spring's
// org.springframework.beans.factory package:
//
//   BeanFactory                       — root: basic bean lookup
//     ├─ ListableBeanFactory          — enumerate beans by type
//     ├─ HierarchicalBeanFactory      — parent-child container support
//     └─ AutowireCapableBeanFactory   — create/autowire beans programmatically
//         └─ ConfigurableBeanFactory  — configure aliases, scope, destroy
//
// The existing `Container` struct satisfies all these interfaces via its
// existing methods — no changes to Container are required.

// ── BeanFactory (root interface) ──

// BeanFactory is the root interface for accessing the Photon IoC container.
//
// Spring equivalent: org.springframework.beans.factory.BeanFactory
pub interface BeanFactory {
mut:
	resolve(name string) !voidptr
	has(name string) bool
	has_qualifier(qualifier string) bool
	resolve_by_qualifier(qualifier string) !voidptr
	is_singleton(name string) bool
	is_prototype(name string) bool
}

// ── ListableBeanFactory ──

// ListableBeanFactory extends BeanFactory with the ability to enumerate
// all bean definitions by type, tag, or interface.
//
// Spring equivalent: org.springframework.beans.factory.ListableBeanFactory
pub interface ListableBeanFactory {
mut:
	bean_names() []string
	bean_count() int
	beans_for_interface(interface_name string) []string
	beans_for_tag(tag string) []string
	resolve_all_by_interface(interface_name string) ![]voidptr
	resolve_all_by_tag(tag string) ![]voidptr
}

// ── HierarchicalBeanFactory ──

// HierarchicalBeanFactory extends BeanFactory with parent-child container
// support. A child container can delegate bean lookups to its parent.
//
// Spring equivalent: org.springframework.beans.factory.HierarchicalBeanFactory
pub interface HierarchicalBeanFactory {
mut:
	has_instance(name string) bool
}

// ── AutowireCapableBeanFactory ──

// AutowireCapableBeanFactory extends BeanFactory with the ability to
// create, autowire, and initialize beans programmatically.
//
// Spring equivalent: org.springframework.beans.factory.config.AutowireCapableBeanFactory
pub interface AutowireCapableBeanFactory {
mut:
	register_instance(type_name string, instance voidptr) !
	register(def BeanDefinition) !
	destroy(type_name string) !
	destroy_all()
}

// ── ConfigurableBeanFactory ──

// ConfigurableBeanFactory extends AutowireCapableBeanFactory with
// configuration methods for aliases, scopes, and post-processors.
//
// Spring equivalent: org.springframework.beans.factory.config.ConfigurableBeanFactory
pub interface ConfigurableBeanFactory {
mut:
	register_alias(alias string, canonical_name string) !
	remove_alias(alias string)
	has_alias(alias string) bool
	canonical_name(name string) string
	set_profiles(profiles []string)
	add_profile(profile string)
	has_profile(profile string) bool
}

// ── BeanDefinitionRegistry ──

// BeanDefinitionRegistry is the interface for registering and managing
// bean definitions.
//
// Spring equivalent: org.springframework.beans.factory.support.BeanDefinitionRegistry
pub interface BeanDefinitionRegistry {
mut:
	register(def BeanDefinition) !
	remove_definition(type_name string) !
	has_definition(type_name string) bool
	get_definition(type_name string) !BeanDefinition
	bean_names() []string
	bean_count() int
}

// ── Convenience Combined Interface ──

// DefaultBeanFactory is the standard BeanFactory type that combines
// all sub-interfaces. Container satisfies this combined interface.
pub interface DefaultBeanFactory {
mut:
	// BeanFactory
	resolve(name string) !voidptr
	has(name string) bool
	has_qualifier(qualifier string) bool
	resolve_by_qualifier(qualifier string) !voidptr
	is_singleton(name string) bool
	is_prototype(name string) bool
	// ListableBeanFactory
	bean_names() []string
	bean_count() int
	beans_for_interface(interface_name string) []string
	beans_for_tag(tag string) []string
	resolve_all_by_interface(interface_name string) ![]voidptr
	resolve_all_by_tag(tag string) ![]voidptr
	// HierarchicalBeanFactory
	has_instance(name string) bool
	// AutowireCapableBeanFactory
	register_instance(type_name string, instance voidptr) !
	register(def BeanDefinition) !
	destroy(type_name string) !
	destroy_all()
	// ConfigurableBeanFactory
	register_alias(alias string, canonical_name string) !
	remove_alias(alias string)
	has_alias(alias string) bool
	canonical_name(name string) string
	set_profiles(profiles []string)
	add_profile(profile string)
	has_profile(profile string) bool
	// BeanDefinitionRegistry
	remove_definition(type_name string) !
	has_definition(type_name string) bool
	get_definition(type_name string) !BeanDefinition
}

// ── Factory Helper Functions ──

// as_bean_factory returns the Container as a BeanFactory interface.
pub fn (mut c Container) as_bean_factory() &BeanFactory {
	return unsafe { &BeanFactory(c) }
}

// as_listable_bean_factory returns the Container as a ListableBeanFactory.
pub fn (mut c Container) as_listable_bean_factory() &ListableBeanFactory {
	return unsafe { &ListableBeanFactory(c) }
}

// as_hierarchical_bean_factory returns the Container as a HierarchicalBeanFactory.
pub fn (mut c Container) as_hierarchical_bean_factory() &HierarchicalBeanFactory {
	return unsafe { &HierarchicalBeanFactory(c) }
}

// as_autowire_capable_bean_factory returns the Container as an AutowireCapableBeanFactory.
pub fn (mut c Container) as_autowire_capable_bean_factory() &AutowireCapableBeanFactory {
	return unsafe { &AutowireCapableBeanFactory(c) }
}

// as_configurable_bean_factory returns the Container as a ConfigurableBeanFactory.
pub fn (mut c Container) as_configurable_bean_factory() &ConfigurableBeanFactory {
	return unsafe { &ConfigurableBeanFactory(c) }
}

// as_bean_definition_registry returns the Container as a BeanDefinitionRegistry.
pub fn (mut c Container) as_bean_definition_registry() &BeanDefinitionRegistry {
	return unsafe { &BeanDefinitionRegistry(c) }
}

// as_default_bean_factory returns the Container as a DefaultBeanFactory.
pub fn (mut c Container) as_default_bean_factory() &DefaultBeanFactory {
	return unsafe { &DefaultBeanFactory(c) }
}
