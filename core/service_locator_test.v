module core

// service_locator_test.v — 整套 ServiceLocator API 第一次被真正调用
//
// context_test.v 有 200+ 条用例，文件头也写着「ServiceLocator」，但这一套
// API 一条都没碰过：三个模块级便利函数、new_service_locator、ServiceLocator
// 的四个实例方法、全局定位器，全是零引用。
//
// 第一轮拿真实编译器扫「零引用的 pub 函数」时，把它们逐个调了一遍，撞到
// 段错误：service_from 原来收 `mut ctx ApplicationContext`（按值），调用方
// 很自然就写 `ApplicationContext{}` 传进去；而 ApplicationContext 的
// container / event_bus / environment 都是 `&X = unsafe { nil }`，
// `ctx.has()` 一进去就解引用 nil。改成 `&ApplicationContext` 之后，零值
// 构造在编译期就传不进来了（见 test_convenience_functions_reject_value）。
//
// 这里的用例分两部分：行为（真的解析到服务）和结构（签名不许退回按值）。
import os

fn new_populated_context() &ApplicationContext {
	mut ctx := new_application_context()
	ctx.register_instance('greeter', unsafe { voidptr(1) }) or { panic(err) }
	ctx.register_instance('qualified_one', unsafe { voidptr(2) }) or { panic(err) }
	return ctx
}

fn test_has_service_from() {
	mut ctx := new_populated_context()
	assert has_service_from(mut ctx, 'greeter') == true
	assert has_service_from(mut ctx, 'missing') == false
}

fn test_service_from_resolves_registered_instance() {
	mut ctx := new_populated_context()
	instance := service_from(mut ctx, 'greeter') or {
		assert false, 'service_from 应能解析已注册实例：${err}'
		return
	}
	assert !isnil(instance)
	assert instance == unsafe { voidptr(1) }
}

fn test_service_from_reports_missing() {
	mut ctx := new_populated_context()
	_ = service_from(mut ctx, 'missing') or {
		assert err.str().len > 0
		return
	}
	assert false, '未注册的类型应返回 error'
}

fn test_qualified_service_from_reports_missing() {
	mut ctx := new_populated_context()
	_ = qualified_service_from(mut ctx, 'no-such-qualifier') or {
		assert err.str().len > 0
		return
	}
	assert false, '不存在的 qualifier 应返回 error'
}

fn test_new_service_locator_has_and_resolve() {
	mut ctx := new_populated_context()
	mut sl := new_service_locator(ctx)
	assert sl.has('greeter') == true
	assert sl.has('missing') == false
	instance := sl.resolve('greeter') or {
		assert false, 'ServiceLocator.resolve 失败：${err}'
		return
	}
	assert !isnil(instance)
	_ = sl.resolve('missing') or {
		assert err.str().len > 0
		return
	}
}

fn test_new_service_locator_resolve_by_qualifier() {
	mut ctx := new_populated_context()
	mut sl := new_service_locator(ctx)
	_ = sl.resolve_by_qualifier('no-such-qualifier') or {
		assert err.str().len > 0
		return
	}
	assert false, '不存在的 qualifier 应返回 error'
}

fn test_service_locator_without_context_is_safe() {
	// 空 context 不能崩，必须走 error / false，而不是解引用 nil。
	mut sl := new_service_locator(unsafe { nil })
	assert sl.has('anything') == false
	_ = sl.resolve('anything') or {
		assert err.str().contains('no application context')
		return
	}
	assert false, '没有 context 时应返回 error'
	_ = sl.resolve_by_qualifier('anything') or {
		assert err.str().contains('no application context')
		return
	}
	assert false, '没有 context 时应返回 error'
}

fn test_global_service_locator_roundtrip() {
	mut ctx := new_populated_context()
	mut sl := new_service_locator(ctx)
	set_global_service_locator(sl)
	assert has_global_service('greeter') == true
	assert has_global_service('missing') == false
}

// test_convenience_functions_take_reference 把「不许退回按值」钉成结构断言。
//
// 没有它，把签名改回 `mut ctx ApplicationContext` 后所有行为用例照样绿
// （用 new_application_context() 调，按值也能跑），而零值构造的段错误会
// 悄悄回来 —— 正是「用例恒过、缺陷沉默」那种形状。
fn test_convenience_functions_take_reference() {
	path := os.join_path(@DIR, 'service_locator.v')
	text := os.read_file(path) or { panic(err) }
	for name in ['service_from', 'has_service_from', 'qualified_service_from'] {
		mut found := false
		for line in text.split_into_lines() {
			t := line.trim_space()
			if t.starts_with('pub fn ${name}(') {
				found = true
				assert t.contains('&ApplicationContext'), '`${name}` 必须收 `&ApplicationContext`（按值会让零值构造段错误）：${t}'
			}
		}
		assert found, 'service_locator.v 里找不到 `pub fn ${name}`'
	}
}
