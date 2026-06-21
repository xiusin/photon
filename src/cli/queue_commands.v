module cli

// queue_commands.v - Queue CLI Commands (Laravel queue:work inspired)

// QueueCommandRunner is the interface for queue operations
pub interface QueueCommandRunner {
	new_worker() &WorkerRunner
	count() int
	clear_queue() !
}

// WorkerRunner is the interface for queue workers
pub interface WorkerRunner {
mut:
	run()
	tick()
	is_running() bool
}

// QueueWorkCommand processes jobs from the queue
pub struct QueueWorkCommand {
	BaseCommand
	runner &QueueCommandRunner = unsafe { nil }
}

pub fn new_queue_work_command(runner &QueueCommandRunner) &QueueWorkCommand {
	return unsafe {
		&QueueWorkCommand{
			BaseCommand: BaseCommand{
				name:        'queue:work'
				description: 'Start processing jobs from the queue'
				sig:         '[--queue=default] [--sleep=5]'
			}
			runner:      runner
		}
	}
}

pub fn (c &QueueWorkCommand) execute(input &CommandInput, output &CommandOutput) ! {
	queue_name := input.get_option_or('queue', 'default')
	sleep_secs := input.get_option_or('sleep', '5').int()

	output.writeln('')
	output.success('Queue worker started')
	output.info('  Queue: ${queue_name}')
	output.info('  Sleep: ${sleep_secs}s')
	output.info('  Polling for jobs... (Ctrl+C to stop)')
	output.writeln('')

	mut worker := c.runner.new_worker()
	worker.run()
	// In production: loop with time.sleep(sleep_secs * time.second)
	worker.tick()
	output.info('Queue worker stopped.')
	return
}

// QueueListCommand lists pending jobs
pub struct QueueListCommand {
	BaseCommand
	runner &QueueCommandRunner = unsafe { nil }
}

pub fn new_queue_list_command(runner &QueueCommandRunner) &QueueListCommand {
	return unsafe {
		&QueueListCommand{
			BaseCommand: BaseCommand{
				name:        'queue:list'
				description: 'List pending jobs in the queue'
				sig:         '[--queue=default]'
			}
			runner:      runner
		}
	}
}

pub fn (c &QueueListCommand) execute(input &CommandInput, output &CommandOutput) ! {
	queue_name := input.get_option_or('queue', 'default')
	count := c.runner.count()

	output.writeln('')
	if count == 0 {
		output.info("Queue \"${queue_name}\" is empty.")
	} else {
		output.info("Queue \"${queue_name}\": ${count} pending job(s)")
	}
	return
}

// QueueClearCommand clears all jobs
pub struct QueueClearCommand {
	BaseCommand
	runner &QueueCommandRunner = unsafe { nil }
}

pub fn new_queue_clear_command(runner &QueueCommandRunner) &QueueClearCommand {
	return unsafe {
		&QueueClearCommand{
			BaseCommand: BaseCommand{
				name:        'queue:clear'
				description: 'Clear all jobs from the default queue'
				sig:         '[--queue=default]'
			}
			runner:      runner
		}
	}
}

pub fn (c &QueueClearCommand) execute(input &CommandInput, output &CommandOutput) ! {
	_ = input
	c.runner.clear_queue()!
	output.success('Queue cleared.')
	return
}
