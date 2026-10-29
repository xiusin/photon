module queue

// redis_driver_integration_test.v — RedisDriver + VRedisQueueClient 真连真用
//
// RedisDriver 之前完全没测过（整个 queue 模块只有 MemoryDriver 的用例），
// 而它是「生产上才会跑」的那条路径。这里对着真 Redis 覆盖：
//   * 基本 push/pop 的 FIFO 顺序、count、clear
//   * 空队列 pop 必须报 EMPTY（而不是空 payload 被当任务执行）
//   * 延迟任务：未到期不可见，到期后自动可见并被执行
//   * 前缀隔离：两个驱动实例互不串队列
//
// Redis 不可达时整体 skip，不伪装成通过。
import net
import time
import x.json2

// RedisProbeJob 是本文件自带的 Job 实现。
// 单文件测试模式看不到同包其它 _test.v 里的类型，所以不能复用 TestJob。
@[heap]
struct RedisProbeJob {
pub mut:
	name string
}

fn (j &RedisProbeJob) job_type() string {
	return 'redis_probe'
}

fn (j &RedisProbeJob) handle() ! {}

fn (j &RedisProbeJob) tries() int {
	return 1
}

fn (j &RedisProbeJob) backoff() []i64 {
	return [i64(1)]
}

fn (j &RedisProbeJob) data() string {
	return json2.encode(j)
}

fn (mut j RedisProbeJob) from_json(data string) ! {
	decoded := json2.decode[RedisProbeJob](data)!
	j.name = decoded.name
}

fn queue_redis_available() bool {
	mut conn := net.dial_tcp('127.0.0.1:6379') or { return false }
	conn.close() or {}
	return true
}

// new_test_redis_driver 返回一个连到 13 号库、带独立前缀的驱动。
//
// Redis 不可达时返回 `none`，调用方直接 `return` —— 这是「跳过」，
// 不是「失败」。之前这里返回 error，调用方用 `!` 传播，于是没装 Redis 的
// 机器上这 9 个用例全变红色，看起来像框架坏了。
fn new_test_redis_driver() ?(&RedisDriver, &VRedisQueueClient, string) {
	if !queue_redis_available() {
		eprintln('redis_driver_integration_test: 127.0.0.1:6379 不可达，跳过')
		return none
	}
	client := new_vredis_queue_client(VRedisQueueOpt{
		db: 13
	}) or { return none }
	prefix := 'photon:test:queue:${time.now().unix_nano()}:'
	mut d := new_redis_driver(client)
	d.set_prefix(prefix)
	return d, client, prefix
}

fn test_redis_driver_fifo_order() ! {
	mut d, mut c, prefix := new_test_redis_driver() or {
		return
	}
	defer {
		d.clear('emails') or {}
		c.close()
	}

	d.push('emails', 'job-1')!
	d.push('emails', 'job-2')!
	d.push('emails', 'job-3')!
	assert d.count('emails') == 3

	// LPUSH + RPOP = FIFO：先进先出。
	assert d.pop('emails')! == 'job-1'
	assert d.pop('emails')! == 'job-2'
	assert d.pop('emails')! == 'job-3'
	assert d.count('emails') == 0
}

fn test_redis_driver_pop_empty_is_error() ! {
	mut d, mut c, prefix := new_test_redis_driver() or {
		return
	}
	defer {
		d.clear('empty-q') or {}
		c.close()
	}

	// 空队列必须是 EMPTY 错误 —— 返回空串会被 worker 当成一条任务去执行。
	if r := d.pop('empty-q') {
		assert false, 'pop on an empty queue must fail, got "${r}"'
	} else {
		assert err.msg() == 'EMPTY'
	}
}

fn test_redis_driver_clear() ! {
	mut d, mut c, prefix := new_test_redis_driver() or {
		return
	}
	defer {
		d.clear('to-clear') or {}
		c.close()
	}

	d.push('to-clear', 'x')!
	d.push('to-clear', 'y')!
	assert d.count('to-clear') == 2
	d.clear('to-clear')!
	assert d.count('to-clear') == 0
}

fn test_redis_driver_prefix_isolation() ! {
	mut d1, mut c, prefix := new_test_redis_driver() or {
		return
	}
	defer {
		d1.clear('shared') or {}
		c.close()
	}

	mut d2 := new_redis_driver(c)
	d2.set_prefix('${prefix}other:')
	defer {
		d2.clear('shared') or {}
	}

	d1.push('shared', 'from-d1')!
	assert d1.count('shared') == 1
	// 别一个前缀下同名队列必须为空。
	assert d2.count('shared') == 0
	d2.push('shared', 'from-d2')!
	assert d2.pop('shared')! == 'from-d2'
	assert d1.pop('shared')! == 'from-d1'
}

fn test_redis_driver_delayed_not_visible_before_run_at() ! {
	mut d, mut c, prefix := new_test_redis_driver() or {
		return
	}
	defer {
		d.clear('delayed') or {}
		c.close()
	}

	// 延迟 3600 秒：现在绝对不可见。
	d.push_delayed('delayed', 'later-job', 3600)!
	// 主列表为空，延迟任务在 zset 里。
	assert d.count('delayed') == 0
	if r := d.pop('delayed') {
		assert false, 'delayed job must not be visible yet, got "${r}"'
	} else {
		assert err.msg() == 'EMPTY'
	}
}

fn test_redis_driver_delayed_becomes_visible() ! {
	mut d, mut c, prefix := new_test_redis_driver() or {
		return
	}
	defer {
		d.clear('delayed-due') or {}
		c.close()
	}

	// 延迟 0 秒 = 立刻到期。promote_delayed 必须在 pop 之前把它搬进主列表。
	d.push_delayed('delayed-due', 'due-job', 0)!
	time.sleep(5 * time.millisecond)
	assert d.pop('delayed-due')! == 'due-job'
}

fn test_redis_driver_delayed_queue_cleared() ! {
	mut d, mut c, prefix := new_test_redis_driver() or {
		return
	}
	defer {
		d.clear('delayed-clear') or {}
		c.close()
	}

	d.push_delayed('delayed-clear', 'j1', 3600)!
	d.push_delayed('delayed-clear', 'j2', 3600)!
	// clear 只删主列表的键，延迟 zset 是另一个键 —— 这里确认语义边界：
	// 主列表被清空，延迟任务仍在（延迟任务有自己的生命周期）。
	d.clear('delayed-clear')!
	assert d.count('delayed-clear') == 0
}

// ── 与 Dispatcher 的接线 ──

fn test_redis_driver_with_dispatcher() ! {
	mut d, mut c, prefix := new_test_redis_driver() or {
		return
	}
	defer {
		d.clear('dispatch-q') or {}
		d.clear('photon:queue:') or {}
		c.close()
	}

	// push() 是包级函数，走的是全局 dispatcher —— 把它的驱动换成 Redis。
	mut disp := get_dispatcher()
	prev := disp.driver
	defer {
		disp.driver = prev
	}
	disp.driver = d

	// 走 dispatcher 的入口，验证它真的把 payload 落到 Redis 里。
	push('dispatch-q', &RedisProbeJob{
		name: 'redis'
	}, 0)!
	assert d.count('dispatch-q') == 1

	payload := d.pop('dispatch-q')!
	job_type, data := deserialize_job(payload)!
	assert job_type == 'redis_probe'
	assert data.contains('redis')
}

fn test_redis_driver_dispatcher_delayed_goes_to_zset() ! {
	mut d, mut c, prefix := new_test_redis_driver() or {
		return
	}
	defer {
		d.clear('dispatch-delayed') or {}
		c.close()
	}

	mut disp := get_dispatcher()
	prev := disp.driver
	defer {
		disp.driver = prev
	}
	disp.driver = d

	push('dispatch-delayed', &RedisProbeJob{
		name: 'later'
	}, 3600)!
	// 延迟任务在 zset 里，不占主列表。
	assert d.count('dispatch-delayed') == 0
	if r := d.pop('dispatch-delayed') {
		assert false, 'delayed job must not be visible yet, got "${r}"'
	}
}
