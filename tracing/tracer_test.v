module tracing

// tracer_test.v - Tests for the distributed tracing module (SubTask D2.4)
//
// Covers:
//   - Span creation, identity (trace_id/span_id), uniqueness
//   - Span duration, status, attributes, end() idempotency
//   - Parent-child nesting (automatic + explicit parent)
//   - current_span() lifecycle, list_spans(), clear()
//   - trace_operation success/error paths
//   - Deep nesting (A → B → C) parent chain
//   - Concurrency: parallel span creation with no races
//   - @[trace] comptime scanning
import time

// ============================================================
// Span Creation & Identity
// ============================================================

fn test_start_span_creates_named_span() {
	mut tracer := new_in_memory_tracer()
	span := tracer.start_span('op')

	assert span.name() == 'op'
}

fn test_span_has_trace_id() {
	mut tracer := new_in_memory_tracer()
	span := tracer.start_span('op')

	assert span.trace_id().len > 0
	assert span.trace_id().len == 32 // 128-bit hex
}

fn test_span_has_span_id() {
	mut tracer := new_in_memory_tracer()
	span := tracer.start_span('op')

	assert span.span_id().len > 0
	assert span.span_id().len == 16 // 64-bit hex
}

fn test_span_ids_are_unique() {
	mut tracer := new_in_memory_tracer()
	mut ids := map[string]bool{}
	for i in 0 .. 100 {
		span := tracer.start_span('op_${i}')
		ids[span.span_id()] = true
		tracer.finish_span(span)
	}
	// All 100 span ids must be distinct.
	assert ids.len == 100
}

fn test_trace_id_consistent_across_spans() {
	mut tracer := new_in_memory_tracer()
	s1 := tracer.start_span('a')
	s2 := tracer.start_span('b')
	tracer.finish_span(s2)
	s3 := tracer.start_span('c')
	tracer.finish_span(s3)
	tracer.finish_span(s1)

	assert s1.trace_id() == s2.trace_id()
	assert s2.trace_id() == s3.trace_id()
	assert tracer.trace_id_of() == s1.trace_id()
}

// ============================================================
// Span Duration
// ============================================================

fn test_span_duration_measures_elapsed_time() {
	mut tracer := new_in_memory_tracer()
	span := tracer.start_span('timed')

	time.sleep(50 * time.millisecond)
	tracer.finish_span(span)

	// Duration must be at least the time we slept.
	assert span.duration().nanoseconds() >= 50 * time.millisecond.nanoseconds()
}

fn test_span_duration_before_end_is_positive() {
	mut tracer := new_in_memory_tracer()
	span := tracer.start_span('open')

	time.sleep(5 * time.millisecond)
	// While open, duration keeps growing.
	assert span.duration().nanoseconds() > 0
	tracer.finish_span(span)
}

// ============================================================
// Span Status
// ============================================================

fn test_span_status_defaults_to_unset() {
	mut tracer := new_in_memory_tracer()
	span := tracer.start_span('op')

	assert span.status() == .unset
	tracer.finish_span(span)
}

fn test_span_status_can_be_set() {
	mut tracer := new_in_memory_tracer()
	span := tracer.start_span('op')

	span.set_status(.ok)
	assert span.status() == .ok

	span.set_status(.error)
	assert span.status() == .error

	tracer.finish_span(span)
}

// ============================================================
// Span Attributes
// ============================================================

fn test_span_attributes_set_and_get() {
	mut tracer := new_in_memory_tracer()
	span := tracer.start_span('op')

	span.set_attribute('user', 'alice')
	span.set_attribute('region', 'us-east-1')

	attrs := span.attributes()
	assert attrs['user'] == 'alice'
	assert attrs['region'] == 'us-east-1'

	tracer.finish_span(span)
}

fn test_span_attributes_returned_is_a_copy() {
	mut tracer := new_in_memory_tracer()
	span := tracer.start_span('op')
	span.set_attribute('k', 'v')
	tracer.finish_span(span)

	mut attrs := span.attributes()
	// Mutating the returned map must not affect the span.
	attrs['injected'] = 'bad'
	assert 'injected' !in span.attributes()
}

// ============================================================
// Span End
// ============================================================

fn test_span_end_sets_ended_flag() {
	mut tracer := new_in_memory_tracer()
	span := tracer.start_span('op')

	assert span.is_ended() == false
	span.end()
	assert span.is_ended() == true
}

fn test_span_end_is_idempotent() {
	mut tracer := new_in_memory_tracer()
	span := tracer.start_span('op')

	span.end()
	first_end := span.end_time()

	time.sleep(5 * time.millisecond)
	span.end() // second end must be a no-op
	second_end := span.end_time()

	assert second_end == first_end
}

// ============================================================
// Parent-Child Nesting
// ============================================================

fn test_child_span_inherits_parent_id() {
	mut tracer := new_in_memory_tracer()
	parent := tracer.start_span('parent')
	child := tracer.start_span('child')

	assert child.parent_span_id() == parent.span_id()
	assert child.trace_id() == parent.trace_id()

	tracer.finish_span(child)
	tracer.finish_span(parent)
}

fn test_start_span_with_parent_explicit() {
	mut tracer := new_in_memory_tracer()
	parent := tracer.start_span('parent')

	child := tracer.start_span_with_parent('child', parent)
	assert child.parent_span_id() == parent.span_id()
	assert child.trace_id() == parent.trace_id()

	tracer.finish_span(child)
	tracer.finish_span(parent)
}

fn test_nested_spans_parent_chain() {
	mut tracer := new_in_memory_tracer()
	a := tracer.start_span('A')
	b := tracer.start_span('B')
	c := tracer.start_span('C')

	// C's parent is B, B's parent is A, A is a root span.
	assert c.parent_span_id() == b.span_id()
	assert b.parent_span_id() == a.span_id()
	assert a.parent_span_id() == ''

	tracer.finish_span(c)
	tracer.finish_span(b)
	tracer.finish_span(a)
}

// ============================================================
// current_span / list_spans / clear
// ============================================================

fn test_current_span_lifecycle() {
	mut tracer := new_in_memory_tracer()

	// No active span initially.
	assert tracer.current_span() == none

	span := tracer.start_span('op')
	current := tracer.current_span() or {
		assert false
		return
	}
	assert current.span_id() == span.span_id()

	tracer.finish_span(span)
	assert tracer.current_span() == none
}

fn test_current_span_restores_parent_after_finish() {
	mut tracer := new_in_memory_tracer()
	parent := tracer.start_span('parent')
	child := tracer.start_span('child')

	// Active span is the child.
	cur := tracer.current_span() or { assert false; return }
	assert cur.span_id() == child.span_id()

	tracer.finish_span(child)
	// After finishing child, parent becomes active again.
	cur2 := tracer.current_span() or { assert false; return }
	assert cur2.span_id() == parent.span_id()

	tracer.finish_span(parent)
	assert tracer.current_span() == none
}

fn test_list_spans_returns_all_records() {
	mut tracer := new_in_memory_tracer()

	s1 := tracer.start_span('a')
	s2 := tracer.start_span('b')
	s3 := tracer.start_span('c')
	tracer.finish_span(s3)
	tracer.finish_span(s2)
	tracer.finish_span(s1)

	records := tracer.list_spans()
	assert records.len == 3

	mut names := map[string]bool{}
	for r in records {
		names[r.name] = true
	}
	assert names['a']
	assert names['b']
	assert names['c']
}

fn test_list_spans_record_fields_populated() {
	mut tracer := new_in_memory_tracer()
	span := tracer.start_span('op')
	span.set_attribute('k', 'v')
	span.set_status(.ok)
	tracer.finish_span(span)

	records := tracer.list_spans()
	assert records.len == 1
	r := records[0]
	assert r.name == 'op'
	assert r.trace_id.len == 32
	assert r.span_id.len == 16
	assert r.status == .ok
	assert r.attributes['k'] == 'v'
	assert r.duration.nanoseconds() >= 0
	assert r.end_time > r.start_time || r.duration.nanoseconds() >= 0
}

fn test_clear_empties_spans() {
	mut tracer := new_in_memory_tracer()
	s1 := tracer.start_span('a')
	tracer.finish_span(s1)
	assert tracer.list_spans().len == 1

	tracer.clear()
	assert tracer.list_spans().len == 0
	assert tracer.current_span() == none
}

// ============================================================
// trace_operation
// ============================================================

fn test_trace_operation_success() {
	mut tracer := new_in_memory_tracer()

	result := trace_operation[int](mut tracer, 'compute', fn () !int {
		return 42
	}) or {
		assert false
		return
	}
	assert result == 42

	records := tracer.list_spans()
	assert records.len == 1
	assert records[0].name == 'compute'
	assert records[0].status == .ok
	assert tracer.current_span() == none
}

fn test_trace_operation_error() {
	mut tracer := new_in_memory_tracer()

	_ = trace_operation[int](mut tracer, 'failing', fn () !int {
		return error('boom')
	}) or {
		// expected error path
		return
	}

	records := tracer.list_spans()
	assert records.len == 1
	assert records[0].name == 'failing'
	assert records[0].status == .error
	assert records[0].attributes['error'] == 'boom'
	assert tracer.current_span() == none
}

// nested_inner_helper runs an inner trace_operation. Takes a shared reference
// (matching the concurrent-test pattern) and uses unsafe internally to obtain
// a mutable binding, avoiding an immutable-capture notice in the caller.
fn nested_inner_helper(tracer &InMemoryTracer) !int {
	unsafe {
		mut t := tracer
		return trace_operation[int](mut t, 'inner', fn () !int {
			return 7
		})!
	}
}

fn test_trace_operation_nested() {
	mut tracer := new_in_memory_tracer()

	outer := trace_operation[int](mut tracer, 'outer', fn [tracer] () !int {
		return nested_inner_helper(tracer)! + 1
	}) or {
		assert false
		return
	}
	assert outer == 8

	records := tracer.list_spans()
	assert records.len == 2
	// The inner span's parent should be the outer span.
	mut outer_rec := SpanRecord{}
	mut inner_rec := SpanRecord{}
	for r in records {
		if r.name == 'outer' {
			outer_rec = r
		} else if r.name == 'inner' {
			inner_rec = r
		}
	}
	assert inner_rec.parent_span_id == outer_rec.span_id
	assert outer_rec.parent_span_id == ''
}

// ============================================================
// TraceContext
// ============================================================

fn test_trace_context_from_span() {
	mut tracer := new_in_memory_tracer()
	span := tracer.start_span('op')
	ctx := TraceContext{
		trace_id: span.trace_id()
		span_id: span.span_id()
		parent_span_id: span.parent_span_id()
	}

	assert ctx.trace_id == span.trace_id()
	assert ctx.span_id == span.span_id()
	assert ctx.parent_span_id == span.parent_span_id()
	assert ctx.is_valid() == true

	empty := TraceContext{}
	assert empty.is_valid() == false

	tracer.finish_span(span)
}

// ============================================================
// Concurrency
// ============================================================

fn test_concurrent_span_creation_no_race() {
	mut tracer := new_in_memory_tracer()

	num_workers := 20
	iterations := 50
	done := chan bool{cap: num_workers}

	for w in 0 .. num_workers {
		spawn fn (done chan bool, tracer &InMemoryTracer, w int, iterations int) {
			for i in 0 .. iterations {
				unsafe {
					mut t := tracer
					span := t.start_span('worker_${w}_${i}')
					t.finish_span(span)
				}
			}
			done <- true
		}(done, tracer, w, iterations)
	}
	for _ in 0 .. num_workers {
		_ := <-done
	}

	// Every span created by every worker must be recorded exactly once.
	records := tracer.list_spans()
	assert records.len == num_workers * iterations
	// All span ids must be unique.
	mut ids := map[string]bool{}
	for r in records {
		assert ids[r.span_id] == false
		ids[r.span_id] = true
	}
}

fn test_concurrent_span_attribute_updates() {
	mut tracer := new_in_memory_tracer()
	span := tracer.start_span('shared')

	num_workers := 10
	done := chan bool{cap: num_workers}

	for w in 0 .. num_workers {
		spawn fn (done chan bool, span Span, w int) {
			for i in 0 .. 100 {
				span.set_attribute('w${w}', '${i}')
			}
			done <- true
		}(done, span, w)
	}
	for _ in 0 .. num_workers {
		_ := <-done
	}

	attrs := span.attributes()
	// Each worker's last write must be present.
	for w in 0 .. num_workers {
		assert 'w${w}' in attrs
	}
	tracer.finish_span(span)
}

// ============================================================
// @[trace] Comptime Scanning (SubTask D2.3)
// ============================================================

// TracedService is a test fixture with @[trace]-annotated methods.
struct TracedService {
	tracer &InMemoryTracer = unsafe { nil }
}

@[trace]
fn (s &TracedService) simple_op() int {
	return 42
}

@[trace: 'custom_span_name']
fn (s &TracedService) named_op() int {
	return 100
}

fn not_traced(s &TracedService) int {
	return 1
}

fn test_extract_trace_methods_detects_annotated_methods() {
	methods := extract_trace_methods[TracedService]()

	// simple_op and named_op are traced; not_traced is not.
	assert methods.len == 2

	mut by_name := map[string]TraceMethodInfo{}
	for m in methods {
		by_name[m.method_name] = m
	}
	assert 'simple_op' in by_name
	assert 'named_op' in by_name
	assert 'not_traced' !in by_name
}

fn test_extract_trace_methods_uses_method_name_when_no_arg() {
	methods := extract_trace_methods[TracedService]()

	for m in methods {
		if m.method_name == 'simple_op' {
			// No explicit span name → defaults to method name.
			assert m.span_name == 'simple_op'
		}
	}
}

fn test_extract_trace_methods_uses_explicit_span_name() {
	methods := extract_trace_methods[TracedService]()

	for m in methods {
		if m.method_name == 'named_op' {
			// @[trace: 'custom_span_name'] → span_name = 'custom_span_name'.
			assert m.span_name == 'custom_span_name'
		}
	}
}

fn test_is_trace_annotated() {
	assert is_trace_annotated[TracedService]() == true

	// A struct with no @[trace] methods is not annotated.
	assert is_trace_annotated[PlainService]() == false
}

struct PlainService {}

fn test_parse_trace_attr() {
	// Empty → no span name.
	a := parse_trace_attr('')
	assert a.span_name == ''

	// Bare name.
	b := parse_trace_attr('my_op')
	assert b.span_name == 'my_op'

	// Double-quoted name.
	c := parse_trace_attr('"my_op"')
	assert c.span_name == 'my_op'

	// Single-quoted name with surrounding spaces.
	d := parse_trace_attr("  'my_op'  ")
	assert d.span_name == 'my_op'
}

// ============================================================
// Tracer isolation
// ============================================================

fn test_tracers_have_distinct_trace_ids() {
	mut t1 := new_in_memory_tracer()
	mut t2 := new_in_memory_tracer()

	assert t1.trace_id_of() != t2.trace_id_of()

	s1 := t1.start_span('a')
	s2 := t2.start_span('b')
	assert s1.trace_id() != s2.trace_id()

	t1.finish_span(s1)
	t2.finish_span(s2)
}

fn test_tracer_with_explicit_trace_id() {
	mut tracer := new_in_memory_tracer_with_trace_id('my-trace-123')
	assert tracer.trace_id_of() == 'my-trace-123'

	span := tracer.start_span('op')
	assert span.trace_id() == 'my-trace-123'
	tracer.finish_span(span)
}
