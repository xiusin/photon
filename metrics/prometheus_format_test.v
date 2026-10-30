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

// ── 同名不同 tags 的系列顺序 ──

fn test_prometheus_series_with_same_name_are_ordered() {
	mut registry := new_in_memory_registry()
	// 插入顺序刻意打乱：c, a, b

	registry.counter('req', {
		'path': '/c'
	}).increment()

	registry.counter('req', {
		'path': '/a'
	}).increment()

	registry.counter('req', {
		'path': '/b'
	}).increment()

	out := registry.format_prometheus()
	a := out.index('req{path="/a"}') or { -1 }
	b := out.index('req{path="/b"}') or { -1 }
	c := out.index('req{path="/c"}') or { -1 }
	assert a > -1 && b > -1 && c > -1
	// 只按名字排序时三者相等，顺序就退化成 map 遍历顺序
	assert a < b
	assert b < c
}

fn test_prometheus_output_is_repeatable() {
	mut registry := new_in_memory_registry()
	for p in ['/z', '/a', '/m', '/b'] {
		registry.counter('req', {
			'path': p
		}).increment()
	}
	first := registry.format_prometheus()
	for _ in 0 .. 5 {
		assert registry.format_prometheus() == first
	}
}

// 指标名本身也必须符合 Prometheus 的名字语法（[a-zA-Z_:][a-zA-Z0-9_:]*）。
// 名字里出现空格/花括号会让整条 exposition 解析失败，而 /metrics 出错
// 在监控侧的表现只是「没数据」—— 没人看得到异常。
fn test_invalid_metric_name_is_sanitized() {
	reg := new_in_memory_registry()
	c := reg.counter('my metric{broken}', {})
	c.increment()
	out := reg.format_prometheus()
	for line in out.split_into_lines() {
		if line.starts_with('#') || line.trim_space().len == 0 {
			continue
		}
		name := line.split(' ')[0]
		// 逐字符白名单：名字段（标签前）只允许 [a-zA-Z0-9_:]
		mut name_part := name
		if brace := name.index('{') {
			name_part = name[..brace]
		}
		for ch in name_part {
			is_letter := (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`)
			is_digit := ch >= `0` && ch <= `9`
			is_sep := ch == `_` || ch == `:`
			assert is_letter || is_digit || is_sep, 'invalid character in metric name "${name_part}": ${line}'
		}
	}
}

fn test_sanitize_metric_name() {
	assert sanitize_metric_name('http_requests_total') == 'http_requests_total'
	assert sanitize_metric_name('my metric') == 'my_metric'
	assert sanitize_metric_name('job{done}') == 'job_done_'
	assert sanitize_metric_name('') == '_'
	// 首字符不能是数字
	assert sanitize_metric_name('1st') == '_st'
	assert sanitize_metric_name('ns:metric') == 'ns:metric'
}
