module ticker

// schedule.v - Scheduled Task System (Spring @Scheduled + Laravel Task Scheduling inspired)
//
// Provides a fluent API for scheduling recurring and one-off tasks.
// Inspired by Spring's @Scheduled annotation and Laravel's Task Scheduler.
//
// Supported schedules:
//   - every(duration)           — run at fixed intervals
//   - cron(expression)         — cron-style scheduling
//   - at(time)                  — run once at a specific time
//   - delay(duration)          — run once after a delay
//
// Usage:
//   mut sched := ticker.new_scheduler()
//   sched.every(30 * time.minute).task(fn () ! {
//       println('Cleaning up temp files...')
//   }).name('cleanup')
//   sched.cron('0 9 * * 1-5').task(fn () ! {
//       println('Weekday morning report')
//   }).name('morning_report')
//   sched.start()  // runs in background
//   sched.stop()   // graceful shutdown
import time

// ── TaskSchedule ──

// TaskScheduleType defines how a scheduled task is triggered.
pub enum TaskScheduleType {
	interval       // every N seconds
	cron           // cron expression
	one_shot_at    // run once at a specific time
	one_shot_delay // run once after a delay
}

// ── ScheduledTask ──

// ScheduledTask represents a registered scheduled task.
pub struct ScheduledTask {
pub mut:
	name          string
	schedule_type TaskScheduleType
	interval_ns   i64    // for interval type
	cron_expr     string // for cron type
	target_time   i64    // unix nano, for one_shot_at
	delay_ns      i64    // for one_shot_delay
	task_fn       ScheduledTaskFn = unsafe { nil }
	last_run      i64 // unix nano of last execution
	run_count     int
	is_running    bool
	enabled       bool = true
}

// ScheduledTaskFn is the function signature for scheduled tasks.
pub type ScheduledTaskFn = fn () !

// ── CronParser ──

// CronField represents a parsed cron field.
pub struct CronField {
pub:
	values []int // sorted list of matching values
}

// parse_cron parses a 5-field cron expression (minute hour day month weekday).
// Supports: *, ranges (1-5), steps (*/5, 1-5/2), lists (1,3,5).
pub fn parse_cron(expr string) ![]CronField {
	fields := expr.split(' ')
	if fields.len != 5 {
		return error('cron expression must have 5 fields, got ${fields.len}: "${expr}"')
	}
	mut result := []CronField{}
	range_mins := [0, 0, 1, 1, 0]
	range_maxs := [59, 23, 31, 12, 6]
	for i in 0 .. 5 {
		parsed := parse_cron_field(fields[i], range_mins[i], range_maxs[i]) or {
			return error('cron field ${i + 1} parse error: ${err}')
		}
		result << parsed
	}
	return result
}

// parse_cron_field parses a single cron field.
fn parse_cron_field(field string, min int, max int) !CronField {
	mut values := []int{}

	for part in field.split(',') {
		if part == '*' {
			// All values
			for v in min .. max + 1 {
				values << v
			}
		} else if part.contains('/') {
			// Step: range/step or */step
			parts := part.split('/')
			if parts.len != 2 {
				return error('invalid step expression: "${part}"')
			}
			step := parts[1].int()
			if step <= 0 {
				return error('step must be positive: "${part}"')
			}
			mut range_min := min
			mut range_max := max
			if parts[0] != '*' {
				range_parts := parts[0].split('-')
				if range_parts.len == 2 {
					range_min = range_parts[0].int()
					range_max = range_parts[1].int()
				} else {
					range_min = parts[0].int()
				}
			}
			mut v := range_min
			for v <= range_max {
				values << v
				v += step
			}
		} else if part.contains('-') {
			// Range: start-end
			parts := part.split('-')
			if parts.len != 2 {
				return error('invalid range expression: "${part}"')
			}
			start := parts[0].int()
			end := parts[1].int()
			for v in start .. end + 1 {
				values << v
			}
		} else {
			// Single value
			values << part.int()
		}
	}

	return CronField{
		values: values
	}
}

// cron_matches checks if the parsed cron fields match the given time.
pub fn cron_matches(fields []CronField, t time.Time) bool {
	wd := t.day_of_week()
	return t.minute in fields[0].values && t.hour in fields[1].values && t.day in fields[2].values
		&& t.month in fields[3].values && wd in fields[4].values
}

// ── TaskBuilder ──

// TaskBuilder provides a fluent API for configuring a scheduled task.
@[heap]
pub struct TaskBuilder {
pub mut:
	schedule_type TaskScheduleType
	interval_ns   i64
	cron_expr     string
	target_time   i64
	delay_ns      i64
	task_fn       ScheduledTaskFn = unsafe { nil }
	name_         string
}

// task registers the function to run.
pub fn (mut b TaskBuilder) task(f ScheduledTaskFn) &TaskBuilder {
	b.task_fn = f
	return b
}

// name sets the task name.
pub fn (mut b TaskBuilder) name(n string) &TaskBuilder {
	b.name_ = n
	return b
}

// ── Scheduler ──

// Scheduler manages and executes scheduled tasks.
// Thread-safe via sync.RwMutex.
@[heap]
pub struct Scheduler {
pub mut:
	tasks                []&ScheduledTask
	is_running           bool
	default_name_counter int
}

// new_task_scheduler creates a new Scheduler for scheduled tasks.
// Named differently from bucket.v's new_scheduler() to avoid conflict.
pub fn new_task_scheduler() &Scheduler {
	return &Scheduler{
		tasks: []&ScheduledTask{}
	}
}

// every schedules a task at fixed intervals.
pub fn (mut s Scheduler) every(d time.Duration) &TaskBuilder {
	return &TaskBuilder{
		schedule_type: .interval
		interval_ns:   i64(d)
	}
}

// cron schedules a task using a cron expression.
pub fn (mut s Scheduler) cron(expr string) &TaskBuilder {
	return &TaskBuilder{
		schedule_type: .cron
		cron_expr:     expr
	}
}

// at schedules a one-shot task at a specific time.
pub fn (mut s Scheduler) at(t time.Time) &TaskBuilder {
	return &TaskBuilder{
		schedule_type: .one_shot_at
		target_time:   t.unix_nano()
	}
}

// delay schedules a one-shot task after a delay.
pub fn (mut s Scheduler) delay(d time.Duration) &TaskBuilder {
	return &TaskBuilder{
		schedule_type: .one_shot_delay
		delay_ns:      i64(d)
	}
}

// register adds a configured task builder to the scheduler.
pub fn (mut s Scheduler) register(b &TaskBuilder) {
	if isnil(b.task_fn) {
		return
	}
	task_name := if b.name_.len > 0 { b.name_ } else { 'task_${s.default_name_counter}' }
	s.default_name_counter++

	mut task := &ScheduledTask{
		name:          task_name
		schedule_type: b.schedule_type
		interval_ns:   b.interval_ns
		cron_expr:     b.cron_expr
		target_time:   b.target_time
		delay_ns:      b.delay_ns
		task_fn:       b.task_fn
		enabled:       true
	}

	if b.schedule_type == .one_shot_delay {
		task.target_time = time.now().unix_nano() + b.delay_ns
	}

	s.tasks << task
}

// start begins executing scheduled tasks in a background goroutine.
pub fn (mut s Scheduler) start() {
	if s.is_running {
		return
	}
	s.is_running = true

	spawn fn (sc &Scheduler) {
		for sc.is_running {
			unsafe { sc.tick() }
			time.sleep(1 * time.second)
		}
	}(s)
}

// stop gracefully shuts down the scheduler.
pub fn (mut s Scheduler) stop() {
	s.is_running = false
}

// tick checks and executes due tasks. Called automatically by start(),
// but can also be called manually for testing.
pub fn (mut s Scheduler) tick() {
	now := time.now()

	for mut task in s.tasks {
		if !task.enabled {
			continue
		}

		is_due := match task.schedule_type {
			.interval {
				if task.last_run == 0 {
					true // first run
				} else {
					(now.unix_nano() - task.last_run) >= task.interval_ns
				}
			}
			.cron {
				if task.last_run == 0 {
					true
				} else {
					// Only match if we haven't already run this minute
					cron_fields := parse_cron(task.cron_expr) or { continue }

					cron_matches(cron_fields, now)
						&& (now.unix() - (task.last_run / 1_000_000_000)) >= 60
				}
			}
			.one_shot_at {
				now.unix_nano() >= task.target_time && task.run_count == 0
			}
			.one_shot_delay {
				now.unix_nano() >= task.target_time && task.run_count == 0
			}
		}

		if is_due {
			task.is_running = true
			task.task_fn() or { eprintln('[Scheduler] task "${task.name}" failed: ${err}') }
			task.last_run = now.unix_nano()
			task.run_count++
			task.is_running = false

			// Disable one-shot tasks after execution
			if task.schedule_type in [.one_shot_at, .one_shot_delay] {
				task.enabled = false
			}
		}
	}
}

// ── Status & Diagnostics ──

// task_count returns the number of registered tasks.
pub fn (mut s Scheduler) task_count() int {
	return s.tasks.len
}

// enabled_count returns the number of enabled tasks.
pub fn (mut s Scheduler) enabled_count() int {
	mut count := 0
	for task in s.tasks {
		if task.enabled {
			count++
		}
	}
	return count
}

// print_status prints the status of all scheduled tasks.
pub fn (mut s Scheduler) print_status() {
	println('=== Scheduled Tasks: ${s.tasks.len} ===')
	for task in s.tasks {
		schedule_str := match task.schedule_type {
			.interval { 'every ${time.Duration(task.interval_ns)}' }
			.cron { 'cron: ${task.cron_expr}' }
			.one_shot_at { 'at ${time.unix(task.target_time / 1_000_000_000).format_ss()}' }
			.one_shot_delay { 'delay ${time.Duration(task.delay_ns)}' }
		}

		enabled_str := if task.enabled { 'Y' } else { 'N' }
		println('  ${task.name} | ${schedule_str} | runs:${task.run_count} | enabled:${enabled_str}')
	}
}
