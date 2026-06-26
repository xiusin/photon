module queue

// worker.v - Queue Worker (Laravel Queue Worker inspired)
// worker.v - 队列 Worker（灵感来自 Laravel Queue Worker）
//
// Polls the queue for jobs and executes them with retry and backoff.
// Jobs are registered by type name to a factory function.
// Supports configurable worker lifecycle, graceful shutdown, and drain mode.
//
// 轮询队列获取任务并执行，支持重试和退避。
// 任务通过类型名称注册到工厂函数。
// 支持可配置的 Worker 生命周期、优雅关闭和排空模式。
import sync
import time

// JobFactory creates a new Job instance from a registered type
// JobFactory 从注册类型创建新的 Job 实例
pub type JobFactory = fn () &Job

// WorkerConfig holds configuration for a QueueWorker
// WorkerConfig 队列 Worker 配置
pub struct WorkerConfig {
pub:
	max_jobs          int    // Max jobs to process (0 = unlimited) / 最大处理任务数（0 = 无限）
	rest_interval     int    // Rest interval in secs after max_jobs / 达到上限后休息间隔（秒）
	timeout           int  = 30   // Job timeout in seconds / 任务超时时间（秒）
	graceful_shutdown bool = true // Enable graceful shutdown / 启用优雅关闭
}

// WorkerLifecycle defines hooks for worker lifecycle events
// WorkerLifecycle 定义 Worker 生命周期事件钩子
pub interface WorkerLifecycle {
	on_start()
	on_job_start(job_type string)
	on_job_complete(job_type string)
	on_job_fail(job_type string, reason string)
	on_stop()
}

// QueueWorker polls and executes jobs from the queue
// QueueWorker 轮询并执行队列中的任务
pub struct QueueWorker {
pub:
	queue_name string = 'default'
	sleep_secs int    = 5 // poll interval when idle / 空闲时轮询间隔
pub mut:
	running        bool
	registry       map[string]JobFactory
	failed_handler &FailedJobHandler = unsafe { nil }
mut:
	mu             sync.Mutex   // protects running flag / 保护 running 标志
	registry_mu    sync.RwMutex // protects registry map / 保护注册表
	stop_ch        chan bool = chan bool{cap: 1}
	config         WorkerConfig // worker configuration / Worker 配置
	lifecycle      &WorkerLifecycle = unsafe { nil } // lifecycle hooks / 生命周期钩子
	active_jobs    int          // currently processing jobs / 当前处理中的任务数
	draining       bool         // drain mode active / 排空模式激活
	drained_ch     chan bool = chan bool{cap: 1} // signal when drained / 排空完成信号
}

// new_worker creates a new QueueWorker with an empty job registry
// new_worker 创建带有空注册表的 QueueWorker
pub fn new_worker() &QueueWorker {
	return &QueueWorker{
		registry: map[string]JobFactory{}
		config: WorkerConfig{}
	}
}

// register adds a job type to the worker's registry.
// The factory function should return a new Job instance.
// Usage:
//   worker.register('SendEmail', fn () &Job { return &SendEmailJob{} })
//
// register 添加任务类型到 Worker 的注册表。
// 工厂函数应返回新的 Job 实例。
pub fn (mut w QueueWorker) register(job_type string, factory JobFactory) {
	w.registry_mu.@lock()
	defer { w.registry_mu.unlock() }
	w.registry[job_type] = factory
}

// set_failed_handler configures the handler for failed jobs
// set_failed_handler 配置失败任务处理器
pub fn (mut w QueueWorker) set_failed_handler(handler &FailedJobHandler) {
	unsafe {
		w.failed_handler = handler
	}
}

// set_lifecycle configures the lifecycle event hooks
// set_lifecycle 配置生命周期事件钩子
pub fn (mut w QueueWorker) set_lifecycle(lc &WorkerLifecycle) {
	unsafe {
		w.lifecycle = lc
	}
}

// run marks the worker as running
// run 标记 Worker 为运行状态
pub fn (mut w QueueWorker) run() {
	w.mu.@lock()
	defer { w.mu.unlock() }
	w.running = true
	w.draining = false
	if !isnil(w.lifecycle) {
		w.lifecycle.on_start()
	}
}

// is_running returns whether the worker is active
// is_running 返回 Worker 是否处于活动状态
pub fn (w &QueueWorker) is_running() bool {
	// Reading a bool is atomic on most platforms, but for memory
	// visibility across goroutines we use the mutex.
	unsafe {
		mut mw := w
		mw.mu.@lock()
		val := mw.running
		mw.mu.unlock()
		return val
	}
}

// start_with_config starts the worker with the given configuration
// start_with_config 使用给定配置启动 Worker
pub fn (mut w QueueWorker) start_with_config(config WorkerConfig) {
	w.mu.@lock()
	w.config = config
	w.running = true
	w.draining = false
	w.mu.unlock()
	if !isnil(w.lifecycle) {
		w.lifecycle.on_start()
	}
}

// drain stops accepting new jobs and waits for current jobs to finish
// drain 停止接受新任务，等待当前任务完成
pub fn (mut w QueueWorker) drain() {
	w.mu.@lock()
	w.draining = true
	w.mu.unlock()

	// Wait until all active jobs are done
	// 等待所有活动任务完成
	for {
		w.mu.@lock()
		jobs := w.active_jobs
		running := w.running
		w.mu.unlock()

		if jobs == 0 || !running {
			break
		}
		time.sleep(50 * time.millisecond)
	}

	// Mark as stopped
	// 标记为已停止
	w.mu.@lock()
	w.running = false
	w.mu.unlock()

	// Signal drained
	// 发送排空完成信号
	select {
		w.drained_ch <- true {}
		else {}
	}

	if !isnil(w.lifecycle) {
		w.lifecycle.on_stop()
	}
}

// job_count returns the number of currently processing jobs
// job_count 返回当前正在处理的任务数
pub fn (mut w QueueWorker) job_count() int {
	w.mu.@lock()
	defer { w.mu.unlock() }
	return w.active_jobs
}

// is_idle returns whether the worker has no active jobs
// is_idle 返回 Worker 是否空闲（无活动任务）
pub fn (mut w QueueWorker) is_idle() bool {
	w.mu.@lock()
	defer { w.mu.unlock() }
	return w.active_jobs == 0
}

// tick does one polling iteration (call in a loop).
// Pops a job from the queue, looks up its handler, and executes
// with retry + backoff logic. Failed jobs are passed to the
// FailedJobHandler if configured.
//
// tick 执行一次轮询迭代（在循环中调用）。
// 从队列弹出任务，查找处理器，使用重试+退避逻辑执行。
// 失败的任务传递给 FailedJobHandler（如果已配置）。
pub fn (mut w QueueWorker) tick() {
	w.mu.@lock()
	running := w.running
	draining := w.draining
	w.mu.unlock()
	if !running {
		return
	}

	// In drain mode, don't pick up new jobs
	// 排空模式下，不获取新任务
	if draining {
		return
	}

	mut d := get_dispatcher()
	payload := d.driver.pop(w.queue_name) or {
		// No jobs available — idle
		return
	}

	job_info := parse_job_payload(payload) or {
		// Corrupt payload — skip
		w.record_failure('unknown', payload, 'failed to parse payload: ${err}', 0)
		return
	}

	// Increment active job count
	// 递增活动任务计数
	w.mu.@lock()
	w.active_jobs++
	w.mu.unlock()

	// Look up the job handler via registry (read-locked)
	w.registry_mu.@rlock()
	factory := w.registry[job_info.name] or {
		w.registry_mu.runlock()
		// Unregistered job type — log and skip
		w.record_failure(job_info.name, payload, 'unregistered job type', 0)
		w.decrement_active_jobs()
		return
	}
	w.registry_mu.runlock()

	job := factory()

	// Fire lifecycle hook: on_job_start
	// 触发生命周期钩子：on_job_start
	if !isnil(w.lifecycle) {
		w.lifecycle.on_job_start(job_info.name)
	}

	// Normalize tries to at least 1 (a job must execute at least once).
	// treats 0 and negative values as "use default of 1"
	mut max_tries := job.tries()
	if max_tries < 1 {
		max_tries = 1
	}
	backoffs := job.backoff()

	// Execute with retry
	// 带重试执行
	mut job_succeeded := false
	for attempt := 0; attempt < max_tries; attempt++ {
		mut has_error := false
		job.handle() or { has_error = true }
		if !has_error {
			// Success — job completed
			job_succeeded = true
			break
		}

		// Handle failure: apply backoff before retry (interruptible)
		if attempt < max_tries - 1 {
			mut delay_secs := i64(1) // default 1s backoff
			if attempt < backoffs.len {
				delay_secs = backoffs[attempt]
			}
			// Interruptible sleep: poll stop_ch so stop() can break retry backoff
			if w.interruptible_sleep(delay_secs) {
				// Worker was stopped during backoff
				break
			}
		}
	}

	if job_succeeded {
		// Fire lifecycle hook: on_job_complete
		// 触发生命周期钩子：on_job_complete
		if !isnil(w.lifecycle) {
			w.lifecycle.on_job_complete(job_info.name)
		}
		// Update dispatcher stats
		// 更新分发器统计
		d.increment_stat(w.queue_name, .completed, 1)
		d.increment_stat(w.queue_name, .total, 1)
	} else {
		// All retries exhausted — record as failed
		// 所有重试耗尽 — 记录为失败
		w.record_failure(job_info.name, payload, 'max retries (${max_tries}) exhausted', max_tries)
		// Fire lifecycle hook: on_job_fail
		// 触发生命周期钩子：on_job_fail
		if !isnil(w.lifecycle) {
			w.lifecycle.on_job_fail(job_info.name, 'max retries (${max_tries}) exhausted')
		}
		// Update dispatcher stats
		// 更新分发器统计
		d.increment_stat(w.queue_name, .failed, 1)
		d.increment_stat(w.queue_name, .total, 1)
	}

	// Decrement active job count
	// 递减活动任务计数
	w.decrement_active_jobs()
}

// decrement_active_jobs safely decrements the active job counter
// decrement_active_jobs 安全地递减活动任务计数器
fn (mut w QueueWorker) decrement_active_jobs() {
	w.mu.@lock()
	defer { w.mu.unlock() }
	if w.active_jobs > 0 {
		w.active_jobs--
	}
}

// interruptible_sleep sleeps for the given seconds, but can be interrupted
// by a stop signal on stop_ch. Returns true if interrupted, false if the
// full duration elapsed.
//
// interruptible_sleep 休眠指定秒数，但可被 stop_ch 上的停止信号中断。
// 如果被中断返回 true，如果完整休眠返回 false。
fn (mut w QueueWorker) interruptible_sleep(delay_secs i64) bool {
	mut remaining_ms := delay_secs * 1000
	for remaining_ms > 0 {
		// Check for stop signal (non-blocking)
		mut stopped := false
		select {
			_ := <-w.stop_ch {
				stopped = true
			}
			else {}
		}
		if stopped {
			w.mu.@lock()
			w.running = false
			w.mu.unlock()
			return true
		}
		sleep_ms := if remaining_ms < 100 { remaining_ms } else { 100 }
		time.sleep(sleep_ms * time.millisecond)
		remaining_ms -= sleep_ms
	}
	return false
}

// record_failure logs a failed job to the configured FailedJobHandler
// record_failure 将失败任务记录到已配置的 FailedJobHandler
fn (mut w QueueWorker) record_failure(job_type string, payload string, reason string, attempts int) {
	mut handler := w.failed_handler
	if isnil(handler) {
		return
	}
	handler.handle(job_type, payload, reason, w.queue_name, attempts) or {}
}

// stop halts the worker and interrupts any pending retry backoff.
// stop 停止 Worker 并中断任何待处理的重试退避。
pub fn (mut w QueueWorker) stop() {
	w.mu.@lock()
	w.running = false
	w.mu.unlock()
	// Signal interruptible_sleep to wake up immediately
	select {
		w.stop_ch <- true {}
		else {}
	}
	if !isnil(w.lifecycle) {
		w.lifecycle.on_stop()
	}
}

// JobInfo holds parsed job metadata
// JobInfo 保存解析后的任务元数据
struct JobInfo {
	name string
	data string
}

// parse_job_payload extracts job type and data from payload
// parse_job_payload 从 payload 提取任务类型和数据
fn parse_job_payload(payload string) !JobInfo {
	name, data := deserialize_job(payload)!
	return JobInfo{
		name: name
		data: data
	}
}
