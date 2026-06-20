module core

// auto_configuration.v - Auto-Configuration (Spring Boot AutoConfiguration inspired)
//
// Provides automatic bean configuration based on classpath conditions,
// active profiles, and property settings. This is the Photon equivalent
// of Spring Boot's @EnableAutoConfiguration mechanism.
//
// Spring Boot equivalent: org.springframework.boot.autoconfigure.*
// Laravel equivalent: Package auto-discovery (config/app.php providers)
//
// Key concepts:
//   - @[auto_configuration] — marks a struct as an auto-configuration source
//   - @[conditional_on_profile('prod')] — only activate in production
//   - @[conditional_on_property('cache.driver')] — only activate if property exists
//   - @[conditional_on_bean('CacheManager')] — only activate if bean exists
//   - @[conditional_on_missing_bean('CacheManager')] — only activate if bean is absent
//
// Auto-configuration is processed AFTER user-defined beans, allowing
// user beans to take precedence (the "user has the final word" principle).
import sync

// ── AutoConfiguration ──

// AutoConfiguration is the interface for auto-configuration classes.
// An auto-configuration class provides bean definitions that are
// conditionally registered based on the application's state.
//
// Spring equivalent: @AutoConfiguration
// Laravel equivalent: Service Provider with deferred loading
pub interface AutoConfiguration {
	// configure registers beans into the application context.
	// Called during refresh() after user beans are registered.
	configure(mut ctx ApplicationContext) !

	// order returns the priority of this auto-configuration.
	// Lower values are processed first. Default: 0.
	order() int
}

// ── AutoConfigurationCandidate ──

// AutoConfigurationCandidate describes a potential auto-configuration
// that can be conditionally loaded.
pub struct AutoConfigurationCandidate {
pub:
	type_name  string
	config     &AutoConfiguration = unsafe { nil }
	conditions []&Condition
	order_     int
}

// ── AutoConfigurationManager ──

// AutoConfigurationManager manages the discovery and loading of auto-configurations.
// It is responsible for:
//   1. Scanning for @[auto_configuration] classes
//   2. Evaluating conditions
//   3. Applying configurations in order
//
// Spring equivalent: AutoConfigurationImportSelector
// Laravel equivalent: PackageManifest (auto-discovery)
@[heap]
pub struct AutoConfigurationManager {
pub mut:
	candidates []AutoConfigurationCandidate
	mu         sync.RwMutex
}

// new_auto_configuration_manager creates an empty AutoConfigurationManager.
pub fn new_auto_configuration_manager() &AutoConfigurationManager {
	return &AutoConfigurationManager{
		candidates: []AutoConfigurationCandidate{}
	}
}

// add_candidate adds an auto-configuration candidate.
pub fn (mut m AutoConfigurationManager) add_candidate(candidate AutoConfigurationCandidate) {
	m.mu.@lock()
	defer { m.mu.unlock() }
	m.candidates << candidate
}

// add_auto_configuration registers an AutoConfiguration with optional conditions.
pub fn (mut m AutoConfigurationManager) add_auto_configuration(type_name string, config &AutoConfiguration, conditions []&Condition) {
	candidate := AutoConfigurationCandidate{
		type_name:  type_name
		config:     unsafe { config }
		conditions: conditions
		order_:     config.order()
	}
	m.add_candidate(candidate)
}

// apply_all evaluates all candidates and applies those whose conditions are met.
// Candidates are applied in order (lower order_ first).
pub fn (mut m AutoConfigurationManager) apply_all(mut ctx ApplicationContext) ! {
	m.mu.rlock()
	mut candidates := m.candidates.clone()
	m.mu.runlock()

	// Sort by order
	candidates.sort_with_compare(fn (a &AutoConfigurationCandidate, b &AutoConfigurationCandidate) int {
		if a.order_ < b.order_ {
			return -1
		} else if a.order_ > b.order_ {
			return 1
		}
		return 0
	})

	mut cond_ctx := new_condition_context()
	cond_ctx = cond_ctx.with_container(ctx.container)
	cond_ctx = cond_ctx.with_profiles(ctx.environment.get_active_profiles())
	cond_ctx = cond_ctx.with_properties(ctx.environment.properties.clone())

	for candidate in candidates {
		// Evaluate all conditions
		if evaluate_conditions(candidate.conditions, mut cond_ctx) {
			if !isnil(candidate.config) {
				candidate.config.configure(mut ctx) or {
					eprintln('[AutoConfiguration] failed for "${candidate.type_name}": ${err}')
				}
			}
		}
	}
}

// candidate_count returns the number of registered candidates.
pub fn (mut m AutoConfigurationManager) candidate_count() int {
	m.mu.rlock()
	defer { m.mu.runlock() }
	return m.candidates.len
}

// list returns a snapshot of all registered auto-configuration candidates.
// The returned slice is a copy — callers may iterate it without holding the
// manager's lock.
//
// Spring equivalent: AutoConfigurationImportSelector.getAutoConfigurations()
pub fn (mut m AutoConfigurationManager) list() []AutoConfigurationCandidate {
	m.mu.rlock()
	defer { m.mu.runlock() }
	return m.candidates.clone()
}

// has_candidate returns true if a candidate with the given type_name is
// registered. Used by tests and diagnostics to verify comptime registration.
pub fn (mut m AutoConfigurationManager) has_candidate(type_name string) bool {
	m.mu.rlock()
	defer { m.mu.runlock() }
	for c in m.candidates {
		if c.type_name == type_name {
			return true
		}
	}
	return false
}

// ── Comptime-Driven Registration (Task A1) ──
//
// V comptime can only inspect types in the current compilation unit, so
// cross-module "class-path scanning" (Spring Boot's classpath traversal) is
// impossible. Instead, Photon realizes auto-configuration as a
// contract-enforcing comptime helper: the bootstrap code calls
// `register_from_comptime[T]()` for each candidate type, and the comptime
// check guarantees T carries `@[auto_configuration]` — refusing any
// non-annotated type. This is the "auto" guarantee: no manual type_name
// strings, no runtime reflection, and a compile-time-verified annotation
// contract.
//
// Usage (in the application's bootstrap, before refresh()):
//   ctx.auto_config_manager.register_from_comptime[RedisAutoConfig]()!
//   ctx.auto_config_manager.register_from_comptime[WebMvcAutoConfig]()!
//   ctx.refresh()!  // apply_all() evaluates conditions and invokes configure()

// register_from_comptime registers type T as an auto-configuration candidate
// if (and only if) T is annotated with `@[auto_configuration]`.
//
// The comptime scan extracts:
//   1. The `@[auto_configuration]` attribute — required; refusal returns an error.
//   2. Any `@[conditional_on_*]` attributes — parsed into Condition objects
//      and attached to the candidate. Conditions are later evaluated by
//      apply_all() during refresh().
//
// For Task A1, the candidate is registered with `config = nil` — the
// configuration class itself is recorded as a bean candidate. Task A3 will
// extend this to scan T's `@[bean]` methods and wire them into the container.
//
// Returns an error (with bilingual message) if T lacks the annotation,
// enforcing the auto-configuration contract at compile time.
pub fn (mut m AutoConfigurationManager) register_from_comptime[T]() ! {
	// Comptime check: T MUST carry @[auto_configuration].
	// This is the core of the "auto" guarantee — non-annotated types are refused.
	if !extract_auto_configuration[T]() {
		return error('type "${T.name}" is not annotated with @[auto_configuration]; cannot register as auto-configuration / 类型 "${T.name}" 未标注 @[auto_configuration]，无法注册为自动配置类')
	}

	// Extract the full attribute set (comptime) and parse any conditional
	// annotations into Condition objects. Conditions are evaluated later
	// during apply_all(), NOT at registration time — this mirrors Spring
	// Boot's two-phase model (import → evaluate).
	attrs := extract_auto_configuration_attrs[T]()
	mut cond_ctx := new_condition_context()
	conditions := parse_conditions(attrs, mut cond_ctx)

	candidate := AutoConfigurationCandidate{
		type_name:  T.name
		config:     unsafe { nil } // A1: register the class itself; A3 wires @[bean] methods
		conditions: conditions
		order_:     0 // default order; A3 may extract @[order] if needed
	}
	m.add_candidate(candidate)
}
