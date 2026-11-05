module cli

// annotated_command_test.v — 注解驱动的命令（scan_command / bind_input）
//
// 为什么这个文件以前不存在
// ------------------------
// `scan_command[T]` 和 `bind_input[T]` 在 0.5.2 下**整块编不过**：它们把
// `field.attrs`（实际是 `[]string`）当成 `[]VAttribute` 用，读 `.name` /
// `.args`；`T.attributes` 才是结构体形态。因为没有任何用例、也没有任何
// example 实例化过它们，编译器从没被要求编过这两个函数。
//
// 这不是「算错了」，是「从来不存在」。下面的用例是它们第一次被真正执行。

// ── 测试用的命令定义 ──

@[command: 'deploy']
@[description('Deploy an application')]
struct DeployCmd {
	environment string @[option('env'); default('production')]
	replicas    int    @[option('replicas'); default('2')]
	verbose     bool   @[option('verbose')]
	token       string @[option('token'); required]
	version     string @[argument]
	target      string @[argument]
}

// ── scan_command ──

fn test_scan_command_reads_struct_attributes() {
	info := scan_command[DeployCmd]()
	assert info.name == 'deploy'
	assert info.description == 'Deploy an application'
}

fn test_scan_command_splits_options_and_arguments() {
	info := scan_command[DeployCmd]()
	assert info.options.len == 4
	assert info.arguments.len == 2

	mut opt_names := []string{}
	for opt in info.options {
		opt_names << opt.param_name
	}
	assert 'env' in opt_names
	assert 'replicas' in opt_names
	assert 'verbose' in opt_names
	assert 'token' in opt_names

	mut arg_names := []string{}
	for arg in info.arguments {
		arg_names << arg.param_name
	}
	assert arg_names == ['version', 'target']
}

fn test_scan_command_reads_param_attributes() {
	info := scan_command[DeployCmd]()
	mut env := ParamInfo{}
	for opt in info.options {
		if opt.param_name == 'env' {
			env = opt
		}
	}
	assert env.field_name == 'environment'
	assert env.default_val == 'production'
	assert env.is_option

	mut token := ParamInfo{}
	for opt in info.options {
		if opt.param_name == 'token' {
			token = opt
		}
	}
	assert token.is_required
}

fn test_scan_command_marks_bool_option() {
	info := scan_command[DeployCmd]()
	for opt in info.options {
		if opt.param_name == 'verbose' {
			assert opt.is_bool
		}
		if opt.param_name == 'env' {
			assert !opt.is_bool
		}
	}
}

fn test_scan_command_without_attributes_falls_back_to_struct_name() {
	info := scan_command[PlainCmd]()
	assert info.name == 'PlainCmd'
	assert info.options.len == 0
	assert info.arguments.len == 0
}

struct PlainCmd {
	x int
}

// ── bind_input ──

fn test_bind_input_options_and_arguments() {
	input := new_input(['deploy', '--env', 'staging', '--token', 't0k', 'v1.2.3', 'prod'])
	cmd := bind_input[DeployCmd](input) or { panic(err) }
	assert cmd.environment == 'staging'
	assert cmd.token == 't0k'
	assert cmd.version == 'v1.2.3'
	assert cmd.target == 'prod'
}

fn test_bind_input_applies_defaults() {
	// 只给必填项，其余走 @[default]
	input := new_input(['deploy', '--token', 't0k', 'v1', 'prod'])
	cmd := bind_input[DeployCmd](input) or { panic(err) }
	assert cmd.environment == 'production'
	assert cmd.replicas == 2
}

fn test_bind_input_converts_int() {
	input := new_input(['deploy', '--token', 't0k', '--replicas', '7', 'v1', 'prod'])
	cmd := bind_input[DeployCmd](input) or { panic(err) }
	assert cmd.replicas == 7
}

fn test_bind_input_missing_required_is_error() {
	// 没有 --token 必须报错，而不是静默给空串
	if _ := bind_input[DeployCmd](new_input(['deploy', 'v1', 'prod'])) {
		assert false, 'missing @[required] option should be an error'
	} else {
		assert err.msg().contains('token')
	}
}

fn test_bind_input_positional_bound_by_declaration_order() {
	// 位置参数按「带 @[argument] 的字段声明顺序」取，不是按字段名
	input := new_input(['deploy', '--token', 't0k', 'FIRST', 'SECOND'])
	cmd := bind_input[DeployCmd](input) or { panic(err) }
	assert cmd.version == 'FIRST'
	assert cmd.target == 'SECOND'
}

// ── 布尔选项 ──
//
// 布尔选项在 argv 上是裸的 `--verbose`，new_input 把它放进 flags 而不是
// options。只查 options 的实现会让 bool 字段永远是 false —— 这也是
// bind_input 修好之后仍然要单独验的一条。

fn test_bind_input_bool_option_from_flag() {
	mut schema := new_option_schema()
	schema.declare_flag_option('verbose')
	input := new_input_with_schema(['deploy', '--verbose', '--token', 't0k', 'v1', 'prod'],
		schema)
	assert input.has_flag('verbose')
	cmd := bind_input[DeployCmd](input) or { panic(err) }
	assert cmd.verbose
}

fn test_bool_flag_does_not_swallow_next_token() {
	// `--verbose v2` 里的 `v2` 是位置参数，不是 verbose 的值。
	// 旧实现（只按「名字声明过」判断）会把它吞掉，位置参数从此错位。
	mut schema := new_option_schema()
	schema.declare_flag_option('verbose')
	input := new_input_with_schema(['deploy', '--verbose', 'v2', 'prod'], schema)
	assert input.flags['verbose']
	assert input.get_option('verbose') == ''
	assert input.get_arg(0) == 'v2'
	assert input.get_arg(1) == 'prod'
}

fn test_value_option_still_swallows_next_token() {
	mut schema := new_option_schema()
	schema.declare_value_option('port')
	input := new_input_with_schema(['serve', '--port', '8080', 'x'], schema)
	assert input.get_option('port') == '8080'
	assert input.get_arg(0) == 'x'
}

fn test_legacy_options_map_still_treats_names_as_value_taking() {
	// 旧入口的语义一个不变：表里的名字一律吞下一个 token
	input := new_input_with_options(['app', '--port', '8080', 'x'], {
		'port': true
	})
	assert input.get_option('port') == '8080'
	assert input.get_arg(0) == 'x'
}

// ── 与 Application 打通 ──

fn test_register_command_from_makes_it_listable() {
	mut app := new_application('testapp', '1.0.0')
	register_command_from[DeployCmd](mut app)
	assert app.commands.len == 1

	found := app.find_command('deploy')
	assert found != unsafe { nil }
	assert found.name() == 'deploy'

	help := app.generate_help('deploy')
	assert help.contains('--env')
	assert help.contains('<version>')
}

// ── 端到端：run_args 真的把参数送到命令手上 ──
//
// `run()` 直接读 os.args，用例没法驱动它；CommandOutput 又直接 println，
// 用例看不到它印了什么。两个缺陷叠在一起时，「CLI 是否正确分发参数」这件事
// 从来没有被任何用例验证过。下面这两条补的就是这个缺口。

struct EchoCmd {
	BaseCommand
}

fn (c &EchoCmd) execute(input &CommandInput, mut output CommandOutput) ! {
	// 把解析结果原样回显，便于断言
	output.writeln('name=${input.command_name}')
	output.writeln('verbose=${input.has_flag('verbose')}')
	output.writeln('env=${input.get_option('env')}')
	output.writeln('args=${input.args.len}')
	output.writeln('arg0=${input.get_arg(0)}')
}

fn echo_cmd() &Command {
	return &EchoCmd{
		BaseCommand: BaseCommand{
			name:        'echo'
			description: 'echo parsed input'
			sig:         '[--env=<value>] [--verbose] [args...]'
		}
	}
}

fn test_run_args_dispatches_flags_and_positionals() {
	mut app := new_application('testapp', '1.0.0')
	app.add_command(echo_cmd())

	mut out := new_capturing_output()
	app.run_args_with_output(['echo', '--verbose', '--env', 'staging', 'src/'], mut out)!

	text := out.collected()
	assert text.contains('name=echo')
	assert text.contains('verbose=true')
	assert text.contains('env=staging')
	assert text.contains('args=1')
	assert text.contains('arg0=src/')
}

fn test_option_schema_marks_bool_option_as_flag() {
	// Application 汇总出的 schema 必须把 bool 字段标成 flag，
	// 否则 `--verbose staging` 里的 staging 会被吃成 verbose 的值。
	mut app := new_application('testapp', '1.0.0')
	register_command_from[EchoAnnotated](mut app)

	schema := app.option_schema_for('deploy')
	assert schema.known['verbose']
	assert schema.known['env']
	assert !schema.takes_value['verbose']
	assert schema.takes_value['env']
}

fn test_declared_schema_keeps_bool_flag_out_of_positionals() {
	mut app := new_application('testapp', '1.0.0')
	register_command_from[EchoAnnotated](mut app)

	input := new_input_with_schema(['deploy', '--verbose', 'staging', 'v1'],
		app.option_schema_for('deploy'))
	assert input.has_flag('verbose')
	assert input.get_option('verbose') == ''
	assert input.get_arg(0) == 'staging'
	assert input.get_arg(1) == 'v1'
}

@[command: 'deploy']
struct EchoAnnotated {
	verbose bool   @[option('verbose')]
	env     string @[option('env'); default('dev')]
	target  string @[argument]
}

// ── bind_input_from_args：类型自己出 schema ──
//
// new_input() 没有 schema，`--dry-run 42` 会把 42 吃成 dry-run 的值。
// bind_input 拿到的是「已经解析错了」的结果，看不出少了什么。所以运行时
// 入口应该是 bind_input_from_args：先按 T 的注解建表，再解析一遍。

fn test_schema_for_marks_bool_and_value_options() {
	schema := schema_for[DeployCmd]()
	assert schema.takes_value['env']
	assert schema.takes_value['replicas']
	assert schema.takes_value['token']
	assert !schema.takes_value['verbose']
	assert schema.known['verbose']
}

fn test_bind_input_from_args_keeps_positional_after_bool_flag() {
	// 关键场景：`--verbose` 后面紧跟位置参数，不能被吃成它的值。
	//
	// 先证明「裸 new_input 会错」——这不是假设，是解析器的真实行为：
	input := new_input(['deploy', '--verbose', 'v2', 'prod'])
	assert input.get_option('verbose') == 'v2'
	assert input.get_arg(0) == 'prod'
	assert input.get_arg(1) == ''

	// 走类型自带 schema 的入口，位置参数归位
	cmd := bind_input_from_args[DeployCmd](['deploy', '--verbose', '--token', 't0k',
		'v2', 'prod']) or { panic(err) }
	assert cmd.verbose
	assert cmd.version == 'v2'
	assert cmd.target == 'prod'
}

fn test_bind_input_from_args_end_to_end() {
	cmd := bind_input_from_args[DeployCmd](['deploy', '--verbose', '--token', 't0k', 'v1',
		'prod']) or { panic(err) }
	assert cmd.verbose
	assert cmd.token == 't0k'
	assert cmd.version == 'v1'
	assert cmd.target == 'prod'
	assert cmd.environment == 'production'
}

fn test_bind_input_from_args_reports_missing_required() {
	if _ := bind_input_from_args[DeployCmd](['deploy', 'v1', 'prod']) {
		assert false, 'missing @[required] should fail'
	} else {
		assert err.msg().contains('token')
	}
}

fn test_bind_input_from_args_bool_flag_then_positional_only() {
	// 只给布尔选项和位置参数：`--verbose` 后面那个 token 必须是位置参数。
	// 这条用例对「schema 是否真的生效」最敏感 —— 没有 schema 时 v2 会被
	// verbose 吞掉，version 变成空串。
	cmd := bind_input_from_args[DeployCmd](['deploy', '--token', 't0k', '--verbose',
		'v2', 'prod']) or { panic(err) }
	assert cmd.verbose
	assert cmd.version == 'v2'
	assert cmd.target == 'prod'
}
