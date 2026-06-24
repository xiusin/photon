module tracing

// tracer.v - Distributed Tracing (Spring Cloud Sleuth / OpenTelemetry-inspired)
//
// Provides a tracing abstraction with three core types:
//   - TraceContext: carries trace identity across boundaries
//   - Span:         a unit of work within a trace (start/end/status/attributes)
//   - Tracer:       creates and manages spans, records the span chain
//
// The in-memory implementation (InMemoryTracer) is thread-safe:
//   - The tracer uses sync.RwMutex: span creation/finishing uses write-lock,
//     current_span()/list_spans() use read-lock.
//   - Each span has its own sync.Mutex, so concurrent attribute/status updates
//     on different spans never contend.
//
// @[trace] annotation support (SubTask D2.3):
//   Methods annotated with @[trace] are discovered at compile time via
//   `extract_trace_methods[T]()`. The `trace_operation[T]()` helper wraps a
//   function call in a span, automatically opening/closing it and recording
//   status (ok/error) — this is the "auto-open span" mechanism.
//
// All span identity (trace_id/span_id) is generated with sufficient entropy
// (32 hex chars for trace_id, 16 for span_id) to guarantee uniqueness.
//
// Thread-safety notes:
//   - V's rand module uses a process-wide PRNG that is NOT thread-safe.
//     We use C.arc4random() instead (thread-safe CSPRNG).
//   - V's time.now() calls C.localtime() which returns a pointer to a static
//     buffer — NOT thread-safe. We store time as i64 ticks (from time.ticks(),
//     which uses mach_absolute_time on macOS / clock_gettime on Linux) and
//     i64 unix seconds (from C.time(0), which returns time_t by value).
//     Conversion to time.Time happens lazily in start_time()/end_time(),
//     which are only called from the main thread (e.g. list_spans).
import sync
import time
import strings

// C function declarations for thread-safe primitives.
fn C.arc4random() u32
fn C.time(t voidptr) i64

// thread_safe_now_ticks returns monotonic milliseconds from time.ticks().
// On macOS: uses mach_absolute_time() — thread-safe.
// On Linux: uses clock_gettime(CLOCK_MONOTONIC) — thread-safe.
fn thread_safe_now_ticks() i64 {
	return time.ticks()
}

// thread_safe_unix returns Unix seconds from C.time(0), which is thread-safe
// (returns time_t by value, unlike C.localtime() which returns a static buffer).
fn thread_safe_unix() i64 {
	return C.time(unsafe { nil })
}

// ticks_to_duration converts a tick difference (milliseconds) to time.Duration
// (nanoseconds).
fn ticks_to_duration(ticks_diff i64) time.Duration {
	return time.Duration(ticks_diff * 1_000_000)
}

// unix_to_time converts Unix seconds to time.Time. This calls time.unix()
// internally, which uses C.localtime() — only safe to call from the main
// thread (not from goroutines).
pub fn unix_to_time(unix_secs i64) time.Time {
	if unix_secs == 0 {
		return time.Time{}
	}
	return time.unix(int(unix_secs))
}

// ============================================================
// Span Status
// ============================================================

// SpanStatus represents the outcome of a span.
pub enum SpanStatus {
	unset // default, status not yet recorded
	ok    // operation completed successfully
	error // operation failed
}

// ============================================================
// Interfaces (SubTask D2.1)
// ============================================================

// Span represents a unit of work in a trace.
//
// All methods are callable through a shared reference (&InMemorySpan): the
// concrete implementation guards mutable state with an internal mutex, so
// callers do not need a `mut` binding to update status/attributes/end the
// span. This mirrors the thread-safe accessor pattern used by metrics.Counter.
pub interface Span {
	span_id() string
	trace_id() string
	parent_span_id() string
	name() string
	start_time() time.Time
	end_time() time.Time
	duration() time.Duration
	status() SpanStatus
	attributes() map[string]string
	is_ended() bool
	set_status(status SpanStatus)
	set_attribute(key string, value string)
	end()
}

// TraceContext carries trace information across boundaries (e.g. into a
// downstream HTTP call). It is a snapshot of a Span's identity.
pub struct TraceContext {
pub:
	trace_id       string
	span_id        string
	parent_span_id string
}

// is_valid returns true when the context carries a non-empty trace and span id.
pub fn (ctx TraceContext) is_valid() bool {
	return ctx.trace_id.len > 0 && ctx.span_id.len > 0
}

// Tracer creates and manages spans. Implementations record the full span
// chain so it can be inspected (e.g. by tests or an exporter).
//
// Note: start_span/finish_span/start_span_with_parent use &InMemorySpan
// (concrete pointer) instead of Span (interface). V's interface dispatch
// in goroutines causes GC crashes because the GC scans interface fat
// pointers on thread stacks incorrectly. current_span() returns ?Span
// because it's only called from the main thread (safe for interface use),
// and ?&InMemorySpan has a V compiler codegen bug.
pub interface Tracer {
	current_span() ?Span
	list_spans() []SpanRecord
mut:
	start_span(name string) &InMemorySpan
	start_span_with_parent(name string, parent &InMemorySpan) &InMemorySpan
	finish_span(span &InMemorySpan)
	clear()
}

// SpanRecord is an immutable snapshot of a span, returned by list_spans().
pub struct SpanRecord {
pub:
	trace_id       string
	span_id        string
	parent_span_id string
	name           string
	start_time     time.Time
	end_time       time.Time
	duration       time.Duration
	status         SpanStatus
	attributes     map[string]string
}

// ============================================================
// InMemorySpan (SubTask D2.2)
// ============================================================

// InMemorySpan is a thread-safe Span backed by a per-span sync.Mutex.
//
// Time is stored as i64 fields instead of time.Time, because V's
// time.now() calls C.localtime() which is NOT thread-safe (returns a
// pointer to a static buffer). Instead:
//   - started_ticks / ended_ticks: monotonic ms from time.ticks() (thread-safe)
//   - started_unix / ended_unix: Unix seconds from C.time(0) (thread-safe)
// Conversion to time.Time happens lazily in start_time()/end_time(),
// which are only called from the main thread (e.g. list_spans).
pub struct InMemorySpan {
pub:
	trace_id_str   string
	span_id_str    string
	parent_id      string
	name_str       string
	started_ticks  i64
	started_unix   i64
mut:
	mu           sync.Mutex
	ended_ticks  i64
	ended_unix   i64
	status_val   SpanStatus = .unset
	attrs        map[string]string
	ended        bool
}

// span_id returns this span's unique identifier.
pub fn (s &InMemorySpan) span_id() string {
	return s.span_id_str
}

// trace_id returns the trace identifier shared by all spans in the chain.
pub fn (s &InMemorySpan) trace_id() string {
	return s.trace_id_str
}

// parent_span_id returns the parent span's id, or '' for a root span.
pub fn (s &InMemorySpan) parent_span_id() string {
	return s.parent_id
}

// name returns the human-readable operation name.
pub fn (s &InMemorySpan) name() string {
	return s.name_str
}

// start_time returns when the span was started.
// Converts from stored Unix seconds to time.Time. This calls time.unix()
// internally (which uses C.localtime) — only safe from the main thread.
pub fn (s &InMemorySpan) start_time() time.Time {
	return unix_to_time(s.started_unix)
}

// end_time returns when the span was ended (zero Time if not yet ended).
// Converts from stored Unix seconds to time.Time. Only safe from main thread.
pub fn (s &InMemorySpan) end_time() time.Time {
	unsafe {
		s.mu.@lock()
	}
	v := s.ended_unix
	unsafe {
		s.mu.unlock()
	}
	return unix_to_time(v)
}

// duration returns the elapsed time of the span. If the span is still open,
// returns the time since start; otherwise returns end_time - start_time.
// Uses thread-safe time.ticks() for current time (not time.now()).
pub fn (s &InMemorySpan) duration() time.Duration {
	unsafe {
		s.mu.@lock()
	}
	is_ended := s.ended
	ended := s.ended_ticks
	unsafe {
		s.mu.unlock()
	}
	if is_ended {
		return ticks_to_duration(ended - s.started_ticks)
	}
	return ticks_to_duration(thread_safe_now_ticks() - s.started_ticks)
}

// status returns the current span status.
pub fn (s &InMemorySpan) status() SpanStatus {
	unsafe {
		s.mu.@lock()
	}
	v := s.status_val
	unsafe {
		s.mu.unlock()
	}
	return v
}

// set_status records the outcome of the span.
pub fn (s &InMemorySpan) set_status(status SpanStatus) {
	unsafe {
		s.mu.@lock()
		s.status_val = status
		s.mu.unlock()
	}
}

// set_attribute attaches a key/value attribute to the span.
pub fn (s &InMemorySpan) set_attribute(key string, value string) {
	unsafe {
		s.mu.@lock()
		s.attrs[key] = value
		s.mu.unlock()
	}
}

// attributes returns a copy of the span's attributes.
pub fn (s &InMemorySpan) attributes() map[string]string {
	unsafe {
		s.mu.@lock()
	}
	c := s.attrs.clone()
	unsafe {
		s.mu.unlock()
	}
	return c
}

// end marks the span as completed and records the end timestamp.
// Calling end() more than once is a no-op.
// Uses thread_safe_now_ticks() + thread_safe_unix() instead of time.now().
pub fn (s &InMemorySpan) end() {
	unsafe {
		s.mu.@lock()
		if !s.ended {
			s.ended_ticks = thread_safe_now_ticks()
			s.ended_unix = thread_safe_unix()
			s.ended = true
		}
		s.mu.unlock()
	}
}

// is_ended returns true if end() has been called on this span.
pub fn (s &InMemorySpan) is_ended() bool {
	unsafe {
		s.mu.@lock()
	}
	v := s.ended
	unsafe {
		s.mu.unlock()
	}
	return v
}

// to_context builds a TraceContext snapshot from this span's identity.
pub fn (s &InMemorySpan) to_context() TraceContext {
	return TraceContext{
		trace_id: s.trace_id_str
		span_id: s.span_id_str
		parent_span_id: s.parent_id
	}
}

// ============================================================
// InMemoryTracer (SubTask D2.2)
// ============================================================

// InMemoryTracer is a thread-safe Tracer that records every span in memory.
//
// It maintains two collections:
//   - spans: the full history of every span created (for list_spans()).
//   - stack: the active span nesting stack (LIFO). start_span pushes,
//     finish_span pops. current_span() returns the top.
//
// All spans created by one tracer share the same trace_id, forming a single
// trace. start_span_with_parent() can join an existing trace from another
// tracer by inheriting the parent's trace_id.
pub struct InMemoryTracer {
mut:
	mu       sync.RwMutex
	spans    []&InMemorySpan
	stack    []&InMemorySpan
	trace_id string
}

// new_in_memory_tracer creates a tracer with a fresh trace id.
pub fn new_in_memory_tracer() &InMemoryTracer {
	return &InMemoryTracer{
		trace_id: generate_trace_id()
	}
}

// new_in_memory_tracer_with_trace_id creates a tracer bound to an explicit
// trace id. Useful for continuing a trace received from an upstream caller.
pub fn new_in_memory_tracer_with_trace_id(trace_id string) &InMemoryTracer {
	return &InMemoryTracer{
		trace_id: trace_id
	}
}

// trace_id_of returns the trace id this tracer assigns to new spans.
pub fn (mut t InMemoryTracer) trace_id_of() string {
	return t.trace_id
}

// start_span begins a new span. If there is an active span, it becomes the
// parent (enabling automatic nesting); otherwise this is a root span.
//
// Thread-safety: All operations (parent lookup, span ID generation, struct
// allocation, array append) are performed UNDER the write lock. This
// serializes all work across goroutines, preventing:
//   - GC concurrent-allocation races (Boehm GC thread_suspend failures)
//   - PRNG state corruption (C.arc4random is per-thread safe anyway)
//   - time.now() localtime() static buffer races (avoided by using
//     thread-safe time.ticks() + C.time(0))
pub fn (mut t InMemoryTracer) start_span(name string) &InMemorySpan {
	t.mu.@lock()

	mut parent_id := ''
	if t.stack.len > 0 {
		parent_id = t.stack[t.stack.len - 1].span_id_str
	}

	span := &InMemorySpan{
		trace_id_str:  t.trace_id
		span_id_str:   generate_span_id()
		parent_id:     parent_id
		name_str:      name
		started_ticks: thread_safe_now_ticks()
		started_unix:  thread_safe_unix()
	}

	t.spans << span
	t.stack << span
	t.mu.unlock()

	return span
}

// start_span_with_parent begins a new span as a child of an explicit parent.
// The new span inherits the parent's trace_id, allowing traces to cross
// tracer boundaries.
//
// Thread-safety: same as start_span — all work under the write lock.
pub fn (mut t InMemoryTracer) start_span_with_parent(name string, parent &InMemorySpan) &InMemorySpan {
	t.mu.@lock()

	span := &InMemorySpan{
		trace_id_str:  parent.trace_id_str
		span_id_str:   generate_span_id()
		parent_id:     parent.span_id_str
		name_str:      name
		started_ticks: thread_safe_now_ticks()
		started_unix:  thread_safe_unix()
		attrs:         map[string]string{}
	}

	t.spans << span
	t.stack << span
	t.mu.unlock()

	return span
}

// current_span returns the active (top-of-stack) span, or none if no span
// is open.
pub fn (mut t InMemoryTracer) current_span() ?Span {
	t.mu.@rlock()
	if t.stack.len > 0 {
		top := t.stack[t.stack.len - 1]
		t.mu.runlock()
		return top
	}
	t.mu.runlock()
	return none
}

// finish_span ends the given span and pops the active span stack. Spans
// should be finished in LIFO (reverse-start) order to keep the nesting
// stack consistent.
pub fn (mut t InMemoryTracer) finish_span(span &InMemorySpan) {
	span.end()
	t.mu.@lock()
	if t.stack.len > 0 {
		t.stack.delete(t.stack.len - 1)
	}
	t.mu.unlock()
}

// list_spans returns a snapshot of every span recorded by this tracer
// (including finished spans), as immutable SpanRecords.
pub fn (mut t InMemoryTracer) list_spans() []SpanRecord {
	t.mu.@rlock()
	mut records := []SpanRecord{cap: t.spans.len}
	for span in t.spans {
		records << SpanRecord{
			trace_id: span.trace_id_str
			span_id: span.span_id_str
			parent_span_id: span.parent_id
			name: span.name_str
			start_time: span.start_time()
			end_time: span.end_time()
			duration: span.duration()
			status: span.status()
			attributes: span.attributes()
		}
	}
	t.mu.runlock()
	return records
}

// clear resets the tracer: drops all recorded spans and the active stack.
// The trace id is preserved so subsequent spans still belong to the same trace.
pub fn (mut t InMemoryTracer) clear() {
	t.mu.@lock()
	t.spans = []
	t.stack = []
	t.mu.unlock()
}

// ============================================================
// ID Generation
// ============================================================

// hex_charset is the lowercase hexadecimal alphabet used for trace/span ids.
const hex_charset = '0123456789abcdef'

// generate_trace_id produces a 32-char lowercase hex trace id (128 bits).
fn generate_trace_id() string {
	return random_hex(32)
}

// generate_span_id produces a 16-char lowercase hex span id (64 bits).
fn generate_span_id() string {
	return random_hex(16)
}

// random_hex builds a random hex string of the given length.
//
// Thread-safety: Uses C.arc4random() instead of V's rand.intn(). V's rand
// module uses a process-wide PRNG that is NOT thread-safe — concurrent calls
// corrupt the PRNG state and segfault in rand__PRNG_u32n. C.arc4random() is
// thread-safe (uses a per-thread CSPRNG on macOS/BSD, getrandom on Linux)
// and requires no mutex.
fn random_hex(length int) string {
	mut sb := strings.new_builder(length)
	for _ in 0 .. length {
		r := C.arc4random()
		sb.write_byte(hex_charset[int(r & 0xF)])
	}
	return sb.str()
}

// ============================================================
// @[trace] Annotation Support (SubTask D2.3)
// ============================================================
//
// Spring equivalent: @Trace / Sleuth's automatic span creation.
//
// V comptime note: method-level attributes are inspected via
// `method.attrs` (a []string) inside `$for method in T.methods`. Each entry
// is the raw attribute text: 'trace', 'trace:op_name', or 'trace("op_name")'.
// Struct-level attributes use the `$for attr in T.attributes` form with
// VAttribute fields (.name/.has_arg/.arg) — not needed here since @[trace]
// is applied to methods.

// TraceAttribute holds parsed attributes from @[trace].
pub struct TraceAttribute {
pub mut:
	span_name string // explicit span name; '' means use the method name
}

// parse_trace_attr parses the @[trace] attribute string into a TraceAttribute.
// Accepted forms:
//   ''                       → no explicit name (use method name)
//   'op_name'                → span name = 'op_name'
//   '"op_name"' / "'op_name'" → quoted name, quotes stripped
pub fn parse_trace_attr(attr string) TraceAttribute {
	mut ta := TraceAttribute{}
	cleaned := attr.trim_space().trim('"').trim("'").trim_space()
	if cleaned.len > 0 {
		ta.span_name = cleaned
	}
	return ta
}

// TraceMethodInfo describes a method annotated with @[trace].
pub struct TraceMethodInfo {
pub:
	method_name string
	span_name   string // resolved span name (explicit or method name)
	attrs       []string
}

// extract_trace_methods scans type T at compile time for methods annotated
// with @[trace]. Returns one TraceMethodInfo per traced method.
//
// This is a pure comptime scan — zero runtime reflection. The resolved
// span_name is the explicit argument (if any) or the method name itself.
//
// Usage:
//   methods := tracing.extract_trace_methods[MyService]()
pub fn extract_trace_methods[T]() []TraceMethodInfo {
	mut methods := []TraceMethodInfo{}
	$for method in T.methods {
		mut has_trace := false
		mut span_name := method.name
		for attr in method.attrs {
			if attr == 'trace' {
				has_trace = true
			} else if attr.starts_with('trace:') {
				has_trace = true
				arg := attr['trace:'.len..]
				parsed := parse_trace_attr(arg)
				if parsed.span_name.len > 0 {
					span_name = parsed.span_name
				}
			} else if attr.starts_with('trace(') {
				has_trace = true
				// Extract content between 'trace(' and the closing ')'.
				end_idx := attr.last_index(')') or { attr.len }
				inner := attr[6..end_idx]
				parsed := parse_trace_attr(inner)
				if parsed.span_name.len > 0 {
					span_name = parsed.span_name
				}
			}
		}
		if has_trace {
			methods << TraceMethodInfo{
				method_name: method.name
				span_name: span_name
				attrs: method.attrs.clone()
			}
		}
	}
	return methods
}

// is_trace_annotated returns true if type T has any @[trace] methods.
pub fn is_trace_annotated[T]() bool {
	return extract_trace_methods[T]().len > 0
}

// ============================================================
// trace_operation — auto-open span helper (SubTask D2.3)
// ============================================================

// trace_operation runs `operation` inside a span managed by `tracer`.
//
// It opens a span before the operation, sets status to .ok on success or
// .error on failure (recording the error message as an attribute), and
// finishes the span on exit (including the error path). This is the
// runtime counterpart to the @[trace] annotation: methods discovered by
// extract_trace_methods can be wrapped with this helper to get automatic
// span lifecycle management.
//
// Usage:
//   result := tracing.trace_operation[int](mut tracer, 'compute', fn () !int {
//       return do_work()
//   })!
pub fn trace_operation[T](mut tracer InMemoryTracer, name string, operation fn () !T) !T {
	span := tracer.start_span(name)
	defer {
		tracer.finish_span(span)
	}

	result := operation() or {
		span.set_status(.error)
		span.set_attribute('error', err.msg())
		return err
	}

	span.set_status(.ok)
	return result
}
