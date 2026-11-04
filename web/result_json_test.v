module web

// result_json_test.v — Result.to_json() 的回归测试
//
// 背景：Result 自己实现了 to_json()，而它的实现又是 `json2.encode(r)`。
// json2 对实现了 to_json() 的类型（JsonEncoder 接口）不会逐字段编码，
// 而是回头调用 to_json() —— 从 to_json 进 json2 再回到 to_json，
// 第一次调用就把栈打爆（不是偶发、不是只有 Result：任何「to_json 里调
// json2.encode(self)」的 struct 都中招）。
//
// 所以断言不能只是「to_json 返回了字符串」，必须是「它是合法 JSON、字段齐全」。
import x.json2

fn test_result_to_json_is_valid_json() {
	// data 约定是「JSON 字符串或裸值」，这里用合法 JSON 载荷
	r := ok('{"a":1}')
	raw := r.to_json()

	decoded := json2.decode[map[string]json2.Any](raw) or {
		assert false, 'Result.to_json() 输出不是合法 JSON: ${raw}'
		return
	}
	assert decoded.len == 6
	for field in ['success', 'code', 'message', 'data', 'timestamp', 'path'] {
		assert field in decoded, 'Result.to_json() 丢了字段 ${field}: ${raw}'
	}
}

fn test_result_to_json_keeps_scalar_types() {
	raw := success_with_msg('x', 'OK').to_json()
	// success 必须是 JSON 布尔，不能是字符串 "true"
	assert raw.contains('"success":true')
	assert !raw.contains('"success":"true"')
	assert raw.contains('"code":200')
}

fn test_fail_to_json() {
	raw := fail(404, 'not found').to_json()
	assert raw.contains('"success":false')
	assert raw.contains('"code":404')
	assert raw.contains('"message":"not found"')
	// data 为空时是空串——保字段、不报错
	assert raw.contains('"data":')
}

fn test_result_to_json_escapes_message() {
	raw := fail(400, 'bad "quoted" value').to_json()
	assert raw.contains('bad \\"quoted\\" value'), 'message 里的引号没被转义: ${raw}'
	// data 为空串时是裸的空值，整段本就不是 JSON（约定如此，#data 由调用方给合法 JSON）
	assert raw.contains('"path":""')
}

fn test_page_result_to_json_unchanged() {
	pr := page('{"a":1}', 2, 10, 25)
	raw := pr.to_json()
	assert raw.contains('"pagination"')
	assert raw.contains('"page":2')
	assert raw.contains('"total_pages":3')
	assert raw.contains('"has_next":true')
	assert raw.contains('"has_prev":true')
}
