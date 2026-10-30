module core

// resolve_cache_freeze_test.v — 冻结（freeze）之后 resolve 快路径是否真的生效。
//
// 冻结的承诺是「此后每次 resolve 都无锁读快照」。这条承诺只有在缓存里
// 真有条目时才成立，所以断言必须落在命中计数上；只断言「能取到实例」
// 的话，走加锁慢路径也一样通过 —— 那正是原来漏掉的情况。

struct ResolveCacheProbeBean {
pub mut:
	name string
}

// test_frozen_resolve_caches_later_instances 覆盖「冻结之后才被解析」的 bean。
//
// 典型来源：@[lazy] 单例、refresh() 时被跳过的 bean，以及冻结后由外部
// resolver 拉起的实例。它们不在 freeze 的预热快照里。
fn test_frozen_resolve_caches_later_instances() {
	mut ctx := new_application_context()
	ctx.register_instance('ResolveCacheProbeBean', &ResolveCacheProbeBean{
		name: 'probe'
	}) or { panic(err) }
	ctx.freeze_bean_definitions()
	assert ctx.is_frozen == true

	// freeze 会预热已知 singleton 的缓存，这里清掉以模拟「冻结时还没解析」
	ctx.cache_mu.@lock()
	ctx.resolve_cache.delete('ResolveCacheProbeBean')
	ctx.cache_mu.unlock()

	first := ctx.resolve('ResolveCacheProbeBean') or { panic(err) }
	assert !isnil(first)
	hits := ctx.cache_hit_count()
	_ = ctx.resolve('ResolveCacheProbeBean') or { panic(err) }
	assert ctx.cache_hit_count() == hits + 1,
		'冻结后解析出来的 singleton 没有进缓存，每次 resolve 都要抢容器锁'
}

// test_unfreeze_clears_counters 保证 shutdown 之后计数器和缓存一起复位，
// 否则第二次 refresh 的诊断数据会累加上一轮的数字。
fn test_unfreeze_clears_cache_state() {
	mut ctx := new_application_context()
	ctx.register_instance('ResolveCacheProbeBean', &ResolveCacheProbeBean{
		name: 'probe'
	}) or { panic(err) }
	ctx.refresh() or { panic(err) }
	_ = ctx.resolve('ResolveCacheProbeBean') or { panic(err) }
	assert ctx.cache_hit_count() > 0

	ctx.unfreeze_bean_definitions()
	assert ctx.is_frozen == false
	assert ctx.cache_hit_count() == 0
	assert ctx.resolve_cache.len == 0
}
