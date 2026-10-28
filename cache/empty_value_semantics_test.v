module cache

// empty_value_semantics_test.v - 空字符串是合法缓存值
//
// 三个「命中判据用值长度」的地方会静默失效：
//   - CacheOperation.save() 把 value == '' 当成「没设置」，直接报错
//   - CacheableInterceptor.get_or_compute() 用 cached.len > 0 判命中
//   - get_or_load() 先 has() 再 get()，两步之间条目可能刚过期
//
// 值本身是空串不代表没缓存。返回空串的方法（"查无此关键词" 之类）
// 每次都穿透到 loader，压测时就是每个请求打一次数据库。
__global (
	empty_semantics_loader_calls int
)

fn test_cache_operation_save_accepts_empty_value() {
	mut reg := new_cache_registry()
	reg.chain().put('empty:1', '').ttl(60).save() or {
		assert false, 'save() must accept an empty value: ${err}'
		return
	}
	assert reg.has('empty:1')
	assert reg.get('empty:1')! == ''
}

fn test_cache_operation_save_still_rejects_missing_key() {
	mut reg := new_cache_registry()
	mut op := new_cache_operation(reg)
	op.value = 'x'
	if _ := op.save() {
		assert false, 'save() without a key must fail'
	}
}

fn test_get_or_load_caches_empty_result() {
	mut reg := new_cache_registry()
	empty_semantics_loader_calls = 0

	v1 := reg.get_or_load('k:empty', 60, fn () !string {
		empty_semantics_loader_calls++
		return ''
	})!
	assert v1 == ''

	// 第二次必须命中缓存，loader 不再执行
	v2 := reg.get_or_load('k:empty', 60, fn () !string {
		empty_semantics_loader_calls++
		return 'should-not-run'
	})!
	assert v2 == ''
	assert empty_semantics_loader_calls == 1
}

fn test_tagged_cache_remember_hits_cached_empty_value() {
	mut reg := new_cache_registry()
	empty_semantics_loader_calls = 0

	// get_with_tags 路径（带 tags 的 remember）
	v1 := reg.chain().with_tags(['t']).remember('k', 60, fn () !string {
		empty_semantics_loader_calls++
		return ''
	}).get()!
	assert v1 == ''
	v2 := reg.chain().with_tags(['t']).remember('k', 60, fn () !string {
		empty_semantics_loader_calls++
		return 'other'
	}).get()!
	assert v2 == ''
	assert empty_semantics_loader_calls == 1
}

fn test_cacheable_interceptor_caches_empty_result() {
	mut cm := new_cache_registry()
	mut ci := new_cacheable_interceptor(cm)
	empty_semantics_loader_calls = 0

	attr := CacheableAttribute{
		cache_name:  'default'
		ttl_seconds: 60
	}
	r1 := ci.get_or_compute(attr, 'find_nothing', [], fn () !string {
		empty_semantics_loader_calls++
		return ''
	})!
	assert r1 == ''
	r2 := ci.get_or_compute(attr, 'find_nothing', [], fn () !string {
		empty_semantics_loader_calls++
		return 'second'
	})!
	assert r2 == ''
	assert empty_semantics_loader_calls == 1
}

// CacheLock：写入后回读确认，避免「两个进程同时看到没锁」的竞态。
fn test_cache_lock_acquire_and_release() {
	cm := new_cache_registry()
	mut l1 := new_cache_lock(cm.default_cache, 'job:42', 30)
	assert l1.acquire()!
	assert l1.is_acquired()

	// 第二个持有者抢不到
	mut l2 := new_cache_lock(cm.default_cache, 'job:42', 30)
	assert !l2.acquire()!

	l1.release()!
	assert !l1.is_acquired()

	// 释放后可以再拿
	assert l2.acquire()!
	l2.release()!
}

fn test_cache_lock_owner_identity_guard() {
	mut cm := new_cache_registry()
	mut l1 := new_cache_lock(cm.default_cache, 'res', 30)
	assert l1.acquire()!

	// 别人的 owner 不能覆盖已持有的锁
	mut intruder := new_cache_lock(cm.default_cache, 'res', 30)
	assert !intruder.acquire()!
	// 原持有者的值不变
	assert cm.get('res')! == l1.get_owner()
	l1.release()!
}
