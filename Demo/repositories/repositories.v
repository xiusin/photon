module repositories

// repositories.v — PhotonBlog 仓储层
//
// 使用 photon.orm.BaseRepository[T] + OrmAdapter[T] 实现仓储模式。
//
// 由于 V ORM 的 `sql db { ... }` 编译期语法在跨模块嵌入结构体
// （phorm.BaseEntity）场景下存在限制（where 子句无法引用嵌入字段、
// insert 会包含 id=0 破坏自增主键），所有 CRUD 回调使用原生 SQL
// （db.exec_param / exec_param_many / q_int）实现。
//
// OrmAdapter 自动管理生命周期（通过 BaseRepository.save 内部调用）：
//   - before_insert / before_update 自动调用 touch() 更新时间戳与版本号
//   - after_find / after_find_all 钩子（BaseEntity 未实现，为空操作）
//
// 仓储包装 save 方法：insert 后通过 last_insert_rowid() 回填自增 ID。

import models
import photon.orm as phorm
import db.sqlite
import time
import database

// ═══════════════════════════════════════════════════════════
// UserRepository — 用户仓储
// ═══════════════════════════════════════════════════════════

// row_to_user 将 sqlite.Row 映射为 User 实体
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

// ── CRUD 回调（原生 SQL）──

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

// ── 仓储结构体 ──

pub struct UserRepository {
mut:
	base &phorm.BaseRepository[models.User]
pub:
	db &sqlite.DB
}

// new_user_repository 创建用户仓储，注册 7 个原生 SQL 回调到 BaseRepository[User]
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

// ── CRUD 方法 ──

// save 插入或更新用户，insert 后回填自增 ID
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

// ── 派生查询 ──

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

// exists_by_username 检查用户名是否已存在
pub fn (repo &UserRepository) exists_by_username(username string) bool {
	rows := repo.db.exec_param('SELECT 1 FROM users WHERE username = ?', username) or { return false }
	return rows.len > 0
}

// exists_by_email 检查邮箱是否已存在
pub fn (repo &UserRepository) exists_by_email(email string) bool {
	rows := repo.db.exec_param('SELECT 1 FROM users WHERE email = ?', email) or { return false }
	return rows.len > 0
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

// ── CRUD 回调 ──

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

// ── 仓储结构体 ──

pub struct PostRepository {
mut:
	base &phorm.BaseRepository[models.Post]
pub:
	db &sqlite.DB
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

// ── CRUD 方法 ──

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

// ── 派生查询 ──

// find_by_author 查询某作者的所有文章
pub fn (repo &PostRepository) find_by_author(author_id int) ![]models.Post {
	rows := repo.db.exec_param('SELECT * FROM posts WHERE author_id = ? ORDER BY created_at DESC', author_id.str())!
	mut result := []models.Post{}
	for row in rows {
		result << row_to_post(row)
	}
	return result
}

// find_by_category 查询某分类下的所有文章
pub fn (repo &PostRepository) find_by_category(category_id int) ![]models.Post {
	rows := repo.db.exec_param('SELECT * FROM posts WHERE category_id = ? ORDER BY created_at DESC', category_id.str())!
	mut result := []models.Post{}
	for row in rows {
		result << row_to_post(row)
	}
	return result
}

// find_by_status 按状态查询文章
pub fn (repo &PostRepository) find_by_status(status string) ![]models.Post {
	rows := repo.db.exec_param('SELECT * FROM posts WHERE status = ? ORDER BY created_at DESC', status)!
	mut result := []models.Post{}
	for row in rows {
		result << row_to_post(row)
	}
	return result
}

// find_published 查询所有已发布文章（便捷方法）
pub fn (repo &PostRepository) find_published() ![]models.Post {
	return repo.find_by_status('published')
}

// increment_views 文章浏览数自增（用于详情页访问）
pub fn (repo &PostRepository) increment_views(id int) ! {
	_ = repo.db.exec_param('UPDATE posts SET views = views + 1 WHERE id = ?', id.str())!
}

// count_by_status 按状态统计文章数
pub fn (repo &PostRepository) count_by_status(status string) !int {
	rows := repo.db.exec_param('SELECT COUNT(*) AS cnt FROM posts WHERE status = ?', status)!
	if rows.len == 0 {
		return 0
	}
	return rows[0].get_int('cnt')
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

// ── CRUD 回调 ──

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

// ── 仓储结构体 ──

pub struct CommentRepository {
mut:
	base &phorm.BaseRepository[models.Comment]
pub:
	db &sqlite.DB
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

// ── CRUD 方法 ──

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

// ── 派生查询 ──

// find_by_post 查询某文章的所有评论
pub fn (repo &CommentRepository) find_by_post(post_id int) ![]models.Comment {
	rows := repo.db.exec_param('SELECT * FROM comments WHERE post_id = ? ORDER BY created_at ASC', post_id.str())!
	mut result := []models.Comment{}
	for row in rows {
		result << row_to_comment(row)
	}
	return result
}

// find_by_parent 查询某评论的所有子评论（嵌套评论）
pub fn (repo &CommentRepository) find_by_parent(parent_id int) ![]models.Comment {
	rows := repo.db.exec_param('SELECT * FROM comments WHERE parent_id = ? ORDER BY created_at ASC', parent_id.str())!
	mut result := []models.Comment{}
	for row in rows {
		result << row_to_comment(row)
	}
	return result
}

// count_by_post 统计某文章的评论数
pub fn (repo &CommentRepository) count_by_post(post_id int) !int {
	rows := repo.db.exec_param('SELECT COUNT(*) AS cnt FROM comments WHERE post_id = ?', post_id.str())!
	if rows.len == 0 {
		return 0
	}
	return rows[0].get_int('cnt')
}

// touch_post 更新文章的 updated_at 时间戳（用于评论创建时标记文章活动）
// 与评论创建同事务执行，确保原子性
pub fn (repo &CommentRepository) touch_post(post_id int) ! {
	now := time.now().unix().str()
	repo.db.exec_param_many('UPDATE posts SET updated_at = ? WHERE id = ?', [now, post_id.str()])!
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

// ── CRUD 回调 ──

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

// ── 仓储结构体 ──

pub struct CategoryRepository {
mut:
	base &phorm.BaseRepository[models.Category]
pub:
	db &sqlite.DB
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

// ── CRUD 方法 ──

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

// ── 派生查询 ──

// find_by_slug 按 slug 查询分类
pub fn (repo &CategoryRepository) find_by_slug(slug string) !models.Category {
	rows := repo.db.exec_param('SELECT * FROM categories WHERE slug = ?', slug)!
	if rows.len == 0 {
		return error('Category not found: slug=${slug}')
	}
	return row_to_category(rows[0])
}

// exists_by_slug 检查 slug 是否已存在
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

// ── CRUD 回调 ──

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

// ── 仓储结构体 ──

pub struct TagRepository {
mut:
	base &phorm.BaseRepository[models.Tag]
pub:
	db &sqlite.DB
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

// ── CRUD 方法 ──

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

// ── 派生查询 ──

// find_by_slug 按 slug 查询标签
pub fn (repo &TagRepository) find_by_slug(slug string) !models.Tag {
	rows := repo.db.exec_param('SELECT * FROM tags WHERE slug = ?', slug)!
	if rows.len == 0 {
		return error('Tag not found: slug=${slug}')
	}
	return row_to_tag(rows[0])
}

// exists_by_slug 检查 slug 是否已存在
pub fn (repo &TagRepository) exists_by_slug(slug string) bool {
	rows := repo.db.exec_param('SELECT 1 FROM tags WHERE slug = ?', slug) or { return false }
	return rows.len > 0
}

// ── 文章-标签关联操作 ──

// attach_tag 为文章添加标签（插入 post_tags 关联记录）
pub fn (repo &TagRepository) attach_tag(post_id int, tag_id int) ! {
	// 先检查是否已关联，避免唯一约束冲突
	rows := repo.db.exec_param2('SELECT 1 FROM post_tags WHERE post_id = ? AND tag_id = ?', post_id.str(), tag_id.str())!
	if rows.len > 0 {
		return // 已存在关联，幂等返回
	}
	now := time.now().unix()
	params := [post_id.str(), tag_id.str(), now.str(), now.str(), '1']
	repo.db.exec_param_many('INSERT INTO post_tags (post_id, tag_id, created_at, updated_at, version) VALUES (?, ?, ?, ?, ?)', params)!
}

// detach_tag 移除文章的标签关联
pub fn (repo &TagRepository) detach_tag(post_id int, tag_id int) ! {
	_ = repo.db.exec_param2('DELETE FROM post_tags WHERE post_id = ? AND tag_id = ?', post_id.str(), tag_id.str())!
}

// find_tags_by_post 查询文章的所有标签
pub fn (repo &TagRepository) find_tags_by_post(post_id int) ![]models.Tag {
	query := 'SELECT t.* FROM tags t INNER JOIN post_tags pt ON t.id = pt.tag_id WHERE pt.post_id = ? ORDER BY t.name'
	rows := repo.db.exec_param(query, post_id.str())!
	mut result := []models.Tag{}
	for row in rows {
		result << row_to_tag(row)
	}
	return result
}

// find_posts_by_tag 查询带有某标签的所有文章 ID
pub fn (repo &TagRepository) find_post_ids_by_tag(tag_id int) ![]int {
	rows := repo.db.exec_param('SELECT post_id FROM post_tags WHERE tag_id = ?', tag_id.str())!
	mut result := []int{}
	for row in rows {
		result << row.get_int('post_id')
	}
	return result
}
