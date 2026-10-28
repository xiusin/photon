module queue

// redis_driver_client.v — 把 vendored 的 xiusin.vredis 接成 QueueRedisClient
//
// RedisDriver 一直是个「接口 + 让用户自己写适配器」的占位：仓库里没有
// 任何实现，new_redis_driver() 在生产代码里调不起来。这里补上开箱可用
// 的适配器，复用 vredis 的连接池。
//
// 两处语义要盯住：
//   * RPOP 空列表返回 nil 回复，必须折成 ''（驱动层据此报 'EMPTY'），
//     不能当成 Redis 故障。
//   * 延迟队列的 zset score 是 unix 纳秒的 f64。f64 只有 53 位尾数，
//     纳秒时间戳（约 1.8e18）会丢精度 —— 所以到期判断带 1ms 容差，
//     否则延迟任务会被判成「还没到期」而永远不执行。
import xiusin.vredis
import time

// VRedisQueueClient 用一个 vredis 连接池为队列驱动提供命令通道。
pub struct VRedisQueueClient {
mut:
	pool &vredis.Pool = unsafe { nil }
}

// VRedisQueueOpt 配置队列驱动的 Redis 连接。
@[params]
pub struct VRedisQueueOpt {
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
}

// new_vredis_queue_client 建立到 Redis 的连接池，并 ping 一次确认可达。
pub fn new_vredis_queue_client(opt VRedisQueueOpt) !&VRedisQueueClient {
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
		return error('queue: redis ping failed for ${opt.host}:${opt.port}')
	}

	pool := vredis.new_pool(vredis.PoolOpt{
		max_active:         if opt.max_active > 0 { opt.max_active } else { 8 }
		idle_timeout:       opt.idle_timeout
		max_conn_life_time: opt.idle_timeout
		dial:               fn [conn_opts] () !&vredis.Redis {
			return vredis.new_client(conn_opts)!
		}
	})!

	return &VRedisQueueClient{
		pool: pool
	}
}

// close 关闭连接池。
pub fn (c &VRedisQueueClient) close() {
	if !isnil(c.pool) {
		c.pool.close()
	}
}

@[inline]
fn (c &VRedisQueueClient) with_conn[T](f fn (mut conn vredis.ActiveRedisConn) !T) !T {
	if isnil(c.pool) {
		return error('queue: redis pool is closed')
	}
	mut conn := c.pool.get()!
	defer {
		conn.release()
	}
	return f(mut conn)
}

// lpush 从列表头插入。
pub fn (c &VRedisQueueClient) lpush(key string, values ...string) !int {
	if values.len == 0 {
		return 0
	}
	return c.with_conn[int](fn [key, values] (mut conn vredis.ActiveRedisConn) !int {
		return conn.lpush(key, values[0], ...values[1..])!
	})!
}

// rpop 从列表尾弹出。空列表返回空串（不是 error）。
pub fn (c &VRedisQueueClient) rpop(key string) !string {
	return c.with_conn[string](fn [key] (mut conn vredis.ActiveRedisConn) !string {
		val := conn.rpop(key) or {
			if err.msg() == vredis.err_nil.msg() {
				return ''
			}
			return err
		}
		return val
	})!
}

// llen 返回列表长度。
pub fn (c &VRedisQueueClient) llen(key string) !int {
	return c.with_conn[int](fn [key] (mut conn vredis.ActiveRedisConn) !int {
		return conn.llen(key)!
	})!
}

// del 删除一个或多个键，返回实际删除的数量。
pub fn (c &VRedisQueueClient) del(keys ...string) !int {
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

// zadd 写入有序集合成员，score 为 run_at（unix 纳秒）。
pub fn (c &VRedisQueueClient) zadd(key string, score f64, member string) !int {
	return c.with_conn[int](fn [key, score, member] (mut conn vredis.ActiveRedisConn) !int {
		return conn.zadd(key, score, member)!
	})!
}

// zrangebyscore 返回 score 落在 [min, max] 的成员，最多 count 个。
pub fn (c &VRedisQueueClient) zrangebyscore(key string, min string, max string, count int) ![]string {
	return c.with_conn[[]string](fn [key, min, max, count] (mut conn vredis.ActiveRedisConn) ![]string {
		opt := vredis.ZrangeOpt{
			offset: 0
			count:  if count > 0 { count } else { 0 }
		}
		return conn.zrangebyscore(key, min, max, opt)!
	})!
}

// zrem 从有序集合移除成员。
pub fn (c &VRedisQueueClient) zrem(key string, member string) !int {
	return c.with_conn[int](fn [key, member] (mut conn vredis.ActiveRedisConn) !int {
		return conn.zrem(key, member)!
	})!
}
