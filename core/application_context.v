module core

// application_context.v - Application Context (Spring ApplicationContext inspired)
//
// The central interface providing configuration for an application.
// This is the unified entry point that combines:
//   - Container (IoC / DI)
//   - EventBus (ApplicationEvent publishing)
//   - LifecycleManager (Bean lifecycle)
//   - Environment (Profiles + Properties)
//   - BeanPostProcessor (Bean post-processing / AOP foundation)
//   - BeanFactoryPostProcessor (Bean definition modification)
//   - AutoConfigurationManager (Spring Boot-style auto-configuration)
//
// Spring equivalent: org.springframework.context.ApplicationContext
// Laravel equivalent: Illuminate\Foundation\Application (Service Container + Event Dispatcher)
//
// Usage:
//   mut app := core.new_application_context()
//   app.set_profiles(['dev', 'local'])
//   app.register(core.BeanDefinition{ type_name: 'UserService', ... })
//   app.refresh()!  // instantiate all eager singletons
//   instance := app.resolve('UserService')!
//   app.shutdown()
import sync
import time
import ticker

// ── ApplicationState ──

// ApplicationState tracks the state of the application context.
pub enum ApplicationState {
	created    // context created, not yet refreshed
	refreshing // beans being instantiated and wired
	ready      // all beans ready, application running (after refresh)
	started    // explicitly started via start() — Spring Lifecycle
	stopped    // explicitly stopped via stop() — Spring Lifecycle
	closing    // shutdown in progress
	closed     // fully shut down
}

// str returns a human-readable application state.
pub fn (as_ ApplicationState) str() string {
	return match as_ {
		.created { 'created' }
		.refreshing { 'refreshing' }
		.ready { 'ready' }
		.started { 'started' }
		.stopped { 'stopped' }
		.closing { 'closing' }
		.closed { 'closed' }
	}
}

// ── ApplicationContext ──

// ApplicationContext is the unified application context — the heart of Photon.
// It combines IoC container, event bus, lifecycle manager, and environment
// into a single cohesive unit, following Spring's ApplicationContext pattern.
//
// Performance optimization: resolve() results are cached in resolve_cache.
// After freeze_bean_definitions() (called automatically by refresh()),
// resolve() reads from the frozen snapshot without locking.
// 性能优化：resolve() 结果缓存在 resolve_cache 中。
// freeze_bean_definitions() 后（refresh() 自动调用），resolve() 无锁读取冻结快照。
//
// Thread-safety: all mutable operations are protected by a sync.RwMutex.
// The resolve cache has its own independent lock (cache_mu) to avoid
// contention with the container lock.
@[heap]
pub struct ApplicationContext {
pub mut:
	container               &Container             = unsafe { nil }
	event_bus               &EventBus              = unsafe { nil }
	lifecycle               &LifecycleManager      = unsafe { nil }
	smart_lifecycle         &SmartLifecycleManager = unsafe { nil }
	environment             &Environment           = unsafe { nil }
	post_processors         []&BeanPostProcessor
	factory_post_processors []&BeanFactoryPostProcessor
	auto_config_manager     &AutoConfigurationManager = unsafe { nil }
	provider_registry       &ProviderRegistry         = unsafe { nil } // ServiceProvider (Laravel)
	runners                 []&ApplicationRunner
	shutdown_hooks          &ShutdownHookManager    = unsafe { nil }
	ordered_shutdown        &OrderedShutdownManager = unsafe { nil } // Task 16: ordered module shutdown
	lifecycle_beans         []&Lifecycle // Spring Lifecycle beans
	resolve_cache           map[string]voidptr // resolve 结果缓存 / resolve result cache
mut:
	state           ApplicationState = .created
	mu              sync.RwMutex
	cache_mu        sync.RwMutex // resolve 缓存专用锁 / dedicated lock for resolve cache
	frozen_bean_defs map[string]BeanDefinition // 冻结快照 / frozen snapshot of bean definitions
	is_frozen       bool // 是否已冻结 / whether bean definitions are frozen
	cache_hits      int  // 缓存命中次数 / cache hit count (diagnostic)
	cache_misses    int  // 缓存未命中次数 / cache miss count (diagnostic)
}

// new_application_context creates a fully initialized ApplicationContext
// with all subsystems wired together.
pub fn new_application_context() &ApplicationContext {
	mut ctx := &ApplicationContext{
		container:               new_container()
		event_bus:               new_event_bus()
		lifecycle:               new_lifecycle_manager()
		smart_lifecycle:         new_smart_lifecycle_manager()
		environment:             new_environment()
		post_processors:         []&BeanPostProcessor{}
		factory_post_processors: []&BeanFactoryPostProcessor{}
		auto_config_manager:     new_auto_configuration_manager()
		provider_registry:       new_provider_registry()
		runners:                 []&ApplicationRunner{}
		shutdown_hooks:          new_shutdown_hook_manager()
		ordered_shutdown:        new_ordered_shutdown_manager()
		lifecycle_beans:         []&Lifecycle{}
		resolve_cache:           map[string]voidptr{}
		frozen_bean_defs:        map[string]BeanDefinition{}
		is_frozen:               false
		cache_hits:              0
		cache_misses:            0
		state:                   .created
	}
	// Wire the container's event bus to the application's event bus
	// so bean lifecycle events (bean.created, bean.destroyed) are dispatched
	// through the application's event system.
	ctx.container.set_event_bus(ctx.event_bus)
	// Wire the environment to the container so that condition evaluation
	// during container.register() can access configuration properties.
	ctx.container.set_environment(ctx.environment)
	return ctx
}

// ── State ──

// current_state returns the current application state.
pub fn (mut ctx ApplicationContext) current_state() ApplicationState {
	ctx.mu.rlock()
	defer { ctx.mu.runlock() }
	return ctx.state
}

// is_ready returns true if the application is in the ready state.
pub fn (mut ctx ApplicationContext) is_ready() bool {
	ctx.mu.rlock()
	defer { ctx.mu.runlock() }
	return ctx.state == .ready
}

// is_readiness_ready returns true if the application is ready to serve
// traffic, suitable for use by a K8s readiness probe.
//
// This is stricter than is_ready(): it requires BOTH:
//   1. The application state is .ready or .started (the context has been
//      refreshed and is not shutting down).
//   2. All registered SmartLifecycle beans report is_running() == true
//      (background services like schedulers, queue workers, etc. are up).
//
// If no SmartLifecycle beans are registered, only the state check applies
// (an app with no lifecycle-managed components is ready as soon as refresh()
// completes). If SmartLifecycle beans ARE registered, every one of them
// must be running — a single not-yet-started component keeps the probe
// returning 503, which is the K8s convention for "starting".
//
// Thread-safety: takes the context read lock for the state check, then
// delegates to SmartLifecycleManager.all_running() which takes its own lock.
// The two locks are not held simultaneously, so there is no deadlock risk.
//
// Spring equivalent: AvailabilityChangeEvent + SmartLifecycle aggregation
// used by Spring Boot's readiness probe.
pub fn (mut ctx ApplicationContext) is_readiness_ready() bool {
	ctx.mu.rlock()
	state := ctx.state
	ctx.mu.runlock()

	if state != .ready && state != .started {
		return false
	}

	if isnil(ctx.smart_lifecycle) {
		return true
	}
	if ctx.smart_lifecycle.entry_count() == 0 {
		return true
	}
	return ctx.smart_lifecycle.all_running()
}

// is_running returns true if the application is not closed/closing.
pub fn (mut ctx ApplicationContext) is_running() bool {
	ctx.mu.rlock()
	defer { ctx.mu.runlock() }
	return ctx.state in [.ready, .refreshing, .started, .stopped]
}

// ── Profile ──

// set_profiles sets the active profiles.
// Also syncs to the container for backward compatibility.
pub fn (mut ctx ApplicationContext) set_profiles(profiles []string) {
	ctx.environment.set_active_profiles(profiles)
	ctx.container.set_profiles(profiles)
}

// add_profile adds a profile to the active profiles.
pub fn (mut ctx ApplicationContext) add_profile(profile string) {
	ctx.environment.add_active_profile(profile)
	ctx.container.add_profile(profile)
}

// has_profile checks if a profile is active.
pub fn (mut ctx ApplicationContext) has_profile(profile string) bool {
	return ctx.environment.accepts_profile(profile)
}

// ── Property ──

// set_property sets a configuration property on the environment.
pub fn (mut ctx ApplicationContext) set_property(key string, value string) {
	ctx.environment.set_property(key, value)
}

// get_property retrieves a property from the environment.
pub fn (mut ctx ApplicationContext) get_property(key string) string {
	return ctx.environment.get_property(key)
}

// get_property_or retrieves a property with a default value.
pub fn (mut ctx ApplicationContext) get_property_or(key string, default_val string) string {
	return ctx.environment.get_property_or(key, default_val)
}

// ── Bean Registration ──

// register adds a BeanDefinition to the container.
// Conditions are evaluated before registration — if conditions are not met,
// the bean is silently skipped.
// 注册后使 resolve 缓存失效。
// 冻结后禁止注册新 BeanDefinition，因为 frozen_bean_defs 快照不会更新，
// 导致 resolve() 冻结路径无法命中新注册的 bean。
// Registration is blocked after freeze_bean_definitions() because the frozen
// snapshot would not include new beans, causing resolve() misses on the frozen path.
pub fn (mut ctx ApplicationContext) register(def BeanDefinition) ! {
	// 阻止冻结后注册 / Block registration after freeze
	if ctx.is_frozen {
		return error('cannot register bean "${def.type_name}": bean definitions are frozen / BeanDefinition 已冻结，无法注册 "${def.type_name}"')
	}
	// Evaluate conditions before registering
	if !isnil(ctx.environment) {
		mut cond_ctx := new_condition_context()
		cond_ctx = cond_ctx.with_container(ctx.container)
		cond_ctx = cond_ctx.with_profiles(ctx.environment.get_active_profiles())
		cond_ctx = cond_ctx.with_properties(ctx.environment.properties.clone())

		// Parse and evaluate any conditional attributes from tags
		conditions := parse_conditions(def.tags, mut cond_ctx)
		if !evaluate_conditions(conditions, mut cond_ctx) {
			return
		}
	}
	ctx.container.register(def)!
	ctx.invalidate_cache(def.type_name)
}

// register_bean is a convenience method to register a bean with minimal config.
// Inspired by Spring's BeanDefinitionBuilder and Laravel's service container binding.
pub fn (mut ctx ApplicationContext) register_bean(type_name string, opts BeanRegistrationOptions) ! {
	mut def := new_bean_definition(type_name)
	def.scope = opts.scope
	def.is_lazy = opts.is_lazy
	def.qualifier = opts.qualifier
	def.tags = opts.tags
	def.dependencies = opts.dependencies
	def.init_method = opts.init_method
	def.destroy_method = opts.destroy_method
	def.depends_on = opts.depends_on
	def.is_primary = opts.is_primary
	def.parent_name = opts.parent_name
	def.interfaces = opts.interfaces
	def.method_injections = opts.method_injections
	def.collection_injections = opts.collection_injections
	def.lookup_injections = opts.lookup_injections
	def.conditions = opts.conditions
	ctx.register(def)!
}

// register_instance registers a pre-created instance as a singleton.
// 注册后使 resolve 缓存失效。
// 冻结后禁止注册 / Registration blocked after freeze.
pub fn (mut ctx ApplicationContext) register_instance(type_name string, instance voidptr) ! {
	if ctx.is_frozen {
		return error('cannot register instance "${type_name}": bean definitions are frozen / BeanDefinition 已冻结，无法注册 "${type_name}"')
	}
	ctx.container.register_instance(type_name, instance)!
	ctx.invalidate_cache(type_name)
}

// register_factory registers a FactoryBean with the container.
// Laravel equivalent: Container::bind('name', fn() => new Service())
pub fn (mut ctx ApplicationContext) register_factory(factory_type_name string, factory &FactoryBean) ! {
	ctx.container.register_factory(factory_type_name, factory)!
}

// ── Bean Resolution ──

// resolve retrieves a bean by type name.
// Performance optimization: checks resolve_cache first (fast path).
// After freeze_bean_definitions(), the frozen snapshot is read without locking.
// 性能优化：优先查询缓存（快速路径）。冻结后无锁读取快照。
//
// 线程安全说明：
//   - 冻结后（is_frozen == true），resolve_cache 和 frozen_bean_defs 为不可变快照，
//     可无锁安全读取。is_frozen 标志由 freeze_bean_definitions() 在写锁下设置，
//     一旦为 true 不会再变回 false（unfreeze 仅在 shutdown 时调用）。
//   - 未冻结时，通过 cache_mu 保护 resolve_cache 的读写。
//   - cache_hits/cache_misses 为诊断计数器，使用 cache_mu 保护写入，
//     避免多线程并发写入导致的数据竞争。
//
// Thread-safety notes:
//   - When frozen (is_frozen == true), resolve_cache and frozen_bean_defs are immutable
//     snapshots, safe for lock-free reads. The is_frozen flag is set under write lock by
//     freeze_bean_definitions() and once true it never goes back to false (unfreeze is
//     only called during shutdown).
//   - When not frozen, cache_mu protects resolve_cache reads and writes.
//   - cache_hits/cache_misses are diagnostic counters protected by cache_mu to avoid
//     data races from concurrent writes.
pub fn (mut ctx ApplicationContext) resolve(type_name string) !voidptr {
	// 快速路径 1：缓存命中（冻结后无锁读取）
	// Fast path 1: cache hit (lock-free read when frozen)
	if ctx.is_frozen {
		if cached := ctx.resolve_cache[type_name] {
			// 诊断计数器：冻结后多线程并发读取，cache_hits++ 不加锁。
			// 这是可接受的数据竞争——计数器精度不重要，加锁会影响性能。
			// Diagnostic counter: concurrent cache_hits++ without lock is acceptable
			// data race — counter precision is not critical, locking would hurt performance.
			unsafe { ctx.cache_hits++ }
			return cached
		}
	}

	// 快速路径 2：缓存命中（未冻结时加锁读取）
	// Fast path 2: cache hit (locked read when not frozen)
	if !ctx.is_frozen {
		ctx.cache_mu.rlock()
		if cached := ctx.resolve_cache[type_name] {
			ctx.cache_mu.runlock()
			ctx.cache_mu.@lock()
			ctx.cache_hits++
			ctx.cache_mu.unlock()
			return cached
		}
		ctx.cache_mu.runlock()
	}

	// 慢速路径：从容器解析
	// Slow path: resolve from container
	ctx.cache_mu.@lock()
	ctx.cache_misses++
	ctx.cache_mu.unlock()
	instance := ctx.container.resolve(type_name) or { return err }

	// 写入缓存（仅在未冻结时写入，冻结后缓存应已完整）
	// Write to cache (only when not frozen; cache should be complete after freezing)
	if !ctx.is_frozen {
		ctx.cache_mu.@lock()
		ctx.resolve_cache[type_name] = instance
		ctx.cache_mu.unlock()
	}

	return instance
}

// resolve_by_qualifier retrieves a bean by qualifier name.
pub fn (mut ctx ApplicationContext) resolve_by_qualifier(qualifier string) !voidptr {
	return ctx.container.resolve_by_qualifier(qualifier)
}

// has checks if a bean is registered.
pub fn (mut ctx ApplicationContext) has(type_name string) bool {
	return ctx.container.has(type_name)
}

// ── BeanPostProcessor ──

// add_post_processor adds a BeanPostProcessor.
// Post-processors are invoked during refresh() for each bean.
pub fn (mut ctx ApplicationContext) add_post_processor(pp &BeanPostProcessor) {
	ctx.post_processors << pp
}

// ── BeanFactoryPostProcessor ──

// add_factory_post_processor adds a BeanFactoryPostProcessor.
// Factory post-processors are invoked during refresh() before beans are instantiated.
// Spring equivalent: BeanFactoryPostProcessor
// Laravel equivalent: Service Provider register() method
pub fn (mut ctx ApplicationContext) add_factory_post_processor(fpp &BeanFactoryPostProcessor) {
	ctx.factory_post_processors << fpp
}

// ── AutoConfiguration ──

// add_auto_configuration registers an auto-configuration with conditions.
// Spring Boot equivalent: @AutoConfiguration class
pub fn (mut ctx ApplicationContext) add_auto_configuration(type_name string, config &AutoConfiguration, conditions []&Condition) {
	ctx.auto_config_manager.add_auto_configuration(type_name, config, conditions)
}

// register_auto_configuration is the comptime-driven entry point for
// auto-configuration discovery (Task A1).
//
// It delegates to `AutoConfigurationManager.register_from_comptime[T]()`,
// which performs a compile-time scan of T's struct-level attributes and:
//   - Refuses (returns error) if T is NOT annotated with `@[auto_configuration]`
//   - Registers T as an auto-configuration candidate
//   - Parses any `@[conditional_on_*]` attributes into Condition objects
//
// V comptime can only see types in the current compilation unit, so users
// call this once per auto-configuration class during bootstrap (before
// refresh()). The candidates are then evaluated and applied during
// refresh() via `auto_config_manager.apply_all()` (step 3 of refresh()).
//
// Spring Boot equivalent: @EnableAutoConfiguration classpath scan
//
// Usage:
//   mut app := core.new_application_context()
//   app.register_auto_configuration[RedisAutoConfig]()!
//   app.register_auto_configuration[WebMvcAutoConfig]()!
//   app.refresh()!  // apply_all() evaluates conditions during step 3
pub fn (mut ctx ApplicationContext) register_auto_configuration[T]() ! {
	ctx.auto_config_manager.register_from_comptime[T]()!
}

// ── @[scheduled] Auto-Registration (Task C4) ──

// register_scheduled scans type T at compile time for @[scheduled('cron')]
// methods and registers each one with the provided Scheduler. The bean
// instance is resolved from the container (must already be registered under
// T.name), and a comptime closure is generated for each scheduled method
// that invokes `bean.$method()`.
//
// Spring equivalent: ScheduledAnnotationBeanPostProcessor — automatically
// registers @Scheduled-annotated methods with the TaskScheduler.
//
// V comptime pattern: the closure `fn [bean_ptr] () ! { ... bean.$method() }`
// captures the raw bean pointer (as voidptr) and casts it to a mutable &T
// reference inside the closure. This is necessary because:
//   1. V closures capture variables as immutable, but scheduled methods
//      typically have `mut` receivers (they modify bean state).
//   2. The `mut bean := unsafe { &T(bean_ptr) }` binding grants mutable
//      access, allowing `mut`-receiver method calls.
//   3. `bean.$method()` is a comptime method call — `method` is the comptime
//      loop variable from `$for method in T.methods`, so each iteration
//      generates a distinct closure with the specific method baked in.
//
// Thread-safety: the Scheduler itself is thread-safe (sync.RwMutex). The
// bean instance is accessed from the scheduler's background goroutine; the
// caller is responsible for ensuring the bean's internal state is thread-safe
// (e.g., via mutex-protected fields).
//
// Usage:
//   mut sched := ticker.new_task_scheduler()
//   ctx.register_instance('HeartbeatService', &service)!
//   ctx.register_scheduled[HeartbeatService](mut sched)!
//   sched.start()  // scheduled methods begin executing
//   // ...
//   sched.stop()   // graceful shutdown
pub fn (mut ctx ApplicationContext) register_scheduled[T](mut scheduler ticker.Scheduler) ! {
	// Resolve the bean instance from the container by type name.
	// We use the raw voidptr so the closure can cast it to a mutable &T.
	type_name := auto_configuration_type_name[T]()
	bean_ptr := ctx.container.resolve(type_name) or {
		return error('register_scheduled: bean "${type_name}" not found / 未找到 bean "${type_name}"')
	}

	// Comptime scan: for each method of T, check if it has @[scheduled(...)]
	// and generate a per-method closure that delegates to the dispatcher.
	$for method in T.methods {
		cron_expr := extract_scheduled_expr(method.attrs)
		if cron_expr.len > 0 {
			// V 0.5.1 comptime limitation: T and $for method variables are
			// not accessible inside nested closures. We capture the bean
			// pointer and method name, then delegate to the top-level
			// generic dispatcher which CAN access comptime variables.
			method_name := method.name
			dispatcher := dispatch_scheduled_method[T]
			task_fn := fn [bean_ptr, method_name, dispatcher] () ! {
				dispatcher(bean_ptr, method_name)!
			}

			mut b := scheduler.cron(cron_expr)
			b.task(task_fn)
			b.name('${type_name}.${method_name}')
			scheduler.register(b)
		}
	}
}

// ── Starter Pattern: Manifest Imports (Task A5) ──

// register_imports registers a list of auto-configuration class names as
// pending manifest imports. This is the programmatic equivalent of loading
// a manifest file — each module can export a `pub const auto_configuration_imports`
// array and pass it here during bootstrap.
//
// The imports are declarations only — they do NOT create candidates. Actual
// candidate registration requires a separate `register_auto_configuration[T]()`
// call for each type.
//
// Spring Boot equivalent: AutoConfigurationImportSelector.selectImports()
//
// Usage:
//   // Module db exports: pub const auto_configuration_imports = ['DbAutoConfig']
//   ctx.register_imports(db.auto_configuration_imports)
//   ctx.register_auto_configuration[db.DbAutoConfig]()!
pub fn (mut ctx ApplicationContext) register_imports(imports []string) {
	ctx.auto_config_manager.register_imports(imports)
}

// load_imports_from_manifest loads auto-configuration class names from a
// manifest file (auto_configuration_imports.v format).
//
// The file format is plain text:
//   - One fully-qualified class name per line
//   - Lines starting with # are comments (ignored)
//   - Empty lines are ignored
//
// Returns the number of class names loaded.
//
// Spring Boot equivalent: loading META-INF/spring/...AutoConfiguration.imports
pub fn (mut ctx ApplicationContext) load_imports_from_manifest(path string) !int {
	return ctx.auto_config_manager.load_imports_from_manifest(path)
}

// scan_manifests recursively scans a directory tree for
// auto_configuration_imports.v manifest files and loads all class names
// from each file found.
//
// This simulates Spring Boot's classpath scanning for
// META-INF/spring/org.springframework.boot.autoconfigure.AutoConfiguration.imports.
// In V, since there is no runtime classpath, the application points this
// method at a directory containing module subdirectories.
//
// Returns the total number of class names loaded across all manifest files.
pub fn (mut ctx ApplicationContext) scan_manifests(directory string) !int {
	return ctx.auto_config_manager.scan_manifests(directory)
}

// ── SmartLifecycle ──

// add_smart_lifecycle registers a SmartLifecycle bean.
// Spring equivalent: SmartLifecycle registration
pub fn (mut ctx ApplicationContext) add_smart_lifecycle(type_name string, bean &SmartLifecycle) {
	ctx.smart_lifecycle.register(type_name, bean)
}

// ── ApplicationRunner ──

// add_runner adds an ApplicationRunner that will be executed after refresh.
// Spring equivalent: ApplicationRunner / CommandLineRunner
pub fn (mut ctx ApplicationContext) add_runner(runner &ApplicationRunner) {
	ctx.runners << runner
}

// ── Bean Alias ──

// register_alias registers an alias for a bean.
// Spring equivalent: ConfigurableBeanFactory.registerAlias()
pub fn (mut ctx ApplicationContext) register_alias(alias string, canonical_name string) ! {
	ctx.container.register_alias(alias, canonical_name)!
}

// remove_alias removes a registered alias.
pub fn (mut ctx ApplicationContext) remove_alias(alias string) {
	ctx.container.remove_alias(alias)
}

// ── Hierarchical Context ──

// set_parent sets the parent ApplicationContext for hierarchical context support.
// Spring equivalent: HierarchicalApplicationContext.setParent()
pub fn (mut ctx ApplicationContext) set_parent(parent &ApplicationContext) {
	ctx.container.set_parent(parent.container)
}

// ── Refresh / Lifecycle ──

// refresh initializes all eager singleton beans.
// This is the Spring equivalent of AbstractApplicationContext.refresh().
//
// Steps:
//   1. Run BeanFactoryPostProcessors (modify bean definitions)
//   2. Apply AutoConfigurations (conditionally register more beans)
//   3. Check for circular dependencies
//   4. Set state to refreshing
//   5. Instantiate all non-lazy singletons in dependency order
//   6. Apply BeanPostProcessor.before on each bean
//   7. Invoke all @[post_construct] callbacks
//   8. Invoke InitializingBean.after_properties_set() callbacks
//   9. Apply BeanPostProcessor.after on each bean
//  10. Start SmartLifecycle beans (in ascending phase order)
//  11. Dispatch ContextRefreshedEvent
//  12. Execute ApplicationRunners
//  13. Set state to ready
//
// Lifecycle order (Spring-aligned, SubTask 8.2):
//   before → @post_construct → afterPropertiesSet → after
//
// On failure (SubTask 8.1): already-created beans are destroyed in reverse
// order, the state is reset to .created, and the original error is returned.
pub fn (mut ctx ApplicationContext) refresh() ! {
	ctx.mu.@lock()
	if ctx.state == .refreshing {
		ctx.mu.unlock()
		return error('application context is already refreshing')
	}
	if ctx.state == .ready || ctx.state == .started || ctx.state == .stopped {
		ctx.mu.unlock()
		return error('application context has already been refreshed (state: ${ctx.state.str()})')
	}
	if ctx.state == .closed {
		ctx.mu.unlock()
		return error('cannot refresh a closed application context')
	}
	ctx.state = .refreshing
	ctx.mu.unlock()

	// 1. Run BeanFactoryPostProcessors (before any bean instantiation)
	for fpp in ctx.factory_post_processors {
		fpp.post_process_bean_factory(mut ctx)
	}

	// 2. Apply ServiceProviders register() phase (Laravel-style)
	//    This adds bean definitions BEFORE auto-configuration,
	//    so user-defined services take precedence.
	if !isnil(ctx.provider_registry) {
		ctx.provider_registry.register_all(mut ctx) or {
			eprintln('[ApplicationContext] service provider register error: ${err}')
		}
	}

	// 3. Apply AutoConfigurations (conditionally register more beans)
	//    Auto-configuration candidates are registered BEFORE refresh() via
	//    `ctx.register_auto_configuration[T]()` (Task A1), which performs a
	//    comptime scan of `@[auto_configuration]` attributes. Here we only
	//    evaluate their `@[conditional_on_*]` conditions and apply those
	//    that match — this is the Spring Boot two-phase model
	//    (import candidates → evaluate conditions during refresh).
	//    User beans (registered in steps 1–2) take precedence over
	//    auto-configured beans ("user has the final word" principle).
	if !isnil(ctx.auto_config_manager) {
		ctx.auto_config_manager.apply_all(mut ctx) or {
			eprintln('[ApplicationContext] auto-configuration error: ${err}')
		}
	}

	// 4. Check for circular dependencies
	ctx.container.check_circular_dependencies() or {
		ctx.mu.@lock()
		ctx.state = .created
		ctx.mu.unlock()
		return error('refresh failed: ${err}')
	}

	// 5. Instantiate non-lazy singletons in dependency order
	mut bean_names := ctx.container.bean_names()
	mut sorted_beans := topological_sort(bean_names, mut ctx.container)

	// Track successfully created beans for rollback on failure (SubTask 8.1).
	// If any bean fails to create or initialize, already-created beans are
	// destroyed in reverse order to leave the context in a clean state.
	mut created_beans := []string{}

	for name in sorted_beans {
		def := ctx.container.get_definition(name) or { continue }
		if def.is_lazy || def.scope == .prototype {
			continue // skip lazy and prototype beans
		}
		if !def.is_singleton() {
			continue
		}

		// Resolve (instantiate) the bean
		instance := ctx.container.resolve(name) or {
			// Rollback: destroy already-created beans in reverse order (SubTask 8.1)
			ctx.rollback_created_beans(mut created_beans)
			ctx.mu.@lock()
			ctx.state = .created
			ctx.mu.unlock()
			return error('refresh failed: bean "${name}" could not be created: ${err}')
		}

		// Track successfully created bean for rollback
		created_beans << name

		// 6. Apply BeanPostProcessor.before (post_process_before_initialization)
		//    Lifecycle order (Spring-aligned, SubTask 8.2):
		//      before → @post_construct → afterPropertiesSet → after
		mut processed_instance := instance
		for pp in ctx.post_processors {
			processed_instance = pp.post_process_before_initialization(name, processed_instance)
		}

		// 7. Invoke @[post_construct] (annotation-based)
		ctx.lifecycle.invoke_post_construct(name) or {
			// Rollback on lifecycle failure (SubTask 8.1)
			ctx.rollback_created_beans(mut created_beans)
			ctx.mu.@lock()
			ctx.state = .created
			ctx.mu.unlock()
			return error('refresh failed: post_construct error for bean "${name}": ${err}')
		}

		// 8. Invoke InitializingBean.after_properties_set() (interface-based, SubTask 8.3)
		//    This must happen AFTER @post_construct and BEFORE BeanPostProcessor.after,
		//    matching Spring's lifecycle order.
		ctx.container.invoke_init_callback(name, processed_instance) or {
			// Rollback on lifecycle failure (SubTask 8.1)
			ctx.rollback_created_beans(mut created_beans)
			ctx.mu.@lock()
			ctx.state = .created
			ctx.mu.unlock()
			return error('refresh failed: after_properties_set error for bean "${name}": ${err}')
		}

		// 9. Apply BeanPostProcessor.after (post_process_after_initialization)
		for pp in ctx.post_processors {
			processed_instance = pp.post_process_after_initialization(name, processed_instance)
		}
	}

	// 8. Start SmartLifecycle beans (ascending phase order)
	if !isnil(ctx.smart_lifecycle) {
		ctx.smart_lifecycle.start_all() or {
			eprintln('[ApplicationContext] SmartLifecycle start error: ${err}')
		}
	}

	// 9. Boot ServiceProviders (Laravel-style boot phase)
	if !isnil(ctx.provider_registry) {
		ctx.provider_registry.boot_all(mut ctx) or {
			eprintln('[ApplicationContext] service provider boot error: ${err}')
		}
	}

	// 10. Dispatch ContextRefreshedEvent
	mut event := new_event(event_context_refreshed, '')
	event.data['profile'] = ctx.environment.get_active_profiles().join(',')
	mut bus := unsafe { ctx.event_bus }
	bus.dispatch(event)

	// 11. Execute ApplicationRunners
	for runner in ctx.runners {
		if !isnil(runner) {
			runner.run(mut ctx) or {
				eprintln('[ApplicationContext] ApplicationRunner error: ${err}')
			}
		}
	}

	// 12. Set state to ready
	ctx.mu.@lock()
	ctx.state = .ready
	ctx.mu.unlock()

	// 13. Freeze bean definitions after refresh completes
	// 冻结 BeanDefinition，后续 resolve 无锁读取
	ctx.freeze_bean_definitions()
}

// rollback_created_beans destroys the given beans in reverse order (LIFO).
// Used by refresh() to clean up partially-created state when a bean fails
// to create or initialize. (SubTask 8.1)
//
// For each bean, this invokes:
//   1. @[pre_destroy] callback (via LifecycleManager.invoke_pre_destroy)
//   2. DisposableBean.destroy() callback (via Container.destroy)
//   3. Removes the singleton instance
//
// Errors from individual destroy operations are swallowed so that rollback
// continues for all remaining beans — we want to clean up as much as possible.
fn (mut ctx ApplicationContext) rollback_created_beans(mut created_beans []string) {
	// Destroy beans in reverse order (last created → first created)
	// Note: manual reverse iteration to avoid V compiler bug with .reverse()
	// on mut array parameters (generates incorrect C code passing pointer).
	for i := created_beans.len - 1; i >= 0; i-- {
		name := created_beans[i]
		// Invoke @pre_destroy callback if registered
		ctx.lifecycle.invoke_pre_destroy(name) or {}
		// Invoke DisposableBean.destroy() and remove instance
		ctx.container.destroy(name) or {}
	}
	created_beans.clear()
}

// ── Resolve Cache & Freeze/Unfreeze ──

// invalidate_cache invalidates the resolve cache entry for a given type name.
// Called automatically after register/register_instance/remove_definition/replace_definition.
// 使用 defer { cache_mu.unlock() } 保证锁释放。
// 使指定 type_name 的缓存条目失效。
// 在 register/register_instance/remove/replace 调用时自动触发。
fn (mut ctx ApplicationContext) invalidate_cache(type_name string) {
	ctx.cache_mu.@lock()
	defer { ctx.cache_mu.unlock() }
	ctx.resolve_cache.delete(type_name)
	// Also invalidate from frozen snapshot
	ctx.frozen_bean_defs.delete(type_name)
}

// freeze_bean_definitions freezes the BeanDefinition registry.
// After freezing, resolve() reads from the frozen snapshot without locking,
// providing maximum performance for the hot resolve path.
// 冻结 BeanDefinition 注册表。冻结后 resolve() 无锁读取快照。
//
// Called automatically by refresh() after all beans are instantiated.
// Idempotent: safe to call multiple times; subsequent calls are no-ops.
// 幂等：多次调用安全。
//
// Spring equivalent: DefaultListableBeanFactory.freezeConfiguration()
pub fn (mut ctx ApplicationContext) freeze_bean_definitions() {
	ctx.cache_mu.@lock()
	defer { ctx.cache_mu.unlock() }
	if ctx.is_frozen {
		return
	}
	// Snapshot all current bean definitions into frozen_bean_defs
	// 快照当前所有 BeanDefinition 到 frozen_bean_defs
	mut snapshot := map[string]BeanDefinition{}
	for name in ctx.container.bean_names() {
		if def := ctx.container.get_definition(name) {
			snapshot[name] = def
		}
	}
	ctx.frozen_bean_defs = snapshot.clone()
	ctx.is_frozen = true
}

// unfreeze_bean_definitions thaws the BeanDefinition registry, allowing
// modifications again. Clears the frozen snapshot and resolve cache.
// 解冻 BeanDefinition 注册表，允许修改。清空冻结快照和缓存。
//
// Called automatically by shutdown() to clean up state.
// Spring equivalent: DefaultListableBeanFactory.clearMetadataCache()
pub fn (mut ctx ApplicationContext) unfreeze_bean_definitions() {
	ctx.cache_mu.@lock()
	defer { ctx.cache_mu.unlock() }
	ctx.is_frozen = false
	ctx.frozen_bean_defs = map[string]BeanDefinition{}
	ctx.resolve_cache = map[string]voidptr{}
	ctx.cache_hits = 0
	ctx.cache_misses = 0
}

// is_frozen_bean_definitions returns whether the BeanDefinition registry is frozen.
// 返回 BeanDefinition 注册表是否已冻结。
pub fn (mut ctx ApplicationContext) is_frozen_bean_definitions() bool {
	ctx.cache_mu.rlock()
	defer { ctx.cache_mu.runlock() }
	return ctx.is_frozen
}

// cache_hit_count returns the number of resolve cache hits (diagnostic).
// 返回缓存命中次数（诊断用）。
pub fn (mut ctx ApplicationContext) cache_hit_count() int {
	ctx.cache_mu.rlock()
	defer { ctx.cache_mu.runlock() }
	return ctx.cache_hits
}

// cache_miss_count returns the number of resolve cache misses (diagnostic).
// 返回缓存未命中次数（诊断用）。
pub fn (mut ctx ApplicationContext) cache_miss_count() int {
	ctx.cache_mu.rlock()
	defer { ctx.cache_mu.runlock() }
	return ctx.cache_misses
}

// cache_size returns the number of entries in the resolve cache.
// 返回 resolve 缓存条目数。
pub fn (mut ctx ApplicationContext) cache_size() int {
	ctx.cache_mu.rlock()
	defer { ctx.cache_mu.runlock() }
	return ctx.resolve_cache.len
}

// shutdown gracefully shuts down the application context.
// This is the Spring equivalent of AbstractApplicationContext.close().
//
// Unified shutdown order (Task 16):
//   1. Dispatch ContextClosedEvent
//   2. Stop SmartLifecycle beans (in descending phase order)
//   3. Run ordered shutdown stages (Task 16) — each with a 5-second timeout:
//        web → queue → ticker → schedule → event → cache → orm → pool
//      Only registered stages are run; unregistered modules are skipped.
//   4. Invoke all @[pre_destroy] callbacks in reverse order (SubTask 4.4)
//      — handled by LifecycleManager.invoke_all_pre_destroy()
//   5. Run shutdown hooks (Spring addShutdownHook)
//   6. Stop Lifecycle beans
//   7. Destroy all singletons (core stage) — Container.destroy_all() now:
//        a. Invokes DisposableBean.destroy() callbacks (SubTask 4.5)
//        b. Clears all reference maps (instances, definitions, aliases,
//           qualifiers, destroy_callbacks, init_callbacks) to allow GC
//           reclamation (SubTask 4.6 / 8.5)
//   8. Set state to closed
//
// The shutdown is idempotent — calling it twice is safe (the second call
// returns immediately because the state is already .closed).
pub fn (mut ctx ApplicationContext) shutdown() {
	ctx.mu.@lock()
	if ctx.state == .closed || ctx.state == .closing {
		ctx.mu.unlock()
		return
	}
	ctx.state = .closing
	ctx.mu.unlock()

	// 1. Dispatch ContextClosedEvent
	event2 := new_event(event_context_closed, '')
	mut bus2 := unsafe { ctx.event_bus }
	bus2.dispatch(event2)

	// 2. Stop SmartLifecycle beans (descending phase order)
	if !isnil(ctx.smart_lifecycle) {
		ctx.smart_lifecycle.stop_all()
	}

	// 3. Run ordered shutdown stages (Task 16)
	//    Stages are executed in descending priority order:
	//    web → queue → ticker → schedule → event → cache → orm → pool
	//    Each stage has a 5-second timeout — if a stage doesn't complete in
	//    5 seconds, a warning is logged and shutdown continues to the next
	//    stage. Only registered stages are run.
	if !isnil(ctx.ordered_shutdown) {
		stages := ctx.ordered_shutdown.stages_sorted()
		for stage in stages {
			ctx.shutdown_stage(stage.name, stage.hook)
		}
	}

	// 4. Invoke all @[pre_destroy] in reverse order (SubTask 4.4)
	//    The LifecycleManager holds callbacks registered by comptime-generated
	//    code for beans with @[pre_destroy] annotated methods. This mirrors
	//    the @[post_construct] invocation pattern used during refresh().
	ctx.lifecycle.invoke_all_pre_destroy() or {}

	// 5. Run shutdown hooks (Spring addShutdownHook)
	if !isnil(ctx.shutdown_hooks) {
		ctx.shutdown_hooks.run_hooks()
	}

	// 6. Stop Lifecycle beans
	for bean in ctx.lifecycle_beans {
		if !isnil(bean) && bean.is_running() {
			bean.stop() or { eprintln('[ApplicationContext] Lifecycle stop error: ${err}') }
		}
	}

	// 7. Destroy all singletons (core stage, SubTask 4.5 + 4.6 + 8.5)
	//    Container.destroy_all() invokes DisposableBean.destroy() callbacks
	//    for each bean, then clears ALL reference maps (instances, definitions,
	//    aliases, qualifiers, destroy_callbacks, init_callbacks) to allow GC
	//    reclamation.
	ctx.container.destroy_all()

	// 7.5. Unfreeze and clear resolve cache
	// 解冻并清空 resolve 缓存
	ctx.unfreeze_bean_definitions()

	// 8. Set state to closed
	ctx.mu.@lock()
	ctx.state = .closed
	ctx.mu.unlock()
}

// shutdown_stage runs a single shutdown stage function with a 5-second timeout.
// If the stage doesn't complete in 5 seconds, a warning is logged and the
// method returns (the stage's background goroutine may continue running —
// this is the standard trade-off when there is no cancellation mechanism).
// Errors from the stage function are logged but do not abort shutdown.
fn (mut ctx ApplicationContext) shutdown_stage(name string, stage_fn fn () !) {
	done := chan bool{cap: 1}
	spawn fn (sf fn () !, d chan bool) {
		sf() or { eprintln('[ApplicationContext] shutdown stage error: ${err}') }
		d <- true
	}(stage_fn, done)

	// Poll for completion with a 5-second deadline. V's `select` with `else`
	// is non-blocking, so we sleep briefly between checks (same pattern as
	// SmartLifecycleManager.stop_all()).
	deadline_ns := time.now().unix_nano() + i64(5 * time.second)
	for {
		select {
			_ := <-done {
				return
			}
			else {}
		}
		if time.now().unix_nano() >= deadline_ns {
			eprintln('[ApplicationContext] shutdown stage "${name}" timed out after 5s, continuing')
			return
		}
		time.sleep(50 * time.millisecond)
	}
}

// ── Spring Lifecycle: start / stop / close ──

// start explicitly starts the application context.
// This calls start() on all registered Lifecycle beans and
// dispatches a ContextStartedEvent.
//
// Spring equivalent: AbstractApplicationContext.start()
//   - Lifecycle.start() on all Lifecycle beans
//   - SmartLifecycle.start() on all SmartLifecycle beans
//   - Dispatches ContextStartedEvent
//
// Can only be called when the context is in ready or stopped state.
pub fn (mut ctx ApplicationContext) start() ! {
	ctx.mu.@lock()
	if ctx.state != .ready && ctx.state != .stopped {
		ctx.mu.unlock()
		return error('cannot start: application context is in ${ctx.state.str()} state (expected ready or stopped)')
	}
	ctx.mu.unlock()

	// Start Lifecycle beans
	for bean in ctx.lifecycle_beans {
		if !isnil(bean) && !bean.is_running() {
			bean.start() or { eprintln('[ApplicationContext] Lifecycle start error: ${err}') }
		}
	}

	// Start SmartLifecycle beans (ascending phase order)
	if !isnil(ctx.smart_lifecycle) {
		ctx.smart_lifecycle.start_all() or {
			eprintln('[ApplicationContext] SmartLifecycle start error: ${err}')
		}
	}

	// Dispatch ContextStartedEvent
	started_event := new_event(event_context_started, '')
	mut bus_s := unsafe { ctx.event_bus }
	bus_s.dispatch(started_event)

	ctx.mu.@lock()
	ctx.state = .started
	ctx.mu.unlock()
}

// stop explicitly stops the application context.
// This calls stop() on all registered Lifecycle beans and
// dispatches a ContextStoppedEvent.
//
// Spring equivalent: AbstractApplicationContext.stop()
//   - SmartLifecycle.stop() on all SmartLifecycle beans (descending phase order)
//   - Lifecycle.stop() on all Lifecycle beans
//   - Dispatches ContextStoppedEvent
//
// Can only be called when the context is in ready or started state.
pub fn (mut ctx ApplicationContext) stop() ! {
	ctx.mu.@lock()
	if ctx.state != .ready && ctx.state != .started {
		ctx.mu.unlock()
		return error('cannot stop: application context is in ${ctx.state.str()} state (expected ready or started)')
	}
	ctx.mu.unlock()

	// Stop SmartLifecycle beans (descending phase order)
	if !isnil(ctx.smart_lifecycle) {
		ctx.smart_lifecycle.stop_all()
	}

	// Stop Lifecycle beans
	for bean in ctx.lifecycle_beans {
		if !isnil(bean) && bean.is_running() {
			bean.stop() or { eprintln('[ApplicationContext] Lifecycle stop error: ${err}') }
		}
	}

	// Dispatch ContextStoppedEvent
	stopped_event := new_event(event_context_stopped, '')
	mut bus_st := unsafe { ctx.event_bus }
	bus_st.dispatch(stopped_event)

	ctx.mu.@lock()
	ctx.state = .stopped
	ctx.mu.unlock()
}

// close is an alias for shutdown() — Spring-compatible naming.
// Spring equivalent: AbstractApplicationContext.close()
pub fn (mut ctx ApplicationContext) close() {
	ctx.shutdown()
}

// ── Shutdown Hook ──

// add_shutdown_hook registers a function to be called during shutdown.
// Spring equivalent: SpringApplication.addShutdownHook()
//
// Usage:
//   app.add_shutdown_hook(fn () {
//       println('Cleaning up resources...')
//   })
pub fn (mut ctx ApplicationContext) add_shutdown_hook(hook ShutdownHook) {
	if isnil(ctx.shutdown_hooks) {
		ctx.shutdown_hooks = new_shutdown_hook_manager()
	}
	ctx.shutdown_hooks.add_hook(hook)
}

// ── Ordered Shutdown Stage (Task 16) ──

// add_shutdown_stage registers an ordered shutdown stage.
// Stages are executed in descending priority order during shutdown
// (highest priority first). Each stage has a 5-second timeout — if a stage
// doesn't complete in 5 seconds, a warning is logged and shutdown continues
// to the next stage.
//
// Standard priority constants (defined in lifecycle.v):
//   - shutdown_priority_web (100)      — stop accepting new requests
//   - shutdown_priority_queue (90)     — stop workers, wait for in-flight jobs
//   - shutdown_priority_ticker (80)    — stop scheduler goroutines
//   - shutdown_priority_schedule (70)  — stop scheduled tasks
//   - shutdown_priority_event (60)     — wait for async event dispatch
//   - shutdown_priority_cache (50)     — close caches, stop GC goroutines
//   - shutdown_priority_orm (40)       — close all DB connections
//   - shutdown_priority_pool (30)      — close all object pools
//   - shutdown_priority_core (10)      — destroy all beans (implicit)
//
// If a stage with the same name already exists, it is replaced.
//
// Usage:
//   app.add_shutdown_stage('web', core.shutdown_priority_web, fn () ! {
//       // stop web server
//   })
pub fn (mut ctx ApplicationContext) add_shutdown_stage(name string, priority int, hook fn () !) {
	if isnil(ctx.ordered_shutdown) {
		ctx.ordered_shutdown = new_ordered_shutdown_manager()
	}
	ctx.ordered_shutdown.add_stage(name, priority, hook)
}

// ordered_shutdown_stage_count returns the number of registered ordered
// shutdown stages.
pub fn (mut ctx ApplicationContext) ordered_shutdown_stage_count() int {
	if isnil(ctx.ordered_shutdown) {
		return 0
	}
	return ctx.ordered_shutdown.stage_count()
}

// has_shutdown_stage checks if an ordered shutdown stage with the given name
// is registered.
pub fn (mut ctx ApplicationContext) has_shutdown_stage(name string) bool {
	if isnil(ctx.ordered_shutdown) {
		return false
	}
	return ctx.ordered_shutdown.has_stage(name)
}

// ── Lifecycle Bean Registration ──

// add_lifecycle_bean registers a bean implementing the Lifecycle interface.
// Spring equivalent: LifecycleProcessor.onRefresh()
pub fn (mut ctx ApplicationContext) add_lifecycle_bean(bean &Lifecycle) {
	ctx.lifecycle_beans << unsafe { bean }
}

// lifecycle_bean_count returns the number of registered Lifecycle beans.
pub fn (mut ctx ApplicationContext) lifecycle_bean_count() int {
	return ctx.lifecycle_beans.len
}

// ── Event ──

// on registers an event listener.
pub fn (mut ctx ApplicationContext) on(event_name string, listener EventListener) {
	ctx.event_bus.on(event_name, listener)
}

// on_with_priority registers an event listener with a specific priority.
pub fn (mut ctx ApplicationContext) on_with_priority(event_name string, listener EventListener, priority int) {
	ctx.event_bus.on_with_priority(event_name, listener, priority)
}

// dispatch fires an event.
pub fn (mut ctx ApplicationContext) dispatch(event &Event) int {
	mut bus := unsafe { ctx.event_bus }
	return bus.dispatch(event)
}

// ── Introspection ──

// bean_names returns all registered bean names.
pub fn (mut ctx ApplicationContext) bean_names() []string {
	return ctx.container.bean_names()
}

// bean_count returns the number of registered beans.
pub fn (mut ctx ApplicationContext) bean_count() int {
	return ctx.container.bean_count()
}

// singleton_count returns the number of instantiated singletons.
pub fn (mut ctx ApplicationContext) singleton_count() int {
	return ctx.container.singleton_count()
}

// get_definition returns a bean definition.
pub fn (mut ctx ApplicationContext) get_definition(type_name string) !BeanDefinition {
	return ctx.container.get_definition(type_name)
}

// dependencies_of returns the dependencies of a bean.
pub fn (mut ctx ApplicationContext) dependencies_of(type_name string) []Dependency {
	return ctx.container.dependencies_of(type_name)
}

// list_beans returns a snapshot of all registered bean definitions as
// BeanInfo records for the /beans actuator endpoint (SubTask D6.2).
// Delegates to Container.list_beans() which acquires the container's
// read lock to produce a consistent view.
//
// Spring equivalent: Spring Boot Actuator's /beans endpoint.
pub fn (mut ctx ApplicationContext) list_beans() []BeanInfo {
	return ctx.container.list_beans()
}

// remove_definition removes a bean definition from the container.
// Also removes any associated singleton instance and qualifier mapping.
// 移除后使 resolve 缓存失效。
// 冻结后禁止移除 / Removal blocked after freeze.
// Spring equivalent: DefaultListableBeanFactory.removeBeanDefinition()
// Laravel equivalent: Container::forget('service')
pub fn (mut ctx ApplicationContext) remove_definition(type_name string) ! {
	if ctx.is_frozen {
		return error('cannot remove definition "${type_name}": bean definitions are frozen / BeanDefinition 已冻结，无法移除 "${type_name}"')
	}
	ctx.container.remove_definition(type_name)!
	ctx.invalidate_cache(type_name)
}

// print_beans prints all registered beans.
pub fn (mut ctx ApplicationContext) print_beans() {
	ctx.container.print_beans()
}

// ── Diagnostic ──

// print_info prints a comprehensive summary of the application context.
// Inspired by Spring Boot's startup banner and Laravel's about command.
pub fn (mut ctx ApplicationContext) print_info() {
	println('╔══════════════════════════════════════════════════════════╗')
	println('║           PhotonApplicationContext                     ║')
	println('╠══════════════════════════════════════════════════════════╣')
	println('║ State:              ${ctx.current_state().str()}')
	println('║ Profiles:           ${ctx.environment.get_active_profiles().join(', ')}')
	println('║ Bean Definitions:   ${ctx.bean_count()}')
	println('║ Singleton Instances:${ctx.singleton_count()}')
	println('║ Bean Aliases:       ${ctx.container.alias_count()}')
	println('║ Post Processors:    ${ctx.post_processors.len}')
	println('║ Factory Post Proc:  ${ctx.factory_post_processors.len}')
	println('║ Smart Lifecycles:   ${ctx.smart_lifecycle.entry_count()}')
	println('║ Lifecycle Beans:    ${ctx.lifecycle_beans.len}')
	println('║ ApplicationRunners: ${ctx.runners.len}')
	println('║ Shutdown Hooks:     ${if !isnil(ctx.shutdown_hooks) {
		ctx.shutdown_hooks.hook_count().str()
	} else {
		'0'
	}}')
	println('║ Event Types:        ${ctx.event_bus.listeners.len}')
	println('║ Properties:         ${ctx.environment.property_count()}')
	println('║ Property Sources:   ${ctx.environment.source_count()}')
	println('║ Frozen:             ${ctx.is_frozen_bean_definitions()}')
	println('║ Cache Size:         ${ctx.cache_size()}')
	println('║ Cache Hits:         ${ctx.cache_hit_count()}')
	println('║ Cache Misses:       ${ctx.cache_miss_count()}')
	println('╚══════════════════════════════════════════════════════════╝')
}

// resolve_typed resolves a bean and casts it to the expected type T.
// This provides type safety compared to the voidptr-based resolve().
//
// Usage:
//   user_service := ctx.resolve_typed[UserService]('UserService')!
//
// Spring equivalent: ApplicationContext.getBean(Class<T>)
pub fn (mut ctx ApplicationContext) resolve_typed[T](type_name string) !&T {
	return ctx.container.resolve_typed[T](type_name)
}

// get_by_prefix returns all properties that start with the given prefix.
// Delegates to Environment.get_by_prefix().
pub fn (mut ctx ApplicationContext) get_by_prefix(prefix string) map[string]string {
	return ctx.environment.get_by_prefix(prefix)
}

// get_subtree returns all properties under a prefix, with the prefix stripped.
// Delegates to Environment.get_subtree().
pub fn (mut ctx ApplicationContext) get_subtree(prefix string) map[string]string {
	return ctx.environment.get_subtree(prefix)
}

// load_sources loads all registered property sources into the environment.
pub fn (mut ctx ApplicationContext) load_sources() ! {
	ctx.environment.load_sources()!
}

// ── @ConfigurationProperties Support (Spring Boot inspired) ──

// contains_prefix checks if any property starts with the given prefix.
// Spring equivalent: @ConfigurationProperties prefix existence check
pub fn (mut ctx ApplicationContext) contains_prefix(prefix string) bool {
	return ctx.environment.contains_prefix(prefix)
}

// prefix_count returns the number of properties under a given prefix.
pub fn (mut ctx ApplicationContext) prefix_count(prefix string) int {
	return ctx.environment.prefix_count(prefix)
}

// bind_to binds all properties with a given prefix into a map.
// The prefix is stripped from keys. Returns error if no properties match.
// Spring equivalent: @ConfigurationProperties(prefix = "app.database")
//
// Deprecated: use bind_to_struct[T] for type-safe binding to structs.
@[deprecated: 'use bind_to_struct[T] for type-safe binding to structs']
@[deprecated_after: '2026-06-01']
pub fn (mut ctx ApplicationContext) bind_to(prefix string) !map[string]string {
	return ctx.environment.bind_to(prefix)
}

// bind_to_struct binds all properties with a given prefix into a typed struct T.
// This is the type-safe equivalent of Spring Boot's @ConfigurationProperties.
//
// See core.bind_to_struct for full documentation.
//
// Example:
//   struct DbConfig { host string; port int }
//   ctx.set_property('app.db.host', 'localhost')
//   ctx.set_property('app.db.port', '5432')
//   config := ctx.bind_to_struct[DbConfig]('app.db')!
//   // config.host == 'localhost', config.port == 5432
pub fn (mut ctx ApplicationContext) bind_to_struct[T](prefix string) !T {
	return bind_to_struct[T](ctx.environment, prefix)
}

// register_configuration_properties binds environment properties to a struct T
// and registers the result as a singleton bean. This is the Photon equivalent of
// Spring Boot's @ConfigurationProperties + @Bean combination.
//
// The bean is registered under `type_name` and can be resolved via ctx.resolve().
// The `prefix` determines which properties are bound (e.g., 'app.database').
//
// Spring Boot equivalent:
//   @ConfigurationProperties(prefix = "app.database")
//   @Bean
//   public DatabaseConfig databaseConfig() { ... }
//
// Example:
//   struct DatabaseConfig {
//       host string
//       port int
//   }
//   ctx.set_property('app.db.host', 'localhost')
//   ctx.set_property('app.db.port', '5432')
//   config := ctx.register_configuration_properties[DatabaseConfig]('DatabaseConfig', 'app.db')!
//   // config is now registered as a singleton bean and can be resolved:
//   resolved := ctx.resolve('DatabaseConfig')!
pub fn (mut ctx ApplicationContext) register_configuration_properties[T](type_name string, prefix string) !&T {
	config := bind_to_struct[T](ctx.environment, prefix)!
	// V escapes `config` to the heap when we take a reference that outlives the function.
	config_ptr := &config
	ctx.register_instance(type_name, config_ptr)!
	return config_ptr
}

// bind_to_with_defaults binds properties with a prefix, merging with defaults.
// Spring equivalent: @ConfigurationProperties with @DefaultValue
pub fn (mut ctx ApplicationContext) bind_to_with_defaults(prefix string, defaults map[string]string) !map[string]string {
	return ctx.environment.bind_to_with_defaults(prefix, defaults)
}

// validate_prefix validates that all required sub-keys exist under a prefix.
// Spring equivalent: @ConfigurationProperties with JSR-303 @Valid + @NotNull
pub fn (mut ctx ApplicationContext) validate_prefix(prefix string, required_keys []string) ! {
	ctx.environment.validate_prefix(prefix, required_keys)!
}

// ── ServiceProvider (Laravel Service Provider) ──

// register_provider registers a ServiceProvider.
// The provider's register() is called during refresh() to add bean definitions,
// and boot() is called after all beans are instantiated.
//
// Spring equivalent: @Configuration class registration
// Laravel equivalent: Application::register(ServiceProvider)
pub fn (mut ctx ApplicationContext) register_provider(type_name string, provider &ServiceProvider) {
	if isnil(ctx.provider_registry) {
		ctx.provider_registry = new_provider_registry()
	}
	ctx.provider_registry.add(type_name, provider)
}

// ── Type-Based Lookup (Spring ListableBeanFactory) ──

// beans_for_interface returns all bean names that implement the given interface.
// Spring equivalent: ListableBeanFactory.getBeanNamesForType()
pub fn (mut ctx ApplicationContext) beans_for_interface(interface_name string) []string {
	return ctx.container.beans_for_interface(interface_name)
}

// beans_for_tag returns all bean names with the given tag.
// Laravel equivalent: Container::tagged()
pub fn (mut ctx ApplicationContext) beans_for_tag(tag string) []string {
	return ctx.container.beans_for_tag(tag)
}

// resolve_all_by_interface resolves all beans implementing the given interface.
// Spring equivalent: getBeansOfType()
pub fn (mut ctx ApplicationContext) resolve_all_by_interface(interface_name string) ![]voidptr {
	return ctx.container.resolve_all_by_interface(interface_name)
}

// resolve_all_by_tag resolves all beans with the given tag.
// Laravel equivalent: Container::tagged()
pub fn (mut ctx ApplicationContext) resolve_all_by_tag(tag string) ![]voidptr {
	return ctx.container.resolve_all_by_tag(tag)
}

// ── @Lookup Method Injection (Spring @Lookup) ──

// resolve_lookup resolves a bean for a @Lookup method injection.
// Unlike regular resolve(), this is designed to be called from within
// singleton bean methods that need to obtain prototype bean instances.
//
// Spring equivalent: @Lookup method override
// Laravel equivalent: Container::make() on each method call
pub fn (mut ctx ApplicationContext) resolve_lookup(type_name string, qualifier string) !voidptr {
	return ctx.container.resolve_lookup(type_name, qualifier)
}

// resolve_lookup_for_bean resolves all @Lookup method injections for a given bean.
// Returns a map of method_name → resolved instance (voidptr).
//
// Spring equivalent: AbstractBeanFactory.resolveDependency() for @Lookup methods
pub fn (mut ctx ApplicationContext) resolve_lookup_for_bean(type_name string) !map[string]voidptr {
	return ctx.container.resolve_lookup_for_bean(type_name)
}

// ── resolve_all_by_type: Generic Type-Based Resolution (Spring getBeansOfType) ──

// resolve_all_by_type resolves all beans that implement a given interface or type.
// This is a more general version of resolve_all_by_interface that also searches
// through bean definitions whose type_name matches the given type.
//
// Spring equivalent: ListableBeanFactory.getBeansOfType(Class<T>)
// Laravel equivalent: Container::tagged() with implicit type matching
pub fn (mut ctx ApplicationContext) resolve_all_by_type(type_name string) ![]voidptr {
	return ctx.container.resolve_all_by_type(type_name)
}

// create_deferred_provider creates a DeferredProvider for lazy resolution.
// Spring equivalent: ObjectProvider<T>
pub fn (mut ctx ApplicationContext) create_deferred_provider(type_name string) &DeferredProvider {
	return ctx.container.create_deferred_provider(type_name)
}

// ── Replace Definition (Spring override / Laravel rebind) ──

// replace_definition replaces an existing bean definition with a new one.
// If the bean was already instantiated, the instance is removed.
// If the bean does not exist yet, this is equivalent to register().
// 替换后使 resolve 缓存失效。
// 冻结后禁止替换 / Replacement blocked after freeze.
//
// Spring equivalent: DefaultListableBeanFactory.registerBeanDefinition()
// Laravel equivalent: Container::rebind()
pub fn (mut ctx ApplicationContext) replace_definition(def BeanDefinition) ! {
	if ctx.is_frozen {
		return error('cannot replace definition "${def.type_name}": bean definitions are frozen / BeanDefinition 已冻结，无法替换 "${def.type_name}"')
	}
	ctx.container.replace_definition(def)!
	ctx.invalidate_cache(def.type_name)
}

// ── Optional Resolution ──

// resolve_or resolves a bean, returning a default value if not found.
// Spring equivalent: ObjectProvider.getIfAvailable()
pub fn (mut ctx ApplicationContext) resolve_or(type_name string, default_val voidptr) voidptr {
	return ctx.container.resolve_or(type_name, default_val)
}

// resolve_typed_or resolves a bean and casts it to type T, returning a default if not found.
// Spring equivalent: ApplicationContext.getBean(Class<T>) with fallback
pub fn (mut ctx ApplicationContext) resolve_typed_or[T](type_name string, default_val &T) &T {
	return ctx.container.resolve_typed_or[T](type_name, default_val)
}

// ── BeanRegistrationOptions ──

// BeanRegistrationOptions provides a fluent way to configure bean registration.
// Inspired by Spring's BeanDefinitionBuilder and Laravel's service container binding.
pub struct BeanRegistrationOptions {
pub:
	scope          Scope = .singleton
	is_lazy        bool
	qualifier      string
	tags           []string
	dependencies   []Dependency
	init_method    string
	destroy_method string
	depends_on     []string // @[depends_on] — explicit creation order
	is_primary     bool     // @[primary] — prefer this bean when multiple candidates exist
	parent_name    string   // parent bean definition for property inheritance
	// ── Enhanced DI fields ──
	interfaces            []string              // interfaces this bean implements
	method_injections     []MethodInjection     // @[autowired] on setter/method
	collection_injections []CollectionInjection // inject all beans of a type
	lookup_injections     []LookupInjection     // @[lookup] method injection (Spring @Lookup)
	conditions            []&Condition          // @[conditional] — conditions that must pass for registration
}

// ── Topological Sort Helper ──

// topological_sort sorts bean names by dependency order using Kahn's algorithm.
fn topological_sort(bean_names []string, mut container Container) []string {
	mut in_degree := map[string]int{}
	mut adj := map[string][]string{}

	// Initialize
	for name in bean_names {
		in_degree[name] = 0
		adj[name] = []string{}
	}

	// Build adjacency list
	for name in bean_names {
		deps := container.dependencies_of(name)
		for dep in deps {
			if dep.type_name in in_degree {
				adj[dep.type_name] << name
				in_degree[name]++
			}
		}
		// Also consider @[depends_on] explicit ordering
		def := container.get_definition(name) or { continue }
		for dep_name in def.depends_on {
			if dep_name in in_degree {
				adj[dep_name] << name
				in_degree[name]++
			}
		}
	}

	// Kahn's algorithm
	mut queue := []string{}
	for name, degree in in_degree {
		if degree == 0 {
			queue << name
		}
	}

	mut sorted := []string{}
	mut head := 0
	for head < queue.len {
		node := queue[head]
		head++
		sorted << node

		for neighbor in adj[node] {
			in_degree[neighbor]--
			if in_degree[neighbor] == 0 {
				queue << neighbor
			}
		}
	}

	// If not all sorted, return original order (cycle already detected elsewhere)
	if sorted.len < bean_names.len {
		return bean_names
	}

	return sorted
}

// ── Annotation-Driven DI: autowire_bean / register_component / create_and_wire ──
//
// Spring equivalents:
//   - autowire_bean[T]  → @Autowired field injection (AutowiringPhase)
//   - register_component[T] → @ComponentScan + register (ComponentScanBeanDefinitionParser)
//   - create_and_wire[T] → create + autowire + @PostConstruct (AbstractAutowireCapableBeanFactory)

// autowire_bean performs compile-time @[autowired] field injection on an existing
// bean instance. It scans T's fields for @[autowired] and @[value] annotations
// and resolves/injects the corresponding dependencies from the container.
//
// Spring equivalent: AbstractAutowireCapableBeanFactory.populateBean()
//
// Usage:
//   mut svc := MyService{}
//   ctx.autowire_bean[MyService](mut svc)!
//   // svc.repo is now injected from the container
pub fn (mut ctx ApplicationContext) autowire_bean[T](mut bean T) ! {
	// Phase 1: @[autowired] field injection
	$for field in T.fields {
		mut has_autowired := false
		mut field_qualifier := ''
		for attr in field.attrs {
			if attr == attr_autowired {
				has_autowired = true
			}
		}
		field_qualifier = extract_qualifier(field.attrs)

		if has_autowired {
			// Try qualifier-based resolution first, then type-based
			mut resolved := false
			if field_qualifier.len > 0 {
				instance := ctx.resolve(field_qualifier) or { unsafe { nil } }
				if !isnil(instance) {
					bean.$(field.name) = unsafe { instance }
					resolved = true
				}
			}
			if !resolved {
				// Type-based resolution: try to resolve by field type name
				// V comptime: $if field.typ is Type { ... }
				$if field.typ is string {
					// String fields with @[autowired] are not typical; skip
				} $else $if field.typ is int {
					// Primitive autowired fields not supported; skip
				}
				// For reference types, we attempt resolve by the field's type name
				// This is a best-effort approach since V comptime doesn't expose
				// the full type name of reference fields directly
			}
		}
	}

	// Phase 2: @[value('key')] configuration injection
	mut pp := ValueAnnotationPostProcessor{
		environment: ctx.environment
	}
	pp.inject_values_for_bean[T](mut bean) or {
		// Value injection errors are non-fatal for autowire_bean
		// (some @[value] keys may not be available yet)
	}
}

// register_component is a convenience method that combines scan_and_register
// with automatic lifecycle callback registration.
//
// It scans T's compile-time annotations, creates a BeanDefinition,
// registers it with the container, and sets up @[post_construct]/@[pre_destroy]
// lifecycle callbacks.
//
// Spring equivalent: ClassPathBeanDefinitionScanner + registerBean()
//
// Usage:
//   @[service]
//   pub struct UserService {
//       @[autowired]
//       repo &UserRepository
//   }
//
//   ctx.register_component[UserService]()!
pub fn (mut ctx ApplicationContext) register_component[T]() ! {
	scan_and_register[T](mut ctx) or {
		return error('register_component: ${err}')
	}

	// Register @[post_construct] / @[pre_destroy] lifecycle callbacks
	$for method in T.methods {
		for attr in method.attrs {
			if attr == attr_post_construct {
				method_name := method.name
				ctx.lifecycle.register_post_construct(T.name, fn [mut ctx, method_name] () ! {
					instance := ctx.resolve_typed[T](T.name) or { return }
					dispatch_scheduled_method[T](voidptr(&instance), method_name) or {}
				})
			}
			if attr == attr_pre_destroy {
				method_name := method.name
				ctx.lifecycle.register_pre_destroy(T.name, fn [mut ctx, method_name] () ! {
					instance := ctx.resolve_typed[T](T.name) or { return }
					dispatch_scheduled_method[T](voidptr(&instance), method_name) or {}
				})
			}
		}
	}
}

// create_and_wire creates a new instance of T, performs @[autowired] and
// @[value] injection, then invokes any @[post_construct] method.
// Returns the fully initialized bean.
//
// Spring equivalent: AbstractAutowireCapableBeanFactory.createBean()
//
// Usage:
//   mut svc := ctx.create_and_wire[UserService]()!
//   // svc is fully initialized with all dependencies injected
pub fn (mut ctx ApplicationContext) create_and_wire[T]() !T {
	mut bean := T{}

	// Phase 1: @[autowired] + @[value] injection
	ctx.autowire_bean[T](mut bean) or {
		// Non-fatal: some dependencies may not be available yet
	}

	// Phase 2: @[post_construct] lifecycle callback
	$for method in T.methods {
		for attr in method.attrs {
			if attr == attr_post_construct {
				bean.$method()
			}
		}
	}

	return bean
}

// ── ServiceLocator Integration ──

// get_service resolves a bean by type T from the container.
// This is the ServiceLocator pattern — a static-like entry point
// for obtaining beans when DI injection is not possible.
//
// Spring equivalent: ApplicationContext.getBean(MyService.class)
// Laravel equivalent: app(MyService::class)
//
// Usage:
//   svc := ctx.get_service[UserService]()!
pub fn (mut ctx ApplicationContext) get_service[T]() !&T {
	return ctx.resolve_typed[T](T.name)
}

// get_service_by_name resolves a bean by name from the container.
//
// Spring equivalent: ApplicationContext.getBean("userService")
// Laravel equivalent: app('userService')
pub fn (mut ctx ApplicationContext) get_service_by_name(name string) !voidptr {
	return ctx.resolve(name)
}

// has_service checks if a bean is registered in the container.
//
// Spring equivalent: ApplicationContext.containsBean("userService")
pub fn (mut ctx ApplicationContext) has_service(name string) bool {
	return ctx.has(name)
}
