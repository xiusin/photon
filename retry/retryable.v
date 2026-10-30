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
			// A negative delay would make time.sleep() a no-op; treat it as
			// "no delay" instead of silently retrying with nonsense config.
			rc.delay = if ms > 0 { ms * time.millisecond } else { time.Duration(0) }
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

// delay_for_attempt 返回「第 attempt 次尝试之前」要等多久（attempt 从 1 开始）。
//
// 「第 1 次尝试」是首次执行，前面不该有等待 —— 重试的意义是先试一次，
// 失败了再等。老实现里 `attempt <= 1` 直接返回 rc.delay，于是每一次
// 首次调用都白白睡了一个 delay。默认配置下是 100ms，看起来无害；
// 但配成 `delay:5000` 的支付回调就是每次调用先卡 5 秒。
//
//   fixed:       attempt 1 → 0；attempt≥2 → delay
//   linear:      delay * (attempt-1)      (0, 100ms, 200ms, 300ms, ...)
//   exponential: delay * 2^(attempt-2)    (0, 100ms, 200ms, 400ms, 800ms, ...)
pub fn (rc RetryConfig) delay_for_attempt(attempt int) time.Duration {
	if attempt <= 1 {
		return time.Duration(0)
	}
	factor := match rc.backoff {
		.fixed { i64(1) }
		.linear { i64(attempt - 1) }
		.exponential { exp_factor(attempt - 1) }
	}

	// Saturate instead of overflowing: at attempt 64 the shift no longer fits
	// in i64 and wraps to 0/negative, silently turning a "wait longer" policy
	// into "retry immediately". Sleeping longer than a day is already beyond
	// any sane retry policy, so clamp there.
	return saturating_multiply(rc.delay, factor)
}

// exp_factor 返回 2^(shift)，饱和到 max_retry_delay_ticks。
// shift 由调用方按「重试次数」给出：第 n 次重试（n 从 1 起）对应 2^(n-1)。
fn exp_factor(attempt int) i64 {
	shift := attempt - 1
	if shift >= 33 {
		return i64(max_retry_delay_ticks)
	}
	return i64(u64(1) << u64(shift))
}

// max_retry_delay_ticks is the upper bound (in time.Duration ticks) applied to
// computed backoff delays: 24h.
const max_retry_delay_ticks = i64(24) * 3600 * 1_000_000_000

// saturating_multiply multiplies a base delay by a factor, clamping the result
// to [0, max_retry_delay_ticks] so no overflow can produce a negative or zero
// delay for a non-zero base.
fn saturating_multiply(base time.Duration, factor i64) time.Duration {
	b := i64(base)
	if b <= 0 || factor <= 0 {
		return time.Duration(0)
	}
	if b > max_retry_delay_ticks / factor {
		return time.Duration(max_retry_delay_ticks)
	}
	return time.Duration(b * factor)
}

// ── Error Type Matching ──

// error_type_matches checks whether an error matches a type name string
// from retry_for / no_retry_for.
//
// V's `err is Type` only works with compile-time types, so for runtime
// string matching we use two strategies (same approach as orm.transaction):
//   1. typeof(err).name — the dynamic type name for custom error structs
//      (e.g. "NetworkError" or "retry.NetworkError").
//   2. err.msg() — fallback for string errors, matched as a whole word.
//
// The msg fallback deliberately requires a word boundary. V's `typeof()` on an
// `IError` value collapses to "IError", so a plain `msg().contains(name)` test
// made `retry_for:'error'` match every error in existence — and
// `no_retry_for:'error'` silently disabled retries for all of them except
// those whose message happened to contain "error". Matching "error" against a
// message also produced false positives on words like "error_code".
pub fn error_type_matches(err IError, type_name string) bool {
	if type_name.len == 0 {
		return false
	}
	// Strategy 1: typeof name (strip module prefix if present)
	tn := typeof(err).name
	if tn == type_name || tn.ends_with('.' + type_name) {
		return true
	}
	// Strategy 2: error message contains the type name as a whole word
	return contains_word(err.msg(), type_name)
}

// contains_word reports whether `word` occurs in `s` delimited by
// non-identifier characters on both sides (ASCII only, which is what error
// type names use).
fn contains_word(s string, word string) bool {
	if word.len == 0 || s.len < word.len {
		return false
	}
	mut from := 0
	for from + word.len <= s.len {
		idx := s.index_after(word, from) or { return false }
		before_ok := idx == 0 || !is_ident_char(s[idx - 1])
		end := idx + word.len
		after_ok := end == s.len || !is_ident_char(s[end])
		if before_ok && after_ok {
			return true
		}
		from = idx + 1
	}
	return false
}

// is_ident_char reports whether `c` may appear inside an identifier
// (letters, digits, underscore or dot — matching how type names are written).
fn is_ident_char(c u8) bool {
	return (c >= `a` && c <= `z`) || (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`)
		|| c == `_` || c == `.`
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
//   - Otherwise, the thread sleeps for delay_for_attempt(attempt + 1) and retries.
//
// 注意那个 `+ 1`。`delay_for_attempt(n)` 的语义是「第 n 次尝试之前等多久」，
// 而 attempt 是刚失败的那一次。用 `delay_for_attempt(attempt)` 等于把
// 第 1 次的「等 0」用在第一次重试上 → 固定退避的第一次重试完全不等，
// 指数退避的第 1、2 次重试也整体偏早一档。测试里之所以没暴露，是因为
// 断言只卡了「至少等过一次」的下界。
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
			// Wait before the NEXT attempt (attempt is the one that just failed)
			time.sleep(config.delay_for_attempt(attempt + 1))
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
