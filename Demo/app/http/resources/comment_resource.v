module resources

// app/Http/Resources/comment_resource.v — 评论 API Resource
//
// 将 Comment 实体转换为 API 响应格式，支持嵌套 user/replies。
// 时间戳格式化为 ISO 8601 字符串。
//
// Laravel 等价：App\Http\Resources\CommentResource

import json

// ═══════════════════════════════════════════════════════════
// CommentResource — 评论 API Resource
// ═══════════════════════════════════════════════════════════

pub struct CommentResource {
pub:
	id         int
	content    string
	status     string
	user       UserResource @[skip_empty]
	replies    []CommentResource @[skip_empty]
	created_at string
	updated_at string
}

// new_comment_resource 从 Comment 实体创建 CommentResource（不含关联）
pub fn new_comment_resource(c &Comment) CommentResource {
	return CommentResource{
		id:         c.id
		content:    c.content
		status:     c.status
		created_at: format_timestamp(c.created_at)
		updated_at: format_timestamp(c.updated_at)
	}
}

// new_comment_resource_with_user 从 Comment 实体创建 CommentResource（含用户）
pub fn new_comment_resource_with_user(c &Comment, user &User) CommentResource {
	mut resource := new_comment_resource(c)
	if !isnil(user) && user.id > 0 {
		resource.user = new_user_resource(user)
	}
	return resource
}

// new_comment_resource_with_replies 从 Comment 实体创建 CommentResource（含用户和回复）
pub fn new_comment_resource_with_replies(c &Comment, user &User, replies []CommentResource) CommentResource {
	mut resource := new_comment_resource_with_user(c, user)
	if replies.len > 0 {
		resource.replies = replies
	}
	return resource
}

// to_json 序列化为 JSON 字符串
pub fn (r CommentResource) to_json() string {
	return json.encode(r)
}

// ═══════════════════════════════════════════════════════════
// CommentResourceCollection — 评论集合
// ═══════════════════════════════════════════════════════════

pub struct CommentResourceCollection {
pub:
	data []CommentResource
	meta ResourceMeta
}

// new_comment_resource_collection 从 Comment 实体列表创建集合
pub fn new_comment_resource_collection(comments []Comment, total int, page int, page_size int) CommentResourceCollection {
	mut resources := []CommentResource{}
	for c in comments {
		resources << new_comment_resource(&c)
	}
	return CommentResourceCollection{
		data: resources
		meta: new_resource_meta(total, page, page_size)
	}
}

// to_json 序列化为 JSON 字符串
pub fn (c CommentResourceCollection) to_json() string {
	return json.encode(c)
}
