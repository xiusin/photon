module core

// shutdown_order_test.v - Tests for unified shutdown order (Task 16)
//
// Verifies:
//   - SubTask 16.1: shutdown() runs ordered stages in priority order:
//       web → queue → ticker → schedule → event → cache → orm → pool → core
//     Only registered stages are run; unregistered modules are skipped.
//     The "core" stage (destroy_all) runs last, after all module stages.
//   - SubTask 16.2: Each stage has a 5-second timeout — a slow stage does
//     not block shutdown forever; a warning is logged and shutdown continues.
//   - SubTask 16.3: Idempotency — calling shutdown() twice is safe.
import time

// ── Test helpers ──

// ShutdownOrderTracker records the order of shutdown stage invocations into a
// shared list. It is heap-allocated so that closures can capture a reference
// to it and mutate its fields when stages fire.
@[heap]
struct ShutdownOrderTracker {
mut:
	stages []string
}

fn (mut t ShutdownOrderTracker) record(stage string) {
	t.stages << stage
}

fn (mut t ShutdownOrderTracker) reset() {
	t.stages = []string{}
}

// ═══════════════════════════════════════════════════════════
// SubTask 16.1 — Full shutdown order: web → queue → ... → pool → core
// ═══════════════════════════════════════════════════════════

// test_shutdown_order_all_modules registers mock shutdown stages for every
// module (web, queue, ticker, schedule, event, cache, orm, pool) plus a bean
// with a destroy callback representing the "core" stage, then verifies the
// exact shutdown order.
fn test_shutdown_order_all_modules() {
	mut ctx := new_application_context()
	mut tracker := &ShutdownOrderTracker{}

	// Register mock shutdown stages for each module
	ctx.add_shutdown_stage('web', shutdown_priority_web, fn [mut tracker] () ! {
		tracker.record('web')
	})
	ctx.add_shutdown_stage('queue', shutdown_priority_queue, fn [mut tracker] () ! {
		tracker.record('queue')
	})
	ctx.add_shutdown_stage('ticker', shutdown_priority_ticker, fn [mut tracker] () ! {
		tracker.record('ticker')
	})
	ctx.add_shutdown_stage('schedule', shutdown_priority_schedule, fn [mut tracker] () ! {
		tracker.record('schedule')
	})
	ctx.add_shutdown_stage('event', shutdown_priority_event, fn [mut tracker] () ! {
		tracker.record('event')
	})
	ctx.add_shutdown_stage('cache', shutdown_priority_cache, fn [mut tracker] () ! {
		tracker.record('cache')
	})
	ctx.add_shutdown_stage('orm', shutdown_priority_orm, fn [mut tracker] () ! {
		tracker.record('orm')
	})
	ctx.add_shutdown_stage('pool', shutdown_priority_pool, fn [mut tracker] () ! {
		tracker.record('pool')
	})

	// Register a bean with a destroy callback to track the "core" stage.
	// destroy_all() is invoked after all ordered stages, so 'core' must be
	// recorded last.
	ctx.register(new_bean_definition('CoreBean')) or { assert false }
	ctx.register_instance('CoreBean', unsafe { voidptr(1) }) or { assert false }
	ctx.container.register_destroy_callback('CoreBean', fn [mut tracker] (instance voidptr) ! {
		tracker.record('core')
	})

	ctx.shutdown()

	// Verify the exact shutdown order:
	//   web → queue → ticker → schedule → event → cache → orm → pool → core
	assert tracker.stages.len == 9
	assert tracker.stages[0] == 'web'
	assert tracker.stages[1] == 'queue'
	assert tracker.stages[2] == 'ticker'
	assert tracker.stages[3] == 'schedule'
	assert tracker.stages[4] == 'event'
	assert tracker.stages[5] == 'cache'
	assert tracker.stages[6] == 'orm'
	assert tracker.stages[7] == 'pool'
	assert tracker.stages[8] == 'core'
}

// ═══════════════════════════════════════════════════════════
// SubTask 16.1 — Only registered stages are run
// ═══════════════════════════════════════════════════════════

// test_shutdown_only_registered_stages registers only web and cache stages
// and verifies that only those are run (unregistered modules are skipped).
fn test_shutdown_only_registered_stages() {
	mut ctx := new_application_context()
	mut tracker := &ShutdownOrderTracker{}

	// Register only web and cache stages
	ctx.add_shutdown_stage('web', shutdown_priority_web, fn [mut tracker] () ! {
		tracker.record('web')
	})
	ctx.add_shutdown_stage('cache', shutdown_priority_cache, fn [mut tracker] () ! {
		tracker.record('cache')
	})

	ctx.shutdown()

	// Only registered stages should be recorded, in priority order
	assert tracker.stages.len == 2
	assert tracker.stages[0] == 'web' // priority 100
	assert tracker.stages[1] == 'cache' // priority 50
}

// ═══════════════════════════════════════════════════════════
// SubTask 16.1 — Idempotency: calling shutdown() twice is safe
// ═══════════════════════════════════════════════════════════

// test_shutdown_idempotent verifies that calling shutdown() twice does not
// error and does not run stages a second time.
fn test_shutdown_idempotent() {
	mut ctx := new_application_context()
	mut tracker := &ShutdownOrderTracker{}

	ctx.add_shutdown_stage('web', shutdown_priority_web, fn [mut tracker] () ! {
		tracker.record('web')
	})

	ctx.shutdown()
	assert ctx.current_state() == .closed
	assert tracker.stages.len == 1

	// Second shutdown should not run stages again
	ctx.shutdown()
	assert ctx.current_state() == .closed
	assert tracker.stages.len == 1
}

// test_shutdown_idempotent_no_stages verifies idempotency with no stages.
fn test_shutdown_idempotent_no_stages() {
	mut ctx := new_application_context()

	ctx.shutdown()
	assert ctx.current_state() == .closed

	// Second shutdown should not panic
	ctx.shutdown()
	assert ctx.current_state() == .closed
}

// ═══════════════════════════════════════════════════════════
// SubTask 16.2 — Timeout: slow stage doesn't block forever
// ═══════════════════════════════════════════════════════════

// test_shutdown_timeout registers a slow stage that sleeps for 30 seconds
// and verifies that shutdown() completes within ~5 seconds (the timeout).
// The fast stage registered after it should still run, proving shutdown
// continues after a timeout.
fn test_shutdown_timeout() {
	mut ctx := new_application_context()
	mut tracker := &ShutdownOrderTracker{}

	// Register a slow stage that sleeps for 30 seconds (will be timed out)
	ctx.add_shutdown_stage('slow', shutdown_priority_web, fn () ! {
		time.sleep(30 * time.second)
	})

	// Register a fast stage that should still run after the slow one times out
	ctx.add_shutdown_stage('fast', shutdown_priority_cache, fn [mut tracker] () ! {
		tracker.record('cache')
	})

	start := time.now()
	ctx.shutdown()
	elapsed := time.now().unix_nano() - start.unix_nano()

	// Should have timed out after ~5 seconds (allow margin for scheduling)
	assert elapsed >= i64(4 * time.second)
	assert elapsed < i64(8 * time.second)

	// The fast stage should still have run after the slow stage timed out
	assert tracker.stages.len == 1
	assert tracker.stages[0] == 'cache'
}

// ═══════════════════════════════════════════════════════════
// SubTask 16.1 — Priority ordering (stages sorted by priority)
// ═══════════════════════════════════════════════════════════

// test_shutdown_stage_priority_ordering registers stages in random order and
// verifies they are executed in descending priority order.
fn test_shutdown_stage_priority_ordering() {
	mut ctx := new_application_context()
	mut tracker := &ShutdownOrderTracker{}

	// Register stages in non-sorted order
	ctx.add_shutdown_stage('pool', shutdown_priority_pool, fn [mut tracker] () ! {
		tracker.record('pool')
	})
	ctx.add_shutdown_stage('web', shutdown_priority_web, fn [mut tracker] () ! {
		tracker.record('web')
	})
	ctx.add_shutdown_stage('orm', shutdown_priority_orm, fn [mut tracker] () ! {
		tracker.record('orm')
	})
	ctx.add_shutdown_stage('cache', shutdown_priority_cache, fn [mut tracker] () ! {
		tracker.record('cache')
	})

	ctx.shutdown()

	// Stages should be sorted by priority descending
	assert tracker.stages.len == 4
	assert tracker.stages[0] == 'web' // priority 100
	assert tracker.stages[1] == 'cache' // priority 50
	assert tracker.stages[2] == 'orm' // priority 40
	assert tracker.stages[3] == 'pool' // priority 30
}

// ═══════════════════════════════════════════════════════════
// SubTask 16.1 — Stage replacement (same name replaces)
// ═══════════════════════════════════════════════════════════

// test_shutdown_stage_replacement verifies that registering a stage with the
// same name as an existing stage replaces the old hook.
fn test_shutdown_stage_replacement() {
	mut ctx := new_application_context()
	mut tracker := &ShutdownOrderTracker{}

	// Register a stage
	ctx.add_shutdown_stage('web', shutdown_priority_web, fn [mut tracker] () ! {
		tracker.record('web_v1')
	})

	// Replace it with a new hook (same name)
	ctx.add_shutdown_stage('web', shutdown_priority_web, fn [mut tracker] () ! {
		tracker.record('web_v2')
	})

	assert ctx.ordered_shutdown_stage_count() == 1

	ctx.shutdown()

	// Only the replacement should be recorded
	assert tracker.stages.len == 1
	assert tracker.stages[0] == 'web_v2'
}

// ═══════════════════════════════════════════════════════════
// SubTask 16.1 — Ordered stages run before bean destruction
// ═══════════════════════════════════════════════════════════

// test_ordered_stages_before_bean_destruction verifies that ordered shutdown
// stages run BEFORE bean pre_destroy and destroy callbacks. This ensures
// modules (web, orm, etc.) are stopped before beans are destroyed.
fn test_ordered_stages_before_bean_destruction() {
	mut ctx := new_application_context()
	mut tracker := &ShutdownOrderTracker{}

	// Register a web stage
	ctx.add_shutdown_stage('web', shutdown_priority_web, fn [mut tracker] () ! {
		tracker.record('web_stage')
	})

	// Register a bean with pre_destroy and destroy callbacks
	ctx.register(new_bean_definition('ServiceBean')) or { assert false }
	ctx.register_instance('ServiceBean', unsafe { voidptr(1) }) or { assert false }
	ctx.lifecycle.register_pre_destroy('ServiceBean', fn [mut tracker] () ! {
		tracker.record('pre_destroy')
	})
	ctx.container.register_destroy_callback('ServiceBean', fn [mut tracker] (instance voidptr) ! {
		tracker.record('destroy')
	})

	ctx.shutdown()

	// Order: web_stage → pre_destroy → destroy
	assert tracker.stages.len == 3
	assert tracker.stages[0] == 'web_stage'
	assert tracker.stages[1] == 'pre_destroy'
	assert tracker.stages[2] == 'destroy'
}

// ═══════════════════════════════════════════════════════════
// OrderedShutdownManager unit tests
// ═══════════════════════════════════════════════════════════

fn test_ordered_shutdown_manager_basic() {
	mut mgr := new_ordered_shutdown_manager()
	assert mgr.stage_count() == 0

	mgr.add_stage('web', shutdown_priority_web, fn () ! {})
	mgr.add_stage('cache', shutdown_priority_cache, fn () ! {})
	assert mgr.stage_count() == 2

	assert mgr.has_stage('web') == true
	assert mgr.has_stage('cache') == true
	assert mgr.has_stage('orm') == false
}

fn test_ordered_shutdown_manager_sorted() {
	mut mgr := new_ordered_shutdown_manager()
	mgr.add_stage('pool', shutdown_priority_pool, fn () ! {})
	mgr.add_stage('web', shutdown_priority_web, fn () ! {})
	mgr.add_stage('orm', shutdown_priority_orm, fn () ! {})

	sorted := mgr.stages_sorted()
	assert sorted.len == 3
	assert sorted[0].name == 'web' // priority 100
	assert sorted[1].name == 'orm' // priority 40
	assert sorted[2].name == 'pool' // priority 30
}

fn test_ordered_shutdown_manager_replace() {
	mut mgr := new_ordered_shutdown_manager()
	mgr.add_stage('web', shutdown_priority_web, fn () ! {})
	assert mgr.stage_count() == 1

	// Replace with same name — count should stay 1
	mgr.add_stage('web', shutdown_priority_web, fn () ! {})
	assert mgr.stage_count() == 1
}

// ═══════════════════════════════════════════════════════════
// ApplicationContext shutdown stage API tests
// ═══════════════════════════════════════════════════════════

fn test_application_context_add_shutdown_stage() {
	mut ctx := new_application_context()
	assert ctx.ordered_shutdown_stage_count() == 0
	assert ctx.has_shutdown_stage('web') == false

	ctx.add_shutdown_stage('web', shutdown_priority_web, fn () ! {})
	assert ctx.ordered_shutdown_stage_count() == 1
	assert ctx.has_shutdown_stage('web') == true
	assert ctx.has_shutdown_stage('cache') == false
}

fn test_application_context_shutdown_stage_priority_constants() {
	// Verify the priority constants match the documented order
	assert shutdown_priority_web == 100
	assert shutdown_priority_queue == 90
	assert shutdown_priority_ticker == 80
	assert shutdown_priority_schedule == 70
	assert shutdown_priority_event == 60
	assert shutdown_priority_cache == 50
	assert shutdown_priority_orm == 40
	assert shutdown_priority_pool == 30
	assert shutdown_priority_core == 10

	// Verify descending order
	assert shutdown_priority_web > shutdown_priority_queue
	assert shutdown_priority_queue > shutdown_priority_ticker
	assert shutdown_priority_ticker > shutdown_priority_schedule
	assert shutdown_priority_schedule > shutdown_priority_event
	assert shutdown_priority_event > shutdown_priority_cache
	assert shutdown_priority_cache > shutdown_priority_orm
	assert shutdown_priority_orm > shutdown_priority_pool
	assert shutdown_priority_pool > shutdown_priority_core
}

// ═══════════════════════════════════════════════════════════
// SubTask 16.1 — Shutdown with no registered stages (backward compat)
// ═══════════════════════════════════════════════════════════

// test_shutdown_no_stages verifies that shutdown() works correctly when no
// ordered stages are registered (backward compatibility with pre-Task 16).
fn test_shutdown_no_stages() {
	mut ctx := new_application_context()
	ctx.register(new_bean_definition('TestBean')) or { assert false }
	ctx.register_instance('TestBean', unsafe { voidptr(1) }) or { assert false }

	assert ctx.ordered_shutdown_stage_count() == 0

	ctx.shutdown()
	assert ctx.current_state() == .closed
	assert ctx.singleton_count() == 0
}

// ═══════════════════════════════════════════════════════════
// SubTask 16.1 — Stage error doesn't abort shutdown
// ═══════════════════════════════════════════════════════════

// test_shutdown_stage_error_continues verifies that an error in one stage
// does not prevent subsequent stages from running.
fn test_shutdown_stage_error_continues() {
	mut ctx := new_application_context()
	mut tracker := &ShutdownOrderTracker{}

	// First stage errors out
	ctx.add_shutdown_stage('web', shutdown_priority_web, fn () ! {
		return error('web shutdown failed')
	})

	// Second stage should still run
	ctx.add_shutdown_stage('cache', shutdown_priority_cache, fn [mut tracker] () ! {
		tracker.record('cache')
	})

	ctx.shutdown()

	// The cache stage should still have run despite the web stage error
	assert tracker.stages.len == 1
	assert tracker.stages[0] == 'cache'
}
