module main

// app/Http/Resources/collection.v — 通用 Resource 集合
//
// 提供泛型 ResourceCollection[T]，支持批量转换与分页元数据。
// 对于已有具体集合类型（UserResourceCollection 等），优先使用具体类型。
// 本泛型集合适用于需要统一处理的场景。
//
// Laravel 等价：Illuminate\Http\Resources\Json\ResourceCollection

import json

// ═══════════════════════════════════════════════════════════
// ResourceCollection[T] — 通用泛型集合
// ═══════════════════════════════════════════════════════════

pub struct ResourceCollection[T] {
pub:
	data []T
	meta ResourceMeta
}

// new_resource_collection 创建通用集合
pub fn new_resource_collection[T](data []T, total int, page int, page_size int) ResourceCollection[T] {
	return ResourceCollection[T]{
		data: data
		meta: new_resource_meta(total, page, page_size)
	}
}

// to_json 序列化为 JSON 字符串
pub fn (c ResourceCollection[T]) to_json() string {
	return json.encode(c)
}

// ═══════════════════════════════════════════════════════════
// ResourceLinks — 分页链接（HATEOAS 风格）
// ═══════════════════════════════════════════════════════════

pub struct ResourceLinks {
pub:
	self  string
	first string
	last  string
pub mut:
	prev  string @[skip_empty]
	next  string @[skip_empty]
}

// new_resource_links 创建分页链接
pub fn new_resource_links(base_path string, page int, page_size int, total int) ResourceLinks {
	if total == 0 || page_size == 0 {
		return ResourceLinks{
			self:  base_path
			first: base_path
			last:  base_path
		}
	}

	last_page := (total + page_size - 1) / page_size
	mut links := ResourceLinks{
		self:  '${base_path}?page=${page}&page_size=${page_size}'
		first: '${base_path}?page=1&page_size=${page_size}'
		last:  '${base_path}?page=${last_page}&page_size=${page_size}'
	}
	if page > 1 {
		links.prev = '${base_path}?page=${page - 1}&page_size=${page_size}'
	}
	if page < last_page {
		links.next = '${base_path}?page=${page + 1}&page_size=${page_size}'
	}
	return links
}

// ═══════════════════════════════════════════════════════════
// PaginatedResource[T] — 带链接的分页集合
// ═══════════════════════════════════════════════════════════

pub struct PaginatedResource[T] {
pub:
	data  []T
	meta  ResourceMeta
	links ResourceLinks
}

// new_paginated_resource 创建带链接的分页集合
pub fn new_paginated_resource[T](data []T, total int, page int, page_size int, base_path string) PaginatedResource[T] {
	return PaginatedResource[T]{
		data:  data
		meta:  new_resource_meta(total, page, page_size)
		links: new_resource_links(base_path, page, page_size, total)
	}
}

// to_json 序列化为 JSON 字符串
pub fn (r PaginatedResource[T]) to_json() string {
	return json.encode(r)
}
