module factories

// comment_factory.v — CommentFactory 模型工厂
//
// 用于测试与种子数据生成评论实体。
//
// 用法：
//   // 创建默认评论（需指定 post_id 和 user_id）
//   comment := new_comment_factory(boot).with_post(post_id).with_user(user_id).create()!
//
//   // 创建子评论（回复）
//   comment := new_comment_factory(boot).with_post(post_id).with_user(user_id).with_parent(parent_id).create()!

import time

// CommentFactory 评论模型工厂
pub struct CommentFactory {
pub:
	bootstrap &Bootstrap
mut:
	post_id   int
	user_id   int
	content   string
	parent_id int
}

// new_comment_factory 创建评论工厂实例，填充默认属性
// 注：post_id 和 user_id 必须由调用方设置
pub fn new_comment_factory(boot &Bootstrap) CommentFactory {
	suffix := time.now().unix().str() + '_' + rand_int_str(4)
	return CommentFactory{
		bootstrap: boot
		post_id:   0 // 必须由 with_post() 设置
		user_id:   0 // 必须由 with_user() 设置
		content:   'Factory comment ${suffix} — great article!'
		parent_id: 0
	}
}

// with_post 设置文章 ID（支持链式调用）
pub fn (f CommentFactory) with_post(post_id int) CommentFactory {
	mut result := f
	result.post_id = post_id
	return result
}

// with_user 设置评论者 ID（支持链式调用）
pub fn (f CommentFactory) with_user(user_id int) CommentFactory {
	mut result := f
	result.user_id = user_id
	return result
}

// with_content 设置评论内容（支持链式调用）
pub fn (f CommentFactory) with_content(content string) CommentFactory {
	mut result := f
	result.content = content
	return result
}

// with_parent 设置父评论 ID（支持链式调用，用于嵌套回复）
pub fn (f CommentFactory) with_parent(parent_id int) CommentFactory {
	mut result := f
	result.parent_id = parent_id
	return result
}

// make 构建评论实体（不持久化）
pub fn (f CommentFactory) make() Comment {
	return Comment{
		post_id:   f.post_id
		user_id:   f.user_id
		content:   f.content
		parent_id: f.parent_id
		status:    'visible'
	}
}

// create 持久化评论到数据库并返回实体
//
// 通过 CommentService.create() 持久化，自动处理文章 updated_at 更新与事件分发。
pub fn (f CommentFactory) create() !Comment {
	if f.post_id == 0 {
		return error('CommentFactory.create: post_id 未设置，请先调用 with_post() / post_id not set')
	}
	if f.user_id == 0 {
		return error('CommentFactory.create: user_id 未设置，请先调用 with_user() / user_id not set')
	}
	dto := CreateCommentDto{
		post_id:   f.post_id
		user_id:   f.user_id
		content:   f.content
		parent_id: f.parent_id
	}
	mut svc := unsafe { f.bootstrap.comment_svc }
	return svc.create(dto)!
}
