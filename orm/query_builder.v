module orm

// query_builder.v — Fluent Query Builder (Laravel Eloquent / Spring JdbcTemplate inspired)
//
// Provides a chainable query-building API that composes SQL SELECT
// statements with WHERE, ORDER BY, LIMIT, OFFSET, JOIN, and GROUP BY
// clauses.  Terminal methods (get, first, count, exists) execute the
// query against the configured database connection.
//
// Usage:
//   qb := orm.new_query_builder(manager, "default", "users")
//   users := qb.where_("age > ?", 18)
//               .where_("status = ?", "active")
//               .order_by("created_at", .desc)
//               .limit(10)
//               .get()!
//
//   // Chained with eager loading:
//   repo.with("posts").where_("active", true).get()!

// ── Order Direction ──

pub enum OrderDir {
	asc
	desc
}

// ── QueryBuilder ──

// QueryBuilder builds parameterised SQL queries for a single table.
// Methods return &QueryBuilder for fluent chaining.  Terminal methods
// (get, first, count, exists) execute via the configured callbacks.
pub struct QueryBuilder {
pub:
	table_name  string
	orm_manager &OrmManager
	db_name     string = 'default'
pub mut:
	columns    []string   // SELECT columns (default: *)
	wheres     []string   // WHERE conditions
	where_args []string   // positional parameters for WHERE
	orders     []string   // ORDER BY clauses
	joins      []string   // JOIN clauses
	groups     []string   // GROUP BY columns
	havings    []string   // HAVING conditions
	limit_val  int        // LIMIT value (0 = no limit)
	offset_val int        // OFFSET value (0 = no offset)
	query_fn   SqlQueryFn = unsafe { nil } // see safe_cast.v
}

// new_query_builder creates a QueryBuilder for the given table.
// The orm_manager resolves the database connection; query_fn receives
// (db voidptr, query string, args []string) and must return [][]string.
pub fn new_query_builder(manager &OrmManager, db_name string, table string) &QueryBuilder {
	return &QueryBuilder{
		table_name:  table
		orm_manager: manager
		db_name:     db_name
		columns:     ['*']
	}
}

// set_query_fn configures the SQL execution callback.
// query_fn must execute the SELECT and return rows as [][]string.
pub fn (mut qb QueryBuilder) set_query_fn(fn_ SqlQueryFn) &QueryBuilder {
	qb.query_fn = fn_
	return qb
}

// ── Clause Builders (return self for chaining) ──

// select_ sets the columns to retrieve (overrides default '*').
//
//   qb.select_(["id", "name", "email"]) // SELECT id, name, email
//   qb.where_("active", true).select_(["id"])  // SELECT id FROM ... WHERE active = ?
pub fn (mut qb QueryBuilder) select_(cols []string) &QueryBuilder {
	qb.columns = cols
	return qb
}

// where_ adds a WHERE condition with positional parameters.
// Accepts the same `?` placeholder syntax as the underlying SQL driver.
//
//   qb.where_("age > ? and age <= ?", 18, 65)
//   qb.where_("status = ?", "active").where_("role IN (?, ?)", "admin", "moderator")
pub fn (mut qb QueryBuilder) where_(condition string, args ...string) &QueryBuilder {
	qb.wheres << condition
	for arg in args {
		qb.where_args << arg
	}
	return qb
}

// where_in adds a WHERE ... IN (...) clause.
//
//   qb.where_in("status", ["active", "pending"])
pub fn (mut qb QueryBuilder) where_in(column string, values []string) &QueryBuilder {
	if values.len == 0 {
		return qb
	}
	mut placeholders := []string{len: values.len, init: '?'}
	qb.wheres << '${column} IN (${placeholders.join(', ')})'
	for v in values {
		qb.where_args << v
	}
	return qb
}

// where_not_null adds a WHERE ... IS NOT NULL clause.
pub fn (mut qb QueryBuilder) where_not_null(column string) &QueryBuilder {
	qb.wheres << '${column} IS NOT NULL'
	return qb
}

// where_null adds a WHERE ... IS NULL clause.
pub fn (mut qb QueryBuilder) where_null(column string) &QueryBuilder {
	qb.wheres << '${column} IS NULL'
	return qb
}

// where_between adds a WHERE ... BETWEEN ? AND ? clause.
pub fn (mut qb QueryBuilder) where_between(column string, low string, high string) &QueryBuilder {
	qb.wheres << '${column} BETWEEN ? AND ?'
	qb.where_args << low
	qb.where_args << high
	return qb
}

// order_by adds an ORDER BY clause.
//
//   qb.order_by("name")                // ORDER BY name ASC (default)
//   qb.order_by("created_at", .desc)   // ORDER BY created_at DESC
pub fn (mut qb QueryBuilder) order_by(column string, dir OrderDir) &QueryBuilder {
	qb.orders << '${column} ${match dir { .asc { 'ASC' } .desc { 'DESC' } }}'
	return qb
}

// latest orders by the given column descending (shorthand).
// Default column is "created_at".
pub fn (mut qb QueryBuilder) latest(column string) &QueryBuilder {
	return qb.order_by(if column.len > 0 { column } else { 'created_at' }, .desc)
}

// oldest orders by the given column ascending (shorthand).
pub fn (mut qb QueryBuilder) oldest(column string) &QueryBuilder {
	return qb.order_by(if column.len > 0 { column } else { 'created_at' }, .asc)
}

// group_by adds a GROUP BY clause.
pub fn (mut qb QueryBuilder) group_by(columns ...string) &QueryBuilder {
	for col in columns {
		qb.groups << col
	}
	return qb
}

// having adds a HAVING condition.
pub fn (mut qb QueryBuilder) having(condition string, args ...string) &QueryBuilder {
	qb.havings << condition
	for arg in args {
		qb.where_args << arg
	}
	return qb
}

// join adds an INNER JOIN clause.
//
//   qb.join("posts", "posts.user_id = users.id")
pub fn (mut qb QueryBuilder) join(table string, on string) &QueryBuilder {
	qb.joins << 'INNER JOIN ${table} ON ${on}'
	return qb
}

// left_join adds a LEFT JOIN clause.
pub fn (mut qb QueryBuilder) left_join(table string, on string) &QueryBuilder {
	qb.joins << 'LEFT JOIN ${table} ON ${on}'
	return qb
}

// right_join adds a RIGHT JOIN clause.
pub fn (mut qb QueryBuilder) right_join(table string, on string) &QueryBuilder {
	qb.joins << 'RIGHT JOIN ${table} ON ${on}'
	return qb
}

// limit sets the maximum number of rows to return.
//
//   qb.limit(10)                  // LIMIT 10
//   qb.limit(10).offset(20)       // LIMIT 10 OFFSET 20
pub fn (mut qb QueryBuilder) limit(n int) &QueryBuilder {
	qb.limit_val = n
	return qb
}

// offset sets the number of rows to skip.
pub fn (mut qb QueryBuilder) offset(n int) &QueryBuilder {
	qb.offset_val = n
	return qb
}

// page is a convenience for pagination: sets limit + offset in one call.
// page is 1-based.
//
//   qb.page(1, 10)   // LIMIT 10 OFFSET 0
//   qb.page(2, 10)   // LIMIT 10 OFFSET 10
pub fn (mut qb QueryBuilder) page(page_num int, page_size int) &QueryBuilder {
	qb.offset_val = (page_num - 1) * page_size
	qb.limit_val = page_size
	return qb
}

// when applies the callback only if condition is true.
// Laravel equivalent: ->when($condition, fn($q) => $q->where(...))
//
//   qb.when(active_only, fn (mut q QueryBuilder) { q.where_("active", true) })
pub fn (mut qb QueryBuilder) when(condition bool, callback fn (mut QueryBuilder)) &QueryBuilder {
	if condition {
		callback(mut qb)
	}
	return qb
}

// ── Terminal Methods (execute the query) ──

// get executes the SELECT and returns all matching rows.
// Each row is []string with column values in the order of qb.columns.
pub fn (mut qb QueryBuilder) get() ![][]string {
	query, args := qb.build_select()
	db := qb.orm_manager.get_conn(qb.db_name)!
	return qb.query_fn(db, query, args)!
}

// first executes the SELECT with LIMIT 1 and returns the first row.
// Returns an error if no rows match.
pub fn (mut qb QueryBuilder) first() ![]string {
	prev_limit := qb.limit_val
	qb.limit_val = 1
	query, args := qb.build_select()
	qb.limit_val = prev_limit
	db := qb.orm_manager.get_conn(qb.db_name)!
	rows := qb.query_fn(db, query, args)!
	if rows.len == 0 {
		return error('no rows found in ${qb.table_name}')
	}
	return rows[0]
}

// count executes a SELECT COUNT(*) and returns the count.
//
//   n := qb.where_("status = ?", "active").count()!
pub fn (mut qb QueryBuilder) count() !i64 {
	mut qb_copy := &QueryBuilder{
		table_name:  qb.table_name
		orm_manager: qb.orm_manager
		db_name:     qb.db_name
		wheres:      qb.wheres.clone()
		where_args:  qb.where_args.clone()
		joins:       qb.joins.clone()
		havings:     qb.havings.clone()
		groups:      qb.groups.clone()
		query_fn:    qb.query_fn
		columns:     ['COUNT(*) AS cnt']
	}
	query, args := qb_copy.build_select()
	db := qb.orm_manager.get_conn(qb.db_name)!
	rows := qb.query_fn(db, query, args)!
	if rows.len == 0 || rows[0].len == 0 {
		return 0
	}
	return rows[0][0].i64()
}

// exists checks if any rows match the conditions.
//
//   if qb.where_("email = ?", email).exists()! { ... }
pub fn (mut qb QueryBuilder) exists() !bool {
	n := qb.count()!
	return n > 0
}

// pluck retrieves a single column's values as a string list.
//
//   names := qb.where_("active", true).pluck("name")!
pub fn (mut qb QueryBuilder) pluck(column string) ![]string {
	qb.columns = [column]
	rows := qb.get()!
	mut values := []string{cap: rows.len}
	for row in rows {
		if row.len > 0 {
			values << row[0]
		}
	}
	return values
}

// to_sql returns the generated SQL and args (for debugging).
//
//   sql, args := qb.where_("id > ?", 10).limit(5).to_sql()
//   println('SQL: ${sql}  ARGS: ${args}')
pub fn (mut qb QueryBuilder) to_sql() (string, []string) {
	return qb.build_select()
}

// ── Internal SQL Builders ──

// build_select composes the full SELECT statement.
fn (qb &QueryBuilder) build_select() (string, []string) {
	cols := if qb.columns.len > 0 { qb.columns.join(', ') } else { '*' }
	mut sql := 'SELECT ${cols} FROM ${qb.table_name}'

	// JOINs
	for join in qb.joins {
		sql += ' ${join}'
	}

	// WHERE
	if qb.wheres.len > 0 {
		sql += ' WHERE ${qb.wheres.join(' AND ')}'
	}

	// GROUP BY
	if qb.groups.len > 0 {
		sql += ' GROUP BY ${qb.groups.join(', ')}'
	}

	// HAVING
	if qb.havings.len > 0 {
		sql += ' HAVING ${qb.havings.join(' AND ')}'
	}

	// ORDER BY
	if qb.orders.len > 0 {
		sql += ' ORDER BY ${qb.orders.join(', ')}'
	}

	// LIMIT / OFFSET
	if qb.limit_val > 0 {
		sql += ' LIMIT ${qb.limit_val}'
	}
	if qb.offset_val > 0 {
		sql += ' OFFSET ${qb.offset_val}'
	}

	return sql, qb.where_args.clone()
}
