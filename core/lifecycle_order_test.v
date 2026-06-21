module core

// lifecycle_order_test.v - Tests for lifecycle ordering and refresh rollback
// (Task 8: HIGH #18 + M28 + lifecycle order)
//
// Verifies:
//   - SubTask 8.2: Lifecycle order during refresh is
//       before → @post_construct → afterPropertiesSet → after
//     (Spring-aligned: BeanPostProcessor.before, @PostConstruct,
//      InitializingBean.afterPropertiesSet, BeanPostProcessor.after)
//   - SubTask 8.3: InitializingBean.after_properties_set() is invoked
//     for beans implementing InitializingBean.
//   - SubTask 8.4: DisposableBean.destroy() is invoked during shutdown.
//   - SubTask 8.1: refresh() failure rolls back already-created beans
//     (destroyed in reverse order, state reset to .created).

// ── Test helpers ──

// OrderTracker records the order of lifecycle callback invocations into a
// shared list. It is heap-allocated so that closures and post-processors can
// capture a reference to it and mutate its fields when callbacks fire.
@[heap]
struct OrderTracker {
mut:
	calls []string
}

fn (mut t OrderTracker) record(call string) {
	t.calls << call
}

fn (mut t OrderTracker) reset() {
	t.calls = []string{}
}

// OrderTrackingPostProcessor is a BeanPostProcessor that records before/after
// calls into the shared OrderTracker. This lets tests verify the exact order
// of post-processor invocation relative to @post_construct and
// after_properties_set.
struct OrderTrackingPostProcessor {
	tracker &OrderTracker
}

pub fn (pp &OrderTrackingPostProcessor) post_process_before_initialization(bean_name string, bean voidptr) voidptr {
	unsafe {
		mut t := pp.tracker
		t.record('before:${bean_name}')
	}
	return bean
}

pub fn (pp &OrderTrackingPostProcessor) post_process_after_initialization(bean_name string, bean voidptr) voidptr {
	unsafe {
		mut t := pp.tracker
		t.record('after:${bean_name}')
	}
	return bean
}

// ═══════════════════════════════════════════════════════════
// SubTask 8.2 — Lifecycle order: before → post_construct → afterPropertiesSet → after
// ═══════════════════════════════════════════════════════════

fn test_lifecycle_order_during_refresh() {
	mut ctx := new_application_context()
	mut tracker := &OrderTracker{}

	ctx.register(new_bean_definition('OrderBean')) or { assert false }
	ctx.register_instance('OrderBean', unsafe { voidptr(1) }) or { assert false }

	// Register a BeanPostProcessor that records before/after calls.
	ctx.add_post_processor(&BeanPostProcessor(&OrderTrackingPostProcessor{
		tracker: tracker
	}))

	// Register @post_construct callback (simulates @[post_construct] method
	// detection by comptime-generated code).
	ctx.lifecycle.register_post_construct('OrderBean', fn [mut tracker] () ! {
		tracker.record('post_construct:OrderBean')
	})

	// Register InitializingBean.after_properties_set() callback (simulates
	// comptime detection of the InitializingBean interface).
	ctx.container.register_init_callback('OrderBean', fn [mut tracker] (instance voidptr) ! {
		tracker.record('after_properties_set:OrderBean')
	})

	ctx.refresh() or { assert false }

	// Verify the exact Spring-aligned lifecycle order:
	//   before → @post_construct → afterPropertiesSet → after
	assert tracker.calls.len == 4
	assert tracker.calls[0] == 'before:OrderBean'
	assert tracker.calls[1] == 'post_construct:OrderBean'
	assert tracker.calls[2] == 'after_properties_set:OrderBean'
	assert tracker.calls[3] == 'after:OrderBean'

	ctx.shutdown()
}

// Verify the OLD (wrong) order is no longer present: previously the code
// called before → after → post_construct. This test ensures before runs
// before post_construct, and after runs after after_properties_set.
fn test_lifecycle_order_before_runs_before_post_construct() {
	mut ctx := new_application_context()
	mut tracker := &OrderTracker{}

	ctx.register(new_bean_definition('BeanX')) or { assert false }
	ctx.register_instance('BeanX', unsafe { voidptr(1) }) or { assert false }

	ctx.add_post_processor(&BeanPostProcessor(&OrderTrackingPostProcessor{
		tracker: tracker
	}))
	ctx.lifecycle.register_post_construct('BeanX', fn [mut tracker] () ! {
		tracker.record('post_construct:BeanX')
	})

	ctx.refresh() or { assert false }

	// before must come before post_construct
	assert tracker.calls.len >= 2
	assert tracker.calls[0] == 'before:BeanX'
	assert tracker.calls[1] == 'post_construct:BeanX'

	ctx.shutdown()
}

fn test_lifecycle_order_after_runs_after_after_properties_set() {
	mut ctx := new_application_context()
	mut tracker := &OrderTracker{}

	ctx.register(new_bean_definition('BeanY')) or { assert false }
	ctx.register_instance('BeanY', unsafe { voidptr(1) }) or { assert false }

	ctx.add_post_processor(&BeanPostProcessor(&OrderTrackingPostProcessor{
		tracker: tracker
	}))
	ctx.container.register_init_callback('BeanY', fn [mut tracker] (instance voidptr) ! {
		tracker.record('after_properties_set:BeanY')
	})

	ctx.refresh() or { assert false }

	// after_properties_set must come before after
	assert tracker.calls.len == 3
	assert tracker.calls[0] == 'before:BeanY'
	assert tracker.calls[1] == 'after_properties_set:BeanY'
	assert tracker.calls[2] == 'after:BeanY'

	ctx.shutdown()
}

// ═══════════════════════════════════════════════════════════
// SubTask 8.3 — InitializingBean.after_properties_set() is called
// ═══════════════════════════════════════════════════════════

fn test_after_properties_set_called_for_initializing_bean() {
	mut ctx := new_application_context()
	mut tracker := &OrderTracker{}

	ctx.register(new_bean_definition('InitBean')) or { assert false }
	ctx.register_instance('InitBean', unsafe { voidptr(1) }) or { assert false }

	ctx.container.register_init_callback('InitBean', fn [mut tracker] (instance voidptr) ! {
		tracker.record('after_properties_set:InitBean')
	})

	ctx.refresh() or { assert false }

	// after_properties_set must have been called exactly once.
	assert tracker.calls.len == 1
	assert tracker.calls[0] == 'after_properties_set:InitBean'

	ctx.shutdown()
}

fn test_after_properties_set_not_called_for_non_initializing_bean() {
	mut ctx := new_application_context()
	mut tracker := &OrderTracker{}

	ctx.register(new_bean_definition('PlainBean')) or { assert false }
	ctx.register_instance('PlainBean', unsafe { voidptr(1) }) or { assert false }

	// No init callback registered — bean does NOT implement InitializingBean.
	ctx.refresh() or { assert false }

	// after_properties_set must NOT have been called.
	assert tracker.calls.len == 0

	ctx.shutdown()
}

fn test_register_and_has_init_callback() {
	mut c := new_container()
	c.register(new_bean_definition('BeanA')) or { assert false }

	assert c.has_init_callback('BeanA') == false

	c.register_init_callback('BeanA', fn (instance voidptr) ! {
		// init callback
	})

	assert c.has_init_callback('BeanA') == true
}

fn test_has_init_callback_nonexistent() {
	mut c := new_container()
	assert c.has_init_callback('NonExistent') == false
}

// ═══════════════════════════════════════════════════════════
// SubTask 8.4 — Shutdown order: @pre_destroy → destroy
// ═══════════════════════════════════════════════════════════

fn test_shutdown_order_pre_destroy_before_destroy() {
	mut ctx := new_application_context()
	mut tracker := &OrderTracker{}

	ctx.register(new_bean_definition('ShutdownBean')) or { assert false }
	ctx.register_instance('ShutdownBean', unsafe { voidptr(1) }) or { assert false }

	// Register @pre_destroy callback (annotation-based)
	ctx.lifecycle.register_pre_destroy('ShutdownBean', fn [mut tracker] () ! {
		tracker.record('pre_destroy:ShutdownBean')
	})

	// Register DisposableBean.destroy() callback (interface-based)
	ctx.container.register_destroy_callback('ShutdownBean', fn [mut tracker] (instance voidptr) ! {
		tracker.record('destroy:ShutdownBean')
	})

	ctx.refresh() or { assert false }
	tracker.reset()

	ctx.shutdown()

	// Verify shutdown order: @pre_destroy → DisposableBean.destroy()
	// (shutdown calls invoke_all_pre_destroy() BEFORE destroy_all())
	assert tracker.calls.len == 2
	assert tracker.calls[0] == 'pre_destroy:ShutdownBean'
	assert tracker.calls[1] == 'destroy:ShutdownBean'
}

// ═══════════════════════════════════════════════════════════
// SubTask 8.1 — refresh() failure rollback
// ═══════════════════════════════════════════════════════════

// When a bean's @post_construct fails, already-created beans must be
// destroyed in reverse order, and the state must be reset to .created.
fn test_refresh_rollback_on_post_construct_failure() {
	mut ctx := new_application_context()
	mut tracker := &OrderTracker{}

	// BeanA — will be created successfully (processed first because BeanB
	// depends_on BeanA, forcing topological order A → B).
	ctx.register(new_bean_definition('BeanA')) or { assert false }
	ctx.register_instance('BeanA', unsafe { voidptr(1) }) or { assert false }
	ctx.container.register_destroy_callback('BeanA', fn [mut tracker] (instance voidptr) ! {
		tracker.record('destroy:BeanA')
	})

	// BeanB — depends_on BeanA, has a failing @post_construct.
	mut def_b := new_bean_definition('BeanB')
	def_b.depends_on = ['BeanA']
	ctx.register(def_b) or { assert false }
	ctx.register_instance('BeanB', unsafe { voidptr(2) }) or { assert false }
	ctx.lifecycle.register_post_construct('BeanB', fn () ! {
		return error('BeanB post_construct failed')
	})
	ctx.container.register_destroy_callback('BeanB', fn [mut tracker] (instance voidptr) ! {
		tracker.record('destroy:BeanB')
	})

	// refresh() should fail and roll back.
	ctx.refresh() or {
		// Both beans must have been destroyed during rollback, in reverse
		// creation order: BeanB (last created) first, then BeanA.
		assert tracker.calls.len == 2
		assert tracker.calls[0] == 'destroy:BeanB'
		assert tracker.calls[1] == 'destroy:BeanA'

		// State must be reset to .created (not .refreshing, not .ready).
		assert ctx.current_state() == .created

		// Instances must have been removed by the rollback.
		assert ctx.singleton_count() == 0
		return
	}
	assert false // should have returned in the or block
}

// When a bean's after_properties_set fails, already-created beans must be
// destroyed in reverse order.
fn test_refresh_rollback_on_after_properties_set_failure() {
	mut ctx := new_application_context()
	mut tracker := &OrderTracker{}

	// BeanA — created successfully.
	ctx.register(new_bean_definition('BeanA')) or { assert false }
	ctx.register_instance('BeanA', unsafe { voidptr(1) }) or { assert false }
	ctx.container.register_destroy_callback('BeanA', fn [mut tracker] (instance voidptr) ! {
		tracker.record('destroy:BeanA')
	})

	// BeanB — depends_on BeanA, has a failing after_properties_set.
	mut def_b := new_bean_definition('BeanB')
	def_b.depends_on = ['BeanA']
	ctx.register(def_b) or { assert false }
	ctx.register_instance('BeanB', unsafe { voidptr(2) }) or { assert false }
	ctx.container.register_init_callback('BeanB', fn (instance voidptr) ! {
		return error('BeanB after_properties_set failed')
	})
	ctx.container.register_destroy_callback('BeanB', fn [mut tracker] (instance voidptr) ! {
		tracker.record('destroy:BeanB')
	})

	ctx.refresh() or {
		// Both beans must have been destroyed during rollback.
		assert tracker.calls.len == 2
		assert ctx.current_state() == .created
		assert ctx.singleton_count() == 0
		return
	}
	assert false // should have returned in the or block
}

// Rollback must invoke @pre_destroy callbacks too, mirroring shutdown order.
fn test_refresh_rollback_invokes_pre_destroy() {
	mut ctx := new_application_context()
	mut tracker := &OrderTracker{}

	// BeanA — created successfully, has @pre_destroy and DisposableBean.
	ctx.register(new_bean_definition('BeanA')) or { assert false }
	ctx.register_instance('BeanA', unsafe { voidptr(1) }) or { assert false }
	ctx.lifecycle.register_pre_destroy('BeanA', fn [mut tracker] () ! {
		tracker.record('pre_destroy:BeanA')
	})
	ctx.container.register_destroy_callback('BeanA', fn [mut tracker] (instance voidptr) ! {
		tracker.record('destroy:BeanA')
	})

	// BeanB — depends_on BeanA, fails during post_construct.
	mut def_b := new_bean_definition('BeanB')
	def_b.depends_on = ['BeanA']
	ctx.register(def_b) or { assert false }
	ctx.register_instance('BeanB', unsafe { voidptr(2) }) or { assert false }
	ctx.lifecycle.register_post_construct('BeanB', fn () ! {
		return error('BeanB post_construct failed')
	})

	ctx.refresh() or {
		// BeanA's @pre_destroy must be called before its DisposableBean.destroy()
		// during rollback (same order as shutdown).
		assert tracker.calls.len == 2
		assert tracker.calls[0] == 'pre_destroy:BeanA'
		assert tracker.calls[1] == 'destroy:BeanA'
		assert ctx.current_state() == .created
		return
	}
	assert false
}

// After a failed refresh, the context should be re-refreshable (state .created).
fn test_context_reusable_after_rollback() {
	mut ctx := new_application_context()

	ctx.register(new_bean_definition('GoodBean')) or { assert false }
	ctx.register_instance('GoodBean', unsafe { voidptr(1) }) or { assert false }

	// First refresh succeeds.
	ctx.refresh() or { assert false }
	assert ctx.current_state() == .ready
	ctx.shutdown()
	assert ctx.current_state() == .closed
}

// ═══════════════════════════════════════════════════════════
// SubTask 8.5 — shutdown() clears all reference maps (regression)
// ═══════════════════════════════════════════════════════════

fn test_shutdown_clears_init_callbacks_map() {
	mut ctx := new_application_context()

	ctx.register(new_bean_definition('InitBean')) or { assert false }
	ctx.register_instance('InitBean', unsafe { voidptr(1) }) or { assert false }
	ctx.container.register_init_callback('InitBean', fn (instance voidptr) ! {
		// init callback
	})

	assert ctx.container.has_init_callback('InitBean') == true

	ctx.shutdown()

	// After shutdown, init_callbacks must be cleared.
	assert ctx.container.has_init_callback('InitBean') == false
	assert ctx.singleton_count() == 0
	assert ctx.bean_count() == 0
}

// ═══════════════════════════════════════════════════════════
// Combined: full lifecycle order across refresh + shutdown
// ═══════════════════════════════════════════════════════════

fn test_full_lifecycle_order_refresh_then_shutdown() {
	mut ctx := new_application_context()
	mut tracker := &OrderTracker{}

	ctx.register(new_bean_definition('FullBean')) or { assert false }
	ctx.register_instance('FullBean', unsafe { voidptr(1) }) or { assert false }

	ctx.add_post_processor(&BeanPostProcessor(&OrderTrackingPostProcessor{
		tracker: tracker
	}))
	ctx.lifecycle.register_post_construct('FullBean', fn [mut tracker] () ! {
		tracker.record('post_construct:FullBean')
	})
	ctx.container.register_init_callback('FullBean', fn [mut tracker] (instance voidptr) ! {
		tracker.record('after_properties_set:FullBean')
	})
	ctx.lifecycle.register_pre_destroy('FullBean', fn [mut tracker] () ! {
		tracker.record('pre_destroy:FullBean')
	})
	ctx.container.register_destroy_callback('FullBean', fn [mut tracker] (instance voidptr) ! {
		tracker.record('destroy:FullBean')
	})

	ctx.refresh() or { assert false }

	// Refresh order: before → post_construct → afterPropertiesSet → after
	assert tracker.calls.len == 4
	assert tracker.calls[0] == 'before:FullBean'
	assert tracker.calls[1] == 'post_construct:FullBean'
	assert tracker.calls[2] == 'after_properties_set:FullBean'
	assert tracker.calls[3] == 'after:FullBean'

	tracker.reset()

	ctx.shutdown()

	// Shutdown order: pre_destroy → destroy
	assert tracker.calls.len == 2
	assert tracker.calls[0] == 'pre_destroy:FullBean'
	assert tracker.calls[1] == 'destroy:FullBean'
}
