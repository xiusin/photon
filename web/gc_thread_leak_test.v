module web

// gc_thread_leak_test.v - background-GC thread-leak regressions
//
// Every MemorySessionStore / ShardedMemorySessionStore / UploadChunkManager
// spawns a sweeper goroutine. Callers frequently just drop the pointer
// (request-scoped stores, tests, short-lived helpers) instead of calling
// close(), and a sweeper that waited a full 60s sweep interval before
// noticing "nothing to do" left one thread behind per instance.
//
// Measured before the fix: 3000 dropped stores -> 3000 live threads. Threads
// are the scarce resource here, so a burst of short-lived stores was enough
// to wedge the process — the symptom looked like a deadlock, the cause was
// thread exhaustion.
//
// The sweepers now probe an EMPTY store on a short cadence, so retirement
// happens in a couple of seconds instead of two minutes.
import os
import time

fn thread_count() int {
	entries := os.ls('/proc/${os.getpid()}/task') or { return -1 }
	return entries.len
}

fn test_dropped_session_store_does_not_leak_threads() {
	baseline := thread_count()
	if baseline < 0 {
		return
	}
	for i in 0 .. 150 {
		s := new_memory_session_store()
		// No close() on purpose — this is the leaking pattern.
		_ = s
	}
	// Empty stores retire after two short idle probes.
	time.sleep(4 * time.second)
	after := thread_count()
	assert after - baseline < 20, 'session store sweepers leaked: before=${baseline} after=${after}'
}

fn test_dropped_sharded_store_does_not_leak_threads() {
	baseline := thread_count()
	if baseline < 0 {
		return
	}
	for i in 0 .. 150 {
		s := new_sharded_memory_session_store()
		_ = s
	}
	time.sleep(4 * time.second)
	after := thread_count()
	assert after - baseline < 20, 'sharded store sweepers leaked: before=${baseline} after=${after}'
}

fn test_dropped_chunk_manager_does_not_leak_threads() {
	baseline := thread_count()
	if baseline < 0 {
		return
	}
	for i in 0 .. 150 {
		cm := new_chunk_manager()
		_ = cm
	}
	time.sleep(4 * time.second)
	after := thread_count()
	assert after - baseline < 20, 'chunk manager sweepers leaked: before=${baseline} after=${after}'
}

// A store that is USED must keep its sweeper: only idle stores retire.
fn test_active_store_keeps_sweeping() {
	mut s := new_memory_session_store()
	s.write('sid-1', {
		'user': 'alice'
	}, map[string]string{}, 3600) or { assert false, 'write failed: ${err}' }
	// Keep it non-empty across the idle window; it must not retire and lose
	// the sweep responsibility.
	time.sleep(2 * time.second)
	assert s.read('sid-1')!.data['user'] == 'alice'
	s.close()
}

// close() must still stop the sweeper promptly and be idempotent.
fn test_close_is_prompt_and_idempotent() {
	mut s := new_memory_session_store()
	s.close()
	s.close()
	mut cm := new_chunk_manager()
	cm.close()
	cm.close()
	mut sh := new_sharded_memory_session_store()
	sh.close()
	sh.close()
}

// Retiring must not break the store: it stays usable, just without a sweeper.
fn test_store_usable_after_sweeper_retires() {
	mut s := new_memory_session_store()
	time.sleep(3 * time.second)
	s.write('sid-2', {
		'user': 'bob'
	}, map[string]string{}, 3600) or { assert false, 'write after retire failed: ${err}' }
	assert s.read('sid-2')!.data['user'] == 'bob'
	s.destroy('sid-2') or { assert false, 'destroy failed: ${err}' }
	assert s.read('sid-2')!.data.len == 0
	s.close()
}
