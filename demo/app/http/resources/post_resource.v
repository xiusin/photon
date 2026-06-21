module resources

// app/Http/Resources/post_resource.v — 文章 API Resource

import json
import models

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

pub fn new_post_resource(p &models.Post) PostResource {
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

pub fn new_post_resource_with_relations(p &models.Post, author &models.User, category &models.Category, tags []models.Tag) PostResource {
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

pub fn (r PostResource) to_json() string {
	return json.encode(r)
}

pub struct PostResourceCollection {
pub:
	data []PostResource
	meta ResourceMeta
}

pub fn new_post_resource_collection(posts []models.Post, total int, page int, page_size int) PostResourceCollection {
	mut resources := []PostResource{}
	for p in posts {
		resources << new_post_resource(&p)
	}
	return PostResourceCollection{
		data: resources
		meta: new_resource_meta(total, page, page_size)
	}
}

pub fn (c PostResourceCollection) to_json() string {
	return json.encode(c)
}
