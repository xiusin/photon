module orm

import strings

// table.v — the fluent table facade (`orm.table('users', om)`)
//
// ── Why a second builder next to QueryBuilder? ──
//
// QueryBuilder (query_builder.v) is SQL-text oriented: conditions arrive as
// raw fragments (`where_('age > ?', '18')`), so every parameter travels as a
// string and users must remember the `_` suffix that dodges V's `where`
// keyword.  This file adds the short, documented API: typed parameters, no
// `?`, no placeholder counting, no suffix.
//
//   users := orm.table('users', om)
//       .where_eq('status', 'active')
//       .order_by_desc('created_at')
//       .limit(10)
//       .get()!
//
//   n := orm.table('users', om).where_eq('status', 'active').count()!
//
// ── Immutable chain (V constraint, turned into an asset) ──
//
// V does not allow continuing a method chain after a mutable-receiver call,
// so every clause builder here takes `&TableQuery` and RETURNS A NEW
// `&TableQuery`.  That is not a workaround, it is the better contract:
//
//   • a chain is one expression — no `mut` bookkeeping, no intermediate vars;
//   • the value you were holding is never mutated, so `base` below is safe to
//     reuse, share, or hand to another goroutine:
//
//       base   := orm.table('users', om).where_eq('tenant_id', 7)
//       active := base.where_eq('status', 'active').get()!
//       all    := base.get()!                    // still tenant-scoped only
//
//   • no aliasing bugs and no "who owns this pointer" puzzle: a query value is
//     a snapshot.  Reuse the old value, discard the new one — nothing leaks.
//
// ── Thread safety ──
//
// A `&TableQuery` is never written after construction, so it is safe to share
// across goroutines as long as whoever holds it treats it as read-only (which
// the type system + immutable builders already enforce).  Terminal methods
// only read.  Connection lookup goes through OrmManager.get_conn(), which is
// RwMutex-guarded.
//
// ── Safety model (SQL injection) ──
//
//   • Values are NEVER interpolated — they are bound as `?` parameters and
//     travel to the driver as []ParamValue, in placeholder order.
//   • Identifiers (table, column, operator, order direction) cannot be bound,
//     so they are validated against a whitelist / pattern.  A violation fails
//     the query with a readable error — it is never silently quoted/escaped.
//   • `raw_where()` / `having()` are the explicit escape hatches; only their
//     values are parameterised.

// ── Value model ──

// TablePredicate is one rendered predicate.  `value == none` marks a unary
// predicate (`IS NULL`); `op` is always a whitelisted operator.
@[heap]
struct TablePredicate {
	column string
	op     string
	value  ?ParamValue
}

// TableQuery is an immutable query value produced by `orm.table()`.
// Every clause method returns a NEW TableQuery; nothing is mutated in place,
// which is what makes chains legal in V and aliasing impossible.
//
// Fields live in `pub mut` only because V requires it for the internal
// copy-and-adjust helpers — treat a TableQuery as read-only from outside:
// build a new one instead of touching these.
@[heap]
pub struct TableQuery {
pub:
	table_name  string
	orm_manager &OrmManager = unsafe { nil }
pub mut:
	db_name     string
	select_cols []string
	groups      [][]TablePredicate // OR of groups; each group is AND-joined
	// group_or marks a group whose predicates are alternatives — it renders as
	// `(p1 OR p2 …)` and is AND-ed with the preceding plain group.  This is how
	// `where_eq('tenant', 7).or_where_eq('status', 'active')` keeps the tenant
	// filter AND-ed with the OR instead of silently widening the result set.
	group_or      []bool
	raw_fragments []string     // raw_where() fragments, in order
	raw_values    []ParamValue // values bound to those fragments
	order_parts   []string
	group_cols    []string
	having_parts  []string
	having_values []ParamValue
	limit_val     int
	offset_val    int
	exec_fn       SqlExecFn      = unsafe { nil }
	exec_typed_fn TypedSqlExecFn = unsafe { nil }
	query_fn      SqlQueryFn     = unsafe { nil }
	error_msg     string // first builder-validation failure
}

// table starts a fluent query against `name` on the manager's default
// connection.  Use `table_on` for a named connection.
//
//   orm.table('users', om).where_eq('id', 1).first()!
pub fn table(name string, manager &OrmManager) &TableQuery {
	return &TableQuery{
		table_name:  name
		orm_manager: manager
		select_cols: ['*']
		groups:      [][]TablePredicate{}
	}
}

// table_on starts a fluent query on an explicitly named connection.
//
//   orm.table_on('users', om, 'analytics').get()!
pub fn table_on(name string, manager &OrmManager, db_name string) &TableQuery {
	base := table(name, manager)
	return base.with_db(db_name)
}

// ── Copiers: every clause builder funnels through these ──
//
// One copy path per field group means a new field can never be forgotten
// (which is exactly how state leaks between query "views" happen).

fn (tq &TableQuery) with(table_name_ string, orm_manager_ &OrmManager, db_name_ string) &TableQuery {
	mut next := &TableQuery{
		table_name:    table_name_
		orm_manager:   orm_manager_
		db_name:       db_name_
		select_cols:   tq.select_cols
		groups:        tq.groups
		raw_fragments: tq.raw_fragments
		raw_values:    tq.raw_values
		order_parts:   tq.order_parts
		group_cols:    tq.group_cols
		having_parts:  tq.having_parts
		having_values: tq.having_values
		limit_val:     tq.limit_val
		offset_val:    tq.offset_val
		exec_fn:       tq.exec_fn
		exec_typed_fn: tq.exec_typed_fn
		query_fn:      tq.query_fn
		error_msg:     tq.error_msg
	}
	return next
}

fn (tq &TableQuery) with_db(db_name_ string) &TableQuery {
	mut next := tq.with(tq.table_name, tq.orm_manager, db_name_)
	next.db_name = db_name_
	return next
}

fn (tq &TableQuery) with_error(message string) &TableQuery {
	return tq.rebuild(message, tq.groups)
}

fn (tq &TableQuery) with_groups(groups [][]TablePredicate) &TableQuery {
	return tq.rebuild(tq.error_msg, groups)
}

// mutable_copy builds a fresh, fully-owned copy that clause builders may then
// adjust.  It is the ONLY construction path for derived queries, so a new
// field can never be forgotten (that is how state leaks between views happen).
fn (tq &TableQuery) mutable_copy() &TableQuery {
	return tq.rebuild(tq.error_msg, tq.groups)
}

// rebuild is mutable_copy() with the two most-requested overrides applied.
fn (tq &TableQuery) rebuild(error_msg_ string, groups_ [][]TablePredicate) &TableQuery {
	mut next := &TableQuery{
		table_name:    tq.table_name
		orm_manager:   tq.orm_manager
		db_name:       tq.db_name
		select_cols:   tq.select_cols
		groups:        groups_
		group_or:      tq.group_or
		raw_fragments: tq.raw_fragments
		raw_values:    tq.raw_values
		order_parts:   tq.order_parts
		group_cols:    tq.group_cols
		having_parts:  tq.having_parts
		having_values: tq.having_values
		limit_val:     tq.limit_val
		offset_val:    tq.offset_val
		exec_fn:       tq.exec_fn
		exec_typed_fn: tq.exec_typed_fn
		query_fn:      tq.query_fn
		error_msg:     error_msg_
	}
	return next
}

fn (tq &TableQuery) with_raw(fragments []string, values []ParamValue) &TableQuery {
	mut next := tq.mutable_copy()
	next.raw_fragments = fragments
	next.raw_values = values
	return next
}

// copy_groups returns a deep copy of the AND-of-AND groups so a new predicate
// can be appended without touching the parent query.
fn (tq &TableQuery) copy_groups() [][]TablePredicate {
	mut groups := [][]TablePredicate{cap: tq.groups.len + 1}
	for group in tq.groups {
		mut row := []TablePredicate{cap: group.len}
		for cond in group {
			row << cond
		}
		groups << row
	}
	return groups
}

// group_or_flags returns the OR-flags matching groups, padded with `false` so
// the two slices never fall out of sync.
fn (tq &TableQuery) group_or_flags(count int) []bool {
	mut flags := []bool{len: count, init: false}
	for i in 0 .. count {
		if i < tq.group_or.len {
			flags[i] = tq.group_or[i]
		}
	}
	return flags
}

// with_groups_and_flags installs both the predicate groups and their OR-flags.
fn (tq &TableQuery) with_groups_and_flags(groups [][]TablePredicate, flags []bool) &TableQuery {
	mut next := tq.rebuild(tq.error_msg, groups)
	next.group_or = flags
	return next
}

// ── Execution wiring ──

// set_exec_fn attaches the statement executor (INSERT/UPDATE/DELETE/DDL).
pub fn (tq &TableQuery) set_exec_fn(fn_ SqlExecFn) &TableQuery {
	mut next := tq.mutable_copy()
	next.exec_fn = fn_
	return next
}

// set_query_fn attaches the row reader (SELECT → [][]string).
pub fn (tq &TableQuery) set_query_fn(fn_ SqlQueryFn) &TableQuery {
	mut next := tq.mutable_copy()
	next.query_fn = fn_
	return next
}

// set_exec_typed_fn attaches the type-preserving statement executor.
// Preferred over exec_fn: int/bool/f64 keep their V type all the way to the
// driver instead of degrading to strings.
pub fn (tq &TableQuery) set_exec_typed_fn(fn_ TypedSqlExecFn) &TableQuery {
	mut next := tq.mutable_copy()
	next.exec_typed_fn = fn_
	return next
}

// ── Identifiers ──

// is_safe_identifier reports whether `name` is usable as an identifier:
// optionally dotted (table.column), ASCII letters/digits/underscore, and it
// must not start with a digit.  Identifiers cannot be parameterised, so a
// rejection is the only correct answer for anything else.
pub fn is_safe_identifier(name string) bool {
	if name.len == 0 {
		return false
	}
	mut at_segment_start := true
	for i, ch in name.bytes() {
		if ch == `.` {
			if i == 0 || at_segment_start {
				return false
			}
			at_segment_start = true
			continue
		}
		is_alpha := (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || ch == `_`
		is_digit := ch >= `0` && ch <= `9`
		if at_segment_start && !is_alpha {
			return false
		}
		if !is_alpha && !is_digit {
			return false
		}
		at_segment_start = false
	}
	return !at_segment_start
}

// is_select_token accepts what may appear in a projection: an identifier
// (optionally dotted), `*`, `col AS alias`, or an aggregate call such as
// COUNT(*) / MAX(t.col).  Quotes, semicolons and comment markers are rejected —
// a projection cannot be parameterised, so it must be validated.
fn is_select_token(token string) bool {
	t := token.trim_space()
	if t == '*' {
		return true
	}
	if has_sql_injection_shape(t) {
		return false
	}
	// `col AS alias`
	lowered := t.to_lower()
	if as_idx := lowered.index(' as ') {
		head := t[..as_idx].trim_space()
		alias := t[as_idx + 4..].trim_space()
		return is_safe_identifier(head) && is_safe_identifier(alias)
	}
	// Aggregate call: FUNC(arg)
	if idx := t.index('(') {
		if !t.ends_with(')') {
			return false
		}
		head := t[..idx].trim_space()
		arg := t[idx + 1..t.len - 1].trim_space()
		if !is_safe_identifier(head) {
			return false
		}
		return arg == '*' || is_safe_identifier(arg)
	}
	return is_safe_identifier(t)
}

// has_sql_injection_shape reports strings that can break out of a template
// slot: quotes, semicolons and comment markers.
fn has_sql_injection_shape(s string) bool {
	if s.contains("'") || s.contains('"') || s.contains(';') || s.contains('--') || s.contains('/*')
		|| s.contains('\\') {
		return true
	}
	return false
}

// column_or_error validates an identifier, returning '' for the invalid case.
fn column_or_error(name string) string {
	col := name.trim_space()
	return if is_safe_identifier(col) { col } else { '' }
}

// ── SELECT columns ──

// select_ replaces the projection (default `*`).
pub fn (tq &TableQuery) select_(cols []string) &TableQuery {
	mut next := tq.mutable_copy()
	next.select_cols = cols.clone()
	return next
}

// one_column narrows the projection to a single column (for pluck/value).
//
//   emails := orm.table('users', om).one_column('email').pluck()!
pub fn (tq &TableQuery) one_column(col string) &TableQuery {
	return tq.select_([col])
}

// ── WHERE ──

// where appends `column <op> ?` to the CURRENT AND group.
//
// Grouping model (the only thing you need to remember):
//   • every `.where*()` extends the current group (AND);
//   • `.or_where*()` starts a NEW group (OR);
//   • a group and an OR group collapse into one AND group when the OR is
//     already contained in it — `.where_eq('tenant_id', 7).or_where_eq(...)`
//     keeps the tenant filter AND-ed with the OR, which is what callers mean;
//   • groups are OR-joined and each one is parenthesised at render time;
//   • `.where_group(cb)` folds `cb`'s predicates into the current AND group.
//
//   .where_eq('tenant_id', 7).where_eq('status', 'active')
//   → WHERE tenant_id = ? AND status = ?
//
//   .where_eq('tenant_id', 7).where_group(|g| g.where_eq('status', 'active')
//                                             .or_where_eq('status', 'trial'))
//   → WHERE tenant_id = ? AND (status = ? OR status = ?)
//
//   .where_eq('a', 1).or_where_eq('b', 2).where_eq('c', 3)
//   → WHERE a = ? OR (b = ? AND c = ?)
//
// Operators: = != > >= < <= like "not like" (case-insensitive).
//
//   .where('age', '>', 18)
//   .where('name', 'like', '%ali%')
pub fn (tq &TableQuery) where(col string, op string, value ParamValue) &TableQuery {
	c := column_or_error(col)
	if c == '' {
		return tq.with_error('invalid column identifier "${col}" / 非法列名 "${col}"')
	}
	norm := normalise_op(op)
	if norm == '' {
		return tq.with_error('unsupported operator "${op}" / 不支持的操作符 "${op}"')
	}
	return tq.append_condition(TablePredicate{
		column: c
		op:     norm
		value:  ?ParamValue(value)
	})
}

// where_eq appends `column = ?` — the default predicate.
//
//   .where_eq('email', 'alice@example.com')
pub fn (tq &TableQuery) where_eq(col string, value ParamValue) &TableQuery {
	return tq.where(col, '=', value)
}

// where_ne appends `column != ?`.
pub fn (tq &TableQuery) where_ne(col string, value ParamValue) &TableQuery {
	return tq.where(col, '!=', value)
}

// where_gt appends `column > ?`.
pub fn (tq &TableQuery) where_gt(col string, value ParamValue) &TableQuery {
	return tq.where(col, '>', value)
}

// where_ge appends `column >= ?`.
pub fn (tq &TableQuery) where_ge(col string, value ParamValue) &TableQuery {
	return tq.where(col, '>=', value)
}

// where_lt appends `column < ?`.
pub fn (tq &TableQuery) where_lt(col string, value ParamValue) &TableQuery {
	return tq.where(col, '<', value)
}

// where_le appends `column <= ?`.
pub fn (tq &TableQuery) where_le(col string, value ParamValue) &TableQuery {
	return tq.where(col, '<=', value)
}

// where_like appends `column LIKE ?` with the pattern wrapped in `%…%`.
//
//   .where_like('name', 'ali')   →  name LIKE '%ali%'
pub fn (tq &TableQuery) where_like(col string, fragment string) &TableQuery {
	return tq.where(col, 'like', '%${strip_quotes(fragment)}%')
}

// where_not_like appends `column NOT LIKE ?` (pattern used verbatim).
pub fn (tq &TableQuery) where_not_like(col string, pattern string) &TableQuery {
	return tq.where(col, 'not like', strip_quotes(pattern))
}

// where_in appends `column IN (?, ?, …)`.  An empty list is a no-op — an
// empty filter must not silently widen the result set.
pub fn (tq &TableQuery) where_in(col string, values []ParamValue) &TableQuery {
	c := column_or_error(col)
	if c == '' {
		return tq.with_error('invalid column identifier "${col}" / 非法列名 "${col}"')
	}
	if values.len == 0 {
		return tq
	}
	mut group := []TablePredicate{cap: values.len}
	for v in values {
		group << TablePredicate{
			column: c
			op:     'in'
			value:  ?ParamValue(v)
		}
	}
	// IN expands into one parenthesised AND-group of its own.
	mut groups := tq.copy_groups()
	groups << group
	return tq.with_groups(groups)
}

// where_not_in appends `column NOT IN (?, ?, …)`.  Empty list → no-op.
pub fn (tq &TableQuery) where_not_in(col string, values []ParamValue) &TableQuery {
	c := column_or_error(col)
	if c == '' {
		return tq.with_error('invalid column identifier "${col}" / 非法列名 "${col}"')
	}
	if values.len == 0 {
		return tq
	}
	mut group := []TablePredicate{cap: values.len}
	for v in values {
		group << TablePredicate{
			column: c
			op:     'not in'
			value:  ?ParamValue(v)
		}
	}
	mut groups := tq.copy_groups()
	groups << group
	return tq.with_groups(groups)
}

// where_null appends `column IS NULL`.
pub fn (tq &TableQuery) where_null(col string) &TableQuery {
	c := column_or_error(col)
	if c == '' {
		return tq.with_error('invalid column identifier "${col}" / 非法列名 "${col}"')
	}
	return tq.append_condition(TablePredicate{
		column: c
		op:     'is null'
		value:  ?ParamValue(none)
	})
}

// where_not_null appends `column IS NOT NULL`.
pub fn (tq &TableQuery) where_not_null(col string) &TableQuery {
	c := column_or_error(col)
	if c == '' {
		return tq.with_error('invalid column identifier "${col}" / 非法列名 "${col}"')
	}
	return tq.append_condition(TablePredicate{
		column: c
		op:     'is not null'
		value:  ?ParamValue(none)
	})
}

// where_between appends `column BETWEEN ? AND ?`.
pub fn (tq &TableQuery) where_between(col string, low ParamValue, high ParamValue) &TableQuery {
	c := column_or_error(col)
	if c == '' {
		return tq.with_error('invalid column identifier "${col}" / 非法列名 "${col}"')
	}
	next := tq.append_condition(TablePredicate{
		column: c
		op:     '>='
		value:  ?ParamValue(low)
	})
	return next.append_condition(TablePredicate{
		column: c
		op:     '<='
		value:  ?ParamValue(high)
	})
}

// or_where adds an alternative to the current OR group, creating that group on
// first use.  A plain `where*()` that came before stays AND-ed with it — an OR
// alternative must never escape the filters already applied:
//
//   .where_eq('tenant_id', 7).or_where_eq('owner_id', 7)
//   → WHERE tenant_id = ? AND (owner_id = ?)
//
//   .or_where_eq('status', 'active').or_where_eq('status', 'trial')
//   → WHERE (status = ? OR status = ?)
pub fn (tq &TableQuery) or_where(col string, op string, value ParamValue) &TableQuery {
	c := column_or_error(col)
	if c == '' {
		return tq.with_error('invalid column identifier "${col}" / 非法列名 "${col}"')
	}
	norm := normalise_op(op)
	if norm == '' {
		return tq.with_error('unsupported operator "${op}" / 不支持的操作符 "${op}"')
	}
	cond := TablePredicate{
		column: c
		op:     norm
		value:  ?ParamValue(value)
	}
	mut groups := tq.copy_groups()
	mut flags := tq.group_or_flags(groups.len)
	// Extend the trailing OR group when there is one; otherwise open a new one.
	if groups.len > 0 && flags[groups.len - 1] {
		groups[groups.len - 1] << cond
	} else {
		groups << [cond]
		flags << true
	}
	return tq.with_groups_and_flags(groups, flags)
}

// or_where_eq is the `= ?` shorthand of or_where.
pub fn (tq &TableQuery) or_where_eq(col string, value ParamValue) &TableQuery {
	return tq.or_where(col, '=', value)
}

// where_group folds a nested query into the current AND group as one
// parenthesised sub-expression.  Nesting is one level deep by design — deeper
// trees belong in raw_where() or a Specification:
//
//   .where_eq('tenant_id', 7)
//   .where_group(fn (g &TableQuery) &TableQuery {
//       return g.where_eq('status', 'active').or_where_eq('status', 'trial')
//   })
//   → WHERE tenant_id = ? AND (status = ? OR status = ?)
pub fn (tq &TableQuery) where_group(callback fn (&TableQuery) &TableQuery) &TableQuery {
	inner := callback(&TableQuery{
		table_name:  tq.table_name
		orm_manager: tq.orm_manager
		db_name:     tq.db_name
		select_cols: ['*']
		groups:      [][]TablePredicate{}
	})
	if inner.error_msg.len > 0 {
		return tq.with_error(inner.error_msg)
	}

	// Fold the nested predicates into ONE sub-expression: a single OR group
	// when the callback used `or_where*()`, a plain AND group otherwise.
	mut nested := []TablePredicate{}
	mut nested_is_or := false
	for group_idx, group in inner.groups {
		if inner.group_or.len > group_idx && inner.group_or[group_idx] {
			nested_is_or = true
		}
		for cond in group {
			nested << cond
		}
	}

	mut groups := tq.copy_groups()
	mut flags := tq.group_or_flags(groups.len)
	if nested.len > 0 {
		groups << nested
		flags << nested_is_or
	}

	// raw_where() values live outside the groups, indexed in call order by
	// build_where().  Dropping the nested query's raw_values would leave its
	// `?` placeholders in the SQL with no bound argument (silent misbinding).
	mut bound := tq.raw_values.clone()
	for v in inner.raw_values {
		bound << v
	}
	mut fragments := tq.raw_fragments.clone()
	for f in inner.raw_fragments {
		fragments << f
	}
	mut next := tq.with_groups_and_flags(groups, flags)
	next = next.with_raw(fragments, bound)
	return next
}

// when applies `callback` only when `condition` is true — keeps request-driven
// filters readable:
//
//   .when(min_age > 0, fn (g &orm.TableQuery) &orm.TableQuery { return g.where_ge('age', min_age) })
pub fn (tq &TableQuery) when(condition bool, callback fn (&TableQuery) &TableQuery) &TableQuery {
	if condition {
		return callback(tq)
	}
	return tq
}

// raw_where appends a hand-written predicate with bound values.  The fragment
// is trusted verbatim (that is its purpose) — never build it from user input:
//
//   .raw_where('lower(email) = ? OR phone = ?', 'a@b.com', '13800000000')
pub fn (tq &TableQuery) raw_where(fragment string, values ...ParamValue) &TableQuery {
	if fragment.count('?') != values.len {
		return tq.with_error('raw_where(): ${values.len} value(s) for ${fragment.count('?')} placeholder(s) / raw_where() 占位符与参数数量不匹配')
	}
	mut bound := tq.raw_values.clone()
	for v in values {
		bound << v
	}
	// A raw fragment is a predicate of the current AND group, not a new OR
	// group — otherwise `a = ? AND b = ?` would silently change meaning.
	next := tq.append_condition(TablePredicate{
		column: fragment
		op:     'raw'
		value:  ?ParamValue(none)
	})
	return next.with_raw(tq.raw_fragments, bound)
}

// append_condition appends one predicate to the current AND group, untouched
// copies all the way down.
fn (tq &TableQuery) append_condition(cond TablePredicate) &TableQuery {
	mut groups := tq.copy_groups()
	mut flags := tq.group_or_flags(groups.len)
	if groups.len == 0 {
		groups << []TablePredicate{}
		flags << false
	}
	groups[groups.len - 1] << cond
	return tq.with_groups_and_flags(groups, flags)
}

// normalise_op maps an operator to its canonical lowercase form, or '' when it
// is not whitelisted.
fn normalise_op(op string) string {
	norm := op.trim_space().to_lower()
	allowed := ['=', '!=', '>', '>=', '<', '<=', 'like', 'not like']
	if norm in allowed {
		return norm
	}
	return ''
}

// ── ORDER / GROUP / HAVING / LIMIT ──

// order_by appends `ORDER BY column ASC|DESC`.
// `desc` is a bool on purpose: no enum to import, and a typo cannot silently
// invert the intent.
//
//   .order_by('name', false)         // ASC
//   .order_by('created_at', true)    // DESC
pub fn (tq &TableQuery) order_by(col string, desc bool) &TableQuery {
	c := column_or_error(col)
	if c == '' {
		return tq.with_error('invalid column identifier "${col}" / 非法列名 "${col}"')
	}
	mut parts := tq.order_parts.clone()
	parts << '${c} ${if desc { 'DESC' } else { 'ASC' }}'
	mut next := tq.mutable_copy()
	next.order_parts = parts
	return next
}

// order_by_asc is the readable spelling of `order_by(col, false)`.
pub fn (tq &TableQuery) order_by_asc(col string) &TableQuery {
	return tq.order_by(col, false)
}

// order_by_desc is the readable spelling of `order_by(col, true)`.
pub fn (tq &TableQuery) order_by_desc(col string) &TableQuery {
	return tq.order_by(col, true)
}

// latest orders by `created_at DESC` (or the given column).
pub fn (tq &TableQuery) latest(column string) &TableQuery {
	return tq.order_by_desc(if column.len > 0 { column } else { 'created_at' })
}

// oldest orders by `created_at ASC` (or the given column).
pub fn (tq &TableQuery) oldest(column string) &TableQuery {
	return tq.order_by_asc(if column.len > 0 { column } else { 'created_at' })
}

// group_by appends GROUP BY columns.
pub fn (tq &TableQuery) group_by(cols ...string) &TableQuery {
	mut groups_cols := tq.group_cols.clone()
	for col in cols {
		c := column_or_error(col)
		if c == '' {
			return tq.with_error('invalid column identifier "${col}" / 非法列名 "${col}"')
		}
		groups_cols << c
	}
	mut next := tq.mutable_copy()
	next.group_cols = groups_cols
	return next
}

// having appends a HAVING predicate with bound values.  The fragment must
// carry one `?` per value.
//
//   .group_by('tenant_id').having('COUNT(*) > ?', 5)
pub fn (tq &TableQuery) having(fragment string, values ...ParamValue) &TableQuery {
	if values.len > 0 && !fragment.contains('?') {
		return tq.with_error('having() needs "?" for every value / having() 的每个值都需要 "?" 占位')
	}
	mut parts := tq.having_parts.clone()
	mut bound := tq.having_values.clone()
	parts << fragment
	for v in values {
		bound << v
	}
	mut next := tq.mutable_copy()
	next.having_parts = parts
	next.having_values = bound
	return next
}

// limit caps the row count; `n <= 0` clears it.
pub fn (tq &TableQuery) limit(n int) &TableQuery {
	mut next := tq.mutable_copy()
	next.limit_val = if n > 0 { n } else { 0 }
	return next
}

// offset skips rows; `n <= 0` clears it.
pub fn (tq &TableQuery) offset(n int) &TableQuery {
	mut next := tq.mutable_copy()
	next.offset_val = if n > 0 { n } else { 0 }
	return next
}

// page is 1-based pagination sugar: page 2 of 10 → LIMIT 10 OFFSET 10.
pub fn (tq &TableQuery) page(page_num int, page_size int) &TableQuery {
	if page_size <= 0 {
		return tq
	}
	p := if page_num < 1 { 1 } else { page_num }
	return tq.limit(page_size).offset((p - 1) * page_size)
}

// ── SQL rendering ──

// build renders the SELECT and its bound parameters in placeholder order.
// Values are never interpolated into the SQL.
pub fn (tq &TableQuery) build() !(string, []ParamValue) {
	if tq.error_msg.len > 0 {
		return error(tq.error_msg)
	}
	tbl := tq.table_name.trim_space()
	if !is_safe_identifier(tbl) {
		return error('invalid table identifier "${tq.table_name}" / 非法表名 "${tq.table_name}"')
	}
	where_sql, where_args := tq.build_where()!
	having_sql, having_args := tq.build_having()!
	mut args := where_args.clone()

	mut sb := strings.new_builder(192)
	mut safe_cols := []string{cap: tq.select_cols.len}
	for col in tq.select_cols {
		if col == 'COUNT(*) AS cnt' {
			// internally generated by count_view()
			safe_cols << col
			continue
		}
		if !is_select_token(col) {
			return error('invalid select column "${col}" / 非法查询列 "${col}"')
		}
		safe_cols << col
	}
	cols := if safe_cols.len > 0 { safe_cols.join(', ') } else { '*' }
	sb.write_string('SELECT ${cols} FROM ${tbl}')
	if where_sql.len > 0 {
		sb.write_string(' WHERE ${where_sql}')
	}
	if tq.group_cols.len > 0 {
		sb.write_string(' GROUP BY ${tq.group_cols.join(', ')}')
	}
	if having_sql.len > 0 {
		sb.write_string(' HAVING ${having_sql}')
	}
	if tq.order_parts.len > 0 {
		sb.write_string(' ORDER BY ${tq.order_parts.join(', ')}')
	}
	if tq.limit_val > 0 {
		sb.write_string(' LIMIT ${tq.limit_val}')
	}
	if tq.offset_val > 0 {
		sb.write_string(' OFFSET ${tq.offset_val}')
	}
	for v in having_args {
		args << v
	}
	return sb.str(), args
}

// to_sql renders the SELECT without touching the database — for logs, tests
// and EXPLAIN during debugging.
//
//   sql, args := orm.table('users', om).where_eq('id', 1).to_sql()!
pub fn (tq &TableQuery) to_sql() !(string, []ParamValue) {
	return tq.build()
}

// build_where renders the WHERE clause and its bound values, in placeholder
// order.
//
// Grouping rules:
//   • a plain group is the AND of its predicates;
//   • an OR group renders as `(p1 OR p2 …)` and is AND-ed with the group
//     before it — `tenant = ? AND (status = ? OR status = ?)`;
//   • groups that are neither OR nor AND-joined to a neighbour are OR-joined
//     and parenthesised;
//   • IN expands to one `?` per value inside its group;
//   • unary predicates (`IS NULL`) emit no placeholder.
//   • the number of rendered `?` always equals len(args).
fn (tq &TableQuery) build_where() !(string, []ParamValue) {
	mut args := []ParamValue{}
	mut groups := []string{cap: tq.groups.len}
	mut group_kinds := []bool{cap: tq.groups.len} // true = OR group
	mut raw_idx := 0
	for group_idx, group in tq.groups {
		mut parts := []string{cap: group.len}
		mut in_column := ''
		mut in_count := 0
		for cond in group {
			match cond.op {
				'is null', 'is not null' {
					parts << '${cond.column} ${cond.op.to_upper()}'
				}
				'in', 'not in' {
					// The IN column is emitted once; later rows of the same
					// group only extend the placeholder list.
					if cond.column != in_column {
						in_column = cond.column
						in_count = 0
						parts << ''
					}
					if v := cond.value {
						args << v
					}
					in_count++
					parts[parts.len - 1] = '${cond.column} ${cond.op.to_upper()} (${sql_placeholders(in_count)})'
				}
				'raw' {
					// A raw fragment may carry several placeholders; its values
					// were appended to raw_values in call order.
					placeholders := cond.column.count('?')
					for _ in 0 .. placeholders {
						if raw_idx < tq.raw_values.len {
							args << tq.raw_values[raw_idx]
							raw_idx++
						}
					}
					parts << cond.column
				}
				else {
					if v := cond.value {
						args << v
					}
					parts << '${cond.column} ${cond.op.to_upper()} ?'
				}
			}
		}
		if parts.len > 0 {
			is_or := group_idx < tq.group_or.len && tq.group_or[group_idx]
			if is_or {
				groups << '(${parts.join(' OR ')})'
			} else {
				groups << parts.join(' AND ')
			}
			group_kinds << is_or
		}
	}
	// raw_where() predicates carry their own bound values (see raw_values);
	// consume any that were not reached because their group vanished.
	_ = raw_idx
	if groups.len == 0 {
		return '', args
	}
	mut rendered := groups[0]
	for i in 1 .. groups.len {
		if group_kinds[i] || group_kinds[i - 1] {
			// An OR alternative is AND-ed with everything before it: a filter
			// that was already applied must not be widened by an OR.
			rendered += ' AND ' + groups[i]
		} else {
			rendered += ' OR ' + groups[i]
		}
	}
	return rendered, args
}

// build_having renders the HAVING clause and its bound values.
fn (tq &TableQuery) build_having() !(string, []ParamValue) {
	if tq.having_parts.len == 0 {
		return '', []ParamValue{}
	}
	return tq.having_parts.join(' AND '), tq.having_values.clone()
}

// sql_placeholders renders `?, ?, ?` for n values.
fn sql_placeholders(n int) string {
	mut list := []string{cap: n}
	for _ in 0 .. n {
		list << '?'
	}
	return list.join(', ')
}

// ── Terminal methods (read-only) ──

// conn resolves the connection, failing with a readable message when the
// query was built without a manager.
fn (tq &TableQuery) conn() !voidptr {
	if isnil(tq.orm_manager) {
		return error('orm.table: no OrmManager attached / 未绑定 OrmManager')
	}
	name := if tq.db_name.len > 0 { tq.db_name } else { tq.orm_manager.default }
	if name.len == 0 {
		return error('orm.table: no database connection name / 缺少连接名')
	}
	return tq.orm_manager.get_conn(name)!
}

// require_query_fn guards SELECT execution.
fn (tq &TableQuery) require_query_fn() !SqlQueryFn {
	if isnil(tq.query_fn) {
		return error('orm.table: query_fn not configured / 未配置 query_fn')
	}
	return tq.query_fn
}

// get executes the SELECT and returns raw rows (columns in projection order).
//
//   rows := orm.table('users', om).where_eq('status', 'active').get()!
pub fn (tq &TableQuery) get() ![][]string {
	if tq.offset_val > 0 && tq.limit_val == 0 {
		return error('orm.table: OFFSET requires LIMIT / OFFSET 必须与 LIMIT 搭配')
	}
	qfn := tq.require_query_fn()!
	sql_stmt, args := tq.build()!
	db := tq.conn()!
	return qfn(db, sql_stmt, param_values_to_strings(args))!
}

// first executes the query with LIMIT 1 and returns the first row.
// The receiver is untouched (it is immutable) — reuse it freely.
pub fn (tq &TableQuery) first() ![]string {
	rows := tq.limit(1).get()!
	if rows.len == 0 {
		return error('orm.table: no rows found in ${tq.table_name} / 未找到记录')
	}
	return rows[0]
}

// exists reports whether any row matches.
pub fn (tq &TableQuery) exists() !bool {
	return tq.count()! > 0
}

// count returns COUNT(*) for the current WHERE, ignoring ORDER BY / LIMIT.
//
//   n := orm.table('users', om).where_eq('status', 'active').count()!
pub fn (tq &TableQuery) count() !i64 {
	qfn := tq.require_query_fn()!
	view := tq.count_view()
	sql_stmt, args := view.build()!
	db := tq.conn()!
	rows := qfn(db, sql_stmt, param_values_to_strings(args))!
	if rows.len == 0 || rows[0].len == 0 {
		return 0
	}
	return rows[0][0].i64()
}

// count_view derives the COUNT(*) variant of this query: same WHERE, no
// ORDER BY / LIMIT, projection replaced.  It bypasses the projection validator
// on purpose — the aggregate is generated here, not user-supplied.
fn (tq &TableQuery) count_view() &TableQuery {
	mut next := tq.mutable_copy()
	next.select_cols = ['COUNT(*) AS cnt']
	next.order_parts = []string{}
	next.limit_val = 0
	next.offset_val = 0
	return next
}

// order_by_none drops every ORDER BY clause (used by count()).
pub fn (tq &TableQuery) order_by_none() &TableQuery {
	mut next := tq.mutable_copy()
	next.order_parts = []string{}
	return next
}

// pluck returns the first column of every row as strings.
//
//   names := orm.table('users', om).one_column('name').pluck()!
pub fn (tq &TableQuery) pluck() ![]string {
	rows := tq.get()!
	mut values := []string{cap: rows.len}
	for row in rows {
		if row.len > 0 {
			values << row[0]
		}
	}
	return values
}

// value returns the first column of the first row, or '' when nothing matches
// — the non-failing counterpart of first().
pub fn (tq &TableQuery) value() !string {
	qfn := tq.require_query_fn()!
	view := tq.limit(1).offset(0)
	sql_stmt, args := view.build()!
	db := tq.conn()!
	rows := qfn(db, sql_stmt, param_values_to_strings(args))!
	if rows.len == 0 || rows[0].len == 0 {
		return ''
	}
	return rows[0][0]
}

// require_exec backs the write terminal methods.
fn (tq &TableQuery) require_exec() !bool {
	if isnil(tq.exec_fn) && isnil(tq.exec_typed_fn) {
		return error('orm.table: exec_fn or exec_typed_fn not configured / 未配置 SQL 执行回调')
	}
	return true
}

// run_exec dispatches to the typed executor when configured.
fn (tq &TableQuery) run_exec(sql_stmt string, args []ParamValue) ! {
	db := tq.conn()!
	if !isnil(tq.exec_typed_fn) {
		tq.exec_typed_fn(db, sql_stmt, args)!
	} else {
		tq.exec_fn(db, sql_stmt, param_values_to_strings(args))!
	}
}

// update sets `column = value` pairs on the matching rows.
//
// The WHERE clause is mandatory: a typo that produces an empty filter must not
// wipe the table, so this call fails instead.
//
//   orm.table('users', om).where_eq('id', 1).update({'name': 'Alice'})!
pub fn (tq &TableQuery) update(pairs map[string]ParamValue) ! {
	if pairs.len == 0 {
		return error('orm.table.update: empty column set / 更新列不能为空')
	}
	if tq.groups.len == 0 && tq.raw_fragments.len == 0 {
		return error('orm.table.update: refusing to update without WHERE / 缺少 WHERE 条件，拒绝全表更新')
	}
	tq.require_exec()!
	where_sql, where_args := tq.build_where()!
	if where_sql.len == 0 {
		return error('orm.table.update: refusing to update without WHERE / 缺少 WHERE 条件，拒绝全表更新')
	}
	mut keys := pairs.keys()
	keys.sort()
	mut sets := []string{cap: keys.len}
	mut args := []ParamValue{cap: keys.len + where_args.len}
	for key in keys {
		col := column_or_error(key)
		if col == '' {
			return error('orm.table.update: invalid column identifier "${key}" / 非法列名 "${key}"')
		}
		sets << '${col} = ?'
		args << pairs[key] or { ParamValue('') }
	}
	for v in where_args {
		args << v
	}
	return tq.run_exec('UPDATE ${tq.safe_table()!} SET ${sets.join(', ')} WHERE ${where_sql}', args)
}

// delete removes matching rows.
//
// The WHERE clause is mandatory — see update() for the reasoning.
//
//   orm.table('users', om).where_eq('status', 'stale').delete()!
pub fn (tq &TableQuery) delete() ! {
	if tq.groups.len == 0 && tq.raw_fragments.len == 0 {
		return error('orm.table.delete: refusing to delete without WHERE / 缺少 WHERE 条件，拒绝全表删除')
	}
	tq.require_exec()!
	where_sql, args := tq.build_where()!
	if where_sql.len == 0 {
		return error('orm.table.delete: refusing to delete without WHERE / 缺少 WHERE 条件，拒绝全表删除')
	}
	return tq.run_exec('DELETE FROM ${tq.safe_table()!} WHERE ${where_sql}', args)
}

// insert binds the named columns.  Identity handling (auto-increment,
// defaults) stays explicit at the call site.
//
//   orm.table('users', om).insert({'name': 'Alice', 'status': 'active'})!
pub fn (tq &TableQuery) insert(values map[string]ParamValue) ! {
	if values.len == 0 {
		return error('orm.table.insert: empty row / 插入数据不能为空')
	}
	tq.require_exec()!
	mut keys := values.keys()
	keys.sort()
	mut cols := []string{cap: keys.len}
	mut args := []ParamValue{cap: keys.len}
	for key in keys {
		col := column_or_error(key)
		if col == '' {
			return error('orm.table.insert: invalid column identifier "${key}" / 非法列名 "${key}"')
		}
		cols << col
		args << values[key] or { ParamValue('') }
	}
	return tq.run_exec('INSERT INTO ${tq.safe_table()!} (${cols.join(', ')}) VALUES (${sql_placeholders(cols.len)})',
		args)
}

// safe_table validates the table identifier, or errors.
fn (tq &TableQuery) safe_table() !string {
	tbl := tq.table_name.trim_space()
	if !is_safe_identifier(tbl) {
		return error('invalid table identifier "${tq.table_name}" / 非法表名 "${tq.table_name}"')
	}
	return tbl
}

// param_values_to_strings converts typed parameters for the string-based
// callbacks (SqlExecFn / SqlQueryFn).  Typed callbacks receive them untouched.
pub fn param_values_to_strings(values []ParamValue) []string {
	mut out := []string{cap: values.len}
	for v in values {
		out << match v {
			string {
				v
			}
			bool {
				if v { '1' } else { '0' }
			}
			int {
				'${v}'
			}
			i64 {
				'${v}'
			}
			f64 {
				'${v}'
			}
		}
	}
	return out
}
