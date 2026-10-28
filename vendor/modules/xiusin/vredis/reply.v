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
	// 错误回复不能被当成普通值读出（见 check() 的注释）。
	r.check() or { panic(err.msg()) }
	return match r.kind {
		.integer { r.int_val.str() }
		.nil_reply { '' }
		else { r.str_val }
	}
}

// bytestr is kept for backwards compatibility; it returns the same value
// as str().
@[inline]
pub fn (r Reply) bytestr() string {
	return r.str()
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
			out << elem.str()
		}
		return out
	}
	return [r.str()]
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
	return r.str() == v.str()
}

// data returns the raw bytes of str(). It is kept for backwards
// compatibility with callers that previously operated on []u8.
@[inline]
pub fn (r Reply) data() []u8 {
	return r.str().bytes()
}
