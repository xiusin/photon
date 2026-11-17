module core

// resolve_cache_alias_test.v — 别名与限定符变更之后，resolve_cache 会留旧值。
//
// 为什么单独一个文件
// ------------------
// `resolve_cache` 的键是**调用方传进来的名字**，而不是容器解析出来的
// canonical 名字：
//
//     ctx.register_instance_with_aliases('log', voidptr(log1), ['Logger'])!
//     // 此时缓存里已有 'log' → log1
//     ctx.resolve('Logger')     // alias → 'log' → log1，然后缓存 'Logger' → log1
//
// 接着 `register_instance_with_aliases` 用同一个名字重新注册（新实例），
// `invalidate_cache()` 只清 `'log'`，`'Logger'` 这条留在缓存里 —— 于是
// `resolve('Logger')` 继续交出**已经被替换掉的旧实例**，而且从此命中的是
// 无锁快路径，容器里那个新实例永远拿不到。
//
// 限定符走的是同一个模式：`resolve_by_qualifier()` 先查 qualifiers 拿到
// canonical 名字，再查 instances，再把结果写进同一个 `resolve_cache`，
// 键还是 canonical 名字。所以这一处修法必须是「缓存键统一用 canonical 名字」，
// 只给 alias 加清理是补不上的。

struct AliasProbeBean {
pub mut:
	serial int
}

// test_alias_resolves_latest_instance_after_reregister 覆盖 alias 的旧缓存。
fn test_alias_resolves_latest_instance_after_reregister() {
	mut ctx := new_application_context()
	first := &AliasProbeBean{
		serial: 1
	}
	ctx.register_instance_with_aliases('log', unsafe { voidptr(first) }, ['Logger'])!

	// 先通过 alias 解析一次：这一步把 'Logger' 写进缓存
	assert ctx.resolve('Logger')! == unsafe { voidptr(first) }

	// 删掉再重新注册（换实例）。register_instance 拒绝同名覆盖，所以走
	// remove_definition → register_instance，这也正是「热替换一个 bean」的路径。
	// remove_definition 会把指向这个 bean 的别名一并摘掉（与 Spring 的
	// removeBeanDefinition 一致），所以这里把别名一起重新注册回来。
	second := &AliasProbeBean{
		serial: 2
	}
	ctx.remove_definition('log')!
	ctx.register_instance_with_aliases('log', unsafe { voidptr(second) }, ['Logger'])!

	got := ctx.resolve('Logger')!
	assert got == unsafe { voidptr(second) },
		'别名解析到了被替换掉的旧实例（缓存键是别名而不是 canonical 名字）'
}

// test_qualifier_resolves_latest_instance_after_destroy 覆盖限定符路径上的旧缓存。
//
// 这里走 remove_definition 而不是 container.destroy()：ApplicationContext
// 没有任何「销毁单个 bean」的公开入口（destroy 只在 refresh 回滚和 shutdown
// 里被调用），所以「让一个 bean 从此不存在」的公开路径只有 remove_definition。
// 它同时也是限定符映射被摘掉的那条路径 —— 正是这条路径上缓存没清干净。
fn test_qualifier_resolves_latest_instance_after_destroy() {
	mut ctx := new_application_context()
	mut def := new_bean_definition('qualified_probe')
	def.qualifier = 'probe_qualifier'
	ctx.register(def)!

	first := &AliasProbeBean{
		serial: 10
	}
	ctx.register_instance('qualified_probe', unsafe { voidptr(first) })!

	assert ctx.resolve_by_qualifier('probe_qualifier')! == unsafe { voidptr(first) }

	// 销毁 → 缓存必须一起清；否则 resolve_by_qualifier 交出已销毁的实例。
	// 先按名字解析一次，让 canonical 名字那条缓存存在。
	assert ctx.resolve('qualified_probe')! == unsafe { voidptr(first) }
	ctx.remove_definition('qualified_probe')!

	ctx.resolve_by_qualifier('probe_qualifier') or {
		// 期望：容器里已经没有实例，报错而不是把旧实例交出去
		return
	}
	assert false, 'resolve_by_qualifier 在 bean 定义被移除后仍返回了缓存里的旧实例'
}
