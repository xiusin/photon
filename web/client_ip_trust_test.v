module web

import veb

// client_ip_trust_test.v —— 转发头只在「对端确实是代理」时才采信。
//
// 缺陷形状：client_ip() 无条件读 X-Forwarded-For / X-Real-IP。
// 这两个头是客户端自己写的，而它的返回值被当成客户端身份用于
// 限流分桶与访问日志 —— 伪造一个 XFF 就等于每次换一个新桶。

fn with_forwarded_header(ff string) &veb.Context {
	mut ctx := &veb.Context{}
	ctx.req.header.add_custom('X-Forwarded-For', ff) or {}
	return ctx
}

fn test_untrusted_proxy_headers_are_ignored() {
	set_trusted_proxies([])
	defer {
		set_trusted_proxies([])
	}
	ctx := with_forwarded_header('6.6.6.6')
	// 没有 conn（= 无对端地址）且未信任任何代理 → 绝不能返回客户端自报的地址
	assert client_ip(ctx) != '6.6.6.6'
	assert client_ip(ctx) == '-'
}

fn test_trusted_proxy_headers_are_used() {
	set_trusted_proxies(['*'])
	defer {
		set_trusted_proxies([])
	}
	ctx := with_forwarded_header('6.6.6.6, 10.0.0.1')
	// 采信时取最左一跳（真实客户端），而不是整串的第一段以外的内容
	assert client_ip(ctx) == '6.6.6.6'
}

fn test_trusted_exact_peer_matching() {
	set_trusted_proxies(['10.0.0.5'])
	defer {
		set_trusted_proxies([])
	}
	assert is_trusted_proxy('10.0.0.5')
	assert !is_trusted_proxy('10.0.0.6')
	// 空对端永远不可信 —— 否则「无连接上下文」会被当成代理
	assert !is_trusted_proxy('')
}

fn test_trusted_prefix_matching() {
	set_trusted_proxies(['10.0.0.'])
	defer {
		set_trusted_proxies([])
	}
	assert is_trusted_proxy('10.0.0.7')
	assert !is_trusted_proxy('10.0.1.7')
}

// 最直接的副作用断言：同一个伪造头，不信任时不该产生「新的客户端身份」。
fn test_forged_header_does_not_create_a_new_rate_limit_bucket() {
	set_trusted_proxies([])
	defer {
		set_trusted_proxies([])
	}
	mut ctx := new_middleware_context(with_forwarded_header('6.6.6.6'))
	k1 := throttle_key(ctx)
	ctx.ctx = with_forwarded_header('7.7.7.7')
	k2 := throttle_key(ctx)
	// 两个不同的伪造地址必须落到同一个桶里 —— 伪造不再能换来新配额
	assert k1 == k2
}
