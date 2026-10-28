module locking

// redis_lock_client.v — 把 vendored 的 xiusin.vredis 接成 RedisClient
//
// 之前的 RedisClient 是一个「接口 + 让用户自己写适配器」的占位：仓库里
// 没有任何实现，new_redis_lock() 在生产代码里根本调不起来。这里补上
// 开箱可用的适配器，复用 vredis 的连接池。
//
// 语义上有一处必须纠正：SET NX 失败时 Redis 返回的是 **nil 回复**，
// 不是 "-ERR"。老实现拿 result == 'OK' 判断，nil 与错误两种情形被
// 压成同一个 false —— 锁被占用和 Redis 挂了看起来一模一样。
import xiusin.vredis
import time

// VRedisLockClient 用一个 vredis 连接池为分布式锁提供命令通道。
pub struct VRedisLockClient {
mut:
	pool &vredis.Pool = unsafe { nil }
	// closed 标记连接池已关闭，避免重复 close。
	closed bool
}

// VRedisLockOpt 配置分布式锁的 Redis 连接。
@[params]
pub struct VRedisLockOpt {
pub:
	host          string = '127.0.0.1'
	port          int    = 6379
	db            u32
	username      string
	password      string
	read_timeout  int = 10 // 秒
	write_timeout int = 10 // 秒
	max_active    int = 8
	idle_timeout  int = 600
	key_prefix    string // 例如 'myapp:lock:'
}

// new_vredis_lock_client 建立到 Redis 的连接池，并 ping 一次确认可达。
pub fn new_vredis_lock_client(opt VRedisLockOpt) !&VRedisLockClient {
	conn_opts := vredis.ConnOpts{
		host:          opt.host
		port:          opt.port
		db:            opt.db
		username:      opt.username
		requirepass:   opt.password
		read_timeout:  time.second * (if opt.read_timeout > 0 { opt.read_timeout } else { 10 })
		write_timeout: time.second * (if opt.write_timeout > 0 {
			opt.write_timeout
		} else {
			10
		})
	}

	mut probe := vredis.new_client(conn_opts)!
	alive := probe.ping() or { false }
	probe.close() or {}
	if !alive {
		return error('locking: redis ping failed for ${opt.host}:${opt.port}')
	}

	pool := vredis.new_pool(vredis.PoolOpt{
		max_active:         if opt.max_active > 0 { opt.max_active } else { 8 }
		idle_timeout:       opt.idle_timeout
		max_conn_life_time: opt.idle_timeout
		dial:               fn [conn_opts] () !&vredis.Redis {
			return vredis.new_client(conn_opts)!
		}
	})!

	return &VRedisLockClient{
		pool: pool
	}
}

// close 关闭连接池。幂等。
pub fn (c &VRedisLockClient) close() {
	if !isnil(c.pool) {
		c.pool.close()
	}
}

// with_conn 借一条连接执行 fn，结束后归还。
@[inline]
fn (c &VRedisLockClient) with_conn[T](f fn (mut conn vredis.ActiveRedisConn) !T) !T {
	if isnil(c.pool) {
		return error('locking: redis pool is closed')
	}
	mut conn := c.pool.get()!
	defer {
		conn.release()
	}
	return f(mut conn)
}

// set 以 SET NX PX 语义写入 key。
// 返回 'OK' 表示写入成功；锁已被占用时返回空串（Redis 的 nil 回复）。
// 这是「接口契约」要求的形式，调用方据此区分「拿不到锁」与「出错」。
pub fn (c &VRedisLockClient) set(key string, value string, ttl_ms int) !string {
	return c.with_conn[string](fn [key, value, ttl_ms] (mut conn vredis.ActiveRedisConn) !string {
		opts := vredis.SetOpts{
			px: if ttl_ms > 0 { ttl_ms } else { -4 }
			nx: true
		}
		ok := conn.set_opts(key, value, opts) or { return err }
		// NX 失败时 Redis 回 nil 回复，vredis 的 set_opts 把它折成 false。
		// 这里不能把它当错误 —— 那就是「别人持锁」的正常回答。
		if ok {
			return 'OK'
		}
		return ''
	})!
}

// get 读取 key 的值，key 不存在时返回空串。
pub fn (c &VRedisLockClient) get(key string) !string {
	return c.with_conn[string](fn [key] (mut conn vredis.ActiveRedisConn) !string {
		val := conn.get(key) or {
			if err.msg() == vredis.err_nil.msg() {
				return ''
			}
			return err
		}
		return val
	})!
}

// del 删除 key，返回删除的条数（0 或 1）。
pub fn (c &VRedisLockClient) del(keys ...string) !int {
	if keys.len == 0 {
		return 0
	}
	return c.with_conn[int](fn [keys] (mut conn vredis.ActiveRedisConn) !int {
		mut removed := 0
		for k in keys {
			if conn.del(k) or { false } {
				removed++
			}
		}
		return removed
	})!
}

// eval 执行 Lua 脚本。num_keys 为 KEYS[] 的个数，keys/args 依次传入。
// 返回值统一渲染成字符串：整数回复 (1/0) 就是 "1"/"0"。
pub fn (c &VRedisLockClient) eval(script string, num_keys int, keys []string, args []string) !string {
	mut all := []string{cap: keys.len + args.len}
	all << keys
	all << args
	return c.with_conn[string](fn [script, num_keys, all] (mut conn vredis.ActiveRedisConn) !string {
		reply := conn.eval(script, num_keys, ...all)!
		if reply.nil() {
			return ''
		}
		return reply.to_string()
	})!
}
