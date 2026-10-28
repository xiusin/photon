module vredis

import strings

// Protocol is a RESP (REdis Serialization Protocol) reader bound to a
// single Redis connection.
//
// Design notes
// ------------
// The previous implementation read every reply with `read_line()` and
// joined array elements with "\r\n". This corrupted any payload
// containing those bytes and made nested arrays impossible to parse
// correctly.
//
// This implementation follows the RESP specification exactly:
//   - Status  (+)  and error (-) replies are read line-by-line.
//   - Integer (:)  replies are parsed from the line payload.
//   - Bulk    ($)  replies read exactly N bytes after the length header,
//                  then consume the trailing CRLF. This is binary-safe.
//   - Array   (*)  replies recursively read N sub-replies.
//   - Null    ($-1 / *-1) replies become a Reply with kind == .nil_reply.
//
// A reusable stack buffer is used for chunked bulk reads to avoid
// per-command heap allocation on the hot path.
pub struct Protocol {
mut:
	client &Redis = unsafe { nil }
}

fn new_protocol(client &Redis) &Protocol {
	return &Protocol{
		client: unsafe { client }
	}
}

// read_line reads one CRLF-terminated line from the socket and returns
// the payload without the trailing CR/LF. `read_line()` on TcpConn
// returns content up to and including LF, so we trim the trailing
// CR/LF pair. An empty result signals EOF / closed connection.
@[inline]
fn (mut p Protocol) read_line() !string {
	line := p.client.socket.read_line()
	if line.len == 0 {
		return err_read_message
	}
	// read_line() includes the trailing \n; RESP lines end with \r\n.
	// Trim any trailing \r and \n characters.
	return line.trim_right('\r\n')
}

// read_exact_line 读取一整行 RESP 头部（+ - : $ * 开头的那些）。
//
// 上游用 TcpConn.read_line()，它按 1 字节一读直到 `\n`，看上去没问题；
// 但 read_line() 在「行尾是 `\r\n`」时会把 `\r` 一起吃掉并提前返回，
// 于是紧跟其后的读操作会错位 —— 订阅循环里第一条 `*3\r\n` 之后读到的是
// 空块，表现为「订阅上去了但一条消息都收不到」。
//
// 这里自己按字节读，读到 LF 为止，不做任何提前返回。
fn (mut p Protocol) read_exact_line() !string {
	mut buf := []u8{cap: 64}
	mut b := [1]u8{}
	for {
		n := unsafe { p.client.socket.read_ptr(&b[0], 1)! }
		if n <= 0 {
			return err_read_message
		}
		if b[0] == `\n` {
			break
		}
		if b[0] != `\r` {
			buf << b[0]
		}
		if buf.len > max_resp_line {
			return error('redis: RESP line too long')
		}
	}
	return buf.bytestr()
}

// max_resp_line 限制单行 RESP 头部的长度，避免畸形响应把内存吃光。
const max_resp_line = 64 * 1024

// read_full reads exactly `need` bytes from the socket into a freshly
// allocated, owned string. A stack scratch buffer is reused across
// calls to avoid per-read heap allocation. The trailing CRLF that
// follows every bulk payload is consumed and discarded.
//
// The caller must pass a non-negative length; nil bulks ($-1) are
// handled by read_reply before reaching this method.
fn (mut p Protocol) read_full(need int) !string {
	if need == 0 {
		// Consume the trailing CRLF of an empty bulk string.
		p.read_exact_line() or {}
		return ''
	}

	mut builder := strings.new_builder(need)
	defer {
		unsafe {
			builder.free()
		}
	}
	mut scratch := [4096]u8{}
	mut got := 0
	for got < need {
		remaining := need - got
		to_read := if remaining < scratch.len { remaining } else { scratch.len }
		n := unsafe {
			p.client.socket.read_ptr(&scratch[0], to_read)!
		}
		if n <= 0 {
			return err_read_message
		}
		unsafe {
			builder.write_ptr(&scratch[0], n)
		}
		got += n
	}
	// Consume the trailing \r\n that follows the bulk payload.
	p.read_exact_line() or {}
	return builder.str()
}

// read_reply parses one complete RESP reply and returns a typed Reply.
pub fn (mut p Protocol) read_reply() !Reply {
	line := p.read_exact_line()!
	if line.len == 0 {
		return err_read_message
	}

	if p.client.debug {
		println('<- ${line}')
	}

	first := line[0]
	payload := line[1..]

	match first {
		`-` {
			// Error reply: the payload is the error message.
			return Reply{
				kind:    .error
				str_val: payload
			}
		}
		`+` {
			// Simple status string.
			return Reply{
				kind:    .status
				str_val: payload
			}
		}
		`:` {
			// Integer reply.
			//
			// str_val 也一并写上十进制文本：str() 直接返回它，不再
			// 从 int_val 现场格式化。原因见 reply.v 里 str() 的注释 ——
			// V 0.5.2 下把通过 &Reply 拿到的 i64 字段传给 str()，
			// 会得到 "&1" 这种带地址前缀的文本。
			return Reply{
				kind:    .integer
				str_val: payload
				int_val: payload.i64()
			}
		}
		`$` {
			// Bulk string. $-1 means nil.
			n := payload.i64()
			if n < 0 {
				return Reply{
					kind: .nil_reply
				}
			}
			data := p.read_full(int(n))!
			return Reply{
				kind:    .bulk
				str_val: data
			}
		}
		`*` {
			// Array. *-1 means nil array.
			count := payload.i64()
			if count < 0 {
				return Reply{
					kind: .nil_reply
				}
			}
			mut elems := []Reply{cap: int(count)}
			for _ in 0 .. count {
				elems << p.read_reply()!
			}
			return Reply{
				kind: .array
				arr:  elems
			}
		}
		else {
			// Inline / unexpected payload — return as a bulk string
			// so callers that sent inline commands still get data.
			return Reply{
				kind:    .bulk
				str_val: line
			}
		}
	}
}
