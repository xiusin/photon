module queue

// dispatcher.v - Job Dispatcher (Laravel Queue Dispatcher inspired)
// dispatcher.v - 任务分发器（灵感来自 Laravel Queue Dispatcher）
import time
import sync

// get_dispatcher returns the global queue singleton (thread-safe).
// Uses double-checked locking with a read lock on the fast path so the
// write mutex is only contended during the very first initialization.
//
// IMPORTANT (H5): the fast-path read of global_dispatcher MUST be under at
// least a read lock. A bare `if global_dispatcher != nil` read has no memory
// barrier — on weak-memory architectures (ARM, Apple Silicon) another
// goroutine's write to global_dispatcher may not be visible, leading to
// duplicate initialization or use of a partially-constructed object.
//
// get_dispatcher 返回全局队列单例（线程安全）。
// 使用双重检查锁定，快速路径使用读锁，写锁仅在首次初始化时竞争。
fn get_dispatcher() &QueueDispatcher {
	// Fast path: read under read lock for memory visibility.
	dispatcher_mu.rlock()
	d := unsafe { global_dispatcher }
	dispatcher_mu.runlock()
	if !isnil(d) {
		return d
	}

	// Slow path: acquire write lock to create the dispatcher.
	dispatcher_mu.@lock()
	// Double-check after acquiring write lock (another goroutine may have
	// created it while we waited).
	if !isnil(unsafe { global_dispatcher }) {
		d2 := unsafe { global_dispatcher }
		dispatcher_mu.unlock()
		return d2
	}
	unsafe {
		global_dispatcher = new_dispatcher(new_memory_driver())
	}
	d3 := unsafe { global_dispatcher }
	dispatcher_mu.unlock()
	return d3
}

__global (
	dispatcher_mu     sync.RwMutex
	global_dispatcher &QueueDispatcher
)

// QueueStats holds statistics for a queue
// QueueStats 队列统计信息
pub struct QueueStats {
pub mut:
	pending   int // Jobs waiting to be processed / 等待处理的任务数
	completed int // Jobs completed successfully / 成功完成的任务数
	failed    int // Jobs that failed / 失败的任务数
	total     int // Total jobs processed (completed + failed) / 总处理任务数
}

// JobFactoryFn creates a new Job instance from a registered type
// JobFactoryFn 从注册类型创建新的 Job 实例
pub type JobFactoryFn = fn () &Job

// QueueDispatcher handles job dispatching with chain/batch/later support
// QueueDispatcher 处理任务分发，支持链式/批量/延迟
pub struct QueueDispatcher {
pub:
	default_queue string = 'default'
pub mut:
	driver &QueueDriver = new_memory_driver()
mut:
	job_factories map[string]JobFactoryFn // job_type → factory / 任务类型 → 工厂
	paused_queues map[string]bool         // paused queue names / 暂停的队列名称
	stats         map[string]QueueStats   // queue_name → stats / 队列名称 → 统计
	factories_mu  sync.RwMutex            // protects job_factories / 保护 job_factories
	paused_mu     sync.RwMutex            // protects paused_queues / 保护 paused_queues
	stats_mu      sync.Mutex              // protects stats / 保护 stats
}

// new_dispatcher creates a QueueDispatcher
// new_dispatcher 创建 QueueDispatcher
pub fn new_dispatcher(driver &MemoryDriver) &QueueDispatcher {
	return unsafe {
		&QueueDispatcher{
			driver: driver
			job_factories: map[string]JobFactoryFn{}
			paused_queues: map[string]bool{}
			stats: map[string]QueueStats{}
		}
	}
}

// register_job_factory registers a job factory with metadata for auto-dispatch
// register_job_factory 注册带元数据的任务工厂，用于自动分发
pub fn (mut d QueueDispatcher) register_job_factory(meta JobMetadata, factory JobFactoryFn) {
	d.factories_mu.@lock()
	defer { d.factories_mu.unlock() }
	d.job_factories[meta.job_type] = factory
}

// dispatch pushes a job onto the default queue
// dispatch 将任务推入默认队列
pub fn dispatch(job Job) ! {
	mut d := get_dispatcher()
	payload := serialize_job(job.job_type(), '{}')
	d.driver.push(d.default_queue, payload)!
	d.increment_stat(d.default_queue, .pending, 1)
}

// dispatch_on pushes a job onto a specific queue
// dispatch_on 将任务推入指定队列
pub fn dispatch_on(job Job, queue_name string) ! {
	mut d := get_dispatcher()
	// Check if queue is paused / 检查队列是否已暂停
	d.paused_mu.@rlock()
	is_paused := d.paused_queues[queue_name] or { false }
	d.paused_mu.runlock()
	if is_paused {
		return error('queue ${queue_name} is paused')
	}
	payload := serialize_job(job.job_type(), '{}')
	d.driver.push(queue_name, payload)!
	d.increment_stat(queue_name, .pending, 1)
}

// dispatch_bulk dispatches multiple jobs as a batch onto the default queue
// dispatch_bulk 批量分发多个任务到默认队列
pub fn dispatch_bulk(jobs []Job) ! {
	mut d := get_dispatcher()
	for job in jobs {
		payload := serialize_job(job.job_type(), '{}')
		d.driver.push(d.default_queue, payload)!
		d.increment_stat(d.default_queue, .pending, 1)
	}
}

// dispatch_chain dispatches jobs sequentially
// dispatch_chain 顺序分发任务链
pub fn dispatch_chain(jobs []Job) ! {
	mut d := get_dispatcher()
	for job in jobs {
		payload := serialize_job(job.job_type(), '{}')
		d.driver.push(d.default_queue, payload)!
		d.increment_stat(d.default_queue, .pending, 1)
	}
}

// dispatch_chain_with_delay dispatches jobs sequentially with individual delays
// dispatch_chain_with_delay 链式延迟分发，每个任务带有独立延迟
pub fn dispatch_chain_with_delay(jobs []Job, delay_secs []int) ! {
	mut d := get_dispatcher()
	for i, job in jobs {
		delay := if i < delay_secs.len { delay_secs[i] } else { 0 }
		push(d.default_queue, job, i64(delay))!
		d.increment_stat(d.default_queue, .pending, 1)
	}
}

// push pushes a serialized job to a specific queue
// push 将序列化的任务推入指定队列
pub fn push(queue_name string, job Job, delay_secs i64) ! {
	mut d := get_dispatcher()
	mut payload := serialize_job(job.job_type(), '{}')

	// Delayed jobs include a timestamp prefix
	// 延迟任务包含时间戳前缀
	if delay_secs > 0 {
		run_at := time.now().unix_nano() + delay_secs * 1_000_000_000
		payload = '${run_at}||${payload}'
	}
	d.driver.push(queue_name, payload)!
}

// dispatch_later dispatches a job to run after a delay
// dispatch_later 延迟分发任务
pub fn dispatch_later(job Job, delay_secs i64) ! {
	push('default', job, delay_secs)!
}

// dispatch_batch dispatches multiple jobs as a batch
// dispatch_batch 批量分发任务
pub fn dispatch_batch(jobs []Job) !string {
	batch_id := generate_batch_id()
	mut d := get_dispatcher()
	for job in jobs {
		payload := serialize_job(job.job_type(), '{"batch_id":"${batch_id}"}')
		d.driver.push(d.default_queue, payload)!
		d.increment_stat(d.default_queue, .pending, 1)
	}
	return batch_id
}

// get_queue_stats returns statistics for a specific queue
// get_queue_stats 返回指定队列的统计信息
pub fn get_queue_stats(queue_name string) QueueStats {
	mut d := get_dispatcher()
	d.stats_mu.@lock()
	defer { d.stats_mu.unlock() }
	mut s := d.stats[queue_name] or { QueueStats{} }
	// Update pending count from driver / 从驱动更新等待数
	s.pending = d.driver.count(queue_name)
	return s
}

// pause_queue pauses a queue (rejects new dispatches)
// pause_queue 暂停队列（拒绝新分发）
pub fn pause_queue(queue_name string) {
	mut d := get_dispatcher()
	d.paused_mu.@lock()
	defer { d.paused_mu.unlock() }
	d.paused_queues[queue_name] = true
}

// resume_queue resumes a paused queue
// resume_queue 恢复暂停的队列
pub fn resume_queue(queue_name string) {
	mut d := get_dispatcher()
	d.paused_mu.@lock()
	defer { d.paused_mu.unlock() }
	d.paused_queues.delete(queue_name)
}

// is_queue_paused checks if a queue is paused
// is_queue_paused 检查队列是否已暂停
pub fn is_queue_paused(queue_name string) bool {
	mut d := get_dispatcher()
	d.paused_mu.@rlock()
	defer { d.paused_mu.runlock() }
	return d.paused_queues[queue_name] or { false }
}

// count returns the number of pending jobs
// count 返回等待处理的任务数
pub fn count() int {
	mut d := get_dispatcher()
	return d.driver.count(d.default_queue)
}

// clear removes all jobs from the default queue
// clear_queue 清除默认队列中的所有任务
pub fn clear_queue() ! {
	mut d := get_dispatcher()
	d.driver.clear(d.default_queue)!
}

// StatField identifies which stats field to increment
// StatField 标识要递增的统计字段
enum StatField {
	pending
	completed
	failed
	total
}

// increment_stat atomically increments a stats field for a queue
// increment_stat 原子地递增队列的统计字段
fn (mut d QueueDispatcher) increment_stat(queue_name string, field StatField, amount int) {
	d.stats_mu.@lock()
	defer { d.stats_mu.unlock() }
	mut s := d.stats[queue_name] or { QueueStats{} }
	match field {
		.pending { s.pending += amount }
		.completed { s.completed += amount }
		.failed { s.failed += amount }
		.total { s.total += amount }
	}
	d.stats[queue_name] = s
}

// generate_batch_id creates a unique batch identifier
// generate_batch_id 创建唯一的批量标识符
fn generate_batch_id() string {
	return 'batch_${time.now().unix_nano()}'
}
