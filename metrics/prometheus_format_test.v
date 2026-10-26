module metrics

// prometheus_format_test.v — 导出格式必须是合法 Prometheus 文本
//
// 标签值来自用户数据（HTTP 路径、method、错误码等）。Prometheus 文本格式
// 要求标签值内的 `\` `"` `\n` 转义，否则一条带引号的请求路径就能让整个
// /metrics 端点解析失败 —— 而且失败是静默的，grafana 那边只会看到空图。

fn test_tag_value_quote_is_escaped() {
	mut r := new_in_memory_registry()
	c := r.counter('http_requests', {
		'route': '/say/"hi"'
	})
	c.increment()
	out := r.format_prometheus()
	assert !out.contains('route="/say/"hi""'), 'unescaped quote breaks the exposition format: ${out}'
	assert out.contains(r'route="/say/\"hi\""')
}

fn test_tag_value_backslash_is_escaped() {
	mut r := new_in_memory_registry()
	c := r.counter('disk_usage', {
		'path': r'C:\temp'
	})
	c.increment()
	out := r.format_prometheus()
	assert out.contains(r'path="C:\\temp"'), 'backslash must be escaped: ${out}'
}

fn test_tag_value_newline_is_escaped() {
	mut r := new_in_memory_registry()
	c := r.counter('errors', {
		'reason': 'line1\nline2'
	})
	c.increment()
	out := r.format_prometheus()
	assert !out.contains('line1\nline2'), 'raw newline breaks the exposition format'
	assert out.contains(r'line1\nline2')
}

fn test_each_sample_is_on_one_line() {
	mut r := new_in_memory_registry()
	r.counter('a', {
		'k': 'v\nw'
	}).increment()
	r.gauge('b', {}).set(1.0)
	out := r.format_prometheus()
	for line in out.split_into_lines() {
		if line.starts_with('a{') {
			assert line.contains(r'\n'), 'escaped newline must stay on the same line'
		}
	}
}
