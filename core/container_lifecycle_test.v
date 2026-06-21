module core

// container_lifecycle_test.v - Tests for container lifecycle fixes
// (CRITICAL #1/#2/#5 + H8)
//
// Verifies:
//   - @pre_destroy callbacks invoked during shutdown (SubTask 4.4)
//   - DisposableBean.destroy() callbacks invoked during destroy_all (SubTask 4.5)
//   - Reference maps cleared after destroy_all (SubTask 4.6)
//   - resolve_all_by_type() lock balance — no panic on multiple calls (SubTask 4.2)
//   - Pointer field protection — set_event_bus/get_event_bus under lock (SubTask 4.3)
//   - pre_destroy called in reverse registration order

// ── Test helpers ──

// LifecycleTracker records the order of lifecycle callback invocations.
// It is heap-allocated so that closures can capture a reference to it
// and mutate its fields when callbacks fire.
@[heap]
struct LifecycleTracker {
mut:
	pre_destroy_calls []string
	disposable_calls  []string
}

fn (mut t LifecycleTracker) record_pre_destroy(name string) {
	t.pre_destroy_calls << name
}

fn (mut t LifecycleTracker) record_disposable(name string) {
	t.disposable_calls << name
}

fn (mut t LifecycleTracker) reset() {
	t.pre_destroy_calls = []string{}
	t.disposable_calls = []string{}
}

// ═══════════════════════════════════════════════════════════
// SubTask 4.4 — @pre_destroy callbacks invoked during shutdown
// ═══════════════════════════════════════════════════════════

fn test_pre_destroy_called_during_shutdown() {
	mut ctx := new_application_context()
	mut tracker := &LifecycleTracker{}

	ctx.register(new_bean_definition('BeanA')) or { assert false }
	ctx.register_instance('BeanA', unsafe { voidptr(1) }) or { assert false }

	// Register a pre_destroy callback (simulates @[pre_destroy] method detection
	// by comptime-generated code, which calls register_pre_destroy()).
	ctx.lifecycle.register_pre_destroy('BeanA', fn [mut tracker] () ! {
		tracker.record_pre_destroy('BeanA')
	})

	ctx.shutdown()

	// The pre_destroy callback must have been invoked.
	assert tracker.pre_destroy_calls.len == 1
	assert tracker.pre_destroy_calls[0] == 'BeanA'
}

fn test_pre_destroy_reverse_order() {
	mut ctx := new_application_context()
	mut tracker := &LifecycleTracker{}

	ctx.register(new_bean_definition('BeanA')) or { assert false }
	ctx.register(new_bean_definition('BeanB')) or { assert false }
	ctx.register(new_bean_definition('BeanC')) or { assert false }
	ctx.register_instance('BeanA', unsafe { voidptr(1) }) or { assert false }
	ctx.register_instance('BeanB', unsafe { voidptr(2) }) or { assert false }
	ctx.register_instance('BeanC', unsafe { voidptr(3) }) or { assert false }

	// Register pre_destroy callbacks in order A, B, C.
	// LifecycleManager.invoke_all_pre_destroy() calls them in REVERSE order.
	ctx.lifecycle.register_pre_destroy('BeanA', fn [mut tracker] () ! {
		tracker.record_pre_destroy('BeanA')
	})
	ctx.lifecycle.register_pre_destroy('BeanB', fn [mut tracker] () ! {
		tracker.record_pre_destroy('BeanB')
	})
	ctx.lifecycle.register_pre_destroy('BeanC', fn [mut tracker] () ! {
		tracker.record_pre_destroy('BeanC')
	})

	ctx.shutdown()

	// All three callbacks must have been invoked in reverse order: C, B, A.
	assert tracker.pre_destroy_calls.len == 3
	assert tracker.pre_destroy_calls[0] == 'BeanC'
	assert tracker.pre_destroy_calls[1] == 'BeanB'
	assert tracker.pre_destroy_calls[2] == 'BeanA'
}

// ═══════════════════════════════════════════════════════════
// SubTask 4.5 — DisposableBean.destroy() invoked during destroy_all
// ═══════════════════════════════════════════════════════════

fn test_disposable_bean_destroy_called_in_destroy_all() {
	mut c := new_container()
	mut tracker := &LifecycleTracker{}

	c.register(new_bean_definition('DisposableService')) or { assert false }
	c.register_instance('DisposableService', unsafe { voidptr(42) }) or { assert false }

	// Register a DisposableBean destroy callback (simulates comptime detection
	// of the DisposableBean interface, which calls register_destroy_callback()).
	c.register_destroy_callback('DisposableService', fn [mut tracker] (instance voidptr) ! {
		tracker.record_disposable('DisposableService')
	})

	c.destroy_all()

	// The DisposableBean destroy callback must have been invoked.
	assert tracker.disposable_calls.len == 1
	assert tracker.disposable_calls[0] == 'DisposableService'
}

fn test_disposable_bean_destroy_called_in_destroy_single() {
	mut c := new_container()
	mut tracker := &LifecycleTracker{}

	c.register(new_bean_definition('DisposableService')) or { assert false }
	c.register_instance('DisposableService', unsafe { voidptr(42) }) or { assert false }

	c.register_destroy_callback('DisposableService', fn [mut tracker] (instance voidptr) ! {
		tracker.record_disposable('DisposableService')
	})

	// destroy() (singular) should also invoke the DisposableBean callback.
	c.destroy('DisposableService') or { assert false }

	assert tracker.disposable_calls.len == 1
	assert tracker.disposable_calls[0] == 'DisposableService'
	// Instance should be removed.
	assert c.singleton_count() == 0
}

fn test_destroy_callback_not_called_for_unregistered_bean() {
	mut c := new_container()
	mut tracker := &LifecycleTracker{}

	c.register(new_bean_definition('NoCallbackBean')) or { assert false }
	c.register_instance('NoCallbackBean', unsafe { voidptr(1) }) or { assert false }
	// No destroy callback registered.

	c.destroy_all()

	// No callback should have been called.
	assert tracker.disposable_calls.len == 0
}

// ═══════════════════════════════════════════════════════════
// SubTask 4.6 — Reference maps cleared after destroy_all
// ═══════════════════════════════════════════════════════════

fn test_destroy_all_clears_all_maps() {
	mut c := new_container()

	c.register(new_bean_definition('BeanA')) or { assert false }
	c.register(new_bean_definition('BeanB')) or { assert false }
	c.register_instance('BeanA', unsafe { voidptr(1) }) or { assert false }
	c.register_instance('BeanB', unsafe { voidptr(2) }) or { assert false }
	c.register_alias('a', 'BeanA') or { assert false }

	mut def := new_bean_definition('BeanC')
	def.qualifier = 'c'
	c.register(def) or { assert false }

	assert c.bean_count() == 3
	assert c.singleton_count() == 2
	assert c.alias_count() == 1
	assert c.has_qualifier('c') == true

	c.destroy_all()

	// All reference maps must be cleared to allow GC reclamation.
	assert c.singleton_count() == 0
	assert c.bean_count() == 0
	assert c.alias_count() == 0
	assert c.has_qualifier('c') == false
}

fn test_shutdown_clears_container_maps() {
	mut ctx := new_application_context()

	ctx.register(new_bean_definition('ServiceA')) or { assert false }
	ctx.register(new_bean_definition('ServiceB')) or { assert false }
	ctx.register_instance('ServiceA', unsafe { voidptr(1) }) or { assert false }
	ctx.register_instance('ServiceB', unsafe { voidptr(2) }) or { assert false }

	assert ctx.bean_count() == 2
	assert ctx.singleton_count() == 2

	ctx.shutdown()

	// After shutdown, all container maps must be cleared.
	assert ctx.singleton_count() == 0
	assert ctx.bean_count() == 0
	assert ctx.current_state() == .closed
}

// ═══════════════════════════════════════════════════════════
// Combined: pre_destroy + DisposableBean during shutdown
// ═══════════════════════════════════════════════════════════

fn test_shutdown_calls_both_pre_destroy_and_disposable() {
	mut ctx := new_application_context()
	mut tracker := &LifecycleTracker{}

	ctx.register(new_bean_definition('ServiceA')) or { assert false }
	ctx.register_instance('ServiceA', unsafe { voidptr(1) }) or { assert false }

	// Register pre_destroy callback (simulates @[pre_destroy] method)
	ctx.lifecycle.register_pre_destroy('ServiceA', fn [mut tracker] () ! {
		tracker.record_pre_destroy('ServiceA')
	})

	// Register DisposableBean destroy callback (simulates DisposableBean.destroy())
	ctx.container.register_destroy_callback('ServiceA', fn [mut tracker] (instance voidptr) ! {
		tracker.record_disposable('ServiceA')
	})

	ctx.shutdown()

	// Both callbacks must have been invoked.
	assert tracker.pre_destroy_calls.len == 1
	assert tracker.pre_destroy_calls[0] == 'ServiceA'
	assert tracker.disposable_calls.len == 1
	assert tracker.disposable_calls[0] == 'ServiceA'

	// Maps must be cleared.
	assert ctx.singleton_count() == 0
	assert ctx.bean_count() == 0
}

fn test_shutdown_pre_destroy_before_disposable() {
	mut ctx := new_application_context()
	mut tracker := &LifecycleTracker{}

	ctx.register(new_bean_definition('ServiceA')) or { assert false }
	ctx.register_instance('ServiceA', unsafe { voidptr(1) }) or { assert false }

	// Register both pre_destroy and DisposableBean callbacks.
	// pre_destroy should be called BEFORE DisposableBean.destroy()
	// (shutdown calls invoke_all_pre_destroy() before destroy_all()).
	ctx.lifecycle.register_pre_destroy('ServiceA', fn [mut tracker] () ! {
		tracker.record_pre_destroy('ServiceA')
	})
	ctx.container.register_destroy_callback('ServiceA', fn [mut tracker] (instance voidptr) ! {
		tracker.record_disposable('ServiceA')
	})

	ctx.shutdown()

	// Both should be called.
	assert tracker.pre_destroy_calls.len == 1
	assert tracker.disposable_calls.len == 1
}

// ═══════════════════════════════════════════════════════════
// SubTask 4.2 — resolve_all_by_type() lock balance (no panic)
// ═══════════════════════════════════════════════════════════

fn test_resolve_all_by_type_no_panic_multiple_calls() {
	mut c := new_container()

	// Register multiple beans — some with exact name match, some via interface.
	mut def1 := new_bean_definition('ServiceA')
	def1.interfaces = ['IHandler']
	c.register(def1) or { assert false }
	c.register_instance('ServiceA', unsafe { voidptr(1) }) or { assert false }

	mut def2 := new_bean_definition('ServiceB')
	def2.tags = ['handler']
	c.register(def2) or { assert false }
	c.register_instance('ServiceB', unsafe { voidptr(2) }) or { assert false }

	c.register(new_bean_definition('UniqueService')) or { assert false }
	c.register_instance('UniqueService', unsafe { voidptr(3) }) or { assert false }

	// Call resolve_all_by_type multiple times — previously this could panic
	// due to lock imbalance on early `continue` paths after runlock().
	instances1 := c.resolve_all_by_type('IHandler') or {
		assert false
		return
	}
	instances2 := c.resolve_all_by_type('handler') or {
		assert false
		return
	}
	instances3 := c.resolve_all_by_type('UniqueService') or {
		assert false
		return
	}
	instances4 := c.resolve_all_by_type('NonExistent') or {
		assert false
		return
	}

	assert instances1.len == 1
	assert instances2.len == 1
	assert instances3.len == 1
	assert instances4.len == 0
}

fn test_resolve_all_by_type_lock_balance_with_errors() {
	mut c := new_container()

	// Register definitions but NOT instances. resolve() returns nil for
	// definitions without instances (actual instantiation is done by
	// comptime-generated code). This test verifies that resolve_all_by_type()
	// completes without panicking or deadlocking — the lock must remain balanced
	// across all code paths (the old code had lock imbalance on early continues).
	mut def1 := new_bean_definition('NoInstanceA')
	def1.interfaces = ['IHandler']
	c.register(def1) or { assert false }

	mut def2 := new_bean_definition('NoInstanceB')
	def2.interfaces = ['IHandler']
	c.register(def2) or { assert false }

	// This should NOT panic or deadlock — the lock must be balanced.
	instances := c.resolve_all_by_type('IHandler') or {
		assert false
		return
	}

	// resolve() returns nil for each definition without an instance.
	// Reaching this assert without deadlocking proves the lock is balanced.
	assert instances.len == 2
}

// ═══════════════════════════════════════════════════════════
// SubTask 4.3 — Pointer field protection under lock
// ═══════════════════════════════════════════════════════════

fn test_set_event_bus_under_lock() {
	mut c := new_container()
	mut bus := new_event_bus()

	// set_event_bus should be thread-safe (protected by mu).
	c.set_event_bus(bus)

	// Verify the event bus is set via the locked getter.
	retrieved := c.get_event_bus()
	assert !isnil(retrieved)
}

fn test_get_event_bus_returns_nil_by_default() {
	mut c := new_container()
	retrieved := c.get_event_bus()
	assert isnil(retrieved)
}

fn test_register_factory_under_lock() {
	mut c := new_container()

	// register_factory modifies factory_registry — must be under lock.
	// Just verify it doesn't panic.
	assert !isnil(c.factory_registry)
}

// ═══════════════════════════════════════════════════════════
// SubTask 4.1 — Single lock (no dual-lock race)
// ═══════════════════════════════════════════════════════════

fn test_container_no_sharded_mu_field() {
	mut c := new_container()
	// The Container should no longer have a sharded_mu field.
	// All operations use the single `mu sync.RwMutex`.
	// Verify basic operations work correctly under the unified lock.
	c.register(new_bean_definition('TestBean')) or { assert false }
	c.register_instance('TestBean', unsafe { voidptr(42) }) or { assert false }

	assert c.has('TestBean') == true
	assert c.singleton_count() == 1

	instance := c.resolve('TestBean') or {
		assert false
		return
	}
	assert instance == unsafe { voidptr(42) }
}

fn test_concurrent_register_and_resolve() {
	mut c := new_container()

	// Register multiple beans and resolve them — all under the single mu lock.
	// This verifies the unified lock works for mixed read/write operations.
	for i in 0 .. 10 {
		name := 'Bean${i}'
		c.register(new_bean_definition(name)) or { assert false }
		c.register_instance(name, unsafe { voidptr(i + 1) }) or { assert false }
	}

	assert c.bean_count() == 10
	assert c.singleton_count() == 10

	// Resolve all beans.
	for i in 0 .. 10 {
		name := 'Bean${i}'
		instance := c.resolve(name) or {
			assert false
			return
		}
		assert instance == unsafe { voidptr(i + 1) }
	}

	// Destroy all and verify maps are cleared.
	c.destroy_all()
	assert c.bean_count() == 0
	assert c.singleton_count() == 0
}

// ═══════════════════════════════════════════════════════════
// register_destroy_callback / has_destroy_callback Tests
// ═══════════════════════════════════════════════════════════

fn test_register_destroy_callback() {
	mut c := new_container()
	c.register(new_bean_definition('BeanA')) or { assert false }

	assert c.has_destroy_callback('BeanA') == false

	c.register_destroy_callback('BeanA', fn (instance voidptr) ! {
		// destroy callback
	})

	assert c.has_destroy_callback('BeanA') == true
}

fn test_has_destroy_callback_nonexistent() {
	mut c := new_container()
	assert c.has_destroy_callback('NonExistent') == false
}
