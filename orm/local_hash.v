module orm

// local_hash.v — 本模块私有的 FNV-1a 与 snake_case
//
// 为什么不直接用 support：
// ----------------------
// `support` 既是独立模块（`import support`），又因为 `photon.v` 声明
// `module photon` 而同时被注册成 `photon.support`。当编译单元里同时加载了
// 这两条路径时，V 会解析到 `photon.support` 那份「空的」函数表，于是
// `support.snake(...)` 变成 `unknown function`，整个模块链编译失败：
//
//     orm/entity.v:358:17: error: unknown function: support.snake
//     orm/entity.v:358:2:  error: `support.snake(field_name)` used as value
//
// 受影响的不只是 `v test`，任何 `import photon.web` / `import photon.orm`
// 的下游用户都会撞上 —— 这是一个对外可见的构建缺陷，不是测试环境怪癖。
//
// 缓存模块（cache/memory.v 的 support_fnv1a）早就因为同一原因做过同样的
// 事。这里把这两个函数常量级复制过来，代价是十几行代码，换来的是
// orm / web / core 对 support 不再有构建期依赖。

// fnv1a_str computes the FNV-1a 64-bit hash of a string by iterating over its
// bytes directly. Kept byte-identical to support.fnv1a_str.
@[direct_array_access; inline]
pub fn fnv1a_str(s string) u64 {
	mut hash := u64(14695981039346656037) // FNV offset basis
	for i in 0 .. s.len {
		hash = (hash ^ u64(s[i])) * u64(1099511628211) // FNV prime
	}
	return hash
}

// snake_case converts PascalCase / camelCase to snake_case.
// Acronyms stay together (`HTTPServer` → `http_server`), which matters for
// table names: `TableName('UserDOB')` must be `user_dobs`, not `user_d_o_bs`.
pub fn snake_case(s string) string {
	if s.len == 0 {
		return ''
	}
	mut buf := []u8{cap: s.len * 2}
	for i, ch in s {
		if snake_word_boundary(s, i) {
			buf << `_`
		}
		mut c := ch
		if c >= `A` && c <= `Z` {
			c += 32
		}
		buf << c
	}
	return buf.bytestr()
}

// snake_word_boundary reports whether a `_` belongs before s[i].
// Kept behaviourally identical to support/str.v's word_boundary_at:
//
//   - lower/digit → upper: `blogPost` → `blog_post`
//   - upper → upper followed by lower: `HTMLParser` → `html_parser`
//   - digit → lower: `Order2Item` → `order2_item`
fn snake_word_boundary(s string, i int) bool {
	if i == 0 {
		return false
	}
	prev := s[i - 1]
	cur := s[i]
	if cur >= `A` && cur <= `Z` {
		if (prev >= `a` && prev <= `z`) || (prev >= `0` && prev <= `9`) {
			return true
		}
		if prev >= `A` && prev <= `Z` && i + 1 < s.len {
			nxt := s[i + 1]
			return nxt >= `a` && nxt <= `z`
		}
	}
	return (cur >= `a` && cur <= `z`) && prev >= `0` && prev <= `9`
}
