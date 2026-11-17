module pool

import sync
import time

// pool_wakeup_test.v — acquire() 里「新建对象」这条分支结束得太早。
//
// `acquire()` 有两条返回路径：从 free_stack 取到空闲对象，和创建新对象。
// 后者在 `p.objects << PoolEntry{...}` 之后直接 `return obj`，落下了两件事：
//
//   1. 没把新对象登记进 `obj_index`（反向索引 → ledger 槽位）。于是这个
//      对象的第一次 `release()` 在 `entry_unsafe()` 里查不到，被当成
//      「未知指针」静默忽略：对象既没回到 free_stack，`active` 也没减。
//      它变成一个只有 close() 才回收的僵尸槽位，直到下一次 GC sweep 重建
//      索引才「复活」——两次 sweep 之间，池对它的容量是白算的。
//
//   2. 没调 `wake_waiters_unsafe()`。而 pool 的上限约束的是 **active**
//      （in-use + 预留槽位），不是对象总数：只要有别的协程还持有对象，
//      池里「没有空闲对象且 active < max」会一直成立，每进来一个 waiter
//      就新建一个对象，然后睡在 `avail` 上等一个永远不会来的唤醒。
//      堆一个都不够用。

struct WakeProbe {
mut:
	id int
}

fn wake_probe_factory() !voidptr {
	return voidptr(&WakeProbe{})
}

// test_new_object_release_returns_to_idle 钉住第 1 件事。
fn test_new_object_release_returns_to_idle() {
	mut p := new_pool_with_config('wake-new-release', wake_probe_factory, 0, 4)
	obj := p.acquire()!
	p.release(obj)
	assert p.stats().active == 0, 'release() 之后 active 必须归零'
	assert p.stats().idle == 1, '新建的对象 release() 之后没回到 idle（反向索引没登记）'
	// 再取一次必须拿到同一个对象，而不是又新建一个
	again := p.acquire()!
	assert again == obj, '池没有复用刚归还的对象'
	p.release(again)
	p.close()!
}

// test_new_object_wakes_parked_waiter 钉住第 2 件事。
//
// 一个协程持着对象不放，另一个协程来 acquire 并睡在 avail 上；接着调用方
// 自己再 acquire 一次（池里没有空闲对象 → 新建一个并直接返回）。这一步
// 必须唤醒那个睡着的 waiter，否则它只能等到有人 release 才动 —— 而此刻
// 谁都没有对象可还，它就这么睡到超时。
fn test_new_object_wakes_parked_waiter() {
	mut p := new_pool_with_config('wake-waiters', wake_probe_factory, 0, 4)
	held := p.acquire()!

	woke := chan bool{cap: 1}
	got := chan voidptr{cap: 1}
	spawn fn (mut pp Pool, ch chan bool, och chan voidptr) {
		obj := pp.acquire_with_timeout(3) or {
			ch <- false
			return
		}
		ch <- true
		och <- obj
	}(mut p, woke, got)

	// 让 waiter 先睡在 avail 上
	time.sleep(150 * time.millisecond)

	fresh := p.acquire()!
	// 此时手上两个对象（held + fresh），池已满，谁都不可能有对象归还。
	// waiter 唯一的活路就是「新建对象之后的那次广播」。
	ok := <-woke
	if ok {
		p.release(<-got)
	}
	p.release(fresh)
	p.release(held)
	p.close()!
	assert ok, '新建对象之后没有唤醒 avail 上的 waiter（它睡到了超时）'
}

// test_release_wakes_only_up_to_free_slots 的反面：这里只要求「唤醒后能拿到
// 对象」，不要求唤醒次数 —— 唤醒是广播，多余醒来的人重试一次即可。
fn test_waiter_wakes_and_gets_object() {
	mut p := new_pool_with_config('wake-retry', wake_probe_factory, 0, 1)
	held := p.acquire()!

	got := chan voidptr{cap: 1}
	mut wg := sync.new_waitgroup()
	wg.add(1)
	spawn fn (mut pp Pool, ch chan voidptr, mut g sync.WaitGroup) {
		defer {
			g.done()
		}
		obj := pp.acquire_with_timeout(3) or {
			ch <- unsafe { nil }
			return
		}
		ch <- obj
	}(mut p, got, mut wg)

	time.sleep(150 * time.millisecond)
	p.release(held)

	obj := <-got
	wg.wait()
	p.close()!
	assert !isnil(obj), 'release() 之后 waiter 没有被唤醒'
}
