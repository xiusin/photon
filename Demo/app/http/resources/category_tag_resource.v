module resources

// app/Http/Resources/category_tag_resource.v — 分类与标签 API Resource

import json
import models

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

pub fn new_category_resource(c &models.Category) CategoryResource {
	return CategoryResource{
		id:          c.id
		name:        c.name
		slug:        c.slug
		description: c.description
		created_at:  format_timestamp(c.created_at)
		updated_at:  format_timestamp(c.updated_at)
	}
}

pub fn (r CategoryResource) to_json() string {
	return json.encode(r)
}

pub struct CategoryResourceCollection {
pub:
	data []CategoryResource
	meta ResourceMeta
}

pub fn new_category_resource_collection(categories []models.Category, total int, page int, page_size int) CategoryResourceCollection {
	mut resources := []CategoryResource{}
	for c in categories {
		resources << new_category_resource(&c)
	}
	return CategoryResourceCollection{
		data: resources
		meta: new_resource_meta(total, page, page_size)
	}
}

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

pub fn new_tag_resource(t &models.Tag) TagResource {
	return TagResource{
		id:         t.id
		name:       t.name
		slug:       t.slug
		created_at: format_timestamp(t.created_at)
		updated_at: format_timestamp(t.updated_at)
	}
}

pub fn (r TagResource) to_json() string {
	return json.encode(r)
}

pub struct TagResourceCollection {
pub:
	data []TagResource
	meta ResourceMeta
}

pub fn new_tag_resource_collection(tags []models.Tag, total int, page int, page_size int) TagResourceCollection {
	mut resources := []TagResource{}
	for t in tags {
		resources << new_tag_resource(&t)
	}
	return TagResourceCollection{
		data: resources
		meta: new_resource_meta(total, page, page_size)
	}
}

pub fn (c TagResourceCollection) to_json() string {
	return json.encode(c)
}
