module metrics

// prometheus_family_test.v — 指标族级别的注解只能出现一次
//
// 文本格式 0.0.4 里 `# HELP` / `# TYPE` 是「指标族」的注解。同名不同标签的
// 多条序列属于同一族，只能有一份注解。重复会让严格的解析器整份报错，
// 而 /metrics 抓取失败的观感只是「图上没数据」。
import strings

fn count_lines_starting_with(out string, prefix string) int {
	mut n := 0
	for line in out.split_into_lines() {
		if line.starts_with(prefix) {
			n++
		}
	}
	return n
}

fn test_counter_family_emits_single_help_and_type() {
	r := new_in_memory_registry()

	r.counter('http_requests', {
		'path':   '/a'
		'method': 'GET'
	}).increment()

	r.counter('http_requests', {
		'path':   '/b'
		'method': 'GET'
	}).increment_by(2)
	out := r.format_prometheus()
	assert count_lines_starting_with(out, '# HELP http_requests') == 1
	assert count_lines_starting_with(out, '# TYPE http_requests') == 1
	assert count_lines_starting_with(out, 'http_requests{') == 2
}

fn test_gauge_family_emits_single_help_and_type() {
	r := new_in_memory_registry()
	r.gauge('queue_depth', {
		'q': 'a'
	}).set(1)
	r.gauge('queue_depth', {
		'q': 'b'
	}).set(2)
	out := r.format_prometheus()
	assert count_lines_starting_with(out, '# HELP queue_depth') == 1
	assert count_lines_starting_with(out, '# TYPE queue_depth') == 1
}

fn test_timer_family_emits_single_help_and_type() {
	r := new_in_memory_registry()
	r.timer('latency', {
		'op': 'read'
	}).record(1)
	r.timer('latency', {
		'op': 'write'
	}).record(2)
	out := r.format_prometheus()
	assert count_lines_starting_with(out, '# HELP latency') == 1
	assert count_lines_starting_with(out, '# TYPE latency') == 1
	// 两条序列，各出 _count 与 _sum
	assert count_lines_starting_with(out, 'latency_count{') == 2
	assert count_lines_starting_with(out, 'latency_sum{') == 2
}

fn test_distinct_families_each_get_their_own_header() {
	r := new_in_memory_registry()
	r.counter('a_total', {}).increment()
	r.counter('b_total', {}).increment()
	out := r.format_prometheus()
	assert count_lines_starting_with(out, '# TYPE a_total') == 1
	assert count_lines_starting_with(out, '# TYPE b_total') == 1
}

fn test_sanitized_names_do_not_duplicate_type_lines() {
	// 'a b' 和 'a-b' 都会被规整成 'a_b'，属于同一族，只能有一份 TYPE。
	r := new_in_memory_registry()
	r.counter('a b', {}).increment()
	r.counter('a-b', {}).increment()
	out := r.format_prometheus()
	assert count_lines_starting_with(out, '# TYPE a_b') == 1
}

fn test_every_line_is_well_formed() {
	r := new_in_memory_registry()
	r.counter('c', {
		'k': 'v'
	}).increment()
	r.gauge('g', {
		'k': 'v'
	}).set(1)
	r.timer('t', {
		'k': 'v'
	}).record(5)
	out := r.format_prometheus()
	mut sb := strings.new_builder(16)
	for line in out.split_into_lines() {
		assert line.len > 0, 'exposition must not contain blank lines'
		if line.starts_with('#') {
			assert line.starts_with('# HELP ') || line.starts_with('# TYPE ')
		}
		sb.write_string(line)
	}
	assert sb.len > 0
}
