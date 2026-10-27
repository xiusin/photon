module cli

// input.v - CommandInput — parsed command-line arguments
// CommandInput — 解析后的命令行参数

// CommandInput holds the parsed command-line arguments
// CommandInput 保存解析后的命令行参数
pub struct CommandInput {
pub mut:
	command_name string
	args         map[string]string
	options      map[string]string
	flags        map[string]bool
	raw_args     []string
}

// parse_options splits the raw argv into command_name / options / flags /
// positional args.
//
// When `known` is non-empty the parser is schema-aware: a preceding `--name`
// only consumes the next token when `name` is a declared option. Without a
// schema the parser falls back to the historical greedy rule, except for the
// unambiguous cases below.
//
// `--` always terminates option parsing (`-- --looks-like-flag`).
pub fn new_input_with_options(raw_args []string, known map[string]bool) &CommandInput {
	mut input := CommandInput{
		args:     map[string]string{}
		options:  map[string]string{}
		flags:    map[string]bool{}
		raw_args: raw_args
	}

	if raw_args.len == 0 {
		return &CommandInput{
			args:    map[string]string{}
			options: map[string]string{}
			flags:   map[string]bool{}
		}
	}

	input.command_name = raw_args[0]

	mut i := 1
	mut only_positional := false
	for i < raw_args.len {
		arg := raw_args[i]

		if only_positional {
			input.args['arg_${input.args.len}'] = arg
			i++
			continue
		}

		if arg == '--' {
			only_positional = true
			i++
			continue
		}

		next := if i + 1 < raw_args.len { raw_args[i + 1] } else { '' }
		option_name := option_token_name(arg)
		// 声明了选项表时，只有已知选项才吞下一个 token；否则 `--verbose build`
		// 会把子命令当成布尔选项的值吃掉。没有 `--` 前缀的单字母短选项无法
		// 从声明里查到（命令只声明长名），按声明了选项表处理时它仍然取值。
		name_takes_value := known.len == 0 || option_name in known || is_short_option(arg)
		next_is_value := i + 1 < raw_args.len && name_takes_value && is_value_token(next)

		if arg.starts_with('--') {
			rest := arg[2..]
			if rest.len == 0 {
				i++
				continue
			}
			if rest.contains('=') {
				parts := rest.split_nth('=', 2)
				input.options[parts[0]] = parts[1]
			} else if next_is_value {
				input.options[rest] = next
				i++
			} else {
				input.flags[rest] = true
			}
		} else if arg.starts_with('-') && arg.len > 1 {
			rest := arg[1..]
			if rest.len > 1 && !rest.contains('=') && !next_is_value {
				// `-abc` is the conventional bundling of boolean flags.
				for ch in rest {
					input.flags[ch.ascii_str()] = true
				}
			} else if next_is_value {
				input.options[rest] = next
				i++
			} else {
				input.flags[rest] = true
			}
		} else {
			input.args['arg_${input.args.len}'] = arg
		}
		i++
	}

	return &input
}

// is_short_option reports whether `arg` is a single-letter short option such
// as `-o`. Command schemas only declare long names, so short options are
// always assumed to take a value when one follows.
fn is_short_option(arg string) bool {
	return arg.len == 2 && arg.starts_with('-') && arg[1] != `-`
}

// option_token_name extracts the option name from a raw argv token:
// `--output` → `output`, `--output=x` → `output`, `-o` → `o`. Returns '' for
// positional tokens.
fn option_token_name(arg string) string {
	if arg.starts_with('--') {
		rest := arg[2..]
		if idx := rest.index('=') {
			return rest[..idx]
		}
		return rest
	}
	if arg.starts_with('-') && arg.len > 1 {
		return arg[1..]
	}
	return ''
}

// is_value_token reports whether `token` may be consumed as the value of the
// preceding option.
//
//   - A negative number is always a value (`--offset -1`).
//   - Any other dash-prefixed token starts a new option, never a value.
//   - A bare token is a value; the ambiguity with subcommands is resolved by
//     the caller through the declared option table before calling this.
fn is_value_token(token string) bool {
	if token.len == 0 {
		return false
	}
	if token.starts_with('-') {
		return token.len > 1 && (token[1] >= `0` && token[1] <= `9`)
	}
	return true
}

// new_input parses os.args into a CommandInput
// new_input 将 os.args 解析为 CommandInput
pub fn new_input(raw_args []string) &CommandInput {
	return new_input_with_options(raw_args, map[string]bool{})
}

// get_arg returns a positional argument by index (0-based)
// get_arg 按索引返回位置参数（从 0 开始）
pub fn (input &CommandInput) get_arg(idx int) string {
	key := 'arg_${idx}'
	return input.args[key] or { '' }
}

// get_option returns an option value
// get_option 返回选项值
pub fn (input &CommandInput) get_option(name string) string {
	return input.options[name] or { '' }
}

// get_option_or returns an option value with default
// get_option_or 返回选项值，若不存在则返回默认值
pub fn (input &CommandInput) get_option_or(name string, default_val string) string {
	return input.options[name] or { default_val }
}

// has_flag returns true if flag is set
// has_flag 检查标志是否被设置
pub fn (input &CommandInput) has_flag(name string) bool {
	return input.flags[name] or { false }
}

// arg_count returns number of positional arguments
// arg_count 返回位置参数数量
pub fn (input &CommandInput) arg_count() int {
	return input.args.len
}

// ============================================================
// Enhanced Input Methods / 增强的输入方法
// ============================================================

// has_option checks whether an option with the given name exists.
// Returns true if the option was provided on the command line,
// regardless of whether it has a value.
//
// has_option 检查给定名称的选项是否存在。
// 如果命令行提供了该选项则返回 true，无论是否有值。
pub fn (input &CommandInput) has_option(name string) bool {
	val := input.options[name] or { return false }
	_ = val
	return true
}

// get_argument_or returns a positional argument by index with a default value.
// If the argument at the given index does not exist, returns default_val.
//
// get_argument_or 按索引返回位置参数，若不存在则返回默认值。
// 如果给定索引的参数不存在，返回 default_val。
pub fn (input &CommandInput) get_argument_or(index int, default_val string) string {
	key := 'arg_${index}'
	return input.args[key] or { default_val }
}

// validate_required checks that all required option/argument names are present
// in the input. Returns an error listing any missing required parameters.
//
// validate_required 验证所有必填的选项/参数名称是否存在于输入中。
// 如果有缺失的必填参数，返回列出缺失项的错误。
pub fn (input &CommandInput) validate_required(required []string) ! {
	mut missing := []string{}
	for name in required {
		// Check both options and arguments / 同时检查选项和参数
		opt_val := input.options[name] or { '' }
		arg_key := 'arg_${name}'
		arg_val := input.args[arg_key] or { '' }

		// Also check by index for positional args / 也按索引检查位置参数
		mut is_found := false
		if opt_val.len > 0 {
			is_found = true
		}
		if arg_val.len > 0 {
			is_found = true
		}
		// Check if it's a numeric index for positional args / 检查是否为位置参数的数字索引
		if name.len > 0 && name[0] >= `0` && name[0] <= `9` {
			idx := name.int()
			positional := input.get_arg(idx)
			if positional.len > 0 {
				is_found = true
			}
		}

		if !is_found {
			missing << name
		}
	}

	if missing.len > 0 {
		return error('Missing required parameters: ${missing.join(', ')}')
	}
}

// ============================================================
// Comptime Input Binding / 编译期输入绑定
// ============================================================

// bind_input[T]() binds the parsed CommandInput to a struct of type T
// using comptime field scanning. Fields annotated with @[option('name')]
// are populated from input options, and fields annotated with @[argument]
// are populated from positional arguments. Fields with @[default('value')]
// receive their default if the input does not provide a value.
//
// bind_input[T]() 使用编译期字段扫描将解析后的 CommandInput 绑定到
// 类型 T 的 struct。标注 @[option('name')] 的字段从输入选项填充，
// 标注 @[argument] 的字段从位置参数填充。标注 @[default('value')] 的字段
// 在输入未提供值时接收默认值。
//
// Example:
//   @[command]
//   @[description('Deploy the application')]
//   struct DeployCommand {
//       @[option: 'env']
//       @[default('production')]
//       environment string
//
//       @[argument]
//       version string
//   }
//
//   cmd := bind_input[DeployCommand](input) or { panic(err) }
pub fn bind_input[T](input &CommandInput) !T {
	mut result := T{}

	$for field in T.fields {
		mut is_option_field := false
		mut is_argument_field := false
		mut param_name := ''
		mut default_value := ''

		for attr in field.attrs {
			if attr.name == attr_option {
				is_option_field = true
				if attr.args.len > 0 {
					param_name = attr.args[0].replace("'", '')
				} else {
					param_name = field.name
				}
			} else if attr.name == attr_argument {
				is_argument_field = true
				param_name = field.name
			} else if attr.name == attr_default {
				if attr.args.len > 0 {
					default_value = attr.args[0].replace("'", '')
				}
			} else if attr.name == attr_required {
				// Required validation handled below / 必填验证在下面处理
			}
		}

		// Skip fields without option/argument annotations / 跳过没有 option/argument 注解的字段
		if !is_option_field && !is_argument_field {
			continue
		}

		mut value := default_value

		if is_option_field && param_name.len > 0 {
			// Bind from options / 从选项绑定
			opt_val := input.get_option_or(param_name, '')
			if opt_val.len > 0 {
				value = opt_val
			}
		} else if is_argument_field {
			// Bind from positional arguments / 从位置参数绑定
			// Try to find by sequential index / 尝试按顺序索引查找
			mut arg_idx := -1
			mut arg_counter := 0
			$for f in T.fields {
				mut is_arg := false
				for a in f.attrs {
					if a.name == attr_argument {
						is_arg = true
						break
					}
				}
				if is_arg {
					if f.name == field.name {
						arg_idx = arg_counter
						break
					}
					arg_counter++
				}
			}

			if arg_idx >= 0 {
				arg_val := input.get_argument_or(arg_idx, '')
				if arg_val.len > 0 {
					value = arg_val
				}
			}
		}

		// Assign the value to the field / 将值赋给字段
		$if field.typ is string {
			result.$(field.name) = value
		} $else $if field.typ is int {
			if value.len > 0 {
				result.$(field.name) = value.int()
			}
		} $else $if field.typ is bool {
			result.$(field.name) = value == 'true' || value == '1'
		} $else $if field.typ is f64 {
			if value.len > 0 {
				result.$(field.name) = value.f64()
			}
		}

		// Check required constraint / 检查必填约束
		mut is_required := false
		for attr in field.attrs {
			if attr.name == attr_required {
				is_required = true
				break
			}
		}
		if is_required && value.len == 0 {
			return error('Required parameter "${param_name}" is missing')
		}
	}

	return result
}
