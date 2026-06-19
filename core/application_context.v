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
// Thread-safety: all mutable operations are protected by a sync.RwMutex.
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
	shutdown_hooks          &ShutdownHookManager = unsafe { nil }
	lifecycle_beans         []&Lifecycle // Spring Lifecycle beans
mut:
	state ApplicationState = .created
	mu    sync.RwMutex
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
		lifecycle_beans:         []&Lifecycle{}
		state:                   .created
	}
	// Wire the container's event bus to the application's event bus
	// so bean lifecycle events (bean.created, bean.destroyed) are dispatched
	// through the application's event system.
	ctx.container.set_event_bus(ctx.event_bus)
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
pub fn (mut ctx ApplicationContext) register(def BeanDefinition) ! {
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
	ctx.register(def)!
}

// register_instance registers a pre-created instance as a singleton.
pub fn (mut ctx ApplicationContext) register_instance(type_name string, instance voidptr) ! {
	ctx.container.register_instance(type_name, instance)!
}

// register_factory registers a FactoryBean with the container.
// Laravel equivalent: Container::bind('name', fn() => new Service())
pub fn (mut ctx ApplicationContext) register_factory(factory_type_name string, factory &FactoryBean) ! {
	ctx.container.register_factory(factory_type_name, factory)!
}

// ── Bean Resolution ──

// resolve retrieves a bean by type name.
pub fn (mut ctx ApplicationContext) resolve(type_name string) !voidptr {
	return ctx.container.resolve(type_name)
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
//   6. Run BeanPostProcessors on each bean
//   7. Invoke all @[post_construct] callbacks
//   8. Start SmartLifecycle beans (in ascending phase order)
//   9. Dispatch ContextRefreshedEvent
//  10. Execute ApplicationRunners
//  11. Set state to ready
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

	for name in sorted_beans {
		def := ctx.container.get_definition(name) or { continue }
		if def.is_lazy || def.scope == .prototype {
			continue // skip lazy and prototype beans
		}
		if !def.is_singleton() {
			continue
		}

		// Resolve (instantiate) the bean
		instance := ctx.container.resolve(name) or { continue }

		// 6. Apply BeanPostProcessors
		mut processed_instance := instance
		for pp in ctx.post_processors {
			processed_instance = pp.post_process_before_initialization(name, processed_instance)
			processed_instance = pp.post_process_after_initialization(name, processed_instance)
		}

		// 7. Invoke @[post_construct]
		ctx.lifecycle.invoke_post_construct(name) or {
			eprintln('[ApplicationContext] post_construct error for "${name}": ${err}')
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
}

// shutdown gracefully shuts down the application context.
// This is the Spring equivalent of AbstractApplicationContext.close().
//
// Steps:
//   1. Dispatch ContextClosedEvent
//   2. Stop SmartLifecycle beans (in descending phase order)
//   3. Invoke all @[pre_destroy] callbacks in reverse order
//   4. Destroy all singleton instances
//   5. Set state to closed
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

	// 3. Invoke all @[pre_destroy] in reverse order
	ctx.lifecycle.invoke_all_pre_destroy() or {}

	// 3.5. Run shutdown hooks (Spring addShutdownHook)
	if !isnil(ctx.shutdown_hooks) {
		ctx.shutdown_hooks.run_hooks()
	}

	// 3.6. Stop Lifecycle beans
	for bean in ctx.lifecycle_beans {
		if !isnil(bean) && bean.is_running() {
			bean.stop() or { eprintln('[ApplicationContext] Lifecycle stop error: ${err}') }
		}
	}

	// 4. Destroy all singletons
	ctx.container.destroy_all()

	// 5. Set state to closed
	ctx.mu.@lock()
	ctx.state = .closed
	ctx.mu.unlock()
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

// remove_definition removes a bean definition from the container.
// Also removes any associated singleton instance and qualifier mapping.
// Spring equivalent: DefaultListableBeanFactory.removeBeanDefinition()
// Laravel equivalent: Container::forget('service')
pub fn (mut ctx ApplicationContext) remove_definition(type_name string) ! {
	ctx.container.remove_definition(type_name)!
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
	println('║           Photon ApplicationContext                     ║')
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
pub fn (mut ctx ApplicationContext) bind_to(prefix string) !map[string]string {
	return ctx.environment.bind_to(prefix)
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
//
// Spring equivalent: DefaultListableBeanFactory.registerBeanDefinition()
// Laravel equivalent: Container::rebind()
pub fn (mut ctx ApplicationContext) replace_definition(def BeanDefinition) ! {
	ctx.container.replace_definition(def)!
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

	// If not all sorted, return original order (cycle already detected elsewhere)
	if sorted.len < bean_names.len {
		return bean_names
	}

	return sorted
}
