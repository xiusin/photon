module mailer

// ── Address Tests ──

fn test_address_str_email_only() {
	a := Address{
		email: 'user@example.com'
	}
	assert a.str() == 'user@example.com'
}

fn test_address_str_with_name() {
	a := Address{
		email: 'user@example.com'
		name:  'John Doe'
	}
	assert a.str() == '"John Doe" <user@example.com>'
}

fn test_parse_address_simple() {
	a := parse_address('user@example.com')
	assert a.email == 'user@example.com'
	assert a.name.len == 0
}

fn test_parse_address_with_name() {
	a := parse_address('John Doe <john@example.com>')
	assert a.email == 'john@example.com'
	assert a.name == 'John Doe'
}

fn test_parse_address_with_angle_brackets() {
	a := parse_address('  <admin@test.com>  ')
	assert a.email == 'admin@test.com'
	assert a.name.len == 0
}

// ── Email Tests ──

fn test_new_email() {
	e := new_email()
	assert e.to.len == 0
	assert e.cc.len == 0
	assert e.bcc.len == 0
	assert e.attachments.len == 0
	assert e.headers.len == 0
	assert e.priority == 3
}

fn test_email_set_fields() {
	mut e := new_email()
	e.from = Address{
		email: 'sender@example.com'
		name:  'Sender'
	}
	e.to = [Address{ email: 'receiver@example.com' }]
	e.subject = 'Test Subject'
	e.body = 'Hello, World!'

	assert e.from.email == 'sender@example.com'
	assert e.to.len == 1
	assert e.subject == 'Test Subject'
	assert e.body == 'Hello, World!'
}

// ── Attachment Tests ──

fn test_new_attachment() {
	att := new_attachment('doc.pdf', [u8(1), 2, 3], 'application/pdf')
	assert att.filename == 'doc.pdf'
	assert att.content.len == 3
	assert att.content_type == 'application/pdf'
}

fn test_new_attachment_default_type() {
	att := new_attachment('file.txt', [u8(65)], '')
	assert att.content_type == 'application/octet-stream'
}

// ── SmtpConfig Tests ──

fn test_smtp_config_defaults() {
	config := SmtpConfig{
		host:     'smtp.example.com'
		username: 'user@example.com'
		password: 'secret'
	}
	assert config.port == 587
	assert config.encryption == .starttls
	assert config.timeout_ms == 30000
	assert config.from_name == 'Photon App'
}

// ── LogTransport Tests ──

fn test_log_transport_send() {
	reset_log_sent_count()
	mut lt := new_log_transport()
	mut e := new_email()
	e.from = Address{
		email: 'sender@example.com'
	}
	e.to = [Address{ email: 'receiver@example.com' }]
	e.subject = 'Test'
	e.body = 'Hello'

	lt.send(e)!
	assert get_log_sent_count() == 1
}

fn test_log_transport_send_html() {
	reset_log_sent_count()
	mut lt := new_log_transport()
	mut e := new_email()
	e.from = Address{
		email: 'sender@example.com'
	}
	e.to = [Address{ email: 'receiver@example.com' }]
	e.subject = 'HTML Test'
	e.html_body = '<h1>Hello</h1>'
	e.is_html = true

	lt.send(e)!
	assert get_log_sent_count() == 1
}

fn test_log_transport_with_cc_bcc() {
	reset_log_sent_count()
	mut lt := new_log_transport()
	mut e := new_email()
	e.from = Address{
		email: 'sender@example.com'
	}
	e.to = [Address{ email: 'to@example.com' }]
	e.cc = [Address{ email: 'cc@example.com' }]
	e.bcc = [Address{ email: 'bcc@example.com' }]
	e.reply_to = Address{
		email: 'reply@example.com'
	}
	e.subject = 'Multi-recipient'
	e.body = 'Test body'
	e.headers['X-Priority'] = '1'
	e.priority = 1

	lt.send(e)!
	assert get_log_sent_count() == 1
}

// ── NullTransport Tests ──

fn test_null_transport_send() {
	reset_null_transport()
	mut nt := new_null_transport()
	mut e := new_email()

	nt.send(e)!
	assert get_null_sent_count() == 1
	assert get_null_last_email() != none
}

fn test_null_transport_multiple() {
	reset_null_transport()
	mut nt := new_null_transport()
	for _ in 0 .. 5 {
		mut ee := new_email()
		nt.send(ee)!
	}
	assert get_null_sent_count() == 5
}

// ── Mailer Tests ──

fn test_new_log_mailer() {
	m := new_log_mailer()
	assert !isnil(m.transport)
}

fn test_mailer_send_to() {
	reset_log_sent_count()
	mut m := new_log_mailer()
	m.send_to('test@example.com', 'Test Subject', 'Test Body') or { assert false }
}

fn test_mailer_send_html() {
	reset_log_sent_count()
	mut m := new_log_mailer()
	m.send_html('test@example.com', 'HTML Subject', '<h1>Hello</h1>') or { assert false }
}

fn test_null_mailer() {
	m := new_null_mailer()
	assert !isnil(m.transport)
}

// ── EncryptionType Tests ──

fn test_encryption_type_values() {
	assert EncryptionType.none.str() == 'none'
	assert EncryptionType.starttls.str() == 'starttls'
	assert EncryptionType.tls.str() == 'tls'
}

// ── EmailBuilder Tests ──

fn test_builder_basic() {
	mut b := new_email_builder()
	b = b.from('admin@app.com')
	b = b.to('user@example.com')
	b = b.subject('Hello World')
	b = b.text('This is the email body.')

	email := b.build()
	assert email.from.email == 'admin@app.com'
	assert email.to.len == 1
	assert email.to[0].email == 'user@example.com'
	assert email.subject == 'Hello World'
	assert email.body == 'This is the email body.'
	assert email.is_html == false
}

fn test_builder_html() {
	mut b := new_email_builder()
	b = b.from('noreply@app.com')
	b = b.to('user@example.com')
	b = b.subject('Welcome!')
	b = b.html('<h1>Welcome!</h1>')
	email := b.build()

	assert email.is_html == true
	assert email.html_body == '<h1>Welcome!</h1>'
}

fn test_builder_multiple_recipients() {
	mut b := new_email_builder()
	b = b.from('admin@app.com')
	b = b.to_many(['a@example.com', 'b@example.com', 'c@example.com'])
	b = b.cc('manager@example.com')
	b = b.bcc('archive@example.com')
	b = b.subject('Team Update')
	b = b.text('Update info')
	email := b.build()

	assert email.to.len == 3
	assert email.cc.len == 1
	assert email.bcc.len == 1
}

fn test_builder_with_attachments() {
	mut b := new_email_builder()
	b = b.from('admin@app.com')
	b = b.to('user@example.com')
	b = b.subject('Report')
	b = b.attach('report.pdf', [u8(1), 2, 3, 4], 'application/pdf')
	email := b.build()

	assert email.attachments.len == 1
	assert email.attachments[0].filename == 'report.pdf'
	assert email.attachments[0].content.len == 4
}

fn test_builder_headers_and_priority() {
	mut b := new_email_builder()
	b = b.from('admin@app.com')
	b = b.to('user@example.com')
	b = b.subject('Urgent')
	b = b.header('X-Priority', '1')
	b = b.header('X-Mailer', 'Photon')
	b = b.priority(1)
	email := b.build()

	assert email.headers['X-Priority'] == '1'
	assert email.headers['X-Mailer'] == 'Photon'
	assert email.priority == 1
}

fn test_builder_priority_clamping() {
	mut b := new_email_builder()
	b = b.from('x@y.z')
	b = b.to('a@b.c')
	b = b.priority(10)
	email := b.build()
	assert email.priority == 5 // clamped to max

	mut b2 := new_email_builder()
	b2 = b2.from('x@y.z')
	b2 = b2.to('a@b.c')
	b2 = b2.priority(-1)
	email2 := b2.build()
	assert email2.priority == 1 // clamped to min
}

// ── Template Rendering Tests ──

fn test_render_template_basic() {
	tpl := 'Hello, {{name}}! Welcome to {{app_name}}.'
	data := {
		'name':     'Alice'
		'app_name': 'PhotonApp'
	}
	result := render_template(tpl, data)
	assert result == 'Hello, Alice! Welcome to PhotonApp.'
}

fn test_render_template_partial() {
	tpl := 'Dear {{name}}, your order #{{order_id}} is confirmed.'
	data := {
		'name': 'Bob'
	}
	result := render_template(tpl, data)
	assert result.contains('Dear Bob,')
	assert result.contains('#{{order_id}}') // unknown var left as-is
}

fn test_render_template_empty_data() {
	tpl := 'No variables here!'
	data := map[string]string{}
	result := render_template(tpl, data)
	assert result == 'No variables here!'
}

fn test_template_welcome() {
	tpl := template_welcome()
	assert tpl.contains('{{name}}')
	assert tpl.contains('{{app_name}}')

	data := {
		'name':       'Charlie'
		'app_name':   'MyApp'
		'action_url': 'https://example.com/start'
	}
	rendered := render_template(tpl, data)
	assert rendered.contains('Charlie')
	assert rendered.contains('MyApp')
	assert !rendered.contains('{{name}}') // should be replaced
}

fn test_template_password_reset() {
	tpl := template_password_reset()
	assert tpl.contains('{{reset_url}}')
	assert tpl.contains('{{expires_in}}')

	data := {
		'name':       'Dave'
		'app_name':   'SecureApp'
		'reset_url':  'https://example.com/reset?token=abc123'
		'expires_in': '24'
	}
	rendered := render_template(tpl, data)
	assert rendered.contains('Dave')
	assert rendered.contains('reset?token=abc123')
	assert rendered.contains('24 hours')
}

fn test_template_notification() {
	tpl := template_notification()
	data := {
		'title':        'New Comment'
		'greeting':     'Hi'
		'name':         'Eve'
		'message':      'Someone commented on your post.'
		'action_text':  'View it here:'
		'action_url':   'https://example.com/posts/42'
		'action_label': 'View Post'
	}
	rendered := render_template(tpl, data)
	assert rendered.contains('New Comment')
	assert rendered.contains('Eve')
	assert rendered.contains('View Post')
}

// ── Builder with Template Tests ──

fn test_builder_with_template() {
	mut b := new_email_builder()
	b = b.from('hello@world.com')
	b = b.to('user@example.com')
	b = b.subject('Welcome!')
	b = b.set_template(template_welcome())
	b = b.with_var('name', 'Frank')
	b = b.with_var('app_name', 'CoolApp')
	b = b.with_var('action_url', 'https://cool.app/start')
	email := b.build()

	assert email.is_html == true
	assert email.html_body.contains('Frank')
	assert email.html_body.contains('CoolApp')
}

fn test_builder_with_vars_batch() {
	mut b := new_email_builder()
	b = b.from('x@y.z')
	b = b.to('a@b.c')
	b = b.set_template('Hi {{first}} {{last}}, your code is {{code}}.')
	b = b.with_vars({
		'first': 'Grace'
		'last':  'Hopper'
		'code':  '123456'
	})
	email := b.build()

	assert email.body == 'Hi Grace Hopper, your code is 123456.'
}

// ── Batch Send Tests ──

fn test_send_batch() {
	reset_null_transport()
	mut m := new_null_mailer()
	count := m.send_batch(['a@b.c', 'd@e.f', 'g@h.i'], 'Batch Subject', 'Batch Body')!
	assert count == 3
}

fn test_send_batch_empty() {
	reset_null_transport()
	mut m := new_null_mailer()
	count := m.send_batch([], 'Subject', 'Body')!
	assert count == 0
}

// ── send_with_builder Tests ──

fn test_send_with_builder() {
	reset_log_sent_count()
	mut m := new_log_mailer()
	mut builder := new_email_builder()
	builder = builder.from('test@test.com')
	builder = builder.to('recipient@test.com')
	builder = builder.subject('Builder Test')
	builder = builder.text('Sent via builder')

	m.send_with_builder(builder) or { assert false }
}
