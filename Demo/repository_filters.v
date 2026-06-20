module main

// repository_filters.v — 仓储层升级：过滤查询 + 软删除 + 预加载辅助
//
// 实现内容：
//   1. PostRepository.find_with_filters — 过滤/排序/分页下沉到 SQL（SubTask 12.2）
//   2. UserRepository.find_with_filters — 用户过滤查询（SubTask 12.3）
//   3. CommentRepository.find_by_post_with_filters — 评论过滤查询（SubTask 12.3）
//   4. 软删除支持 — User/Post/Comment 使用 status 软删除（SubTask 12.4/12.5）
//   5. 预加载辅助 — find_post_with_relations 一次性加载 author/category/tags（SubTask 12.1 应用层实现）
//
// 设计说明：
//   框架 orm.EagerRepository[T].find_by_id_with 为 stub（未实现），
//   orm.SoftDeletableEntity 仅实体级方法（无查询自动过滤），
//   本文件在应用层实现等价功能，保持与框架 API 一致的接口风格。
//
// Laravel 等价：Eloquent's with() / where() / softDelete / withTrashed

import time

// ═══════════════════════════════════════════════════════════
// 查询条件结构体
// ═══════════════════════════════════════════════════════════

// PostFilter 文章查询过滤条件
pub struct PostFilter {
pub mut:
	keyword    string // 标题/摘要模糊匹配
	status     string // draft/published/archived/all
	category_id int   // 分类过滤（0 = 不过滤）
	tag_id      int   // 标签过滤（0 = 不过滤）
	author_id   int   // 作者过滤（0 = 不过滤）
}

// UserFilter 用户查询过滤条件
pub struct UserFilter {
pub mut:
	keyword string // 用户名/邮箱模糊匹配
	status  int    // 状态过滤（0 = 不过滤）
	role    string // 角色过滤
}

// CommentFilter 评论查询过滤条件
pub struct CommentFilter {
pub mut:
	status string // visible/hidden/deleted/all
}

// SortDirection 排序方向
pub enum SortDirection {
	asc
	desc
}

// SortSpec 排序规格
pub struct SortSpec {
pub:
	field     string
	direction SortDirection
}

// parse_sort 解析排序字符串（如 "created_at_desc", "title_asc"）
// 默认返回 created_at desc
pub fn parse_sort_spec(sort string) SortSpec {
	if sort.len == 0 {
		return SortSpec{field: 'created_at', direction: .desc}
	}
	parts := sort.split('_')
	if parts.len < 2 {
		return SortSpec{field: 'created_at', direction: .desc}
	}
	// 最后一段是方向：asc/desc
	dir_str := parts[parts.len - 1]
	field := parts[0..parts.len - 1].join('_')
	direction := if dir_str == 'asc' { SortDirection.asc } else { SortDirection.desc }
	return SortSpec{field: field, direction: direction}
}

// sort_clause 生成 SQL ORDER BY 子句
fn (s SortSpec) to_sql() string {
	dir := if s.direction == .asc { 'ASC' } else { 'DESC' }
	return 'ORDER BY ${s.field} ${dir}'
}

// ═══════════════════════════════════════════════════════════
// PostRepository 扩展方法
// ═══════════════════════════════════════════════════════════

// find_with_filters 按条件过滤/排序/分页查询文章
// 返回 (当前页文章, 总数)
pub fn (repo &PostRepository) find_with_filters(filter PostFilter, sort_str string, page int, page_size int) !([]Post, int) {
	mut where_clauses := []string{}
	mut params := []string{}

	// 状态过滤
	if filter.status.len > 0 && filter.status != 'all' {
		where_clauses << 'status = ?'
		params << filter.status
	}

	// 分类过滤
	if filter.category_id > 0 {
		where_clauses << 'category_id = ?'
		params << filter.category_id.str()
	}

	// 作者过滤
	if filter.author_id > 0 {
		where_clauses << 'author_id = ?'
		params << filter.author_id.str()
	}

	// 关键词过滤（标题或摘要模糊匹配）
	if filter.keyword.len > 0 {
		where_clauses << '(title LIKE ? OR summary LIKE ?)'
		keyword_param := '%${filter.keyword}%'
		params << keyword_param
		params << keyword_param
	}

	// 标签过滤（需要子查询）
	if filter.tag_id > 0 {
		where_clauses << 'id IN (SELECT post_id FROM post_tags WHERE tag_id = ?)'
		params << filter.tag_id.str()
	}

	// 构建 WHERE 子句
	where_sql := if where_clauses.len > 0 {
		'WHERE ' + where_clauses.join(' AND ')
	} else {
		''
	}

	// 统计总数
	count_sql := 'SELECT COUNT(*) AS cnt FROM posts ${where_sql}'
	count_rows := repo.db.exec_param_many(count_sql, params.clone())!
	total := if count_rows.len > 0 { count_rows[0].get_int('cnt') } else { 0 }

	// 排序
	sort_spec := parse_sort_spec(sort_str)
	order_sql := sort_spec.to_sql()

	// 分页
	offset := (page - 1) * page_size
	limit_sql := 'LIMIT ${page_size} OFFSET ${offset}'

	// 查询当前页
	query_sql := 'SELECT * FROM posts ${where_sql} ${order_sql} ${limit_sql}'
	rows := repo.db.exec_param_many(query_sql, params)!
	mut result := []Post{}
	for row in rows {
		result << row_to_post(row)
	}

	return result, total
}

// find_post_with_relations 查询文章并预加载关联（author/category/tags）
// 应用层实现预加载，替代框架 EagerRepository stub
pub fn (repo &PostRepository) find_post_with_relations(id int, user_repo &UserRepository, category_repo &CategoryRepository, tag_repo &TagRepository) !(Post, User, Category, []Tag) {
	post := repo.find_by_id(id)!

	// 预加载 author
	mut author := User{}
	if post.author_id > 0 {
		author = user_repo.find_by_id(post.author_id) or { User{} }
	}

	// 预加载 category
	mut category := Category{}
	if post.category_id > 0 {
		category = category_repo.find_by_id(post.category_id) or { Category{} }
	}

	// 预加载 tags
	tags := tag_repo.find_tags_by_post(id) or { []Tag{} }

	return post, author, category, tags
}

// ═══════════════════════════════════════════════════════════
// UserRepository 扩展方法
// ═══════════════════════════════════════════════════════════

// find_with_filters 按条件过滤/排序/分页查询用户
// 返回 (当前页用户, 总数)
pub fn (repo &UserRepository) find_with_filters(filter UserFilter, sort_str string, page int, page_size int) !([]User, int) {
	mut where_clauses := []string{}
	mut params := []string{}

	// 状态过滤
	if filter.status != 0 {
		where_clauses << 'status = ?'
		params << filter.status.str()
	}

	// 角色过滤
	if filter.role.len > 0 {
		where_clauses << 'role = ?'
		params << filter.role
	}

	// 关键词过滤
	if filter.keyword.len > 0 {
		where_clauses << '(username LIKE ? OR email LIKE ?)'
		keyword_param := '%${filter.keyword}%'
		params << keyword_param
		params << keyword_param
	}

	// 构建 WHERE 子句
	where_sql := if where_clauses.len > 0 {
		'WHERE ' + where_clauses.join(' AND ')
	} else {
		''
	}

	// 统计总数
	count_sql := 'SELECT COUNT(*) AS cnt FROM users ${where_sql}'
	count_rows := repo.db.exec_param_many(count_sql, params.clone())!
	total := if count_rows.len > 0 { count_rows[0].get_int('cnt') } else { 0 }

	// 排序
	sort_spec := parse_sort_spec(sort_str)
	order_sql := sort_spec.to_sql()

	// 分页
	offset := (page - 1) * page_size
	limit_sql := 'LIMIT ${page_size} OFFSET ${offset}'

	// 查询当前页
	query_sql := 'SELECT * FROM users ${where_sql} ${order_sql} ${limit_sql}'
	rows := repo.db.exec_param_many(query_sql, params)!
	mut result := []User{}
	for row in rows {
		result << row_to_user(row)
	}

	return result, total
}

// soft_delete 软删除用户（设置 status = -1）
pub fn (mut repo UserRepository) soft_delete(id int) ! {
	params := [(-1).str(), time.now().unix().str(), id.str()]
	repo.db.exec_param_many('UPDATE users SET status = ?, updated_at = ? WHERE id = ?', params)!
}

// restore 恢复软删除的用户
pub fn (mut repo UserRepository) restore(id int) ! {
	params := ['1', time.now().unix().str(), id.str()]
	repo.db.exec_param_many('UPDATE users SET status = ?, updated_at = ? WHERE id = ?', params)!
}

// force_delete 物理删除用户
pub fn (repo &UserRepository) force_delete(id int) ! {
	repo.db.exec_param('DELETE FROM users WHERE id = ?', id.str())!
}

// find_with_trashed 查询包含软删除记录的用户
pub fn (repo &UserRepository) find_with_trashed(id int) !User {
	rows := repo.db.exec_param('SELECT * FROM users WHERE id = ?', id.str())!
	if rows.len == 0 {
		return error('User not found: id=${id}')
	}
	return row_to_user(rows[0])
}

// find_only_trashed 查询仅软删除记录
pub fn (repo &UserRepository) find_only_trashed() ![]User {
	rows := repo.db.exec('SELECT * FROM users WHERE status = -1 ORDER BY id')!
	mut result := []User{}
	for row in rows {
		result << row_to_user(row)
	}
	return result
}

// ═══════════════════════════════════════════════════════════
// CommentRepository 扩展方法
// ═══════════════════════════════════════════════════════════

// find_by_post_with_filters 按条件过滤查询某文章的评论
// 返回 (当前页评论, 总数)
pub fn (repo &CommentRepository) find_by_post_with_filters(post_id int, filter CommentFilter, sort_str string, page int, page_size int) !([]Comment, int) {
	mut where_clauses := ['post_id = ?']
	mut params := [post_id.str()]

	// 状态过滤
	if filter.status.len > 0 && filter.status != 'all' {
		where_clauses << 'status = ?'
		params << filter.status
	}

	where_sql := 'WHERE ' + where_clauses.join(' AND ')

	// 统计总数
	count_sql := 'SELECT COUNT(*) AS cnt FROM comments ${where_sql}'
	count_rows := repo.db.exec_param_many(count_sql, params.clone())!
	total := if count_rows.len > 0 { count_rows[0].get_int('cnt') } else { 0 }

	// 排序（评论默认按时间正序）
	sort_spec := if sort_str.len > 0 { parse_sort_spec(sort_str) } else {
		SortSpec{field: 'created_at', direction: .asc}
	}
	order_sql := sort_spec.to_sql()

	// 分页
	offset := (page - 1) * page_size
	limit_sql := 'LIMIT ${page_size} OFFSET ${offset}'

	// 查询当前页
	query_sql := 'SELECT * FROM comments ${where_sql} ${order_sql} ${limit_sql}'
	rows := repo.db.exec_param_many(query_sql, params)!
	mut result := []Comment{}
	for row in rows {
		result << row_to_comment(row)
	}

	return result, total
}

// soft_delete 软删除评论（设置 status = 'deleted'）
pub fn (mut repo CommentRepository) soft_delete(id int) ! {
	params := ['deleted', time.now().unix().str(), id.str()]
	repo.db.exec_param_many('UPDATE comments SET status = ?, updated_at = ? WHERE id = ?', params)!
}

// restore 恢复软删除的评论
pub fn (mut repo CommentRepository) restore(id int) ! {
	params := ['visible', time.now().unix().str(), id.str()]
	repo.db.exec_param_many('UPDATE comments SET status = ?, updated_at = ? WHERE id = ?', params)!
}

// find_with_trashed 查询包含软删除的评论
pub fn (repo &CommentRepository) find_with_trashed(post_id int) ![]Comment {
	rows := repo.db.exec_param('SELECT * FROM comments WHERE post_id = ? ORDER BY created_at ASC', post_id.str())!
	mut result := []Comment{}
	for row in rows {
		result << row_to_comment(row)
	}
	return result
}

// ═══════════════════════════════════════════════════════════
// PostRepository 软删除扩展
// ═══════════════════════════════════════════════════════════

// soft_delete 软删除文章（设置 status = 'archived'）
pub fn (mut repo PostRepository) soft_delete(id int) ! {
	params := ['archived', time.now().unix().str(), id.str()]
	repo.db.exec_param_many('UPDATE posts SET status = ?, updated_at = ? WHERE id = ?', params)!
}

// restore 恢复软删除的文章
pub fn (mut repo PostRepository) restore(id int) ! {
	params := ['draft', time.now().unix().str(), id.str()]
	repo.db.exec_param_many('UPDATE posts SET status = ?, updated_at = ? WHERE id = ?', params)!
}

// find_only_archived 查询仅归档（软删除）的文章
pub fn (repo &PostRepository) find_only_archived() ![]Post {
	rows := repo.db.exec("SELECT * FROM posts WHERE status = 'archived' ORDER BY id")!
	mut result := []Post{}
	for row in rows {
		result << row_to_post(row)
	}
	return result
}
