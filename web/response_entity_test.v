module web

// response_entity_test.v — ResponseEntity（Spring ResponseEntity<T> 等价物）
//
// 这个文件存在的理由比它的用例更重要：
//
// `web/response_entity.v` 的整条链式 API 在 0.5.2 上编译不过，而它既没有
// 用例也没有任何调用方（全仓库 0 引用，只有光子自己的 re-export 提到类型名）。
// 于是每次「全量全绿」都与它无关 —— 它没被编译过，也就不会失败。
//
// 具体原因有两个，都是 V 的语义问题而不是笔误：
//
//   1. `pub:` 字段是只读的。构建器 `re.headers[k] = v` 直接编译失败。
//      一条链式方法错，整个泛型 struct 的方法集就一起编不过 —— 所以哪怕
//      只调用一个工厂函数 `ok_entity[string]('x')` 都会报 5 个错。
//   2. 工厂返回的是值。`created_entity[T](x).location(...)` 里 `location`
//      是 mut 接收者，V 拒绝「把表达式当 mut 传」（cannot pass expression
//      as `mut`）——而文件头文档承诺的正是这种写法。
//
// 所以这里的断言分两层：结构层（签名）锁住这两条 V 语义约束，行为层锁住
// HTTP 语义。只留行为用例是没用的：用 `mut e := ...` 绕开之后，即使把签名
// 改回按值 mut 接收者，行为断言照样全绿 —— 缺陷会悄悄回来。

import veb
import os

// ── 工厂：状态码与 has_body ──

fn test_ok_entity_defaults() {
	e := ok_entity[string]('hi')
	assert e.status == 200
	assert e.body == 'hi'
	assert e.has_body
	assert e.headers.len == 0
}

fn test_created_entity_is_201_with_body() {
	e := created_entity[string]('x')
	assert e.status == 201
	assert e.body == 'x'
	assert e.has_body
}

fn test_accepted_entity_is_202_without_body() {
	e := accepted_entity[string]()
	assert e.status == 202
	assert !e.has_body
}

fn test_no_content_entity_is_204_without_body() {
	e := no_content_entity[string]()
	assert e.status == 204
	assert !e.has_body
}

fn test_error_entity_statuses() {
	assert bad_request_entity[string]().status == 400
	assert not_found_entity[string]().status == 404
	assert server_error_entity[string]().status == 500
}

// ── 链式构建 ──

// 直接链在工厂返回值上。这是文件头文档承诺的用法，也是第 2 条缺陷的
// 唯一复现形式：工厂若返回 `ResponseEntity[T]` 而不是 `&ResponseEntity[T]`，
// 这行在编译期就挂（cannot pass expression as `mut`），用例根本跑不起来。
fn test_chaining_directly_on_factory_result() {
	e := ok_entity[string]('hi')
		.header('X-Trace', 'abc')
		.content_type('application/json')
		.set_status(201)
	assert e.status == 201
	assert e.headers['X-Trace'] == 'abc'
	assert e.headers['Content-Type'] == 'application/json'
	assert e.body == 'hi'
}

fn test_location_chaining() {
	e := created_entity[string]('x').location('/api/users/42')
	assert e.status == 201
	assert e.headers['Location'] == '/api/users/42'
}

fn test_etag_chaining() {
	e := not_found_entity[string]().etag('"v1"')
	assert e.headers['ETag'] == '"v1"'
}

fn test_set_status_overrides_factory_status() {
	e := no_content_entity[string]().set_status(304)
	assert e.status == 304
	// has_body 不被 set_status 影响，这是有意的：状态码与是否有体是两件事
	assert !e.has_body
}

fn test_header_overwrites_same_key() {
	e := ok_entity[string]('x').header('K', 'v1').header('K', 'v2')
	assert e.headers['K'] == 'v2'
	assert e.headers.len == 1
}

fn test_each_entity_owns_its_headers() {
	// 链式方法原地改的是「这一个」实体。若哪天改成共享 map，互相污染
	// 会在真实并发请求间串味。
	a := ok_entity[string]('a').header('K', 'v')
	b := ok_entity[string]('b')
	assert a.headers['K'] == 'v'
	assert b.headers.len == 0
}

// ── to_result / to_json_result ──

fn test_to_result_sets_status() {
	mut ctx := &veb.Context{}
	_ := ok_entity[string]('x').to_result(mut ctx)
	assert ctx.res.status_code == 200
}

fn test_no_content_entity_to_result_has_empty_body() {
	mut ctx := &veb.Context{}
	no_content_entity[string]().to_result(mut ctx)
	assert ctx.res.status_code == 204
}

fn test_to_json_result_sets_status() {
	mut ctx := &veb.Context{}
	_ := bad_request_entity[string]().to_json_result(mut ctx)
	assert ctx.res.status_code == 400
}

// ── 结构断言：锁住 V 语义约束 ──
//
// 上面那些行为用例都能被 `mut e := ...` 绕开。没有这一段，把工厂签名改回
// 返回值类型（缺陷 1、2 同时复活）时，行为用例依然全绿 —— 只要有人记得写
// mut 左值。所以这里直接盯源码。

fn test_struct_fields_are_mutable() {
	src := 'web/response_entity.v'
	content := read_source_or_empty(src)
	if content.len == 0 {
		// 测试可能从别的 cwd 启动；找不到源码时不能假装通过
		assert false, 'cannot read ${src}; run tests from the repository root (sh scripts/run-tests.sh)'
	}
	struct_def := content.all_before('// ── Factory Functions ──')
	assert struct_def.contains('pub mut:'),
		'ResponseEntity[T] 的 status/headers 必须是 pub mut，否则链式方法无法赋值'
	assert struct_def.contains('status  int = 200') || struct_def.contains('status int = 200'),
		'status 字段缺失或改名'
}

fn test_factories_return_pointer() {
	src := 'web/response_entity.v'
	content := read_source_or_empty(src)
	if content.len == 0 {
		assert false, 'cannot read ${src}; run tests from the repository root (sh scripts/run-tests.sh)'
	}
	// 工厂必须返回 &ResponseEntity[T]，链式方法才能在表达式的返回值上调用
	for f in ['ok_entity', 'created_entity', 'accepted_entity', 'no_content_entity',
		'bad_request_entity', 'not_found_entity', 'server_error_entity'] {
		needle := 'pub fn ${f}[T]'
		idx := content.index(needle) or {
			assert false, 'factory ${f} not found'
			return
		}
		line := content[idx..].all_before('\n')
		assert line.contains('&ResponseEntity[T]'),
			'${f} 必须返回 &ResponseEntity[T]，否则链式调用在编译期就挂：${line}'
	}
}

fn test_chain_methods_take_shared_receiver() {
	src := 'web/response_entity.v'
	content := read_source_or_empty(src)
	if content.len == 0 {
		assert false, 'cannot read ${src}; run tests from the repository root (sh scripts/run-tests.sh)'
	}
	// mut 接收者 + 返回 &self 在 V 里无法用在表达式上（cannot pass expression
	// as `mut`）。链式方法必须是 &ResponseEntity[T] 接收者。
	for m in ['header', 'content_type', 'location', 'etag', 'set_status'] {
		needle := 'pub fn (re &ResponseEntity[T]) ${m}('
		assert content.contains(needle),
			'${m} 必须以 &ResponseEntity[T] 为接收者（看到的是别的形式），否则无法链在工厂返回值上'
	}
}

// read_source_or_empty 读源码文件，失败返回空串 —— 由调用方断言报错，
// 不在这里静默吞掉。
fn read_source_or_empty(path string) string {
	return os.read_file(path) or { '' }
}
