module orm

// local_hash.v — 本模块私有的 FNV-1a 与 snake_case
//
// 为什么这里是一份副本：
// --------------------
// 这是性能选择，不是构建约束。`strutil.snake` 走的是同一条逐字节扫描，
// 但 `orm` 在实体映射的热路径上（每个字段、每次派生查询解析）都要算一次
// 表名/列名，多一层跨模块调用没有收益。`fnv1a_str` 同理，它只服务分片选择。
//
// 历史提示：这份副本最初是为了绕开「`support` 同时被注册成 `photon.support`，
// 解析到空函数表」的构建缺陷（见 ARCHITECTURE.md 8.10）。那个缺陷已经从根上
// 消掉了 —— 模块现在叫 `strutil`，不再是 `photon.` 前缀。副本留着只是因为
// 上面那条性能理由，编不过的问题不再存在。
//
// 副本最大的风险是「改了一边忘了另一边」，所以 orm/local_hash_test.v 与
// strutil 的用例各自钉了一张字符向量表；两边只要有一天给出不同结果，
// 至少有一侧会红。

// fnv1a_str computes the FNV-1a 64-bit hash of a string by iterating over its
// bytes directly. Kept byte-identical to strutil.fnv1a_str.
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
// Kept behaviourally identical to strutil/str.v word_boundary_at:
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
