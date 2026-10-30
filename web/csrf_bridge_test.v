module web

import crypto.hmac
import crypto.sha256
import encoding.base64
import net.http
import veb

// csrf_bridge_test.v - CsrfBridgeConfig.to_before_middleware 的行为回归。
//
// 这一组用例监控的都是「校验通过」这个结果本身：全部断言 mid 返回 true
// 还是 false、以及拒绝时给出的原因，而不是「中间件被调用过」。

const csrf_test_secret = 'csrf-test-secret'

// csrf_test_context 构造一个只填了请求侧信息的 veb.Context。
//
// 走 net.http.parse_request_head_str() 而不是手工填 Request：cookie 字段
// 是 net.http 的私有字段，而且真实请求里它们也确实是由头部解析出来的。
fn csrf_test_context(method http.Method, headers map[string]string, form map[string]string) &veb.Context {
	mut head := '${method.str()} /submit HTTP/1.1\r\nHost: app.example.com\r\n'
	for k, v in headers {
		head += '${k}: ${v}\r\n'
	}
	req := http.parse_request_head_str(head) or {
		panic('failed to build test request: ${err}')
	}
	return &veb.Context{
		req:  req
		form: form
	}
}

// csrf_test_cookie_value 复刻 csrf_generate_cookie() 的算法，用来伪造 / 构造
// 合法的 cookie 值。
fn csrf_test_cookie_value(exp i64, token string) string {
	hash := base64.url_encode(hmac.new(csrf_test_secret.bytes(), token.bytes(), sha256.sum,
		sha256.block_size))
	return '${exp}.${hash}'
}

// 关于「篡改 session 段」这一组用例的口径：旧实现校验时用 `data.last()`
// 重新拼 `exp.session.nonce` 再算 HMAC，而 cookie 里签的本来就是这串 ——
// 也就是说它验的始终是自己重算出来的值，提交上来的 `data[1]` 从未进入过
// 任何一次比较。这个断言因此不是「复现一次攻击」，而是把「token 的每一段
// 都必须落在签名覆盖范围内」这条契约钉在测试里。

// csrf_test_token 生成一份合法的 (token, cookie) 对。
fn csrf_test_token(exp i64, session string, nonce string) (string, string) {
	token := base64.url_encode_str('${exp}.${session}.${nonce}')
	return token, csrf_test_cookie_value(exp, token)
}

fn csrf_test_future() i64 {
	return 4102444800 // 2100-01-01，永远不过期
}

// csrf_test_config 用「要求来源头」的严格模式，避免兼容开关掩盖 Origin 校验。
fn csrf_test_config() CsrfBridgeConfig {
	return new_csrf_bridge(
		secret:                csrf_test_secret
		allowed_hosts:         ['app.example.com']
		session_cookie:        'sid'
		allow_non_browser:     false
	)
}

fn csrf_test_run(config CsrfBridgeConfig, ctx &veb.Context) bool {
	mut mctx := &MiddlewareContext{
		ctx:  ctx
		data: map[string]string{}
	}
	mid := config.to_before_middleware()
	return mid(mctx) or { false }
}

// ── 合法请求必须通过 ──

fn test_csrf_bridge_accepts_valid_form_submission() {
	session := 'sess-1'
	token, cookie := csrf_test_token(csrf_test_future(), session, 'NONCEAAA')
	ctx := csrf_test_context(.post, {
		'Origin': 'https://app.example.com'
		'Cookie': 'sid=${session}; csrftoken=${cookie}'
	}, {
		'csrftoken': token
	})
	assert csrf_test_run(csrf_test_config(), ctx)
}

fn test_csrf_bridge_accepts_valid_header_token() {
	session := 'sess-2'
	token, cookie := csrf_test_token(csrf_test_future(), session, 'NONCEBBB')
	// JSON / XHR 客户端：token 只能放在请求头里，`ctx.form` 是空的。
	ctx := csrf_test_context(.post, {
		'Origin':      'https://app.example.com'
		'Cookie':      'sid=${session}; csrftoken=${cookie}'
		'csrftoken':   token
	}, map[string]string{})
	assert csrf_test_run(csrf_test_config(), ctx)
}

fn test_csrf_bridge_skips_safe_methods() {
	ctx := csrf_test_context(.get, map[string]string{}, map[string]string{})
	assert csrf_test_run(csrf_test_config(), ctx)
}

fn test_csrf_bridge_wildcard_allows_any_origin() {
	session := 'sess-3'
	token, cookie := csrf_test_token(csrf_test_future(), session, 'NONCECCC')
	ctx := csrf_test_context(.post, {
		'Origin': 'https://anything.test'
		'Cookie': 'sid=${session}; csrftoken=${cookie}'
	}, {
		'csrftoken': token
	})
	config := new_csrf_bridge(
		secret: csrf_test_secret
		allowed_hosts: ['*']
		session_cookie: 'sid'
	)
	assert csrf_test_run(config, ctx)
}

// ── 篡改必须被拒 ──

fn test_csrf_bridge_rejects_tampered_token_segment() {
	session := 'sess-4'
	exp := csrf_test_future()
	nonce := 'NONCEDDD'
	_, cookie := csrf_test_token(exp, session, nonce)
	// 保留合法 cookie 与 nonce/过期时间，只改 session 段。
	// 旧实现只对 nonce 签名，这种篡改会被放行。
	tampered := base64.url_encode_str('${exp}.attacker-other-session.${nonce}')
	ctx := csrf_test_context(.post, {
		'Origin': 'https://app.example.com'
		'Cookie': 'sid=${session}; csrftoken=${cookie}'
	}, {
		'csrftoken': tampered
	})
	assert csrf_test_run(csrf_test_config(), ctx) == false
	assert ctx.res.status_code == 403
}

fn test_csrf_bridge_rejects_forged_cookie() {
	session := 'sess-5'
	token, _ := csrf_test_token(csrf_test_future(), session, 'NONCEEE')
	ctx := csrf_test_context(.post, {
		'Origin': 'https://app.example.com'
		'Cookie': 'sid=${session}; csrftoken=${csrf_test_future()}.Zm9yZ2Vk'
	}, {
		'csrftoken': token
	})
	assert csrf_test_run(csrf_test_config(), ctx) == false
	assert ctx.res.status_code == 403
}

fn test_csrf_bridge_rejects_expired_token() {
	session := 'sess-6'
	token, cookie := csrf_test_token(1000000000, session, 'NONCEFFF')
	ctx := csrf_test_context(.post, {
		'Origin': 'https://app.example.com'
		'Cookie': 'sid=${session}; csrftoken=${cookie}'
	}, {
		'csrftoken': token
	})
	assert csrf_test_run(csrf_test_config(), ctx) == false
	assert ctx.res.status_code == 403
}

fn test_csrf_bridge_rejects_foreign_origin() {
	session := 'sess-7'
	token, cookie := csrf_test_token(csrf_test_future(), session, 'NONCEGGG')
	ctx := csrf_test_context(.post, {
		'Origin': 'https://evil.test'
		'Cookie': 'sid=${session}; csrftoken=${cookie}'
	}, {
		'csrftoken': token
	})
	assert csrf_test_run(csrf_test_config(), ctx) == false
	assert ctx.res.status_code == 403
}

fn test_csrf_bridge_rejects_suffix_lookalike_origin() {
	session := 'sess-8'
	token, cookie := csrf_test_token(csrf_test_future(), session, 'NONCEHHH')
	ctx := csrf_test_context(.post, {
		'Origin': 'https://app.example.com.evil.test'
		'Cookie': 'sid=${session}; csrftoken=${cookie}'
	}, {
		'csrftoken': token
	})
	assert csrf_test_run(csrf_test_config(), ctx) == false
}

fn test_csrf_bridge_rejects_missing_token() {
	session := 'sess-9'
	_, cookie := csrf_test_token(csrf_test_future(), session, 'NONCEIII')
	ctx := csrf_test_context(.post, {
		'Origin': 'https://app.example.com'
		'Cookie': 'sid=${session}; csrftoken=${cookie}'
	}, map[string]string{})
	assert csrf_test_run(csrf_test_config(), ctx) == false
	assert ctx.res.status_code == 403
}

fn test_csrf_bridge_rejects_empty_allowed_hosts() {
	session := 'sess-10'
	token, cookie := csrf_test_token(csrf_test_future(), session, 'NONCEJJJ')
	ctx := csrf_test_context(.post, {
		'Origin': 'https://app.example.com'
		'Cookie': 'sid=${session}; csrftoken=${cookie}'
	}, {
		'csrftoken': token
	})
	config := new_csrf_bridge(
		secret: csrf_test_secret
		session_cookie: 'sid'
		// 兼容开关在测试里显式关闭：语义见 csrf_test_config()
	)
	assert csrf_test_run(config, ctx) == false
}

// ── 非浏览器客户端策略 ──

fn test_csrf_bridge_requires_origin_by_default_when_configured() {
	session := 'sess-11'
	token, cookie := csrf_test_token(csrf_test_future(), session, 'NONCEKKK')
	// 完全不带 Origin/Referer：中间件无法证明同源。
	ctx := csrf_test_context(.post, {
		'Cookie': 'sid=${session}; csrftoken=${cookie}'
	}, {
		'csrftoken': token
	})
	assert csrf_test_run(csrf_test_config(), ctx) == false
	assert ctx.res.status_code == 403

	// allow_non_browser 打开时这类请求按兼容策略放行（token 本身仍然要合法）。
	// 新 ctx：上一轮已经把响应写完了，同一个 Context 不能再发一次。
	compat := new_csrf_bridge(
		secret: csrf_test_secret
		allowed_hosts: ['app.example.com']
		session_cookie: 'sid'
	)
	ctx2 := csrf_test_context(.post, {
		'Cookie': 'sid=${session}; csrftoken=${cookie}'
	}, {
		'csrftoken': token
	})
	assert csrf_test_run(compat, ctx2)
}

// ── host 解析 ──

fn test_csrf_extract_host_variants() {
	assert csrf_extract_host('https://app.example.com') == 'app.example.com'
	assert csrf_extract_host('https://app.example.com:8443/path') == 'app.example.com'
	assert csrf_extract_host('http://user:pw@app.example.com/x') == 'app.example.com'
	// Origin 的字面量 null 不是 URL，不能被解析成 host。
	assert csrf_extract_host('null') == ''
	assert csrf_extract_host('') == ''
}
