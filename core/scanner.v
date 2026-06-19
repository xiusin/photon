module core

// scanner.v - Compile-Time Bean Scanner
//
// Provides comptime helper functions that scan struct attributes
// and generate BeanDefinitions for the DI container.
//
// At compile time, the user's application code calls:
//   core.scan_and_register[MyApp](mut container)
//
// This uses $for to inspect all structs/methods and automatically
// register @[component], @[service], @[repository], @[controller] beans.
//
// All resolution happens at compile time — zero runtime reflection.

// ── Attribute Constants ──

pub const attr_component = 'component'
pub const attr_service = 'service'
pub const attr_repository = 'repository'
pub const attr_controller = 'controller'
pub const attr_configuration = 'configuration'
pub const attr_autowired = 'autowired'
pub const attr_scope = 'scope'
pub const attr_lazy = 'lazy'
pub const attr_qualifier = 'qualifier'
pub const attr_value = 'value'
pub const attr_post_construct = 'post_construct'
pub const attr_pre_destroy = 'pre_destroy'
// New annotations (Spring Boot / Laravel inspired)
pub const attr_auto_configuration = 'auto_configuration'
pub const attr_event_listener = 'event_listener'
pub const attr_conditional_on_profile = 'conditional_on_profile'
pub const attr_conditional_on_property = 'conditional_on_property'
pub const attr_conditional_on_bean = 'conditional_on_bean'
pub const attr_conditional_on_missing_bean = 'conditional_on_missing_bean'
pub const attr_conditional_on_expression = 'conditional_on_expression'
pub const attr_conditional_on_class = 'conditional_on_class'
pub const attr_conditional_on_missing_class = 'conditional_on_missing_class'
pub const attr_conditional_on_cloud_platform = 'conditional_on_cloud_platform'
pub const attr_scheduled = 'scheduled'
pub const attr_transactional = 'transactional'
pub const attr_cacheable = 'cacheable'
pub const attr_required = 'required'
pub const attr_depends_on = 'depends_on'
pub const attr_primary = 'primary'
pub const attr_extends = 'extends'
pub const attr_bean = 'bean'

// ── Component Types ──

// ComponentType categorizes the kind of bean.
pub enum ComponentType {
	unknown
	component
	service
	repository
	controller
	configuration
	auto_configuration
}

// str returns a human-readable component type.
pub fn (ct ComponentType) str() string {
	return match ct {
		.unknown { 'unknown' }
		.component { 'component' }
		.service { 'service' }
		.repository { 'repository' }
		.controller { 'controller' }
		.configuration { 'configuration' }
		.auto_configuration { 'auto_configuration' }
	}
}

// component_type_from_attr maps a V attribute name to ComponentType.
pub fn component_type_from_attr(attr string) ComponentType {
	return match attr {
		'component' { .component }
		'service' { .service }
		'repository' { .repository }
		'controller' { .controller }
		'configuration' { .configuration }
		'auto_configuration' { .auto_configuration }
		else { .unknown }
	}
}

// ── Scan Result ──

// ScannedBean is the result of comptime inspection of a struct.
// Used to build a BeanDefinition for the container.
pub struct ScannedBean {
pub:
	type_name      string
	component_type ComponentType
	scope          Scope = .singleton
	is_lazy        bool
	qualifier      string
	dependencies   []Dependency
	init_method    string // @[post_construct]
	destroy_method string // @[pre_destroy]
	value_bindings []ValueBinding
	conditions     []string // @[conditional_on_*] attribute strings
}

// ValueBinding represents an @[value('config.key')] annotation on a field.
pub struct ValueBinding {
pub:
	field_name string
	expr       string // e.g., 'app.name' or 'app.name:MyApp'
}

// ── Attribute Parsing Helpers ──

// has_component_attr checks if a list of V attributes contains
// any component-type annotation (component, service, repository, etc.).
pub fn has_component_attr(attrs []string) bool {
	for attr in attrs {
		if attr in [attr_component, attr_service, attr_repository, attr_controller,
			attr_configuration, attr_auto_configuration] {
			return true
		}
	}
	return false
}

// get_component_type extracts the ComponentType from attributes.
pub fn get_component_type(attrs []string) ComponentType {
	for attr in attrs {
		ct := component_type_from_attr(attr)
		if ct != .unknown {
			return ct
		}
	}
	return .unknown
}

// has_attr checks if a specific attribute name is present.
pub fn has_attr(attrs []string, name string) bool {
	return name in attrs
}

// extract_scope parses @[scope('singleton')] from attributes.
pub fn extract_scope(attrs []string) Scope {
	for attr in attrs {
		if attr.starts_with('scope:') || attr.starts_with('scope(') {
			mut val := attr
			if val.starts_with('scope:') {
				val = val['scope:'.len..]
			} else if val.starts_with('scope(') {
				val = val['scope('.len..]
				if val.ends_with(')') {
					val = val[..val.len - 1]
				}
			}
			val = val.trim("'").trim('"').trim_space()
			return scope_from_str(val)
		}
	}
	return .singleton
}

// extract_qualifier parses @[qualifier('name')] from attributes.
pub fn extract_qualifier(attrs []string) string {
	for attr in attrs {
		if attr.starts_with('qualifier:') || attr.starts_with('qualifier(') {
			mut val := attr
			if val.starts_with('qualifier:') {
				val = val['qualifier:'.len..]
			} else if val.starts_with('qualifier(') {
				val = val['qualifier('.len..]
				if val.ends_with(')') {
					val = val[..val.len - 1]
				}
			}
			return val.trim("'").trim('"').trim_space()
		}
	}
	return ''
}

// extract_value_expr parses @[value('config.key')] from attributes.
pub fn extract_value_expr(attrs []string) string {
	for attr in attrs {
		if attr.starts_with('value:') || attr.starts_with('value(') {
			mut val := attr
			if val.starts_with('value:') {
				val = val['value:'.len..]
			} else if val.starts_with('value(') {
				val = val['value('.len..]
				if val.ends_with(')') {
					val = val[..val.len - 1]
				}
			}
			return val.trim("'").trim('"').trim_space()
		}
	}
	return ''
}

// has_method_attr checks if a method has a specific attribute.
pub fn has_method_attr(method_attrs []string, target_attr string) bool {
	return target_attr in method_attrs
}

// ── @DependsOn / @Primary Attribute Parsing ──

// extract_depends_on parses @[depends_on('BeanA','BeanB')] from attributes.
// Spring equivalent: @DependsOn
//
// Returns a list of bean names that this bean depends on for creation order.
pub fn extract_depends_on(attrs []string) []string {
	for attr in attrs {
		if attr.starts_with('depends_on:') || attr.starts_with('depends_on(') {
			mut val := attr
			if val.starts_with('depends_on:') {
				val = val['depends_on:'.len..]
			} else if val.starts_with('depends_on(') {
				val = val['depends_on('.len..]
				if val.ends_with(')') {
					val = val[..val.len - 1]
				}
			}
			val = val.trim("'").trim('"').trim_space()
			// Support comma-separated list: 'BeanA','BeanB' or BeanA,BeanB
			mut names := []string{}
			parts := val.split(',')
			for part in parts {
				trimmed := part.trim_space().trim("'").trim('"')
				if trimmed.len > 0 {
					names << trimmed
				}
			}
			return names
		}
	}
	return []string{}
}

// has_primary_attr checks if @[primary] attribute is present.
// Spring equivalent: @Primary
pub fn has_primary_attr(attrs []string) bool {
	return 'primary' in attrs
}

// extract_parent_name parses @[extends('ParentBean')] from attributes.
// Used for BeanDefinition property inheritance.
pub fn extract_parent_name(attrs []string) string {
	for attr in attrs {
		if attr.starts_with('extends:') || attr.starts_with('extends(') {
			mut val := attr
			if val.starts_with('extends:') {
				val = val['extends:'.len..]
			} else if val.starts_with('extends(') {
				val = val['extends('.len..]
				if val.ends_with(')') {
					val = val[..val.len - 1]
				}
			}
			return val.trim("'").trim('"').trim_space()
		}
	}
	return ''
}

// ── New Scanner Helpers (Spring Boot / Laravel inspired) ──

// has_conditional_attr checks if any @[conditional_on_*] attribute is present.
pub fn has_conditional_attr(attrs []string) bool {
	for attr in attrs {
		if attr.starts_with('conditional_on_') {
			return true
		}
	}
	return false
}

// extract_conditions extracts all @[conditional_on_*] attributes from a list.
// Returns the raw attribute strings, which can be parsed by parse_conditions().
pub fn extract_conditions(attrs []string) []string {
	mut conditions := []string{}
	for attr in attrs {
		if attr.starts_with('conditional_on_') {
			conditions << attr
		}
	}
	return conditions
}

// is_required checks if an @[autowired] field also has @[required] annotation.
// Required dependencies must be satisfied; optional ones are silently skipped.
// Spring equivalent: @Autowired(required = true/false)
pub fn is_required(attrs []string) bool {
	for attr in attrs {
		if attr == 'required' {
			return true
		}
	}
	return false // @[autowired] is required by default
}

// has_event_listener checks if a method has @[event_listener] attribute.
// Spring equivalent: @EventListener
pub fn has_event_listener(attrs []string) bool {
	return 'event_listener' in attrs
}

// extract_scheduled_expr parses @[scheduled('cron')] from attributes.
// Spring equivalent: @Scheduled(cron = "0 0 * * *")
pub fn extract_scheduled_expr(attrs []string) string {
	for attr in attrs {
		if attr.starts_with('scheduled:') || attr.starts_with('scheduled(') {
			mut val := attr
			if val.starts_with('scheduled:') {
				val = val['scheduled:'.len..]
			} else if val.starts_with('scheduled(') {
				val = val['scheduled('.len..]
				if val.ends_with(')') {
					val = val[..val.len - 1]
				}
			}
			return val.trim("'").trim('"').trim_space()
		}
	}
	return ''
}

// extract_cacheable_key parses @[cacheable('key_pattern')] from attributes.
// Spring equivalent: @Cacheable(key = "#id")
pub fn extract_cacheable_key(attrs []string) string {
	for attr in attrs {
		if attr.starts_with('cacheable:') || attr.starts_with('cacheable(') {
			mut val := attr
			if val.starts_with('cacheable:') {
				val = val['cacheable:'.len..]
			} else if val.starts_with('cacheable(') {
				val = val['cacheable('.len..]
				if val.ends_with(')') {
					val = val[..val.len - 1]
				}
			}
			return val.trim("'").trim('"').trim_space()
		}
	}
	return ''
}

// ── @Configuration + @Bean Model ──
//
// Spring equivalent: @Configuration class with @Bean methods.
// Provides a structured model for annotation-driven configuration classes.

// BeanMethod represents a method annotated with @[bean] inside a @[configuration] class.
// Spring equivalent: @Bean method
pub struct BeanMethod {
pub:
	method_name string   // V method name
	bean_name   string   // resulting bean type_name (defaults to method_name)
	attrs       []string // method-level attributes (scope, primary, depends_on, etc.)
}

// new_bean_method creates a BeanMethod from a method name and attributes.
pub fn new_bean_method(method_name string, attrs []string) BeanMethod {
	// Extract bean name from @[bean('CustomName')] if present, else use method_name
	mut bean_name := method_name
	for attr in attrs {
		if attr.starts_with('bean:') || attr.starts_with('bean(') {
			mut val := attr
			if val.starts_with('bean:') {
				val = val['bean:'.len..]
			} else if val.starts_with('bean(') {
				val = val['bean('.len..]
				if val.ends_with(')') {
					val = val[..val.len - 1]
				}
			}
			custom_name := val.trim("'").trim('"').trim_space()
			if custom_name.len > 0 {
				bean_name = custom_name
			}
			break
		}
	}
	return BeanMethod{
		method_name: method_name
		bean_name:   bean_name
		attrs:       attrs.clone()
	}
}

// scope returns the scope for this bean method.
pub fn (bm &BeanMethod) scope() Scope {
	return extract_scope(bm.attrs)
}

// is_primary returns whether this bean method produces a primary bean.
pub fn (bm &BeanMethod) is_primary() bool {
	return has_primary_attr(bm.attrs)
}

// depends_on returns the explicit dependencies for this bean method.
pub fn (bm &BeanMethod) depends_on() []string {
	return extract_depends_on(bm.attrs)
}

// ConfigurationClass represents a @[configuration] class with @[bean] methods.
// Spring equivalent: @Configuration class
pub struct ConfigurationClass {
pub mut:
	type_name    string       // struct name
	bean_methods []BeanMethod // @[bean] methods found in this class
	attrs        []string     // class-level attributes
}

// new_configuration_class creates a ConfigurationClass.
pub fn new_configuration_class(type_name string, attrs []string) ConfigurationClass {
	return ConfigurationClass{
		type_name:    type_name
		bean_methods: []BeanMethod{}
		attrs:        attrs.clone()
	}
}

// add_bean_method adds a @[bean] method to the configuration class.
pub fn (mut cc ConfigurationClass) add_bean_method(method BeanMethod) {
	cc.bean_methods << method
}

// bean_count returns the number of @[bean] methods in this configuration.
pub fn (cc &ConfigurationClass) bean_count() int {
	return cc.bean_methods.len
}

// has_bean_attr checks if a list of method attributes contains @[bean].
pub fn has_bean_attr(attrs []string) bool {
	for attr in attrs {
		if attr == 'bean' || attr.starts_with('bean:') || attr.starts_with('bean(') {
			return true
		}
	}
	return false
}
