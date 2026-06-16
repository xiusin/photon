module apidoc

// store.v — API 文档持久化存储 & 锁定合并引擎
//
// 职责：
//   1. JSON 文件读写（逐条存储，按 method:path 命名）
//   2. 自动发现新数据与锁定字段的智能合并
//   3. 线程安全的原子更新

import os
import json
import time

// ============================================================
// ApiDocStore — 文档存储
@[heap]
pub struct ApiDocStore {
pub mut:
	entries  map[string]&ApiDocEntry // key = id ("{method}:{path}")
mut:
	data_dir string
}

// new_store 创建文档存储，指定数据目录
pub fn new_store(data_dir string) !&ApiDocStore {
	os.mkdir_all(data_dir) or { return error('cannot create doc store dir: ${err}') }
	mut s := &ApiDocStore{
		data_dir: data_dir
	}
	s.load_all() or { /* first run, empty */ }
	return s
}

// ============================================================
// 持久化基础操作
// ============================================================

// file_path 返回条目的磁盘路径
fn (s &ApiDocStore) file_path(id string) string {
	// 将 "GET:/api/v1/users" 转为合法文件名
	mut safe_name := id.replace('/', '_').replace(':', '_').replace('?', '_').replace('&', '_').replace('=', '_')
	// 限制长度防止路径问题
	if safe_name.len > 200 {
		safe_name = safe_name[..200]
	}
	return os.join_path(s.data_dir, safe_name + '.json')
}

// save_entry 将单条写入磁盘
pub fn (mut s ApiDocStore) save_entry(id string) ! {
	entry := s.entries[id] or { return error('entry not found: ${id}') }
	fpath := s.file_path(id)
	os.write_file(fpath, entry.to_json()) or {
		return error('failed to write doc entry: ${err}')
	}
}

// load_all 从磁盘加载所有条目
pub fn (mut s ApiDocStore) load_all() ! {
	files := os.ls(s.data_dir) or { return }
	for fname in files {
		if !fname.ends_with('.json') {
			continue
		}
		fpath := os.join_path(s.data_dir, fname)
		data := os.read_file(fpath) or { continue }
		entry := json.decode(ApiDocEntry, data) or { continue }
		s.entries[entry.id] = &entry
	}
}

// ============================================================
// CRUD 操作
// ============================================================

// get_or_create 获取已有条目或创建新的
pub fn (mut s ApiDocStore) get_or_create(method string, path string) &ApiDocEntry {
	id := '${method}:${path}'
	existing := s.entries[id] or {
		now_ms := time.now().unix_milli()
		new_entry := &ApiDocEntry{
			id: id
			method: method
			path: path
			group: extract_group(path)
			first_seen: now_ms
			last_seen: now_ms
			hit_count: 1
		}
		s.entries[id] = new_entry
		s.save_entry(id) or { /* silent fail on first save */ }
		return new_entry
	}
	unsafe {
		existing.last_seen = time.now().unix_milli()
		existing.hit_count++
	}
	return existing
}

// get_entry 获取单条
pub fn (s &ApiDocStore) get_entry(id string) !&ApiDocEntry {
	return s.entries[id] or { return error('entry not found: ${id}') }
}

// get_entries 获取所有条目（按分组排序）
pub fn (s &ApiDocStore) get_entries() []&ApiDocEntry {
	mut result := []&ApiDocEntry{}
	for _, e in s.entries {
		result << e
	}
	// 按 group → path → method 排序（手动冒泡）
	for i in 0 .. result.len {
		for j in i + 1 .. result.len {
			mut cmp := false
			if result[i].group != result[j].group {
				cmp = result[i].group > result[j].group
			} else if result[i].path != result[j].path {
				cmp = result[i].path > result[j].path
			} else {
				cmp = result[i].method > result[j].method
			}
			if cmp {
				result[i], result[j] = result[j], result[i]
			}
		}
	}
	return result
}

// update_entry 更新条目（用户编辑/锁定）
pub fn (mut s ApiDocStore) update_entry(id string, updated ApiDocEntry) ! {
	existing := s.entries[id] or { return error('entry not found: ${id}') }
	mut upd := updated
	// 保留系统字段
	upd.first_seen = existing.first_seen
	upd.last_seen = time.now().unix_milli()
	upd.hit_count = existing.hit_count
	s.entries[id] = &upd
	s.save_entry(id)!
}

// delete_entry 删除条目
pub fn (mut s ApiDocStore) delete_entry(id string) ! {
	if id !in s.entries {
		return error('entry not found: ${id}')
	}
	s.entries.delete(id)
	fpath := s.file_path(id)
	os.rm(fpath) or { /* already gone */ }
}

// ============================================================
// 锁定合并引擎（核心）
// ============================================================

// merge_observed 将自动发现的数据合并到现有条目，遵循锁定规则
pub fn (mut s ApiDocStore) merge_observed(observed ApiDocEntry) ! {
	existing := s.entries[observed.id] or {
		// 全新条目 — 直接存入
		s.entries[observed.id] = &observed
		s.save_entry(observed.id) or { /* silent */ }
		return
	}

	// ---- 整条锁定保护 ----
	if existing.locked {
		// 只更新元数据 + raw body 示例，不覆盖描述/字段
		unsafe {
			existing.last_seen = observed.last_seen
			existing.hit_count = observed.hit_count
		}
		if observed.response.raw_body.len > 0 {
			unsafe { existing.response.raw_body = observed.response.raw_body }
		}
		s.save_entry(existing.id) or { /* silent */ }
		return
	}

	// ---- 参数合并 ----
	for new_param in observed.parameters {
		mut found := false
		for i := 0; i < existing.parameters.len; i++ {
			if existing.parameters[i].name == new_param.name && existing.parameters[i].location == new_param.location {
				found = true
				if !existing.parameters[i].locked {
					unsafe {
						existing.parameters[i].type_ = new_param.type_
						existing.parameters[i].required = new_param.required
						existing.parameters[i].description = new_param.description
					}
				}
				unsafe { existing.parameters[i].example = new_param.example }
				break
			}
		}
		if !found {
			unsafe { existing.parameters << new_param }
		}
	}

	// ---- 请求头合并 ----
	for new_hdr in observed.headers {
		mut found := false
		for i := 0; i < existing.headers.len; i++ {
			if existing.headers[i].name == new_hdr.name {
				found = true
				if !existing.headers[i].locked {
					unsafe { existing.headers[i].value = new_hdr.value }
				}
				break
			}
		}
		if !found {
			unsafe { existing.headers << new_hdr }
		}
	}

	// ---- 响应体属性合并 ----
	if observed.response.properties.len > 0 {
		for new_prop in observed.response.properties {
			mut found := false
			for i := 0; i < existing.response.properties.len; i++ {
				if existing.response.properties[i].path == new_prop.path {
					found = true
					if !existing.response.properties[i].locked {
						unsafe {
							existing.response.properties[i].type_ = new_prop.type_
							existing.response.properties[i].original_type = new_prop.type_
							existing.response.properties[i].description = new_prop.description
							existing.response.properties[i].nullable = new_prop.nullable
						}
					} else {
						unsafe { existing.response.properties[i].original_type = new_prop.type_ }
					}
					unsafe { existing.response.properties[i].example = new_prop.example }
					break
				}
			}
			if !found {
				mut prop := new_prop
				prop.original_type = prop.type_
				unsafe { existing.response.properties << prop }
			}
		}
	}

	// ---- 请求体 schema 合并 ----
	if observed.request_body.properties.len > 0 {
		for key, new_prop in observed.request_body.properties {
			unsafe { existing.request_body.properties[key] = new_prop }
		}
		if observed.request_body.example.len > 0 {
			unsafe { existing.request_body.example = observed.request_body.example }
		}
	}

	// ---- 响应原始体 + 状态码 ----
	if observed.response.raw_body.len > 0 {
		unsafe { existing.response.raw_body = observed.response.raw_body }
	}
	if observed.response.status_code > 0 {
		unsafe { existing.response.status_code = observed.response.status_code }
	}

	// ---- 元信息 ----
	unsafe {
		existing.last_seen = observed.last_seen
		existing.hit_count = observed.hit_count
	}

	// 持久化
	s.save_entry(existing.id) or { /* silent */ }
}

// ============================================================
// 工具函数
// ============================================================

// extract_group 从路径中提取默认分组名（path 的第一段）
fn extract_group(path string) string {
	parts := path.split('/')
	for p in parts {
		if p.len > 0 && p[0] != `/` && p[0] != `{` {
			return p
		}
	}
	return 'default'
}

// build_id 构造唯一键
pub fn build_id(method string, path string) string {
	return '${method}:${path}'
}
