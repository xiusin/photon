module core

// lifecycle.v - Bean Lifecycle Management
//
// Manages the lifecycle of beans in the container:
//   Instantiation → @[autowired] Injection → @[post_construct] → Ready → @[pre_destroy] → Destroyed
//
// Lifecycle hooks are detected at compile time via comptime $for
// scanning for @[post_construct] and @[pre_destroy] attributes.
import sync
import time

// ── LifecyclePhase ──

// LifecyclePhase represents the current phase of a bean.
pub enum LifecyclePhase {
	created     // struct instantiated, no injection yet
	injecting   // @[autowired] fields being set
	initialized // @[post_construct] called, bean is ready
	destroying  // @[pre_destroy] called, bean is shutting down
	destroyed   // bean is no longer usable
}

// str returns a human-readable lifecycle phase.
pub fn (lp LifecyclePhase) str() string {
	return match lp {
		.created { 'created' }
		.injecting { 'injecting' }
		.initialized { 'initialized' }
		.destroying { 'destroying' }
		.destroyed { 'destroyed' }
	}
}

// ── LifecycleCallback ──

// LifecycleCallback wraps a function to be called during a bean's lifecycle.
pub type LifecycleCallback = fn () !

// ── LifecycleManager ──

// LifecycleManager manages the lifecycle callbacks for all beans.
// It ensures callbacks are invoked in the correct order during
// application startup and shutdown.
//
// Thread-safety: all mutable operations are protected by sync.RwMutex.
// Invoke operations (invoke_*) use read lock to allow concurrent reads
// of the callback maps. Registration uses write lock.
pub struct LifecycleManager {
pub mut:
	post_construct_callbacks map[string]LifecycleCallback // type_name → callback
	pre_destroy_callbacks    map[string]LifecycleCallback // type_name → callback
	init_order               []string                     // ordered list of type_names for startup
	destroy_order            []string                     // reverse of init_order for shutdown
mut:
	mu sync.RwMutex
}

// new_lifecycle_manager creates an empty LifecycleManager.
pub fn new_lifecycle_manager() &LifecycleManager {
	return &LifecycleManager{
		post_construct_callbacks: map[string]LifecycleCallback{}
		pre_destroy_callbacks:    map[string]LifecycleCallback{}
		init_order:               []string{}
		destroy_order:            []string{}
	}
}

// register_post_construct registers a @[post_construct] callback for a bean.
pub fn (mut lm LifecycleManager) register_post_construct(type_name string, callback LifecycleCallback) {
	lm.mu.@lock()
	defer { lm.mu.unlock() }
	lm.post_construct_callbacks[type_name] = callback
	if type_name !in lm.init_order {
		lm.init_order << type_name
	}
}

// register_pre_destroy registers a @[pre_destroy] callback for a bean.
pub fn (mut lm LifecycleManager) register_pre_destroy(type_name string, callback LifecycleCallback) {
	lm.mu.@lock()
	defer { lm.mu.unlock() }
	lm.pre_destroy_callbacks[type_name] = callback
	if type_name !in lm.destroy_order {
		lm.destroy_order << type_name
	}
}

// invoke_post_construct calls the @[post_construct] callback for a bean.
pub fn (mut lm LifecycleManager) invoke_post_construct(type_name string) ! {
	lm.mu.rlock()
	callback := lm.post_construct_callbacks[type_name] or {
		lm.mu.runlock()
		return
	}
	lm.mu.runlock()

	callback() or { return error('post_construct failed for "${type_name}": ${err}') }
}

// invoke_pre_destroy calls the @[pre_destroy] callback for a bean.
pub fn (mut lm LifecycleManager) invoke_pre_destroy(type_name string) ! {
	lm.mu.rlock()
	callback := lm.pre_destroy_callbacks[type_name] or {
		lm.mu.runlock()
		return
	}
	lm.mu.runlock()

	callback() or { return error('pre_destroy failed for "${type_name}": ${err}') }
}

// invoke_all_post_construct calls all @[post_construct] callbacks in order.
// Order is determined by the init_order list (dependencies first).
pub fn (mut lm LifecycleManager) invoke_all_post_construct() ! {
	lm.mu.rlock()
	order := lm.init_order.clone()
	lm.mu.runlock()

	for type_name in order {
		lm.invoke_post_construct(type_name)!
	}
}

// invoke_all_pre_destroy calls all @[pre_destroy] callbacks in reverse order.
// This ensures that beans with no dependents are destroyed first.
pub fn (mut lm LifecycleManager) invoke_all_pre_destroy() ! {
	lm.mu.rlock()
	order := lm.destroy_order.clone()
	lm.mu.runlock()

	// Reverse the order for destruction
	mut reversed := order.reverse()
	for type_name in reversed {
		lm.invoke_pre_destroy(type_name) or {
			// Log but don't fail — we want to try to destroy everything
			eprintln('[Lifecycle] pre_destroy error for "${type_name}": ${err}')
		}
	}
}

// has_post_construct checks if a bean has a post_construct callback.
pub fn (lm &LifecycleManager) has_post_construct(type_name string) bool {
	return type_name in lm.post_construct_callbacks
}

// has_pre_destroy checks if a bean has a pre_destroy callback.
pub fn (lm &LifecycleManager) has_pre_destroy(type_name string) bool {
	return type_name in lm.pre_destroy_callbacks
}

// callback_count returns the total number of registered callbacks.
pub fn (lm &LifecycleManager) callback_count() (int, int) {
	return lm.post_construct_callbacks.len, lm.pre_destroy_callbacks.len
}

// ── SmartLifecycle ──

// SmartLifecycle is an interface for beans that need fine-grained
// control over their startup/shutdown order.
// Beans implementing this interface will be started/stopped in
// order of their phase value (lower phase starts first).
//
// Spring equivalent: org.springframework.context.SmartLifecycle
pub interface SmartLifecycle {
	is_running() bool
	start() !
	stop() !
	phase() int // lower = starts earlier, stops later
}

// ── ApplicationRunner ──

// ApplicationRunner is an interface for components that should execute
// after the ApplicationContext has been fully refreshed.
// This is the Photon equivalent of Spring's ApplicationRunner.
//
// Spring equivalent: org.springframework.boot.ApplicationRunner
// Laravel equivalent: Service Provider boot() method
pub interface ApplicationRunner {
	run(mut ctx ApplicationContext) !
}

// ── SmartLifecycleManager ──

// SmartLifecycleEntry wraps a SmartLifecycle bean with its phase.
pub struct SmartLifecycleEntry {
pub:
	type_name string
	bean      &SmartLifecycle = unsafe { nil }
	phase_    int
}

// SmartLifecycleManager manages SmartLifecycle beans, starting them
// in ascending phase order and stopping them in descending phase order.
//
// Thread-safety (M9): all reads/writes of `entries` are protected by
// sync.RwMutex. Registration uses write lock; iteration/count uses read
// lock. Callbacks (start/stop) are invoked OUTSIDE the lock to avoid
// deadlock if a callback re-enters the manager.
pub struct SmartLifecycleManager {
pub mut:
	entries []SmartLifecycleEntry
mut:
	mu sync.RwMutex
}

// new_smart_lifecycle_manager creates an empty SmartLifecycleManager.
pub fn new_smart_lifecycle_manager() &SmartLifecycleManager {
	return &SmartLifecycleManager{
		entries: []SmartLifecycleEntry{}
	}
}

// register adds a SmartLifecycle bean to the manager.
pub fn (mut m SmartLifecycleManager) register(type_name string, bean &SmartLifecycle) {
	phase := bean.phase()
	m.mu.@lock()
	defer { m.mu.unlock() }
	m.entries << SmartLifecycleEntry{
		type_name: type_name
		bean:      unsafe { bean }
		phase_:    phase
	}
}

// start_all starts all SmartLifecycle beans in ascending phase order.
pub fn (mut m SmartLifecycleManager) start_all() ! {
	// Under write lock: sort and clone entries so callbacks run outside the
	// lock (avoids deadlock if a callback re-enters the manager).
	m.mu.@lock()
	m.entries.sort_with_compare(fn (a &SmartLifecycleEntry, b &SmartLifecycleEntry) int {
		if a.phase_ < b.phase_ {
			return -1
		} else if a.phase_ > b.phase_ {
			return 1
		}
		return 0
	})
	entries_copy := m.entries.clone()
	m.mu.unlock()

	for entry in entries_copy {
		if !isnil(entry.bean) && !entry.bean.is_running() {
			entry.bean.start() or {
				eprintln('[SmartLifecycle] start failed for "${entry.type_name}": ${err}')
			}
		}
	}
}

// stop_all stops all SmartLifecycle beans in descending phase order.
//
// Thread-safety (M26): runs the stop callbacks in a background goroutine and
// waits up to 5 seconds for completion. If a callback hangs, stop_all returns
// after the timeout so the shutdown sequence is not blocked indefinitely. The
// background goroutine may continue running after the timeout — this is the
// standard trade-off when there is no cancellation/context mechanism.
pub fn (mut m SmartLifecycleManager) stop_all() {
	// Under write lock: sort and clone entries so callbacks run outside the
	// lock (avoids deadlock if a callback re-enters the manager).
	m.mu.@lock()
	m.entries.sort_with_compare(fn (a &SmartLifecycleEntry, b &SmartLifecycleEntry) int {
		if a.phase_ > b.phase_ {
			return -1
		} else if a.phase_ < b.phase_ {
			return 1
		}
		return 0
	})
	entries_copy := m.entries.clone()
	m.mu.unlock()

	// Nothing to stop — skip spawning a goroutine.
	if entries_copy.len == 0 {
		return
	}

	done := chan bool{cap: 1}
	spawn fn (entries []core.SmartLifecycleEntry, d chan bool) {
		for entry in entries {
			if !isnil(entry.bean) && entry.bean.is_running() {
				entry.bean.stop() or {
					eprintln('[SmartLifecycle] stop failed for "${entry.type_name}": ${err}')
				}
			}
		}
		d <- true
	}(entries_copy, done)

	// Poll for completion with a 5-second deadline. V's `select` with `else`
	// is non-blocking, so we sleep briefly between checks.
	deadline_ns := time.now().unix_nano() + i64(5 * time.second)
	for {
		select {
			_ := <-done {
				return
			}
			else {}
		}
		if time.now().unix_nano() >= deadline_ns {
			return
		}
		time.sleep(50 * time.millisecond)
	}
}

// entry_count returns the number of registered SmartLifecycle beans.
pub fn (mut m SmartLifecycleManager) entry_count() int {
	m.mu.rlock()
	defer { m.mu.runlock() }
	return m.entries.len
}

// ── Standard Application Events ──
//
// Spring equivalent: org.springframework.context.event.*
// These replace bare string event names with type-safe constants.

// ApplicationEventNames provides standardized event name constants.
// Spring equivalent: ApplicationEvent subclasses.
pub const event_context_refreshed = 'context.refreshed'
pub const event_context_started = 'context.started'
pub const event_context_stopped = 'context.stopped'
pub const event_context_closed = 'context.closed'
pub const event_bean_created = 'bean.created'
pub const event_bean_destroyed = 'bean.destroyed'

// ── InitializingBean / DisposableBean ──
//
// Spring equivalent: org.springframework.beans.factory.InitializingBean
//                   org.springframework.beans.factory.DisposableBean
//
// These interfaces provide a programmatic alternative to @[post_construct]
// and @[pre_destroy] annotations. Beans can implement these interfaces
// for lifecycle callbacks without relying on annotation scanning.

// InitializingBean is implemented by beans that need to perform
// initialization after all properties have been set.
//
// Spring equivalent: org.springframework.beans.factory.InitializingBean
//
// Usage:
//   pub struct MyService {
//       &[core.InitializingBean]  // implicit via interface
//   }
//   pub fn (mut s MyService) after_properties_set() ! {
//       // initialization logic
//   }
pub interface InitializingBean {
	after_properties_set() !
}

// DisposableBean is implemented by beans that need to perform
// cleanup before being destroyed.
//
// Spring equivalent: org.springframework.beans.factory.DisposableBean
pub interface DisposableBean {
	destroy() !
}

// ── Shutdown Hook ──
//
// Spring equivalent: Runtime.addShutdownHook() / SpringApplication.setRegisterShutdownHook()
// Provides a mechanism to register callbacks that execute during shutdown,
// ensuring graceful cleanup of resources.

// ShutdownHook is a function called during application shutdown.
pub type ShutdownHook = fn ()

// ShutdownHookManager manages shutdown hooks.
// Spring equivalent: SpringApplication.shutdownHooks
pub struct ShutdownHookManager {
pub mut:
	hooks []ShutdownHook
}

// new_shutdown_hook_manager creates an empty ShutdownHookManager.
pub fn new_shutdown_hook_manager() &ShutdownHookManager {
	return &ShutdownHookManager{
		hooks: []ShutdownHook{}
	}
}

// add_hook registers a shutdown hook.
// Spring equivalent: Runtime.addShutdownHook()
pub fn (mut m ShutdownHookManager) add_hook(hook ShutdownHook) {
	m.hooks << hook
}

// run_hooks executes all shutdown hooks in reverse registration order.
// This ensures that hooks registered later (which may depend on earlier ones)
// are cleaned up first.
pub fn (mut m ShutdownHookManager) run_hooks() {
	mut reversed := m.hooks.reverse()
	for hook in reversed {
		hook()
	}
}

// hook_count returns the number of registered shutdown hooks.
pub fn (m &ShutdownHookManager) hook_count() int {
	return m.hooks.len
}

// ── Ordered Shutdown Stages (Task 16) ──
//
// Provides a priority-ordered shutdown mechanism for coordinating shutdown
// across multiple modules (web, queue, ticker, schedule, event, cache, orm,
// pool, core). Each module registers a shutdown stage with a priority; during
// shutdown, stages are executed in descending priority order (highest first).
//
// This prevents errors caused by modules shutting down independently — e.g.,
// the web server stopping after ORM connections have already been closed.
//
// Standard shutdown order (highest priority first):
//   web(100) → queue(90) → ticker(80) → schedule(70) → event(60)
//   → cache(50) → orm(40) → pool(30) → core(10)

// Shutdown stage priority constants for standard modules.
// Higher priority stages run first during shutdown.
pub const shutdown_priority_web = 100
pub const shutdown_priority_queue = 90
pub const shutdown_priority_ticker = 80
pub const shutdown_priority_schedule = 70
pub const shutdown_priority_event = 60
pub const shutdown_priority_cache = 50
pub const shutdown_priority_orm = 40
pub const shutdown_priority_pool = 30
pub const shutdown_priority_core = 10

// ShutdownStage represents a named shutdown stage with a priority.
// Higher priority stages run first during shutdown.
pub struct ShutdownStage {
pub:
	name     string
	priority int @[required]
	hook     fn () !
}

// OrderedShutdownManager manages ordered shutdown stages.
// Stages are executed in descending priority order during shutdown.
//
// Thread-safety: all mutable operations are protected by sync.RwMutex.
pub struct OrderedShutdownManager {
pub mut:
	stages []ShutdownStage
mut:
	mu sync.RwMutex
}

// new_ordered_shutdown_manager creates an empty OrderedShutdownManager.
pub fn new_ordered_shutdown_manager() &OrderedShutdownManager {
	return &OrderedShutdownManager{
		stages: []ShutdownStage{}
	}
}

// add_stage registers a shutdown stage.
// If a stage with the same name already exists, it is replaced.
pub fn (mut m OrderedShutdownManager) add_stage(name string, priority int, hook fn () !) {
	m.mu.@lock()
	defer { m.mu.unlock() }
	for i, stage in m.stages {
		if stage.name == name {
			m.stages[i] = ShutdownStage{
				name:     name
				priority: priority
				hook:     hook
			}
			return
		}
	}
	m.stages << ShutdownStage{
		name:     name
		priority: priority
		hook:     hook
	}
}

// stages_sorted returns a copy of stages sorted by priority descending
// (highest priority first).
pub fn (mut m OrderedShutdownManager) stages_sorted() []ShutdownStage {
	m.mu.rlock()
	defer { m.mu.runlock() }
	mut sorted_stages := m.stages.clone()
	sorted_stages.sort_with_compare(fn (a &ShutdownStage, b &ShutdownStage) int {
		if a.priority > b.priority {
			return -1
		} else if a.priority < b.priority {
			return 1
		}
		return 0
	})
	return sorted_stages
}

// stage_count returns the number of registered shutdown stages.
pub fn (mut m OrderedShutdownManager) stage_count() int {
	m.mu.rlock()
	defer { m.mu.runlock() }
	return m.stages.len
}

// has_stage checks if a stage with the given name is registered.
pub fn (mut m OrderedShutdownManager) has_stage(name string) bool {
	m.mu.rlock()
	defer { m.mu.runlock() }
	for stage in m.stages {
		if stage.name == name {
			return true
		}
	}
	return false
}

// ── Lifecycle Interface (Spring Lifecycle) ──
//
// Spring equivalent: org.springframework.context.Lifecycle
// Provides a standard interface for objects that can be started and stopped.

// Lifecycle is the interface for objects that support start/stop lifecycle.
// Unlike SmartLifecycle, this is the simpler version without phase ordering.
//
// Spring equivalent: org.springframework.context.Lifecycle
pub interface Lifecycle {
	start() !
	stop() !
	is_running() bool
}

// ── ContextRefreshed ──

// ContextRefreshedEvent is dispatched when the container has been
// fully initialized and all beans are ready.
// This allows beans to perform actions that depend on the full
// application context being available.
pub struct ContextRefreshedEvent {
pub:
	timestamp i64
}

// ContextClosedEvent is dispatched when the container is shutting down.
pub struct ContextClosedEvent {
pub:
	timestamp i64
}

// ContextStartedEvent is dispatched when the ApplicationContext is started.
// Spring equivalent: ContextStartedEvent
pub struct ContextStartedEvent {
pub:
	timestamp i64
}

// ContextStoppedEvent is dispatched when the ApplicationContext is stopped.
// Spring equivalent: ContextStoppedEvent
pub struct ContextStoppedEvent {
pub:
	timestamp i64
}
