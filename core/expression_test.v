module core

// expression_test.v - Tests for Photon Expression Language
// Note: \$ is used to escape V's string interpolation in test strings.

fn test_resolve_placeholders_simple() {
	props := {
		'app.name': 'PhotonAPI'
		'app.version': '2.0'
	}

	result := resolve_placeholders('\${app.name} v\${app.version}', props)
	assert result == 'PhotonAPI v2.0'
}

fn test_resolve_placeholders_with_default() {
	props := map[string]string{}

	result := resolve_placeholders('\${app.name:MyApp}', props)
	assert result == 'MyApp'
}

fn test_resolve_placeholders_mixed() {
	props := {
		'app.name': 'PhotonAPI'
	}

	result := resolve_placeholders('\${app.name:MyApp} v\${app.version:1.0}', props)
	assert result == 'PhotonAPI v1.0'
}

fn test_resolve_placeholders_no_default() {
	props := map[string]string{}

	result := resolve_placeholders('\${app.name}', props)
	assert result == '\${app.name}'
}

fn test_resolve_placeholders_nested() {
	props := {
		'prefix': 'app'
		'app.name': 'PhotonAPI'
	}

	result := resolve_placeholders('\${\${prefix}.name}', props)
	assert result == 'PhotonAPI'
}

fn test_resolve_placeholders_no_placeholders() {
	props := map[string]string{}

	result := resolve_placeholders('hello world', props)
	assert result == 'hello world'
}

fn test_resolve_placeholders_empty() {
	props := map[string]string{}

	result := resolve_placeholders('', props)
	assert result == ''
}

fn test_eval_condition_eq() {
	props := {
		'app.env': 'prod'
	}

	assert eval_condition('app.env==prod', props) == true
	assert eval_condition('app.env==dev', props) == false
}

fn test_eval_condition_neq() {
	props := {
		'app.env': 'prod'
	}

	assert eval_condition('app.env!=dev', props) == true
	assert eval_condition('app.env!=prod', props) == false
}

fn test_eval_condition_existence() {
	props := {
		'feature.x': 'true'
	}

	assert eval_condition('feature.x', props) == true
	assert eval_condition('feature.y', props) == false
}

fn test_eval_condition_negation() {
	props := {
		'feature.disabled': 'true'
	}

	assert eval_condition('!feature.disabled', props) == false
	assert eval_condition('!feature.enabled', props) == true
}

fn test_eval_condition_and() {
	props := {
		'app.env': 'prod'
		'feature.x': 'true'
	}

	assert eval_condition('app.env==prod && feature.x', props) == true
	assert eval_condition('app.env==prod && feature.y', props) == false
}

fn test_eval_condition_or() {
	props := {
		'app.env': 'staging'
	}

	assert eval_condition('app.env==prod || app.env==staging', props) == true
	assert eval_condition('app.env==prod || app.env==dev', props) == false
}

fn test_eval_condition_complex() {
	props := {
		'app.env': 'prod'
		'feature.x': 'true'
		'feature.y': ''
	}

	// (env==prod AND feature.x) OR feature.y
	assert eval_condition('app.env==prod && feature.x || feature.y', props) == true
}

fn test_eval_condition_empty() {
	props := map[string]string{}

	assert eval_condition('', props) == true
}

fn test_split_default_single() {
	result := split_default('key')
	assert result.len == 1
	assert result[0] == 'key'
}

fn test_split_default_with_default() {
	result := split_default('key:default')
	assert result.len == 2
	assert result[0] == 'key'
	assert result[1] == 'default'
}

fn test_split_default_multiple_colons() {
	result := split_default('key:http://example.com')
	assert result.len == 2
	assert result[0] == 'key'
	assert result[1] == 'http://example.com'
}

fn test_env_to_map() {
	mut env := new_environment()
	env.set_property('app.name', 'TestApp')
	env.set_property('app.version', '1.0')

	result := env_to_map(mut env)
	assert result['app.name'] == 'TestApp'
	assert result['app.version'] == '1.0'
}
