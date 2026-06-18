module core

// ═══════════════════════════════════════════════════════════════════
// photon/core — The Core Container
// ═══════════════════════════════════════════════════════════════════
//
// The core module provides the foundation for Photon's annotation-driven
// programming model, inspired by Spring Framework and Laravel:
//
//   Container              — IoC container with compile-time dependency injection
//   ApplicationContext     — unified application context (Spring ApplicationContext)
//   Environment            — profile + property management (Spring Environment)
//   Scanner                — comptime bean scanning and attribute parsing
//   Event                  — type-safe event dispatching system (Spring ApplicationEvent)
//   Lifecycle              — bean lifecycle management (@[post_construct] / @[pre_destroy])
//   SmartLifecycle         — fine-grained startup/shutdown control (Spring SmartLifecycle)
//   SmartLifecycleManager  — manages SmartLifecycle beans by phase order
//   ApplicationRunner      — post-refresh execution callback (Spring ApplicationRunner)
//   Condition              — conditional bean registration (@[conditional_on_*])
//   BeanPostProcessor      — bean post-processing hooks (Spring BeanPostProcessor / AOP)
//   BeanFactoryPostProcessor — bean definition modification before instantiation
//   FactoryBean            — factory-based bean creation (Spring FactoryBean)
//   ServiceLocator         — service locator pattern (Laravel app() helper)
//   AutoConfiguration      — auto-configuration system (Spring Boot AutoConfiguration)
//   BeanDefinitionBuilder  — fluent API for building BeanDefinitions
//   PropertySource         — property source interface (Spring PropertySource)
//   InitializingBean       — programmatic initialization (Spring InitializingBean)
//   DisposableBean         — programmatic destruction (Spring DisposableBean)
//   ShutdownHookManager   — shutdown callback management (Spring addShutdownHook)
//   Lifecycle              — start/stop lifecycle interface (Spring Lifecycle)
//   BeanMethod             — @[bean] method model (Spring @Bean)
//   ConfigurationClass     — @[configuration] class model (Spring @Configuration)
//
// Enhanced DI (Spring/Laravel inspired):
//   MethodInjection        — @[autowired] on setter methods (Spring method injection)
//   CollectionInjection    — inject all beans of a type (Spring List<T> injection)
//   DeferredProvider       — lazy bean resolution (Spring ObjectProvider<T>)
//   BeanTypeIndex          — type-based bean lookup index (Spring ListableBeanFactory)
//   ServiceProvider        — modular service registration (Laravel ServiceProvider)
//   ProviderRegistry       — manages discovery and loading of ServiceProviders
//   DeferredServiceProvider — deferred service loading (Laravel deferred providers)
//   ShardedRwMutex         — fine-grained sharded locking for high concurrency
//   BeanLock               — per-bean lock for safe singleton instantiation
//
// Key design patterns (Spring/Laravel equivalents):
//   - Bean aliases (ConfigurableBeanFactory.registerAlias)
//   - Hierarchical contexts (HierarchicalApplicationContext)
//   - Type-safe generic resolution (ApplicationContext.getBean(Class<T>))
//   - Nested property prefix queries (Environment.getProperty("prefix.*"))
//   - @Primary bean selection (Spring @Primary)
//   - @DependsOn explicit creation order (Spring @DependsOn)
//   - BeanDefinition property inheritance (Spring parent/child BeanDefinition)
//   - Standardized event names (Spring ApplicationEvent constants)
//   - Shutdown hooks (Spring addShutdownHook)
//   - PropertySource priority ordering (Spring MutablePropertySources)
//   - start/stop/close lifecycle (Spring Lifecycle interface)
//   - Type-based bean lookup (Spring ListableBeanFactory)
//   - Collection injection (Spring @Autowired List<T>)
//   - Deferred/lazy providers (Spring ObjectProvider<T>)
//   - Service providers (Laravel ServiceProvider)
//   - Sharded locking for high-concurrency IoC containers
//
// ── Quick Start (Container only) ──
//
//   mut container := core.new_container()
//
//   // Register beans (typically done by comptime-generated code)
//   container.register(core.BeanDefinition{
//       type_name: 'UserService'
//       scope: .singleton
//       dependencies: [core.Dependency{field_name: 'repo', type_name: 'UserRepository'}]
//       depends_on: ['ConfigService']  // explicit creation order
//   })
//
//   // Register alias
//   container.register_alias('userSvc', 'UserService')!
//
//   // Register @Primary bean
//   mut cache_def := core.new_bean_definition('RedisCache')
//   cache_def.is_primary = true
//   container.register(cache_def)!
//
//   // Check for circular dependencies
//   container.check_circular_dependencies()!
//
//   // Resolve a bean
//   instance := container.resolve('UserService')!
//
//   // Type-safe resolve (Spring getBean(Class<T>))
//   user_svc := container.resolve_typed[UserService]('UserService')!
//
//   // Resolve primary bean (Spring @Primary)
//   primary := container.resolve_primary()!
//
//   // Get merged definition with parent inheritance
//   merged := container.get_merged_definition('ExtendedService')!
//
// ── Quick Start (ApplicationContext — recommended) ──
//
//   mut app := core.new_application_context()
//   app.set_profiles(['dev'])
//
//   // Register beans
//   app.register(core.BeanDefinition{
//       type_name: 'UserService'
//       scope: .singleton
//       dependencies: [core.Dependency{field_name: 'repo', type_name: 'UserRepository'}]
//   })
//
//   // Register alias
//   app.register_alias('userSvc', 'UserService')!
//
//   // Add SmartLifecycle bean
//   app.add_smart_lifecycle('scheduler', &MyScheduler{})
//
//   // Add ApplicationRunner
//   app.add_runner(&MyStartupRunner{})
//
//   // Add shutdown hook (Spring addShutdownHook)
//   app.add_shutdown_hook(fn () {
//       println('Cleaning up resources...')
//   })
//
//   // Add Lifecycle bean
//   app.add_lifecycle_bean(&MyLifecycleBean{})
//
//   // Refresh — instantiate all eager singletons, start SmartLifecycle, run ApplicationRunners
//   app.refresh()!
//
//   // Explicit start (Spring Lifecycle.start())
//   app.start()!
//
//   // Resolve a bean
//   instance := app.resolve('UserService')!
//
//   // Listen for events using type-safe constants
//   app.on(core.event_context_refreshed, fn (e &core.Event) {
//       println('Context refreshed!')
//   })
//
//   // Stop without destroying (Spring Lifecycle.stop())
//   app.stop()!
//
//   // Graceful shutdown (stops SmartLifecycle in reverse phase order)
//   app.close()
//
// ── Service Locator (Laravel-style) ──
//
//   // Initialize once during bootstrap
//   core.init_service_locator(app_context)
//
//   // Use anywhere in code
//   svc := core.service('UserService')!
//
// ── Compile-Time Scanning ──
//
//   // In your application's comptime block:
//   $for struct_ in T.structs {
//       if core.has_component_attr(struct_.attrs) {
//           ct := core.get_component_type(struct_.attrs)
//           scope := core.extract_scope(struct_.attrs)
//           depends_on := core.extract_depends_on(struct_.attrs)
//           is_primary := core.has_primary_attr(struct_.attrs)
//           parent := core.extract_parent_name(struct_.attrs)
//           // ... build BeanDefinition and register
//       }
//   }
//
// ── Architecture Comparison ──
//
//   Spring Boot:       SpringApplication.run()  → ApplicationContext
//   Laravel:           new Application()        → Service Container
//   Photon:            new_application_context() → ApplicationContext
