module web

// response_entity.v - ResponseEntity (Spring-inspired)
//
// Provides a typed, chainable response entity that carries HTTP status,
// headers, and a body. This is the Photon equivalent of Spring's
// ResponseEntity<T> — a type-safe alternative to manually setting
// status codes and headers on the response.
//
// Spring equivalent: org.springframework.http.ResponseEntity<T>
//
// ── Usage ──
//
//   // 200 + JSON body
//   return web.ok_entity[User](user).to_result(mut ctx)
//
//   // 201 + Location（工厂返回 &T，可以直接链）
//   return web.created_entity[User](user)
//       .location('/api/users/${user.id}')
//       .to_result(mut ctx)
//
//   // 自定义状态码与响应头
//   return web.no_content_entity[string]()
//       .set_status(304)
//       .etag('"v3"')
//       .to_result(mut ctx)
//
//   // 错误响应（无 body）
//   return web.not_found_entity[string]().to_result(mut ctx)
//
// 注意命名：工厂都是 `*_entity` 后缀（ok_entity / created_entity /
// not_found_entity …），与 http 模块的 RequestEntity/ResponseEntity 风格一致。
// 早期文档里写的 web.response_entity / web.created / web.not_found 从未存在过。
import veb
import x.json2
import net.http

// ── ResponseEntity ──

// ResponseEntity wraps an HTTP response with typed body, status code,
// and headers. The body type T is generic — use json2.encode() to
// serialize it.
//
// Spring equivalent: ResponseEntity<T>
//
// Thread-safety: ResponseEntity is a request-scoped, single-thread
// object. No locking is needed — it is built via chained calls in
// a single goroutine and consumed immediately.
//
// @[heap] 是链式 API 成立的前提：工厂返回 `&ResponseEntity[T]`，而 V 不允许
// 把可能指向栈上对象的指针返回出去。不加这个属性，工厂函数一编译就报
// "cannot be returned outside `unsafe` blocks as it might refer to an
// object stored on stack"。
@[heap]
pub struct ResponseEntity[T] {
pub mut:
	// status / headers 必须可变：链式方法（header/content_type/location/
	// etag/set_status）通过 `&ResponseEntity[T]` 原地修改它们。
	// 只写 `pub:` 时这些字段是只读的，`re.headers[k] = v` 会报
	// "field `headers` is immutable" —— 整个文件因此编译不过。
	status  int = 200
	headers map[string]string
pub:
	body     T
	has_body bool = true
}

// ── Factory Functions ──

// ok_entity creates a ResponseEntity with 200 status and the given body.
// Spring equivalent: ResponseEntity.ok(body)
pub fn ok_entity[T](body T) &ResponseEntity[T] {
	return &ResponseEntity[T]{
		status:  200
		body:    body
		headers: map[string]string{}
	}
}

// created_entity creates a ResponseEntity with 201 status and the given body.
// Spring equivalent: ResponseEntity.created(uri).body(body)
pub fn created_entity[T](body T) &ResponseEntity[T] {
	return &ResponseEntity[T]{
		status:  201
		body:    body
		headers: map[string]string{}
	}
}

// accepted_entity creates a ResponseEntity with 202 status.
// Spring equivalent: ResponseEntity.accepted()
pub fn accepted_entity[T]() &ResponseEntity[T] {
	return &ResponseEntity[T]{
		status:   202
		has_body: false
		headers:  map[string]string{}
	}
}

// no_content_entity creates a ResponseEntity with 204 status (no body).
// Spring equivalent: ResponseEntity.noContent()
pub fn no_content_entity[T]() &ResponseEntity[T] {
	return &ResponseEntity[T]{
		status:   204
		has_body: false
		headers:  map[string]string{}
	}
}

// bad_request_entity creates a ResponseEntity with 400 status.
// Spring equivalent: ResponseEntity.badRequest()
pub fn bad_request_entity[T]() &ResponseEntity[T] {
	return &ResponseEntity[T]{
		status:   400
		has_body: false
		headers:  map[string]string{}
	}
}

// not_found_entity creates a ResponseEntity with 404 status.
// Spring equivalent: ResponseEntity.notFound()
pub fn not_found_entity[T]() &ResponseEntity[T] {
	return &ResponseEntity[T]{
		status:   404
		has_body: false
		headers:  map[string]string{}
	}
}

// server_error_entity creates a ResponseEntity with 500 status.
pub fn server_error_entity[T]() &ResponseEntity[T] {
	return &ResponseEntity[T]{
		status:   500
		has_body: false
		headers:  map[string]string{}
	}
}

// ── Builder Methods ──

// header adds a header to the ResponseEntity. Returns self for chaining.
pub fn (re &ResponseEntity[T]) header(key string, value string) &ResponseEntity[T] {
	unsafe {
		mut r := re
		r.headers[key] = value
	}
	return re
}

// content_type sets the Content-Type header. Returns self for chaining.
pub fn (re &ResponseEntity[T]) content_type(ct string) &ResponseEntity[T] {
	unsafe {
		mut r := re
		r.headers['Content-Type'] = ct
	}
	return re
}

// location sets the Location header. Returns self for chaining.
pub fn (re &ResponseEntity[T]) location(url string) &ResponseEntity[T] {
	unsafe {
		mut r := re
		r.headers['Location'] = url
	}
	return re
}

// etag sets the ETag header. Returns self for chaining.
pub fn (re &ResponseEntity[T]) etag(tag string) &ResponseEntity[T] {
	unsafe {
		mut r := re
		r.headers['ETag'] = tag
	}
	return re
}

// set_status sets the HTTP status code. Returns self for chaining.
pub fn (re &ResponseEntity[T]) set_status(code int) &ResponseEntity[T] {
	unsafe {
		mut r := re
		r.status = code
	}
	return re
}

// ── Conversion ──

// to_result converts the ResponseEntity to a veb.Result.
// The body is JSON-encoded by default. If the Content-Type header
// is set to a non-JSON type, the body is converted to string.
//
// Usage in controller:
//   pub fn (mut app App) get_user(id string) veb.Result {
//       user := app.services.user_service.get_by_id(id)!
//       entity := web.ok(user)
//       return entity.to_result(mut app.Context)
//   }
pub fn (re ResponseEntity[T]) to_result(mut ctx veb.Context) veb.Result {
	mut content_type := 'application/json'
	if ct := re.headers['Content-Type'] {
		content_type = ct
	}

	// Set status code
	ctx.res.set_status(unsafe { http.Status(re.status) })

	// Set headers
	for key, value in re.headers {
		if key != 'Content-Type' {
			ctx.set_custom_header(key, value) or {}
		}
	}
	ctx.set_content_type(content_type)

	if !re.has_body {
		return ctx.text('')
	}

	// Serialize body
	body_str := if content_type == 'application/json' {
		json2.encode(re.body)
	} else {
		'${re.body}'
	}

	return ctx.text(body_str)
}

// to_json_result converts the ResponseEntity to a JSON veb.Result.
// This is a convenience method that always JSON-encodes the body.
pub fn (re ResponseEntity[T]) to_json_result(mut ctx veb.Context) veb.Result {
	// Set status and headers
	ctx.res.set_status(unsafe { http.Status(re.status) })
	for key, value in re.headers {
		ctx.set_custom_header(key, value) or {}
	}
	body_str := json2.encode(re.body)
	ctx.set_content_type('application/json')
	return ctx.text(body_str)
}

// ── Headers Helper ──

// HttpHeaders is a helper for building response headers.
pub struct HttpHeaders {
pub mut:
	headers map[string]string
}

pub fn new_http_headers() HttpHeaders {
	return HttpHeaders{
		headers: map[string]string{}
	}
}

pub fn (mut h HttpHeaders) add(key string, value string) &HttpHeaders {
	h.headers[key] = value
	return unsafe { h }
}

pub fn (mut h HttpHeaders) content_type(ct string) &HttpHeaders {
	h.headers['Content-Type'] = ct
	return unsafe { h }
}

pub fn (mut h HttpHeaders) location(url string) &HttpHeaders {
	h.headers['Location'] = url
	return unsafe { h }
}

pub fn (mut h HttpHeaders) cache_control(value string) &HttpHeaders {
	h.headers['Cache-Control'] = value
	return unsafe { h }
}
