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
