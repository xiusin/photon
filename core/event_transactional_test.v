module core

// event_transactional_test.v - Tests for TransactionalEventListener support

struct CommitListener {
mut:
	called bool
}

fn (l CommitListener) phase() TransactionPhase {
	return .after_commit
}

fn (mut l CommitListener) handle(event &Event) {
	l.called = true
}

struct RollbackListener {
mut:
	called bool
}

fn (l RollbackListener) phase() TransactionPhase {
	return .after_rollback
}

fn (mut l RollbackListener) handle(event &Event) {
	l.called = true
}

struct BeforeCommitListener {
mut:
	called bool
}

fn (l BeforeCommitListener) phase() TransactionPhase {
	return .before_commit
}

fn (mut l BeforeCommitListener) handle(event &Event) {
	l.called = true
}

struct CompletionListener {
mut:
	called bool
}

fn (l CompletionListener) phase() TransactionPhase {
	return .after_completion
}

fn (mut l CompletionListener) handle(event &Event) {
	l.called = true
}

fn test_transactional_event_listener_after_commit() {
	mut bus := new_event_bus()
	mut commit_listener := &CommitListener{}

	bus.on_transactional('user.created', commit_listener)

	event := new_event('user.created', 'alice')
	// Should NOT fire on rollback
	bus.dispatch_transactional(event, .after_rollback)
	assert commit_listener.called == false

	// Should fire on commit
	bus.dispatch_transactional(event, .after_commit)
	assert commit_listener.called == true
}

fn test_transactional_event_listener_after_rollback() {
	mut bus := new_event_bus()
	mut rollback_listener := &RollbackListener{}

	bus.on_transactional('user.created', rollback_listener)

	event := new_event('user.created', 'alice')
	// Should NOT fire on commit
	bus.dispatch_transactional(event, .after_commit)
	assert rollback_listener.called == false

	// Should fire on rollback
	bus.dispatch_transactional(event, .after_rollback)
	assert rollback_listener.called == true
}

fn test_transactional_event_listener_before_commit() {
	mut bus := new_event_bus()
	mut before_listener := &BeforeCommitListener{}

	bus.on_transactional('user.created', before_listener)

	event := new_event('user.created', 'alice')
	bus.dispatch_transactional(event, .before_commit)
	assert before_listener.called == true

	// Should NOT fire on after_commit
	mut before_listener2 := &BeforeCommitListener{}
	bus.on_transactional('user.created2', before_listener2)
	event2 := new_event('user.created2', 'bob')
	bus.dispatch_transactional(event2, .after_commit)
	assert before_listener2.called == false
}

fn test_transactional_event_listener_after_completion() {
	mut bus := new_event_bus()
	mut completion_listener := &CompletionListener{}

	bus.on_transactional('user.created', completion_listener)

	event := new_event('user.created', 'alice')
	// after_completion listeners should fire for both commit and rollback
	bus.dispatch_transactional(event, .after_commit)
	assert completion_listener.called == true

	mut completion_listener2 := &CompletionListener{}
	bus.on_transactional('user.created2', completion_listener2)
	event2 := new_event('user.created2', 'bob')
	bus.dispatch_transactional(event2, .after_rollback)
	assert completion_listener2.called == true
}

fn test_transactional_event_listener_no_match() {
	mut bus := new_event_bus()
	mut commit_listener := &CommitListener{}

	bus.on_transactional('user.created', commit_listener)

	event := new_event('user.deleted', 'alice') // different event name
	called := bus.dispatch_transactional(event, .after_commit)
	assert called == 0
	assert commit_listener.called == false
}

fn test_transactional_event_listener_multiple() {
	mut bus := new_event_bus()
	mut commit_listener := &CommitListener{}
	mut rollback_listener := &RollbackListener{}

	bus.on_transactional('user.created', commit_listener)
	bus.on_transactional('user.created', rollback_listener)

	event := new_event('user.created', 'alice')
	// Only commit listener should fire
	called := bus.dispatch_transactional(event, .after_commit)
	assert called == 1
	assert commit_listener.called == true
	assert rollback_listener.called == false
}

fn test_transactional_event_listener_dispatch_all() {
	mut bus := new_event_bus()
	mut commit_listener := &CommitListener{}
	mut rollback_listener := &RollbackListener{}

	bus.on_transactional('user.created', commit_listener)
	bus.on_transactional('user.created', rollback_listener)

	event := new_event('user.created', 'alice')
	called := bus.dispatch_transactional_all(event)
	assert called == 2
	assert commit_listener.called == true
	assert rollback_listener.called == true
}

fn test_transactional_event_listener_returns_count() {
	mut bus := new_event_bus()
	mut l1 := &CommitListener{}
	mut l2 := &CommitListener{}
	mut l3 := &CommitListener{}

	bus.on_transactional('user.created', l1)
	bus.on_transactional('user.created', l2)
	bus.on_transactional('user.created', l3)

	event := new_event('user.created', 'alice')
	called := bus.dispatch_transactional(event, .after_commit)
	assert called == 3
}

fn test_transaction_phase_enum_values() {
	assert TransactionPhase.before_commit == TransactionPhase.before_commit
	assert TransactionPhase.after_commit == TransactionPhase.after_commit
	assert TransactionPhase.after_rollback == TransactionPhase.after_rollback
	assert TransactionPhase.after_completion == TransactionPhase.after_completion
}
