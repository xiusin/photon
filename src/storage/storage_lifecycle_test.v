module storage

// storage_lifecycle_test.v - Lifecycle tests for LocalAdapter permissions map
//
// Verifies fixes for:
//   - HIGH #19: permissions map protected by sync.RwMutex (thread-safe read/write)
//   - HIGH #19: permissions map bounded via FIFO eviction (perm_access_order)
//
// Note: The full eviction test (exceeding max_permissions = 10000) is not
// practical for a unit test as it would require creating 10k+ files.
// The eviction logic is verified by code inspection — set_visibility()
// evicts oldest entries when len > max_permissions.
import os

// ============================================================
// set_visibility / visibility — thread-safe round-trip (HIGH #19)
// ============================================================

fn test_storage_lifecycle_set_and_get_visibility() {
	root := '/tmp/photon-storage-lifecycle-test'
	os.rmdir_all(root) or {}
	defer { os.rmdir_all(root) or {} }

	mut adapter := new_local_adapter(root)
	os.mkdir_all(root, os.MkdirParams{}) or {}

	// Create a test file
	full_path := os.join_path(root, 'file1.txt')
	os.write_file(full_path, 'content') or { assert false }

	// Set public visibility
	adapter.set_visibility('file1.txt', .public_) or { assert false }
	vis := adapter.visibility('file1.txt') or { Visibility.private_ }
	assert vis == .public_

	// Set private visibility
	adapter.set_visibility('file1.txt', .private_) or { assert false }
	vis2 := adapter.visibility('file1.txt') or { Visibility.public_ }
	assert vis2 == .private_
}

fn test_storage_lifecycle_visibility_default_private() {
	root := '/tmp/photon-storage-lifecycle-default-test'
	os.rmdir_all(root) or {}
	defer { os.rmdir_all(root) or {} }

	mut adapter := new_local_adapter(root)
	os.mkdir_all(root, os.MkdirParams{}) or {}

	full_path := os.join_path(root, 'default.txt')
	os.write_file(full_path, 'content') or { assert false }

	// Without set_visibility, visibility() returns private by default
	vis := adapter.visibility('default.txt') or { Visibility.public_ }
	assert vis == .private_
}

// ============================================================
// Concurrent set_visibility — thread safety (HIGH #19)
// ============================================================

fn test_storage_lifecycle_concurrent_set_visibility() {
	root := '/tmp/photon-storage-concurrent-test'
	os.rmdir_all(root) or {}
	defer { os.rmdir_all(root) or {} }

	mut adapter := new_local_adapter(root)
	os.mkdir_all(root, os.MkdirParams{}) or {}

	// Create multiple test files
	for i in 0 .. 10 {
		full_path := os.join_path(root, 'file-${i}.txt')
		os.write_file(full_path, 'content-${i}') or { assert false }
	}

	done := chan bool{cap: 10}

	// Concurrently set visibility on different files
	for i in 0 .. 10 {
		spawn fn (ga &LocalAdapter, idx int, d chan bool) {
			vis := if idx % 2 == 0 { Visibility.public_ } else { Visibility.private_ }
			unsafe {
				mut a := ga
				a.set_visibility('file-${idx}.txt', vis) or {}
			}
			d <- true
		}(adapter, i, done)
	}

	for _ in 0 .. 10 {
		_ = <-done
	}

	// Verify all visibilities were set correctly
	for i in 0 .. 10 {
		expected := if i % 2 == 0 { Visibility.public_ } else { Visibility.private_ }
		vis := adapter.visibility('file-${i}.txt') or { Visibility.private_ }
		assert vis == expected
	}
}

fn test_storage_lifecycle_concurrent_read_visibility() {
	root := '/tmp/photon-storage-concurrent-read-test'
	os.rmdir_all(root) or {}
	defer { os.rmdir_all(root) or {} }

	mut adapter := new_local_adapter(root)
	os.mkdir_all(root, os.MkdirParams{}) or {}

	// Create and set visibility for a file
	full_path := os.join_path(root, 'shared.txt')
	os.write_file(full_path, 'content') or { assert false }
	adapter.set_visibility('shared.txt', .public_) or { assert false }

	done := chan bool{cap: 20}

	// Concurrent reads — should all return the same value without racing
	for _ in 0 .. 20 {
		spawn fn (ga &LocalAdapter, d chan bool) {
			vis := ga.visibility('shared.txt') or { Visibility.private_ }
			assert vis == .public_
			d <- true
		}(adapter, done)
	}

	for _ in 0 .. 20 {
		_ = <-done
	}
}

// ============================================================
// perm_access_order — tracks insertion order for eviction
// ============================================================

fn test_storage_lifecycle_perm_access_order_tracks_insertions() {
	root := '/tmp/photon-storage-order-test'
	os.rmdir_all(root) or {}
	defer { os.rmdir_all(root) or {} }

	mut adapter := new_local_adapter(root)
	os.mkdir_all(root, os.MkdirParams{}) or {}

	// Create files and set visibility in order
	for i in 0 .. 5 {
		full_path := os.join_path(root, 'f-${i}.txt')
		os.write_file(full_path, 'content') or { assert false }
		adapter.set_visibility('f-${i}.txt', .public_) or { assert false }
	}

	// perm_access_order should track all 5 insertions
	assert adapter.perm_access_order.len == 5
	assert adapter.permissions.len == 5

	// Verify order matches insertion sequence
	for i in 0 .. 5 {
		assert adapter.perm_access_order[i] == 'f-${i}.txt'
	}
}

fn test_storage_lifecycle_set_visibility_updates_existing() {
	root := '/tmp/photon-storage-update-test'
	os.rmdir_all(root) or {}
	defer { os.rmdir_all(root) or {} }

	mut adapter := new_local_adapter(root)
	os.mkdir_all(root, os.MkdirParams{}) or {}

	full_path := os.join_path(root, 'update.txt')
	os.write_file(full_path, 'content') or { assert false }

	// Set visibility twice on the same file
	adapter.set_visibility('update.txt', .public_) or { assert false }
	adapter.set_visibility('update.txt', .private_) or { assert false }

	// perm_access_order should NOT have duplicate entries
	assert adapter.perm_access_order.len == 1
	assert adapter.permissions.len == 1

	// Latest visibility should be reflected
	vis := adapter.visibility('update.txt') or { Visibility.public_ }
	assert vis == .private_
}
