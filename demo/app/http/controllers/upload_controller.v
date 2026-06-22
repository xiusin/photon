module controllers

import json
import os

import veb
import photon.web
import app.http
import app.http.middleware

// UploadController — 文件上传控制器，头像/配图/文件访问
pub struct UploadController {
	BaseController
}

// post_upload_avatar POST /api/v1/uploads/avatar — 头像上传（需 USER+，限制 2MB，.jpg/.png）
pub fn (c &UploadController) post_upload_avatar(mut ctx http.Context) veb.Result {
	// 认证 + 角色校验
	_, roles := c.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	c.middleware_registry.authorize(['USER', 'EDITOR', 'ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	// 从 multipart 表单获取文件
	files := ctx.files['file'] or {
		return ctx.send_bad_request('no file uploaded / 未上传文件')
	}
	if files.len == 0 {
		return ctx.send_bad_request('no file uploaded / 未上传文件')
	}

	file := files[0]
	if file.data.len == 0 {
		return ctx.send_bad_request('empty file / 文件为空')
	}

	// 调用上传服务
	mut upload_svc := c.bootstrap.upload_svc
	stored_name, _ := upload_svc.upload(file.filename, file.data.bytes()) or {
		return ctx.send_bad_request(err.msg())
	}

	// 构建响应数据
	resp := http.UploadResponseDto{
		original_name: file.filename
		stored_name:   stored_name
		path:          '/uploads/${stored_name}'
		size:          file.data.len
		extension:     file.filename.all_after_last('.')
		mime_type:     file.filename.all_after_last('.')
		hash:          ''
		url:           '/api/v1/uploads/${stored_name}'
	}
	return ctx.send_data(json.encode(resp))
}

// post_upload_image POST /api/v1/uploads/image — 文章配图上传（需 EDITOR+，限制 5MB）
pub fn (c &UploadController) post_upload_image(mut ctx http.Context) veb.Result {
	// 认证 + 角色校验
	_, roles := c.middleware_registry.authenticate(mut ctx.Context) or {
		return ctx.send_unauthorized(err.msg())
	}
	c.middleware_registry.authorize(['EDITOR', 'ADMIN'], roles) or {
		return ctx.send_forbidden(err.msg())
	}

	// 从 multipart 表单获取文件
	files := ctx.files['file'] or {
		return ctx.send_bad_request('no file uploaded / 未上传文件')
	}
	if files.len == 0 {
		return ctx.send_bad_request('no file uploaded / 未上传文件')
	}

	file := files[0]
	if file.data.len == 0 {
		return ctx.send_bad_request('empty file / 文件为空')
	}

	// 调用上传服务
	mut upload_svc := c.bootstrap.upload_svc
	stored_name, _ := upload_svc.upload(file.filename, file.data.bytes()) or {
		return ctx.send_bad_request(err.msg())
	}

	// 构建响应数据
	resp := http.UploadResponseDto{
		original_name: file.filename
		stored_name:   stored_name
		path:          '/uploads/${stored_name}'
		size:          file.data.len
		extension:     file.filename.all_after_last('.')
		mime_type:     file.filename.all_after_last('.')
		hash:          ''
		url:           '/api/v1/uploads/${stored_name}'
	}
	return ctx.send_data(json.encode(resp))
}

// get_upload_file GET /api/v1/uploads/:file — 访问已上传文件
pub fn (c &UploadController) get_upload_file(mut ctx http.Context, file string) veb.Result {
	if file.len == 0 {
		return ctx.send_bad_request('file name required / 文件名为必填项')
	}

	// 安全检查：防止路径遍历攻击
	if file.contains('..') || file.contains('/') || file.contains('\\') {
		return ctx.send_bad_request('invalid file name / 无效的文件名')
	}

	// 读取文件内容
	content := os.read_file('uploads/${file}') or {
		return ctx.send_not_found('file not found / 文件不存在: ${file}')
	}

	// 根据扩展名推断 MIME 类型
	mime_type := web.guess_mime_type(file)

	// 直接返回文件内容（不使用统一 JSON 封装）
	return ctx.send_response_to_client(mime_type, content)
}