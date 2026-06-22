module controllers

import json

import veb
import photon.web
import models
import app.http
import app.http.resources

// CommentController — 评论控制器，列表/创建/删除
pub struct CommentController {
	BaseController
}

// get_post_comments GET /api/v1/posts/:id/comments — 文章评论列表（公开，支持嵌套）
pub fn (c &CommentController) get_post_comments(mut ctx http.Context, id string) veb.Result {
	post_id := id.int()
	if post_id <= 0 {
		return ctx.send_bad_request('invalid post id / 无效的文章 ID')
	}

	comment_svc := c.bootstrap.comment_svc
	comments := comment_svc.find_by_post(post_id) or {
		return ctx.send_internal_error('failed to fetch comments / 获取评论失败: ${err}')
	}

	// 构建嵌套评论结构（顶层评论 + 子评论）
	mut top_level := []models.Comment{}
	mut replies_map := map[int][]models.Comment{}
	for cmt in comments {
		if cmt.parent_id == 0 {
			top_level << cmt
		} else {
			mut existing := replies_map[cmt.parent_id] or { []models.Comment{} }
			existing << cmt
			replies_map[cmt.parent_id] = existing
		}
	}

	// 构建带 replies 的 Resource 列表
	mut items := []resources.CommentResource{}
	for cmt in top_level {
		replies := replies_map[cmt.id] or { []models.Comment{} }
		mut reply_resources := []resources.CommentResource{}
		for r in replies {
			reply_resources << resources.new_comment_resource(&r)
		}
		items << resources.new_comment_resource_with_replies(&cmt, unsafe { nil }, reply_resources)
	}

	// 使用 web.page 构建分页响应（评论一次性返回，分页元数据标识总数）
	page_result := web.page(json.encode(items), 1, items.len, items.len)
	return ctx.send_page_result(page_result)
}

// post_post_comment POST /api/v1/posts/:id/comments — 创建评论（需 USER+，触发 comment.posted 事件）
pub fn (c &CommentController) post_post_comment(mut ctx http.Context, id string) veb.Result {
	// 认证 + 角色校验（USER+ 包含 EDITOR 和 ADMIN）
	username, roles := c.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	c.middleware_registry.authorize(['USER', 'EDITOR', 'ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	post_id := id.int()
	if post_id <= 0 {
		return ctx.send_bad_request('invalid post id / 无效的文章 ID')
	}

	// 获取当前用户 ID
	user_svc := c.bootstrap.user_svc
	user := user_svc.find_by_username(username) or {
		return ctx.send_unauthorized('user not found / 用户不存在')
	}

	// 校验请求体
	mut dto := web.bind_json[models.CreateCommentDto](ctx.Context) or {
		return ctx.send_result(web.fail(422, err.msg()))
	}
	// 注入 post_id 与 user_id（由控制器设置，非客户端输入）
	dto.post_id = post_id
	dto.user_id = user.id

	mut comment_svc := c.bootstrap.comment_svc
	comment, _ := comment_svc.create(dto, user.id) or {
		return ctx.send_bad_request(err.msg())
	}

	return ctx.send_created(resources.new_comment_resource(&comment).to_json())
}

// delete_comment DELETE /api/v1/comments/:id — 删除评论（需 ADMIN 或作者本人）
pub fn (c &CommentController) delete_comment(mut ctx http.Context, id string) veb.Result {
	// 认证（必须登录）
	username, roles := c.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}

	comment_id := id.int()
	if comment_id <= 0 {
		return ctx.send_bad_request('invalid comment id / 无效的评论 ID')
	}

	// 查询评论以检查所有权
	mut comment_svc := c.bootstrap.comment_svc
	comment := comment_svc.find_by_id(comment_id) or {
		return ctx.send_not_found('comment not found / 评论不存在: ${id}')
	}

	// 获取当前用户
	user_svc := c.bootstrap.user_svc
	current_user := user_svc.find_by_username(username) or {
		return ctx.send_unauthorized('user not found / 用户不存在')
	}

	// 权限校验：ADMIN 或评论作者本人
	is_admin := 'ADMIN' in roles
	is_owner := comment.user_id == current_user.id
	if !is_admin && !is_owner {
		return ctx.send_forbidden('permission denied — only admin or comment owner can delete / 权限不足，仅管理员或评论作者可删除')
	}

	// 执行软删除（SubTask 12.4：设置 status = 'deleted'）
	mut comment_repo := c.bootstrap.comment_repo
	comment_repo.soft_delete(comment_id) or {
		return ctx.send_internal_error(err.msg())
	}

	return ctx.send_data(json.encode(http.MessageDto{message: 'comment deleted / 评论已删除'}))
}