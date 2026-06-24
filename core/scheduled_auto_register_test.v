module core

// scheduled_auto_register_test.v - Tests for @[scheduled] auto-registration (Task C4)
//
// Verifies that:
//   1. extract_scheduled_methods[T]() correctly scans @[scheduled] methods
//   2. register_scheduled[T]() registers tasks with the Scheduler
//   3. Registered tasks auto-start when the scheduler starts
//   4. Bean-not-found returns an error
//   5. Multiple services and multiple methods per service work
//   6. Various cron expression formats are parsed correctly
//
// V comptime can only inspect types in the current compilation unit, so all
// test structs are defined in this file. The cron expressions use 5-field
// format (minute hour day month weekday) as required by ticker.parse_cron.

import sync
import time
import ticker

// ═══════════════════════════════════════════════════════════
// Test Fixtures — services with @[scheduled] methods
// ═══════════════════════════════════════════════════════════

// SchedCronService has a single @[scheduled] method with a mut receiver.
// Used to test the basic scan + register + auto-start flow.
struct SchedCronService {
mut:
	mu         sync.Mutex
	call_count int
}

@[scheduled: '* * * * *']
fn (mut s SchedCronService) heartbeat() {
	s.mu.@lock()
	s.call_count++
	s.mu.unlock()
}

// SchedMultiService has two @[scheduled] methods with different cron expressions.
// Used to test that multiple methods on the same service are all registered.
struct SchedMultiService {
mut:
	mu      sync.Mutex
	count_a int
	count_b int
}

@[scheduled: '* * * * *']
fn (mut s SchedMultiService) task_a() {
	s.mu.@lock()
	s.count_a++
	s.mu.unlock()
}

@[scheduled: '0 * * * *']
fn (mut s SchedMultiService) task_b() {
	s.mu.@lock()
	s.count_b++
	s.mu.unlock()
}

// SchedPlainService has no @[scheduled] methods.
// Used to test that extract_scheduled_methods returns an empty list.
struct SchedPlainService {
	x int
}

fn (mut s SchedPlainService) do_something() {
}

// SchedSecondService is used alongside SchedCronService to test multiple
// services registering scheduled tasks independently.
struct SchedSecondService {
mut:
	mu    sync.Mutex
	count int
}

@[scheduled: '*/5 * * * *']
fn (mut s SchedSecondService) periodic() {
	s.mu.@lock()
	s.count++
	s.mu.unlock()
}

// SchedVariousCronService uses several different cron expression formats
// to verify the parser handles all of them.
struct SchedVariousCronService {
mut:
	mu    sync.Mutex
	count int
}

@[scheduled: '0 9 * * 1-5']
fn (mut s SchedVariousCronService) weekday_report() {
	s.mu.@lock()
	s.count++
	s.mu.unlock()
}

@[scheduled: '*/15 * * * *']
fn (mut s SchedVariousCronService) every_15_min() {
	s.mu.@lock()
	s.count++
	s.mu.unlock()
}

@[scheduled: '30 0 1 1 *']
fn (mut s SchedVariousCronService) new_year() {
	s.mu.@lock()
	s.count++
	s.mu.unlock()
}

// ═══════════════════════════════════════════════════════════
// SubTask C4.1 — extract_scheduled_methods[T]() comptime scanning
// ═══════════════════════════════════════════════════════════

fn test_extract_scheduled_methods_single() {
	tasks := extract_scheduled_methods[SchedCronService]()
	assert tasks.len == 1
	assert tasks[0].method_name == 'heartbeat'
	assert tasks[0].cron_expr == '* * * * *'
}

fn test_extract_scheduled_methods_multiple() {
	tasks := extract_scheduled_methods[SchedMultiService]()
	assert tasks.len == 2
	// Methods may be in any order; collect names into a map
	mut names := map[string]bool{}
	for t in tasks {
		names[t.method_name] = true
	}
	assert 'task_a' in names
	assert 'task_b' in names
	// Verify cron expressions match the annotations
	for t in tasks {
		match t.method_name {
			'task_a' { assert t.cron_expr == '* * * * *' }
			'task_b' { assert t.cron_expr == '0 * * * *' }
			else { assert false }
		}
	}
}

fn test_extract_scheduled_methods_none() {
	tasks := extract_scheduled_methods[SchedPlainService]()
	assert tasks.len == 0
}

fn test_extract_scheduled_methods_cron_parsing() {
	// Verify the cron expression is extracted exactly as written in the
	// @[scheduled('...')] annotation, with quotes stripped.
	tasks := extract_scheduled_methods[SchedCronService]()
	assert tasks.len == 1
	assert tasks[0].cron_expr == '* * * * *'
	// The expression must be a valid 5-field cron
	fields := tasks[0].cron_expr.split(' ')
	assert fields.len == 5
}

fn test_extract_scheduled_methods_different_cron_formats() {
	// SchedVariousCronService has three methods with different cron formats:
	//   - '0 9 * * 1-5'   (weekday range)
	//   - '*/15 * * * *'  (step)
	//   - '30 0 1 1 *'    (specific date)
	tasks := extract_scheduled_methods[SchedVariousCronService]()
	assert tasks.len == 3

	mut found_weekday := false
	mut found_step := false
	mut found_date := false
	for t in tasks {
		match t.cron_expr {
			'0 9 * * 1-5' { found_weekday = true }
			'*/15 * * * *' { found_step = true }
			'30 0 1 1 *' { found_date = true }
			else {}
		}
	}
	assert found_weekday
	assert found_step
	assert found_date
}

fn test_extract_scheduled_methods_returns_struct_fields() {
	// Verify ScheduledTaskInfo struct has the expected fields
	tasks := extract_scheduled_methods[SchedCronService]()
	assert tasks.len == 1
	info := tasks[0]
	assert info.method_name.len > 0
	assert info.cron_expr.len > 0
}

// ═══════════════════════════════════════════════════════════
// SubTask C4.2 — register_scheduled[T]() registration
// ═══════════════════════════════════════════════════════════

fn test_register_scheduled_registers_task() {
	mut ctx := new_application_context()
	mut sched := ticker.new_task_scheduler()

	mut service := &SchedCronService{}
	ctx.register_instance(auto_configuration_type_name[SchedCronService](), service) or { assert false }

	assert sched.task_count() == 0
	ctx.register_scheduled[SchedCronService](mut sched) or { assert false }
	assert sched.task_count() == 1

	sched.stop()
}

fn test_register_scheduled_multiple_methods() {
	mut ctx := new_application_context()
	mut sched := ticker.new_task_scheduler()

	mut service := &SchedMultiService{}
	ctx.register_instance(auto_configuration_type_name[SchedMultiService](), service) or { assert false }

	ctx.register_scheduled[SchedMultiService](mut sched) or { assert false }
	assert sched.task_count() == 2

	sched.stop()
}

fn test_register_scheduled_bean_not_found() {
	mut ctx := new_application_context()
	mut sched := ticker.new_task_scheduler()

	// Don't register the bean — register_scheduled should return an error
	// with a bilingual message.
	ctx.register_scheduled[SchedCronService](mut sched) or {
		msg := err.msg()
		assert msg.contains('not found') || msg.contains('未找到')
		return
	}
	assert false // should have returned error above
}

fn test_register_scheduled_multiple_services() {
	mut ctx := new_application_context()
	mut sched := ticker.new_task_scheduler()

	mut service1 := &SchedCronService{}
	mut service2 := &SchedSecondService{}
	ctx.register_instance(auto_configuration_type_name[SchedCronService](), service1) or { assert false }
	ctx.register_instance(auto_configuration_type_name[SchedSecondService](), service2) or { assert false }

	ctx.register_scheduled[SchedCronService](mut sched) or { assert false }
	ctx.register_scheduled[SchedSecondService](mut sched) or { assert false }

	// SchedCronService has 1 scheduled method, SchedSecondService has 1
	assert sched.task_count() == 2

	sched.stop()
}

fn test_register_scheduled_no_scheduled_methods() {
	// Registering a service with no @[scheduled] methods should succeed
	// but register zero tasks.
	mut ctx := new_application_context()
	mut sched := ticker.new_task_scheduler()

	mut service := &SchedPlainService{}
	ctx.register_instance(auto_configuration_type_name[SchedPlainService](), service) or { assert false }

	ctx.register_scheduled[SchedPlainService](mut sched) or { assert false }
	assert sched.task_count() == 0

	sched.stop()
}

fn test_register_scheduled_various_cron_formats() {
	// All three cron expressions should parse and register successfully.
	mut ctx := new_application_context()
	mut sched := ticker.new_task_scheduler()

	mut service := &SchedVariousCronService{}
	ctx.register_instance(auto_configuration_type_name[SchedVariousCronService](), service) or { assert false }

	ctx.register_scheduled[SchedVariousCronService](mut sched) or { assert false }
	assert sched.task_count() == 3

	sched.stop()
}

// ═══════════════════════════════════════════════════════════
// SubTask C4.3 — Task auto-start integration tests
// ═══════════════════════════════════════════════════════════

fn test_register_scheduled_task_auto_starts() {
	// After register_scheduled + scheduler.start(), the @[scheduled] method
	// should execute automatically. The Scheduler's tick() runs cron tasks
	// immediately on the first tick (last_run == 0), so within ~1 second
	// the heartbeat method should have been called at least once.
	mut ctx := new_application_context()
	mut sched := ticker.new_task_scheduler()

	mut service := &SchedCronService{}
	ctx.register_instance(auto_configuration_type_name[SchedCronService](), service) or { assert false }
	ctx.register_scheduled[SchedCronService](mut sched) or { assert false }

	sched.start()

	// Wait 2 seconds — the scheduler ticks every 1 second, and the first
	// tick triggers cron tasks immediately (last_run == 0).
	time.sleep(2 * time.second)

	sched.stop()

	// Verify the task executed at least once (thread-safe read)
	service.mu.@lock()
	count := service.call_count
	service.mu.unlock()
	assert count > 0
}

fn test_register_scheduled_scheduler_integration() {
	// Verify that multiple scheduled methods on the same service all
	// execute when the scheduler starts. Both task_a and task_b use
	// cron expressions where the first run is immediate (last_run == 0).
	mut ctx := new_application_context()
	mut sched := ticker.new_task_scheduler()

	mut service := &SchedMultiService{}
	ctx.register_instance(auto_configuration_type_name[SchedMultiService](), service) or { assert false }
	ctx.register_scheduled[SchedMultiService](mut sched) or { assert false }

	sched.start()
	time.sleep(2 * time.second)
	sched.stop()

	// Both tasks should have run at least once (first run is immediate)
	service.mu.@lock()
	count_a := service.count_a
	count_b := service.count_b
	service.mu.unlock()

	assert count_a > 0
	assert count_b > 0
}

fn test_register_scheduled_multiple_services_auto_start() {
	// Two services with scheduled methods — both should auto-start.
	mut ctx := new_application_context()
	mut sched := ticker.new_task_scheduler()

	mut service1 := &SchedCronService{}
	mut service2 := &SchedSecondService{}
	ctx.register_instance(auto_configuration_type_name[SchedCronService](), service1) or { assert false }
	ctx.register_instance(auto_configuration_type_name[SchedSecondService](), service2) or { assert false }

	ctx.register_scheduled[SchedCronService](mut sched) or { assert false }
	ctx.register_scheduled[SchedSecondService](mut sched) or { assert false }

	sched.start()
	time.sleep(2 * time.second)
	sched.stop()

	// Both services' scheduled methods should have executed
	service1.mu.@lock()
	count1 := service1.call_count
	service1.mu.unlock()
	assert count1 > 0

	service2.mu.@lock()
	count2 := service2.count
	service2.mu.unlock()
	assert count2 > 0
}

fn test_register_scheduled_no_goroutine_leak() {
	// Verify that sched.stop() fully terminates the background goroutine.
	// After stop(), no more task executions should occur.
	mut ctx := new_application_context()
	mut sched := ticker.new_task_scheduler()

	mut service := &SchedCronService{}
	ctx.register_instance(auto_configuration_type_name[SchedCronService](), service) or { assert false }
	ctx.register_scheduled[SchedCronService](mut sched) or { assert false }

	sched.start()
	time.sleep(2 * time.second)
	sched.stop()

	// Record count immediately after stop
	service.mu.@lock()
	count_after_stop := service.call_count
	service.mu.unlock()

	// Wait another 2 seconds — if the goroutine leaked, the count
	// would increase (the task runs every second on the first tick pattern).
	time.sleep(2 * time.second)

	// Count should NOT have increased (goroutine has exited)
	service.mu.@lock()
	count_final := service.call_count
	service.mu.unlock()

	assert count_final == count_after_stop
}
