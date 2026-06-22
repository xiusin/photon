module cli

// application.v - CliApplication — command registry and dispatch
// CliApplication — 命令注册与分发入口
//
// The CliApplication is the entry point for CLI-based Photon apps.
// Inspired by Symfony Console's Application class.
import os
import strings

// CliApplication is the main CLI entry point
// CliApplication 是 CLI 主入口
pub struct CliApplication {
pub:
	name    string
	version string
pub mut:
	commands []&Command
}

// new_application creates a new CLI application
// new_application 创建新的 CLI 应用
pub fn new_application(name string, version string) &CliApplication {
	return &CliApplication{
		name:    name
		version: version
	}
}

// add_command registers a command with the application
// add_command 注册命令到应用
pub fn (mut app CliApplication) add_command(cmd &Command) {
	app.commands << cmd
}

// find_command looks up a command by name
// find_command 按名称查找命令
pub fn (app &CliApplication) find_command(name string) &Command {
	for cmd in app.commands {
		if cmd.name() == name {
			return unsafe { cmd }
		}
	}
	return unsafe { nil }
}

// run parses arguments and dispatches the command
// run 解析参数并分发命令
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

	// Handle case where command is the only arg / 处理命令是唯一参数的情况
	if args.len > 0 && !args[0].starts_with('-') {
		// command is args[0] / 命令是 args[0]
	} else if args.len == 0 {
		// no args, use 'list' / 无参数，使用 'list'
	} else {
		// args start with flags, treat as 'list' subcommand / 参数以标志开头，视为 'list' 子命令
		raw_args = [command_name]
		for arg in args {
			raw_args << arg
		}
	}

	mut input := new_input(raw_args.clone())
	mut output := new_output()

	// Handle global flags / 处理全局标志
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

	// Dispatch to command / 分发到命令
	cmd := app.find_command(command_name)
	if cmd == unsafe { nil } {
		output.error('Command "${command_name}" not found. Run "${app.name} list" for available commands.')
		return error('command not found: ${command_name}')
	}

	cmd.execute(input, output)!
}

// print_banner displays the application banner
// print_banner 显示应用横幅
pub fn (app &CliApplication) print_banner(output &CommandOutput) {
	output.writeln('')
	output.writeln(green_text(bold_text('  ${app.name}')))
	output.writeln(dim_text('  version ${app.version}'))
	output.writeln('')
}

// print_help displays general help
// print_help 显示通用帮助
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
// print_command_help 显示特定命令的帮助
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

// ============================================================
// Help Generation Methods / 帮助生成方法
// ============================================================

// generate_help generates a formatted help text string for the given command.
// Extracts description, usage, options, and arguments from the command's
// metadata. For AnnotatedCommand instances, uses the rich CommandInfo;
// for regular commands, builds help from the Command interface methods.
//
// generate_help 为给定命令生成格式化的帮助文本字符串。
// 从命令的元数据中提取描述、用法、选项和参数。
// 对于 AnnotatedCommand 实例，使用丰富的 CommandInfo；
// 对于常规命令，从 Command 接口方法构建帮助。
pub fn (app &CliApplication) generate_help(command_name string) string {
	cmd := app.find_command(command_name)
	if cmd == unsafe { nil } {
		return 'Command "${command_name}" not found.'
	}

	// Try to use AnnotatedCommand's rich info / 尝试使用 AnnotatedCommand 的丰富信息
	mut help := CommandHelp{
		name:        cmd.name()
		description: cmd.description()
		usage:       '${app.name} ${cmd.name()} ${cmd.signature()}'
	}

	// Check if it's an AnnotatedCommand with extra metadata
	// 检查是否为带有额外元数据的 AnnotatedCommand
	if cmd is AnnotatedCommand {
		annotated_cmd := unsafe { &AnnotatedCommand(cmd) }
		help = annotated_cmd.info.to_command_help()
		help.usage = '${app.name} ${help.usage}'
	}

	return help.to_help_text()
}

// generate_man_page generates a man page formatted string for the given command.
// Produces a structured document with NAME, SYNOPSIS, DESCRIPTION,
// OPTIONS, ARGUMENTS, and EXAMPLES sections following man page conventions.
//
// generate_man_page 为给定命令生成 man page 格式的字符串。
// 按照 man page 惯例，生成包含 NAME、SYNOPSIS、DESCRIPTION、
// OPTIONS、ARGUMENTS 和 EXAMPLES 段落的结构化文档。
pub fn (app &CliApplication) generate_man_page(command_name string) string {
	cmd := app.find_command(command_name)
	if cmd == unsafe { nil } {
		return 'Command "${command_name}" not found.'
	}

	mut sb := strings.new_builder(512)

	// NAME section / NAME 段落
	sb.writeln('NAME')
	sb.writeln('    ${cmd.name()} - ${cmd.description()}')
	sb.writeln('')

	// SYNOPSIS section / SYNOPSIS 段落
	sb.writeln('SYNOPSIS')
	sb.writeln('    ${app.name} ${cmd.name()} ${cmd.signature()}')
	sb.writeln('')

	// DESCRIPTION section / DESCRIPTION 段落
	sb.writeln('DESCRIPTION')
	if cmd is AnnotatedCommand {
		annotated_cmd := unsafe { &AnnotatedCommand(cmd) }
		if annotated_cmd.info.description.len > 0 {
			sb.writeln('    ${annotated_cmd.info.description}')
		} else {
			sb.writeln('    ${cmd.description()}')
		}

		// OPTIONS section from annotation info / 从注解信息生成 OPTIONS 段落
		if annotated_cmd.info.options.len > 0 {
			sb.writeln('')
			sb.writeln('OPTIONS')
			for opt in annotated_cmd.info.options {
				mut line := '    --${opt.param_name}'
				if opt.is_required {
					line += ' (required)'
				}
				sb.writeln(line)
				if opt.description.len > 0 {
					sb.writeln('        ${opt.description}')
				}
				if opt.default_val.len > 0 {
					sb.writeln('        Default: ${opt.default_val}')
				}
			}
		}

		// ARGUMENTS section from annotation info / 从注解信息生成 ARGUMENTS 段落
		if annotated_cmd.info.arguments.len > 0 {
			sb.writeln('')
			sb.writeln('ARGUMENTS')
			for arg in annotated_cmd.info.arguments {
				mut line := '    <${arg.param_name}>'
				if arg.is_required {
					line += ' (required)'
				}
				sb.writeln(line)
				if arg.description.len > 0 {
					sb.writeln('        ${arg.description}')
				}
				if arg.default_val.len > 0 {
					sb.writeln('        Default: ${arg.default_val}')
				}
			}
		}
	} else {
		sb.writeln('    ${cmd.description()}')
	}

	// SEE ALSO section / SEE ALSO 段落
	sb.writeln('')
	sb.writeln('SEE ALSO')
	sb.writeln('    ${app.name} list')
	sb.writeln('    ${app.name} help <command>')

	return sb.str()
}
