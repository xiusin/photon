// exporter_concurrency_test.v — 导出器注册与导出时的一致性
//
// 两个缺陷：
//   1. exporters 挂在 pub mut 段，任何人可以绕过 add_exporter 直接改数组；
//   2. export_all() 持着读锁又调一次自己会 @rlock 的函数 —— 读锁不可重入。
module tracing

struct CountingExporter {
	name_str string
}

fn (e &CountingExporter) name() string {
	return e.name_str
}

// 只读接收者，且不记录状态：SpanExporter.export 在接口里是不可变的，
// 用 mut 接收者会直接「implements 不匹配」。
fn (e &CountingExporter) export(spans []SpanRecord) ! {
	_ = e
	_ = spans
}

fn test_export_all_collects_records_without_relocking() {
	mut tracer := new_in_memory_tracer()
	tracer.add_exporter(&CountingExporter{
		name_str: 'counting'
	})

	for i in 0 .. 3 {
		s := tracer.start_span('op_${i}')
		s.end()
		tracer.finish_span(s)
	}

	// 读锁重入会在这里挂住（表现为用例超时），而 export_all 必须返回 ok
	tracer.export_all()!
	assert tracer.list_spans().len == 3
}

fn test_exporter_names_reflects_registration() {
	mut tracer := new_in_memory_tracer()
	assert tracer.exporter_names().len == 0

	tracer.add_exporter(&CountingExporter{
		name_str: 'a'
	})
	tracer.add_exporter(&CountingExporter{
		name_str: 'b'
	})
	assert tracer.exporter_names() == ['a', 'b']

	tracer.remove_exporters()
	assert tracer.exporter_names().len == 0
}

fn test_export_all_without_exporters_is_noop() {
	mut tracer := new_in_memory_tracer()
	s := tracer.start_span('noop')
	s.end()
	tracer.finish_span(s)
	tracer.export_all()!
	assert tracer.list_spans().len == 1
}

fn test_finish_span_does_not_pop_foreign_stack_entry() {
	mut tracer := new_in_memory_tracer()
	outer := tracer.start_span('outer')
	inner := tracer.start_span('inner')

	// finish 一个不在栈顶的 span：栈里那一条不能被它摘掉
	tracer.finish_span(outer)
	assert tracer.list_spans().len == 2
	top := tracer.current_span() or { panic('finishing a non-top span must not empty the stack') }
	assert top.span_id() == inner.span_id()

	tracer.finish_span(inner)
	assert tracer.current_span() == none
}
