module controllers

import json

import veb
import photon.web
import models
import app.http
import app.http.resources

// CategoryController — 分类控制器，列表/创建
pub struct CategoryController {
	BaseController
}

// get_categories GET /api/v1/categories — 分类列表（公开）
pub fn (c &CategoryController) get_categories(mut ctx http.Context) veb.Result {
	mut category_svc := c.bootstrap.category_svc
	categories := category_svc.find_all() or {
		return ctx.send_internal_error('failed to fetch categories / 获取分类列表失败: ${err}')
	}

	// 转换为 CategoryResource 集合
	mut res_list := []resources.CategoryResource{}
	for cat in categories {
		res_list << resources.new_category_resource(&cat)
	}

	// 使用 web.page 构建分页响应
	page_result := web.page(json.encode(res_list), 1, res_list.len, res_list.len)
	return ctx.send_page_result(page_result)
}

// post_category POST /api/v1/categories — 创建分类（需 ADMIN）
pub fn (c &CategoryController) post_category(mut ctx http.Context) veb.Result {
	// 认证 + 角色校验
	_, roles := c.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	c.middleware_registry.authorize(['ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	// 校验请求体
	dto := web.bind_json[models.CreateCategoryDto](ctx.Context) or {
		return ctx.send_result(web.fail(422, err.msg()))
	}
	return c.do_create_category(mut ctx, dto)
}

// do_create_category 执行分类创建（内部辅助方法）
fn (c &CategoryController) do_create_category(mut ctx http.Context, dto models.CreateCategoryDto) veb.Result {
	mut category_svc := c.bootstrap.category_svc
	category, _ := category_svc.create(dto) or {
		return ctx.send_bad_request(err.msg())
	}

	return ctx.send_created(resources.new_category_resource(&category).to_json())
}