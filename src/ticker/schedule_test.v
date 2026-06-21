module ticker

import time

// Shared counter for tick tests (module-level to avoid closure capture issues)
__global (
	test_tick_count int
)

// ── Cron Parser Tests ──

fn test_parse_cron_every_minute() ! {
	fields := parse_cron('* * * * *')!
	assert fields.len == 5
	assert fields[0].values.len == 60
	assert fields[1].values.len == 24
}

fn test_parse_cron_specific_time() ! {
	fields := parse_cron('30 9 * * 1-5')!
	assert 30 in fields[0].values
	assert fields[0].values.len == 1
	assert 9 in fields[1].values
	assert fields[1].values.len == 1
	assert 1 in fields[4].values
	assert 5 in fields[4].values
}

fn test_parse_cron_step() ! {
	fields := parse_cron('*/15 * * * *')!
	assert 0 in fields[0].values
	assert 15 in fields[0].values
	assert 30 in fields[0].values
	assert 45 in fields[0].values
}

fn test_parse_cron_invalid() ! {
	parse_cron('too many fields here') or { return }
	assert false
}

fn test_parse_cron_wrong_field_count() ! {
	parse_cron('1 2 3') or { return }
	assert false
}

// ── Cron Matching Tests ──

fn test_cron_matches_basic() ! {
	fields := parse_cron('0 9 * * *')!
	t := time.new(year: 2025, month: 6, day: 17, hour: 9, minute: 0)
	assert cron_matches(fields, t)
}

fn test_cron_matches_no_match() ! {
	fields := parse_cron('0 9 * * *')!
	t := time.new(year: 2025, month: 6, day: 17, hour: 10, minute: 0)
	assert !cron_matches(fields, t)
}

// ── Scheduler Tests ──

fn test_new_task_scheduler() {
	s := new_task_scheduler()
	assert s.tasks.len == 0
	assert !s.is_running
}

fn test_scheduler_every() {
	mut s := new_task_scheduler()
	b := s.every(30 * time.second)
	assert b.schedule_type == .interval
	assert b.interval_ns == i64(30 * time.second)
}

fn test_scheduler_cron() {
	mut s := new_task_scheduler()
	b := s.cron('0 9 * * *')
	assert b.schedule_type == .cron
	assert b.cron_expr == '0 9 * * *'
}

fn test_scheduler_delay() {
	mut s := new_task_scheduler()
	b := s.delay(5 * time.minute)
	assert b.schedule_type == .one_shot_delay
	assert b.delay_ns == i64(5 * time.minute)
}

fn test_scheduler_register_task() {
	mut s := new_task_scheduler()
	mut b := s.every(1 * time.second)
	b.task_fn = fn () ! {
		println('task running')
	}
	b.name_ = 'test_task'
	s.register(b)
	assert s.tasks.len == 1
	assert s.tasks[0].name == 'test_task'
}

fn test_scheduler_register_empty_task() {
	mut s := new_task_scheduler()
	b := s.every(1 * time.second)
	// No task_fn set, should be skipped
	s.register(b)
	assert s.tasks.len == 0
}

fn test_scheduler_tick_interval() {
	mut s := new_task_scheduler()
	test_tick_count = 0
	mut b := s.every(1 * time.nanosecond)
	b.task_fn = fn () ! {
		test_tick_count++
	}
	b.name_ = 'fast_task'
	s.register(b)

	s.tick()
	assert test_tick_count == 1

	s.tick()
	assert test_tick_count == 2
}

fn test_scheduler_one_shot_delay() {
	mut s := new_task_scheduler()
	test_tick_count = 0
	mut b := s.delay(0 * time.nanosecond)
	b.task_fn = fn () ! {
		test_tick_count++
	}
	b.name_ = 'one_shot'
	s.register(b)

	s.tick()
	assert test_tick_count == 1
	assert !s.tasks[0].enabled // should be disabled after execution
}

fn test_scheduler_task_count() {
	mut s := new_task_scheduler()
	assert s.task_count() == 0

	mut b1 := s.every(1 * time.second)
	b1.task_fn = fn () ! {}
	b1.name_ = 't1'
	s.register(b1)

	mut b2 := s.every(2 * time.second)
	b2.task_fn = fn () ! {}
	b2.name_ = 't2'
	s.register(b2)

	assert s.task_count() == 2
}

fn test_scheduler_enabled_count() {
	mut s := new_task_scheduler()

	mut b1 := s.every(1 * time.second)
	b1.task_fn = fn () ! {}
	b1.name_ = 't1'
	s.register(b1)

	mut b2 := s.every(2 * time.second)
	b2.task_fn = fn () ! {}
	b2.name_ = 't2'
	s.register(b2)

	assert s.enabled_count() == 2

	s.tasks[0].enabled = false
	assert s.enabled_count() == 1
}

fn test_task_builder_name() {
	mut b := &TaskBuilder{
		schedule_type: .interval
		interval_ns:   i64(10 * time.second)
	}
	b.name_ = 'my_task'
	assert b.name_ == 'my_task'
	assert b.schedule_type == .interval
	assert b.interval_ns == i64(10 * time.second)
}

fn test_parse_cron_field_single_value() ! {
	field := parse_cron_field('5', 0, 59)!
	assert field.values.len == 1
	assert 5 in field.values
}

fn test_parse_cron_field_range() ! {
	field := parse_cron_field('1-5', 0, 59)!
	assert field.values.len == 5
	assert 1 in field.values
	assert 5 in field.values
}

fn test_parse_cron_field_list() ! {
	field := parse_cron_field('1,3,5', 0, 59)!
	assert field.values.len == 3
	assert 1 in field.values
	assert 3 in field.values
	assert 5 in field.values
}

fn test_parse_cron_field_step() ! {
	field := parse_cron_field('*/10', 0, 59)!
	assert 0 in field.values
	assert 10 in field.values
	assert 20 in field.values
	assert 30 in field.values
	assert 40 in field.values
	assert 50 in field.values
}

fn test_scheduler_print_status() {
	mut s := new_task_scheduler()
	mut b := s.every(5 * time.second)
	b.task_fn = fn () ! {}
	b.name_ = 'status_test'
	s.register(b)
	s.print_status()
}

fn test_scheduler_stop() {
	mut s := new_task_scheduler()
	s.stop()
	assert !s.is_running
}

fn test_cron_matches_weekday() ! {
	fields := parse_cron('0 9 * * 1')!
	// Monday June 16, 2025
	t_mon := time.new(year: 2025, month: 6, day: 16, hour: 9, minute: 0)
	assert cron_matches(fields, t_mon)

	// Sunday June 15, 2025 (should not match)
	t_sun := time.new(year: 2025, month: 6, day: 15, hour: 9, minute: 0)
	assert !cron_matches(fields, t_sun)
}
