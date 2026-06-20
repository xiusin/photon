module main

// pagination_test.v — 分页器集成测试
//
// 测试覆盖：
//   - web.page 构建分页响应
//   - web.PageResult 序列化（含 pagination 元数据）
//   - web.Pagination 字段计算（total_pages / has_next / has_prev）

import json
import photon.web

fn test_web_page_basic() {
	result := web.page('{"items":[]}', 1, 20, 100)

	assert result.success == true
	assert result.code == 200
	assert result.pagination.page == 1
	assert result.pagination.page_size == 20
	assert result.pagination.total == 100
	assert result.pagination.total_pages == 5
	assert result.pagination.has_next == true
	assert result.pagination.has_prev == false
}

fn test_web_page_last_page() {
	result := web.page('{"items":[]}', 5, 20, 100)

	assert result.pagination.page == 5
	assert result.pagination.has_next == false
	assert result.pagination.has_prev == true
}

fn test_web_page_single_page() {
	result := web.page('{"items":[]}', 1, 20, 15)

	assert result.pagination.total_pages == 1
	assert result.pagination.has_next == false
	assert result.pagination.has_prev == false
}

fn test_web_page_empty() {
	result := web.page('{"items":[]}', 1, 20, 0)

	assert result.pagination.total == 0
	assert result.pagination.total_pages == 0
	assert result.pagination.has_next == false
	assert result.pagination.has_prev == false
}

fn test_web_page_rounding() {
	// 101 条，每页 20 → 6 页
	result := web.page('{"items":[]}', 1, 20, 101)
	assert result.pagination.total_pages == 6
}

fn test_page_result_to_json() {
	result := web.page('{"id":1}', 2, 10, 50)
	json_str := result.to_json()

	// 应包含标准响应字段
	assert json_str.contains('"success":true')
	assert json_str.contains('"code":200')

	// 应包含 pagination 元数据
	assert json_str.contains('"pagination":')
	assert json_str.contains('"page":2')
	assert json_str.contains('"page_size":10')
	assert json_str.contains('"total":50')
	assert json_str.contains('"total_pages":5')
	assert json_str.contains('"has_next":true')
	assert json_str.contains('"has_prev":true')
}

fn test_page_result_with_resource_data() {
	// 模拟控制器中的用法：将 Resource 列表编码后传入 web.page
	mut users := []UserResource{}
	users << UserResource{id: 1, username: 'alice', role: 'USER'}
	users << UserResource{id: 2, username: 'bob', role: 'EDITOR'}

	data_json := json.encode(users)
	result := web.page(data_json, 1, 20, 2)
	json_str := result.to_json()

	// data 字段应包含用户列表
	assert json_str.contains('alice')
	assert json_str.contains('bob')
	assert json_str.contains('"total":2')
}

fn test_pagination_struct_fields() {
	p := web.Pagination{
		page:        3
		page_size:   15
		total:       42
		total_pages: 3
		has_next:    false
		has_prev:    true
	}

	assert p.page == 3
	assert p.page_size == 15
	assert p.total == 42
	assert p.total_pages == 3
	assert p.has_next == false
	assert p.has_prev == true
}
