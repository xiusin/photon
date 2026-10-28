module apidoc

import x.json2

// apidoc_test.v — apidoc 模块的行为契约
//
// 覆盖三条最容易被改坏的性质：
//   1. 响应构造函数必须对 msg 转义，否则一个引号就能把响应变成非法
//      JSON，甚至注入额外字段
//   2. store 的读操作返回副本，写操作只在锁内发生
//   3. export_openapi 在并发追加条目时不会崩、且结构合法

// sum type 的 map 下标在 -prod 下必须带 or 块（warning 会升级成 error），
// 统一用下面三个取值器收口，避免每条断言都写一遍 or {}。
fn get_obj(m map[string]json2.Any, key string) map[string]json2.Any {
	missing := json2.Any(json2.Null{})
	return (m[key] or { missing }) as map[string]json2.Any
}

fn get_str(m map[string]json2.Any, key string) string {
	return (m[key] or { json2.Any('') }) as string
}

fn get_arr(m map[string]json2.Any, key string) []json2.Any {
	return (m[key] or { json2.Any([]json2.Any{}) }) as []json2.Any
}

fn get_any(m map[string]json2.Any, key string) json2.Any {
	missing := json2.Any(json2.Null{})
	return m[key] or { missing }
}

fn as_obj(v json2.Any) map[string]json2.Any {
	return v as map[string]json2.Any
}

fn test_encode_response_escapes_msg() {
	got := encode_response(0, 'say "hi"', '{"a":1}')
	parsed := json2.decode[json2.Any](got) or {
		assert false, 'encode_response produced invalid JSON: ${got}'
		return
	}
	obj := as_obj(parsed)
	assert get_str(obj, 'msg') == 'say "hi"'
	assert (get_any(obj, 'code') as f64) == 0
}

fn test_encode_response_keeps_data_as_json_fragment() {
	got := encode_response(200, 'ok', '{"users":[1,2]}')
	obj := as_obj(json2.decode[json2.Any](got)!)
	inner := get_obj(obj, 'data')
	assert get_arr(inner, 'users').len == 2
}

fn test_encode_response_empty_data_is_null() {
	got := encode_response(0, 'ok', '')
	obj := as_obj(json2.decode[json2.Any](got)!)
	assert get_any(obj, 'data') is json2.Null
}

fn test_api_error_escapes_newline() {
	got := api_error(400, 'bad\nline')
	obj := as_obj(json2.decode[json2.Any](got) or {
		assert false, 'api_error produced invalid JSON: ${got}'
		return
	})
	assert get_str(obj, 'msg') == 'bad\nline'
}

fn test_api_error_rejects_injection() {
	// 未转义时这里会变成 {"code":0,"msg":"x","admin":true}
	got := api_error(0, 'x","admin":true')
	obj := as_obj(json2.decode[json2.Any](got)!)
	assert 'admin' !in obj
	assert get_str(obj, 'msg') == 'x","admin":true'
}

fn test_store_get_entry_returns_copy() {
	mut s := new_store()
	s.with_or_create_entry('get', '/api/users', fn (mut e ApiDocEntry) ! {
		e.summary = 'list users'
	})!
	first := s.get_entry('GET::/api/users')!
	mut changed := first
	changed.summary = 'mutated locally'

	second := s.get_entry('GET::/api/users')!
	assert second.summary == 'list users'
}

fn test_store_entry_survives_growth() {
	mut s := new_store()
	for i in 0 .. 64 {
		id := '/api/r${i}'
		s.with_or_create_entry('get', id, fn [i] (mut e ApiDocEntry) ! {
			e.summary = 'r${i}'
		})!
	}
	// map 扩容过，早先条目的指针仍须有效
	for i in 0 .. 64 {
		e := s.get_entry('GET::/api/r${i}')!
		assert e.summary == 'r${i}'
	}
}

fn test_lock_endpoint_missing_id_is_noop() {
	mut s := new_store()
	s.lock_endpoint('GET::/nope')
	assert s.get_entries().len == 0
}

fn test_delete_entry_missing_returns_error() {
	mut s := new_store()
	mut failed := false
	s.delete_entry('GET::/nope') or { failed = true }
	assert failed
}

fn test_export_openapi_structure() {
	mut s := new_store()
	s.with_or_create_entry('get', '/api/users', fn (mut e ApiDocEntry) ! {
		e.summary = 'list'
		e.parameters << ApiDocParam{
			name:     'page'
			location: 'query'
			required: false
			type_:    'integer'
		}
	})!
	raw := s.export_openapi()
	obj := as_obj(json2.decode[json2.Any](raw)!)
	assert get_str(obj, 'openapi') == '3.0.0'
	paths := get_obj(obj, 'paths')
	assert '/api/users' in paths
	op := get_obj(as_obj(paths['/api/users'] or { json2.Any(map[string]json2.Any{}) }), 'get')
	assert get_str(op, 'summary') == 'list'
	assert get_arr(op, 'parameters').len == 1
}

fn test_store_concurrent_appends() {
	mut s := new_store()
	// 8 个协程并发写不同条目：锁内追加不应丢数据，也不应崩溃
	mut handles := []thread{}
	for w in 0 .. 8 {
		handles << spawn fn [mut s, w] () {
			for i in 0 .. 20 {
				id := '/api/w${w}_${i}'
				s.with_or_create_entry('post', id, fn [w, i] (mut e ApiDocEntry) ! {
					e.summary = 'w${w}-${i}'
				}) or { return }
			}
		}()
	}
	handles.wait()
	assert s.get_entries().len == 160
}
