module web

// orm_tracker.v - ORM 实体追踪与回收
// ORM Entity Tracking and Reclamation
//
// 追踪请求级 ORM 实体引用。请求结束后清除所有引用，使实体可被 GC 回收。
// 请求结束后由 after_completion 触发 clear_all()。
//
// Tracks request-scoped ORM entity references. After the request ends,
// clears all references so entities can be GC'd.
// clear_all() is triggered by after_completion after the request ends.
import sync

// OrmEntityTracker 追踪请求级 ORM 实体引用。
// 请求结束后清除所有引用，使实体可被 GC 回收。
// 使用 sync.RwMutex 允许 tracked_count() 等读操作并发执行。
//
// OrmEntityTracker tracks request-scoped ORM entity references.
// After the request ends, clears all references so entities can be GC'd.
// Uses sync.RwMutex to allow concurrent reads for tracked_count() etc.
@[heap]
pub struct OrmEntityTracker {
pub mut:
	entities  []voidptr
	mu        sync.RwMutex
	threshold int = 10000 // 追踪数量告警阈值 / tracking count warning threshold
}

// new_orm_entity_tracker 创建实体追踪器。
// new_orm_entity_tracker creates an entity tracker.
pub fn new_orm_entity_tracker() &OrmEntityTracker {
	return &OrmEntityTracker{
		entities: []voidptr{}
	}
}

// track 追踪一个 ORM 实体引用。O(1) 追加操作。
// 使用 defer { mu.unlock() } 保证锁释放，防止异常路径锁泄漏。
//
// track tracks an ORM entity reference. O(1) append operation.
// Uses defer { mu.unlock() } to guarantee lock release, preventing lock leaks on error paths.
pub fn (mut t OrmEntityTracker) track(entity voidptr) {
	t.mu.@lock()
	defer { t.mu.unlock() }
	t.entities << entity
	if t.entities.len > t.threshold {
		eprintln('[OrmEntityTracker] tracking count exceeded threshold: ${t.entities.len} > ${t.threshold}')
	}
}

// track_all 批量追踪多个实体引用。
// 使用 defer { mu.unlock() } 保证锁释放。
//
// track_all tracks multiple entity references in batch.
// Uses defer { mu.unlock() } to guarantee lock release.
pub fn (mut t OrmEntityTracker) track_all(entities []voidptr) {
	t.mu.@lock()
	defer { t.mu.unlock() }
	t.entities << entities
	if t.entities.len > t.threshold {
		eprintln('[OrmEntityTracker] tracking count exceeded threshold: ${t.entities.len} > ${t.threshold}')
	}
}

// clear_all 清除所有追踪的实体引用。
// 请求结束后由 after_completion 触发。
// 使用 defer { mu.unlock() } 保证锁释放。
//
// clear_all clears all tracked entity references.
// Triggered by after_completion after the request ends.
// Uses defer { mu.unlock() } to guarantee lock release.
pub fn (mut t OrmEntityTracker) clear_all() {
	t.mu.@lock()
	defer { t.mu.unlock() }
	t.entities.clear()
}

// tracked_count 返回当前追踪的实体数量。
// 使用 rlock 允许与其他读操作并发。
//
// tracked_count returns the current number of tracked entities.
// Uses rlock to allow concurrency with other read operations.
pub fn (mut t OrmEntityTracker) tracked_count() int {
	t.mu.rlock()
	defer { t.mu.runlock() }
	return t.entities.len
}
