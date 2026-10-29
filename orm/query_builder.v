module orm

import strings

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
//   // Prefer the shorter, typed facade (table.v):
//   orm.table("users", manager).where("age", ">", 18).limit(10).get()!
//
// ── Guarantees ──
//
//   • Chain-safe: clause builders return `&QueryBuilder` (mutate in place).
//   • Memory-safe: no hidden copies of the receiver; terminal methods work on
//     a private snapshot, so `first()`/`count()` never disturb the builder.
//   • Thread-safe usage: the builder holds no lock — use one per goroutine,
//     or take `.clone()` for branches.  Connections are resolved through the
//     RwMutex-guarded OrmManager on every terminal call.
//   • Injection-safe: values are always bound as `?`; only `where_()` /
//     `join()` / `order_by()` fragments are literal (they are code, not data).

// ── Order Direction ──

pub enum OrderDir {
	asc
	desc
}

// ── QueryBuilder ──

// QueryBuilder builds parameterised SQL queries for a single table.
// Methods return &QueryBuilder for fluent chaining.  Terminal methods
// (get, first, count, exists) execute via the configured callbacks.
//
// @[heap]: every fluent setter hands the builder back by reference, and V
// 0.5.2 refuses to store a pointer to a stack object.
@[heap]
pub struct QueryBuilder {
pub:
	table_name  string
	orm_manager &OrmManager
	db_name     string = 'default'
pub mut:
	columns     []string // SELECT columns (default: *)
	wheres      []string // WHERE conditions
	where_logic []string // 'AND' per condition (AND by default, 'OR' for or_where)
	where_args  []string // positional parameters for WHERE
	orders      []string // ORDER BY clauses
	joins       []string // JOIN clauses
	groups      []string // GROUP BY columns
	havings     []string // HAVING conditions
	limit_val   int      // LIMIT value (0 = no limit)
	offset_val  int      // OFFSET value (0 = no offset)
	query_fn    SqlQueryFn = unsafe { nil } // see safe_cast.v
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
//
// The `_` suffix exists because `where` is a V keyword; `orm.table()` offers
// the same predicate without the suffix.
pub fn (mut qb QueryBuilder) where_(condition string, args ...string) &QueryBuilder {
	if qb.wheres.len > 0 {
		qb.where_logic << 'AND'
	}
	qb.wheres << condition
	for arg in args {
		qb.where_args << arg
	}
	return qb
}

// or_where joins the previous and the new condition with OR instead of AND.
//
//   qb.where_('status = ?', 'active').or_where('status = ?', 'pending')
//   → WHERE (status = ?) OR (status = ?)
pub fn (mut qb QueryBuilder) or_where(condition string, args ...string) &QueryBuilder {
	// where_() records 'AND' for the new condition; overwrite it with 'OR'.
	qb.where_(condition, ...args)
	if qb.wheres.len > 1 && qb.where_logic.len > 0 {
		qb.where_logic[qb.where_logic.len - 1] = 'OR'
	}
	return qb
}

// where_and appends several pre-formatted conditions at once.
//
//   qb.where_and(['age >= ?', 18, 'age <= ?', 65])
pub fn (mut qb QueryBuilder) where_and(parts ...string) &QueryBuilder {
	for part in parts {
		qb.where_('${part}', part)
	}
	return qb
}

// where_in adds a WHERE ... IN (...) clause.
//
//   qb.where_in("status", ["active", "pending"])
//
// An empty list emits `1 = 0`, not nothing. Dropping the clause turned
// "nothing matches the filter" into "the filter does not exist": a caller that
// builds the list from user input silently got every row in the table.
pub fn (mut qb QueryBuilder) where_in(column string, values []string) &QueryBuilder {
	if values.len == 0 {
		if qb.wheres.len > 0 {
			qb.where_logic << 'AND'
		}
		qb.wheres << '1 = 0'
		return qb
	}
	if qb.wheres.len > 0 {
		qb.where_logic << 'AND'
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
	if qb.wheres.len > 0 {
		qb.where_logic << 'AND'
	}
	qb.wheres << '${column} IS NOT NULL'
	return qb
}

// where_null adds a WHERE ... IS NULL clause.
pub fn (mut qb QueryBuilder) where_null(column string) &QueryBuilder {
	if qb.wheres.len > 0 {
		qb.where_logic << 'AND'
	}
	qb.wheres << '${column} IS NULL'
	return qb
}

// where_between adds a WHERE ... BETWEEN ? AND ? clause.
pub fn (mut qb QueryBuilder) where_between(column string, low string, high string) &QueryBuilder {
	if qb.wheres.len > 0 {
		qb.where_logic << 'AND'
	}
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
	qb.orders << '${column} ${match dir {
		.asc { 'ASC' }
		.desc { 'DESC' }
	}}'
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
//
// The builder is not mutated: the LIMIT 1 lives on a temporary copy, so a
// builder can be re-used after calling first().
pub fn (mut qb QueryBuilder) first() ![]string {
	mut view := qb.clone()
	view.limit_val = 1
	query, args := view.build_select()
	db := qb.orm_manager.get_conn(qb.db_name)!
	rows := qb.query_fn(db, query, args)!
	if rows.len == 0 {
		return error('no rows found in ${qb.table_name}')
	}
	return rows[0]
}

// clone returns an independent copy of the builder, for branching a query
// without disturbing the original.
pub fn (qb &QueryBuilder) clone() &QueryBuilder {
	return &QueryBuilder{
		table_name:  qb.table_name
		orm_manager: qb.orm_manager
		db_name:     qb.db_name
		columns:     qb.columns.clone()
		wheres:      qb.wheres.clone()
		where_logic: qb.where_logic.clone()
		where_args:  qb.where_args.clone()
		orders:      qb.orders.clone()
		joins:       qb.joins.clone()
		groups:      qb.groups.clone()
		havings:     qb.havings.clone()
		limit_val:   qb.limit_val
		offset_val:  qb.offset_val
		query_fn:    qb.query_fn
	}
}

// count executes a SELECT COUNT(*) and returns the count.
//
//   n := qb.where_("status = ?", "active").count()!
//
// GROUP BY / HAVING are wrapped in a subquery instead of being dropped.
// `SELECT COUNT(*) ... GROUP BY user_id` counts rows per group — the driver
// hands back the first group's size, not the number of groups. And feeding a
// HAVING that names a projection alias into a COUNT query is a SQL error at
// best; dropping it silently answers a different question than the one asked.
// A paged query asks "how many rows in total", so that is what this returns.
pub fn (mut qb QueryBuilder) count() !i64 {
	mut qb_copy := qb.clone()

	if qb_copy.groups.len > 0 || qb_copy.havings.len > 0 {
		inner, inner_args := qb_copy.build_select()
		query := 'SELECT COUNT(*) AS cnt FROM (${inner}) AS photon_count'
		db := qb.orm_manager.get_conn(qb.db_name)!
		rows := qb.query_fn(db, query, inner_args)!
		if rows.len == 0 || rows[0].len == 0 {
			return 0
		}
		return rows[0][0].i64()
	}

	qb_copy.columns = ['COUNT(*) AS cnt']
	qb_copy.orders = []string{}
	qb_copy.limit_val = 0
	qb_copy.offset_val = 0
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
//
// The builder's own projection is left untouched (a copy is used).
pub fn (mut qb QueryBuilder) pluck(column string) ![]string {
	mut view := qb.clone()
	view.columns = [column]
	rows := view.get()!
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
	mut sb := strings.new_builder(256)
	sb.write_string('SELECT ${cols} FROM ${qb.table_name}')

	// JOINs
	for join in qb.joins {
		sb.write_string(' ${join}')
	}

	// WHERE — consecutive OR-joined conditions are wrapped in parentheses so
	// `a AND b OR c` cannot silently flip the intended precedence.
	if qb.wheres.len > 0 {
		// The WHERE clause is written straight into the statement builder
		// instead of into a throwaway `where_sql` string that gets copied in
		// afterwards — that cost one extra allocation plus a full copy per
		// query.
		//
		// The parenthesisation rule is unchanged and subtle enough to spell
		// out: an OR-run is wrapped as a whole, `(... OR ...)`, including every
		// condition that came before it in the same run. That means the `(`
		// sometimes has to go in front of text already written — which is
		// exactly what the old `where_sql = '(' + where_sql + ' OR ' + cond`
		// did. Here the WHERE prefix is still the tail of the builder when the
		// run opens, so the `(` is emitted by re-writing that prefix. Once any
		// condition follows the prefix this branch is no longer taken (a run
		// only ever opens right after the previous AND), so the argument holds.
		sb.write_string(' WHERE ')
		mut pending := ''
		mut in_or_run := false
		for i, cond in qb.wheres {
			logic := if i == 0 {
				'AND'
			} else if i - 1 < qb.where_logic.len {
				qb.where_logic[i - 1]
			} else {
				'AND'
			}
			if logic == 'OR' {
				if !in_or_run {
					// Opening a run: wrap everything from its first condition.
					// `pending` is that condition, already written right after
					// the `" WHERE "` prefix. Nothing has been written after it
					// (a run only opens on the condition right after it), so
					// the `(` can still be spliced in — the equivalent of the
					// old `where_sql = '(' + where_sql + ' OR ' + cond`.
					if pending.len > 0 {
						sb.go_back(pending.len)
					}
					// `" WHERE "` is still the tail of the builder here — the
					// `(` has to sit in front of it, not behind it.
					sb.go_back(7)
					sb.write_string(' WHERE (')
					sb.write_string(pending)
					pending = ''
					in_or_run = true
				}
				sb.write_string(' OR ')
				sb.write_string(cond)
				continue
			}
			if in_or_run {
				sb.write_u8(`)`)
				in_or_run = false
			}
			if i > 0 {
				sb.write_string(' AND ')
			}
			sb.write_string(cond)
			pending = cond
		}
		if in_or_run {
			sb.write_u8(`)`)
		}
	}

	// GROUP BY
	if qb.groups.len > 0 {
		sb.write_string(' GROUP BY ${qb.groups.join(', ')}')
	}

	// HAVING
	if qb.havings.len > 0 {
		sb.write_string(' HAVING ${qb.havings.join(' AND ')}')
	}

	// ORDER BY
	if qb.orders.len > 0 {
		sb.write_string(' ORDER BY ${qb.orders.join(', ')}')
	}

	// LIMIT / OFFSET
	if qb.limit_val > 0 {
		sb.write_string(' LIMIT ${qb.limit_val}')
	}
	if qb.offset_val > 0 {
		sb.write_string(' OFFSET ${qb.offset_val}')
	}

	return sb.str(), qb.where_args.clone()
}

// ── Repository fluent entry point ──

// repo_query returns a fluent TableQuery bound to the repository's table,
// connection and callbacks — the entity-ordered projection is pre-selected so
// rows can be paged into T with `find_all_with`.
//
//   page := orm.table('users', om).page(2, 10)
//   users := repo.find_all_with(page)!
//
//   users := orm.table('users', om).where_eq('status', 'active').to_entities[T]()!
//
// or start from the repository so the projection, connection and callbacks are
// already wired to the entity:
//
//   users := repo.query().where_eq('status', 'active').limit(10).to_entities[T]()!
//
// V note: Repository[T]'s methods that mention T in their signature cannot be
// declared generic, so this lives on the value receiver `&Repository[T]` and is
// only callable through a pointer.
pub fn repo_query[T](repo &Repository[T]) &TableQuery {
	return &TableQuery{
		table_name:    repo.table_name
		orm_manager:   repo.orm_manager
		db_name:       repo.db_name
		select_cols:   repo.column_names.clone()
		exec_fn:       repo.exec_fn
		exec_typed_fn: repo.exec_typed_fn
		query_fn:      repo.query_fn
	}
}

// Repository.query is a thin alias so call sites read naturally:
//
//   repo := orm.new_entity_repository[User](om, 'default', 'users', exec_fn, query_fn)!
//   users := orm.repo_query(repo).where_eq('status', 'active').to_entities[User]()!
pub fn (repo &Repository[T]) sql_query[T]() &TableQuery {
	return repo_query[T](repo)
}

// to_entities executes the fluent query and maps every row onto T, honouring
// @[column] renames (the projection is the entity's column order).
//
//   users := orm.table('users', om).where_eq('status', 'active').to_entities[T]()!
pub fn (tq &TableQuery) to_entities[T]() ![]T {
	rows := tq.get()!
	mut entities := []T{cap: rows.len}
	for row in rows {
		mut entity := T{}
		jpa_map_row(mut entity, row)
		entities << entity
	}
	return entities
}

// to_entity executes the fluent query with LIMIT 1 and maps the row onto T.
//
//   user := orm.table('users', om).where_eq('email', 'a@b.com').to_entity[T]()!
pub fn (tq &TableQuery) to_entity[T]() !T {
	row := tq.first()!
	mut entity := T{}
	jpa_map_row(mut entity, row)
	return entity
}

// find_all_with pages an arbitrary TableQuery into entities — the escape hatch
// for WHERE trees that the fixed find_by_field() helpers cannot express.
//
//   users := orm.find_all_with(repo, orm.table('users', om).where_eq('status', 'active').page(2, 10))!
pub fn find_all_with[T](repo &Repository[T], tq &TableQuery) ![]T {
	return tq.to_entities[T]()
}
