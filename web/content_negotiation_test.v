module web

// content_negotiation_test.v - Tests for ContentNegotiationManager and strategies

fn test_accept_header_strategy_default() {
	s := new_accept_header_strategy()
	result := s.resolve_content_type('', map[string]string{})!
	assert result == 'application/json'
}

fn test_accept_header_strategy_json() {
	s := new_accept_header_strategy()
	result := s.resolve_content_type('application/json', map[string]string{})!
	assert result == 'application/json'
}

fn test_accept_header_strategy_multiple_types() {
	s := new_accept_header_strategy()
	result := s.resolve_content_type('text/html,application/json', map[string]string{})!
	assert result == 'text/html' // first one wins with equal q
}

fn test_accept_header_strategy_with_q_values() {
	s := new_accept_header_strategy()
	result := s.resolve_content_type('text/html;q=0.5,application/json;q=0.9', map[string]string{})!
	assert result == 'application/json' // higher q wins
}

fn test_accept_header_strategy_wildcard() {
	s := new_accept_header_strategy()
	result := s.resolve_content_type('*/*', map[string]string{})!
	assert result == 'application/json' // default for wildcard
}

fn test_parameter_strategy_json() {
	mut s := new_parameter_strategy()
	params := {
		'format': 'json'
	}
	result := s.resolve_content_type('', params)!
	assert result == 'application/json'
}

fn test_parameter_strategy_xml() {
	mut s := new_parameter_strategy()
	params := {
		'format': 'xml'
	}
	result := s.resolve_content_type('', params)!
	assert result == 'application/xml'
}

fn test_parameter_strategy_missing_param() {
	s := new_parameter_strategy()
	mut failed := false
	s.resolve_content_type('', map[string]string{}) or { failed = true }
	assert failed
}

fn test_parameter_strategy_unknown_value() {
	s := new_parameter_strategy()
	params := {
		'format': 'unknown'
	}
	mut failed := false
	s.resolve_content_type('', params) or { failed = true }
	assert failed
}

fn test_parameter_strategy_custom_mapping() {
	mut s := new_parameter_strategy()
	s.add_media_type('pdf', 'application/pdf')
	params := {
		'format': 'pdf'
	}
	result := s.resolve_content_type('', params)!
	assert result == 'application/pdf'
}

fn test_fixed_strategy() {
	s := new_fixed_strategy('text/csv')
	result := s.resolve_content_type('', map[string]string{})!
	assert result == 'text/csv'
}

fn test_content_negotiation_manager_empty() {
	m := new_content_negotiation_manager()
	mut failed := false
	m.resolve_content_type('', map[string]string{}) or { failed = true }
	assert failed
}

fn test_content_negotiation_manager_with_strategies() {
	mut m := new_content_negotiation_manager()
	m.add_strategy(new_parameter_strategy())
	m.add_strategy(new_accept_header_strategy())

	// Parameter strategy succeeds first
	params := {
		'format': 'json'
	}
	result := m.resolve_content_type('text/html', params)!
	assert result == 'application/json'
}

fn test_content_negotiation_manager_falls_through() {
	mut m := new_content_negotiation_manager()
	m.add_strategy(new_parameter_strategy()) // will fail (no param)
	m.add_strategy(new_accept_header_strategy()) // will succeed

	result := m.resolve_content_type('application/json', map[string]string{})!
	assert result == 'application/json'
}

fn test_content_negotiation_strategy_interface_compatible() {
	mut strategies := []ContentNegotiationStrategy{}
	strategies << new_accept_header_strategy()
	strategies << new_fixed_strategy('text/plain')
	strategies << new_parameter_strategy()

	for s in strategies {
		// verify method is callable
		_ := s.resolve_content_type('', map[string]string{}) or { '' }
	}
}
