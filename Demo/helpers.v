module main

// helpers.v — PhotonBlog 集中式工具函数
//
// 将分散在各模块中的通用工具函数集中管理，降低心智成本、提升复用性：
//   1. generate_request_id  — UUID v4 风格请求 ID（原 middleware.v）
//   2. generate_slug        — URL 友好 slug 生成（原 services.v）
//   3. now_unix             — 当前 Unix 时间戳
//   4. now_rfc3339          — RFC3339 格式时间字符串
//   5. cache_remember       — 泛型缓存辅助（缓存未命中时执行 loader 并回填）
//   6. parse_pagination     — 从请求上下文解析分页参数
//   7. parse_sort           — 从请求上下文解析排序参数
//   8. load_env_file        — 解析 .env 文件并设置环境变量

import os
import time
import crypto.rand
import encoding.hex
import photon.cache
import veb
import json

// ═══════════════════════════════════════════════════════════
// 标识符生成
// ═══════════════════════════════════════════════════════════

// generate_request_id 生成 UUID v4 风格的请求 ID
// 格式：xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
pub fn generate_request_id() string {
	mut bytes := rand.read(16) or {
		// Fallback: 基于时间戳生成
		mut fallback := []u8{len: 16}
		ts := time.now().unix_nano()
		for i in 0 .. 16 {
			fallback[i] = u8((ts >> ((i % 8) * 8)) & 0xff)
		}
		fallback
	}

	// 设置 version 4 和 variant 位（UUID v4 规范）
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80

	hex_str := hex.encode(bytes)
	// 格式化为 UUID：8-4-4-4-12
	return '${hex_str[0..8]}-${hex_str[8..12]}-${hex_str[12..16]}-${hex_str[16..20]}-${hex_str[20..32]}'
}

// generate_slug 将标题转换为 URL 友好的 slug
// 规则：转小写 → 空格/下划线替换为连字符 → 移除非字母数字字符 → 修剪首尾连字符
pub fn generate_slug(title string) string {
	mut slug := title.to_lower()
	slug = slug.replace(' ', '-')
	slug = slug.replace('_', '-')
	// 保留小写字母、数字、连字符
	mut result := []u8{}
	for ch in slug {
		if (ch >= `a` && ch <= `z`) || (ch >= `0` && ch <= `9`) || ch == `-` {
			result << u8(ch)
		}
	}
	slug = result.bytestr()
	// 移除首尾连字符
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

// ═══════════════════════════════════════════════════════════
// 时间工具
// ═══════════════════════════════════════════════════════════

// now_unix 返回当前 Unix 时间戳
pub fn now_unix() i64 {
	return time.now().unix()
}

// now_rfc3339 返回 RFC3339 格式时间字符串
pub fn now_rfc3339() string {
	return time.now().format_rfc3339()
}

// ═══════════════════════════════════════════════════════════
// 缓存辅助
// ═══════════════════════════════════════════════════════════

// cache_remember 泛型缓存辅助：缓存不存在时执行 loader 并写入缓存
// 若缓存存在但 JSON 解码失败，则删除缓存重新加载，避免脏数据长期驻留
pub fn cache_remember[T](mut cm cache.CacheManager, key string, ttl int, loader fn () !T) !T {
	// 检查缓存
	if cm.has(key) {
		cached := cm.get(key) or { '' }
		if cached.len > 0 {
			// 尝试解码，失败则删除缓存重新加载
			value := json.decode(T, cached) or {
				cm.delete(key) or {}
				loaded := loader()!
				cm.set(key, json.encode(loaded), ttl) or {}
				return loaded
			}
			return value
		}
	}
	// 缓存未命中，执行 loader
	value := loader()!
	cm.set(key, json.encode(value), ttl) or {}
	return value
}

// flush_cache_tag 失效指定标签下的所有缓存键
// 使用 TaggedCache.flush() 批量删除以 tag 为前缀的所有键。
// 例如 flush_cache_tag(cm, 'posts') 会删除 'posts:1'、'posts:published' 等所有以 'posts:' 开头的键。
pub fn flush_cache_tag(cm &cache.CacheManager, tag string) {
	mut tc := cache.new_tagged_cache(cm.default_cache, [tag])
	tc.flush() or {}
}

// ═══════════════════════════════════════════════════════════
// 请求参数解析
// ═══════════════════════════════════════════════════════════

// parse_pagination 从请求上下文解析分页参数
// page 默认 1（最小 1），page_size 默认 20（范围 1-100）
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
// sort_field 必须在 allowed 列表中（默认 'id'），sort_dir 仅允许 'asc'/'desc'（默认 'desc'）
pub fn parse_sort(ctx &veb.Context, allowed []string) (string, string) {
	sort_field := ctx.query['sort'] or { 'id' }
	sort_dir := ctx.query['order'] or { 'desc' }
	// 验证 sort_field 在 allowed 列表中
	if sort_field !in allowed {
		return 'id', 'desc'
	}
	// 验证 sort_dir
	if sort_dir != 'asc' && sort_dir != 'desc' {
		return sort_field, 'desc'
	}
	return sort_field, sort_dir
}

// ═══════════════════════════════════════════════════════════
// 环境变量
// ═══════════════════════════════════════════════════════════

// load_env_file 解析 .env 文件并设置环境变量
// 格式：KEY=VALUE，支持 # 注释和双引号包裹的值；文件不存在时静默返回
pub fn load_env_file(path string) {
	content := os.read_file(path) or { return }
	for line in content.split('\n') {
		mut l := line.trim_space()
		if l.len == 0 || l.starts_with('#') {
			continue
		}
		// KEY=VALUE format
		parts := l.split_nth('=', 2)
		if parts.len < 2 {
			continue
		}
		key := parts[0].trim_space()
		mut val := parts[1].trim_space()
		// Remove surrounding quotes
		if val.len >= 2 && val.starts_with('"') && val.ends_with('"') {
			val = val[1..val.len - 1]
		}
		os.setenv(key, val, true)
	}
}
