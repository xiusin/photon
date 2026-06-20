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
import os

// ── Manifest Filename (Task A5) ──

// auto_configuration_imports_filename is the conventional filename for
// auto-configuration manifest files. Each module that provides
// auto-configurations may ship a file with this name listing the
// fully-qualified class names it contributes.
//
// Spring Boot equivalent:
//   META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports
pub const auto_configuration_imports_filename = 'auto_configuration_imports.v'

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
//   4. Loading manifest imports (Task A5) — declarations of which
//      auto-configuration classes a module contributes
//
// Spring equivalent: AutoConfigurationImportSelector
// Laravel equivalent: PackageManifest (auto-discovery)
@[heap]
pub struct AutoConfigurationManager {
pub mut:
	candidates []AutoConfigurationCandidate
	imports    []string // manifest imports: class names declared in auto_configuration_imports.v files
	mu         sync.RwMutex
}

// new_auto_configuration_manager creates an empty AutoConfigurationManager.
pub fn new_auto_configuration_manager() &AutoConfigurationManager {
	return &AutoConfigurationManager{
		candidates: []AutoConfigurationCandidate{}
		imports:    []string{}
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

// ── @[configuration] + @[bean] Method Registration (Task A3) ──
//
// Spring equivalent: @Configuration class with @Bean methods.
//
// V comptime can only inspect types in the current compilation unit, so
// "class-path scanning" is realized as a contract-enforcing comptime helper:
// the bootstrap code calls `register_bean_methods[T](mut ctx)` for each
// `@[configuration]` class, and the comptime check guarantees T carries
// `@[configuration]` — refusing any non-annotated type.
//
// V 0.5.1 comptime limitation: `t.$method()` inside a `$for method in T.methods`
// loop generates a single call site that must be valid for ALL methods. Methods
// with different argument counts cannot share the same call site. To handle
// this, we use `$if method.return_type is R` to branch at compile time — V only
// generates the method-call code inside a `$if` branch for methods whose return
// type matches R. This requires the caller to know the return type, which is
// provided via the type-parameterized helpers:
//   - `register_bean_method_factory[T, R](mut ctx)` — 0-arg @[bean] methods returning R
//   - `register_bean_method_with_dep[T, R, D](mut ctx)` — 1-arg @[bean] methods
//     returning R, taking a dependency of type D resolved from the container
//
// Usage (in the application's bootstrap, before refresh()):
//   ctx.register_bean_method_factory[AppConfig, DataSource]()!
//   ctx.register_bean_method_with_dep[AppConfig, UserService, DataSource]()!
//   ctx.refresh()!

// register_bean_methods scans type T for @[bean] methods and registers a
// BeanDefinition for each. The configuration class T MUST be annotated with
// `@[configuration]`.
//
// This function registers BeanDefinitions with metadata (bean_name, scope,
// dependencies) but does NOT instantiate the beans — instantiation happens
// during refresh() or when the bean is first resolved. The actual factory
// (calling `t.$method()`) is set up by the type-parameterized helpers below,
// which the user calls once per distinct return type.
//
// Returns an error (with bilingual message) if T lacks `@[configuration]`.
//
// Spring equivalent: @Configuration class processing — registers @Bean
// definitions without instantiating them (lazy until getBean() or refresh()).
pub fn (mut m AutoConfigurationManager) register_bean_methods[T](mut ctx ApplicationContext) ![]BeanMethod {
	// Comptime check: T MUST carry @[configuration].
	if !extract_configuration[T]() {
		return error('type "${T.name}" is not annotated with @[configuration]; cannot register bean methods / 类型 "${T.name}" 未标注 @[configuration]，无法注册 bean 方法')
	}

	methods := extract_bean_methods[T]()
	for method in methods {
		// Build a BeanDefinition for each @[bean] method.
		// The bean_name (from @[bean('CustomName')] or method name) is used
		// as the type_name for registration. Dependencies are inferred from
		// arg_count — the actual dependency type is resolved by the
		// type-parameterized factory helpers at instantiation time.
		mut def := new_bean_definition(method.bean_name)
		def.scope = method.scope()
		def.is_primary = method.is_primary()
		def.depends_on = method.depends_on()
		def.tags = ['configuration', 'bean']
		// Register the definition — conditions (if any) are evaluated by
		// ctx.register() before the definition is stored.
		ctx.register(def) or {
			// If a bean with the same name is already registered, skip it
			// (user beans take precedence — "user has the final word").
			continue
		}
	}
	return methods
}

// register_bean_method_factory registers and instantiates all 0-arg @[bean]
// methods of configuration class T that return type R. The method is called
// at registration time (eager instantiation), and the result is stored as a
// singleton in the container.
//
// V comptime pattern: `$if method.return_type is R` ensures the `t.$method()`
// call is only generated for methods returning R. The `if method.args.len == 0`
// guard further restricts to 0-arg methods. Since V generates the `$if` branch
// only for matching methods, the `t.$method()` call site is valid.
//
// Spring equivalent: @Bean method invocation — the container calls the method
// to produce the bean instance.
//
// Usage:
//   ctx.register_bean_method_factory[AppConfig, DataSource]()!
//   ds := ctx.resolve_typed[DataSource]('datasource')!  // resolve by bean name
pub fn (mut ctx ApplicationContext) register_bean_method_factory[T, R]() ! {
	// Comptime check: T MUST carry @[configuration].
	if !extract_configuration[T]() {
		return error('type "${T.name}" is not annotated with @[configuration] / 类型 "${T.name}" 未标注 @[configuration]')
	}

	$for method in T.methods {
		mut has_bean := false
		for attr in method.attrs {
			if attr == attr_bean || attr.starts_with('bean:') || attr.starts_with('bean(') {
				has_bean = true
			}
		}
		if has_bean {
			$if method.return_type is R {
				if method.args.len == 0 {
					t := T{}
					result := t.$method()
					// Take a typed reference so V's escape analysis heap-allocates
					// `result` (the reference outlives the function via the
					// container's instance map). Using `unsafe { &result }` would
					// hide the escape from V, leaving a dangling stack pointer.
					result_ptr := &result
					bm := new_bean_method(method.name, method.attrs)
					ctx.register_instance(bm.bean_name, result_ptr) or {
						return error('failed to register bean from method "${method.name}" of ${T.name}: ${err} / 注册 bean 失败: 方法 "${method.name}" 于 ${T.name}: ${err}')
					}
					// Also register an alias from the fully-qualified return
					// type name (R.name) to the bean name, so the bean can be
					// resolved by type as well — this is required for
					// dependency resolution in register_bean_method_with_dep
					// (which resolves dependencies by D.name). Silently skip
					// if the alias already exists (idempotent registration).
					ctx.register_alias(R.name, bm.bean_name) or {}
				}
			}
		}
	}
}

// register_bean_method_with_dep registers and instantiates all 1-arg @[bean]
// methods of configuration class T that return type R and take a single
// argument of type D. The dependency D is resolved from the container before
// calling the method, and the result is stored as a singleton.
//
// V comptime pattern: `$if method.return_type is R` restricts to methods
// returning R; `$if method.args[0].typ is D` restricts to methods whose first
// arg is D. The `t.$method(dep)` call is only generated for matching methods.
//
// Spring equivalent: @Bean method with @Autowired parameter — the container
// resolves the dependency and passes it to the method.
//
// Usage:
//   // DataSource must already be registered:
//   ctx.register_bean_method_factory[AppConfig, DataSource]()!
//   // Now register UserService, which depends on DataSource:
//   ctx.register_bean_method_with_dep[AppConfig, UserService, DataSource]()!
pub fn (mut ctx ApplicationContext) register_bean_method_with_dep[T, R, D]() ! {
	// Comptime check: T MUST carry @[configuration].
	if !extract_configuration[T]() {
		return error('type "${T.name}" is not annotated with @[configuration] / 类型 "${T.name}" 未标注 @[configuration]')
	}

	$for method in T.methods {
		mut has_bean := false
		for attr in method.attrs {
			if attr == attr_bean || attr.starts_with('bean:') || attr.starts_with('bean(') {
				has_bean = true
			}
		}
		if has_bean {
			$if method.return_type is R {
				if method.args.len == 1 {
					$if method.args[0].typ is D {
						// Resolve the dependency from the container by type
						// name (D.name). The dependency must already be
						// registered — typically via a prior call to
						// register_bean_method_factory[T, D], which registers
						// an alias from D.name to the dependency's bean name.
						dep_ptr := ctx.container.resolve(D.name) or {
							return error('dependency "${D.name}" not found for bean method "${method.name}" of ${T.name} / 依赖 "${D.name}" 未找到: bean 方法 "${method.name}" 于 ${T.name}')
						}
						dep := unsafe { &D(dep_ptr) }
						dep_value := *dep
						t := T{}
						result := t.$method(dep_value)
						// Take a typed reference so V's escape analysis
						// heap-allocates `result` — see note in
						// register_bean_method_factory above.
						result_ptr := &result
						bm := new_bean_method(method.name, method.attrs)
						ctx.register_instance(bm.bean_name, result_ptr) or {
							return error('failed to register bean from method "${method.name}" of ${T.name}: ${err} / 注册 bean 失败: 方法 "${method.name}" 于 ${T.name}: ${err}')
						}
						// Alias from R.name to bean name — see note in
						// register_bean_method_factory above.
						ctx.register_alias(R.name, bm.bean_name) or {}
					}
				}
			}
		}
	}
}

// register_configuration is the high-level entry point for @[configuration]
// class processing. It:
//   1. Verifies T is annotated with @[configuration]
//   2. Scans T for @[bean] methods and registers BeanDefinitions
//   3. Returns the list of discovered BeanMethod descriptors
//
// After calling this, the user must call the type-parameterized factory helpers
// (`register_bean_method_factory[T, R]` / `register_bean_method_with_dep[T, R, D]`)
// to instantiate the beans, since V comptime requires knowing the return type
// at the call site.
//
// Spring equivalent: @Configuration class registration during context refresh.
//
// Usage:
//   methods := ctx.register_configuration[AppConfig]()!
//   // Then instantiate each bean by return type:
//   ctx.register_bean_method_factory[AppConfig, DataSource]()!
//   ctx.register_bean_method_with_dep[AppConfig, UserService, DataSource]()!
pub fn (mut ctx ApplicationContext) register_configuration[T]() ![]BeanMethod {
	return ctx.auto_config_manager.register_bean_methods[T](mut ctx)
}

// ── Starter Pattern: Manifest Imports (Task A5) ──
//
// Spring Boot equivalent: spring.factories /
//   META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports
// Laravel equivalent: PackageManifest (config/app.php providers auto-discovery)
//
// The Starter pattern lets third-party modules declare which auto-configuration
// classes they contribute via a manifest file named `auto_configuration_imports.v`.
// The manifest is a plain-text file (despite the .v extension, which aids
// discoverability and tooling) with one fully-qualified class name per line:
//
//   # auto_configuration_imports.v
//   # One config class name per line; lines starting with # are comments
//   photon.db.DbAutoConfig
//   photon.db.RedisAutoConfig
//
// V has no runtime class loading, so the manifest is a *declaration of intent*:
// it records which classes a module wishes to contribute. The actual
// registration still happens via comptime (`register_from_comptime[T]()`)
// in the application's bootstrap code. The manifest serves three purposes:
//   1. Documentation — which auto-configs a module provides
//   2. Tooling — a code generator could read manifests and emit bootstrap calls
//   3. Diagnostics — `list_imports()` shows what was declared vs. what was
//      actually registered via comptime (detecting missing registrations)
//
// Modules may also declare their imports programmatically via a `pub const`
// array, which the bootstrap code passes to `register_imports()`:
//
//   // In module db/auto_configuration_imports.v
//   module db
//   pub const auto_configuration_imports = ['DbAutoConfig', 'RedisAutoConfig']
//
//   // In application bootstrap
//   ctx.register_imports(db.auto_configuration_imports)
//   ctx.register_auto_configuration[db.DbAutoConfig]()!
//   ctx.register_auto_configuration[db.RedisAutoConfig]()!

// register_imports registers a list of auto-configuration class names as
// pending manifest imports. This is the programmatic entry point — each
// module can export a `pub const auto_configuration_imports []string` and
// pass it here during bootstrap.
//
// The imports are declarations only — they do NOT create candidates. Actual
// candidate registration requires a separate `register_from_comptime[T]()`
// call for each type. This separation mirrors Spring Boot's two-phase model
// (import → evaluate) and lets diagnostics detect declared-but-unregistered
// configurations.
//
// Thread-safe.
pub fn (mut m AutoConfigurationManager) register_imports(imports []string) {
	for class_name in imports {
		m.register_imported(class_name)
	}
}

// register_imported registers a single auto-configuration class name as a
// pending manifest import.
//
// Thread-safe.
pub fn (mut m AutoConfigurationManager) register_imported(class_name string) {
	m.mu.@lock()
	defer { m.mu.unlock() }
	m.imports << class_name
}

// list_imports returns a snapshot of all registered manifest imports
// (class names declared in manifest files or via register_imports()).
// The returned slice is a copy — callers may iterate it without holding
// the manager's lock.
//
// Spring equivalent: AutoConfigurationImportSelector.getAutoConfigurations()
pub fn (mut m AutoConfigurationManager) list_imports() []string {
	m.mu.rlock()
	defer { m.mu.runlock() }
	return m.imports.clone()
}

// has_import returns true if the given class name has been registered as a
// manifest import. Useful for diagnostics and conditional logic.
pub fn (mut m AutoConfigurationManager) has_import(class_name string) bool {
	m.mu.rlock()
	defer { m.mu.runlock() }
	return class_name in m.imports
}

// import_count returns the number of registered manifest imports.
pub fn (mut m AutoConfigurationManager) import_count() int {
	m.mu.rlock()
	defer { m.mu.runlock() }
	return m.imports.len
}

// clear_imports removes all registered manifest imports. Candidates
// registered via register_from_comptime[T]() are NOT affected.
pub fn (mut m AutoConfigurationManager) clear_imports() {
	m.mu.@lock()
	defer { m.mu.unlock() }
	m.imports.clear()
}

// ── Manifest File Parsing ──

// parse_manifest_content parses the content of an auto_configuration_imports.v
// manifest file and returns the list of class names.
//
// File format (plain text):
//   - One fully-qualified class name per line
//   - Lines starting with # are comments (ignored)
//   - Empty lines and whitespace-only lines are ignored
//   - Leading/trailing whitespace on each class name is trimmed
//
// Example:
//   # Database auto-configurations
//   photon.db.DbAutoConfig
//   photon.db.RedisAutoConfig
//
// This is a pure function (no I/O, no side effects) so it can be unit-tested
// independently of the filesystem.
pub fn parse_manifest_content(content string) []string {
	mut class_names := []string{}
	for line in content.split_into_lines() {
		trimmed := line.trim_space()
		// Skip empty lines
		if trimmed.len == 0 {
			continue
		}
		// Skip comments (lines starting with #)
		if trimmed.starts_with('#') {
			continue
		}
		class_names << trimmed
	}
	return class_names
}

// load_imports_from_manifest reads an auto_configuration_imports.v manifest
// file, parses it, and registers all class names as manifest imports.
//
// Returns the number of class names loaded. Returns an error if the file
// does not exist or cannot be read.
//
// Thread-safe.
pub fn (mut m AutoConfigurationManager) load_imports_from_manifest(path string) !int {
	if !os.exists(path) {
		return error('load_imports_from_manifest: file not found: "${path}" / 文件不存在: "${path}"')
	}
	content := os.read_file(path) or {
		return error('load_imports_from_manifest: failed to read "${path}": ${err} / 读取文件 "${path}" 失败: ${err}')
	}
	class_names := parse_manifest_content(content)
	for class_name in class_names {
		m.register_imported(class_name)
	}
	return class_names.len
}

// scan_manifests recursively scans a directory tree for
// auto_configuration_imports.v manifest files and loads all class names
// from each file found.
//
// This simulates Spring Boot's classpath scanning for
// META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports.
// In V, since there is no runtime classpath, the application points this
// method at a directory containing module subdirectories (e.g., the
// VMODULES path or a project's vendor tree).
//
// Hidden directories (starting with .) are skipped to avoid scanning
// .git, .vmodules, etc.
//
// Returns the total number of class names loaded across all manifest files.
// Returns an error if the path does not exist or is not a directory.
//
// Thread-safe.
pub fn (mut m AutoConfigurationManager) scan_manifests(directory string) !int {
	if !os.exists(directory) {
		return 0
	}
	if !os.is_dir(directory) {
		return error('scan_manifests: "${directory}" is not a directory / "${directory}" 不是目录')
	}
	return m.scan_manifests_dir(directory)
}

// scan_manifests_dir is the recursive helper for scan_manifests().
// It walks the directory tree looking for auto_configuration_imports.v files.
fn (mut m AutoConfigurationManager) scan_manifests_dir(directory string) int {
	mut count := 0
	entries := os.ls(directory) or { return 0 }
	for entry in entries {
		full_path := os.join_path(directory, entry)
		if os.is_dir(full_path) {
			// Skip hidden directories (e.g., .git, .vmodules)
			if entry.starts_with('.') {
				continue
			}
			count += m.scan_manifests_dir(full_path)
		} else if entry == auto_configuration_imports_filename {
			loaded := m.load_imports_from_manifest(full_path) or {
				eprintln('[AutoConfiguration] failed to load manifest "${full_path}": ${err}')
				0
			}
			count += loaded
		}
	}
	return count
}
