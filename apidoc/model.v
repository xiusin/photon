module apidoc

// model.v — API 文档数据模型
//
// 定义文档条目的完整数据结构，支持"锁定"语义
// 使得用户编辑的字段不会被自动发现覆盖。

import json

// ============================================================
// ApiDocEntry — 单条 API 文档条目（唯一键: method:path）
// ============================================================

pub struct ApiDocEntry {
pub mut:
	id           string           // "{method}:{path}" 唯一键
	method       string           // GET / POST / PUT / DELETE / PATCH
	path         string           // /api/v1/users
	group        string           // 分组标签（可编辑）
	summary      string           // 摘要描述（可编辑锁定）
	description  string           // 详细说明（可编辑锁定）
	locked       bool             // 整条锁定标志
	is_hidden    bool             // 用户手动隐藏
	parameters   []ApiParameter   // 查询 + 路径参数
	headers      []ApiHeader      // 非标准请求头
	request_body ApiBodySchema    // 请求体 schema
	response     ApiResponse      // 响应分析
	first_seen   i64              // 首次发现时间戳(ms)
	last_seen    i64              // 最近访问时间戳(ms)
	hit_count    int              // 请求次数
}

// ============================================================
// ApiParameter — 单个请求参数
// ============================================================

pub struct ApiParameter {
pub mut:
	name        string // 参数名
	location    string // query / path / header
	type_       string // string / integer / boolean / number / array
	required    bool
	description string // 可编辑描述
	example     string // 最近观测示例值
	locked      bool   // 参数级锁定
}

// ============================================================
// ApiHeader — 请求头记录
// ============================================================

pub struct ApiHeader {
pub mut:
	name    string
	value   string // 示例值（自动脱敏）
	locked  bool
}

// ============================================================
// ApiBodySchema — 请求/响应体 schema
// ============================================================

pub struct ApiBodySchema {
pub mut:
	content_type string                    // application/json
	properties   map[string]BodyProperty   // key = 点号路径
	example      string                    // 原始 JSON 文本
}

// ============================================================
// BodyProperty — JSON 体中的单个属性
// ============================================================

pub struct BodyProperty {
pub mut:
	path          string // data.id
	type_         string // string / integer / boolean / array / object
	original_type string // 自动推断的类型（锁定后仍可见）
	description   string // 可编辑描述
	example       string // 示例值
	locked        bool   // 属性级锁定
	nullable      bool
}

// ============================================================
// ApiResponse — 响应汇总
// ============================================================

pub struct ApiResponse {
pub mut:
	status_code int              // 最后一次观测的状态码
	properties  []BodyProperty   // 响应属性列表
	raw_body    string           // 最近一次原始响应
}

// ============================================================
// 序列化 / 反序列化
// ============================================================

// to_json 将条目序列化为 JSON
pub fn (e &ApiDocEntry) to_json() string {
	return json.encode(e)
}

// entry_from_json 从 JSON 反序列化条目
pub fn entry_from_json(data string) !ApiDocEntry {
	return json.decode(ApiDocEntry, data)
}
