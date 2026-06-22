module web

// orm_tracker_test.v - OrmEntityTracker 单元测试
// OrmEntityTracker Unit Tests
//
// 测试覆盖 / Test Coverage:
//   - track() 追踪单个实体
//   - track_all() 批量追踪
//   - clear_all() 清除所有追踪
//   - tracked_count() 获取追踪数量
//   - 重复追踪同一实体（允许重复追加）
//   - 空追踪器操作不报错
//   - 并发安全追踪
//   - 阈值告警（超过 threshold 时打印警告）
import sync

// ── new_orm_entity_tracker 测试 / new_orm_entity_tracker tests ──

fn test_new_orm_entity_tracker_empty() {
	// 新创建的追踪器为空
	// Newly created tracker is empty
	mut t := new_orm_entity_tracker()
	assert t.tracked_count() == 0
}

fn test_new_orm_entity_tracker_default_threshold() {
	// 默认阈值为 10000
	// Default threshold is 10000
	mut t := new_orm_entity_tracker()
	assert t.threshold == 10000
}

// ── track() 测试 / track() tests ──

fn test_orm_entity_tracker_track_single() {
	// track() 追踪单个实体
	// track() tracks a single entity
	mut t := new_orm_entity_tracker()
	t.track(voidptr(0x1))
	assert t.tracked_count() == 1
}

fn test_orm_entity_tracker_track_multiple() {
	// track() 追踪多个实体
	// track() tracks multiple entities
	mut t := new_orm_entity_tracker()
	t.track(voidptr(0x1))
	t.track(voidptr(0x2))
	t.track(voidptr(0x3))
	assert t.tracked_count() == 3
}

fn test_orm_entity_tracker_track_increments_count() {
	// 每次追踪后计数递增
	// Count increments after each track
	mut t := new_orm_entity_tracker()
	assert t.tracked_count() == 0
	t.track(voidptr(0x1))
	assert t.tracked_count() == 1
	t.track(voidptr(0x2))
	assert t.tracked_count() == 2
	t.track(voidptr(0x3))
	assert t.tracked_count() == 3
}

fn test_orm_entity_tracker_track_same_entity_twice() {
	// 重复追踪同一实体（允许重复追加，不去重）
	// Tracking the same entity twice is allowed (append, no dedup)
	mut t := new_orm_entity_tracker()
	t.track(voidptr(0x1))
	t.track(voidptr(0x1)) // 重复 / duplicate
	assert t.tracked_count() == 2
}

fn test_orm_entity_tracker_track_nil_pointer() {
	// 追踪 nil 指针（voidptr(0)）不报错
	// Tracking nil pointer (voidptr(0)) does not error
	mut t := new_orm_entity_tracker()
	t.track(voidptr(0))
	assert t.tracked_count() == 1
}

// ── track_all() 测试 / track_all() tests ──

fn test_orm_entity_tracker_track_all_batch() {
	// track_all() 批量追踪多个实体
	// track_all() tracks multiple entities in batch
	mut t := new_orm_entity_tracker()
	entities := [voidptr(0x1), voidptr(0x2), voidptr(0x3)]
	t.track_all(entities)
	assert t.tracked_count() == 3
}

fn test_orm_entity_tracker_track_all_empty() {
	// track_all() 空数组不报错
	// track_all() with empty array does not error
	mut t := new_orm_entity_tracker()
	t.track_all([]voidptr{})
	assert t.tracked_count() == 0
}

fn test_orm_entity_tracker_track_all_after_track() {
	// track() 后再 track_all()
	// track_all() after track()
	mut t := new_orm_entity_tracker()
	t.track(voidptr(0x1))
	assert t.tracked_count() == 1
	t.track_all([voidptr(0x2), voidptr(0x3)])
	assert t.tracked_count() == 3
}

fn test_orm_entity_tracker_track_all_multiple_batches() {
	// 多次 track_all()
	// Multiple track_all() calls
	mut t := new_orm_entity_tracker()
	t.track_all([voidptr(0x1), voidptr(0x2)])
	t.track_all([voidptr(0x3), voidptr(0x4), voidptr(0x5)])
	assert t.tracked_count() == 5
}

// ── clear_all() 测试 / clear_all() tests ──

fn test_orm_entity_tracker_clear_all() {
	// clear_all() 清除所有追踪
	// clear_all() clears all tracked entities
	mut t := new_orm_entity_tracker()
	t.track(voidptr(0x1))
	t.track(voidptr(0x2))
	assert t.tracked_count() == 2
	t.clear_all()
	assert t.tracked_count() == 0
}

fn test_orm_entity_tracker_clear_all_empty() {
	// 空追踪器 clear_all() 不报错
	// clear_all() on empty tracker does not error
	mut t := new_orm_entity_tracker()
	t.clear_all()
	assert t.tracked_count() == 0
}

fn test_orm_entity_tracker_clear_all_idempotent() {
	// 多次 clear_all() 安全
	// Multiple clear_all() calls are safe
	mut t := new_orm_entity_tracker()
	t.track(voidptr(0x1))
	t.clear_all()
	t.clear_all() // 第二次 / second time
	assert t.tracked_count() == 0
}

fn test_orm_entity_tracker_track_after_clear() {
	// 清除后可以继续追踪
	// Can continue tracking after clear
	mut t := new_orm_entity_tracker()
	t.track(voidptr(0x1))
	t.clear_all()
	assert t.tracked_count() == 0
	t.track(voidptr(0x2))
	assert t.tracked_count() == 1
}

fn test_orm_entity_tracker_clear_all_then_track_all() {
	// 清除后批量追踪
	// Batch track after clear
	mut t := new_orm_entity_tracker()
	t.track(voidptr(0x1))
	t.clear_all()
	t.track_all([voidptr(0x2), voidptr(0x3), voidptr(0x4)])
	assert t.tracked_count() == 3
}

// ── tracked_count() 测试 / tracked_count() tests ──

fn test_orm_entity_tracker_tracked_count_zero() {
	// 初始计数为 0
	// Initial count is 0
	mut t := new_orm_entity_tracker()
	assert t.tracked_count() == 0
}

fn test_orm_entity_tracker_tracked_count_after_operations() {
	// 各种操作后的计数
	// Count after various operations
	mut t := new_orm_entity_tracker()
	assert t.tracked_count() == 0
	t.track(voidptr(0x1))
	assert t.tracked_count() == 1
	t.track_all([voidptr(0x2), voidptr(0x3)])
	assert t.tracked_count() == 3
	t.clear_all()
	assert t.tracked_count() == 0
	t.track(voidptr(0x4))
	assert t.tracked_count() == 1
}

// ── 阈值测试 / Threshold tests ──

fn test_orm_entity_tracker_custom_threshold() {
	// 自定义阈值
	// Custom threshold
	mut t := new_orm_entity_tracker()
	t.threshold = 5
	assert t.threshold == 5
}

fn test_orm_entity_tracker_threshold_default() {
	// 默认阈值为 10000
	// Default threshold is 10000
	t := new_orm_entity_tracker()
	assert t.threshold == 10000
}

// ── 并发安全测试 / Concurrency safety tests ──

fn test_orm_entity_tracker_concurrent_track() {
	// 并发追踪不应 panic
	// Concurrent tracking should not panic
	mut t := new_orm_entity_tracker()
	mut wg := sync.new_waitgroup()

	for i in 0 .. 20 {
		wg.add(1)
		spawn fn (mut tracker OrmEntityTracker, idx int, mut w sync.WaitGroup) {
			defer { w.done() }
			tracker.track(voidptr(idx))
		}(mut t, i, mut wg)
	}

	wg.wait()
	assert t.tracked_count() == 20
}

fn test_orm_entity_tracker_concurrent_track_and_clear() {
	// 并发追踪和清除不应 panic
	// Concurrent tracking and clearing should not panic
	mut t := new_orm_entity_tracker()
	mut wg := sync.new_waitgroup()

	for i in 0 .. 10 {
		wg.add(1)
		spawn fn (mut tracker OrmEntityTracker, idx int, mut w sync.WaitGroup) {
			defer { w.done() }
			if idx % 3 == 0 {
				tracker.clear_all()
			} else {
				tracker.track(voidptr(idx))
			}
		}(mut t, i, mut wg)
	}

	wg.wait()
	// 不应 panic / should not panic
	assert true
}

fn test_orm_entity_tracker_concurrent_tracked_count() {
	// 并发读取 tracked_count 不应 panic
	// Concurrent reads of tracked_count should not panic
	mut t := new_orm_entity_tracker()
	for i in 0 .. 50 {
		t.track(voidptr(i))
	}
	mut wg := sync.new_waitgroup()

	for _ in 0 .. 10 {
		wg.add(1)
		spawn fn (mut tracker OrmEntityTracker, mut w sync.WaitGroup) {
			defer { w.done() }
			_ = tracker.tracked_count()
		}(mut t, mut wg)
	}

	wg.wait()
	assert true
}

// ── 边界条件测试 / Edge case tests ──

fn test_orm_entity_tracker_large_number_of_entities() {
	// 追踪大量实体
	// Track a large number of entities
	mut t := new_orm_entity_tracker()
	t.threshold = 100000 // 设置高阈值避免告警 / Set high threshold to avoid warning
	for i in 0 .. 1000 {
		t.track(voidptr(i))
	}
	assert t.tracked_count() == 1000
	t.clear_all()
	assert t.tracked_count() == 0
}

fn test_orm_entity_tracker_track_all_single_entity() {
	// track_all() 只有一个实体
	// track_all() with a single entity
	mut t := new_orm_entity_tracker()
	t.track_all([voidptr(0x1)])
	assert t.tracked_count() == 1
}

fn test_orm_entity_tracker_alternating_track_and_clear() {
	// 交替追踪和清除
	// Alternating track and clear
	mut t := new_orm_entity_tracker()
	for i in 0 .. 5 {
		t.track(voidptr(i))
		assert t.tracked_count() == 1
		t.clear_all()
		assert t.tracked_count() == 0
	}
}

// ── RwMutex 并发读写测试 / RwMutex concurrent read/write tests ──

fn test_orm_entity_tracker_concurrent_track_and_tracked_count() {
	// 并发 track（写）和 tracked_count（读）不应 panic
	// Concurrent track (write) and tracked_count (read) should not panic
	mut t := new_orm_entity_tracker()
	mut wg := sync.new_waitgroup()

	// 写线程 / Write threads
	for i in 0 .. 20 {
		wg.add(1)
		spawn fn (mut tracker OrmEntityTracker, idx int, mut w sync.WaitGroup) {
			defer { w.done() }
			tracker.track(voidptr(idx))
		}(mut t, i, mut wg)
	}

	// 读线程 / Read threads
	for _ in 0 .. 10 {
		wg.add(1)
		spawn fn (mut tracker OrmEntityTracker, mut w sync.WaitGroup) {
			defer { w.done() }
			_ = tracker.tracked_count()
		}(mut t, mut wg)
	}

	wg.wait()
	assert t.tracked_count() == 20
}

fn test_orm_entity_tracker_concurrent_track_all_and_tracked_count() {
	// 并发 track_all（写）和 tracked_count（读）不应 panic
	// Concurrent track_all (write) and tracked_count (read) should not panic
	mut t := new_orm_entity_tracker()
	mut wg := sync.new_waitgroup()

	for i in 0 .. 10 {
		wg.add(1)
		spawn fn (mut tracker OrmEntityTracker, idx int, mut w sync.WaitGroup) {
			defer { w.done() }
			tracker.track_all([voidptr(idx), voidptr(idx + 100)])
		}(mut t, i, mut wg)
	}

	for _ in 0 .. 5 {
		wg.add(1)
		spawn fn (mut tracker OrmEntityTracker, mut w sync.WaitGroup) {
			defer { w.done() }
			_ = tracker.tracked_count()
		}(mut t, mut wg)
	}

	wg.wait()
	assert t.tracked_count() == 20
}

fn test_orm_entity_tracker_concurrent_clear_all_and_tracked_count() {
	// 并发 clear_all（写）和 tracked_count（读）不应 panic
	// Concurrent clear_all (write) and tracked_count (read) should not panic
	mut t := new_orm_entity_tracker()
	for i in 0 .. 50 {
		t.track(voidptr(i))
	}
	mut wg := sync.new_waitgroup()

	for _ in 0 .. 5 {
		wg.add(1)
		spawn fn (mut tracker OrmEntityTracker, mut w sync.WaitGroup) {
			defer { w.done() }
			tracker.clear_all()
		}(mut t, mut wg)
	}

	for _ in 0 .. 5 {
		wg.add(1)
		spawn fn (mut tracker OrmEntityTracker, mut w sync.WaitGroup) {
			defer { w.done() }
			_ = tracker.tracked_count()
		}(mut t, mut wg)
	}

	wg.wait()
	assert true
}

// ── 阈值告警测试 / Threshold warning tests ──

fn test_orm_entity_tracker_threshold_exceeded() {
	// 追踪数量超过阈值时打印警告（此处验证功能不崩溃）
	// Tracking count exceeding threshold prints warning (here verify no crash)
	mut t := new_orm_entity_tracker()
	t.threshold = 5
	for i in 0 .. 10 {
		t.track(voidptr(i))
	}
	// 应追踪 10 个实体（超过阈值 5）/ Should track 10 entities (exceeds threshold 5)
	assert t.tracked_count() == 10
}

fn test_orm_entity_tracker_threshold_at_boundary() {
	// 追踪数量恰好等于阈值
	// Tracking count exactly equals threshold
	mut t := new_orm_entity_tracker()
	t.threshold = 5
	for i in 0 .. 5 {
		t.track(voidptr(i))
	}
	assert t.tracked_count() == 5
}

fn test_orm_entity_tracker_threshold_zero() {
	// 阈值为 0 时任何追踪都会触发告警（但不崩溃）
	// Threshold 0 means any tracking triggers warning (but no crash)
	mut t := new_orm_entity_tracker()
	t.threshold = 0
	t.track(voidptr(0x1))
	assert t.tracked_count() == 1
}

// ── 边界条件增强测试 / Enhanced edge case tests ──

fn test_orm_entity_tracker_track_all_large_batch() {
	// 大批量追踪
	// Large batch tracking
	mut t := new_orm_entity_tracker()
	t.threshold = 100000
	mut entities := []voidptr{cap: 5000}
	for i in 0 .. 5000 {
		entities << voidptr(i)
	}
	t.track_all(entities)
	assert t.tracked_count() == 5000
}

fn test_orm_entity_tracker_clear_all_then_track_all_large() {
	// 清除后大批量追踪
	// Large batch tracking after clear
	mut t := new_orm_entity_tracker()
	t.track(voidptr(0x1))
	t.clear_all()
	t.threshold = 100000
	mut entities := []voidptr{cap: 1000}
	for i in 0 .. 1000 {
		entities << voidptr(i)
	}
	t.track_all(entities)
	assert t.tracked_count() == 1000
}

fn test_orm_entity_tracker_tracked_count_after_partial_clear() {
	// 追踪后清除再追踪，计数正确
	// Track, clear, track again — count is correct
	mut t := new_orm_entity_tracker()
	t.track(voidptr(0x1))
	t.track(voidptr(0x2))
	assert t.tracked_count() == 2
	t.clear_all()
	assert t.tracked_count() == 0
	t.track(voidptr(0x3))
	t.track(voidptr(0x4))
	t.track(voidptr(0x5))
	assert t.tracked_count() == 3
}

fn test_orm_entity_tracker_track_all_with_single_nil() {
	// track_all 包含 nil 指针
	// track_all with nil pointer
	mut t := new_orm_entity_tracker()
	t.track_all([voidptr(0)])
	assert t.tracked_count() == 1
}