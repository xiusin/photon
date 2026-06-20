module cli

// cli_test.v - Tests for the Photon CLI module

// ============================================================
// Input Parsing Tests
// ============================================================

fn test_input_basic() {
	input := new_input(['serve', '--port=8080', '--verbose'])
	assert input.command_name == 'serve'
	assert input.get_option('port') == '8080'
	assert input.has_flag('verbose') == true
}

fn test_input_no_args() {
	input := new_input([])
	assert input.command_name == ''
}

fn test_input_command_only() {
	input := new_input(['list'])
	assert input.command_name == 'list'
	assert input.arg_count() == 0
}

fn test_input_no_value_flags() {
	input := new_input(['serve', '--debug', '--verbose'])
	assert input.has_flag('debug') == true
	assert input.has_flag('verbose') == true
	assert input.has_flag('nonexistent') == false
}

fn test_input_short_options() {
	input := new_input(['serve', '-p', '9090', '-v'])
	assert input.get_option('p') == '9090'
	assert input.has_flag('v') == true
}

fn test_input_with_equals() {
	input := new_input(['serve', '--host=localhost', '--port=9090'])
	assert input.get_option('host') == 'localhost'
	assert input.get_option('port') == '9090'
}

fn test_input_positional_args() {
	input := new_input(['deploy', 'production', 'v1.0.0'])
	assert input.command_name == 'deploy'
	assert input.get_arg(0) == 'production'
	assert input.get_arg(1) == 'v1.0.0'
	assert input.arg_count() == 2
}

fn test_input_get_option_or() {
	input := new_input(['serve', '--port=8080'])
	assert input.get_option_or('port', '3000') == '8080'
	assert input.get_option_or('host', 'localhost') == 'localhost'
}

// ============================================================
// Application Tests
// ============================================================

fn test_application_new() {
	app := new_application('testapp', '1.0.0')
	assert app.name == 'testapp'
	assert app.version == '1.0.0'
	assert app.commands.len == 0
}

fn test_application_add_command() {
	mut app := new_application('testapp', '1.0.0')
	cmd := new_serve_command()
	app.add_command(cmd)
	assert app.commands.len == 1
}

fn test_application_find_command() {
	mut app := new_application('testapp', '1.0.0')
	app.add_command(new_serve_command())
	app.add_command(new_list_command(app))

	found := app.find_command('serve')
	assert found != unsafe { nil }
	assert found.name() == 'serve'

	not_found := app.find_command('nonexistent')
	assert not_found == unsafe { nil }
}

// ============================================================
// Output Tests
// ============================================================

fn test_output_new() {
	output := new_output()
	assert output.style == .normal
}

fn test_output_styles() {
	mut output := new_output()
	output.style = .quiet
	assert output.style == .quiet
	output.style = .verbose
	assert output.style == .verbose
}

fn test_output_writeln() {
	output := new_output()
	output.writeln('test message')
	// No assertion, just check it doesn't panic
}

fn test_output_success() {
	output := new_output()
	output.success('test success')
}

fn test_output_error() {
	output := new_output()
	output.error('test error')
}

// ============================================================
// Command Tests
// ============================================================

fn test_list_command() {
	mut app := new_application('testapp', '1.0.0')
	app.add_command(new_serve_command())
	cmd := new_list_command(app)
	assert cmd.name() == 'list'
	assert cmd.description().len > 0
}

fn test_help_command() {
	mut app := new_application('testapp', '1.0.0')
	app.add_command(new_serve_command())
	cmd := new_help_command(app)
	assert cmd.name() == 'help'
	assert cmd.description().len > 0
}

fn test_serve_command() {
	cmd := new_serve_command()
	assert cmd.name() == 'serve'
	assert cmd.description().len > 0
	assert cmd.signature().len > 0
}

// ============================================================
// Format Tests
// ============================================================

fn test_bold_text() {
	result := bold_text('hello')
	assert result.contains('\x1b[1m')
	assert result.contains('hello')
}

fn test_red_text() {
	result := red_text('error')
	assert result.contains('\x1b[31m')
	assert result.contains('error')
}

fn test_green_text() {
	result := green_text('ok')
	assert result.contains('\x1b[32m')
	assert result.contains('ok')
}

fn test_yellow_text() {
	result := yellow_text('warn')
	assert result.contains('\x1b[33m')
	assert result.contains('warn')
}

fn test_pad_right() {
	assert pad_right('hi', 5) == 'hi   '
	assert pad_right('hello', 5) == 'hello'
	assert pad_right('hello world', 5) == 'hello world'
}

fn test_success_text() {
	result := success_text('done')
	assert result.contains('\x1b[32m')
	assert result.contains('\x1b[1m')
	assert result.contains('done')
}

fn test_error_text() {
	result := error_text('fail')
	assert result.contains('\x1b[31m')
	assert result.contains('\x1b[1m')
	assert result.contains('fail')
}

// ============================================================
// ProgressBar Tests
// ============================================================

fn test_progress_bar_new() {
	mut pb := new_progress_bar(100)
	assert pb.total == 100
	assert pb.current == 0
}

fn test_progress_bar_advance() {
	mut pb := new_progress_bar(100)
	pb.advance(50)
	assert pb.current == 50
	pb.advance(50)
	assert pb.current == 100
}

fn test_progress_bar_set() {
	mut pb := new_progress_bar(100)
	pb.set(75)
	assert pb.current == 75
}

fn test_progress_bar_finish() {
	mut pb := new_progress_bar(100)
	pb.finish()
	assert pb.current == 100
}

fn test_progress_bar_no_overflow() {
	mut pb := new_progress_bar(100)
	pb.advance(200)
	assert pb.current == 100
}

fn test_progress_bar_set_no_overflow() {
	mut pb := new_progress_bar(100)
	pb.set(200)
	assert pb.current == 100
}

// ============================================================
// Make Command Tests
// ============================================================

fn test_make_command_command() {
	cmd := new_make_command_command()
	assert cmd.name() == 'make:command'
	assert cmd.description().len > 0
	assert cmd.signature() == '<name>'
}

fn test_make_controller_command() {
	cmd := new_make_controller_command()
	assert cmd.name() == 'make:controller'
	assert cmd.description().len > 0
	assert cmd.signature() == '<name> [--resource]'
}

fn test_make_middleware_command() {
	cmd := new_make_middleware_command()
	assert cmd.name() == 'make:middleware'
	assert cmd.description().len > 0
}

fn test_make_provider_command() {
	cmd := new_make_provider_command()
	assert cmd.name() == 'make:provider'
	assert cmd.description().len > 0
}

fn test_make_entity_command() {
	cmd := new_make_entity_command()
	assert cmd.name() == 'make:entity'
	assert cmd.description().len > 0
}

fn test_make_model_command() {
	cmd := new_make_model_command()
	assert cmd.name() == 'make:model'
	assert cmd.description().len > 0
}

fn test_make_migration_command() {
	cmd := new_make_migration_command()
	assert cmd.name() == 'make:migration'
	assert cmd.description().len > 0
}

fn test_make_resource_command() {
	cmd := new_make_resource_command()
	assert cmd.name() == 'make:resource'
	assert cmd.description().len > 0
}

fn test_make_seeder_command() {
	cmd := new_make_seeder_command()
	assert cmd.name() == 'make:seeder'
	assert cmd.description().len > 0
}

fn test_make_factory_command() {
	cmd := new_make_factory_command()
	assert cmd.name() == 'make:factory'
	assert cmd.description().len > 0
}

// ============================================================
// Case Conversion Tests
// ============================================================

fn test_to_snake_case() {
	assert to_snake_case('HelloWorld') == 'hello_world'
	assert to_snake_case('PostController') == 'post_controller'
	assert to_snake_case('Simple') == 'simple'
	assert to_snake_case('HTMLParser') == 'h_t_m_l_parser'
}

fn test_to_pascal_case() {
	assert to_pascal_case('hello_world') == 'HelloWorld'
	assert to_pascal_case('post_controller') == 'PostController'
	assert to_pascal_case('simple') == 'Simple'
	assert to_pascal_case('hello-world') == 'HelloWorld'
}
