module repositories

import photon.orm as phorm
import db.sqlite
import time
import models
import database
import util

// ═══════════════════════════════════════════════════════════
// UserRepository
// ═══════════════════════════════════════════════════════════

pub struct UserRepository {
	phorm.Repository[models.User]
pub mut:
	om &phorm.OrmManager = unsafe { nil }
}

pub fn new_user_repository(om &phorm.OrmManager) !&UserRepository {
	mut repo := &UserRepository{
		om: om
	}
	unsafe {
		repo.orm_manager = om
	}
	return repo
}

pub fn (mut r UserRepository) find_by_username(username string) !models.User {
	return r.where('username = ', username).first()!
}

pub fn (mut r UserRepository) find_by_email(email string) !models.User {
	return r.where('email = ', email).first()!
}

pub fn (mut r UserRepository) find_active(id int) !models.User {
	user := r.find_by_id(id)!
	if user.status != 1 {
		return error('User is not active')
	}
	return user
}

pub fn (mut r UserRepository) find_with_filters(filter models.UserFilter) ![]models.User {
	mut q := r.query()
	if filter.keyword.len > 0 {
		q = q.where('username LIKE ', '%${filter.keyword}%').or_where('email LIKE ', '%${filter.keyword}%')
	}
	if filter.status > 0 {
		q = q.where('status = ', filter.status)
	}
	if filter.role.len > 0 {
		q = q.where('role = ', filter.role)
	}
	return q.get()!
}

pub fn (mut r UserRepository) soft_delete(id int) ! {
	mut user := r.find_by_id(id)!
	user.status = -1
	user.updated_at = time.now()
	r.update(user)!
}

pub fn (mut r UserRepository) count_by_role(role string) !int {
	return r.where('role = ', role).where('status = ', 1).count()!
}

// ═══════════════════════════════════════════════════════════
// PostRepository
// ═══════════════════════════════════════════════════════════

pub struct PostRepository {
	phorm.Repository[models.Post]
pub mut:
	om &phorm.OrmManager = unsafe { nil }
}

pub fn new_post_repository(om &phorm.OrmManager) !&PostRepository {
	mut repo := &PostRepository{
		om: om
	}
	unsafe {
		repo.orm_manager = om
	}
	return repo
}

pub fn (mut r PostRepository) find_published(id int) !models.Post {
	post := r.find_by_id(id)!
	if post.status != 'published' {
		return error('Post not published')
	}
	return post
}

pub fn (mut r PostRepository) published_posts() ![]models.Post {
	return r.where('status = ', 'published').order_by('created_at', .desc).get()!
}

pub fn (mut r PostRepository) by_category(category_id int) ![]models.Post {
	return r.where('category_id = ', category_id).where('status = ', 'published').get()!
}

pub fn (mut r PostRepository) by_author(author_id int) ![]models.Post {
	return r.where('author_id = ', author_id).get()!
}

pub fn (mut r PostRepository) increment_views(id int) ! {
	mut post := r.find_by_id(id)!
	post.views++
	r.update(post)!
}

pub fn (mut r PostRepository) find_with_filters(filter models.PostFilter) ![]models.Post {
	mut q := r.query()
	if filter.keyword.len > 0 {
		q = q.where('title LIKE ', '%${filter.keyword}%')
	}
	if filter.status.len > 0 {
		q = q.where('status = ', filter.status)
	}
	if filter.category_id > 0 {
		q = q.where('category_id = ', filter.category_id)
	}
	if filter.tag_id > 0 {
		// Join with post_tags table
		q = q.where_raw('id IN (SELECT post_id FROM post_tags WHERE tag_id = ${filter.tag_id})')
	}
	return q.order_by('created_at', .desc).get()!
}

pub fn (mut r PostRepository) soft_delete(id int) ! {
	mut post := r.find_by_id(id)!
	post.status = 'archived'
	post.updated_at = time.now()
	r.update(post)!
}

pub fn (mut r PostRepository) count_by_status(status string) !int {
	return r.where('status = ', status).count()!
}

// ═══════════════════════════════════════════════════════════
// CommentRepository
// ═══════════════════════════════════════════════════════════

pub struct CommentRepository {
	phorm.Repository[models.Comment]
pub mut:
	om &phorm.OrmManager = unsafe { nil }
}

pub fn new_comment_repository(om &phorm.OrmManager) !&CommentRepository {
	mut repo := &CommentRepository{
		om: om
	}
	unsafe {
		repo.orm_manager = om
	}
	return repo
}

pub fn (mut r CommentRepository) by_post(post_id int) ![]models.Comment {
	return r.where('post_id = ', post_id).where('status = ', 'visible').order_by('created_at', .asc).get()!
}

pub fn (mut r CommentRepository) find_with_filters(filter models.CommentFilter) ![]models.Comment {
	mut q := r.query()
	if filter.post_id > 0 {
		q = q.where('post_id = ', filter.post_id)
	}
	if filter.status.len > 0 {
		q = q.where('status = ', filter.status)
	}
	return q.order_by('created_at', .desc).get()!
}

pub fn (mut r CommentRepository) soft_delete(id int) ! {
	mut comment := r.find_by_id(id)!
	comment.status = 'deleted'
	comment.updated_at = time.now()
	r.update(comment)!
}

pub fn (mut r CommentRepository) count_by_post(post_id int) !int {
	return r.where('post_id = ', post_id).where('status = ', 'visible').count()!
}

// ═══════════════════════════════════════════════════════════
// CategoryRepository
// ═══════════════════════════════════════════════════════════

pub struct CategoryRepository {
	phorm.Repository[models.Category]
pub mut:
	om &phorm.OrmManager = unsafe { nil }
}

pub fn new_category_repository(om &phorm.OrmManager) !&CategoryRepository {
	mut repo := &CategoryRepository{
		om: om
	}
	unsafe {
		repo.orm_manager = om
	}
	return repo
}

pub fn (mut r CategoryRepository) find_by_slug(slug string) !models.Category {
	return r.where('slug = ', slug).first()!
}

pub fn (mut r CategoryRepository) all_ordered() ![]models.Category {
	return r.order_by('name', .asc).get()!
}

// ═══════════════════════════════════════════════════════════
// TagRepository
// ═══════════════════════════════════════════════════════════

pub struct TagRepository {
	phorm.Repository[models.Tag]
pub mut:
	om &phorm.OrmManager = unsafe { nil }
}

pub fn new_tag_repository(om &phorm.OrmManager) !&TagRepository {
	mut repo := &TagRepository{
		om: om
	}
	unsafe {
		repo.orm_manager = om
	}
	return repo
}

pub fn (mut r TagRepository) find_by_slug(slug string) !models.Tag {
	return r.where('slug = ', slug).first()!
}

pub fn (mut r TagRepository) all_ordered() ![]models.Tag {
	return r.order_by('name', .asc).get()!
}

pub fn (mut r TagRepository) find_by_post(post_id int) ![]models.Tag {
	db := database.get_db(r.om)!
	rows := db.query('SELECT t.* FROM tags t INNER JOIN post_tags pt ON t.id = pt.tag_id WHERE pt.post_id = ${post_id}') or { return [] }
	mut tags := []models.Tag{}
	for row in rows {
		mut tag := models.Tag{}
		tag.id = row.int_by_field('id') or { 0 }
		tag.name = row.string_by_field('name') or { '' }
		tag.slug = row.string_by_field('slug') or { '' }
		tags << tag
	}
	return tags
}
