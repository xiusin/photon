module main

// main.v — Photon 框架功能验证套件入口
//
// 这是一个独立的自验证程序（module main，独立于 example/ 的 Web 应用），
// 用断言逐项验证 photon 各模块的真实用法、依赖注入、生命周期与可用注解。
//
// 运行：v -enable-globals run example/verify
//
// 输出每项 ✓/✗，并在结尾汇总通过/失败数；任意失败时退出码为 1。

import os

// Verifier 简单的断言报告器
pub struct Verifier {
pub mut:
	passed  int
	failed  int
	section string
}

pub fn (mut v Verifier) section(title string) {
	v.section = title
	println('\n\033[1;36m=== ${title} ===\033[0m')
}

pub fn (mut v Verifier) check(name string, cond bool) {
	if cond {
		v.passed++
		println('  \033[32m✓\033[0m ${name}')
	} else {
		v.failed++
		println('  \033[31m✗ FAIL\033[0m ${name}')
	}
}

// eq 比较两个可比较值并报告
pub fn (mut v Verifier) eq[T](name string, got T, want T) {
	v.check('${name} (got=${got}, want=${want})', got == want)
}

fn main() {
	mut v := &Verifier{}

	println('\033[1m╔══════════════════════════════════════════════╗\033[0m')
	println('\033[1m║   Photon Framework — 功能验证套件             ║\033[0m')
	println('\033[1m╚══════════════════════════════════════════════╝\033[0m')

	verify_di(mut v)
	verify_lifecycle(mut v)
	verify_cycle_detection(mut v)
	verify_config(mut v)
	verify_logger(mut v)
	verify_cache(mut v)
	verify_pool(mut v)
	verify_locking(mut v)
	verify_orm(mut v)
	verify_security(mut v)
	verify_scheduling(mut v)
	verify_queue(mut v)
	verify_web(mut v)
	verify_annotations(mut v)
	verify_value_injection(mut v)
	verify_bean_methods(mut v)
	verify_pool_guard(mut v)
	verify_service_locator(mut v)
	verify_auto_logger(mut v)
	verify_lock_guard(mut v)
	verify_controller_mount(mut v)
	verify_controller_di_injection(mut v)
	verify_controller_register_container(mut v)
	verify_webmodule_integration(mut v)
	verify_multi_controller_dispatch(mut v)
	verify_locate_controller_global(mut v)
	verify_dispatch_controller_method(mut v)

	println('\n\033[1m──────────────────────────────────────────────\033[0m')
	total := v.passed + v.failed
	if v.failed == 0 {
		println('\033[1;32m全部通过：${v.passed}/${total}\033[0m')
		exit(0)
	} else {
		println('\033[1;31m失败：${v.failed}，通过：${v.passed}，共 ${total}\033[0m')
		exit(1)
	}
}
