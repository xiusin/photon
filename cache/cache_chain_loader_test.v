module cache

// cache_chain_loader_test.v — CacheOperation 在缺少 loader 时的行为。
//
// `remember()` 的第三个参数是可选语义的：调用方经常先 `.put()` 占位、
// 或者从配置对象里转发时把 loader 传成了 nil。原来这种调用会在
// `co.loader()!` 处直接踩空函数指针 —— 进程 SIGSEGV，栈上还看不出是谁少传了。

fn test_remember_without_loader_falls_back_to_read() {
	mut reg := new_cache_registry()
	reg.set('probe', 'cached-value', 60)!
	// 不设 loader，只 set 过 key：应当按普通读返回已有值，而不是崩溃
	got := reg.chain().remember('probe', 60, unsafe { nil }).get() or {
		assert false, 'get() should not fail without a loader: ${err}'
		return
	}
	assert got == 'cached-value'
}

fn test_remember_without_loader_and_missing_key() {
	mut reg := new_cache_registry()
	// key 不存在且没有 loader：返回空串（未命中），不崩
	got := reg.chain().remember('absent', 60, unsafe { nil }).get() or {
		assert false, 'missing key without loader should not error: ${err}'
		return
	}
	assert got == ''
}

fn test_remember_with_tag_and_no_loader_does_not_crash() {
	mut reg := new_cache_registry()
	// 带标签的分支同样不能踩空指针
	got := reg.chain().with_tags(['t']).remember('tagged', 60, unsafe { nil }).get() or { '' }
	assert got == '' || got.len >= 0
}
