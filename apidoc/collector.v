module apidoc

// collector.v — 请求 / 响应拦截器（中间件核心）
//
// 在 veb.before_request 和 veb.after_request 中调用，
// 零侵入地采集所有路由的请求和响应数据。
//
// 使用方式：
//   app.api_doc.collect(mut ctx.Context)   // before_request
//   app.api_doc.collect_response(mut ctx.Context) // after_request

import veb

// ============================================================
// 标准 HTTP 头（不记录的请求头）
// ============================================================

const standard_headers = {
	'accept': true
	'accept-encoding': true
	'accept-language': true
	'cache-control': true
	'connection': true
	'content-length': true
	'host': true
	'user-agent': true
	'upgrade-insecure-requests': true
	'sec-fetch-dest': true
	'sec-fetch-mode': true
	'sec-fetch-site': true
	'sec-fetch-user': true
	'sec-ch-ua': true
	'sec-ch-ua-mobile': true
	'sec-ch-ua-platform': true
	'dnt': true
	'pragma': true
	'referer': true
	'te': true
	'transfer-encoding': true
	'x-request-id': true
	'x-forwarded-for': true
	'x-forwarded-proto': true
	'x-forwarded-host': true
	'x-real-ip': true
}

// ============================================================
// 以下敏感头，值会被自动脱敏
// ============================================================

const sensitive_headers = {
	'authorization': true
	'cookie': true
	'set-cookie': true
	'x-csrf-token': true
	'x-xsrf-token': true
	'x-api-key': true
}

// ============================================================
// Collector — 运行时采集器
// ============================================================

pub struct Collector {
pub mut:
	store &ApiDocStore
}

// new_collector 创建采集器
pub fn new_collector(store &ApiDocStore) &Collector {
	return &Collector{
		store: store
	}
}

// ============================================================
// 请求采集
// ============================================================

// collect 在 before_request 阶段调用，采集请求数据
pub fn (mut c Collector) collect(mut ctx veb.Context) {
	method := ctx.req.method.str()
	path := ctx.req.url

	// 跳过文档自身 API
	if path.starts_with('/__docs') {
		return
	}

	// 获取或创建条目
	mut entry := c.store.get_or_create(method, strip_query(path))

	// 解析 query 参数
	query_params := parse_query(ctx.req.url)
	for key, vals in query_params {
		val := if vals.len > 0 { vals[0] } else { '' }
		mut found := false
		for mut p in entry.parameters {
			if p.name == key && p.location == 'query' {
				found = true
				p.example = val
				break
			}
		}
		if !found {
			entry.parameters << ApiParameter{
				name: key
				location: 'query'
				type_: infer_param_type(val)
				example: val
			}
		}
	}

	// 读取请求头（排除标准头，脱敏敏感头）
	non_default_headers := extract_non_default_headers(mut ctx)
	for hdr_name, hdr_val in non_default_headers {
		mut found := false
		for mut eh in entry.headers {
			if eh.name == hdr_name {
				found = true
				if !eh.locked {
					eh.value = hdr_val
				}
				break
			}
		}
		if !found {
			entry.headers << ApiHeader{
				name: hdr_name
				value: hdr_val
			}
		}
	}
}

// ============================================================
// 响应采集
// ============================================================

// collect_response 在 after_request 阶段调用，采集响应数据
pub fn (mut c Collector) collect_response(mut ctx veb.Context) {
	path := ctx.req.url
	if path.starts_with('/__docs') {
		return
	}

	method := ctx.req.method.str()
	id := build_id(method, strip_query(path))
	mut existing := c.store.entries[id] or { return }

	// 响应状态码
	status := ctx.res.status_code
	if status > 0 {
		existing.response.status_code = status
	}

	// 尝试读取响应体
	// veb 在 after_request 时响应的 body 还在 ctx.res 中
	body := ctx.res.body
	if body.len > 0 {
		existing.response.raw_body = body

		// 推断 JSON 结构
		mut content_type := ''
		if ct := ctx.get_custom_header('Content-Type') {
			content_type = ct
		}
		if content_type.contains('json') || body.starts_with('{') || body.starts_with('[') {
			props := infer_json_structure(body, '')

			// 合并到现有属性（锁定保护）
			for new_prop in props {
				mut found := false
				for mut ep in existing.response.properties {
					if ep.path == new_prop.path {
						found = true
						if !ep.locked {
							ep.type_ = new_prop.type_
							ep.original_type = new_prop.type_
							ep.nullable = new_prop.nullable
						} else {
							ep.original_type = new_prop.type_
						}
						ep.example = new_prop.example
						break
					}
				}
				if !found {
					existing.response.properties << new_prop
				}
			}
		}
	}
}

// ============================================================
// 工具函数
// ============================================================

// strip_query 去掉 URL 中的查询参数部分
fn strip_query(url string) string {
	pos := url.index('?') or { return url }
	return url[..pos]
}

// parse_query 解析 URL 查询参数
fn parse_query(url string) map[string][]string {
	mut result := map[string][]string{}
	pos := url.index('?') or { return result }
	query := url[pos + 1..]
	if query.len == 0 {
		return result
	}
	for pair in query.split('&') {
	    eq_pos := pair.index('=') or { 0 }
	    key := if eq_pos > 0 { pair[..eq_pos] } else { pair }
	    val := if eq_pos > 0 { pair[eq_pos + 1..] } else { '' }
	    result[key] << val
	}
	return result
}

// infer_param_type 根据值推断参数类型
fn infer_param_type(val string) string {
	if val.len == 0 {
		return 'string'
	}
	if val == 'true' || val == 'false' {
		return 'boolean'
	}
	if val.int() != 0 || val == '0' {
		return 'integer'
	}
	if val.contains('.') {
		// 尝试解析为 f64
		if val.f64() != 0.0 || val == '0.0' {
			return 'number'
		}
		// 检查是否以数字开头且含小数点
		if val.len > 0 && val[0].is_digit() {
			return 'number'
		}
	}
	return 'string'
}

// extract_non_default_headers 提取非标准请求头
fn extract_non_default_headers(mut ctx veb.Context) map[string]string {
	mut result := map[string]string{}
	// 通过 veb.Context 的 get_custom_header 能力探测常见头
	// veb 不暴露完整的 header map，我们探测已知的非标准头
	// 同时捕获取自定义头

	// 尝试获取常见的自定义头
	custom_candidates := [
		'Authorization',
		'X-CSRF-TOKEN',
		'X-XSRF-TOKEN',
		'X-API-Key',
		'X-Requested-With',
		'Origin',
		'Content-Type',
		'If-None-Match',
		'If-Modified-Since',
		'Range',
	]

	for name in custom_candidates {
		val := ctx.get_custom_header(name) or { continue }
		lower := name.to_lower()
		if lower in standard_headers {
			continue
		}
		mut masked := val
		if lower in sensitive_headers {
			masked = mask_sensitive(val)
		}
		result[name] = masked
	}

	return result
}

// mask_sensitive 脱敏敏感头（如 Authorization: Bearer xxxx...）
fn mask_sensitive(val string) string {
	if val.len <= 8 {
		return '****'
	}
	return val[..4] + '****' + val[val.len - 4..]
}

// ============================================================
// JSON 结构推断（字符串解析，不依赖 json2.Any）
// ============================================================

// infer_json_structure 从 JSON 字符串推断属性结构
fn infer_json_structure(body string, prefix string) []BodyProperty {
	mut props := []BodyProperty{}
	trimmed := body.trim_space()

	if trimmed.len == 0 {
		return props
	}

	// 简单 JSON 对象解析：假设格式为 {"key": value, "key2": value2}
	if trimmed.starts_with('{') {
		inner := trimmed[1..trimmed.len - 1].trim_space()
		if inner.len == 0 {
			return props
		}

		// 按顶层逗号分割
		mut depth := 0
		mut start := 0
		for i := 0; i < inner.len; i++ {
			ch := inner[i]
			if ch == `{` || ch == `[` {
				depth++
			} else if ch == `}` || ch == `]` {
				depth--
			} else if ch == `,` && depth == 0 {
				parse_json_kv(inner[start..i], prefix, mut props)
				start = i + 1
			}
		}
		if start < inner.len {
			parse_json_kv(inner[start..].trim_space(), prefix, mut props)
		}
	}

	return props
}

// parse_json_kv 解析单个 "key": value 对
fn parse_json_kv(pair_str string, prefix string, mut props []BodyProperty) {
	pair := pair_str.trim_space()
	if pair.len == 0 {
		return
	}
	// 找第一个冒号（不在引号内）
	mut depth := 0
	mut in_str := false
	mut colon_pos := -1
	for i := 0; i < pair.len; i++ {
		if pair[i] == `"` && (i == 0 || pair[i - 1] != `\\`) {
			in_str = !in_str
		}
		if !in_str && pair[i] == `:` && depth == 0 {
			colon_pos = i
			break
		}
		if !in_str && (pair[i] == `{` || pair[i] == `[`) {
			depth++
		}
		if !in_str && (pair[i] == `}` || pair[i] == `]`) {
			depth--
		}
	}
	if colon_pos < 0 {
		return
	}

	key_raw := pair[..colon_pos].trim_space()
	key_stripped := key_raw.trim('"')
	full_path := if prefix.len > 0 { '${prefix}.${key_stripped}' } else { key_stripped }

	value_raw := pair[colon_pos + 1..].trim_space()

	// 推断类型和示例
	mut prop_type := 'string'
	mut example := value_raw
	mut nullable := false

	if value_raw.starts_with('"') {
		prop_type = 'string'
		example = value_raw.trim('"')
	} else if value_raw == 'true' || value_raw == 'false' {
		prop_type = 'boolean'
		example = value_raw
	} else if value_raw == 'null' {
		prop_type = 'string'
		example = ''
		nullable = true
	} else if value_raw.starts_with('{') {
		prop_type = 'object'
		example = '{...}'
		// 递归
		nested := infer_json_structure(value_raw, full_path)
		props << nested
	} else if value_raw.starts_with('[') {
		prop_type = 'array'
		example = '[...]'
	} else if value_raw.contains('.') {
		prop_type = 'number'
		example = value_raw
	} else if value_raw.len > 0 && value_raw[0].is_digit() {
		prop_type = 'integer'
		example = value_raw
	}

	// 去重检查
	for p in props {
		if p.path == full_path {
			return
		}
	}

	props << BodyProperty{
		path: full_path
		type_: prop_type
		original_type: prop_type
		example: example
		nullable: nullable
	}
}
