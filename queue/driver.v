module queue

// driver.v - Queue Driver Interface

// QueueDriver is the backend interface for queue storage
pub interface QueueDriver {
mut:
	count(queue_name string) int
	push(queue_name string, payload string) !
	// push_delayed 在 run_at_ns（unix 纳秒）之前不可见。
	// 默认实现退化为立即 push，便于第三方驱动按需覆盖。
	push_delayed(queue_name string, payload string, delay_secs i64) !
	// push_attempt 把一个「已经失败过 retry_count 次」的任务重新入队。
	//
	// 重放次数必须跟着 payload 走：任务再次失败时 record_failure 把它写回
	// 新记录的 retry_count。丢掉它，每次重放都从 0 重新计数，
	// 死信队列就成了无限重投机器。
	//
	// push_attempt re-enqueues a job that has already failed retry_count
	// times. The count must travel with the payload, otherwise every replay
	// restarts the counter at zero and the dead-letter loop never ends.
	push_attempt(queue_name string, payload string, delay_secs i64, retry_count int) !
	pop(queue_name string) !string
	clear(queue_name string) !
}

// delayed_run_at 从 payload 头部解析出 run_at_ns。
// 返回 0 表示「没有延迟元数据，立即可用」。
fn delayed_run_at(payload string) i64 {
	if payload.len < 3 {
		return 0
	}
	// 头部必须是 `<数字>||`
	sep := payload.index('||') or { return 0 }
	if sep <= 0 {
		return 0
	}
	stamp := payload[..sep]
	for c in stamp {
		if c < `0` || c > `9` {
			return 0
		}
	}
	return stamp.i64()
}

// strip_delay_prefix 去掉 run_at 前缀，返回真正的 job payload。
fn strip_delay_prefix(payload string) string {
	sep := payload.index('||') or { return payload }
	if sep <= 0 {
		return payload
	}
	stamp := payload[..sep]
	for c in stamp {
		if c < `0` || c > `9` {
			return payload
		}
	}
	return payload[sep + 2..]
}

// split_delay 同时返回 (run_at_ns, 真实 payload)
//
// 重放次数头也在这里一并剥掉：延迟前缀与重放前缀谁在前都可能
// （驱动搬延迟任务时会重新拼头部），所以两头都循环剥一次。
//
// split_delay returns (run_at_ns, real payload) and strips both the
// optional delay prefix and the optional replay-count prefix.
fn split_delay(payload string) (i64, string) {
	mut rest := payload
	mut run_at := i64(0)
	for {
		probe := delayed_run_at(rest)
		if probe == 0 {
			break
		}
		run_at = probe
		rest = strip_delay_prefix(rest)
	}
	rest = strip_retry_count(rest)
	return run_at, rest
}

// is_delay_ready 判断一条 payload 当前是否可用
fn is_delay_ready(payload string, now_ns i64) bool {
	run_at, _ := split_delay(payload)
	return run_at == 0 || run_at <= now_ns
}

// serialize_job serializes a job to a pipe-delimited string
fn serialize_job(job_type string, data string) string {
	return '${job_type}||${data}'
}

// retry_meta_prefix 标记 payload 头部的重放次数元数据。
//
// 形如 `#r3||<job_type>||<data>`，和延迟前缀一样放在最前面：
// `split_n('||', 2)` 的切分点因此不受影响，老代码读到它也只会
// 当成一个不认识的 job_type —— 所以这里必须两侧都剥，
// 而不是只在 worker 侧剥。
//
// retry_meta_prefix marks the replay-count header carried by a payload.
const retry_meta_prefix = '#r'

// attach_retry_count 给 payload 加/换重放次数头。
fn attach_retry_count(payload string, retry_count int) string {
	body := strip_retry_count(payload)
	return '${retry_meta_prefix}${retry_count}||${body}'
}

// strip_retry_count 去掉 payload 头部的重放次数元数据。
fn strip_retry_count(payload string) string {
	if !payload.starts_with(retry_meta_prefix) {
		return payload
	}
	sep := payload.index('||') or { return payload }
	stamp := payload[retry_meta_prefix.len..sep]
	if stamp.len == 0 {
		return payload
	}
	for c in stamp {
		if c < `0` || c > `9` {
			return payload
		}
	}
	return payload[sep + 2..]
}

// payload_retry_count 读出 payload 里携带的重放次数，没有就是 0。
//
// 必须先剥掉延迟前缀再找 `#r`。延迟重放投递出去的 payload 形如
//   <run_at_ns>||#r2||<job_type>||<data>
// `#r` 并不在开头 —— 只看 starts_with 的话，这类 payload 一律读成 0。
// 后果正是这一批要修的那个循环：任务延迟重放后再次失败，record_failure
// 把 retry_count 写成 0（新记录），退避算出来永远是 1 秒，
// `max_retries` 也就永远数不到上限。
//
// strip 的顺序必须和 split_delay 一致（先延迟前缀，再 `#r`），
// 否则「能解析」和「计数正确」会分成两套规则。
fn payload_retry_count(payload string) int {
	// split_delay 会把 `#r` 读掉，这里改从原始串里自己取那一段。
	// 逐层剥延迟前缀，与 split_delay 的循环保持同一形态。
	mut head := payload
	for {
		probe := delayed_run_at(head)
		if probe == 0 {
			break
		}
		head = strip_delay_prefix(head)
	}
	if !head.starts_with(retry_meta_prefix) {
		return 0
	}
	sep := head.index('||') or { return 0 }
	stamp := head[retry_meta_prefix.len..sep]
	if stamp.len == 0 {
		return 0
	}
	for c in stamp {
		if c < `0` || c > `9` {
			return 0
		}
	}
	return stamp.int()
}

// deserialize_job extracts job_type and data from serialized payload.
// Uses split_n to prevent data truncation when job data contains '||'.
fn deserialize_job(payload string) !(string, string) {
	parts := payload.split_n('||', 2)
	if parts.len < 2 {
		return error('invalid job payload format')
	}
	return parts[0], parts[1]
}
