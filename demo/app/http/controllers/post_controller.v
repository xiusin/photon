module controllers

import json

import veb
import photon.web
import models
import app.http
import app.http.resources

// PostController — 文章控制器，CRUD（公开 / EDITOR+ / ADMIN）
pub struct PostController {
	BaseController
}

// get_posts GET /api/v1/posts — 文章分页列表（公开，支持 category/tag/keyword/status 过滤 + 排序）
pub fn (c &PostController) get_posts(mut ctx http.Context) veb.Result {
	// 解析查询参数
	page_str := ctx.query['page'] or { '1' }
	page_size_str := ctx.query['page_size'] or { '20' }
	category := ctx.query['category'] or { '' }
	tag := ctx.query['tag'] or { '' }
	keyword := ctx.query['keyword'] or { '' }
	status := ctx.query['status'] or { 'published' }
	sort := ctx.query['sort'] or { 'created_at_desc' }

	mut page := page_str.int()
	mut page_size := page_size_str.int()
	if page < 1 {
		page = 1
	}
	if page_size < 1 || page_size > 100 {
		page_size = 20
	}

	// 构建过滤条件（SubTask 12.2：过滤下沉到 SQL）
	filter := models.PostFilter{
		keyword:     keyword
		status:      status
		category_id: if category.len > 0 { category.int() } else { 0 }
		tag_id:      if tag.len > 0 { tag.int() } else { 0 }
	}

	// 调用仓储层过滤查询（过滤/排序/分页全部在 SQL 完成）
	post_repo := c.bootstrap.post_repo
	posts, total := post_repo.find_with_filters(filter, sort, page, page_size) or {
		return ctx.send_internal_error('failed to fetch posts / 获取文章列表失败: ${err}')
	}

	// 转换为 PostResource 集合（加载作者与分类关联）
	mut user_svc := c.bootstrap.user_svc
	mut category_svc := c.bootstrap.category_svc
	mut res_list := []resources.PostResource{}
	for p in posts {
		post_author := user_svc.find_by_id(p.author_id) or { models.User{} }
		post_category := category_svc.find_by_id(p.category_id) or { models.Category{} }
		res_list << resources.new_post_resource_with_relations(&p, &post_author,
			&post_category, []models.Tag{})
	}

	// 使用 web.page 构建分页响应（含 pagination 元数据）
	page_result := web.page(json.encode(res_list), page, page_size, total)
	return ctx.send_page_result(page_result)
}

// get_post GET /api/v1/posts/:id — 文章详情（公开，自增 views，缓存命中）
pub fn (c &PostController) get_post(mut ctx http.Context, id string) veb.Result {
	post_id := id.int()
	if post_id <= 0 {
		return ctx.send_bad_request('invalid post id / 无效的文章 ID')
	}

	mut post_svc := c.bootstrap.post_svc
	post := post_svc.find_by_id(post_id) or {
		return ctx.send_not_found('post not found / 文章不存在: ${id}')
	}

	// 自增浏览量（同步执行：共享单个 sqlite 连接，禁止用 go 协程并发访问，
	// 否则与请求处理线程并发 prepare/exec 会导致 SQLite 崩溃）
	post_svc.increment_views(post_id) or {
		c.bootstrap.log.error('[get_post] increment_views failed: ${err}')
	}

	// 加载关联：作者与分类
	mut user_svc := c.bootstrap.user_svc
	mut category_svc := c.bootstrap.category_svc
	author := user_svc.find_by_id(post.author_id) or { models.User{} }
	category := category_svc.find_by_id(post.category_id) or { models.Category{} }
	return ctx.send_data(resources.new_post_resource_with_relations(&post, &author, &category,
		[]models.Tag{}).to_json())
}

// post_post POST /api/v1/posts — 创建文章（需 EDITOR+，触发 post.published 事件）
pub fn (c &PostController) post_post(mut ctx http.Context) veb.Result {
	// 认证 + 角色校验（EDITOR+ 包含 ADMIN）
	username, roles := c.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	c.middleware_registry.authorize(['EDITOR', 'ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	// 获取当前用户 ID（作为作者）
	user_svc := c.bootstrap.user_svc
	user := user_svc.find_by_username(username) or {
		return ctx.send_unauthorized('user not found / 用户不存在')
	}

	// 校验请求体
	mut dto := web.bind_json[models.CreatePostDto](ctx.Context) or {
		return ctx.send_result(web.fail(422, err.msg()))
	}
	// 注入作者 ID（由控制器从 JWT 设置，非客户端输入）
	dto.author_id = user.id

	return c.do_create_post(mut ctx, dto)
}

// do_create_post 执行文章创建（内部辅助方法）
fn (c &PostController) do_create_post(mut ctx http.Context, dto models.CreatePostDto) veb.Result {
	mut post_svc := c.bootstrap.post_svc
	post, _ := post_svc.create(dto, dto.author_id) or {
		return ctx.send_bad_request(err.msg())
	}

	return ctx.send_created(resources.new_post_resource(&post).to_json())
}

// put_post PUT /api/v1/posts/:id — 更新文章（需 EDITOR+，清除缓存）
pub fn (c &PostController) put_post(mut ctx http.Context, id string) veb.Result {
	// 认证 + 角色校验
	_, roles := c.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	c.middleware_registry.authorize(['EDITOR', 'ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	post_id := id.int()
	if post_id <= 0 {
		return ctx.send_bad_request('invalid post id / 无效的文章 ID')
	}

	// 校验请求体
	dto := web.bind_json[models.UpdatePostDto](ctx.Context) or {
		return ctx.send_result(web.fail(422, err.msg()))
	}
	return c.do_update_post(mut ctx, post_id, dto)
}

// do_update_post 执行文章更新（内部辅助方法）
fn (c &PostController) do_update_post(mut ctx http.Context, post_id int, dto models.UpdatePostDto) veb.Result {
	mut post_svc := c.bootstrap.post_svc
	post, _ := post_svc.update(post_id, dto) or {
		return ctx.send_not_found(err.msg())
	}

	return ctx.send_data(resources.new_post_resource(&post).to_json())
}

// delete_post DELETE /api/v1/posts/:id — 删除文章（需 ADMIN）
pub fn (c &PostController) delete_post(mut ctx http.Context, id string) veb.Result {
	// 认证 + 角色校验
	_, roles := c.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	c.middleware_registry.authorize(['ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	post_id := id.int()
	if post_id <= 0 {
		return ctx.send_bad_request('invalid post id / 无效的文章 ID')
	}

	// 软删除（SubTask 12.4：设置 status = 'archived'，而非物理删除）
	mut post_repo := c.bootstrap.post_repo
	post_repo.soft_delete(post_id) or {
		return ctx.send_not_found(err.msg())
	}

	return ctx.send_data(json.encode(http.MessageDto{message: 'post deleted / 文章已删除'}))
}