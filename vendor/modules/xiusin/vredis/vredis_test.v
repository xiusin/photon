module vredis

// vredis_test.v — vendored 客户端的「真连真用」功能覆盖
//
// 上游 vredis 没有独立可运行的测试（原 `*_test.v` 直接压在仓库里、依赖
// 真实库状态），vendor 进来之后我们需要自己一份守门测试：
//
//   * 覆盖协议编解码、连接池生命周期、各数据类型命令、JSON 帮工、Lua 脚本
//   * 只在 Redis 可达时运行；不可达时 skip 并明确告知，不伪装成通过
//
// 运行：sh scripts/sync-vendor.sh && v -enable-globals test vendor/modules/xiusin/vredis/
import net
import time

// redis_reachable 探测本机 Redis 是否可用，决定整套测试跑还是 skip。
fn redis_reachable() bool {
	mut conn := net.dial_tcp('127.0.0.1:6379') or { return false }
	conn.close() or {}
	return true
}

fn redis_opts_or_skip() !ConnOpts {
	if !redis_reachable() {
		eprintln('vredis_test: 127.0.0.1:6379 不可达，跳过全部功能覆盖测试')
		return error('redis not reachable')
	}
	return ConnOpts{
		host:          '127.0.0.1'
		port:          6379
		db:            15 // 用 15 号库，避免污染业务数据
		read_timeout:  time.second * 5
		write_timeout: time.second * 5
	}
}

// new_test_client 返回一个连到 15 号库、已清空的客户端。
fn new_test_client() !&Redis {
	opts := redis_opts_or_skip()!
	mut r := new_client(opts)!
	r.flushdb()!
	return r
}

fn unique_key(prefix string) string {
	return 'vredis_test:${prefix}:${time.now().unix_nano()}'
}

// ── 连接 ──

fn test_connect_ping_and_close() ! {
	mut r := new_test_client()!
	defer {
		r.close() or {}
	}
	assert r.ping()!
	assert r.is_active
	r.close()!
	assert !r.is_active
}

fn test_select_db() ! {
	mut r := new_test_client()!
	defer {
		r.close() or {}
	}
	assert r.@select(14)!
	assert r.@select(15)!
}

// ── 字符串 ──

fn test_string_basic_roundtrip() ! {
	mut r := new_test_client()!
	defer {
		r.close() or {}
	}
	k := unique_key('str')

	assert r.set(k, 'hello')!
	assert r.get(k)! == 'hello'
	assert r.exists(k)!

	// SETNX / GETSET / APPEND / STRLEN
	assert !(r.setnx(k, 'nope')!)
	assert r.getset(k, 'world')! == 'hello'
	assert r.append(k, '!!')! == 7
	assert r.strlen(k)! == 7
	assert r.get(k)! == 'world!!'

	// 覆盖写 + SETEX TTL
	assert r.setex(k, 100, 'ttl')!
	ttl := r.ttl(k)!
	assert ttl > 0 && ttl <= 100

	// GETRANGE / SETRANGE
	assert r.set(k, 'abcdef')!
	assert r.getrange(k, 1, 3)! == 'bcd'
	assert r.setrange(k, 1, 'XY')! == 6
	assert r.get(k)! == 'aXYdef'

	assert r.del(k)!
	assert !(r.exists(k)!)
}

fn test_string_numeric_ops() ! {
	mut r := new_test_client()!
	defer {
		r.close() or {}
	}
	k := unique_key('num')

	assert r.incr(k)! == 1
	assert r.incrby(k, 41)! == 42
	assert r.decr(k)! == 41
	assert r.decrby(k, 21)! == 20
	assert r.incrbyfloat(k, 0.5)! == 20.5

	// 对非数字值自增必须报错，而不是静默返回 0
	assert r.set(k, 'abc')!
	if _ := r.incr(k) {
		assert false, 'INCR on a non-numeric value must fail'
	}

	assert r.del(k)!
}

fn test_string_bits() ! {
	mut r := new_test_client()!
	defer {
		r.close() or {}
	}
	k := unique_key('bit')
	assert r.setbit(k, 7, 1)! == 0
	assert r.getbit(k, 7)! == 1
	assert r.getbit(k, 6)! == 0
	assert r.del(k)!
}

fn test_stale_key_get_reports_err_nil() ! {
	mut r := new_test_client()!
	defer {
		r.close() or {}
	}
	// 不存在的 key：GET 必须返回 err_nil，而不是空字符串 —— 调用方靠它
	// 区分「值是空的」和「键不存在」。
	if v := r.get(unique_key('absent')) {
		assert false, 'unexpected value: ${v}'
	} else {
		assert err.msg() == err_nil.msg()
	}
}

fn test_set_opts_nx_xx() ! {
	mut r := new_test_client()!
	defer {
		r.close() or {}
	}
	k := unique_key('setopts')

	assert r.set_opts(k, 'first', SetOpts{ nx: true })!
	// NX：已存在时「业务性拒绝」—— 返回 false，且原值不变。
	// 这不是 error：Redis 的 nil 回复表示条件不成立，不是命令失败。
	assert !(r.set_opts(k, 'second', SetOpts{ nx: true })!)
	assert r.get(k)! == 'first'

	// XX：只覆盖已存在的键
	assert r.set_opts(k, 'third', SetOpts{ xx: true })!
	assert r.get(k)! == 'third'
	assert !(r.set_opts(unique_key('absent'), 'x', SetOpts{ xx: true })!)
	assert r.del(k)!
}

fn test_mget() ! {
	mut r := new_test_client()!
	defer {
		r.close() or {}
	}
	a := unique_key('mget_a')
	b := unique_key('mget_b')
	assert r.set(a, '1')!
	assert r.set(b, '2')!
	m := r.mget(a, b)!
	assert m[a] == '1'
	assert m[b] == '2'
	r.del(a)!
	r.del(b)!
}

// ── 哈希 ──

fn test_hash_ops() ! {
	mut r := new_test_client()!
	defer {
		r.close() or {}
	}
	k := unique_key('hash')

	assert r.hset(k, 'f1', 'v1')!
	assert r.hset(k, 'f2', 'v2')!
	assert r.hlen(k)! == 2
	assert r.hget(k, 'f1')! == 'v1'
	assert r.hexists(k, 'f2')!
	assert !(r.hexists(k, 'f3')!)

	all := r.hgetall(k)!
	assert all['f1'] == 'v1'
	assert all.len == 2

	assert r.hkeys(k)!.len == 2
	assert r.hvals(k)!.len == 2

	vals := r.hmget(k, 'f1', 'f2')!
	assert vals.len == 2
	assert vals[0] == 'v1'

	assert r.hincrby(k, 'cnt', 5)! == 5
	assert r.hincrbyfloat(k, 'fcnt', 1.5)! == 1.5
	// HSETNX 撞上已存在字段时同样返回 false（nil 回复），字段保持不变
	assert !(r.hsetnx(k, 'f1', 'ignored')!)
	assert r.hget(k, 'f1')! == 'v1', 'HSETNX must not overwrite an existing field'

	assert r.hdel(k, 'f1')!
	assert !(r.hexists(k, 'f1')!)
	assert r.del(k)!
}

fn test_hash_json() ! {
	mut r := new_test_client()!
	defer {
		r.close() or {}
	}
	k := unique_key('hashjson')
	r.hset_json(k, 'u1', TUser{
		name: 'alice'
		age:  30
	})!
	got := r.hget_json[TUser](k, 'u1')!
	assert got.name == 'alice'
	assert got.age == 30
	r.del(k)!
}

struct TUser {
	name string
	age  int
}

// ── 列表 ──

fn test_list_ops() ! {
	mut r := new_test_client()!
	defer {
		r.close() or {}
	}
	k := unique_key('list')

	assert r.rpush(k, 'a', ...['b', 'c'])! == 3
	assert r.lpush(k, 'z')! == 4
	assert r.llen(k)! == 4
	assert r.lindex(k, 0)! == 'z'
	assert r.lrange(k, 0, -1)! == ['z', 'a', 'b', 'c']

	assert r.lpop(k)! == 'z'
	assert r.rpop(k)! == 'c'
	assert r.llen(k)! == 2

	assert r.lset(k, 0, 'A')!
	assert r.lindex(k, 0)! == 'A'

	assert r.ltrim(k, 0, 0)!
	assert r.llen(k)! == 1
	assert r.del(k)!
}

fn test_list_rpoplpush() ! {
	mut r := new_test_client()!
	defer {
		r.close() or {}
	}
	src := unique_key('list_src')
	dst := unique_key('list_dst')
	r.rpush(src, 'x')!
	assert r.rpoplpush(src, dst)! == 'x'
	assert r.llen(src)! == 0
	assert r.llen(dst)! == 1
	r.del(src)!
	r.del(dst)!
}

// ── 集合 ──

fn test_set_ops() ! {
	mut r := new_test_client()!
	defer {
		r.close() or {}
	}
	k := unique_key('set')

	assert r.sadd(k, 'a', ...['b', 'c'])! == 3
	// 重复插入返回 0，而不是报错
	assert r.sadd(k, 'a')! == 0
	assert r.scard(k)! == 3
	assert r.sismember(k, 'b')!
	assert !(r.sismember(k, 'zz')!)

	assert r.srem(k, 'a')! == 1
	assert r.scard(k)! == 2
	assert r.spop(k)!.len > 0

	r.sadd(k, 'm1', ...['m2'])!
	assert r.smove(k, unique_key('set2'), 'm1')!
	r.del(k)!
}

// ── 有序集合 ──

fn test_zset_ops() ! {
	mut r := new_test_client()!
	defer {
		r.close() or {}
	}
	k := unique_key('zset')

	assert r.zadd(k, 1.0, 'one')! == 1
	assert r.zadd(k, 2.0, 'two')! == 1
	assert r.zcard(k)! == 2
	assert r.zscore(k, 'two')! == 2.0

	members := r.zrange(k, 0, -1)!
	assert members == ['one', 'two']

	assert r.zincrby(k, 5.0, 'one')! == 6.0
	assert r.zrem(k, 'two')! == 1
	assert r.zcard(k)! == 1
	assert r.del(k)!
}

// ── 键空间 ──

fn test_keys_scan_and_dbsize() ! {
	mut r := new_test_client()!
	defer {
		r.close() or {}
	}
	prefix := 'vredis_test:scan:${time.now().unix_nano()}'
	for i in 0 .. 5 {
		r.set('${prefix}:${i}', '${i}')!
	}
	keys := r.keys('${prefix}:*')!
	assert keys.len == 5, 'KEYS should return all 5 keys, got ${keys.len}'

	// SCAN 的游标语义：第一页返回 cursor + 部分键，cursor 为 0 表示结束
	reply := r.scan(ScanOpts{
		pattern: '${prefix}:*'
		count:   10
	})!
	assert reply.result.len > 0

	assert r.dbsize()! >= 5

	for k in keys {
		r.del(k)!
	}
}

fn test_expire_lifecycle() ! {
	mut r := new_test_client()!
	defer {
		r.close() or {}
	}
	k := unique_key('expire')
	r.set(k, 'v')!
	assert r.expire(k, 100)!
	ttl := r.ttl(k)!
	assert ttl > 0

	assert r.persist(k)! >= 0
	assert r.ttl(k)! == -1 // 无过期时间

	assert r.pexpire(k, 100_000)!
	assert r.pttl(k)! > 0

	assert r.@type(k)! == 'string'
	r.del(k)!
}

fn test_rename() ! {
	mut r := new_test_client()!
	defer {
		r.close() or {}
	}
	a := unique_key('ren_a')
	b := unique_key('ren_b')
	r.set(a, 'v')!
	assert r.rename(a, b)!
	assert !(r.exists(a)!)
	assert r.get(b)! == 'v'
	r.del(b)!
}

// ── JSON 帮工 ──

fn test_json_roundtrip() ! {
	mut r := new_test_client()!
	defer {
		r.close() or {}
	}
	k := unique_key('json')
	assert r.set_json(k, TUser{
		name: 'bob'
		age:  25
	})!
	got := r.get_json[TUser](k)!
	assert got.name == 'bob'
	assert got.age == 25

	// 不是 JSON 的内容必须报错，而不是返回零值
	r.set(k, 'not json')!
	if _ := r.get_json[TUser](k) {
		assert false, 'decode of non-JSON must fail'
	}
	r.del(k)!
}

fn test_json_map_roundtrip() ! {
	mut r := new_test_client()!
	defer {
		r.close() or {}
	}
	k := unique_key('jsonmap')
	assert r.set_json(k, {
		'n': 1
		'm': 2
	})!
	got := r.get_json[map[string]int](k)!
	assert got['n'] == 1
	assert got['m'] == 2
	r.del(k)!
}

// ── Lua 脚本 ──

fn test_eval_and_script_cache() ! {
	mut r := new_test_client()!
	defer {
		r.close() or {}
	}
	k := unique_key('lua')
	r.set(k, '10')!

	// KEYS[1] 自增并返回新值
	script := "return redis.call('INCRBY', KEYS[1], ARGV[1])"
	reply := r.eval(script, 1, k, '5')!
	assert reply.int() == 15

	sha := r.script_load(script)!
	assert sha.len == 40
	exists := r.script_exists(sha)!
	assert exists[sha]

	by_sha := r.evalsha(sha, 1, k, '5')!
	assert by_sha.int() == 20
	r.del(k)!
}

// ── 发布订阅 ──

fn test_pubsub_delivers_messages() ! {
	opts := redis_opts_or_skip()!
	channel := unique_key('pubsub')

	mut publisher := new_client(opts)!

	// 订阅连接在协程里自己创建、自己关闭 —— 客户端的 mut 状态不跨协程传递。
	received := chan string{cap: 4}
	spawn fn [opts, channel, received] () {
		subscriber(opts, channel, received)
	}()

	// 等订阅真正建立：PUBSUB NUMSUB 返回 [channel, count] 二元数组
	mut ready := false
	for _ in 0 .. 100 {
		nums := publisher.pubsub('NUMSUB', channel)!.strings()
		if nums.len == 2 && nums[1].int() > 0 {
			ready = true
			break
		}
		time.sleep(20 * time.millisecond)
	}
	assert ready, 'subscription was never registered'

	publisher.publish(channel, 'hello')!

	select {
		msg := <-received {
			assert msg == 'hello'
		}
		2 * time.second {
			assert false, 'no message received within 2s'
		}
	}

	publisher.close() or {}
}

// subscriber 在独立协程里跑订阅循环：连一条独立连接、收一条消息、关连接。
// 抽成顶层函数是为了不把 defer/mut 客户端的组合放进匿名闭包
// （V 0.5.2 在含 defer 的闭包体里对后续 mut 声明有解析限制）。
fn subscriber(opts ConnOpts, channel string, received chan string) {
	mut sub := new_client(opts) or { return }
	defer {
		sub.close() or {}
	}
	sub.subscribe([channel], fn [received] (ch string, payload string) ! {
		received <- payload
	}) or {}
}

// ── 连接池 ──

fn test_pool_borrow_and_return() ! {
	opts := redis_opts_or_skip()!
	mut pool := new_pool(PoolOpt{
		max_active: 2
		dial:       fn [opts] () !&Redis {
			return new_client(opts)!
		}
	})!
	defer {
		pool.close()
	}

	mut c1 := pool.get()!
	assert c1.ping()!
	c1.set(unique_key('pool'), 'v')!
	st := pool.stats()
	assert st.active == 1
	c1.release()

	st2 := pool.stats()
	assert st2.active == 0, 'release() must return the slot to the pool'
}

fn test_pool_respects_max_active() ! {
	opts := redis_opts_or_skip()!
	mut pool := new_pool(PoolOpt{
		max_active: 1
		dial:       fn [opts] () !&Redis {
			return new_client(opts)!
		}
	})!
	defer {
		pool.close()
	}

	mut first := pool.get()!
	// 上限为 1：第二次借用必须拒绝，而不是悄悄再开一条连接
	if _ := pool.get() {
		assert false, 'pool must not exceed max_active'
	} else {
		assert err.msg() == err_pool_exhausted.msg()
	}
	first.release()
}

fn test_pool_reuses_connection() ! {
	opts := redis_opts_or_skip()!
	mut pool := new_pool(PoolOpt{
		max_active: 2
		dial:       fn [opts] () !&Redis {
			return new_client(opts)!
		}
	})!
	defer {
		pool.close()
	}

	mut c := pool.get()!
	ptr_epoch := c.active_time
	c.release()

	mut c2 := pool.get()!
	// 复用同一批连接：创建时间戳不变
	assert c2.active_time == ptr_epoch, 'pool should reuse idle connections'
	c2.release()
}

fn test_pool_closed_rejects_get() ! {
	opts := redis_opts_or_skip()!
	mut pool := new_pool(PoolOpt{
		max_active: 1
		dial:       fn [opts] () !&Redis {
			return new_client(opts)!
		}
	})!
	pool.close()
	if _ := pool.get() {
		assert false, 'get() on a closed pool must fail'
	}
	// 重复 close 必须幂等
	pool.close()
}

// ── 协议边界 ──

fn test_cmd_arg_escaping_roundtrip() ! {
	mut r := new_test_client()!
	defer {
		r.close() or {}
	}
	k := unique_key('escape')
	// 含 CRLF、引号、空格和中文的值必须原样往返 —— 二进制安全的 RESP 编码
	tricky := 'a\r\nb "c" d 中文 \x00 tail'
	assert r.set(k, tricky)!
	assert r.get(k)! == tricky
	assert r.del(k)!
}

fn test_build_cmd_resp_encoding() {
	// build_cmd 生成标准 RESP 数组：*N\r\n 后每个参数是 $len\r\narg\r\n
	cmd := build_cmd('SET', 'k', 'v')
	assert cmd == '*3\r\n$3\r\nSET\r\n$1\r\nk\r\n$1\r\nv\r\n'

	// 参数数量随参数个数变化，且二进制安全（不做转义/截断）
	two := build_cmd('GET', 'k')
	assert two == '*2\r\n$3\r\nGET\r\n$1\r\nk\r\n'

	binary := build_cmd('SET', 'k', 'a\r\nb')
	assert binary.contains('$4\r\na\r\nb\r\n'), 'bulk string must be binary safe: ${binary}'
}
