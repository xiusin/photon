module controllers

import json

import veb
import photon.web
import models
import app.http
import app.http.resources

// TagController — 标签控制器，列表/创建
pub struct TagController {
	BaseController
}

// get_tags GET /api/v1/tags — 标签列表（公开）
pub fn (c &TagController) get_tags(mut ctx http.Context) veb.Result {
	mut tag_svc := c.bootstrap.tag_svc
	tags := tag_svc.find_all() or {
		return ctx.send_internal_error('failed to fetch tags / 获取标签列表失败: ${err}')
	}

	// 转换为 TagResource 集合
	mut res_list := []resources.TagResource{}
	for t in tags {
		res_list << resources.new_tag_resource(&t)
	}

	// 使用 web.page 构建分页响应
	page_result := web.page(json.encode(res_list), 1, res_list.len, res_list.len)
	return ctx.send_page_result(page_result)
}

// post_tag POST /api/v1/tags — 创建标签（需 EDITOR+）
pub fn (c &TagController) post_tag(mut ctx http.Context) veb.Result {
	// 认证 + 角色校验
	_, roles := c.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	c.middleware_registry.authorize(['EDITOR', 'ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	// 校验请求体
	dto := web.bind_json[models.CreateTagDto](ctx.Context) or {
		return ctx.send_result(web.fail(422, err.msg()))
	}
	return c.do_create_tag(mut ctx, dto)
}

// do_create_tag 执行标签创建（内部辅助方法）
fn (c &TagController) do_create_tag(mut ctx http.Context, dto models.CreateTagDto) veb.Result {
	mut tag_svc := c.bootstrap.tag_svc
	tag, _ := tag_svc.create(dto) or {
		return ctx.send_bad_request(err.msg())
	}

	return ctx.send_created(resources.new_tag_resource(&tag).to_json())
}