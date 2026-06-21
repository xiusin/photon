module retry

import time

// retryable.v - @[retryable] Annotation Support (Spring @Retryable inspired)
//
// Provides annotation-based retry for service/repository methods with
// configurable backoff policies and error-type filtering.
//
// Supported @[retryable] attribute forms:
//   @[retryable]                                            — defaults (3 attempts, 100ms fixed delay)
//   @[retryable: 'max_attempts:5']                          — 5 attempts
//   @[retryable: 'delay:200']                               — 200ms base delay
//   @[retryable: 'backoff:exponential']                     — exponential backoff
//   @[retryable: 'max_attempts:5;delay:200;backoff:exponential']
//   @[retryable: 'retry_for:NetworkError']                  — only retry NetworkError
//   @[retryable: 'no_retry_for:ValidationError']            — never retry ValidationError
//   @[retryable: 'retry_for:NetworkError,TimeoutError']     — retry multiple types
//
// Usage (programmatic API):
//   config := retry.RetryConfig{
//       max_attempts: 3
//       delay:        100 * time.millisecond
//       backoff:      .exponential
//       retry_for:    ['NetworkError']
//   }
//   result := retry.execute_with_retry[int](config, fn () !int {
//       return call_remote_service()!
//   })!
//
// The @[retryable] attribute is detected at compile time via
// extract_retryable_methods[T](); the actual retry wrapping is performed
// by execute_with_retry[T]() at runtime. This mirrors how Photon's
// @[transactional] annotation works: parse-time metadata + runtime executor.

// ── BackoffPolicy ──

// BackoffPolicy defines how the delay between retries grows.
pub enum BackoffPolicy {
	fixed       // constant delay between retries
	linear      // delay increases linearly: delay * attempt
	exponential // delay doubles each retry: delay * 2^(attempt-1)
}

// backoff_from_str parses a BackoffPolicy from a string.
pub fn backoff_from_str(s string) BackoffPolicy {
	return match s.to_lower() {
		'fixed' { .fixed }
		'linear' { .linear }
		'exponential', 'exp' { .exponential }
		else { .fixed }
	}
}

// ── RetryConfig ──

// RetryConfig holds the parsed configuration for a retryable operation.
pub struct RetryConfig {
pub mut:
	max_attempts int           = 3                      // total attempts (including the first)
	delay        time.Duration = 100 * time.millisecond // base delay between retries
	backoff      BackoffPolicy = .fixed                 // delay growth policy
	retry_for    []string // error type names to retry on (empty = retry all)
	no_retry_for []string // error type names to NOT retry on (takes precedence)
}

// new_retry_config creates a RetryConfig with defaults.
pub fn new_retry_config() RetryConfig {
	return RetryConfig{}
}

// ── Attribute Parsing ──

// parse_retryable_attr parses the @[retryable] attribute string into a RetryConfig.
//
// Accepted forms:
//   ''                                                       → all defaults
//   'max_attempts:5'                                         → 5 attempts
//   'delay:200'                                              → 200ms base delay
//   'backoff:exponential'                                    → exponential backoff
//   'retry_for:NetworkError'                                 → only retry NetworkError
//   'retry_for:NetworkError,TimeoutError'                    → retry multiple types
//   'no_retry_for:ValidationError'                           → never retry ValidationError
//   'max_attempts:5;delay:200;backoff:exponential;retry_for:NetworkError'
pub fn parse_retryable_attr(attr string) RetryConfig {
	mut rc := new_retry_config()

	if attr.len == 0 {
		return rc
	}

	// Strip surrounding quotes (comptime method.attrs includes them for
	// @[retryable: '...'] form): e.g. 'max_attempts:5' → max_attempts:5
	cleaned := attr.trim_space().trim('"').trim("'").trim_space()
	if cleaned.len == 0 {
		return rc
	}

	parts := cleaned.split(';')
	for part in parts {
		p := part.trim_space()
		if p.len == 0 {
			continue
		}
		if p.starts_with('max_attempts:') {
			rc.max_attempts = p['max_attempts:'.len..].trim_space().int()
		} else if p.starts_with('delay:') {
			ms := p['delay:'.len..].trim_space().int()
			rc.delay = ms * time.millisecond
		} else if p.starts_with('backoff:') {
			rc.backoff = backoff_from_str(p['backoff:'.len..].trim_space())
		} else if p.starts_with('retry_for:') {
			names := p['retry_for:'.len..].split(',')
			for name in names {
				cleaned_name := name.trim_space().trim('"').trim("'").trim_space()
				if cleaned_name.len > 0 {
					rc.retry_for << cleaned_name
				}
			}
		} else if p.starts_with('no_retry_for:') {
			names := p['no_retry_for:'.len..].split(',')
			for name in names {
				cleaned_name := name.trim_space().trim('"').trim("'").trim_space()
				if cleaned_name.len > 0 {
					rc.no_retry_for << cleaned_name
				}
			}
		}
	}

	// Clamp max_attempts to a safe minimum so the loop always runs at least once.
	if rc.max_attempts <= 0 {
		rc.max_attempts = 1
	}

	return rc
}

// ── Backoff Calculation ──

// delay_for_attempt returns the delay to apply BEFORE the given attempt.
// attempt is 1-indexed (attempt 1 is the first try, which has no preceding delay).
//
//   fixed:       delay                    (constant)
//   linear:      delay * attempt          (100ms, 200ms, 300ms, ...)
//   exponential: delay * 2^(attempt-1)    (100ms, 200ms, 400ms, 800ms, ...)
pub fn (rc RetryConfig) delay_for_attempt(attempt int) time.Duration {
	if attempt <= 1 {
		return rc.delay
	}
	return match rc.backoff {
		.fixed { rc.delay }
		.linear { rc.delay * attempt }
		.exponential { rc.delay * (1 << (attempt - 1)) }
	}
}

// ── Error Type Matching ──

// error_type_matches checks whether an error matches a type name string
// from retry_for / no_retry_for.
//
// V's `err is Type` only works with compile-time types, so for runtime
// string matching we use two strategies (same approach as orm.transaction):
//   1. typeof(err).name — may return the dynamic type name for custom
//      error structs (e.g. "NetworkError" or "retry.NetworkError").
//   2. err.msg() — fallback: check if the error message contains the
//      type name. This handles string errors and custom structs whose
//      msg() includes the type name.
pub fn error_type_matches(err IError, type_name string) bool {
	// Strategy 1: typeof name (strip module prefix if present)
	tn := typeof(err).name
	if tn == type_name || tn.ends_with('.' + type_name) {
		return true
	}
	// Strategy 2: error message contains the type name
	return err.msg().contains(type_name)
}

// should_retry decides whether an error should be retried given the config.
//
// Rules (in priority order):
//   1. If the error matches any entry in no_retry_for → do NOT retry.
//   2. If retry_for is non-empty and the error does NOT match any entry → do NOT retry.
//   3. Otherwise → retry.
pub fn should_retry(config RetryConfig, err IError) bool {
	// Check no_retry_for first (takes precedence)
	for no_retry_type in config.no_retry_for {
		if error_type_matches(err, no_retry_type) {
			return false
		}
	}

	// If retry_for is specified, only retry those types
	if config.retry_for.len > 0 {
		for retry_type in config.retry_for {
			if error_type_matches(err, retry_type) {
				return true
			}
		}
		return false
	}

	// Default: retry all errors
	return true
}

// ── Retry Execution (SubTask C3.2) ──

// execute_with_retry runs `operation` with retry logic per `config`.
//
// The operation is invoked up to `max_attempts` times. On error:
//   - If should_retry() returns false, the error is returned immediately.
//   - If this was the last attempt, the original error is returned.
//   - Otherwise, the thread sleeps for delay_for_attempt(attempt) and retries.
//
// On success, the result is returned immediately (no further attempts).
//
// Thread-safety: the retry logic uses only local state and the immutable
// config, so it is safe to call concurrently from multiple goroutines.
// Any shared mutable state must be synchronised by the caller's operation.
//
// Usage:
//   result := retry.execute_with_retry[int](config, fn () !int {
//       return fetch_count()!
//   })!
pub fn execute_with_retry[T](config RetryConfig, operation fn () !T) !T {
	// Clamp to a safe minimum so the loop always runs at least once.
	attempts := if config.max_attempts <= 0 { 1 } else { config.max_attempts }

	for attempt in 1 .. attempts + 1 {
		// Try the operation
		result := operation() or {
			// err is the captured IError from the failed operation
			// Check if we should retry this error type
			if !should_retry(config, err) {
				return err
			}
			// If this was the last attempt, return the original error
			if attempt >= attempts {
				return err
			}
			// Wait before retrying (backoff delay for the attempt just failed)
			time.sleep(config.delay_for_attempt(attempt))
			continue
		}
		// Success — return immediately
		return result
	}

	// Unreachable: the loop always returns on success or on the final attempt.
	return error('retry: unreachable state (attempts=${attempts})')
}

// execute_void_with_retry runs a void (no-return) operation with retry logic.
//
// This is a convenience wrapper around execute_with_retry for operations
// that do not produce a value. The operation is retried on retriable errors
// and propagates the last error if all attempts are exhausted.
//
// Usage:
//   retry.execute_void_with_retry(config, fn () ! {
//       send_email()!
//   })!
pub fn execute_void_with_retry(config RetryConfig, operation fn () !) ! {
	execute_with_retry[bool](config, fn [operation] () !bool {
		operation()!
		return true
	})!
}

// ── Comptime Annotation Scanning (SubTask C3.2) ──

// RetryMethodInfo describes a method annotated with @[retryable].
pub struct RetryMethodInfo {
pub:
	method_name string
	config      RetryConfig
	attrs       []string
}

// extract_retryable_methods scans type T at compile time for methods
// annotated with @[retryable]. Returns one RetryMethodInfo per annotated
// method, with the attribute string parsed into a RetryConfig.
//
// This is a pure comptime scan — zero runtime reflection. The returned
// metadata can be used by an AOP proxy or application context to wrap
// the method call with execute_with_retry at runtime.
//
// V comptime note: method-level attributes are inspected via
// `method.attrs` (a []string) inside `$for method in T.methods`. Each
// entry is the raw attribute text: 'retryable', 'retryable:max_attempts:5',
// or 'retryable("max_attempts:5")'.
//
// Usage:
//   methods := retry.extract_retryable_methods[MyService]()
pub fn extract_retryable_methods[T]() []RetryMethodInfo {
	mut methods := []RetryMethodInfo{}
	$for method in T.methods {
		mut has_retryable := false
		mut config := new_retry_config()
		for attr in method.attrs {
			if attr == 'retryable' {
				has_retryable = true
			} else if attr.starts_with('retryable:') {
				has_retryable = true
				arg := attr['retryable:'.len..]
				config = parse_retryable_attr(arg)
			} else if attr.starts_with('retryable(') {
				has_retryable = true
				end_idx := attr.last_index(')') or { attr.len }
				inner := attr['retryable('.len..end_idx]
				config = parse_retryable_attr(inner)
			}
		}
		if has_retryable {
			methods << RetryMethodInfo{
				method_name: method.name
				config:      config
				attrs:       method.attrs.clone()
			}
		}
	}
	return methods
}

// is_retry_annotated returns true if type T has any @[retryable] methods.
pub fn is_retry_annotated[T]() bool {
	return extract_retryable_methods[T]().len > 0
}
