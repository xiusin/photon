module mailer

// mailer.v - Mail System (Spring MailSender / Laravel Mailer inspired)
//
// Provides a unified mail abstraction with pluggable transport backends.
// Supports SMTP out of the box, with extension points for
// SendGrid, Mailgun, Amazon SES, etc.
//
// Features:
//   - Multiple transport backends (SMTP, Log)
//   - Email template rendering with variable substitution
//   - Batch sending (send to multiple recipients)
//   - Fluent email builder (EmailBuilder)
//   - CC/BCC/Reply-To support
//   - File attachments
import net.smtp as vsmtp
import strings
import time

// ── Types ──

// EncryptionType defines the mail server encryption mode.
pub enum EncryptionType {
	none
	starttls
	tls
}

// Address represents an email address with optional display name.
pub struct Address {
pub:
	email string
	name  string
}

// str returns the formatted address string.
pub fn (a Address) str() string {
	if a.name.len > 0 {
		return '"${a.name}" <${a.email}>'
	}
	return a.email
}

// parse_address parses an email address string into an Address struct.
// Supports both "user@example.com" and "Display Name <user@example.com>" formats.
pub fn parse_address(s string) Address {
	mut name := ''
	mut email := s.trim_space()

	// Check for "Name <email>" format
	if email.contains('<') && email.contains('>') {
		start := email.index('<') or { 0 }
		end := email.index('>') or { email.len }
		name = email[..start].trim_space()
		email = email[start + 1..end].trim_space()
	}

	return Address{
		email: email
		name:  name
	}
}

// EmailAttachment represents an email attachment.
pub struct EmailAttachment {
pub:
	filename     string
	content      []u8
	content_type string = 'application/octet-stream'
}

// new_attachment creates an EmailAttachment from bytes.
pub fn new_attachment(filename string, content []u8, content_type string) EmailAttachment {
	return EmailAttachment{
		filename:     filename
		content:      content
		content_type: if content_type.len > 0 { content_type } else { 'application/octet-stream' }
	}
}

// Email represents an email message.
pub struct Email {
pub mut:
	from        Address
	to          []Address
	cc          []Address
	bcc         []Address
	reply_to    Address
	subject     string
	body        string
	html_body   string
	is_html     bool
	attachments []EmailAttachment
	headers     map[string]string
	priority    int = 3
}

// new_email creates a new Email with default values.
pub fn new_email() Email {
	return Email{
		to:          []Address{}
		cc:          []Address{}
		bcc:         []Address{}
		attachments: []EmailAttachment{}
		headers:     map[string]string{}
		priority:    3
	}
}

// ── Email Builder (Fluent API) ──

// EmailBuilder provides a fluent API for constructing emails.
pub struct EmailBuilder {
mut:
	from          Address
	to            []Address
	cc            []Address
	bcc           []Address
	reply_to      Address
	subject       string
	body          string
	html_body     string
	is_html       bool
	attachments   []EmailAttachment
	headers       map[string]string
	priority      int
	template      string
	template_data map[string]string
}

// new_email_builder creates a new EmailBuilder.
pub fn new_email_builder() EmailBuilder {
	return EmailBuilder{
		to:            []Address{}
		cc:            []Address{}
		bcc:           []Address{}
		attachments:   []EmailAttachment{}
		headers:       map[string]string{}
		priority:      3
		template_data: map[string]string{}
	}
}

// from sets the sender address.
pub fn (mut b EmailBuilder) from(addr string) EmailBuilder {
	b.from = parse_address(addr)
	return b
}

// from_address sets the sender using an Address struct.
pub fn (mut b EmailBuilder) from_address(addr Address) EmailBuilder {
	b.from = addr
	return b
}

// to adds a recipient.
pub fn (mut b EmailBuilder) to(addr string) EmailBuilder {
	b.to << parse_address(addr)
	return b
}

// to_many adds multiple recipients.
pub fn (mut b EmailBuilder) to_many(addrs []string) EmailBuilder {
	for a in addrs {
		b.to << parse_address(a)
	}
	return b
}

// cc adds a CC recipient.
pub fn (mut b EmailBuilder) cc(addr string) EmailBuilder {
	b.cc << parse_address(addr)
	return b
}

// bcc adds a BCC recipient.
pub fn (mut b EmailBuilder) bcc(addr string) EmailBuilder {
	b.bcc << parse_address(addr)
	return b
}

// reply_to sets the Reply-To address.
pub fn (mut b EmailBuilder) reply_to(addr string) EmailBuilder {
	b.reply_to = parse_address(addr)
	return b
}

// subject sets the email subject.
pub fn (mut b EmailBuilder) subject(subj string) EmailBuilder {
	b.subject = subj
	return b
}

// text sets the plain text body.
pub fn (mut b EmailBuilder) text(body string) EmailBuilder {
	b.body = body
	b.is_html = false
	return b
}

// html sets the HTML body.
pub fn (mut b EmailBuilder) html(body string) EmailBuilder {
	b.html_body = body
	b.is_html = true
	return b
}

// set_template sets a template string with variables to substitute.
// Use {{variable_name}} syntax in templates.
pub fn (mut b EmailBuilder) set_template(template string) EmailBuilder {
	b.template = template
	return b
}

// with_var adds a template variable for substitution.
pub fn (mut b EmailBuilder) with_var(key string, value string) EmailBuilder {
	b.template_data[key] = value
	return b
}

// with_vars adds multiple template variables at once.
pub fn (mut b EmailBuilder) with_vars(vars map[string]string) EmailBuilder {
	for k, v in vars {
		b.template_data[k] = v
	}
	return b
}

// attach adds a file attachment.
pub fn (mut b EmailBuilder) attach(filename string, content []u8, content_type string) EmailBuilder {
	b.attachments << new_attachment(filename, content, content_type)
	return b
}

// header adds a custom header.
pub fn (mut b EmailBuilder) header(key string, value string) EmailBuilder {
	b.headers[key] = value
	return b
}

// priority sets the email priority (1=highest, 5=lowest).
pub fn (mut b EmailBuilder) priority(level int) EmailBuilder {
	b.priority = level
	if level < 1 { b.priority = 1 }
	if level > 5 { b.priority = 5 }
	return b
}

// build constructs the Email from the builder state.
// If a template is set, it renders the template before building.
pub fn (mut b EmailBuilder) build() Email {
	mut e := new_email()
	e.from = b.from
	e.to = b.to
	e.cc = b.cc
	e.bcc = b.bcc
	e.reply_to = b.reply_to
	e.subject = b.subject
	for k, v in b.headers {
		e.headers[k] = v
	}
	e.priority = b.priority
	e.attachments = b.attachments

	// If template is set, render it
	if b.template.len > 0 {
		rendered := render_template(b.template, b.template_data)
		// If the template looks like HTML (contains <html or <body tags), treat as HTML
		is_html_template := rendered.contains('<html') || rendered.contains('<body')
		if b.is_html || b.html_body.len > 0 || is_html_template {
			e.html_body = rendered
			e.is_html = true
		} else {
			e.body = rendered
		}
	} else {
		e.body = b.body
		e.html_body = b.html_body
		e.is_html = b.is_html
	}

	return e
}

// ── Template Rendering ──

// render_template substitutes {{variable}} placeholders in a template string.
// Variables are replaced with their values from the data map.
// Unknown variables are left as-is (or replaced with empty string).
pub fn render_template(template string, data map[string]string) string {
	mut result := template
	for key, val in data {
		placeholder := '{{${key}}}'
		result = result.replace(placeholder, val)
	}
	return result
}

// ── Mail Transport Interface ──

// MailTransport is the interface for mail transport backends.
pub interface MailTransport {
	send(mail Email) !
}

// ── SMTP Transport ──

// SmtpConfig holds SMTP connection configuration.
pub struct SmtpConfig {
pub:
	host       string
	port       int = 587
	username   string
	password   string
	encryption EncryptionType = .starttls
	timeout_ms int            = 30000
	from_name  string         = 'Photon App'
}

// SmtpTransport sends emails via SMTP.
pub struct SmtpTransport {
pub mut:
	config SmtpConfig
}

// new_smtp_transport creates an SmtpTransport.
pub fn new_smtp_transport(config SmtpConfig) &SmtpTransport {
	return &SmtpTransport{
		config: config
	}
}

// send sends an Email via SMTP.
pub fn (st SmtpTransport) send(mail Email) ! {
	mut client := vsmtp.new_client(
		server:   st.config.host
		port:     st.config.port
		username: st.config.username
		password: st.config.password
		from:     mail.from.email
		starttls: st.config.encryption == .starttls
		ssl:      st.config.encryption == .tls
	)!

	to_str := mail.to.map(it.email).join(', ')
	cc_str := mail.cc.map(it.email).join(', ')
	bcc_str := mail.bcc.map(it.email).join(', ')

	mut smtp_attachments := []vsmtp.Attachment{}
	for att in mail.attachments {
		smtp_attachments << vsmtp.Attachment{
			filename: att.filename
			bytes:    att.content
		}
	}

	body_type := if mail.is_html || mail.html_body.len > 0 {
		vsmtp.BodyType.html
	} else {
		vsmtp.BodyType.text
	}
	body_content := if mail.is_html || mail.html_body.len > 0 { mail.html_body } else { mail.body }

	vsmtp_config := vsmtp.Mail{
		from:        mail.from.email
		to:          to_str
		cc:          cc_str
		bcc:         bcc_str
		subject:     mail.subject
		body_type:   body_type
		body:        body_content
		attachments: smtp_attachments
		date:        time.now()
	}

	client.send(vsmtp_config)!
	client.quit() or {}
}

// ── Log Transport (for development) ──

// Global state for LogTransport (needed because V interface methods can't take mut receiver)
__global (
	log_sent_email_count int
)

// LogTransport logs emails instead of sending them.
// Useful for development and testing environments.
pub struct LogTransport {
pub:
	log_file string
}

// new_log_transport creates a LogTransport.
pub fn new_log_transport() &LogTransport {
	return &LogTransport{}
}

// get_log_sent_count returns the number of emails logged.
pub fn get_log_sent_count() int {
	return log_sent_email_count
}

// reset_log_sent_count resets the log counter (useful between tests).
pub fn reset_log_sent_count() {
	log_sent_email_count = 0
}

// send logs the email instead of sending it.
pub fn (lt LogTransport) send(mail Email) ! {
	mut sb := strings.new_builder(256)
	sb.write_string('===========================================================\n')
	sb.write_string('MAIL LOG\n')
	sb.write_string('-----------------------------------------------------------\n')
	sb.write_string('From: ${mail.from.str()}\n')
	sb.write_string('To: ${mail.to.map(it.str()).join(', ')}\n')
	if mail.cc.len > 0 {
		sb.write_string('Cc: ${mail.cc.map(it.str()).join(', ')}\n')
	}
	if mail.bcc.len > 0 {
		sb.write_string('Bcc: ${mail.bcc.map(it.str()).join(', ')}\n')
	}
	if mail.reply_to.email.len > 0 {
		sb.write_string('Reply-To: ${mail.reply_to.str()}\n')
	}
	sb.write_string('Subject: ${mail.subject}\n')
	sb.write_string('Priority: ${mail.priority}\n')
	if mail.headers.len > 0 {
		sb.write_string('Headers:\n')
		for k, v in mail.headers {
			sb.write_string('  ${k}: ${v}\n')
		}
	}
	sb.write_string('-----------------------------------------------------------\n')
	if mail.is_html || mail.html_body.len > 0 {
		sb.write_string('[HTML Body]\n${mail.html_body}\n')
	} else {
		sb.write_string('[Text Body]\n${mail.body}\n')
	}
	if mail.attachments.len > 0 {
		sb.write_string('-----------------------------------------------------------\n')
		sb.write_string('Attachments: ${mail.attachments.len}\n')
		for att in mail.attachments {
			sb.write_string('  - ${att.filename} (${att.content_type}, ${att.content.len} bytes)\n')
		}
	}
	sb.write_string('===========================================================\n')

	println(sb.str())

	// Track count for testing
	log_sent_email_count++
}

// ── Null Transport (for testing) ──

// Global state for NullTransport
__global (
	null_transport_sent_count int
	null_transport_last_email Email
)

// NullTransport discards all emails. Useful for testing.
pub struct NullTransport {}

// new_null_transport creates a NullTransport.
pub fn new_null_transport() &NullTransport {
	return &NullTransport{}
}

// get_null_sent_count returns the number of emails sent via NullTransport.
pub fn get_null_sent_count() int {
	return null_transport_sent_count
}

// get_null_last_email returns the last email sent via NullTransport.
pub fn get_null_last_email() ?Email {
	if null_transport_sent_count == 0 {
		none
	}
	return null_transport_last_email
}

// reset_null_transport resets NullTransport counters (useful between tests).
pub fn reset_null_transport() {
	null_transport_sent_count = 0
	null_transport_last_email = Email{}
}

// send discards the email but records it for testing.
pub fn (nt NullTransport) send(mail Email) ! {
	null_transport_sent_count++
	null_transport_last_email = mail
}

// ── Mailer ──

// Mailer provides high-level mail sending with a pluggable transport.
pub struct Mailer {
pub mut:
	transport    &MailTransport = unsafe { nil }
	from_address Address
}

// new_mailer creates a Mailer with the given SMTP config.
pub fn new_mailer(config SmtpConfig) &Mailer {
	transport := new_smtp_transport(config)
	return &Mailer{
		transport:    transport
		from_address: Address{
			email: config.username
			name:  config.from_name
		}
	}
}

// new_log_mailer creates a Mailer with a log transport (for development).
pub fn new_log_mailer() &Mailer {
	return &Mailer{
		transport: new_log_transport()
	}
}

// new_null_mailer creates a Mailer with a null transport (for testing).
pub fn new_null_mailer() &Mailer {
	return &Mailer{
		transport: new_null_transport()
	}
}

// send sends an Email message.
pub fn (mut m Mailer) send(mail Email) ! {
	mut msg := mail

	if msg.from.email.len == 0 {
		msg.from = m.from_address
	}

	return m.transport.send(msg)
}

// send_with_builder builds and sends an email using an EmailBuilder.
pub fn (mut m Mailer) send_with_builder(builder EmailBuilder) ! {
	mut b := builder
	if b.from.email.len == 0 {
		b.from = m.from_address
	}
	email := b.build()
	return m.send(email)
}

// send_to is a convenience method for simple text emails.
pub fn (mut m Mailer) send_to(to string, subject string, body string) ! {
	return m.send(Email{
		from:    m.from_address
		to:      [Address{ email: to }]
		subject: subject
		body:    body
	})
}

// send_html is a convenience method for HTML emails.
pub fn (mut m Mailer) send_html(to string, subject string, html_body string) ! {
	return m.send(Email{
		from:      m.from_address
		to:        [Address{ email: to }]
		subject:   subject
		html_body: html_body
		is_html:   true
	})
}

// send_batch sends the same email to multiple recipients individually.
// Returns the number of successfully sent emails.
pub fn (mut m Mailer) send_batch(recipients []string, subject string, body string) !int {
	mut count := 0
	for recip in recipients {
		m.send_to(recip, subject, body) or { continue }
		count++
	}
	return count
}

// ── Common Email Templates ──

// template_welcome returns a welcome email template.
pub fn template_welcome() string {
	return '<!DOCTYPE html>
<html>
<body style="font-family: Arial, sans-serif;">
<h2>Welcome, {{name}}!</h2>
<p>Thank you for joining {{app_name}}. We\'re excited to have you aboard.</p>
<p>You can get started by <a href="{{action_url}}">clicking here</a>.</p>
<p>Best regards,<br/>The {{app_name}} Team</p>
</body>
</html>'
}

// template_password_reset returns a password reset email template.
pub fn template_password_reset() string {
	return '<!DOCTYPE html>
<html>
<body style="font-family: Arial, sans-serif;">
<h2>Password Reset Request</h2>
<p>Hello {{name}},</p>
<p>We received a request to reset your password. Click the link below to proceed:</p>
<p><a href="{{reset_url}}">Reset Your Password</a></p>
<p>This link will expire in {{expires_in}} hours.</p>
<p>If you didn\'t request this reset, please ignore this email.</p>
<p>Best regards,<br/>The {{app_name}} Team</p>
</body>
</html>'
}

// template_notification returns a generic notification email template.
pub fn template_notification() string {
	return '<!DOCTYPE html>
<html>
<body style="font-family: Arial, sans-serif;">
<h2>{{title}}</h2>
<p>{{greeting}}, {{name}}</p>
<p>{{message}}</p>
<p>{{action_text}}: <a href="{{action_url}}">{{action_label}}</a></p>
</body>
</html>'
}
