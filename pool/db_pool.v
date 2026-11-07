module pool

// db_pool.v - Database Connection Pool
//
// Specialized connection pool for database connections. It wraps the generic
// Pool with a driver label used only for pool naming and diagnostics.
//
// 为什么这里不 import orm
// ----------------------
// `pool` 与 vlib 自带模块重名。下游用户写 `import photon.pool` 时，任何裸
// `import orm` 会落到 vlib/orm（那里没有 Photon 的 DriverType），于是「用户
// 什么都没改，却在自己的构建里收到 pool/db_pool.v 的 unknown type」。
// DbPool 对 orm 的全部使用只是给池起个名字，连 orm.Connection 都不碰 ——
// 这份依赖不属于通用对象池，去掉它 pool/ 才能真正零依赖、从任何视角安全 import。

import sync

// DbPool wraps a generic Pool for database connections.
pub struct DbPool {
pub mut:
	inner  &Pool
	driver string
}

// new_db_pool creates a new database connection pool with a custom factory.
// driver_label names the backend (e.g. 'sqlite', 'postgresql', 'mysql'); it is
// used for the pool name and diagnostics only. The factory returns a database
// connection (voidptr). For testing, use new_test_db_pool().
pub fn new_db_pool(driver_label string, min_size int, max_size int, factory fn () !voidptr) &DbPool {
	return &DbPool{
		inner:  new_pool_with_config('db-${driver_label}', factory, min_size, max_size)
		driver: driver_label
	}
}

// db_pool_id_counter is used by the test factory to generate unique connection IDs.
// Protected by db_pool_id_mu (M3): the counter is incremented from factory
// callbacks that may run concurrently (e.g. pool.initialize() creating multiple
// connections in parallel). Without the mutex, concurrent increments would
// produce duplicate IDs and lost updates.
__global (
	db_pool_id_counter i64
	db_pool_id_mu      sync.Mutex
)

// new_test_db_pool creates a DbPool with a test factory.
// Each connection is a unique voidptr (just a counter value).
// This is suitable for unit testing pool operations without a real database.
pub fn new_test_db_pool(driver_label string, min_size int, max_size int) &DbPool {
	return new_db_pool(driver_label, min_size, max_size, fn () !voidptr {
		db_pool_id_mu.@lock()
		db_pool_id_counter++
		id := db_pool_id_counter
		db_pool_id_mu.unlock()
		return unsafe { voidptr(id) }
	})
}

// initialize prepares the connection pool.
pub fn (mut dp DbPool) initialize() ! {
	dp.inner.initialize()!
}

// acquire gets a database connection from the pool.
pub fn (mut dp DbPool) acquire() !voidptr {
	return dp.inner.acquire()
}

// release returns a connection to the pool.
pub fn (mut dp DbPool) release(conn voidptr) {
	dp.inner.release(conn)
}

// close closes all connections.
pub fn (mut dp DbPool) close() ! {
	dp.inner.close()!
}

// stats returns pool statistics.
pub fn (dp &DbPool) stats() PoolStats {
	return dp.inner.stats()
}

// driver_label returns the pool's driver label.
pub fn (dp &DbPool) driver_label() string {
	return dp.driver
}

// driver_type returns the pool's driver label.
//
// Deprecated: 名字沿用自「DbPool 直接持有 orm.DriverType」的旧实现。去掉
// orm 依赖后返回的是 label 字符串，请改用 driver_label()。保留它是为了
// 不静默打断任何按旧名字书写的调用方。
pub fn (dp &DbPool) driver_type() string {
	return dp.driver
}
