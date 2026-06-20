module resources

// app/Http/Resources/category_tag_resource.v — 分类与标签 API Resource
//
// 将 Category/Tag 实体转换为 API 响应格式。
// 时间戳格式化为 ISO 8601 字符串。
//
// Laravel 等价：App\Http\Resources\CategoryResource / TagResource

import json

// ═══════════════════════════════════════════════════════════
// CategoryResource — 分类 API Resource
// ═══════════════════════════════════════════════════════════

pub struct CategoryResource {
pub:
	id          int
	name        string
	slug        string
	description string
	created_at  string
	updated_at  string
}

// new_category_resource 从 Category 实体创建 CategoryResource
pub fn new_category_resource(c &Category) CategoryResource {
	return CategoryResource{
		id:          c.id
		name:        c.name
		slug:        c.slug
		description: c.description
		created_at:  format_timestamp(c.created_at)
		updated_at:  format_timestamp(c.updated_at)
	}
}

// to_json 序列化为 JSON 字符串
pub fn (r CategoryResource) to_json() string {
	return json.encode(r)
}

// CategoryResourceCollection 分类集合
pub struct CategoryResourceCollection {
pub:
	data []CategoryResource
	meta ResourceMeta
}

// new_category_resource_collection 从 Category 实体列表创建集合
pub fn new_category_resource_collection(categories []Category, total int, page int, page_size int) CategoryResourceCollection {
	mut resources := []CategoryResource{}
	for c in categories {
		resources << new_category_resource(&c)
	}
	return CategoryResourceCollection{
		data: resources
		meta: new_resource_meta(total, page, page_size)
	}
}

// to_json 序列化为 JSON 字符串
pub fn (c CategoryResourceCollection) to_json() string {
	return json.encode(c)
}

// ═══════════════════════════════════════════════════════════
// TagResource — 标签 API Resource
// ═══════════════════════════════════════════════════════════

pub struct TagResource {
pub:
	id         int
	name       string
	slug       string
	created_at string
	updated_at string
}

// new_tag_resource 从 Tag 实体创建 TagResource
pub fn new_tag_resource(t &Tag) TagResource {
	return TagResource{
		id:         t.id
		name:       t.name
		slug:       t.slug
		created_at: format_timestamp(t.created_at)
		updated_at: format_timestamp(t.updated_at)
	}
}

// to_json 序列化为 JSON 字符串
pub fn (r TagResource) to_json() string {
	return json.encode(r)
}

// TagResourceCollection 标签集合
pub struct TagResourceCollection {
pub:
	data []TagResource
	meta ResourceMeta
}

// new_tag_resource_collection 从 Tag 实体列表创建集合
pub fn new_tag_resource_collection(tags []Tag, total int, page int, page_size int) TagResourceCollection {
	mut resources := []TagResource{}
	for t in tags {
		resources << new_tag_resource(&t)
	}
	return TagResourceCollection{
		data: resources
		meta: new_resource_meta(total, page, page_size)
	}
}

// to_json 序列化为 JSON 字符串
pub fn (c TagResourceCollection) to_json() string {
	return json.encode(c)
}
