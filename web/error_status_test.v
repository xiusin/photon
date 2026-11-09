// error_status_test.v — 错误响应的状态行必须和正文一致
//
// 缺陷：`ctx.json({'code': '403', ...})` 只把错误码写进正文，`ctx.res`
// 的状态码仍然是 0，而 veb 的 `send_response_to_client` 在状态为 0 时补
// 一个 `.ok`。结果是「正文说拒绝、状态行说 200」。
//
// 这组用例的目的不是「跑通」，而是把状态行钉成断言 —— 只断言正文里
// 的 code 等于 403 的用例，在缺陷存在时**照样全绿**，因为正文一直是
// 对的。真正错的是网络上的那个数字。
module web

import veb
import net.http

// status_ctx 造一个干净请求上下文。
fn status_ctx() &veb.Context {
	return &veb.Context{
		req: http.Request{}
	}
}

// send 把 Result 落到 ctx 上。veb 的 send_response_to_client 在 status_code
// 仍为 0 时才补 .ok，所以 true 路径必须真的走一遍发送才能看到结果。
fn send_to(mut ctx veb.Context, res veb.Result) {
	// json_status / error_result 内部已经调用过 send_response_to_client，
	// 这里只读 ctx.res 的状态码，不需要重复发送。
	_ = res
}

// ── 1：json_status 把状态码写到状态行 ──

fn test_json_status_sets_the_status_line() {
	mut ctx := status_ctx()
	res := json_status[int](mut ctx, 403, 403)
	send_to(mut ctx, res)
	assert ctx.res.status_code == 403
}

fn test_json_status_does_not_downgrade_to_ok() {
	mut ctx := status_ctx()
	_ := json_status[string](mut ctx, 500, 'boom')
	assert ctx.res.status_code == 500, 'json_status 之后状态码必须是 500，而不是 veb 补的 200'
}

// ── 2：正文与状态行由同一个参数决定 ──

fn test_error_result_status_matches_body_code() {
	mut ctx := status_ctx()
	_ := error_result(mut ctx, 401, 'token expired')
	assert ctx.res.status_code == 401
	assert ctx.res.body.contains('"code":401'), '正文里的 code 必须是数字 401，实际: ${ctx.res.body}'
	assert ctx.res.body.contains('token expired')
	assert ctx.res.body.contains('"success":false')
}

fn test_error_result_422_and_429() {
	for code in [400, 401, 403, 404, 409, 422, 429, 500, 503] {
		mut ctx := status_ctx()
		_ := error_result(mut ctx, code, 'nope')
		assert ctx.res.status_code == code, 'error_result(${code}) 的状态行是 ${ctx.res.status_code}'
		assert ctx.res.body.contains('"code":${code}')
	}
}

fn test_error_result_with_details_keeps_status() {
	mut ctx := status_ctx()
	_ := error_result_with_details(mut ctx, 422, 'validation failed', {
		'email': 'invalid'
	})
	assert ctx.res.status_code == 422
	assert ctx.res.body.contains('"email":"invalid"')
}

// ── 3：content-type 必须是 JSON ──

fn test_error_result_content_type_is_json() {
	mut ctx := status_ctx()
	_ := error_result(mut ctx, 400, 'bad')
	ct := ctx.res.header.get(.content_type) or { '' }
	assert ct.starts_with('application/json'), '错误响应必须是 JSON，实际: ${ct}'
}

// ── 4：非法状态码不许静默变成别的码 ──

// 未分配的 HTTP 状态码（例如 499、700、-1）不能原样发出去：
// `http.Status(code)` 是不校验的强转，会得到一个有值但无意义的状态行。
fn test_unassigned_code_falls_back_to_500() {
	mut ctx := status_ctx()
	_ := error_result(mut ctx, 499, 'client closed request')
	assert ctx.res.status_code == 500, '未分配的 499 必须退到 500，实际 ${ctx.res.status_code}'
	assert ctx.res.body.contains('"code":499'), '正文里仍要保留调用方给的原始 code'
}

// ── 5：结构断言 —— 三个入口都必须先设状态再发正文 ──
//
// 行为用例可以被绕开：只要有人把实现改成「发完正文再补状态」，veb 的
// send_response_to_client 已经把正文写进 ctx.res.body（还在进程内，没
// 真发出去），行为断言依然会看到正确的状态码。所以这里直接读源码，
// 要求 `set_status` 出现在 `send_response_to_client` / `ctx.json` 之前。
fn test_helpers_set_status_before_sending() {
	src := $embed_file('exception.v').to_string()
	for fname in ['json_status', 'error_result', 'error_result_with_details'] {
		body := fn_body(src, fname) or { panic('找不到函数 ${fname} 的函数体') }
		set_pos := body.index('set_status') or {
			panic('${fname}() 没有调用 set_status —— 错误响应又会变成 200')
		}
		mut send_pos := body.index('send_response_to_client') or { -1 }
		if send_pos < 0 {
			send_pos = body.index('ctx.json') or { -1 }
		}
		assert send_pos > 0, '${fname}() 没有发送正文'
		assert set_pos < send_pos,
			'${fname}() 必须先 set_status 再发送正文：状态码在正文之后设置会被 veb 的默认 .ok 覆盖'
	}
}

// fn_body 从源码里截出某个 pub fn 的函数体（到下一个顶格 `}` 为止）。
// 只用于结构断言，不做通用解析。
fn fn_body(src string, name string) ?string {
	mut at := src.index('fn ${name}[') or { -1 }
	if at < 0 {
		at = src.index('fn ${name}(') or { -1 }
	}
	if at < 0 {
		return none
	}
	rest := src[at..]
	end := rest.index('\n}\n') or { return none }
	return rest[..end]
}
