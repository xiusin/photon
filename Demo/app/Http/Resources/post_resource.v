module main

// app/Http/Resources/post_resource.v — 文章 API Resource
//
// 将 Post 实体转换为 API 响应格式，支持嵌套 author/category/tags。
// 时间戳格式化为 ISO 8601 字符串。
//
// Laravel 等价：App\Http\Resources\PostResource
// Spring 等价：PostDTO + @JsonView

import json

// ═══════════════════════════════════════════════════════════
// PostResource — 文章 API Resource
// ═══════════════════════════════════════════════════════════

pub struct PostResource {
pub mut:
	author     UserResource @[skip_empty]
	category   CategoryResource @[skip_empty]
	tags       []TagResource @[skip_empty]
pub:
	id         int
	title      string
	summary    string
	content    string @[skip_empty]
	status     string
	views      int
	created_at string
	updated_at string
}

// new_post_resource 从 Post 实体创建 PostResource（不含关联）
pub fn new_post_resource(p &Post) PostResource {
	return PostResource{
		id:         p.id
		title:      p.title
		summary:    p.summary
		content:    p.content
		status:     p.status
		views:      p.views
		created_at: format_timestamp(p.created_at)
		updated_at: format_timestamp(p.updated_at)
	}
}

// new_post_resource_with_relations 从 Post 实体创建 PostResource（含关联）
pub fn new_post_resource_with_relations(p &Post, author &User, category &Category, tags []Tag) PostResource {
	mut resource := new_post_resource(p)
	if !isnil(author) && author.id > 0 {
		resource.author = new_user_resource(author)
	}
	if !isnil(category) && category.id > 0 {
		resource.category = new_category_resource(category)
	}
	if tags.len > 0 {
		mut tag_resources := []TagResource{}
		for t in tags {
			tag_resources << new_tag_resource(&t)
		}
		resource.tags = tag_resources
	}
	return resource
}

// to_json 序列化为 JSON 字符串
pub fn (r PostResource) to_json() string {
	return json.encode(r)
}

// ═══════════════════════════════════════════════════════════
// PostResourceCollection — 文章集合
// ═══════════════════════════════════════════════════════════

pub struct PostResourceCollection {
pub:
	data []PostResource
	meta ResourceMeta
}

// new_post_resource_collection 从 Post 实体列表创建集合
pub fn new_post_resource_collection(posts []Post, total int, page int, page_size int) PostResourceCollection {
	mut resources := []PostResource{}
	for p in posts {
		resources << new_post_resource(&p)
	}
	return PostResourceCollection{
		data: resources
		meta: new_resource_meta(total, page, page_size)
	}
}

// to_json 序列化为 JSON 字符串
pub fn (c PostResourceCollection) to_json() string {
	return json.encode(c)
}
