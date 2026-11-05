module cli

// cli.v - Photon CLI Module Entry / CLI 模块入口
//
// A Laravel/Symfony-inspired console CLI framework for V.
// Provides:
//   - Command registration and dispatch / 命令注册与分发
//   - Argument/option parsing / 参数与选项解析
//   - Styled output with ANSI colors / ANSI 彩色样式输出
//   - Built-in commands: serve, list, help, schedule:run, queue:work / 内置命令
//   - Interactive input: ask, confirm, secret, choice / 交互式输入
//   - Code generation: make:command, make:controller, make:middleware, etc. / 代码生成
//   - ProgressBar helper / 进度条辅助
//   - Annotation-driven command registration / 注解驱动的命令注册
//
// Usage:
//   import photon.cli
//
//   mut app := cli.new_application('myapp', '1.0.0')
//   app.add_command(my_command)
//   app.run() or { panic(err) }

// ============================================================
// Annotation Constants / 注解常量
// ============================================================

// Command annotation constants / 命令注解常量
// Usage:
//   @[command]               — mark a struct as a CLI command / 标记 struct 为命令
//   @[command: 'name']       — specify command name / 指定命令名称
//   @[description('help')]   — command description / 命令描述
pub const attr_command     = 'command'
pub const attr_description = 'description'

// Parameter annotation constants / 参数注解常量
// Usage:
//   @[option('name')]   — command option (--name) / 命令选项
//   @[option: 'name']   — shorthand form / 简写形式
//   @[argument]         — positional argument / 位置参数
//   @[required]         — required parameter / 必填参数
//   @[default('value')] — default value / 默认值
pub const attr_option  = 'option'
pub const attr_argument = 'argument'
pub const attr_required = 'required'
pub const attr_default  = 'default'

// ============================================================
// Comptime Scanning Functions / 编译期扫描函数
// ============================================================

// CommandInfo holds metadata extracted from a command struct via comptime
// CommandInfo 保存通过编译期从命令 struct 提取的元数据
pub struct CommandInfo {
pub mut:
	name        string
	description string
	options     []ParamInfo
	arguments   []ParamInfo
}

// ParamInfo holds metadata for a single command parameter (option or argument)
// ParamInfo 保存单个命令参数（选项或位置参数）的元数据
pub struct ParamInfo {
pub mut:
	field_name  string
	param_name  string
	description string
	is_required bool
	default_val string
	is_option   bool // true=option, false=argument / true=选项, false=位置参数
	// is_bool 为 true 表示这个选项在命令行上不带值（`--verbose`）。
	// 解析 argv 时靠它区分「吞下一个 token」还是「就地置真」。
	is_bool bool
}

// scan_command[T]() scans a struct type T annotated with @[command] and extracts
// its metadata at compile time. Returns CommandInfo with name, description,
// options, and arguments derived from the struct's attributes.
//
// scan_command[T]() 在编译期扫描带有 @[command] 注解的 struct 类型 T，
// 提取其元数据，返回包含名称、描述、选项和位置参数的 CommandInfo。
pub fn scan_command[T]() CommandInfo {
	mut info := CommandInfo{}

	// struct 级属性走 `T.attributes`（[]VAttribute），字段级走 `field.attrs`
	// （[]string）—— 两种形态不同，见 cli/attrs.v 顶部的说明。
	mut cmd_name := ''
	mut cmd_desc := ''
	$for attr in T.attributes {
		if attr.name == attr_command {
			cmd_name = attr.arg
		}
		if attr.name == attr_description {
			cmd_desc = attr.arg
		}
	}

	// 无自定义名称时回退到 struct 名称。
	// `T.name` 带模块前缀（`cli.PlainCmd`），拿去当命令名就成了
	// `app cli.PlainCmd --help`，剥掉前缀才是用户会敲的那个词。
	if cmd_name.len == 0 {
		cmd_name = T.name.all_after_last('.')
	}
	info.name = cmd_name
	info.description = cmd_desc

	$for field in T.fields {
		is_option := has_attr(field.attrs, attr_option)
		is_argument := has_attr(field.attrs, attr_argument)

		if is_option || is_argument {
			mut param_name := field.name
			if is_option {
				// `@[option('env')]` 给了名字就用它，否则回退到字段名
				declared := attr_value(field.attrs, attr_option)
				if declared.len > 0 {
					param_name = declared
				}
			}
			// 字段类型在编译期可判，布尔选项在 argv 上不带值
			mut is_bool := false
			$if field.typ is bool {
				is_bool = true
			}
			param := ParamInfo{
				field_name:  field.name
				param_name:  param_name
				description: attr_value(field.attrs, attr_description)
				is_required: has_attr(field.attrs, attr_required)
				default_val: attr_value(field.attrs, attr_default)
				is_option:   is_option
				is_bool:     is_bool
			}
			if is_option {
				info.options << param
			} else {
				info.arguments << param
			}
		}
	}

	return info
}

// register_command_from[T]() creates an AnnotatedCommand from struct type T
// and registers it with the given CliApplication. The struct T must be
// annotated with @[command].
//
// register_command_from[T]() 从 struct 类型 T 创建一个 AnnotatedCommand
// 并注册到给定的 CliApplication。struct T 必须标注 @[command] 注解。
pub fn register_command_from[T](mut app CliApplication) {
	info := scan_command[T]()
	cmd := new_annotated_command(info)
	app.add_command(cmd)
}
