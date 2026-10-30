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

// ── 地址头注入 / Bcc 日志脱敏 ──

fn test_address_str_strips_header_injection() {
	// 换行能把额外的头（Bcc、Content-Type）塞进 SMTP 报文
	a := Address{
		email: 'a@b.com\r\nBcc: victim@evil.com'
	}
	s := a.str()
	assert !s.contains('\r')
	assert !s.contains('\n')
	assert s.starts_with('a@b.com')
}

fn test_address_str_escapes_display_name_quote() {
	a := Address{
		email: 'a@b.com'
		name:  'Evil" <x@evil.com>, "'
	}
	s := a.str()
	// 名字里的引号必须被转义，否则可以提前闭合引号
	assert s.contains('\\"')
	// 并且只包裹一层引号
	assert s.starts_with('"')
	assert s.ends_with('<a@b.com>')
}

fn test_address_str_plain() {
	assert Address{
		email: 'a@b.com'
	}.str() == 'a@b.com'
	assert Address{
		email: 'a@b.com'
		name:  'Alice'
	}.str() == '"Alice" <a@b.com>'
}

fn test_log_transport_redacts_bcc() {
	reset_log_sent_count()
	lt := new_log_transport()
	mail := Email{
		from:    Address{
			email: 'sender@example.com'
		}
		to:      [Address{ email: 'visible@example.com' }]
		bcc:     [Address{ email: 'secret-bcc@example.com' }]
		subject: 'hi'
		body:    'hello'
		headers: map[string]string{}
	}
	lt.send(mail)!
	assert get_log_sent_count() == 1
	// 打码函数本身的行为
	assert redact_address('secret-bcc@example.com') == '***@example.com'
	assert redact_address('no-at-sign') == '***'
}
