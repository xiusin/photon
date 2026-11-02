module queue

// failed_jobs.v - Failed Jobs Persistence (Laravel failed_jobs inspired)
// failed_jobs.v - 失败任务持久化（灵感来自 Laravel failed_jobs）
//
// Provides a failed_jobs table abstraction for persisting jobs that
// exhaust all retry attempts. Allows replaying failed jobs via CLI.
// Supports retry with backoff, retry statistics, and pruning.
//
// 提供失败任务表抽象，用于持久化耗尽所有重试的任务。
// 允许通过 CLI 重放失败任务。支持带退避重试、重试统计和清理。
import sync
import time

// FailedJob represents a job that failed after exhausting retries
// FailedJob 表示耗尽重试后失败的任务
pub struct FailedJob {
pub:
	id         string
	job_type   string
	payload    string
	exception  string
	failed_at  i64
	queue_name string
	attempts   int
pub mut:
	retry_count int // Number of retry attempts made / 已重试次数
	next_retry  i64 // Timestamp of next retry / 下次重试时间戳
}

// RetryStats holds statistics about retry operations
// RetryStats 重试操作统计
pub struct RetryStats {
pub mut:
	total_retried   int // Total jobs retried / 总重试任务数
	total_succeeded int // Total retries that succeeded / 重试成功数
	total_failed    int // Total retries that failed / 重试失败数
	pending_retries int // Jobs awaiting retry / 等待重试的任务数
}

// FailedJobRepository persists and retrieves failed jobs
// FailedJobRepository 持久化和检索失败任务
pub interface FailedJobRepository {
mut:
	save(job FailedJob) !
	all() ![]FailedJob
	find_by_id(id string) !FailedJob
	delete_by_id(id string) !
	clear() !
	count() int
	// get_retry_stats returns retry statistics
	// get_retry_stats 返回重试统计
	get_retry_stats() RetryStats
	// increment_retry_stats increments the retry counters
	// increment_retry_stats 增加重试计数器
	increment_retry_stats()
}

// MemoryFailedJobRepository stores failed jobs in memory (thread-safe)
// MemoryFailedJobRepository 在内存中存储失败任务（线程安全）
pub struct MemoryFailedJobRepository {
pub mut:
	jobs []FailedJob
mut:
	mu          sync.Mutex
	retry_stats RetryStats // retry statistics / 重试统计
}

// new_memory_failed_repo creates an in-memory failed job repository
// new_memory_failed_repo 创建内存失败任务仓库
pub fn new_memory_failed_repo() &MemoryFailedJobRepository {
	return &MemoryFailedJobRepository{}
}

// save records a failed job
// save 记录失败任务
pub fn (mut r MemoryFailedJobRepository) save(job FailedJob) ! {
	r.mu.@lock()
	defer { r.mu.unlock() }
	r.jobs << job
}

// all returns all failed jobs
// all 返回所有失败任务
pub fn (mut r MemoryFailedJobRepository) all() ![]FailedJob {
	r.mu.@lock()
	defer { r.mu.unlock() }
	return r.jobs.clone()
}

// find_by_id finds a failed job by ID
// find_by_id 通过 ID 查找失败任务
pub fn (mut r MemoryFailedJobRepository) find_by_id(id string) !FailedJob {
	r.mu.@lock()
	defer { r.mu.unlock() }
	for job in r.jobs {
		if job.id == id {
			return job
		}
	}
	return error('failed job not found: ${id}')
}

// delete_by_id removes a failed job
// delete_by_id 删除失败任务
pub fn (mut r MemoryFailedJobRepository) delete_by_id(id string) ! {
	r.mu.@lock()
	defer { r.mu.unlock() }
	mut idx := -1
	for i, job in r.jobs {
		if job.id == id {
			idx = i
			break
		}
	}
	if idx >= 0 {
		r.jobs.delete(idx)
	}
}

// clear removes all failed jobs
// clear 清除所有失败任务
pub fn (mut r MemoryFailedJobRepository) clear() ! {
	r.mu.@lock()
	defer { r.mu.unlock() }
	r.jobs.clear()
	r.retry_stats = RetryStats{}
}

// count returns the number of failed jobs
// count 返回失败任务数
pub fn (mut r MemoryFailedJobRepository) count() int {
	r.mu.@lock()
	defer { r.mu.unlock() }
	return r.jobs.len
}

// get_retry_stats returns retry statistics
// get_retry_stats 返回重试统计
pub fn (mut r MemoryFailedJobRepository) get_retry_stats() RetryStats {
	r.mu.@lock()
	defer { r.mu.unlock() }
	return r.retry_stats
}

// increment_retry_stats increments the retry counters
// increment_retry_stats 增加重试计数器
pub fn (mut r MemoryFailedJobRepository) increment_retry_stats() {
	r.mu.@lock()
	r.retry_stats.total_retried++
	r.retry_stats.pending_retries++
	r.mu.unlock()
}

// failed_job_seq 给同纳秒内产生的失败任务补一个单调序号。
__global (
	failed_job_seq    sync.Mutex
	g_failed_job_seen int
)

fn next_failed_job_seq() int {
	failed_job_seq.@lock()
	defer { failed_job_seq.unlock() }
	g_failed_job_seen++
	return g_failed_job_seen
}

// FailedJobHandler processes failed jobs during queue worker execution
// FailedJobHandler 在队列 Worker 执行期间处理失败任务
@[heap]
pub struct FailedJobHandler {
pub mut:
	repository &FailedJobRepository
	// max_retries 是单条失败任务允许被「重放」的次数上限。
	//
	// 为什么需要它：retry() 先把记录从仓库里删掉再投递，任务再次失败时
	// 会被重新 save 成一条**全新的**记录，retry_count 归 0。于是
	// 「失败 → 重放 → 再失败 → 再重放」可以无限循环：仓库里永远只有一条
	// 记录，retry_count 永远是 0，退避算出来永远是 1 秒，死信队列成了
	// 一台永远停不下来的重投机器，而日志里每一次都「成功重试」。
	//
	// 负数表示不限次数（显式选择，而不是默认行为）。
	//
	// max_retries caps how many times a single failed job may be replayed.
	// Without it the retry loop is unbounded: each replay deletes the record
	// and a re-failure saves a brand new one, resetting retry_count to 0.
	max_retries int = 3
}

// new_failed_job_handler creates a FailedJobHandler
// new_failed_job_handler 创建 FailedJobHandler
pub fn new_failed_job_handler(repo &FailedJobRepository) &FailedJobHandler {
	return &FailedJobHandler{
		repository: repo
	}
}

// handle records a job as failed
// handle 记录任务为失败
pub fn (mut h FailedJobHandler) handle(job_type string, payload string, exception string, queue_name string, attempts int) ! {
	h.handle_with_retry_count(job_type, payload, exception, queue_name, attempts,
		payload_retry_count(payload))!
}

// handle_with_retry_count 记录失败任务，并显式指定它的重放次数。
// handle_with_retry_count records a failed job with an explicit replay count.
pub fn (mut h FailedJobHandler) handle_with_retry_count(job_type string, payload string, exception string, queue_name string, attempts int, retry_count int) ! {
	failed := FailedJob{
		// 纳秒时间戳在批量失败时会撞（同一 tick 内数百条），撞了就
		// find_by_id 取到别人的记录。补一个进程内单调序号。
		id:          'failed_${time.now().unix_nano()}_${next_failed_job_seq()}'
		job_type:    job_type
		payload:     payload
		exception:   exception
		failed_at:   time.now().unix()
		queue_name:  queue_name
		attempts:    attempts
		retry_count: retry_count
		next_retry:  0
	}
	h.repository.save(failed)!
}

// retry replays a failed job
// retry 重放失败任务
pub fn (mut h FailedJobHandler) retry(id string) ! {
	job := h.repository.find_by_id(id)!
	h.ensure_retryable(job)!
	h.repository.delete_by_id(id)!
	// Re-dispatch with the ORIGINAL payload — `{}` loses every argument.
	job_type, data := split_delay_payload(job.payload)
	if job_type.len == 0 {
		dispatch_later_by_type(job.job_type, 0, job.retry_count + 1)!
		return
	}
	dispatch_later_by_payload(job_type, data, 0, job.retry_count + 1)!
}

// ensure_retryable 在重放前拦住「已经重放太多次」的记录。
//
// 只在 max_retries > 0 时生效：负数表示调用方显式要求不限次数。
//
// ensure_retryable rejects a record that has already been replayed
// max_retries times. A negative max_retries means "no limit".
fn (mut h FailedJobHandler) ensure_retryable(job FailedJob) ! {
	if h.max_retries <= 0 {
		return
	}
	if job.retry_count >= h.max_retries {
		return error('failed job ${job.id} exceeded max retries (${h.max_retries})')
	}
}

// retry_with_backoff replays a failed job with exponential backoff delay.
// The delay is calculated as: base_delay * 2^retry_count (in seconds),
// capped at one hour.
// retry_with_backoff 带退避重试失败任务。
// 延迟计算为：base_delay * 2^retry_count（秒），上限一小时。
//
// `id` 是 FailedJob.id（字符串）。旧签名收 int 并回退到「列表下标」，
// 下标会指向任意别的任务 —— 等于随机重试一条无关记录，已废弃该行为。
pub fn (mut h FailedJobHandler) retry_with_backoff(id string) ! {
	job := h.repository.find_by_id(id)!
	return h.retry_job_with_backoff(job)
}

// retry_job_with_backoff 是 retry_with_backoff 的实现体，也是给
// 「按下标取到的记录」保留的精确入口 —— 调用方已经拿到整条记录，
// 不需要再靠 id 反查。
pub fn (mut h FailedJobHandler) retry_job_with_backoff(job FailedJob) ! {
	h.ensure_retryable(job)!
	// Calculate backoff delay: base 1s * 2^retry_count
	// 计算退避延迟：基准 1s * 2^retry_count
	mut delay_secs := i64(1)
	for _ in 0 .. job.retry_count {
		delay_secs *= 2
	}
	// Cap at 1 hour
	// 上限 1 小时
	if delay_secs > 3600 {
		delay_secs = 3600
	}

	// Update retry metadata before re-dispatching
	// 重新分发前更新重试元数据
	mut updated_job := job
	updated_job.retry_count++
	updated_job.next_retry = time.now().unix() + delay_secs

	// Remove old entry and save updated one
	// 删除旧条目并保存更新的条目
	h.repository.delete_by_id(job.id) or {}
	h.repository.save(updated_job) or {}

	// Re-dispatch with backoff delay, keeping the original payload
	// 带退避延迟重新分发，且保留原始 payload
	job_type, data := split_delay_payload(job.payload)
	if job_type.len == 0 {
		dispatch_later_by_type(job.job_type, delay_secs, updated_job.retry_count)!
	} else {
		dispatch_later_by_payload(job_type, data, delay_secs, updated_job.retry_count)!
	}

	// Update retry stats
	// 更新重试统计
	h.repository.increment_retry_stats()
}

// get_retry_stats returns statistics about retry operations
// get_retry_stats 返回重试操作统计
pub fn (mut h FailedJobHandler) get_retry_stats() RetryStats {
	return h.repository.get_retry_stats()
}

// prune removes failed jobs older than the specified age in hours
// prune 清理超过指定小时数的失败任务
pub fn (mut h FailedJobHandler) prune(age_hours int) ! {
	all_jobs := h.repository.all() or { return }
	cutoff := time.now().unix() - i64(age_hours) * 3600
	for job in all_jobs {
		if job.failed_at > 0 && job.failed_at < cutoff {
			h.repository.delete_by_id(job.id) or {}
		}
	}
}

// retry_all replays all failed jobs
// retry_all 重放所有失败任务
pub fn (mut h FailedJobHandler) retry_all() ! {
	all_jobs := h.repository.all()!
	for job in all_jobs {
		// 超出重放上限的记录原样留着：重放它只会再失败一次并重置计数，
		// 把死信队列变成无限循环的源头。
		h.ensure_retryable(job) or { continue }
		h.repository.delete_by_id(job.id)!
		job_type, data := split_delay_payload(job.payload)
		if job_type.len == 0 {
			dispatch_later_by_type(job.job_type, 0, job.retry_count + 1)!
		} else {
			dispatch_later_by_payload(job_type, data, 0, job.retry_count + 1)!
		}
	}
}

// dispatch_later_by_type re-dispatches a job by type name
// dispatch_later_by_type 通过类型名称重新分发任务
fn dispatch_later_by_type(job_type string, delay_secs i64, retry_count int) ! {
	dispatch_later_by_payload(job_type, '{}', delay_secs, retry_count)!
}

// dispatch_later_by_payload 用原始 payload 重新投递一条失败任务。
//
// 重放必须带原 payload：`{}` 会把任务的全部业务参数抹掉，被重试的任务
// 于是跑在「参数全空」的状态下 —— 要么直接失败，要么做出错误的事。
// 也计入 pending 统计（与 dispatch_later 一致）；退避延迟必须真的生效，
// 原来收了参数却丢掉，传 0 进去，让「指数退避」在派发环节退化成立即重试。
fn dispatch_later_by_payload(job_type string, data string, delay_secs i64, retry_count int) ! {
	payload := serialize_job(job_type, data)
	mut d := get_dispatcher()
	// 重放次数随 payload 一起走：任务再次失败时 record_failure 把它写回
	// 新记录的 retry_count，重投因此有了可累加的计数。少了这个字段，
	// 「失败 → 重放 → 再失败」会把计数重置成 0，循环永远停不下来。
	//
	// The replay count travels with the payload so that a re-failure keeps
	// accumulating instead of resetting to 0 on every new record.
	d.driver.push_attempt(d.default_queue, payload, delay_secs, retry_count)!
	d.increment_stat(d.default_queue, .pending, 1)
}

// split_delay_payload 把失败记录的 payload 拆成 (job_type, data)。
// payload 里可能自带 `<run_at>||` 前缀，先剥掉再按第一个 `||` 切分。
fn split_delay_payload(payload string) (string, string) {
	_, body := split_delay(payload)
	parts := body.split_n('||', 2)
	if parts.len < 2 {
		return '', ''
	}
	return parts[0], parts[1]
}
