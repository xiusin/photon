module orm

// ── TransactionAttribute Parsing Tests ──

fn test_parse_transactional_attr_default() {
	attr := parse_transactional_attr('')
	assert attr.propagation == .required
	assert attr.isolation == .default_
	assert !attr.readonly
	assert attr.timeout_ms == 0
}

fn test_parse_transactional_attr_readonly() {
	attr := parse_transactional_attr('readonly')
	assert attr.readonly
	assert attr.propagation == .required

	attr2 := parse_transactional_attr('read_only')
	assert attr2.readonly
}

fn test_parse_transactional_attr_requires_new() {
	attr := parse_transactional_attr('requires_new')
	assert attr.propagation == .requires_new
}

fn test_parse_transactional_attr_nested() {
	attr := parse_transactional_attr('nested')
	assert attr.propagation == .nested
}

fn test_parse_transactional_attr_complex() {
	attr :=
		parse_transactional_attr('propagation:requires_new;isolation:read_committed;readonly;timeout:5000')
	assert attr.propagation == .requires_new
	assert attr.isolation == .read_committed
	assert attr.readonly
	assert attr.timeout_ms == 5000
}

fn test_parse_transactional_attr_rollback() {
	attr := parse_transactional_attr('rollback:NotFoundException;no_rollback:ValidationException')
	assert attr.rollback_for.len == 1
	assert attr.rollback_for[0] == 'NotFoundException'
	assert attr.no_rollback_for.len == 1
	assert attr.no_rollback_for[0] == 'ValidationException'
}

// ── Propagation Parsing Tests ──

fn test_propagation_from_str() {
	assert propagation_from_str('required') == .required
	assert propagation_from_str('requires_new') == .requires_new
	assert propagation_from_str('nested') == .nested
	assert propagation_from_str('supports') == .supports
	assert propagation_from_str('not_supported') == .not_supported
	assert propagation_from_str('mandatory') == .mandatory
	assert propagation_from_str('never') == .never
	assert propagation_from_str('unknown') == .required // default
}

fn test_propagation_from_str_case_insensitive() {
	assert propagation_from_str('REQUIRES_NEW') == .requires_new
	assert propagation_from_str('Nested') == .nested
}

// ── Isolation Parsing Tests ──

fn test_isolation_from_str() {
	assert isolation_from_str('default') == .default_
	assert isolation_from_str('read_uncommitted') == .read_uncommitted
	assert isolation_from_str('read_committed') == .read_committed
	assert isolation_from_str('repeatable_read') == .repeatable_read
	assert isolation_from_str('serializable') == .serializable
	assert isolation_from_str('unknown') == .default_ // default
}

// ── TransactionAttribute Constructor Tests ──

fn test_new_transaction_attribute() {
	attr := new_transaction_attribute()
	assert attr.propagation == .required
	assert attr.isolation == .default_
	assert !attr.readonly
	assert attr.timeout_ms == 0
	assert attr.rollback_for.len == 0
	assert attr.no_rollback_for.len == 0
}

// ── TransactionContext Tests ──

fn test_new_transaction_context() {
	attr := TransactionAttribute{
		propagation: .requires_new
		isolation:   .read_committed
		readonly:    true
		timeout_ms:  5000
	}
	ctx := new_transaction_context(attr)
	assert ctx.propagation == .requires_new
	assert ctx.isolation == .read_committed
	assert ctx.readonly
	assert ctx.timeout_ms == 5000
	assert ctx.is_active
	assert ctx.savepoints.len == 0
}

// ── TransactionalInterceptor Tests ──

fn test_new_transactional_interceptor() {
	ti := new_transactional_interceptor(unsafe { nil })
	assert isnil(ti.tx_manager)
}

fn test_transactional_interceptor_begin_nil_manager() {
	mut ti := new_transactional_interceptor(unsafe { nil })
	ti.begin_if_needed(new_transaction_attribute()) or { return }
	assert false // should have errored
}

// ── Transactional Event Listener Attribute Parsing Tests ──

fn test_parse_transactional_event_listener_default() {
	phase := parse_transactional_event_listener_attr('')
	assert phase == 'after_commit'
}

fn test_parse_transactional_event_listener_before_commit() {
	phase := parse_transactional_event_listener_attr('before_commit')
	assert phase == 'before_commit'
}

fn test_parse_transactional_event_listener_after_rollback() {
	phase := parse_transactional_event_listener_attr('after_rollback')
	assert phase == 'after_rollback'
}

fn test_parse_transactional_event_listener_after_completion() {
	phase := parse_transactional_event_listener_attr('after_completion')
	assert phase == 'after_completion'
}

fn test_parse_transactional_event_listener_quoted() {
	phase := parse_transactional_event_listener_attr("'before_commit'")
	assert phase == 'before_commit'
}

fn test_parse_transactional_event_listener_phase_prefix() {
	phase := parse_transactional_event_listener_attr("phase: 'after_rollback'")
	assert phase == 'after_rollback'
}

fn test_parse_transactional_event_listener_invalid_defaults() {
	phase := parse_transactional_event_listener_attr('invalid_phase')
	assert phase == 'after_commit'
}
