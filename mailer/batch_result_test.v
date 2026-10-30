module mailer

// batch_result_test.v — 群发失败不能只剩一个"0"
//
// 老实现每次失败都 `or { continue }`，于是：
//   - 全部被拒  → 返回 0，看起来像"还没发"
//   - 部分被拒  → 返回成功数，失败的那些人和原因全部消失
// 群发场景下最需要的信息恰恰是"谁没收到、为什么"。

@[heap]
struct AlwaysFailTransport {}

fn (t &AlwaysFailTransport) send(mail Email) ! {
	return error('smtp: connection refused')
}

@[heap]
struct FailOnTransport {
pub:
	bad string
}

fn (t &FailOnTransport) send(mail Email) ! {
	for to in mail.to {
		if to.email == t.bad {
			return error('smtp: mailbox unavailable')
		}
	}
	return
}

fn batch_mailer(transport &MailTransport) &Mailer {
	mut m := new_null_mailer()
	unsafe {
		m.transport = transport
	}
	return m
}

fn test_all_failures_surface_as_error() {
	mut m := batch_mailer(&AlwaysFailTransport{})
	mut failed := false
	m.send_batch(['a@x.com', 'b@x.com'], 'subj', 'body') or { failed = true }
	assert failed, 'a batch where every recipient failed must not return a silent 0'
}

fn test_partial_failure_reports_who_and_why() {
	mut m := batch_mailer(&FailOnTransport{ bad: 'bad@x.com' })
	result := m.send_batch_report(['ok1@x.com', 'bad@x.com', 'ok2@x.com'], 'subj', 'body')!
	assert result.total == 3
	assert result.sent == 2
	assert result.has_failures()
	assert result.failures.len == 1
	assert result.failures[0].recipient == 'bad@x.com'
	assert result.failures[0].reason.contains('mailbox unavailable')
}

fn test_all_success_has_no_failures() {
	mut m := new_null_mailer()
	reset_null_transport()
	result := m.send_batch_report(['a@x.com', 'b@x.com'], 'subj', 'body')!
	assert result.total == 2
	assert result.sent == 2
	assert !result.has_failures()
	assert get_null_sent_count() == 2
}

fn test_legacy_send_batch_still_counts_successes() {
	mut m := batch_mailer(&FailOnTransport{ bad: 'bad@x.com' })
	n := m.send_batch(['ok@x.com', 'bad@x.com'], 'subj', 'body')!
	assert n == 1
}

fn test_empty_recipient_list_is_not_a_failure() {
	mut m := new_null_mailer()
	reset_null_transport()
	result := m.send_batch_report([]string{}, 'subj', 'body')!
	assert result.total == 0
	assert result.sent == 0
	assert !result.has_failures()
}

fn test_null_transport_returns_a_copy_not_internal_state() {
	reset_null_transport()
	mut m := new_null_mailer()
	m.send_to('a@x.com', 'original', 'body')!

	mut leaked := get_null_last_email() or { panic('expected an email') }
	leaked.subject = 'MUTATED'
	leaked.headers['X-Injected'] = '1'

	again := get_null_last_email() or { panic('expected an email') }
	assert again.subject == 'original', 'callers must not be able to mutate the stored email'
	assert 'X-Injected' !in again.headers
}
