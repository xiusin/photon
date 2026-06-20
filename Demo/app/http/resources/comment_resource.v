module resources

// app/Http/Resources/comment_resource.v — 评论 API Resource

import json
import models

pub struct CommentResource {
pub mut:
	user       UserResource @[skip_empty]
	replies    []CommentResource @[skip_empty]
pub:
	id         int
	content    string
	status     string
	created_at string
	updated_at string
}

pub fn new_comment_resource(c &models.Comment) CommentResource {
	return CommentResource{
		id:         c.id
		content:    c.content
		status:     c.status
		created_at: format_timestamp(c.created_at)
		updated_at: format_timestamp(c.updated_at)
	}
}

pub fn new_comment_resource_with_user(c &models.Comment, user &models.User) CommentResource {
	mut resource := new_comment_resource(c)
	if !isnil(user) && user.id > 0 {
		resource.user = new_user_resource(user)
	}
	return resource
}

pub fn new_comment_resource_with_replies(c &models.Comment, user &models.User, replies []CommentResource) CommentResource {
	mut resource := new_comment_resource_with_user(c, user)
	if replies.len > 0 {
		resource.replies = replies
	}
	return resource
}

pub fn (r CommentResource) to_json() string {
	return json.encode(r)
}

pub struct CommentResourceCollection {
pub:
	data []CommentResource
	meta ResourceMeta
}

pub fn new_comment_resource_collection(comments []models.Comment, total int, page int, page_size int) CommentResourceCollection {
	mut resources := []CommentResource{}
	for c in comments {
		resources << new_comment_resource(&c)
	}
	return CommentResourceCollection{
		data: resources
		meta: new_resource_meta(total, page, page_size)
	}
}

pub fn (c CommentResourceCollection) to_json() string {
	return json.encode(c)
}
