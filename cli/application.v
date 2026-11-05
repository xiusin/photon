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
//
// `os.args` 直接读进程全局，所以 run() 本身无法被用例驱动 —— 它一跑就分发
// 到「刚才那个测试的 argv」。真正可测的是 run_args：把「参数从哪来」和
// 「怎么分发」拆开，测试传自己的 argv。
pub fn (mut app CliApplication) run() ! {
	app.run_args(os.args[1..])!
}

// run_args 与 run 相同，但参数由调用方给出。返回命令的退出码语义上等价于
// run：错误原样上抛，由 main 决定怎么收场。
pub fn (mut app CliApplication) run_args(args []string) ! {
	mut output := new_output()
	app.run_args_with_output(args, mut output)!
}

// option_schema_for 汇总命令声明的选项，供 argv 解析阶段使用。
//
// 单独抽出来的原因：这是「布尔选项要不要吞下一个 token」的唯一判断点，
// 只有它能被单独驱动，端到端用例才可能锁住它。
pub fn (app &CliApplication) option_schema_for(command_name string) &OptionSchema {
	mut schema := new_option_schema()
	declared := app.find_command(command_name)
	if declared != unsafe { nil } {
		if declared is AnnotatedCommand {
			annotated := unsafe { &AnnotatedCommand(declared) }
			for opt in annotated.info.options {
				// 布尔选项在命令行上是裸的 `--verbose`，不能吞下一个 token；
				// 其余选项按取值处理。
				if opt.is_bool {
					schema.declare_flag_option(opt.param_name)
				} else {
					schema.declare_value_option(opt.param_name)
				}
			}
		}
	}
	return schema
}

// run_args_with_output 与 run_args 相同，但输出目标由调用方给出。
// 用例靠它拿到「命令到底印了什么」，不必去截进程的 stdout。
pub fn (mut app CliApplication) run_args_with_output(args []string, mut output CommandOutput) ! {
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

	// 用命令声明的选项表解析参数：没有它，`--verbose build src/` 会把
	// `build` 当成 `--verbose` 的值，子命令从此消失。
	mut schema := app.option_schema_for(command_name)
	mut input := new_input_with_schema(raw_args.clone(), schema)

	// Handle global flags / 处理全局标志
	if input.has_flag('help') || input.has_flag('h') {
		if command_name == 'list' {
			app.print_help(mut output)
			return
		}
		app.print_command_help(mut output, command_name)
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

	cmd.execute(input, mut output)!
}

// print_banner displays the application banner
// print_banner 显示应用横幅
pub fn (app &CliApplication) print_banner(mut output &CommandOutput) {
	output.writeln('')
	output.writeln(green_text(bold_text('  ${app.name}')))
	output.writeln(dim_text('  version ${app.version}'))
	output.writeln('')
}

// print_help displays general help
// print_help 显示通用帮助
fn (app &CliApplication) print_help(mut output &CommandOutput) {
	app.print_banner(mut output)
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
fn (app &CliApplication) print_command_help(mut output &CommandOutput, command_name string) {
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
