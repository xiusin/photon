module main

// http_helpers.v — Context 响应辅助方法 & JSON 工具
//
// 这些方法挂在请求级 Context 上，供各控制器统一构造 JSON 响应。
// 从原 controllers.v 抽出，独立成文件，避免与控制器业务逻辑混杂。
import veb

// json_success 返回成功 JSON
pub fn (mut ctx Context) json_success(message string) veb.Result {
	return ctx.json({
		'code':    '200'
		'message': message
	})
}

// json_error 返回错误 JSON
pub fn (mut ctx Context) json_error(code int, message string) veb.Result {
	return ctx.json({
		'code':    '${code}'
		'message': message
	})
}

// json_response 返回带数据的 JSON
pub fn (mut ctx Context) json_response(code int, data string) veb.Result {
	return ctx.json({
		'code': '${code}'
		'data': data
	})
}

// json_data 将数组转为 JSON 字符串
fn json_data[T](items []T) string {
	if items.len == 0 {
		return '[]'
	}
	mut result := '['
	for i, item in items {
		if i > 0 {
			result += ','
		}
		result += '${item}'
	}
	result += ']'
	return result
}
