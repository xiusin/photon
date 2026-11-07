module pool

// guard_test.v - PooledGuard 的行为契约 / behaviour contract for PooledGuard
//
// 为什么单独一个文件
// ------------------
// `PooledGuard[T]` 在 example/verify 里被调用过，但那里只覆盖了「拿到对象、
// 手动 release、池计数归零」这三步。release() 里有两类分支从来没被任何人走进去：
//
//   1. 临时 guard（创建对象时池已耗尽，guard 里没有 pool）
//   2. reset_on_release（归还前清数据）
//
// 第二条尤其要紧：web.RequestPool 的文档推荐写法是
//
//     mut guard := rp.acquire[Session]('session')!
//     defer { guard.release() }
//
// 而 reset 以前只挂在 rp.release(name, obj) 上。也就是说**文档推荐的那条路
// 不清数据**，上一个请求的 session.user_id 会被下一个请求读到。这类缺陷不会
// 让任何断言变红，只会让线上偶发「串号」。
import sync

struct GuardProbe {
mut:
	id int
}

fn probe_factory() !voidptr {
	return voidptr(&GuardProbe{
		id: 7
	})
}

fn new_probe_pool(name string, min_size int, max_size int) &Pool {
	mut p := new_pool_with_config(name, probe_factory, min_size, max_size)
	p.initialize() or { panic(err) }
	return p
}

fn reset_probe_id(obj voidptr) {
	mut o := unsafe { &GuardProbe(obj) }
	o.id = 0
}

// ── 正常 guard ──

fn test_guard_wraps_typed_object() {
	mut p := new_probe_pool('guard-typed', 1, 2)
	mut g := p.acquire_guard[GuardProbe]() or { panic(err) }
	assert !g.is_released()
	obj := g.get()
	assert !isnil(obj)
	assert obj.id == 7
	assert p.stats().active == 1
	g.release()
	assert g.is_released()
	assert p.stats().active == 0
}

fn test_guard_get_after_release_is_nil() {
	mut p := new_probe_pool('guard-get-nil', 1, 2)
	mut g := p.acquire_guard[GuardProbe]() or { panic(err) }
	mut obj := g.get()
	obj.id = 99
	g.release()
	assert isnil(g.get())

	// released 与 obj 是两件事：把 obj 填回去（release() 会清空它），
	// get() 仍然必须返回 nil。只靠 `isnil(g.obj)` 判断的实现在这里会漏 ——
	// 它会把一个已经归还给池、可能正被别的请求改写的对象交出去。
	g.obj = voidptr(obj)
	assert g.released == true
	assert isnil(g.get())
}

fn test_guard_release_is_idempotent() {
	mut p := new_probe_pool('guard-idempotent', 1, 2)
	mut g := p.acquire_guard[GuardProbe]() or { panic(err) }
	g.release()
	g.release()
	g.release()
	assert g.is_released()
	assert p.stats().active == 0
	// 重复 release 不能把对象重复归还，池里总数必须仍是 1
	assert p.stats().total == 1
}

fn test_guard_drop_equals_release() {
	mut p := new_probe_pool('guard-drop', 1, 2)
	mut g := p.acquire_guard[GuardProbe]() or { panic(err) }
	g.drop()
	assert g.is_released()
	assert p.stats().active == 0
}

// 这条把「RAII 不是析构」钉成事实：不 release 就不会归还。
// 哪天有人试图在 release() 之外加自动回收，这条会红并提醒同步改文档。
fn test_guard_without_release_keeps_object_checked_out() {
	mut p := new_probe_pool('guard-no-release', 1, 1)
	acquire_and_forget(mut p)
	assert p.stats().active == 1
}

fn acquire_and_forget(mut p Pool) {
	mut g := p.acquire_guard[GuardProbe]() or { panic(err) }
	assert !g.is_released()
	// 故意不 release：V 没有 drop 钩子，guard 离开作用域不会归还对象
}

// ── reset_on_release ──

fn test_guard_reset_runs_before_return_to_pool() {
	mut p := new_probe_pool('guard-reset', 1, 1)
	mut g := p.acquire_guard[GuardProbe]() or { panic(err) }
	mut obj := g.get()
	obj.id = 42
	g.reset_on_release = reset_probe_id
	g.release()
	// 对象已归还，且归还前被 reset 过
	mut g2 := p.acquire_guard[GuardProbe]() or { panic(err) }
	assert g2.get().id == 0
	g2.release()
}

fn test_guard_reset_not_required() {
	mut p := new_probe_pool('guard-no-reset', 1, 1)
	mut g := p.acquire_guard[GuardProbe]() or { panic(err) }
	mut obj := g.get()
	obj.id = 5
	// reset_on_release 保持 nil：不应崩，也不该被擅自调用
	g.release()
	mut g2 := p.acquire_guard[GuardProbe]() or { panic(err) }
	assert g2.get().id == 5
	g2.release()
}

// ── 临时 guard（池耗尽时的回退对象）──

fn test_temporary_guard_release_flips_released() {
	// 对象必须真的在堆上：release() 对回退对象会 free 它，
	// 传栈上结构的地址会在下一次读它时段错误，把断言失败伪装成崩溃。
	obj := &GuardProbe{
		id: 3
	}
	mut g := new_temporary_guard[GuardProbe](voidptr(obj))
	assert !g.is_released()
	assert g.get().id == 3
	g.release()
	// 以前这里恒为 false：release() 见到 nil pool 就直接 return，
	// 连 released 都不置位，调用方永远不知道对象还活着没有。
	assert g.is_released()
	assert isnil(g.get())
}

fn test_temporary_guard_release_is_idempotent() {
	obj := &GuardProbe{
		id: 1
	}
	mut g := new_temporary_guard[GuardProbe](voidptr(obj))
	g.release()
	g.release()
	assert g.is_released()
}

fn test_temporary_guard_runs_reset() {
	heap_obj := &GuardProbe{
		id: 8
	}
	mut g := new_temporary_guard[GuardProbe](voidptr(heap_obj))
	obj := g.get()
	assert obj.id == 8
	g.reset_on_release = reset_probe_id
	g.release()
	assert g.is_released()
}

// ── 并发 ──

fn test_guard_concurrent_release_releases_once() {
	mut p := new_probe_pool('guard-concurrent', 1, 2)
	// 守卫必须是 heap 指针再跨协程共享，不能写 `mut g := ...` 后 `fn [mut g]`。
	// 后者传出去的是结构体副本（见 strutil/module_identity_test.v 里那条最小复现），
	// 每个协程改的都是自己那份 `released`，外部那份永远是 false。
	mut gv := p.acquire_guard[GuardProbe]() or { panic(err) }
	mut g := &gv
	mut wg := sync.new_waitgroup()
	for _ in 0 .. 8 {
		wg.add(1)
		spawn fn [mut wg, mut g] () {
			g.release()
			wg.done()
		}()
	}
	wg.wait()
	assert g.is_released()
	assert p.stats().active == 0
	// 只有一条路径真正归还，池总数不变
	assert p.stats().total == 1
}

fn test_pool_close_with_guard_outstanding() {
	mut p := new_probe_pool('guard-close', 1, 2)
	mut g := p.acquire_guard[GuardProbe]() or { panic(err) }
	p.close() or { panic(err) }
	// close 后仍持有对象：guard 看到的是已关闭的池
	assert p.stats().active == 1
	g.release()
	assert g.is_released()
	// 池已关闭，对象被直接销毁，active 归零
	assert p.stats().active == 0
}
