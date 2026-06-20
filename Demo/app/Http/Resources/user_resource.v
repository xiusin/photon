module main

// app/Http/Resources/user_resource.v — 用户 API Resource
//
// 将 User 实体转换为 API 响应格式，隐藏敏感字段（password/version）。
// 时间戳格式化为 ISO 8601 字符串。
//
// Laravel 等价：App\Http\Resources\UserResource
// Spring 等价：UserDTO + @JsonView

import time
import json

// ═══════════════════════════════════════════════════════════
// UserResource — 用户 API Resource
// ═══════════════════════════════════════════════════════════

pub struct UserResource {
pub:
	id         int
	username   string
	email      string
	nickname   string
	avatar     string
	role       string
	status     int
	created_at string
	updated_at string
}

// new_user_resource 从 User 实体创建 UserResource
pub fn new_user_resource(u &User) UserResource {
	return UserResource{
		id:         u.id
		username:   u.username
		email:      u.email
		nickname:   u.nickname
		avatar:     u.avatar
		role:       u.role
		status:     u.status
		created_at: format_timestamp(u.created_at)
		updated_at: format_timestamp(u.updated_at)
	}
}

// to_json 序列化为 JSON 字符串
pub fn (r UserResource) to_json() string {
	return json.encode(r)
}

// ═══════════════════════════════════════════════════════════
// UserResourceCollection — 用户集合
// ═══════════════════════════════════════════════════════════

pub struct UserResourceCollection {
pub:
	data []UserResource
	meta ResourceMeta
}

// new_user_resource_collection 从 User 实体列表创建集合
pub fn new_user_resource_collection(users []User, total int, page int, page_size int) UserResourceCollection {
	mut resources := []UserResource{}
	for u in users {
		resources << new_user_resource(&u)
	}
	return UserResourceCollection{
		data: resources
		meta: new_resource_meta(total, page, page_size)
	}
}

// to_json 序列化为 JSON 字符串
pub fn (c UserResourceCollection) to_json() string {
	return json.encode(c)
}

// ═══════════════════════════════════════════════════════════
// 辅助函数
// ═══════════════════════════════════════════════════════════

// format_timestamp 将 Unix 时间戳格式化为 ISO 8601 字符串
pub fn format_timestamp(ts i64) string {
	if ts == 0 {
		return ''
	}
	return time.unix(ts).format_ss()
}

// ResourceMeta 集合元数据
pub struct ResourceMeta {
pub:
	total     int
	page      int
	page_size int
	has_more  bool
}

// new_resource_meta 创建集合元数据
pub fn new_resource_meta(total int, page int, page_size int) ResourceMeta {
	has_more := page * page_size < total
	return ResourceMeta{
		total:     total
		page:      page
		page_size: page_size
		has_more:  has_more
	}
}
