module core

// condition.v - Conditional Bean Registration (Spring @Conditional inspired)
//
// Provides compile-time and runtime conditions for bean registration.
// A bean is only registered if all its conditions are satisfied.
//
// Supported conditions:
//   @[conditional_on_profile('prod')]              — only if profile is active
//   @[conditional_on_property('key')]             — only if config key exists
//   @[conditional_on_property('key','value')]     — only if config key equals value
//   @[conditional_on_bean('OtherBean')]           — only if another bean is registered
//   @[conditional_on_missing_bean('X')]           — only if bean X is NOT registered
//   @[conditional_on_expression('key==value')]     — only if expression evaluates to true
//   @[conditional_on_class('CacheManager')]        — only if class/struct type exists
//   @[conditional_on_missing_class('RedisCache')]  — only if class/struct type is absent
//
// Conditions are evaluated at registration time (not resolution time).
//
// Spring equivalents:
//   @ConditionalOnProfile       → @Profile
//   @ConditionalOnProperty      → @ConditionalOnProperty
//   @ConditionalOnBean          → @ConditionalOnBean
//   @ConditionalOnMissingBean    → @ConditionalOnMissingBean
//   @ConditionalOnExpression    → @ConditionalOnExpression
//   @ConditionalOnClass         → @ConditionalOnClass

// ── Condition ──

// Condition is the interface for all conditional checks.
pub interface Condition {
	evaluate(mut ctx ConditionContext) bool
}

// ── ConditionContext ──

// ConditionContext provides the context in which conditions are evaluated.
// It gives access to the container, environment, and configuration.
pub struct ConditionContext {
pub mut:
	container  &Container = unsafe { nil }
	profiles   []string
	properties map[string]string
}

// new_condition_context creates a ConditionContext.
pub fn new_condition_context() &ConditionContext {
	return &ConditionContext{
		properties: map[string]string{}
	}
}

// with_container sets the container on the context.
pub fn (mut ctx ConditionContext) with_container(c &Container) &ConditionContext {
	ctx.container = unsafe { c }
	return ctx
}

// with_profiles sets the active profiles.
pub fn (mut ctx ConditionContext) with_profiles(profiles []string) &ConditionContext {
	ctx.profiles = profiles.clone()
	return ctx
}

// with_properties sets the configuration properties.
pub fn (mut ctx ConditionContext) with_properties(props map[string]string) &ConditionContext {
	ctx.properties = props.clone()
	return ctx
}

// ── Built-in Conditions ──

// OnProfileCondition checks if a specific profile is active.
pub struct OnProfileCondition {
pub:
	profile string
}

pub fn (c &OnProfileCondition) evaluate(mut ctx ConditionContext) bool {
	return c.profile in ctx.profiles
}

// OnPropertyCondition checks if a configuration property exists.
pub struct OnPropertyCondition {
pub:
	key              string
	having_value     string // if non-empty, property must equal this value
	match_if_missing bool   // if true, matches when property is absent
}

pub fn (c &OnPropertyCondition) evaluate(mut ctx ConditionContext) bool {
	val := ctx.properties[c.key] or { '' }
	if c.match_if_missing && val.len == 0 {
		return true
	}
	if val.len == 0 {
		return false
	}
	if c.having_value.len > 0 {
		return val == c.having_value
	}
	return true
}

// OnBeanCondition checks if a specific bean is registered.
pub struct OnBeanCondition {
pub:
	bean_type string
}

pub fn (c &OnBeanCondition) evaluate(mut ctx ConditionContext) bool {
	if isnil(ctx.container) {
		return false
	}
	return ctx.container.has(c.bean_type)
}

// OnMissingBeanCondition checks if a specific bean is NOT registered.
pub struct OnMissingBeanCondition {
pub:
	bean_type string
}

pub fn (c &OnMissingBeanCondition) evaluate(mut ctx ConditionContext) bool {
	if isnil(ctx.container) {
		return true // no container → bean is definitely missing
	}
	return !ctx.container.has(c.bean_type)
}

// OnExpressionCondition checks if a property expression evaluates to true.
// Expression format: "key==value", "key!=value", "key", "!key"
//
// Spring equivalent: @ConditionalOnExpression
//
// Examples:
//   @[conditional_on_expression('cache.enabled==true')]
//   @[conditional_on_expression('app.debug==true')]
//   @[conditional_on_expression('cache.driver!=memory')]
//   @[conditional_on_expression('app.prod')]          — property exists and is truthy
//   @[conditional_on_expression('!app.debug')]         — property is absent or falsy
pub struct OnExpressionCondition {
pub:
	expression string
}

pub fn (c &OnExpressionCondition) evaluate(mut ctx ConditionContext) bool {
	return evaluate_expression(c.expression, ctx.properties)
}

// OnClassCondition checks if a class/struct type is available.
// V is a compiled language with no runtime class loading, so "class existence"
// is evaluated by checking whether a bean of that type is registered in the
// container (the practical approach noted in the framework spec). This makes
// the condition perform a real check instead of unconditionally returning true.
//
// Spring equivalent: @ConditionalOnClass
pub struct OnClassCondition {
pub:
	class_name string
}

pub fn (c &OnClassCondition) evaluate(mut ctx ConditionContext) bool {
	// Real class existence check: query the container for a bean of that type.
	// If no container is available, the condition cannot be verified → false.
	if isnil(ctx.container) {
		return false
	}
	return ctx.container.has_definition(c.class_name) || ctx.container.has_instance(c.class_name)
}

// OnMissingClassCondition checks if a class/struct type is NOT available.
// This is the negation of OnClassCondition: it returns true when no bean of
// the given type is registered in the container.
//
// Spring equivalent: @ConditionalOnMissingClass
pub struct OnMissingClassCondition {
pub:
	class_name string
}

pub fn (c &OnMissingClassCondition) evaluate(mut ctx ConditionContext) bool {
	if isnil(ctx.container) {
		return true // no container → cannot confirm class exists → treat as missing
	}
	return !(ctx.container.has_definition(c.class_name) || ctx.container.has_instance(c.class_name))
}

// OnCloudPlatformCondition checks if running on a specific cloud platform.
// Inspired by Spring Boot's @ConditionalOnCloudPlatform.
pub struct OnCloudPlatformCondition {
pub:
	platform string // 'aws', 'gcp', 'azure', 'aliyun', 'none'
}

pub fn (c &OnCloudPlatformCondition) evaluate(mut ctx ConditionContext) bool {
	val := ctx.properties['cloud.platform'] or { 'none' }
	return val == c.platform
}

// ── Expression Evaluator ──

// evaluate_expression evaluates a simple property expression.
// Supports: key==value, key!=value, key (truthy), !key (falsy)
fn evaluate_expression(expr string, properties map[string]string) bool {
	trimmed := expr.trim_space()

	// NOT prefix: !key
	if trimmed.starts_with('!') {
		key := trimmed[1..].trim_space()
		val := properties[key] or { '' }
		return val.len == 0 || val == 'false' || val == '0'
	}

	// Equality: key==value
	if eq_pos := trimmed.index('==') {
		key := trimmed[..eq_pos].trim_space()
		value := trimmed[eq_pos + 2..].trim_space()
		val := properties[key] or { '' }
		return val == value
	}

	// Inequality: key!=value
	if ne_pos := trimmed.index('!=') {
		key := trimmed[..ne_pos].trim_space()
		value := trimmed[ne_pos + 2..].trim_space()
		val := properties[key] or { '' }
		return val != value
	}

	// Simple key existence (truthy check)
	val := properties[trimmed] or { '' }
	return val.len > 0 && val != 'false' && val != '0'
}

// ── Condition Parsing ──

// parse_conditions extracts conditions from V struct attributes.
// Returns a list of Condition objects based on @[conditional_*] attributes.
pub fn parse_conditions(attrs []string, mut ctx ConditionContext) []&Condition {
	mut conditions := []&Condition{}

	for attr in attrs {
		if attr.starts_with('conditional_on_profile:')
			|| attr.starts_with('conditional_on_profile(') {
			profile := extract_conditional_arg(attr)
			conditions << &Condition(&OnProfileCondition{
				profile: profile
			})
		} else if attr.starts_with('conditional_on_property:')
			|| attr.starts_with('conditional_on_property(') {
			// Support: conditional_on_property('key') or conditional_on_property('key','value')
			arg := extract_conditional_arg(attr)
			parts := arg.split_nth(',', 2)
			if parts.len == 2 {
				key := parts[0].trim(' ').trim("'").trim('"')
				having_value := parts[1].trim(' ').trim("'").trim('"')
				conditions << &Condition(&OnPropertyCondition{
					key:          key
					having_value: having_value
				})
			} else {
				conditions << &Condition(&OnPropertyCondition{
					key: parts[0].trim(' ').trim("'").trim('"')
				})
			}
		} else if attr.starts_with('conditional_on_bean:')
			|| attr.starts_with('conditional_on_bean(') {
			bean_type := extract_conditional_arg(attr)
			conditions << &Condition(&OnBeanCondition{
				bean_type: bean_type
			})
		} else if attr.starts_with('conditional_on_missing_bean:')
			|| attr.starts_with('conditional_on_missing_bean(') {
			bean_type := extract_conditional_arg(attr)
			conditions << &Condition(&OnMissingBeanCondition{
				bean_type: bean_type
			})
		} else if attr.starts_with('conditional_on_expression:')
			|| attr.starts_with('conditional_on_expression(') {
			expression := extract_conditional_arg(attr)
			conditions << &Condition(&OnExpressionCondition{
				expression: expression
			})
		} else if attr.starts_with('conditional_on_class:')
			|| attr.starts_with('conditional_on_class(') {
			class_name := extract_conditional_arg(attr)
			conditions << &Condition(&OnClassCondition{
				class_name: class_name
			})
		} else if attr.starts_with('conditional_on_missing_class:')
			|| attr.starts_with('conditional_on_missing_class(') {
			class_name := extract_conditional_arg(attr)
			conditions << &Condition(&OnMissingClassCondition{
				class_name: class_name
			})
		} else if attr.starts_with('conditional_on_cloud_platform:')
			|| attr.starts_with('conditional_on_cloud_platform(') {
			platform := extract_conditional_arg(attr)
			conditions << &Condition(&OnCloudPlatformCondition{
				platform: platform
			})
		}
	}

	return conditions
}

// evaluate_conditions checks all conditions and returns true if all pass.
// any_condition_matches checks if any condition passes (OR logic).
// Useful for "activate if ANY of these conditions are met" scenarios.
pub fn any_condition_matches(conditions []&Condition, mut ctx ConditionContext) bool {
	for c in conditions {
		if c.evaluate(mut ctx) {
			return true
		}
	}
	return false
}

pub fn evaluate_conditions(conditions []&Condition, mut ctx ConditionContext) bool {
	for c in conditions {
		if !c.evaluate(mut ctx) {
			return false
		}
	}
	return true
}

// extract_conditional_arg extracts the argument from a conditional attribute.
fn extract_conditional_arg(attr string) string {
	// Handle both colon and paren syntax
	if colon_pos := attr.index(':') {
		mut val := attr[colon_pos + 1..]
		if val.starts_with('(') {
			val = val[1..]
		}
		if val.ends_with(')') {
			val = val[..val.len - 1]
		}
		return val.trim("'").trim('"').trim_space()
	}
	if paren_pos := attr.index('(') {
		mut val := attr[paren_pos + 1..]
		if val.ends_with(')') {
			val = val[..val.len - 1]
		}
		return val.trim("'").trim('"').trim_space()
	}
	return ''
}
