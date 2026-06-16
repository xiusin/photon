module pool

import orm

// db_pool.v - Database Connection Pool
//
// Specialized connection pool for vorm.Connection instances.
// Provides connection validation, health checking, and multi-driver
// support.

// DbPool wraps a generic Pool for database connections.
pub struct DbPool {
pub mut:
	inner  &Pool
	driver orm.DriverType
}

// new_db_pool creates a new database connection pool with a custom factory.
// The factory function should return a database connection (voidptr).
// For testing, use new_test_db_pool() which creates connections with unique IDs.
pub fn new_db_pool(driver orm.DriverType, min_size int, max_size int, factory fn () !voidptr) &DbPool {
	return &DbPool{
		inner:  new_pool_with_config('db-${driver.str()}', factory, min_size, max_size)
		driver: driver
	}
}

// db_pool_id_counter is used by the test factory to generate unique connection IDs
__global db_pool_id_counter i64

// new_test_db_pool creates a DbPool with a test factory.
// Each connection is a unique voidptr (just a counter value).
// This is suitable for unit testing pool operations without a real database.
pub fn new_test_db_pool(driver orm.DriverType, min_size int, max_size int) &DbPool {
	return new_db_pool(driver, min_size, max_size, fn () !voidptr {
		unsafe {
			db_pool_id_counter++
			return voidptr(db_pool_id_counter)
		}
	})
}

// db_pool_factory creates database connection objects.
// Default factory — returns error instructing to use a real driver factory.
fn db_pool_factory() !voidptr {
	return error('no database driver configured — use new_db_pool(driver, min, max, custom_factory) or new_test_db_pool()')
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

// driver_type returns the pool's driver type.
pub fn (dp &DbPool) driver_type() orm.DriverType {
	return dp.driver
}
