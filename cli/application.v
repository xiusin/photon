module cli

// application.v - CliApplication — command registry and dispatch
//
// The CliApplication is the entry point for CLI-based Photon apps.
// Inspired by Symfony Console's Application class.
import os

// CliApplication is the main CLI entry point
pub struct CliApplication {
pub:
	name    string
	version string
pub mut:
	commands []&Command
}

// new_application creates a new CLI application
pub fn new_application(name string, version string) &CliApplication {
	return &CliApplication{
		name:    name
		version: version
	}
}

// add_command registers a command with the application
pub fn (mut app CliApplication) add_command(cmd &Command) {
	app.commands << cmd
}

// find_command looks up a command by name
pub fn (app &CliApplication) find_command(name string) &Command {
	for cmd in app.commands {
		if cmd.name() == name {
			return unsafe { cmd }
		}
	}
	return unsafe { nil }
}

// run parses arguments and dispatches the command
pub fn (mut app CliApplication) run() ! {
	args := os.args[1..]
	mut command_name := 'list'

	if args.len > 0 && !args[0].starts_with('-') {
		command_name = args[0]
	}

	mut raw_args := []string{cap: args.len + 1}
	raw_args << command_name
	for i in 1 .. args.len {
		raw_args << args[i]
	}

	// Handle case where command is the only arg
	if args.len > 0 && !args[0].starts_with('-') {
		// command is args[0]
	} else if args.len == 0 {
		// no args, use 'list'
	} else {
		// args start with flags, treat as 'list' subcommand
		raw_args = [command_name]
		for arg in args {
			raw_args << arg
		}
	}

	mut input := new_input(raw_args.clone())
	mut output := new_output()

	// Handle global flags
	if input.has_flag('help') || input.has_flag('h') {
		if command_name == 'list' {
			app.print_help(output)
			return
		}
		app.print_command_help(output, command_name)
		return
	}

	if input.has_flag('version') || input.has_flag('V') {
		output.writeln('${app.name} version ${app.version}')
		return
	}

	if input.has_flag('quiet') || input.has_flag('q') {
		output.style = .quiet
	}

	if input.has_flag('verbose') || input.has_flag('v') {
		output.style = .verbose
	}

	// Dispatch to command
	cmd := app.find_command(command_name)
	if cmd == unsafe { nil } {
		output.error('Command "${command_name}" not found. Run "${app.name} list" for available commands.')
		return error('command not found: ${command_name}')
	}

	cmd.execute(input, output)!
}

// print_banner displays the application banner
pub fn (app &CliApplication) print_banner(output &CommandOutput) {
	output.writeln('')
	output.writeln(green_text(bold_text('  ${app.name}')))
	output.writeln(dim_text('  version ${app.version}'))
	output.writeln('')
}

// print_help displays general help
fn (app &CliApplication) print_help(output &CommandOutput) {
	app.print_banner(output)
	output.writeln(bold_text('Usage:'))
	output.writeln('  ${app.name} <command> [options] [arguments]')
	output.writeln('')
	output.writeln(bold_text('Available commands:'))

	for cmd in app.commands {
		name := pad_right('  ${cmd.name()}', 25)
		output.writeln('${green_text(name)}${cmd.description()}')
	}
	output.writeln('')
}

// print_command_help displays help for a specific command
fn (app &CliApplication) print_command_help(output &CommandOutput, command_name string) {
	cmd := app.find_command(command_name)
	if cmd == unsafe { nil } {
		output.error('Command "${command_name}" not found.')
		return
	}

	output.writeln(bold_text('Command: ${cmd.name()}'))
	output.writeln('  ${cmd.description()}')
	output.writeln('')

	if cmd.signature().len > 0 {
		output.writeln(bold_text('Usage:'))
		output.writeln('  ${app.name} ${cmd.name()} ${cmd.signature()}')
		output.writeln('')
	}

	output.writeln(gray_text('Run "${app.name} list" for all commands.'))
}
