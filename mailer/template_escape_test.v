module mailer

// template_escape_test.v — HTML 转义的顺序与双重替换
//
// html_escape 先替换 & 再处理 < > " '，保证 `&lt;` 不会变成 `&amp;lt;`。
// 但 render_template_with 是「变量逐个 replace」，于是：
//   - 变量值里若含 `{{other}}`，后续轮次会再替换一次（模板注入）
//   - 先替换的占位符可能吃掉后替换变量名的一部分

fn test_html_escape_order() {
	assert html_escape('&<>"\'') == '&amp;&lt;&gt;&quot;&#39;'
	// 已经是实体的文本不该被再转一次（单个 & 会转，但 &amp; 只转一层）
	assert html_escape('&amp;') == '&amp;amp;'
}

fn test_unknown_placeholder_left_untouched() {
	out := render_template('<p>{{missing}}</p>', {
		'name': 'x'
	})
	assert out == '<p>{{missing}}</p>'
}

fn test_value_cannot_inject_html() {
	out := render_template('<p>{{name}}</p>', {
		'name': '<script>alert(1)</script>'
	})
	assert !out.contains('<script>')
	assert out.contains('&lt;script&gt;')
}

fn test_value_cannot_introduce_placeholder() {
	// 变量值里的 {{secret}} 不应被再次展开成 secret 的值
	out := render_template('<p>{{user}}</p>', {
		'user':   '{{secret}}'
		'secret': 'topsecret'
	})
	assert !out.contains('topsecret'), 'template injection: ${out}'
}

fn test_prefix_key_does_not_eat_longer_key() {
	// 数据里有 `a` 和 `ab` 时，替换 `{{a}}` 不能影响 `{{ab}}`
	out := render_template('{{a}}-{{ab}}', {
		'a':  'X'
		'ab': 'Y'
	})
	assert out == 'X-Y'
}

fn test_raw_renderer_keeps_entities() {
	out := render_template_raw('Total: {{n}} < 2', {
		'n': '1'
	})
	assert out == 'Total: 1 < 2'
}
