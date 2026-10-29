module pool

import sync

// 池关闭后 release 一个「不属于本池 / 已经还过」的指针，过去会再调一次
// factory.destroy()。一个对象销毁两次不是「多释放一次」，是把指针下面的
// 内存还给分配器之后，别处还留着它 —— 典型 use-after-free 的制造方式。

struct Counted {}

@[heap]
struct DestroyCounter {
pub mut:
	mu  sync.Mutex
	n   int
	ids []int
}

fn (c &DestroyCounter) create() !voidptr {
	unsafe {
		c.mu.@lock()
		c.n++
		c.mu.unlock()
	}
	return voidptr(&Counted{})
}

fn (c &DestroyCounter) is_valid(obj voidptr) bool {
	return true
}

fn (c &DestroyCounter) destroy(obj voidptr) {
	unsafe {
		c.mu.@lock()
		c.n--
		c.mu.unlock()
	}
}

fn (c &DestroyCounter) live() int {
	unsafe {
		c.mu.@lock()
		defer {
			c.mu.unlock()
		}
		return c.n
	}
}

fn test_double_release_after_close_destroys_once() {
	mut c := &DestroyCounter{}
	mut p := new_pool_with_factory('dd', c, 0, 4)
	a := p.acquire()!
	p.close()!

	p.release(a)
	assert c.live() == 0
	// 同一个指针再还一次：池已经不认识它了，不能再销毁一次
	p.release(a)
	assert c.live() == 0, 'object destroyed twice (live=${c.live()})'
}

fn test_release_of_foreign_pointer_is_ignored() {
	mut c := &DestroyCounter{}
	mut p := new_pool_with_factory('dd2', c, 0, 4)
	p.close()!
	// 从来没 acquire 过的指针
	foreign := &Counted{}
	p.release(voidptr(foreign))
	assert c.live() == 0, 'a pointer the pool never handed out must not be destroyed'
}

fn test_concurrent_close_and_release_no_leak_no_double_free() {
	mut c := &DestroyCounter{}
	mut p := new_pool_with_factory('dd3', c, 0, 8)
	mut objs := []voidptr{}
	for _ in 0 .. 8 {
		objs << p.acquire()!
	}
	done := chan bool{cap: 8}
	for o in objs {
		spawn fn (mut pool_ref Pool, obj voidptr, ch chan bool) {
			pool_ref.release(obj)
			ch <- true
		}(mut p, o, done)
	}
	p.close()!
	for _ in 0 .. 8 {
		_ := <-done
	}
	assert c.live() == 0, 'live=${c.live()} (negative = double destroy, positive = leak)'
}
