module cli

// command.v - Command trait and helpers / Command 接口与辅助结构
//
// Commands implement the Command interface with a name, description,
// signature, and execute method. Inspired by Symfony Console's Command class.
// 命令实现 Command 接口，包含名称、描述、签名和执行方法。
// 灵感来自 Symfony Console 的 Command 类。

import strings

// Command is the interface that all CLI commands must implement
// Command 是所有 CLI 命令必须实现的接口
pub interface Command {
	name() string
	description() string
	signature() string
	execute(input &CommandInput, output &CommandOutput) !
}

// BaseCommand provides default implementations for common command patterns
// BaseCommand 提供常见命令模式的默认实现
pub struct BaseCommand {
pub:
	name        string
	description string
pub mut:
	sig string // signature string / 签名字符串
}

// name returns the command name / 返回命令名称
pub fn (c &BaseCommand) name() string {
	return c.name
}

// description returns the command description / 返回命令描述
pub fn (c &BaseCommand) description() string {
	return c.description
}

// signature returns the command signature / 返回命令签名
pub fn (c &BaseCommand) signature() string {
	return c.sig
}

// ============================================================
// CommandHelp — structured help metadata / 结构化帮助元数据
// ============================================================

// CommandHelp holds all metadata needed to generate help text for a command.
// Automatically populated from annotation attributes via comptime scanning.
//
// CommandHelp 保存生成命令帮助文本所需的所有元数据。
// 通过编译期扫描注解属性自动填充。
pub struct CommandHelp {
pub mut:
	name        string
	description string
	usage       string
	options     []HelpParam
	arguments   []HelpParam
	examples    []string
}

// HelpParam describes a single parameter (option or argument) in help output
// HelpParam 描述帮助输出中的单个参数（选项或位置参数）
pub struct HelpParam {
pub:
	name        string
	description string
	default_val string
	is_required bool
}

// to_help_text formats CommandHelp into a human-readable help string.
// Generates a clean, aligned help text with sections for usage,
// arguments, options, and examples.
//
// to_help_text 将 CommandHelp 格式化为人类可读的帮助字符串。
// 生成整洁对齐的帮助文本，包含用法、参数、选项和示例等段落。
pub fn (h &CommandHelp) to_help_text() string {
	mut sb := strings.new_builder(256)

	// Description / 描述
	if h.description.len > 0 {
		sb.writeln(h.description)
		sb.writeln('')
	}

	// Usage / 用法
	if h.usage.len > 0 {
		sb.writeln('Usage:')
		sb.writeln('  ${h.usage}')
		sb.writeln('')
	}

	// Arguments / 参数
	if h.arguments.len > 0 {
		sb.writeln('Arguments:')
		mut max_name := 0
		for arg in h.arguments {
			if arg.name.len > max_name {
				max_name = arg.name.len
			}
		}
		for arg in h.arguments {
			padded := pad_right('  ${arg.name}', max_name + 4)
			mut suffix := ''
			if arg.is_required {
				suffix = ' (required)'
			} else if arg.default_val.len > 0 {
				suffix = ' [default: ${arg.default_val}]'
			}
			sb.writeln('${padded}${arg.description}${suffix}')
		}
		sb.writeln('')
	}

	// Options / 选项
	if h.options.len > 0 {
		sb.writeln('Options:')
		mut max_name := 0
		for opt in h.options {
			name_str := '--${opt.name}'
			if name_str.len > max_name {
				max_name = name_str.len
			}
		}
		for opt in h.options {
			name_str := '--${opt.name}'
			padded := pad_right('  ${name_str}', max_name + 4)
			mut suffix := ''
			if opt.is_required {
				suffix = ' (required)'
			} else if opt.default_val.len > 0 {
				suffix = ' [default: ${opt.default_val}]'
			}
			sb.writeln('${padded}${opt.description}${suffix}')
		}
		sb.writeln('')
	}

	// Examples / 示例
	if h.examples.len > 0 {
		sb.writeln('Examples:')
		for example in h.examples {
			sb.writeln('  ${example}')
		}
		sb.writeln('')
	}

	return sb.str()
}

// ============================================================
// AnnotatedCommand — command created from annotation metadata
// AnnotatedCommand — 从注解元数据创建的命令
// ============================================================

// AnnotatedCommand is a Command implementation that is automatically
// generated from struct annotations via comptime scanning.
// It stores the CommandInfo and provides a default execute that
// displays the command's help text.
//
// AnnotatedCommand 是通过编译期扫描 struct 注解自动生成的 Command 实现。
// 保存 CommandInfo，提供默认的 execute 方法来显示命令帮助文本。
pub struct AnnotatedCommand {
	BaseCommand
pub mut:
	info CommandInfo
}

// new_annotated_command creates an AnnotatedCommand from CommandInfo
// new_annotated_command 从 CommandInfo 创建 AnnotatedCommand
pub fn new_annotated_command(info CommandInfo) &AnnotatedCommand {
	// Build signature string from options and arguments / 从选项和参数构建签名字符串
	mut sig_parts := []string{}
	for arg in info.arguments {
		if arg.is_required {
			sig_parts << '<${arg.param_name}>'
		} else {
			sig_parts << '[<${arg.param_name}>]'
		}
	}
	for opt in info.options {
		if opt.is_required {
			sig_parts << '--${opt.param_name}=<value>'
		} else {
			sig_parts << '[--${opt.param_name}=<value>]'
		}
	}

	return &AnnotatedCommand{
		BaseCommand: BaseCommand{
			name:        info.name
			description: info.description
			sig:         sig_parts.join(' ')
		}
		info: info
	}
}

// execute runs the annotated command; by default prints its help
// execute 执行注解命令；默认打印其帮助信息
pub fn (c &AnnotatedCommand) execute(input &CommandInput, output &CommandOutput) ! {
	help := c.info.to_command_help()
	output.writeln(help.to_help_text())
}

// to_command_help converts CommandInfo to CommandHelp for help generation
// to_command_help 将 CommandInfo 转换为 CommandHelp 以生成帮助信息
pub fn (info &CommandInfo) to_command_help() CommandHelp {
	mut help := CommandHelp{
		name:        info.name
		description: info.description
		usage:       '${info.name} ${build_signature_from_info(info)}'
	}

	for arg in info.arguments {
		help.arguments << HelpParam{
			name:        arg.param_name
			description: arg.description
			default_val: arg.default_val
			is_required: arg.is_required
		}
	}

	for opt in info.options {
		help.options << HelpParam{
			name:        opt.param_name
			description: opt.description
			default_val: opt.default_val
			is_required: opt.is_required
		}
	}

	return help
}

// build_signature_from_info builds a signature string from CommandInfo
// build_signature_from_info 从 CommandInfo 构建签名字符串
fn build_signature_from_info(info &CommandInfo) string {
	mut parts := []string{}
	for arg in info.arguments {
		if arg.is_required {
			parts << '<${arg.param_name}>'
		} else {
			parts << '[<${arg.param_name}>]'
		}
	}
	for opt in info.options {
		if opt.is_required {
			parts << '--${opt.param_name}=<value>'
		} else {
			parts << '[--${opt.param_name}=<value>]'
		}
	}
	return parts.join(' ')
}
