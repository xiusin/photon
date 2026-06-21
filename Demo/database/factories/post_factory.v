module factories

// post_factory.v — PostFactory 模型工厂
//
// 用于测试与种子数据生成文章实体。
//
// 用法：
//   // 创建默认文章（需指定 author_id）
//   post := new_post_factory(boot).with_author(admin_id).create()!
//
//   // 创建已发布文章
//   post := new_post_factory(boot).with_author(admin_id).with_status('published').create()!
//
//   // 构建实体不持久化
//   post := new_post_factory(boot).with_author(admin_id).make()

import time
import bootstrap
import models

// PostFactory 文章模型工厂
pub struct PostFactory {
pub:
	bootstrap &bootstrap.Bootstrap
mut:
	title       string
	content     string
	summary     string
	author_id   int
	category_id int
	status      string
}

// new_post_factory 创建文章工厂实例，填充默认属性
// 注：author_id 必须由调用方通过 with_author() 设置
pub fn new_post_factory(boot &bootstrap.Bootstrap) PostFactory {
	suffix := time.now().unix().str() + '_' + rand_int_str(4)
	return PostFactory{
		bootstrap:   boot
		title:       'Factory Post ${suffix}'
		content:     'This is a factory-generated post content for testing and seeding. PhotonBlog demonstrates V language enterprise framework capabilities including ORM, caching, queues, and event-driven architecture.'
		summary:     'Factory post summary ${suffix}'
		author_id:   0 // 必须由 with_author() 设置
		category_id: 1
		status:      'draft'
	}
}

// with_author 设置作者 ID（支持链式调用）
pub fn (f PostFactory) with_author(author_id int) PostFactory {
	mut result := f
	result.author_id = author_id
	return result
}

// with_category 设置分类 ID（支持链式调用）
pub fn (f PostFactory) with_category(category_id int) PostFactory {
	mut result := f
	result.category_id = category_id
	return result
}

// with_title 设置标题（支持链式调用）
pub fn (f PostFactory) with_title(title string) PostFactory {
	mut result := f
	result.title = title
	return result
}

// with_content 设置内容（支持链式调用）
pub fn (f PostFactory) with_content(content string) PostFactory {
	mut result := f
	result.content = content
	return result
}

// with_status 设置状态（支持链式调用）
pub fn (f PostFactory) with_status(status string) PostFactory {
	mut result := f
	result.status = status
	return result
}

// with_summary 设置摘要（支持链式调用）
pub fn (f PostFactory) with_summary(summary string) PostFactory {
	mut result := f
	result.summary = summary
	return result
}

// make 构建文章实体（不持久化）
pub fn (f PostFactory) make() models.Post {
	return models.Post{
		title:       f.title
		content:     f.content
		summary:     f.summary
		author_id:   f.author_id
		category_id: f.category_id
		status:      f.status
		views:       0
	}
}

// create 持久化文章到数据库并返回实体
//
// 通过 PostService.create() 持久化，自动处理缓存失效与事件分发。
pub fn (f PostFactory) create() !models.Post {
	if f.author_id == 0 {
		return error('PostFactory.create: author_id 未设置，请先调用 with_author() / author_id not set')
	}
	dto := models.CreatePostDto{
		title:       f.title
		content:     f.content
		summary:     f.summary
		author_id:   f.author_id
		category_id: f.category_id
		status:      f.status
	}
	mut svc := unsafe { f.bootstrap.post_svc }
	return svc.create(dto)!
}
