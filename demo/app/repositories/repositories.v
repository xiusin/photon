module repositories

// repositories.v — PhotonBlog 仓储层
//
// 使用 photon.orm.BaseRepository[T] + OrmAdapter[T] 实现仓储模式。
// 所有 CRUD 回调使用原生 SQL（db.exec_param / exec_param_many / q_int）实现。

import photon.orm as phorm
import db.sqlite
import time
import models
import database

// ═══════════════════════════════════════════════════════════
// UserRepository — 用户仓储
// ═══════════════════════════════════════════════════════════

fn row_to_user(row sqlite.Row) models.User {
	return models.User{
		BaseEntity: phorm.BaseEntity{
			id:         row.get_int('id')
			created_at: i64(row.get_int('created_at'))
			updated_at: i64(row.get_int('updated_at'))
			version:    row.get_int('version')
		}
		username: row.get_string('username')
		email:    row.get_string('email')
		password: row.get_string('password')
		nickname: row.get_string('nickname')
		avatar:   row.get_string('avatar')
		status:   row.get_int('status')
		role:     row.get_string('role')
	}
}

fn user_exec_find(conn voidptr, id int) !models.User {
	db := unsafe { &sqlite.DB(conn) }
	rows := db.exec_param('SELECT * FROM users WHERE id = ?', id.str())!
	if rows.len == 0 {
		return error('User not found: id=${id}')
	}
	return row_to_user(rows[0])
}

fn user_exec_find_all(conn voidptr) ![]models.User {
	db := unsafe { &sqlite.DB(conn) }
	rows := db.exec('SELECT * FROM users ORDER BY id')!
	mut result := []models.User{}
	for row in rows {
		result << row_to_user(row)
	}
	return result
}

fn user_exec_insert(conn voidptr, u models.User) ! {
	db := unsafe { &sqlite.DB(conn) }
	params := [u.username, u.email, u.password, u.nickname, u.avatar,
		u.status.str(), u.role, u.created_at.str(), u.updated_at.str(), u.version.str()]
	db.exec_param_many('INSERT INTO users (username, email, password, nickname, avatar, status, role, created_at, updated_at, version) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', params)!
}

fn user_exec_update(conn voidptr, u models.User) ! {
	db := unsafe { &sqlite.DB(conn) }
	params := [u.username, u.email, u.password, u.nickname, u.avatar,
		u.status.str(), u.role, u.updated_at.str(), u.version.str(), u.id.str()]
	db.exec_param_many('UPDATE users SET username = ?, email = ?, password = ?, nickname = ?, avatar = ?, status = ?, role = ?, updated_at = ?, version = ? WHERE id = ?', params)!
}

fn user_exec_delete(conn voidptr, id int) ! {
	db := unsafe { &sqlite.DB(conn) }
	db.exec_param('DELETE FROM users WHERE id = ?', id.str())!
}

fn user_exec_count(conn voidptr) !int {
	db := unsafe { &sqlite.DB(conn) }
	return db.q_int('SELECT COUNT(*) FROM users')
}

fn user_exec_exists(conn voidptr, id int) bool {
	db := unsafe { &sqlite.DB(conn) }
	rows := db.exec_param('SELECT 1 FROM users WHERE id = ?', id.str()) or { return false }
	return rows.len > 0
}

pub struct UserRepository {
mut:
	base &phorm.BaseRepository[models.User]
	db   &sqlite.DB
}

pub fn new_user_repository(manager &phorm.OrmManager) !&UserRepository {
	db := database.get_db(manager)!
	base := phorm.new_repository[models.User](manager, 'default',
		user_exec_find, user_exec_find_all, user_exec_insert,
		user_exec_update, user_exec_delete, user_exec_count, user_exec_exists)!
	return &UserRepository{
		base: base
		db:   db
	}
}

pub fn (mut repo UserRepository) save(mut user models.User) !models.User {
	was_new := user.is_new()
	repo.base.save(mut user)!
	if was_new {
		user.id = int(repo.db.last_insert_rowid())
	}
	return user
}

pub fn (mut repo UserRepository) find_by_id(id int) !models.User {
	return repo.base.find_by_id(id)!
}

pub fn (mut repo UserRepository) find_all() ![]models.User {
	return repo.base.find_all()!
}

pub fn (mut repo UserRepository) update(mut user models.User) !models.User {
	return repo.base.update(mut user)!
}

pub fn (repo &UserRepository) delete_by_id(id int) ! {
	repo.base.delete_by_id(id)!
}

pub fn (repo &UserRepository) count() !int {
	return repo.base.count()
}

pub fn (repo &UserRepository) exists_by_id(id int) bool {
	return repo.base.exists_by_id(id)
}

pub fn (repo &UserRepository) find_by_username(username string) !models.User {
	rows := repo.db.exec_param('SELECT * FROM users WHERE username = ?', username)!
	if rows.len == 0 {
		return error('User not found: username=${username}')
	}
	return row_to_user(rows[0])
}

pub fn (repo &UserRepository) find_by_email(email string) !models.User {
	rows := repo.db.exec_param('SELECT * FROM users WHERE email = ?', email)!
	if rows.len == 0 {
		return error('User not found: email=${email}')
	}
	return row_to_user(rows[0])
}

pub fn (repo &UserRepository) exists_by_username(username string) bool {
	rows := repo.db.exec_param('SELECT 1 FROM users WHERE username = ?', username) or { return false }
	return rows.len > 0
}

pub fn (repo &UserRepository) exists_by_email(email string) bool {
	rows := repo.db.exec_param('SELECT 1 FROM users WHERE email = ?', email) or { return false }
	return rows.len > 0
}

// find_with_filters 按条件过滤/排序/分页查询用户
pub fn (repo &UserRepository) find_with_filters(filter models.UserFilter, sort_str string, page int, page_size int) !([]models.User, int) {
	mut where_clauses := []string{}
	mut params := []string{}

	if filter.status != 0 {
		where_clauses << 'status = ?'
		params << filter.status.str()
	}
	if filter.role.len > 0 {
		where_clauses << 'role = ?'
		params << filter.role
	}
	if filter.keyword.len > 0 {
		where_clauses << '(username LIKE ? OR email LIKE ?)'
		keyword_param := '%${filter.keyword}%'
		params << keyword_param
		params << keyword_param
	}

	where_sql := if where_clauses.len > 0 {
		'WHERE ' + where_clauses.join(' AND ')
	} else {
		''
	}

	count_sql := 'SELECT COUNT(*) AS cnt FROM users ${where_sql}'
	count_rows := repo.db.exec_param_many(count_sql, params.clone())!
	total := if count_rows.len > 0 { count_rows[0].get_int('cnt') } else { 0 }

	sort_spec := models.parse_sort_spec(sort_str)
	order_sql := sort_spec.to_sql()

	offset := (page - 1) * page_size
	limit_sql := 'LIMIT ${page_size} OFFSET ${offset}'

	query_sql := 'SELECT * FROM users ${where_sql} ${order_sql} ${limit_sql}'
	rows := repo.db.exec_param_many(query_sql, params)!
	mut result := []models.User{}
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
pub fn (repo &UserRepository) find_with_trashed(id int) !models.User {
	rows := repo.db.exec_param('SELECT * FROM users WHERE id = ?', id.str())!
	if rows.len == 0 {
		return error('User not found: id=${id}')
	}
	return row_to_user(rows[0])
}

// find_only_trashed 查询仅软删除记录
pub fn (repo &UserRepository) find_only_trashed() ![]models.User {
	rows := repo.db.exec('SELECT * FROM users WHERE status = -1 ORDER BY id')!
	mut result := []models.User{}
	for row in rows {
		result << row_to_user(row)
	}
	return result
}

// ═══════════════════════════════════════════════════════════
// PostRepository — 文章仓储
// ═══════════════════════════════════════════════════════════

fn row_to_post(row sqlite.Row) models.Post {
	return models.Post{
		BaseEntity: phorm.BaseEntity{
			id:         row.get_int('id')
			created_at: i64(row.get_int('created_at'))
			updated_at: i64(row.get_int('updated_at'))
			version:    row.get_int('version')
		}
		title:       row.get_string('title')
		content:     row.get_string('content')
		summary:     row.get_string('summary')
		author_id:   row.get_int('author_id')
		category_id: row.get_int('category_id')
		status:      row.get_string('status')
		views:       row.get_int('views')
	}
}

fn post_exec_find(conn voidptr, id int) !models.Post {
	db := unsafe { &sqlite.DB(conn) }
	rows := db.exec_param('SELECT * FROM posts WHERE id = ?', id.str())!
	if rows.len == 0 {
		return error('Post not found: id=${id}')
	}
	return row_to_post(rows[0])
}

fn post_exec_find_all(conn voidptr) ![]models.Post {
	db := unsafe { &sqlite.DB(conn) }
	rows := db.exec('SELECT * FROM posts ORDER BY id')!
	mut result := []models.Post{}
	for row in rows {
		result << row_to_post(row)
	}
	return result
}

fn post_exec_insert(conn voidptr, p models.Post) ! {
	db := unsafe { &sqlite.DB(conn) }
	params := [p.title, p.content, p.summary, p.author_id.str(), p.category_id.str(),
		p.status, p.views.str(), p.created_at.str(), p.updated_at.str(), p.version.str()]
	db.exec_param_many('INSERT INTO posts (title, content, summary, author_id, category_id, status, views, created_at, updated_at, version) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', params)!
}

fn post_exec_update(conn voidptr, p models.Post) ! {
	db := unsafe { &sqlite.DB(conn) }
	params := [p.title, p.content, p.summary, p.author_id.str(), p.category_id.str(),
		p.status, p.views.str(), p.updated_at.str(), p.version.str(), p.id.str()]
	db.exec_param_many('UPDATE posts SET title = ?, content = ?, summary = ?, author_id = ?, category_id = ?, status = ?, views = ?, updated_at = ?, version = ? WHERE id = ?', params)!
}

fn post_exec_delete(conn voidptr, id int) ! {
	db := unsafe { &sqlite.DB(conn) }
	db.exec_param('DELETE FROM posts WHERE id = ?', id.str())!
}

fn post_exec_count(conn voidptr) !int {
	db := unsafe { &sqlite.DB(conn) }
	return db.q_int('SELECT COUNT(*) FROM posts')
}

fn post_exec_exists(conn voidptr, id int) bool {
	db := unsafe { &sqlite.DB(conn) }
	rows := db.exec_param('SELECT 1 FROM posts WHERE id = ?', id.str()) or { return false }
	return rows.len > 0
}

pub struct PostRepository {
mut:
	base &phorm.BaseRepository[models.Post]
	db   &sqlite.DB
}

pub fn new_post_repository(manager &phorm.OrmManager) !&PostRepository {
	db := database.get_db(manager)!
	base := phorm.new_repository[models.Post](manager, 'default',
		post_exec_find, post_exec_find_all, post_exec_insert,
		post_exec_update, post_exec_delete, post_exec_count, post_exec_exists)!
	return &PostRepository{
		base: base
		db:   db
	}
}

pub fn (mut repo PostRepository) save(mut post models.Post) !models.Post {
	was_new := post.is_new()
	repo.base.save(mut post)!
	if was_new {
		post.id = int(repo.db.last_insert_rowid())
	}
	return post
}

pub fn (mut repo PostRepository) find_by_id(id int) !models.Post {
	return repo.base.find_by_id(id)!
}

pub fn (mut repo PostRepository) find_all() ![]models.Post {
	return repo.base.find_all()!
}

pub fn (mut repo PostRepository) update(mut post models.Post) !models.Post {
	return repo.base.update(mut post)!
}

pub fn (repo &PostRepository) delete_by_id(id int) ! {
	repo.base.delete_by_id(id)!
}

pub fn (repo &PostRepository) count() !int {
	return repo.base.count()
}

pub fn (repo &PostRepository) exists_by_id(id int) bool {
	return repo.base.exists_by_id(id)
}

pub fn (repo &PostRepository) find_by_author(author_id int) ![]models.Post {
	rows := repo.db.exec_param('SELECT * FROM posts WHERE author_id = ? ORDER BY created_at DESC', author_id.str())!
	mut result := []models.Post{}
	for row in rows {
		result << row_to_post(row)
	}
	return result
}

pub fn (repo &PostRepository) find_by_category(category_id int) ![]models.Post {
	rows := repo.db.exec_param('SELECT * FROM posts WHERE category_id = ? ORDER BY created_at DESC', category_id.str())!
	mut result := []models.Post{}
	for row in rows {
		result << row_to_post(row)
	}
	return result
}

pub fn (repo &PostRepository) find_by_status(status string) ![]models.Post {
	rows := repo.db.exec_param('SELECT * FROM posts WHERE status = ? ORDER BY created_at DESC', status)!
	mut result := []models.Post{}
	for row in rows {
		result << row_to_post(row)
	}
	return result
}

pub fn (repo &PostRepository) find_published() ![]models.Post {
	return repo.find_by_status('published')
}

pub fn (repo &PostRepository) increment_views(id int) ! {
	_ = repo.db.exec_param('UPDATE posts SET views = views + 1 WHERE id = ?', id.str())!
}

pub fn (repo &PostRepository) count_by_status(status string) !int {
	rows := repo.db.exec_param('SELECT COUNT(*) AS cnt FROM posts WHERE status = ?', status)!
	if rows.len == 0 {
		return 0
	}
	return rows[0].get_int('cnt')
}

// find_with_filters 按条件过滤/排序/分页查询文章
pub fn (repo &PostRepository) find_with_filters(filter models.PostFilter, sort_str string, page int, page_size int) !([]models.Post, int) {
	mut where_clauses := []string{}
	mut params := []string{}

	if filter.status.len > 0 && filter.status != 'all' {
		where_clauses << 'status = ?'
		params << filter.status
	}
	if filter.category_id > 0 {
		where_clauses << 'category_id = ?'
		params << filter.category_id.str()
	}
	if filter.author_id > 0 {
		where_clauses << 'author_id = ?'
		params << filter.author_id.str()
	}
	if filter.keyword.len > 0 {
		where_clauses << '(title LIKE ? OR summary LIKE ?)'
		keyword_param := '%${filter.keyword}%'
		params << keyword_param
		params << keyword_param
	}
	if filter.tag_id > 0 {
		where_clauses << 'id IN (SELECT post_id FROM post_tags WHERE tag_id = ?)'
		params << filter.tag_id.str()
	}

	where_sql := if where_clauses.len > 0 {
		'WHERE ' + where_clauses.join(' AND ')
	} else {
		''
	}

	count_sql := 'SELECT COUNT(*) AS cnt FROM posts ${where_sql}'
	count_rows := repo.db.exec_param_many(count_sql, params.clone())!
	total := if count_rows.len > 0 { count_rows[0].get_int('cnt') } else { 0 }

	sort_spec := models.parse_sort_spec(sort_str)
	order_sql := sort_spec.to_sql()

	offset := (page - 1) * page_size
	limit_sql := 'LIMIT ${page_size} OFFSET ${offset}'

	query_sql := 'SELECT * FROM posts ${where_sql} ${order_sql} ${limit_sql}'
	rows := repo.db.exec_param_many(query_sql, params)!
	mut result := []models.Post{}
	for row in rows {
		result << row_to_post(row)
	}

	return result, total
}

// find_post_with_relations 查询文章并预加载关联
pub fn (mut repo PostRepository) find_post_with_relations(id int, mut user_repo UserRepository, mut category_repo CategoryRepository, mut tag_repo TagRepository) !(models.Post, models.User, models.Category, []models.Tag) {
	post := repo.find_by_id(id)!

	mut author := models.User{}
	if post.author_id > 0 {
		author = user_repo.find_by_id(post.author_id) or { models.User{} }
	}

	mut category := models.Category{}
	if post.category_id > 0 {
		category = category_repo.find_by_id(post.category_id) or { models.Category{} }
	}

	tags := tag_repo.find_tags_by_post(id) or { []models.Tag{} }

	return post, author, category, tags
}

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
pub fn (repo &PostRepository) find_only_archived() ![]models.Post {
	rows := repo.db.exec("SELECT * FROM posts WHERE status = 'archived' ORDER BY id")!
	mut result := []models.Post{}
	for row in rows {
		result << row_to_post(row)
	}
	return result
}

// ═══════════════════════════════════════════════════════════
// CommentRepository — 评论仓储
// ═══════════════════════════════════════════════════════════

fn row_to_comment(row sqlite.Row) models.Comment {
	return models.Comment{
		BaseEntity: phorm.BaseEntity{
			id:         row.get_int('id')
			created_at: i64(row.get_int('created_at'))
			updated_at: i64(row.get_int('updated_at'))
			version:    row.get_int('version')
		}
		post_id:   row.get_int('post_id')
		user_id:   row.get_int('user_id')
		content:   row.get_string('content')
		parent_id: row.get_int('parent_id')
		status:    row.get_string('status')
	}
}

fn comment_exec_find(conn voidptr, id int) !models.Comment {
	db := unsafe { &sqlite.DB(conn) }
	rows := db.exec_param('SELECT * FROM comments WHERE id = ?', id.str())!
	if rows.len == 0 {
		return error('Comment not found: id=${id}')
	}
	return row_to_comment(rows[0])
}

fn comment_exec_find_all(conn voidptr) ![]models.Comment {
	db := unsafe { &sqlite.DB(conn) }
	rows := db.exec('SELECT * FROM comments ORDER BY id')!
	mut result := []models.Comment{}
	for row in rows {
		result << row_to_comment(row)
	}
	return result
}

fn comment_exec_insert(conn voidptr, c models.Comment) ! {
	db := unsafe { &sqlite.DB(conn) }
	params := [c.post_id.str(), c.user_id.str(), c.content, c.parent_id.str(),
		c.status, c.created_at.str(), c.updated_at.str(), c.version.str()]
	db.exec_param_many('INSERT INTO comments (post_id, user_id, content, parent_id, status, created_at, updated_at, version) VALUES (?, ?, ?, ?, ?, ?, ?, ?)', params)!
}

fn comment_exec_update(conn voidptr, c models.Comment) ! {
	db := unsafe { &sqlite.DB(conn) }
	params := [c.post_id.str(), c.user_id.str(), c.content, c.parent_id.str(),
		c.status, c.updated_at.str(), c.version.str(), c.id.str()]
	db.exec_param_many('UPDATE comments SET post_id = ?, user_id = ?, content = ?, parent_id = ?, status = ?, updated_at = ?, version = ? WHERE id = ?', params)!
}

fn comment_exec_delete(conn voidptr, id int) ! {
	db := unsafe { &sqlite.DB(conn) }
	db.exec_param('DELETE FROM comments WHERE id = ?', id.str())!
}

fn comment_exec_count(conn voidptr) !int {
	db := unsafe { &sqlite.DB(conn) }
	return db.q_int('SELECT COUNT(*) FROM comments')
}

fn comment_exec_exists(conn voidptr, id int) bool {
	db := unsafe { &sqlite.DB(conn) }
	rows := db.exec_param('SELECT 1 FROM comments WHERE id = ?', id.str()) or { return false }
	return rows.len > 0
}

pub struct CommentRepository {
mut:
	base &phorm.BaseRepository[models.Comment]
	db   &sqlite.DB
}

pub fn new_comment_repository(manager &phorm.OrmManager) !&CommentRepository {
	db := database.get_db(manager)!
	base := phorm.new_repository[models.Comment](manager, 'default',
		comment_exec_find, comment_exec_find_all, comment_exec_insert,
		comment_exec_update, comment_exec_delete, comment_exec_count, comment_exec_exists)!
	return &CommentRepository{
		base: base
		db:   db
	}
}

pub fn (mut repo CommentRepository) save(mut comment models.Comment) !models.Comment {
	was_new := comment.is_new()
	repo.base.save(mut comment)!
	if was_new {
		comment.id = int(repo.db.last_insert_rowid())
	}
	return comment
}

pub fn (mut repo CommentRepository) find_by_id(id int) !models.Comment {
	return repo.base.find_by_id(id)!
}

pub fn (mut repo CommentRepository) find_all() ![]models.Comment {
	return repo.base.find_all()!
}

pub fn (mut repo CommentRepository) update(mut comment models.Comment) !models.Comment {
	return repo.base.update(mut comment)!
}

pub fn (repo &CommentRepository) delete_by_id(id int) ! {
	repo.base.delete_by_id(id)!
}

pub fn (repo &CommentRepository) count() !int {
	return repo.base.count()
}

pub fn (repo &CommentRepository) exists_by_id(id int) bool {
	return repo.base.exists_by_id(id)
}

pub fn (repo &CommentRepository) find_by_post(post_id int) ![]models.Comment {
	rows := repo.db.exec_param('SELECT * FROM comments WHERE post_id = ? ORDER BY created_at ASC', post_id.str())!
	mut result := []models.Comment{}
	for row in rows {
		result << row_to_comment(row)
	}
	return result
}

pub fn (repo &CommentRepository) find_by_parent(parent_id int) ![]models.Comment {
	rows := repo.db.exec_param('SELECT * FROM comments WHERE parent_id = ? ORDER BY created_at ASC', parent_id.str())!
	mut result := []models.Comment{}
	for row in rows {
		result << row_to_comment(row)
	}
	return result
}

pub fn (repo &CommentRepository) count_by_post(post_id int) !int {
	rows := repo.db.exec_param('SELECT COUNT(*) AS cnt FROM comments WHERE post_id = ?', post_id.str())!
	if rows.len == 0 {
		return 0
	}
	return rows[0].get_int('cnt')
}

pub fn (repo &CommentRepository) touch_post(post_id int) ! {
	now := time.now().unix().str()
	repo.db.exec_param_many('UPDATE posts SET updated_at = ? WHERE id = ?', [now, post_id.str()])!
}

// find_with_filters 按条件过滤查询评论
pub fn (repo &CommentRepository) find_with_filters(filter models.CommentFilter, sort_str string, page int, page_size int) !([]models.Comment, int) {
	mut where_clauses := []string{}
	mut params := []string{}

	if filter.post_id > 0 {
		where_clauses << 'post_id = ?'
		params << filter.post_id.str()
	}
	if filter.status.len > 0 && filter.status != 'all' {
		where_clauses << 'status = ?'
		params << filter.status
	}

	where_sql := if where_clauses.len > 0 {
		'WHERE ' + where_clauses.join(' AND ')
	} else {
		''
	}

	count_sql := 'SELECT COUNT(*) AS cnt FROM comments ${where_sql}'
	count_rows := repo.db.exec_param_many(count_sql, params.clone())!
	total := if count_rows.len > 0 { count_rows[0].get_int('cnt') } else { 0 }

	sort_spec := if sort_str.len > 0 { models.parse_sort_spec(sort_str) } else {
		models.SortSpec{field: 'created_at', direction: .asc}
	}
	order_sql := sort_spec.to_sql()

	offset := (page - 1) * page_size
	limit_sql := 'LIMIT ${page_size} OFFSET ${offset}'

	query_sql := 'SELECT * FROM comments ${where_sql} ${order_sql} ${limit_sql}'
	rows := repo.db.exec_param_many(query_sql, params)!
	mut result := []models.Comment{}
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
pub fn (repo &CommentRepository) find_with_trashed(post_id int) ![]models.Comment {
	rows := repo.db.exec_param('SELECT * FROM comments WHERE post_id = ? ORDER BY created_at ASC', post_id.str())!
	mut result := []models.Comment{}
	for row in rows {
		result << row_to_comment(row)
	}
	return result
}

// ═══════════════════════════════════════════════════════════
// CategoryRepository — 分类仓储
// ═══════════════════════════════════════════════════════════

fn row_to_category(row sqlite.Row) models.Category {
	return models.Category{
		BaseEntity: phorm.BaseEntity{
			id:         row.get_int('id')
			created_at: i64(row.get_int('created_at'))
			updated_at: i64(row.get_int('updated_at'))
			version:    row.get_int('version')
		}
		name:        row.get_string('name')
		slug:        row.get_string('slug')
		description: row.get_string('description')
	}
}

fn category_exec_find(conn voidptr, id int) !models.Category {
	db := unsafe { &sqlite.DB(conn) }
	rows := db.exec_param('SELECT * FROM categories WHERE id = ?', id.str())!
	if rows.len == 0 {
		return error('Category not found: id=${id}')
	}
	return row_to_category(rows[0])
}

fn category_exec_find_all(conn voidptr) ![]models.Category {
	db := unsafe { &sqlite.DB(conn) }
	rows := db.exec('SELECT * FROM categories ORDER BY id')!
	mut result := []models.Category{}
	for row in rows {
		result << row_to_category(row)
	}
	return result
}

fn category_exec_insert(conn voidptr, c models.Category) ! {
	db := unsafe { &sqlite.DB(conn) }
	params := [c.name, c.slug, c.description, c.created_at.str(), c.updated_at.str(), c.version.str()]
	db.exec_param_many('INSERT INTO categories (name, slug, description, created_at, updated_at, version) VALUES (?, ?, ?, ?, ?, ?)', params)!
}

fn category_exec_update(conn voidptr, c models.Category) ! {
	db := unsafe { &sqlite.DB(conn) }
	params := [c.name, c.slug, c.description, c.updated_at.str(), c.version.str(), c.id.str()]
	db.exec_param_many('UPDATE categories SET name = ?, slug = ?, description = ?, updated_at = ?, version = ? WHERE id = ?', params)!
}

fn category_exec_delete(conn voidptr, id int) ! {
	db := unsafe { &sqlite.DB(conn) }
	db.exec_param('DELETE FROM categories WHERE id = ?', id.str())!
}

fn category_exec_count(conn voidptr) !int {
	db := unsafe { &sqlite.DB(conn) }
	return db.q_int('SELECT COUNT(*) FROM categories')
}

fn category_exec_exists(conn voidptr, id int) bool {
	db := unsafe { &sqlite.DB(conn) }
	rows := db.exec_param('SELECT 1 FROM categories WHERE id = ?', id.str()) or { return false }
	return rows.len > 0
}

pub struct CategoryRepository {
mut:
	base &phorm.BaseRepository[models.Category]
	db   &sqlite.DB
}

pub fn new_category_repository(manager &phorm.OrmManager) !&CategoryRepository {
	db := database.get_db(manager)!
	base := phorm.new_repository[models.Category](manager, 'default',
		category_exec_find, category_exec_find_all, category_exec_insert,
		category_exec_update, category_exec_delete, category_exec_count, category_exec_exists)!
	return &CategoryRepository{
		base: base
		db:   db
	}
}

pub fn (mut repo CategoryRepository) save(mut category models.Category) !models.Category {
	was_new := category.is_new()
	repo.base.save(mut category)!
	if was_new {
		category.id = int(repo.db.last_insert_rowid())
	}
	return category
}

pub fn (mut repo CategoryRepository) find_by_id(id int) !models.Category {
	return repo.base.find_by_id(id)!
}

pub fn (mut repo CategoryRepository) find_all() ![]models.Category {
	return repo.base.find_all()!
}

pub fn (mut repo CategoryRepository) update(mut category models.Category) !models.Category {
	return repo.base.update(mut category)!
}

pub fn (repo &CategoryRepository) delete_by_id(id int) ! {
	repo.base.delete_by_id(id)!
}

pub fn (repo &CategoryRepository) count() !int {
	return repo.base.count()
}

pub fn (repo &CategoryRepository) exists_by_id(id int) bool {
	return repo.base.exists_by_id(id)
}

pub fn (repo &CategoryRepository) find_by_slug(slug string) !models.Category {
	rows := repo.db.exec_param('SELECT * FROM categories WHERE slug = ?', slug)!
	if rows.len == 0 {
		return error('Category not found: slug=${slug}')
	}
	return row_to_category(rows[0])
}

pub fn (repo &CategoryRepository) exists_by_slug(slug string) bool {
	rows := repo.db.exec_param('SELECT 1 FROM categories WHERE slug = ?', slug) or { return false }
	return rows.len > 0
}

// ═══════════════════════════════════════════════════════════
// TagRepository — 标签仓储
// ═══════════════════════════════════════════════════════════

fn row_to_tag(row sqlite.Row) models.Tag {
	return models.Tag{
		BaseEntity: phorm.BaseEntity{
			id:         row.get_int('id')
			created_at: i64(row.get_int('created_at'))
			updated_at: i64(row.get_int('updated_at'))
			version:    row.get_int('version')
		}
		name: row.get_string('name')
		slug: row.get_string('slug')
	}
}

fn tag_exec_find(conn voidptr, id int) !models.Tag {
	db := unsafe { &sqlite.DB(conn) }
	rows := db.exec_param('SELECT * FROM tags WHERE id = ?', id.str())!
	if rows.len == 0 {
		return error('Tag not found: id=${id}')
	}
	return row_to_tag(rows[0])
}

fn tag_exec_find_all(conn voidptr) ![]models.Tag {
	db := unsafe { &sqlite.DB(conn) }
	rows := db.exec('SELECT * FROM tags ORDER BY id')!
	mut result := []models.Tag{}
	for row in rows {
		result << row_to_tag(row)
	}
	return result
}

fn tag_exec_insert(conn voidptr, t models.Tag) ! {
	db := unsafe { &sqlite.DB(conn) }
	params := [t.name, t.slug, t.created_at.str(), t.updated_at.str(), t.version.str()]
	db.exec_param_many('INSERT INTO tags (name, slug, created_at, updated_at, version) VALUES (?, ?, ?, ?, ?)', params)!
}

fn tag_exec_update(conn voidptr, t models.Tag) ! {
	db := unsafe { &sqlite.DB(conn) }
	params := [t.name, t.slug, t.updated_at.str(), t.version.str(), t.id.str()]
	db.exec_param_many('UPDATE tags SET name = ?, slug = ?, updated_at = ?, version = ? WHERE id = ?', params)!
}

fn tag_exec_delete(conn voidptr, id int) ! {
	db := unsafe { &sqlite.DB(conn) }
	db.exec_param('DELETE FROM tags WHERE id = ?', id.str())!
}

fn tag_exec_count(conn voidptr) !int {
	db := unsafe { &sqlite.DB(conn) }
	return db.q_int('SELECT COUNT(*) FROM tags')
}

fn tag_exec_exists(conn voidptr, id int) bool {
	db := unsafe { &sqlite.DB(conn) }
	rows := db.exec_param('SELECT 1 FROM tags WHERE id = ?', id.str()) or { return false }
	return rows.len > 0
}

pub struct TagRepository {
mut:
	base &phorm.BaseRepository[models.Tag]
	db   &sqlite.DB
}

pub fn new_tag_repository(manager &phorm.OrmManager) !&TagRepository {
	db := database.get_db(manager)!
	base := phorm.new_repository[models.Tag](manager, 'default',
		tag_exec_find, tag_exec_find_all, tag_exec_insert,
		tag_exec_update, tag_exec_delete, tag_exec_count, tag_exec_exists)!
	return &TagRepository{
		base: base
		db:   db
	}
}

pub fn (mut repo TagRepository) save(mut tag models.Tag) !models.Tag {
	was_new := tag.is_new()
	repo.base.save(mut tag)!
	if was_new {
		tag.id = int(repo.db.last_insert_rowid())
	}
	return tag
}

pub fn (mut repo TagRepository) find_by_id(id int) !models.Tag {
	return repo.base.find_by_id(id)!
}

pub fn (mut repo TagRepository) find_all() ![]models.Tag {
	return repo.base.find_all()!
}

pub fn (mut repo TagRepository) update(mut tag models.Tag) !models.Tag {
	return repo.base.update(mut tag)!
}

pub fn (repo &TagRepository) delete_by_id(id int) ! {
	repo.base.delete_by_id(id)!
}

pub fn (repo &TagRepository) count() !int {
	return repo.base.count()
}

pub fn (repo &TagRepository) exists_by_id(id int) bool {
	return repo.base.exists_by_id(id)
}

pub fn (repo &TagRepository) find_by_slug(slug string) !models.Tag {
	rows := repo.db.exec_param('SELECT * FROM tags WHERE slug = ?', slug)!
	if rows.len == 0 {
		return error('Tag not found: slug=${slug}')
	}
	return row_to_tag(rows[0])
}

pub fn (repo &TagRepository) exists_by_slug(slug string) bool {
	rows := repo.db.exec_param('SELECT 1 FROM tags WHERE slug = ?', slug) or { return false }
	return rows.len > 0
}

pub fn (repo &TagRepository) attach_tag(post_id int, tag_id int) ! {
	rows := repo.db.exec_param_many('SELECT 1 FROM post_tags WHERE post_id = ? AND tag_id = ?', [post_id.str(), tag_id.str()])!
	if rows.len > 0 {
		return
	}
	now := time.now().unix()
	params := [post_id.str(), tag_id.str(), now.str(), now.str(), '1']
	repo.db.exec_param_many('INSERT INTO post_tags (post_id, tag_id, created_at, updated_at, version) VALUES (?, ?, ?, ?, ?)', params)!
}

pub fn (repo &TagRepository) detach_tag(post_id int, tag_id int) ! {
	repo.db.exec_param_many('DELETE FROM post_tags WHERE post_id = ? AND tag_id = ?', [post_id.str(), tag_id.str()])!
}

pub fn (repo &TagRepository) find_tags_by_post(post_id int) ![]models.Tag {
	query := 'SELECT t.* FROM tags t INNER JOIN post_tags pt ON t.id = pt.tag_id WHERE pt.post_id = ? ORDER BY t.name'
	rows := repo.db.exec_param(query, post_id.str())!
	mut result := []models.Tag{}
	for row in rows {
		result << row_to_tag(row)
	}
	return result
}

pub fn (repo &TagRepository) find_post_ids_by_tag(tag_id int) ![]int {
	rows := repo.db.exec_param('SELECT post_id FROM post_tags WHERE tag_id = ?', tag_id.str())!
	mut result := []int{}
	for row in rows {
		result << row.get_int('post_id')
	}
	return result
}