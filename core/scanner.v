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
// Handles both V-normalized forms:
//   @[value: 'app.name']  → attr = "value: 'app.name'"  → returns "app.name"
//   @[value('app.name')]  → attr = "value('app.name')"  → returns "app.name"
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
			// Trim space first so surrounding quotes are at the edges,
			// then strip matching quotes, then trim any inner space.
			return val.trim_space().trim("'").trim('"').trim_space()
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
			// Trim spaces first so that surrounding quotes become the
			// outermost characters and can be stripped in one pass.
			return val.trim_space().trim("'\"")
		}
	}
	return ''
}

// ── @[scheduled] Comptime Scanning (Task C4) ──
//
// Spring equivalent: @Scheduled annotation post-processor.
//
// V comptime scans type T's methods at compile time for @[scheduled('cron')]
// attributes and returns ScheduledTaskInfo descriptors. This is the
// compile-time equivalent of Spring's ScheduledAnnotationBeanPostProcessor.
//
// The existing `extract_scheduled_expr(attrs)` helper is reused to parse the
// cron expression from each method's attribute list — it handles both
// V-normalized forms (`scheduled: 'expr'` and `scheduled('expr')`).

// ScheduledTaskInfo describes a single @[scheduled] method discovered via
// comptime scanning of type T.
pub struct ScheduledTaskInfo {
pub:
	method_name string
	cron_expr   string
}

// extract_scheduled_methods scans type T at compile time for methods annotated
// with @[scheduled('cron')]. Returns a list of ScheduledTaskInfo descriptors
// containing the method name and parsed cron expression.
//
// Spring equivalent: @Scheduled annotation discovery.
//
// V comptime note: method-level attributes are inspected via `method.attrs`
// inside `$for method in T.methods`. The cron expression is parsed by the
// existing `extract_scheduled_expr(attrs)` helper which handles both
// `scheduled('...')` and `scheduled: '...'` forms.
//
// Usage:
//   tasks := core.extract_scheduled_methods[MyService]()
//   for t in tasks {
//       println('${t.method_name} -> ${t.cron_expr}')
//   }
pub fn extract_scheduled_methods[T]() []ScheduledTaskInfo {
	mut tasks := []ScheduledTaskInfo{}
	$for method in T.methods {
		cron_expr := extract_scheduled_expr(method.attrs)
		if cron_expr.len > 0 {
			tasks << ScheduledTaskInfo{
				method_name: method.name
				cron_expr:   cron_expr
			}
		}
	}
	return tasks
}

// dispatch_scheduled_method invokes the method named `method_name` on the
// bean of type T located at `bean_ptr`. It is a top-level generic function
// (NOT a closure) so that the comptime type `T` and the `$for method` loop
// variable are accessible in its body — V 0.5.1 does not propagate comptime
// variables into nested closures.
//
// The runtime `if method_name == method.name` comparison is generated once
// per method by the unrolled `$for` loop; the matching branch calls
// `bean.$method()` which is resolved at compile time. This yields a
// type-safe, zero-reflection dispatcher.
//
// Used by `ApplicationContext.register_scheduled[T]` to build scheduled-task
// callbacks: the callback closure captures a function pointer to the
// monomorphized `dispatch_scheduled_method[T]` and calls it with the bean
// pointer and method name.
pub fn dispatch_scheduled_method[T](bean_ptr voidptr, method_name string) ! {
	mut bean := unsafe { &T(bean_ptr) }
	$for method in T.methods {
		if method_name == method.name {
			bean.$method()
		}
	}
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
	method_name  string   // V method name
	bean_name    string   // resulting bean type_name (defaults to method_name)
	attrs        []string // method-level attributes (scope, primary, depends_on, etc.)
	arg_count    int      // number of method parameters (Task A3)
	config_class string   // the @[configuration] class this method belongs to (Task A3)
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

// ── @[auto_configuration] Comptime Scanning (Task A1) ──
//
// Spring Boot equivalent: AutoConfigurationImportSelector selecting
// @AutoConfiguration-annotated classes from the classpath.
//
// V comptime can only inspect types in the current compilation unit, so
// "auto-discovery" is realized as a contract-enforcing helper: the user
// calls `extract_auto_configuration[T]()` (or the higher-level
// `AutoConfigurationManager.register_from_comptime[T]()`) for each
// candidate type at the bootstrap site. The comptime check enforces that
// T carries the `@[auto_configuration]` attribute, refusing non-annotated
// types — this is the "auto" guarantee (no manual type_name strings).
//
// V 0.5.1 comptime note: struct-level attributes are NOT exposed via
// `T.attrs` (that field does not exist on the comptime type). Instead,
// V provides the `$for attr in T.attributes { ... }` loop, where each
// `attr` is a `builtin.VAttribute` with `.name`, `.has_arg`, `.arg`,
// and `.kind` fields. We use this to detect `@[auto_configuration]`.

// extract_auto_configuration returns true if type T is annotated with
// `@[auto_configuration]`. This is a pure comptime check — zero runtime
// cost, zero runtime reflection.
//
// Usage:
//   if core.extract_auto_configuration[MyConfig]() {
//       // T is an auto-configuration source
//   }
pub fn extract_auto_configuration[T]() bool {
	mut found := false
	$for attr in T.attributes {
		if attr.name == attr_auto_configuration {
			found = true
		}
	}
	return found
}

// extract_auto_configuration_attrs returns the list of struct-level
// attribute names for type T (comptime). Useful for inspecting the full
// annotation set — e.g. parsing `@[conditional_on_*]` annotations
// alongside `@[auto_configuration]`.
//
// Each returned string is the bare attribute name (e.g. 'auto_configuration',
// 'conditional_on_profile'). Arguments are available via the comptime
// `attr.arg` / `attr.has_arg` fields inside the `$for` loop, but for the
// common case of condition parsing we re-derive the full attribute string
// in `register_from_comptime[T]()` below.
pub fn extract_auto_configuration_attrs[T]() []string {
	mut attrs := []string{}
	$for attr in T.attributes {
		if attr.has_arg {
			// Normalize to the 'name:arg' form expected by parse_conditions()
			// and the extract_* helpers in this file.
			attrs << '${attr.name}:${attr.arg}'
		} else {
			attrs << attr.name
		}
	}
	return attrs
}

// auto_configuration_type_name returns the V type name for T as a string.
// Wraps `T.name` so callers do not depend on comptime internals directly.
pub fn auto_configuration_type_name[T]() string {
	return T.name
}

// ── @[configuration] + @[bean] Comptime Scanning (Task A3) ──
//
// Spring equivalent: @Configuration class with @Bean methods.
//
// V comptime note: struct-level attributes are inspected via
// `$for attr in T.attributes { ... }` (same as Task A1). Method-level
// attributes are inspected via `method.attrs` inside `$for method in T.methods`.
//
// V 0.5.1 comptime limitation: `method.return_type` and `method.args[].typ`
// are integer type indices, NOT type-name strings. To obtain the return type
// name as a string, we call `t.$method()` inside the `$for` loop and use
// `typeof(result).name`. This only works for 0-arg methods; for methods with
// args, the caller must use the type-parameterized registration helpers
// (`register_bean_method_factory[T, R]` / `register_bean_method_with_dep[T, R, D]`)
// which use `$if method.return_type is R` to branch at compile time.

// extract_configuration returns true if type T is annotated with
// `@[configuration]`. This is a pure comptime check — zero runtime cost.
//
// Usage:
//   if core.extract_configuration[MyConfig]() {
//       // T is a configuration class
//   }
pub fn extract_configuration[T]() bool {
	mut found := false
	$for attr in T.attributes {
		if attr.name == attr_configuration {
			found = true
		}
	}
	return found
}

// extract_configuration_attrs returns the list of struct-level attribute names
// for type T (comptime). Useful for inspecting conditional annotations alongside
// `@[configuration]`.
pub fn extract_configuration_attrs[T]() []string {
	mut attrs := []string{}
	$for attr in T.attributes {
		if attr.has_arg {
			attrs << '${attr.name}:${attr.arg}'
		} else {
			attrs << attr.name
		}
	}
	return attrs
}

// extract_bean_methods scans type T at compile time for methods annotated with
// `@[bean]`. Returns a list of BeanMethod descriptors containing the method
// name, bean name, attributes, argument count, and the configuration class name.
//
// Spring equivalent: @Bean method discovery in @Configuration classes.
//
// V comptime note: `method.return_type` and `method.args[].typ` are integer
// type indices, not strings. The `return_type` and `param_types` fields are
// left empty here — they are populated by the type-parameterized registration
// helpers which use `$if method.return_type is R` to determine types at
// compile time. The `arg_count` field IS available and is used to select
// the appropriate registration helper (0-arg vs 1-arg).
//
// Usage:
//   methods := core.extract_bean_methods[MyConfig]()
//   for m in methods {
//       println('${m.method_name} (${m.arg_count} args)')
//   }
pub fn extract_bean_methods[T]() []BeanMethod {
	mut methods := []BeanMethod{}
	$for method in T.methods {
		// Check if method has @[bean] attribute
		mut has_bean := false
		for attr in method.attrs {
			if attr == attr_bean || attr.starts_with('bean:') || attr.starts_with('bean(') {
				has_bean = true
			}
		}
		if has_bean {
			bm := new_bean_method(method.name, method.attrs)
			methods << BeanMethod{
				method_name: bm.method_name
				bean_name:   bm.bean_name
				attrs:       bm.attrs.clone()
				arg_count:   method.args.len
				config_class: T.name
			}
		}
	}
	return methods
}

// configuration_type_name returns the V type name for T as a string.
// Wraps `T.name` so callers do not depend on comptime internals directly.
pub fn configuration_type_name[T]() string {
	return T.name
}

// ── scan_and_register[T]() — Compile-Time Auto-Registration ──
//
// Spring equivalent: @ComponentScan + AnnotationConfigApplicationContext
//
// Scans type T at compile time for component-type annotations
// (@[component], @[service], @[repository], @[controller]) and
// automatically creates a BeanDefinition with all scanned metadata,
// then registers it with the ApplicationContext.
//
// This is the one-stop-shop for annotation-driven bean registration:
//   - Struct-level annotations → component type, scope, lazy, qualifier, depends_on
//   - Field-level annotations → @[autowired] dependencies, @[value] config bindings
//   - Method-level annotations → @[post_construct], @[pre_destroy] lifecycle
//
// Usage:
//   @[service]
//   pub struct UserService {
//       @[autowired]
//       repo &UserRepository
//       @[value: 'app.name']
//       app_name string
//   }
//
//   core.scan_and_register[UserService](mut ctx)!
//   // ↑ equivalent to manually creating BeanDefinition + register + lifecycle
pub fn scan_and_register[T](mut ctx ApplicationContext) ! {
	// 1) Scan struct-level annotations
	mut component_type := ComponentType.unknown
	mut scope_val := Scope.singleton
	mut is_lazy := false
	mut qualifier_name := ''
	mut depends_on_list := []string{}
	mut is_component := false

	$for attr in T.attributes {
		$if attr.name == attr_component {
			component_type = .component
			is_component = true
		} $else $if attr.name == attr_service {
			component_type = .service
			is_component = true
		} $else $if attr.name == attr_repository {
			component_type = .repository
			is_component = true
		} $else $if attr.name == attr_controller {
			component_type = .controller
			is_component = true
		} $else $if attr.name == attr_scope {
			$if attr.has_arg {
				scope_val = scope_from_str(attr.arg.trim("'\""))
			}
		} $else $if attr.name == attr_lazy {
			is_lazy = true
		} $else $if attr.name == attr_qualifier {
			$if attr.has_arg {
				qualifier_name = attr.arg.trim("'\"")
			}
		} $else $if attr.name == attr_depends_on {
			$if attr.has_arg {
				parts := attr.arg.trim("'\"").split(',')
				for part in parts {
					trimmed := part.trim_space().trim("'\"")
					if trimmed.len > 0 {
						depends_on_list << trimmed
					}
				}
			}
		}
	}

	if !is_component {
		return error('scan_and_register: type ${T.name} is not annotated with @[component]/@[service]/@[repository]/@[controller] / 类型 ${T.name} 未标记组件注解')
	}

	// 2) Scan field-level annotations
	mut dependencies := []Dependency{}
	mut value_bindings := []ValueBinding{}

	$for field in T.fields {
		mut has_autowired := false
		mut field_qualifier := ''
		mut is_required_field := true
		for attr in field.attrs {
			if attr == attr_autowired {
				has_autowired = true
			}
			if attr.starts_with('qualifier:') || attr.starts_with('qualifier(') {
				field_qualifier = extract_qualifier(field.attrs)
			}
			if attr == attr_required {
				is_required_field = true
			}
		}
		if has_autowired {
			dependencies << Dependency{
				type_name: field.name
				qualifier: field_qualifier
				is_required: is_required_field
			}
		}

		value_key := extract_value_expr(field.attrs)
		if value_key.len > 0 {
			value_bindings << ValueBinding{
				field_name: field.name
				expr:       value_key
			}
		}
	}

	// 3) Scan method-level annotations
	mut init_method := ''
	mut destroy_method := ''

	$for method in T.methods {
		for attr in method.attrs {
			if attr == attr_post_construct && init_method.len == 0 {
				init_method = method.name
			}
			if attr == attr_pre_destroy && destroy_method.len == 0 {
				destroy_method = method.name
			}
		}
	}

	// 4) Build and register BeanDefinition
	type_name := T.name
	bean_name := if qualifier_name.len > 0 { qualifier_name } else { type_name }

	mut def := new_bean_definition(bean_name)
	def.component_type = component_type
	def.scope = scope_val
	def.is_lazy = is_lazy
	def.dependencies = dependencies
	def.value_bindings = value_bindings
	def.init_method = init_method
	def.destroy_method = destroy_method
	def.depends_on = depends_on_list

	ctx.register(def) or {
		return error('scan_and_register: failed to register ${bean_name}: ${err} / 注册 ${bean_name} 失败: ${err}')
	}
}

// ── scan_component_info[T]() — Lightweight Component Scan ──
//
// Returns a ScannedBean descriptor without registering anything.
// Useful for inspection, validation, or custom registration logic.
//
// Usage:
//   info := core.scan_component_info[UserService]()
//   println('${info.type_name} is a ${info.component_type} with ${info.dependencies.len} deps')
pub fn scan_component_info[T]() ScannedBean {
	mut component_type := ComponentType.unknown
	mut scope_val := Scope.singleton
	mut is_lazy := false
	mut qualifier_name := ''
	mut depends_on_list := []string{}
	mut is_component := false

	$for attr in T.attributes {
		$if attr.name == attr_component {
			component_type = .component
			is_component = true
		} $else $if attr.name == attr_service {
			component_type = .service
			is_component = true
		} $else $if attr.name == attr_repository {
			component_type = .repository
			is_component = true
		} $else $if attr.name == attr_controller {
			component_type = .controller
			is_component = true
		} $else $if attr.name == attr_scope {
			$if attr.has_arg {
				scope_val = scope_from_str(attr.arg.trim("'\""))
			}
		} $else $if attr.name == attr_lazy {
			is_lazy = true
		} $else $if attr.name == attr_qualifier {
			$if attr.has_arg {
				qualifier_name = attr.arg.trim("'\"")
			}
		} $else $if attr.name == attr_depends_on {
			$if attr.has_arg {
				parts := attr.arg.trim("'\"").split(',')
				for part in parts {
					trimmed := part.trim_space().trim("'\"")
					if trimmed.len > 0 {
						depends_on_list << trimmed
					}
				}
			}
		}
	}

	mut dependencies := []Dependency{}
	mut value_bindings := []ValueBinding{}
	mut init_method := ''
	mut destroy_method := ''

	$for field in T.fields {
		mut has_autowired := false
		mut field_qualifier := ''
		mut is_required_field := true
		for attr in field.attrs {
			if attr == attr_autowired {
				has_autowired = true
			}
			if attr.starts_with('qualifier:') || attr.starts_with('qualifier(') {
				field_qualifier = extract_qualifier(field.attrs)
			}
			if attr == attr_required {
				is_required_field = true
			}
		}
		if has_autowired {
			dependencies << Dependency{
				type_name: field.name
				qualifier: field_qualifier
				is_required: is_required_field
			}
		}
		value_key := extract_value_expr(field.attrs)
		if value_key.len > 0 {
			value_bindings << ValueBinding{
				field_name: field.name
				expr:       value_key
			}
		}
	}

	$for method in T.methods {
		for attr in method.attrs {
			if attr == attr_post_construct && init_method.len == 0 {
				init_method = method.name
			}
			if attr == attr_pre_destroy && destroy_method.len == 0 {
				destroy_method = method.name
			}
		}
	}

	return ScannedBean{
		type_name:      T.name
		component_type: component_type
		scope:          scope_val
		is_lazy:        is_lazy
		qualifier:      qualifier_name
		dependencies:   dependencies
		init_method:    init_method
		destroy_method: destroy_method
		value_bindings: value_bindings
		conditions:     depends_on_list
	}
}
