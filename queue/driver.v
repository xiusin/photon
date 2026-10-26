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
fn split_delay(payload string) (i64, string) {
	run_at := delayed_run_at(payload)
	if run_at == 0 {
		return 0, payload
	}
	return run_at, strip_delay_prefix(payload)
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

// deserialize_job extracts job_type and data from serialized payload.
// Uses split_n to prevent data truncation when job data contains '||'.
fn deserialize_job(payload string) !(string, string) {
	parts := payload.split_n('||', 2)
	if parts.len < 2 {
		return error('invalid job payload format')
	}
	return parts[0], parts[1]
}
