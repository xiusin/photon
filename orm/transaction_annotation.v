module orm

// transaction_annotation.v - @[transactional] Annotation Support (Spring @Transactional inspired)
//
// Provides annotation-based transaction management for repository methods.
// The @[transactional] attribute is detected at compile time and used
// to wrap the method call in a transaction.
//
// Supported attributes:
//   @[transactional]                              — default (REQUIRED, default isolation)
//   @[transactional: 'readonly']                 — read-only transaction
//   @[transactional: 'requires_new']              — always create a new transaction
//   @[transactional: 'nested']                    — nested with savepoint
//   @[transactional: 'propagation:requires_new;isolation:read_committed']
//
// Usage:
//   @[repository]
//   pub struct UserRepository {
//       @[autowired]
//       repo &BaseRepository[User]
//   }
//
//   @[transactional]
//   pub fn (mut r UserRepository) create_user(mut user User) ! {
//       r.repo.save(mut user)!
//   }

// ── TransactionAttribute ──

// TransactionAttribute holds parsed attributes from @[transactional].
pub struct TransactionAttribute {
pub mut:
	propagation     Propagation = .required
	isolation       Isolation   = .default_
	readonly        bool
	timeout_ms      int      // 0 = no timeout
	rollback_for    []string // exception type names that trigger rollback
	no_rollback_for []string // exception type names that do NOT trigger rollback
}

// new_transaction_attribute creates a TransactionAttribute with defaults.
pub fn new_transaction_attribute() TransactionAttribute {
	return TransactionAttribute{
		propagation: .required
		isolation:   .default_
	}
}

// ── Attribute Parsing ──

// parse_transactional_attr parses the @[transactional] attribute string.
// Supports:
//   ''                                    → defaults (REQUIRED, default isolation)
//   'readonly'                           → read-only transaction
//   'requires_new'                       → REQUIRES_NEW propagation
//   'nested'                              → NESTED propagation
//   'propagation:requires_new'            → explicit propagation
//   'isolation:read_committed'            → explicit isolation
//   'timeout:5000'                         → timeout in milliseconds
//   'rollback:NotFoundException'          → rollback for specific exception
pub fn parse_transactional_attr(attr string) TransactionAttribute {
	mut ta := new_transaction_attribute()

	if attr.len == 0 {
		return ta
	}

	// Simple shorthand: 'readonly', 'requires_new', 'nested'
	lower := attr.to_lower()
	if lower == 'readonly' || lower == 'read_only' {
		ta.readonly = true
		return ta
	}

	propagation := propagation_from_str(lower)
	if propagation != .required || lower == 'required' {
		ta.propagation = propagation
		return ta
	}

	// Complex: key:value pairs separated by ';'
	parts := attr.split(';')
	for part in parts {
		p := part.trim_space()
		if p.starts_with('propagation:') {
			ta.propagation = propagation_from_str(p['propagation:'.len..])
		} else if p.starts_with('isolation:') {
			ta.isolation = isolation_from_str(p['isolation:'.len..])
		} else if p.starts_with('readonly') || p.starts_with('read_only') {
			ta.readonly = true
		} else if p.starts_with('timeout:') {
			ta.timeout_ms = p['timeout:'.len..].int()
		} else if p.starts_with('rollback:') {
			ta.rollback_for << p['rollback:'.len..]
		} else if p.starts_with('no_rollback:') {
			ta.no_rollback_for << p['no_rollback:'.len..]
		} else {
			// Try to parse as propagation shorthand
			prop := propagation_from_str(p)
			if prop != .required || p == 'required' {
				ta.propagation = prop
			}
		}
	}

	return ta
}

// propagation_from_str parses a Propagation value from string.
pub fn propagation_from_str(s string) Propagation {
	return match s.to_lower() {
		'required' { .required }
		'requires_new' { .requires_new }
		'nested' { .nested }
		'supports' { .supports }
		'not_supported', 'notsupported' { .not_supported }
		'mandatory' { .mandatory }
		'never' { .never }
		else { .required }
	}
}

// isolation_from_str parses an Isolation value from string.
pub fn isolation_from_str(s string) Isolation {
	return match s.to_lower() {
		'default', '' { .default_ }
		'read_uncommitted', 'readuncommitted' { .read_uncommitted }
		'read_committed', 'readcommitted' { .read_committed }
		'repeatable_read', 'repeatableread' { .repeatable_read }
		'serializable' { .serializable }
		else { .default_ }
	}
}

// parse_transactional_event_listener_attr parses the @[transactional_event_listener]
// attribute string and returns the transaction phase as a string identifier.
// Returns one of: 'before_commit', 'after_commit', 'after_rollback', 'after_completion'.
// This string can be mapped to core.TransactionPhase by the caller, avoiding a
// circular dependency between orm and core.
pub fn parse_transactional_event_listener_attr(attr string) string {
	// Expected formats:
	//   @[transactional_event_listener]                         → 'after_commit' (default)
	//   @[transactional_event_listener('before_commit')]        → 'before_commit'
	//   @[transactional_event_listener(phase: 'after_rollback')] → 'after_rollback'
	s := attr.trim_space()
	if s.len == 0 {
		return 'after_commit'
	}

	// Strip surrounding quotes if present
	cleaned := s.trim('"').trim("'").trim_space()
	if cleaned.len == 0 {
		return 'after_commit'
	}

	// Handle 'phase: value' format
	mut phase_str := cleaned
	if cleaned.starts_with('phase:') {
		phase_str = cleaned[6..].trim_space().trim('"').trim("'").trim_space()
	}

	return match phase_str.to_lower() {
		'before_commit', 'beforecommit' { 'before_commit' }
		'after_commit', 'aftercommit' { 'after_commit' }
		'after_rollback', 'afterrollback' { 'after_rollback' }
		'after_completion', 'aftercompletion' { 'after_completion' }
		else { 'after_commit' }
	}
}

// ── TransactionContext ──

// TransactionContext holds the current transaction state for the active scope.
pub struct TransactionContext {
pub:
	propagation Propagation
	isolation   Isolation
	readonly    bool
	timeout_ms  int
pub mut:
	is_active  bool
	savepoints []string // named savepoints for nested transactions
}

// new_transaction_context creates a TransactionContext from a TransactionAttribute.
pub fn new_transaction_context(attr TransactionAttribute) &TransactionContext {
	return &TransactionContext{
		propagation: attr.propagation
		isolation:   attr.isolation
		readonly:    attr.readonly
		timeout_ms:  attr.timeout_ms
		is_active:   true
		savepoints:  []string{}
	}
}

// ── TransactionalInterceptor ──

// TransactionalInterceptor provides around-advice for transactional methods.
// It manages the transaction lifecycle based on TransactionAttribute.
pub struct TransactionalInterceptor {
pub mut:
	tx_manager &TransactionManager = unsafe { nil }
}

// new_transactional_interceptor creates a TransactionalInterceptor.
pub fn new_transactional_interceptor(tx_mgr &TransactionManager) &TransactionalInterceptor {
	return &TransactionalInterceptor{
		tx_manager: unsafe { tx_mgr }
	}
}

// begin_if_needed starts a transaction based on the TransactionAttribute.
// Returns true if a new transaction was started.
pub fn (mut ti TransactionalInterceptor) begin_if_needed(attr TransactionAttribute) !bool {
	if isnil(ti.tx_manager) {
		return error('TransactionalInterceptor: TransactionManager not set')
	}

	return match attr.propagation {
		.required {
			if !ti.tx_manager.is_active() {
				ti.tx_manager.begin()!
				true
			} else {
				false
			}
		}
		.requires_new {
			// If existing tx, commit/rollback it first, then start new
			if ti.tx_manager.is_active() {
				ti.tx_manager.commit() or { ti.tx_manager.rollback() or {} }
			}
			ti.tx_manager.begin()!
			true
		}
		.nested {
			if ti.tx_manager.is_active() {
				// Use savepoint_count to track nesting
				ti.tx_manager.savepoint_count++
				false
			} else {
				ti.tx_manager.begin()!
				true
			}
		}
		.supports {
			false
		}
		.not_supported {
			if ti.tx_manager.is_active() {
				ti.tx_manager.commit() or {}
			}
			false
		}
		.mandatory {
			if !ti.tx_manager.is_active() {
				error('no existing transaction found for MANDATORY propagation')
			} else {
				false
			}
		}
		.never {
			if ti.tx_manager.is_active() {
				error('existing transaction found for NEVER propagation')
			} else {
				false
			}
		}
	}
}

// commit_if_needed commits the transaction if it was started by this interceptor.
pub fn (mut ti TransactionalInterceptor) commit_if_needed(started bool) ! {
	if started && !isnil(ti.tx_manager) && ti.tx_manager.is_active() {
		ti.tx_manager.commit()!
	}
}

// rollback_if_needed rolls back the transaction on error.
pub fn (mut ti TransactionalInterceptor) rollback_if_needed(started bool) {
	if started && !isnil(ti.tx_manager) && ti.tx_manager.is_active() {
		ti.tx_manager.rollback() or { return }
	}
}
