module apidoc

// apidoc.v — Module Entry Point
//
// init(), encode_response(), api_error() for the example application.
import os
import x.json2

// init initializes the API documentation module.
pub fn init(storage_path string) !(&ApiDocStore, &Collector) {
	store := get_store()

	if storage_path.len > 0 && !os.exists(storage_path) {
		os.mkdir_all(storage_path) or { return error('failed to create apidoc storage: ${err}') }
	}

	coll := new_collector(store)
	return store, coll
}

// init_without_collector returns just the store
pub fn init_store(storage_path string) !&ApiDocStore {
	store := get_store()
	if storage_path.len > 0 && !os.exists(storage_path) {
		os.mkdir_all(storage_path) or { return error('failed to create apidoc storage: ${err}') }
	}
	return store
}

// encode_response formats a standard JSON API response.
//
// `msg` 走 json2 编码：手拼字符串时消息里一个引号或换行就能把整个响应
// 变成非法 JSON（更糟的是能被注入额外字段）。`data` 由调用方保证已是
// 合法 JSON 片段，保持不变。
pub fn encode_response(code int, msg string, data string) string {
	body := if data.len == 0 { 'null' } else { data }
	return '{"code":${code},"msg":${json2.encode(msg)},"data":${body}}'
}

// api_error formats a standard JSON API error response.
pub fn api_error(code int, msg string) string {
	return '{"code":${code},"msg":${json2.encode(msg)}}'
}
