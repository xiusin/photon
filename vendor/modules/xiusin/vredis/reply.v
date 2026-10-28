module vredis

// ReplyKind enumerates the RESP reply types returned by a Redis server.
pub enum ReplyKind {
	status    // +OK\r\n — simple status string
	error     // -ERR ...\r\n — error reply
	integer   // :123\r\n — 64-bit signed integer
	bulk      // $N\r\n<bytes>\r\n — bulk string (binary safe)
	array     // *N\r\n... — nested array of replies
	nil_reply // $-1\r\n or *-1\r\n — null bulk / null array
}

// Reply is a typed, parsed representation of a single Redis RESP reply.
//
// The previous implementation stored every reply as a raw []u8 and joined
// array elements with "\r\n", which corrupted any payload containing those
// bytes. This typed representation preserves structure and avoids repeated
// string conversions.
pub struct Reply {
pub:
	kind    ReplyKind
	str_val string  // payload for status / bulk / error-message
	int_val i64     // payload for integer replies
	arr     []Reply // payload for array replies (values stored inline)
}

const ok_flag = 'OK'

const crlf = '\r\n'

// ok reports whether the reply is a simple-status "OK".
@[inline]
pub fn (r Reply) ok() bool {
	return r.kind == .status && r.str_val == ok_flag
}

// err returns the error message carried by an error reply, or an empty
// string for every other reply kind.
//
// 上游在 read_reply 里把 `-ERR ...` 解析成 .error 之后就没人管了：所有
// 「返回 bool/数值」的写命令都用 .ok() / .int() / .str() 判读，于是
//   * `SET k v NX` 撞上已存在的键（返回 nil）→ false，看着像「业务不满足」
//   * `INCR` 打在非数字值上（-ERR）→ .int() 把错误文本 `int()` 成 0
//   * `RENAME` 目标不存在（-ERR）→ .ok() 为 false
// 调用方拿到的都是「不报错但结果是错的答案」。
//
// V 的 accessor 不能返回 error（方法签名不带 `!`），所以错误传播放在
// `!` 方法里：string.v / hash.v / list.v 等命令包装统一先调 reply_or_err()
// 把 `-ERR` 转成 Result error，再由 `!` 往上传。
@[inline]
fn (r Reply) check() ! {
	if r.kind == .error {
		return error('redis: ${r.str_val}')
	}
}

// reply_or_err 把错误回复转成 Result error，其余回复原样返回。
// 所有返回 `!T` 的命令包装都应该在读取前调用它。
pub fn reply_or_err(reply &Reply) !&Reply {
	if reply.kind == .error {
		return error('redis: ${reply.str_val}')
	}
	// Reply 由 send() 返回，生命周期由 &Reply 持有；这里只是把不可变引用
	// 原样传出（V 对「函数返回栈对象的引用」保守报错）。
	return unsafe { reply }
}

// nil reports whether the reply is a Redis null (bulk or array).
@[inline]
pub fn (r Reply) nil() bool {
	return r.kind == .nil_reply
}

// str returns the canonical string representation of the reply payload.
// For integer replies this is the decimal text; for nil it is the empty
// string; otherwise it is the raw string payload. This is the single
// source of truth used by bytestr/is/data so conversions happen at most
// once per conceptual access.
//
// Note: callers that need to distinguish "key does not exist" from an
// empty string value must inspect `reply.kind == .nil_reply` (or use the
// command wrappers that return err_nil, such as get / hget / zscore).
@[inline]
pub fn (r Reply) str() string {
	// 这是 Reply 在字符串插值里的唯一入口。
	//
	// 注意：V 0.5.2 对 `&T` 上的 `str()` 有特殊插值路径 —— 不管是不是
	// 指针接收器，`'${p.str()}'` 都会在返回值前面加一个 "&"，长度也跟着
	// 地址变化（见下方 to_string 的注释）。所以 `str()` 只保留给插值/调试，
	// 需要精确文本的调用方请用 to_string()。
	return r.to_string()
}

// to_string 返回回复的精确文本表示，全仓内部一律用它。
//
// 为什么不能只留 str()：`send()` 返回 &Reply，调用方写 `reply.str()`
// 会命中 V 0.5.2 的 `&T` 插值特例，拿到 "&OK" 而不是 "OK" —— Lua 脚本
// 返回的 1/0、SET 的 OK、INCR 的计数全部比对失败，而且不报错。
// to_string 是个普通方法名，不进那条特例路径。
pub fn (r Reply) to_string() string {
	// 错误回复不能被当成普通值读出（见 check() 的注释）。
	r.check() or { panic(err.msg()) }
	if r.kind == .integer {
		// 整数回复的文本在解析时就写进 str_val 了（见 protocol.v）。
		//
		// 不能在这里写 `r.int_val.str()`：V 0.5.2 把「通过 &Reply 读到的
		// i64 字段」传给 builtin 的 str()/i64_str() 时，会产出 "&1" 而不
		// 是 "1" —— 响应前缀是地址，长度还随地址变。所有拿 eval/incr 结果
		// 做字符串比较的调用方（Lua 脚本返回 1/0、INCR 的计数）全部失准。
		if r.str_val.len > 0 {
			return r.str_val
		}
		return i64_str(r.int_val)
	}
	if r.kind == .nil_reply {
		return ''
	}
	return r.str_val
}

// i64_str 把 i64 转成十进制文本。
//
// 这里不能直接写 `r.int_val.str()`：当 int_val 来自一个通过 &Reply 访问的
// 字段时，V 0.5.2 会把它当成 i64 指针传进 builtin 的 str()，产出 "&1"
// 而不是 "1"。显式按值传入即可绕开。
@[inline]
fn i64_str(v i64) string {
	return '${v}'
}

// bytestr is kept for backwards compatibility; it returns the same value
// as str().
@[inline]
pub fn (r Reply) bytestr() string {
	return r.to_string()
}

// int returns the reply payload as a V int.
@[inline]
pub fn (r Reply) int() int {
	r.check() or { panic(err.msg()) }
	if r.kind == .integer {
		return int(r.int_val)
	}
	return r.str_val.int()
}

// i64 returns the reply payload as an i64.
@[inline]
pub fn (r Reply) i64() i64 {
	r.check() or { panic(err.msg()) }
	if r.kind == .integer {
		return r.int_val
	}
	return r.str_val.i64()
}

// f64 returns the reply payload as an f64.
@[inline]
pub fn (r Reply) f64() f64 {
	r.check() or { panic(err.msg()) }
	if r.kind == .integer {
		return f64(r.int_val)
	}
	return r.str_val.f64()
}

// strings returns the string elements of an array reply. For non-array
// replies a single-element slice containing str() is returned.
pub fn (r Reply) strings() []string {
	r.check() or { panic(err.msg()) }
	if r.kind == .array {
		mut out := []string{cap: r.arr.len}
		for elem in r.arr {
			out << elem.to_string()
		}
		return out
	}
	return [r.to_string()]
}

// array returns the nested reply elements for array replies.
@[inline]
pub fn (r Reply) array() []Reply {
	r.check() or { panic(err.msg()) }
	return r.arr
}

// is compares the reply payload with v using string equality. This
// generic form keeps the ergonomic `reply.is(1)` / `reply.is('PONG')`
// call sites working regardless of the integer/string reply kind.
// `is` is a V keyword, so the method name is escaped with `@`.
@[inline]
pub fn (r Reply) @is[T](v T) bool {
	return r.to_string() == v.str()
}

// data returns the raw bytes of the reply payload. Kept for backwards
// compatibility with callers that previously operated on []u8.
@[inline]
pub fn (r Reply) data() []u8 {
	return r.to_string().bytes()
}
