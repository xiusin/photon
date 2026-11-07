module pool

import os

// db_pool_test.v — DbPool 从来没有被测试过，也从来没有被编译过
//
// 它此前只在 TUTORIAL 里有一段示例（`pool.new_db_pool(.sqlite, 2, 10)`），
// 那段既没有枚举上下文、命名空间写法也不对，抽出来实编会直接失败。
// 而它对 `orm.DriverType` 的依赖让整个 pool/ 在下游视角编不过 ——
// 直到有人真的试着编译一次才露出来。

fn test_new_db_pool_keeps_driver_label() {
	dp := new_db_pool('sqlite', 2, 4, fn () !voidptr {
		return voidptr(1)
	})
	assert dp.driver_label() == 'sqlite'
	assert dp.driver_type() == 'sqlite' // 兼容旧名
	assert dp.inner.name == 'db-sqlite'
}

fn test_new_db_pool_uses_label_in_pool_name() {
	for label in ['sqlite', 'postgresql', 'mysql', 'unknown'] {
		dp := new_db_pool(label, 1, 2, fn () !voidptr { return voidptr(1) })
		assert dp.inner.name == 'db-${label}'
	}
}

fn test_db_pool_lifecycle() {
	mut dp := new_test_db_pool('sqlite', 1, 2)
	dp.initialize()!
	c1 := dp.acquire()!
	c2 := dp.acquire()!
	assert c1 != c2, 'test factory 必须给出不同的连接 ID'
	dp.release(c1)
	dp.release(c2)
	st := dp.stats()
	assert st.max == 2
	dp.close()!
}

fn test_db_pool_acquire_after_close_fails() {
	mut dp := new_test_db_pool('pg', 1, 1)
	dp.initialize()!
	dp.close()!
	_ := dp.acquire() or {
		assert err.msg().len > 0
		return
	}
	assert false, '已关闭的池还能 acquire'
}

fn test_db_pool_stats_reflect_inner_pool() {
	mut dp := new_test_db_pool('mysql', 2, 5)
	dp.initialize()!
	assert dp.stats().max == 5
	assert dp.stats().total >= 2
	assert dp.stats().name == 'db-mysql' 
	dp.close()!
}

// test_pool_module_has_no_orm_dependency 顶住「pool/ 重新 import orm」。
// 这是下游 `import photon.pool` 能不能编的唯一开关：裸 `import orm`
// 在下游会落到 vlib/orm（没有 Photon 的 DriverType）。
fn test_pool_module_has_no_orm_dependency() {
	src := os.read_file(os.join_path(os.dir(@DIR), 'pool', 'db_pool.v')) or {
		assert false, 'cannot read pool/db_pool.v'
		return
	}
	// 只看顶格 import 行：注释里会写「为什么这里不 import orm」，
	// 用 contains 全文搜会把注释当成代码，断言恒红。
	mut found := false
	for line in src.split_into_lines() {
		if line.trim_space() == 'import orm' {
			found = true
		}
	}
	assert !found, 'pool/ 又 import orm 了 —— 下游 import photon.pool 会编不过'
}
