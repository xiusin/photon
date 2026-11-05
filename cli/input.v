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

// OptionSchema declares what a command knows about its own options.
//
// OptionSchema 描述命令自己对选项的了解程度。
//
// 为什么不是 `map[string]bool`：光知道「这个名字被声明过」回答不了
// `--verbose v2` 里的 `v2` 是不是值。布尔选项在命令行上是裸的，后面跟的
// 那个 token 是位置参数；取值选项则要吞掉它。两种情况「名字都被声明过」，
// 早期用 `map[string]bool` 时只能一律按取值处理，于是
// `--verbose v2` 把 `v2` 吃成了 verbose 的值。
pub struct OptionSchema {
pub mut:
	// takes_value 为 true 表示该选项需要一个值（`--port 8080`）；
	// 未出现在表里的名字按取值处理，保持旧行为不变。
	takes_value map[string]bool
	// known 是「声明过的选项名」全集，包含布尔选项。
	known map[string]bool
}

// new_option_schema 建一张空表
pub fn new_option_schema() &OptionSchema {
	return &OptionSchema{
		takes_value: map[string]bool{}
		known:       map[string]bool{}
	}
}

// declare_value_option 声明一个「需要值」的选项，如 `--port 8080`
pub fn (mut s OptionSchema) declare_value_option(name string) &OptionSchema {
	s.known[name] = true
	s.takes_value[name] = true
	return s
}

// declare_flag_option 声明一个「不取值」的布尔选项，如 `--verbose`
pub fn (mut s OptionSchema) declare_flag_option(name string) &OptionSchema {
	s.known[name] = true
	s.takes_value[name] = false
	return s
}

// should_take_value 报告 `name` 后面那个 token 是否应被吃成它的值。
//
// 表里有明确声明就照声明；没声明时保持历史行为（按取值处理），
// 这样 `new_input_with_options` 的既有用法语义不变。
fn (s &OptionSchema) should_take_value(name string) bool {
	if name in s.takes_value {
		return s.takes_value[name]
	}
	return true
}

// parse_options splits the raw argv into command_name / options / flags /
// positional args.
//
// When a schema is supplied the parser is schema-aware: a preceding `--name`
// only consumes the next token when `name` is declared to take a value.
// Without a schema the parser falls back to the historical greedy rule,
// except for the unambiguous cases below.
//
// `--` always terminates option parsing (`-- --looks-like-flag`).
pub fn new_input_with_schema(raw_args []string, schema &OptionSchema) &CommandInput {
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
		// 有 schema 时按声明判断：布尔选项不吞下一个 token，取值选项吞。
		// 没有 schema（known 为空）时退回贪心规则；单字母短选项在声明表里
		// 查不到（命令只声明长名），仍然按取值处理。
		mut name_takes_value := true
		if schema.known.len > 0 {
			if option_name in schema.known {
				name_takes_value = schema.should_take_value(option_name)
			} else {
				name_takes_value = is_short_option(arg)
			}
		}
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

// new_input_with_options 是 schema 之前的入口，保留以兼容既有调用。
//
// `known` 里的名字一律按「取值选项」处理 —— 这正是 `--verbose v2` 会吞掉
// `v2` 的历史行为。需要区分布尔选项时改用 new_input_with_schema。
pub fn new_input_with_options(raw_args []string, known map[string]bool) &CommandInput {
	mut schema := new_option_schema()
	for name, _ in known {
		schema.declare_value_option(name)
	}
	return new_input_with_schema(raw_args, schema)
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
	return new_input_with_schema(raw_args, new_option_schema())
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
//       environment string @[option('env'); default('production')]
//       version     string @[argument]
//   }
//
//   cmd := bind_input[DeployCommand](input) or { panic(err) }
pub fn bind_input[T](input &CommandInput) !T {
	mut result := T{}

	$for field in T.fields {
		is_option := has_attr(field.attrs, attr_option)
		is_argument := has_attr(field.attrs, attr_argument)

		if is_option || is_argument {
			// 选项名以 `@[option('env')]` 为准，没给就用字段名；
			// 位置参数只按字段名登记，取值靠序号。
			mut param_name := field.name
			if is_option {
				declared := attr_value(field.attrs, attr_option)
				if declared.len > 0 {
					param_name = declared
				}
			}

			mut value := attr_value(field.attrs, attr_default)
			mut is_present := false
			if is_option {
				opt_val := input.get_option_or(param_name, '')
				if opt_val.len > 0 {
					value = opt_val
					is_present = true
				}
				// 布尔选项在命令行上是裸的 `--verbose`，new_input 把它归进
				// flags 而不是 options。只查 options 会让 bool 字段永远是 false，
				// 所以这里也看 flags。
				if input.has_flag(param_name) {
					value = 'true'
					is_present = true
				}
			} else {
				arg_idx := arg_index_of[T](field.name)
				if arg_idx >= 0 {
					arg_val := input.get_argument_or(arg_idx, '')
					if arg_val.len > 0 {
						value = arg_val
						is_present = true
					}
				}
			}

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

			if has_attr(field.attrs, attr_required) && !is_present && value.len == 0 {
				return error('Required parameter "${param_name}" is missing')
			}
		}
	}

	return result
}

// ============================================================
// Schema-aware binding / 带 schema 的绑定
// ============================================================

// schema_for[T]() 从类型 T 的注解推导出 argv 解析表。
//
// 为什么 bind_input[T](input) 不够：调用方用 `new_input()` 解析 argv 时没有
// 任何 schema，`--dry-run 42` 会把 `42` 吃成 dry-run 的值，位置参数从此少一个。
// bind_input 本身看不出「被吞掉的那个 token 本来是什么」—— 解析早于绑定。
// 所以这里让类型自己出 schema，再用它重新解析原始 argv。
pub fn schema_for[T]() &OptionSchema {
	mut schema := new_option_schema()
	$for field in T.fields {
		if has_attr(field.attrs, attr_option) {
			mut name := field.name
			declared := attr_value(field.attrs, attr_option)
			if declared.len > 0 {
				name = declared
			}
			mut is_bool := false
			$if field.typ is bool {
				is_bool = true
			}
			if is_bool {
				schema.declare_flag_option(name)
			} else {
				schema.declare_value_option(name)
			}
		}
	}
	return schema
}

// bind_input_from_args[T]() 用 T 自己声明的选项表解析 raw_args 并绑定。
//
// 推荐入口：不需要调用方先知道哪些选项是布尔，也就不会再踩
// 「`--flag value` 里 value 被吞掉」这个坑。
//
//   cmd := cli.bind_input_from_args[DeployCmd](os.args[1..])!
pub fn bind_input_from_args[T](raw_args []string) !T {
	input := new_input_with_schema(raw_args, schema_for[T]())
	return bind_input[T](input)
}

// has_flag_like 报告该选项在 flags 里是否出现过（布尔选项的裸形式）
pub fn (input &CommandInput) has_flag_like(name string) bool {
	return input.has_flag(name) || input.has_option(name)
}
