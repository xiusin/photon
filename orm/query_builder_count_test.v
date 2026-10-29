module orm

// QueryBuilder 的两个「条件被静默改写」的缺陷：
//   1. where_in 拿到空列表时整条条件被丢掉；
//   2. count() 忽略 GROUP BY，返回的是「第一组的行数」而不是总行数。

__global g_qbc_last_query string
__global g_qbc_last_args []string

fn qbc_reset() {
	unsafe {
		g_qbc_last_query = ''
		g_qbc_last_args = []string{}
	}
}

fn qbc_query(db voidptr, query string, args []string) ![][]string {
	_ = db
	unsafe {
		g_qbc_last_query = query
		g_qbc_last_args = args.clone()
	}
	return [['7']]
}

fn qbc_builder(table string) &QueryBuilder {
	qbc_reset()
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99)) or {}
	mut qb := new_query_builder(om, 'default', table)
	qb.set_query_fn(qbc_query)
	return qb
}

fn test_empty_where_in_matches_nothing() {
	mut qb := qbc_builder('users')
	qb.where_('active = ?', '1')
	qb.where_in('status', []string{})
	qb.count()!
	unsafe {
		// 空列表的本意是「什么都不匹配」。丢掉条件等于「全表」，
		// 调用方拿用户输入拼列表时就会全量泄露。
		assert g_qbc_last_query.contains('1 = 0')
		assert g_qbc_last_args == ['1']
	}
}

fn test_empty_where_in_alone_matches_nothing() {
	mut qb := qbc_builder('users')
	qb.where_in('status', []string{})
	qb.count()!
	unsafe {
		assert g_qbc_last_query.contains('WHERE 1 = 0')
	}
}

fn test_non_empty_where_in_is_unchanged() {
	mut qb := qbc_builder('users')
	qb.where_in('status', ['a', 'b'])
	qb.count()!
	unsafe {
		assert g_qbc_last_query.contains('status IN (?, ?)')
		assert g_qbc_last_args == ['a', 'b']
	}
}

fn test_count_wraps_group_by_in_subquery() {
	mut qb := qbc_builder('orders')
	qb.select_(['user_id'])
	qb.group_by('user_id')
	qb.having('c > ?', '5')
	n := qb.count()!
	assert n == 7
	unsafe {
		// GROUP BY 保留在子查询里，HAVING 引用的别名才能解析；
		// 外层再 COUNT(*)，得到的是「满足条件的组数」。
		assert g_qbc_last_query.starts_with('SELECT COUNT(*) AS cnt FROM (SELECT user_id FROM orders')
		assert g_qbc_last_query.contains('GROUP BY user_id')
		assert g_qbc_last_query.ends_with(') AS photon_count')
		assert g_qbc_last_args == ['5']
	}
}

fn test_count_without_group_by_is_plain() {
	mut qb := qbc_builder('orders')
	qb.where_('status = ?', 'paid')
	n := qb.count()!
	assert n == 7
	unsafe {
		assert g_qbc_last_query == 'SELECT COUNT(*) AS cnt FROM orders WHERE status = ?'
		assert !g_qbc_last_query.contains('AS photon_count')
	}
}
