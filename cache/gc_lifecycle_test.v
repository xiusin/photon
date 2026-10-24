module cache

// gc_lifecycle_test.v - MemoryCache background-GC lifecycle regressions
//
// Two bugs are pinned here:
//
//  1. Thread leak. Every new_memory_cache() spawns a sweeper goroutine.
//     Callers that just let the pointer go out of scope (tests, request
//     scoped caches) used to leave that thread sleeping forever, so a few
//     hundred caches wedged the process. The sweeper must retire once the
//     cache stays empty.
//
//  2. Concurrent first use. V's sync primitives initialise lazily, and the
//     losing side of that CAS can lock a half-initialised pthread lock.
//     A freshly built cache is immediately hammered by several goroutines
//     (the sweeper plus the caller), so the constructors now initialise
//     every lock eagerly.
import os
import time

// current_thread_count returns the number of threads in this process.
// Returns -1 on platforms without /proc.
fn current_thread_count() int {
	entries := os.ls('/proc/self/task') or { return -1 }
	return entries.len
}

fn test_dropped_cache_does_not_leak_threads() {
	baseline := current_thread_count()
	if baseline < 0 {
		return
	}

	// Deliberately drop every cache without calling close().
	for i in 0 .. 200 {
		c := new_memory_cache('leak-${i}')
		_ = c
	}

	// The sweeper retires after two empty sweeps of 1s each.
	time.sleep(4 * time.second)

	after := current_thread_count()
	assert after - baseline < 20, 'sweeper goroutines leaked: before=${baseline} after=${after}'
}

fn test_concurrent_first_use_of_fresh_cache() {
	// Each round builds a brand-new cache and immediately lets four
	// goroutines touch it. Before the eager lock init this reliably
	// deadlocked: nobody held the lock, yet every goroutine was blocked.
	for round in 0 .. 30 {
		mut c := new_memory_cache('fresh-${round}')
		for i in 0 .. 10 {
			c.set('k${i}', 'v', 0)!
		}

		done := chan bool{cap: 4}
		for _ in 0 .. 4 {
			spawn fn (mut cc MemoryCache, d chan bool) {
				for _ in 0 .. 20 {
					cc.get('k1') or {}
					cc.set('k1', 'v', 0) or {}
					cc.evict_expired()
				}
				d <- true
			}(mut c, done)
		}
		for _ in 0 .. 4 {
			_ := <-done
		}
		c.close()
	}
}

fn test_sweeper_restarts_after_idle_exit() {
	mut c := new_memory_cache('revive')

	// Let the sweeper retire after two idle rounds.
	time.sleep(3 * time.second)
	assert !c.gc_running, 'sweeper should have retired on an empty cache'

	// A write must bring it back.
	c.set('temp', 'v', 0)!
	assert c.gc_running, 'sweeper did not restart after a write'
	c.close()
}

fn test_close_is_idempotent() {
	mut c := new_memory_cache('idem')
	c.set('a', '1', 0)!
	c.close()
	c.close()
	c.close()
	// Cache stays usable after close (documented behaviour).
	assert c.get('a') or { '' } == '1'
}
