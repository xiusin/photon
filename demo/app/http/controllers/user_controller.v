module controllers

import json

import veb
import photon.web
import photon.security
import models
import app.http
import app.http.resources

// UserController — 用户管理控制器，CRUD（均需 ADMIN）
pub struct UserController {
	BaseController
}

// get_users GET /api/v1/users — 用户分页列表（需 ADMIN，支持 keyword/status/role 过滤）
pub fn (c &UserController) get_users(mut ctx http.Context) veb.Result {
	// 认证 + 角色校验
	_, roles := c.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	c.middleware_registry.authorize(['ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	// 解析查询参数
	page_str := ctx.query['page'] or { '1' }
	page_size_str := ctx.query['page_size'] or { '20' }
	keyword := ctx.query['keyword'] or { '' }
	status_str := ctx.query['status'] or { '0' }
	role_filter := ctx.query['role'] or { '' }

	mut page := page_str.int()
	mut page_size := page_size_str.int()
	if page < 1 {
		page = 1
	}
	if page_size < 1 || page_size > 100 {
		page_size = 20
	}
	status_filter := status_str.int()

	// 构建过滤条件（SubTask 12.3：过滤下沉到 SQL）
	filter := models.UserFilter{
		keyword: keyword
		status:  status_filter
		role:    role_filter
	}

	// 调用仓储层过滤查询（过滤/分页全部在 SQL 完成）
	user_repo := c.bootstrap.user_repo
	users, total := user_repo.find_with_filters(filter, 'id_asc', page, page_size) or {
		return ctx.send_internal_error('failed to fetch users / 获取用户列表失败: ${err}')
	}

	// 转换为 UserResource 集合
	mut res_list := []resources.UserResource{}
	for u in users {
		res_list << resources.new_user_resource(&u)
	}

	// 使用 web.page 构建分页响应（含 pagination 元数据）
	page_result := web.page(json.encode(res_list), page, page_size, total)
	return ctx.send_page_result(page_result)
}

// get_user GET /api/v1/users/:id — 用户详情（需 ADMIN）
pub fn (c &UserController) get_user(mut ctx http.Context, id string) veb.Result {
	// 认证 + 角色校验
	_, roles := c.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	c.middleware_registry.authorize(['ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	user_id := id.int()
	if user_id <= 0 {
		return ctx.send_bad_request('invalid user id / 无效的用户 ID')
	}

	mut user_svc := c.bootstrap.user_svc
	user := user_svc.find_by_id(user_id) or {
		return ctx.send_not_found('user not found / 用户不存在: ${id}')
	}

	return ctx.send_data(resources.new_user_resource(&user).to_json())
}

// post_user POST /api/v1/users — 创建用户（需 ADMIN）
pub fn (c &UserController) post_user(mut ctx http.Context) veb.Result {
	// 认证 + 角色校验
	_, roles := c.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	c.middleware_registry.authorize(['ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	// 校验请求体
	dto := web.bind_json[models.CreateUserDto](ctx.Context) or {
		return ctx.send_result(web.fail(422, err.msg()))
	}
	return c.do_admin_create_user(mut ctx, dto)
}

// do_admin_create_user 管理员创建用户（内部辅助方法）
fn (c &UserController) do_admin_create_user(mut ctx http.Context, dto models.CreateUserDto) veb.Result {
	// 哈希密码
	hasher := security.BcryptHasher{}
	hashed_password := hasher.make(dto.password)

	mut user_svc := c.bootstrap.user_svc
	user, _ := user_svc.register(dto, hashed_password) or {
		return ctx.send_bad_request(err.msg())
	}

	return ctx.send_created(resources.new_user_resource(&user).to_json())
}

// put_user PUT /api/v1/users/:id — 更新用户（需 ADMIN）
pub fn (c &UserController) put_user(mut ctx http.Context, id string) veb.Result {
	// 认证 + 角色校验
	_, roles := c.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	c.middleware_registry.authorize(['ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	user_id := id.int()
	if user_id <= 0 {
		return ctx.send_bad_request('invalid user id / 无效的用户 ID')
	}

	// 校验请求体
	dto := web.bind_json[models.UpdateUserDto](ctx.Context) or {
		return ctx.send_result(web.fail(422, err.msg()))
	}
	return c.do_update_user(mut ctx, user_id, dto)
}

// do_update_user 执行用户更新（内部辅助方法）
fn (c &UserController) do_update_user(mut ctx http.Context, user_id int, dto models.UpdateUserDto) veb.Result {
	mut user_svc := c.bootstrap.user_svc
	user := user_svc.update_profile(user_id, dto) or {
		return ctx.send_not_found(err.msg())
	}

	return ctx.send_data(resources.new_user_resource(&user).to_json())
}

// delete_user DELETE /api/v1/users/:id — 删除用户（需 ADMIN，软删除）
pub fn (c &UserController) delete_user(mut ctx http.Context, id string) veb.Result {
	// 认证 + 角色校验
	_, roles := c.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	c.middleware_registry.authorize(['ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	user_id := id.int()
	if user_id <= 0 {
		return ctx.send_bad_request('invalid user id / 无效的用户 ID')
	}

	// 软删除（SubTask 12.4：设置 status = -1，而非物理删除）
	mut user_repo := c.bootstrap.user_repo
	user_repo.soft_delete(user_id) or {
		return ctx.send_not_found(err.msg())
	}

	return ctx.send_data(json.encode(http.MessageDto{message: 'user deleted / 用户已删除'}))
}