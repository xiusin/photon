module cli

// input_parsing_test.v — 命令行参数解析的边界行为
//
// 三个缺陷都属于「解析成功但结果错」的类型：不报错、不 panic，只是子命令
// 悄悄消失或者参数被吞掉。

// ── `--` 终止符 ──

fn test_double_dash_terminates_options() {
	input := new_input(['app', '--', '--not-a-flag', '-x'])
	assert input.arg_count() == 2
	assert input.get_arg(0) == '--not-a-flag'
	assert input.get_arg(1) == '-x'
	assert input.options.len == 0
	assert input.flags.len == 0
}

fn test_double_dash_after_options() {
	input := new_input(['app', '--name', 'x', '--', '--raw'])
	assert input.get_option('name') == 'x'
	assert input.get_arg(0) == '--raw'
}

// ── 短选项组合 ──

fn test_bundled_short_flags() {
	input := new_input(['app', '-abc'])
	assert input.has_flag('a')
	assert input.has_flag('b')
	assert input.has_flag('c')
}

fn test_single_short_flag_not_bundled() {
	input := new_input(['app', '-h'])
	assert input.has_flag('h')
	assert !input.has_flag('h'.repeat(2))
}

// ── 负数值 ──

fn test_negative_number_is_option_value() {
	input := new_input(['app', '--offset', '-1', 'file'])
	assert input.get_option('offset') == '-1'
	assert input.get_arg(0) == 'file'
}

// ── 内联值 ──

fn test_inline_equals_value() {
	input := new_input(['app', '--name=x', 'y'])
	assert input.get_option('name') == 'x'
	assert input.get_arg(0) == 'y'
}

// ── 空参数 ──

fn test_empty_argv() {
	input := new_input([])
	assert input.arg_count() == 0
	assert input.command_name == ''
}

// ── schema 感知解析 ──

fn test_schema_keeps_subcommand_after_boolean_flag() {
	// 没有 schema 时 --verbose 会吞掉 build
	schema := {
		'output':  true
		'port':    true
	}
	input := new_input_with_options(['app', '--verbose', 'build', 'src/'], schema)
	assert input.has_flag('verbose')
	assert input.get_arg(0) == 'build'
	assert input.get_arg(1) == 'src/'
}

fn test_schema_binds_declared_option_value() {
	schema := {
		'port': true
	}
	input := new_input_with_options(['app', 'serve', '--port', '8080'], schema)
	assert input.get_option('port') == '8080'
	assert input.get_arg(0) == 'serve'
}

fn test_schema_short_option_still_takes_value() {
	schema := {
		'output': true
	}
	input := new_input_with_options(['app', '-o', 'out', 'build'], schema)
	assert input.get_option('o') == 'out'
	assert input.get_arg(0) == 'build'
}
