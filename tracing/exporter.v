module tracing

// exporter.v - Span Exporter Interface (OpenTelemetry-inspired)
//
// Provides a pluggable export mechanism for spans. Users can implement
// the SpanExporter interface to send spans to OpenTelemetry, Zipkin,
// Jaeger, or any other tracing backend.
//
// Built-in exporters:
//   - ConsoleExporter: prints spans to stderr (for development/debugging)
//
// Usage:
//   tracer := tracing.new_in_memory_tracer()
//   tracer.add_exporter(tracing.new_console_exporter())
//   // ... spans are created and finished ...
//   tracer.export_all()!  // sends all recorded spans to exporters
//
// Auto-export mode (future enhancement):
//   tracer.enable_auto_export()  // exports spans on every finish_span()

// SpanExporter is the interface for exporting spans to external systems.
// Implementations should be thread-safe if used with auto-export mode.
pub interface SpanExporter {
	// export sends a batch of span records to the backend.
	// Returns an error if the export fails (network issue, etc.).
	export(spans []SpanRecord) !
	// name returns a human-readable identifier for this exporter.
	name() string
}

// ConsoleExporter prints span records to stderr in a human-readable format.
// Useful for development and debugging.
pub struct ConsoleExporter {
pub:
	name_str string = 'console'
}

// new_console_exporter creates a ConsoleExporter.
pub fn new_console_exporter() &ConsoleExporter {
	return &ConsoleExporter{}
}

// name returns the exporter name.
pub fn (e &ConsoleExporter) name() string {
	return e.name_str
}

// export prints each span to stderr.
pub fn (e &ConsoleExporter) export(spans []SpanRecord) ! {
	if spans.len == 0 {
		return
	}
	eprintln('── Trace Export (${spans.len} spans) ──')
	for span in spans {
		status_str := match span.status {
			.ok { 'OK' }
			.error { 'ERROR' }
			.unset { 'UNSET' }
		}

		eprintln('  [${span.trace_id}] ${span.name} (${span.span_id})')
		eprintln('    parent: ${span.parent_span_id}')
		eprintln('    status: ${status_str}')
		eprintln('    duration: ${span.duration}')
		if span.attributes.len > 0 {
			eprintln('    attrs: ${span.attributes}')
		}
	}
	eprintln('── End Trace ──')
}

// ── Exporter-aware InMemoryTracer extensions ──

// add_exporter registers a span exporter with the tracer.
// Exporters receive spans when export_all() is called.
pub fn (mut t InMemoryTracer) add_exporter(exporter SpanExporter) {
	t.mu.@lock()
	t.exporters << exporter
	t.mu.unlock()
}

// exporter_names returns the names of the registered exporters, in order.
// The list itself is private precisely so that registration and iteration are
// both serialized by the tracer mutex; this is the read-only accessor.
pub fn (mut t InMemoryTracer) exporter_names() []string {
	t.mu.rlock()
	defer { t.mu.runlock() }
	mut names := []string{cap: t.exporters.len}
	for e in t.exporters {
		names << e.name()
	}
	return names
}

// remove_exporters clears all registered exporters.
pub fn (mut t InMemoryTracer) remove_exporters() {
	t.mu.@lock()
	t.exporters = []
	t.mu.unlock()
}

// export_all sends all recorded spans to every registered exporter.
// Called at the end of a request or when the tracer is shut down.
pub fn (mut t InMemoryTracer) export_all() ! {
	t.mu.@rlock()
	if t.exporters.len == 0 {
		t.mu.runlock()
		return
	}
	// 就地生成 SpanRecord，别再调一次 list_spans_locked()：那个函数自己
	// 又 @rlock 一次，而 V 的 RwLock 不保证读锁可重入（写者优先的实现上
	// 第二次 rlock 会直接挂住）。
	records := t.records_locked()
	exporters := t.exporters.clone()
	t.mu.runlock()

	// Try each exporter; accumulate errors but don't fail on first
	mut errors := []string{}
	for exporter in exporters {
		exporter.export(records) or { errors << '${exporter.name()}: ${err}' }
	}
	if errors.len > 0 {
		return error(errors.join('; '))
	}
}

// export_and_clear exports all spans, then clears the tracer.
// Useful at the end of a request lifecycle to ship spans and free memory.
pub fn (mut t InMemoryTracer) export_and_clear() ! {
	t.export_all()!
	t.clear()
}

// records_locked returns span records without acquiring the tracer lock.
// Caller must hold at least a read lock.
fn (mut t InMemoryTracer) records_locked() []SpanRecord {
	mut records := []SpanRecord{cap: t.spans.len}
	for span in t.spans {
		records << SpanRecord{
			trace_id:       span.trace_id_str
			span_id:        span.span_id_str
			parent_span_id: span.parent_id
			name:           span.name_str
			start_time:     span.start_time()
			end_time:       span.end_time()
			duration:       span.duration()
			status:         span.status()
			attributes:     span.attributes()
		}
	}
	return records
}
