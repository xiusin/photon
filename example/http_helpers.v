module main

// http_helpers.v — Context 响应辅助方法 & JSON 工具
//
// 这些方法挂在请求级 Context 上，供各控制器统一构造 JSON 响应。
// 从原 controllers.v 抽出，独立成文件，避免与控制器业务逻辑混杂。
import veb
import photon.web

// json_success 返回成功 JSON
pub fn (mut ctx Context) json_success(message string) veb.Result {
	return ctx.json({
		'code':    '200'
		'message': message
	})
}

// json_error 返回错误 JSON。
//
// 状态行必须跟着 code 走：只把 403/401 写进正文、状态码留 200，客户端、
// 网关、APM 的错误率全都会把一次拒绝当成成功。`web.error_result()` 用
// 同一个参数设状态行和正文 code，两者不可能不一致。
pub fn (mut ctx Context) json_error(code int, message string) veb.Result {
	return web.error_result(mut ctx.Context, code, message)
}

// json_response 返回带数据的 JSON。
//
// code 同时决定状态行（201 Created 这类语义状态码因此才真的到达网络）。
pub fn (mut ctx Context) json_response(code int, data string) veb.Result {
	return web.json_status(mut ctx.Context, code, {
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
