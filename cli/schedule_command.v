module cli

// schedule_command.v - Schedule Run Command (Laravel schedule:run inspired)

// ScheduleRunner is the interface that scheduled task systems implement
pub interface ScheduleRunner {
mut:
	due_tasks() []&TaskRunner
}

// TaskRunner is the interface for individual scheduled tasks
pub interface TaskRunner {
mut:
	execute_with_result() !bool
	name string
}

// ScheduleCommand executes due scheduled tasks
pub struct ScheduleCommand {
	BaseCommand
pub mut:
	schedule &ScheduleRunner = unsafe { nil }
}

pub fn new_schedule_command(schedule &ScheduleRunner) &ScheduleCommand {
	return unsafe {
		&ScheduleCommand{
			BaseCommand: BaseCommand{
				name: 'schedule:run'
				description: 'Run due scheduled tasks'
				sig: '[--quiet]'
			}
			schedule: schedule
		}
	}
}

pub fn (mut c ScheduleCommand) execute(input &CommandInput, output &CommandOutput) ! {
	output.writeln('')
	output.info('Running scheduled tasks...')

	mut due := c.schedule.due_tasks()
	if due.len == 0 {
		output.info('No scheduled tasks are due.')
		return
	}

	output.info('Found ${due.len} due task(s)')
	output.writeln('')

	for mut task in due {
		output.write('  Running: ${task.name} ... ')

		success := task.execute_with_result() or {
			output.error('FAILED')
			output.error('    Error: ${err.str()}')
			false
		}
		if success {
			output.success('DONE')
		}
	}

	output.writeln('')
	output.success('Finished running scheduled tasks.')
	return
}
