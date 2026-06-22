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
pub:
	name        string
	description string
	options     []ParamInfo
	arguments   []ParamInfo
}

// ParamInfo holds metadata for a single command parameter (option or argument)
// ParamInfo 保存单个命令参数（选项或位置参数）的元数据
pub struct ParamInfo {
pub:
	field_name  string
	param_name  string
	description string
	is_required bool
	default_val string
	is_option   bool // true=option, false=argument / true=选项, false=位置参数
}

// scan_command[T]() scans a struct type T annotated with @[command] and extracts
// its metadata at compile time. Returns CommandInfo with name, description,
// options, and arguments derived from the struct's attributes.
//
// scan_command[T]() 在编译期扫描带有 @[command] 注解的 struct 类型 T，
// 提取其元数据，返回包含名称、描述、选项和位置参数的 CommandInfo。
pub fn scan_command[T]() CommandInfo {
	mut info := CommandInfo{}
	mut cmd_name := ''
	mut cmd_desc := ''

	// Scan struct-level attributes / 扫描 struct 级别的属性
	$for attr in T.attributes {
		if attr.name == attr_command {
			// @[command: 'name'] — extract the custom name / 提取自定义名称
			if attr.args.len > 0 {
				cmd_name = attr.args[0].replace("'", '')
			}
		}
		if attr.name == attr_description {
			// @[description('help text')] — extract description / 提取描述
			if attr.args.len > 0 {
				cmd_desc = attr.args[0].replace("'", '')
			}
		}
	}

	// Fall back to struct name if no custom name / 无自定义名称时回退到 struct 名称
	if cmd_name.len == 0 {
		cmd_name = T.name
	}

	info.name = cmd_name
	info.description = cmd_desc

	// Scan field-level attributes / 扫描字段级别的属性
	$for field in T.fields {
		mut param := ParamInfo{
			field_name: field.name
		}

		for attr in field.attrs {
			if attr.name == attr_option {
				// @[option('name')] or @[option: 'name'] / 选项注解
				param.is_option = true
				if attr.args.len > 0 {
					param.param_name = attr.args[0].replace("'", '')
				} else {
					param.param_name = field.name
				}
			} else if attr.name == attr_argument {
				// @[argument] — positional argument / 位置参数
				param.is_option = false
				param.param_name = field.name
			} else if attr.name == attr_required {
				// @[required] — mark as required / 标记为必填
				param.is_required = true
			} else if attr.name == attr_default {
				// @[default('value')] — default value / 默认值
				if attr.args.len > 0 {
					param.default_val = attr.args[0].replace("'", '')
				}
			} else if attr.name == attr_description {
				// @[description('text')] on a field / 字段上的描述注解
				if attr.args.len > 0 {
					param.description = attr.args[0].replace("'", '')
				}
			}
		}

		if param.param_name.len > 0 {
			if param.is_option {
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
