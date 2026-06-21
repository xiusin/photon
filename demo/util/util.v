module util

import os
import time
import crypto.rand
import encoding.hex
import photon.cache as pcache
import json
import veb

// generate_request_id 生成 UUID v4 风格的请求 ID
pub fn generate_request_id() string {
	mut bytes := rand.read(16) or {
		mut fallback := []u8{len: 16}
		ts := time.now().unix_nano()
		for i in 0 .. 16 {
			fallback[i] = u8((ts >> ((i % 8) * 8)) & 0xff)
		}
		fallback
	}
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	hex_str := hex.encode(bytes)
	return '${hex_str[0..8]}-${hex_str[8..12]}-${hex_str[12..16]}-${hex_str[16..20]}-${hex_str[20..32]}'
}

// generate_slug 将标题转换为 URL 友好的 slug
pub fn generate_slug(title string) string {
	mut slug := title.to_lower()
	slug = slug.replace(' ', '-')
	slug = slug.replace('_', '-')
	mut result := []u8{}
	for ch in slug {
		if (ch >= `a` && ch <= `z`) || (ch >= `0` && ch <= `9`) || ch == `-` {
			result << u8(ch)
		}
	}
	slug = result.bytestr()
	for slug.starts_with('-') {
		slug = slug[1..]
	}
	for slug.ends_with('-') {
		slug = slug[..slug.len - 1]
	}
	if slug.len == 0 {
		slug = 'item'
	}
	return slug
}

// now_unix 返回当前 Unix 时间戳
pub fn now_unix() i64 {
	return time.now().unix()
}

// now_rfc3339 返回 RFC3339 格式时间字符串
pub fn now_rfc3339() string {
	return time.now().format_rfc3339()
}

// cache_remember 泛型缓存辅助
pub fn cache_remember[T](mut cm pcache.CacheManager, key string, ttl int, loader fn () !T) !T {
	if cm.has(key) {
		cached := cm.get(key) or { '' }
		if cached.len > 0 {
			value := json.decode(T, cached) or {
				cm.delete(key) or {}
				loaded := loader()!
				cm.set(key, json.encode(loaded), ttl) or {}
				return loaded
			}
			return value
		}
	}
	value := loader()!
	cm.set(key, json.encode(value), ttl) or {}
	return value
}

// flush_cache_tag 失效指定标签下的所有缓存键
pub fn flush_cache_tag(cm pcache.Cache, tag string) {
	mut tc := pcache.new_tagged_cache(cm, [tag])
	tc.flush() or {}
}

// load_env_file 解析 .env 文件并设置环境变量
pub fn load_env_file(path string) {
	content := os.read_file(path) or { return }
	for line in content.split('\n') {
		mut l := line.trim_space()
		if l.len == 0 || l.starts_with('#') {
			continue
		}
		parts := l.split_nth('=', 2)
		if parts.len < 2 {
			continue
		}
		key := parts[0].trim_space()
		mut val := parts[1].trim_space()
		if val.len >= 2 && val.starts_with('"') && val.ends_with('"') {
			val = val[1..val.len - 1]
		}
		os.setenv(key, val, true)
	}
}

// parse_pagination 从请求上下文解析分页参数
pub fn parse_pagination(ctx &veb.Context) (int, int) {
	page_str := ctx.query['page'] or { '1' }
	page_size_str := ctx.query['page_size'] or { '20' }
	mut page := page_str.int()
	mut page_size := page_size_str.int()
	if page < 1 {
		page = 1
	}
	if page_size < 1 || page_size > 100 {
		page_size = 20
	}
	return page, page_size
}

// parse_sort 从请求上下文解析排序参数
pub fn parse_sort(ctx &veb.Context, allowed []string) (string, string) {
	sort_field := ctx.query['sort'] or { 'id' }
	sort_dir := ctx.query['order'] or { 'desc' }
	if sort_field !in allowed {
		return 'id', 'desc'
	}
	if sort_dir != 'asc' && sort_dir != 'desc' {
		return sort_field, 'desc'
	}
	return sort_field, sort_dir
}
