module orm

// count_projection_test.v — count() 不能在「投影列」上算错。
//
// count() 的承诺是「有多少行满足条件」。但原来的实现只把 GROUP BY/HAVING
// 包进子查询，直接把投影列换成 `COUNT(*)`：
//
//   qb.select_(['DISTINCT status']).count()
//   → SELECT COUNT(*) AS cnt FROM users      // DISTINCT 被吞掉
//
// 于是去重后的行数变成了总行数。同样是「用 COUNT 覆盖了调用方写的投影」，
// 这里一并锁住两条边界：有投影 / 有 JOIN。

__global g_cpt_query string
__global g_cpt_args []string

fn cpt_query(db voidptr, query string, args []string) ![][]string {
	_ = db
	unsafe {
		g_cpt_query = query
		g_cpt_args = args.clone()
	}
	return [['7']]
}

fn cpt_builder() &QueryBuilder {
	unsafe {
		g_cpt_query = ''
		g_cpt_args = []string{}
	}
	mut om := new_orm_manager()
	om.register_connection('default', .sqlite, voidptr(99)) or {}
	mut qb := new_query_builder(om, 'default', 'users')
	qb.set_query_fn(cpt_query)
	return qb
}

fn test_count_keeps_projection_inside_subquery() {
	mut qb := cpt_builder()
	qb.select_(['DISTINCT status'])
	qb.where_('active = ?', '1')
	n := qb.count()!
	assert n == 7
	// PROJECTION 必须在子查询里，不能被 COUNT(*) 覆盖
	assert unsafe { g_cpt_query } == 'SELECT COUNT(*) AS cnt FROM (SELECT DISTINCT status FROM users WHERE active = ?) AS photon_count'
	assert unsafe { g_cpt_args } == ['1']
}

fn test_count_default_projection_stays_flat() {
	mut qb := cpt_builder()
	qb.where_('status = ?', 'active')
	qb.order_by('id', .desc)
	qb.limit(5)
	n := qb.count()!
	assert n == 7
	// 没有投影、没有 GROUP BY：不额外包一层
	assert unsafe { g_cpt_query } == 'SELECT COUNT(*) AS cnt FROM users WHERE status = ?'
}

fn test_count_keeps_join() {
	mut qb := cpt_builder()
	qb.join('orders', 'orders.user_id = users.id')
	qb.where_('orders.amount > ?', '10')
	_ := qb.count()!
	assert unsafe { g_cpt_query }.contains('INNER JOIN orders ON orders.user_id = users.id')
	assert unsafe { g_cpt_args } == ['10']
}

fn test_count_with_group_by_uses_subquery() {
	mut qb := cpt_builder()
	qb.where_('amount > ?', '100')
	qb.group_by('user_id')
	qb.having('COUNT(*) > 2')
	_ := qb.count()!
	assert unsafe { g_cpt_query } == 'SELECT COUNT(*) AS cnt FROM (SELECT * FROM users WHERE amount > ? GROUP BY user_id HAVING COUNT(*) > 2) AS photon_count'
}
