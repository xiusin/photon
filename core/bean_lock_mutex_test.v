module core

import time

// BeanLock must stay a real mutual exclusion even when set_instance() fires.
//
// set_instance() calls bean_lock.remove(type_name) as soon as a singleton is
// stored — i.e. at the exact moment other goroutines may still be waiting for
// that bean. Deleting the mutex there did two things:
//
//   1. waiters parked in lock() were left on a mutex nobody would ever unlock;
//   2. the next lock() found no entry, created a fresh mutex and succeeded
//      immediately — two goroutines "held" the same bean lock at once.
fn test_remove_does_not_break_mutual_exclusion() {
	mut bl := new_bean_lock()
	// One goroutine takes the lock and keeps it while remove() runs.
	holder_ready := chan bool{cap: 1}
	release_holder := chan bool{cap: 1}
	spawn fn (mut b BeanLock, ready chan bool, release chan bool) {
		b.lock('svc')
		ready <- true
		_ := <-release
		b.unlock('svc')
	}(mut bl, holder_ready, release_holder)
	_ := <-holder_ready

	// set_instance() removes the entry at exactly this moment.
	bl.remove('svc')

	// A second goroutine wants the same bean. It must wait.
	got := chan bool{cap: 1}
	spawn fn (mut b BeanLock, ch chan bool) {
		b.lock('svc')
		ch <- true
		b.unlock('svc')
	}(mut bl, got)

	mut acquired_while_held := false
	select {
		_ := <-got {
			acquired_while_held = true
		}
		300 * time.millisecond {}
	}
	release_holder <- true
	assert !acquired_while_held, 'second holder acquired a bean lock that the first still owns'
}

fn test_remove_still_reclaims_idle_lock() {
	mut bl := new_bean_lock()
	bl.lock('idle')
	bl.unlock('idle')
	assert bl.lock_count() == 1
	bl.remove('idle')
	assert bl.lock_count() == 0
}

fn test_remove_keeps_entry_while_waiter_pending() {
	mut bl := new_bean_lock()
	started := chan bool{cap: 1}
	done := chan bool{cap: 1}
	spawn fn (mut b BeanLock, ch chan bool) {
		b.lock('slow')
		ch <- true
		time.sleep(200 * time.millisecond)
		b.unlock('slow')
	}(mut bl, started)
	_ := <-started

	// A waiter queued behind the holder.
	spawn fn (mut b BeanLock, ch chan bool) {
		b.lock('slow')
		b.unlock('slow')
		ch <- true
	}(mut bl, done)
	time.sleep(20 * time.millisecond)

	bl.remove('slow')
	// Entry must survive: a waiter is parked on that mutex.
	assert bl.lock_count() == 1

	select {
		_ := <-done {}
		2 * time.second { assert false, 'waiter never got the lock after remove()' }
	}
}
