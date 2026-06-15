module cli

// builtin.v - Built-in CLI commands
//
// Provides standard commands:
//   - list: lists all available commands
//   - help: shows detailed help for a command
//   - serve: starts the web server

// ============================================================
// ListCommand — lists all registered commands
// ============================================================

pub struct ListCommand {
	BaseCommand
	app &CliApplication = unsafe { nil }
}

pub fn new_list_command(app &CliApplication) &ListCommand {
	return unsafe {
		&ListCommand{
			BaseCommand: BaseCommand{
				name: 'list'
				description: 'List all available commands'
				sig: ''
			}
			app: app
		}
	}
}

pub fn (c &ListCommand) execute(input &CommandInput, output &CommandOutput) ! {
	output.writeln('')
	output.writeln(green_text(bold_text('  ${c.app.name}')))
	output.writeln(dim_text('  version ${c.app.version}'))
	output.writeln('')
	output.writeln(bold_text('Available commands:'))
	output.writeln('')

	for cmd in c.app.commands {
		name := pad_right('  ${cmd.name()}', 25)
		output.writeln('${green_text(name)}${cmd.description()}')
	}

	output.writeln('')
	return
}

// ============================================================
// HelpCommand — shows help for a command
// ============================================================

pub struct HelpCommand {
	BaseCommand
	app &CliApplication = unsafe { nil }
}

pub fn new_help_command(app &CliApplication) &HelpCommand {
	return unsafe {
		&HelpCommand{
			BaseCommand: BaseCommand{
				name: 'help'
				description: 'Display help for a command'
				sig: '[command]'
			}
			app: app
		}
	}
}

pub fn (c &HelpCommand) execute(input &CommandInput, output &CommandOutput) ! {
	command_name := input.get_arg(0)

	if command_name.len == 0 {
		output.writeln(bold_text('Help'))
		output.writeln('')
		output.writeln('Usage: ${c.app.name} help <command>')
		output.writeln('')
		output.writeln('Example: ${c.app.name} help serve')
		return
	}

	cmd := c.app.find_command(command_name)
	if cmd == unsafe { nil } {
		output.error('Command "${command_name}" not found.')
		return error('command not found: ${command_name}')
	}

	output.writeln('')
	output.writeln(bold_text('Command: ${cmd.name()}'))
	output.writeln('')
	output.writeln('  Description: ${cmd.description()}')

	if cmd.signature().len > 0 {
		output.writeln('  Usage:       ${c.app.name} ${cmd.name()} ${cmd.signature()}')
	}

	output.writeln('')
	return
}

// ============================================================
// ServeCommand — starts the web server
// ============================================================

pub struct ServeCommand {
	BaseCommand
	port int
}

pub fn new_serve_command() &ServeCommand {
	return &ServeCommand{
		BaseCommand: BaseCommand{
			name: 'serve'
			description: 'Start the HTTP server'
			sig: '[--port=8080] [--host=localhost]'
		}
	}
}

pub fn (c &ServeCommand) execute(input &CommandInput, output &CommandOutput) ! {
	port_str := input.get_option_or('port', '8080')
	host := input.get_option_or('host', 'localhost')

	output.writeln('')
	output.success('Starting Photon server...')
	output.info('Host: ${host}')
	output.info('Port: ${port_str}')
	output.writeln('')

	return
}
