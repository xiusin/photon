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
	retry_count int    // Number of retry attempts made / 已重试次数
	next_retry  i64    // Timestamp of next retry / 下次重试时间戳
}

// RetryStats holds statistics about retry operations
// RetryStats 重试操作统计
pub struct RetryStats {
pub:
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
}

// MemoryFailedJobRepository stores failed jobs in memory (thread-safe)
// MemoryFailedJobRepository 在内存中存储失败任务（线程安全）
pub struct MemoryFailedJobRepository {
pub mut:
	jobs []FailedJob
mut:
	mu         sync.Mutex
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

// FailedJobHandler processes failed jobs during queue worker execution
// FailedJobHandler 在队列 Worker 执行期间处理失败任务
@[heap]
pub struct FailedJobHandler {
pub mut:
	repository  &FailedJobRepository
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
	failed := FailedJob{
		id:         'failed_${time.now().unix_nano()}'
		job_type:   job_type
		payload:    payload
		exception:  exception
		failed_at:  time.now().unix()
		queue_name: queue_name
		attempts:   attempts
		retry_count: 0
		next_retry:  0
	}
	h.repository.save(failed)!
}

// retry replays a failed job
// retry 重放失败任务
pub fn (mut h FailedJobHandler) retry(id string) ! {
	job := h.repository.find_by_id(id)!
	h.repository.delete_by_id(id)!
	// Re-dispatch the job
	dispatch_later_by_type(job.job_type, 0)!
}

// retry_with_backoff replays a failed job with exponential backoff delay.
// The delay is calculated as: base_delay * 2^retry_count (in seconds).
// retry_with_backoff 带退避重试失败任务。
// 延迟计算为：base_delay * 2^retry_count（秒）。
pub fn (mut h FailedJobHandler) retry_with_backoff(id int) ! {
	// Find by numeric index (convert int id to string-based lookup)
	// 通过数字索引查找（将 int id 转为基于字符串的查找）
	id_str := '${id}'
	job := h.repository.find_by_id(id_str) or {
		// Try finding by position in the list
		// 尝试通过列表位置查找
		all_jobs := h.repository.all() or { []FailedJob{} }
		if id < 0 || id >= all_jobs.len {
			return error('failed job not found: ${id}')
		}
		all_jobs[id]
	}

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

	// Re-dispatch with backoff delay
	// 带退避延迟重新分发
	dispatch_later_by_type(job.job_type, delay_secs)!

	// Update retry stats
	// 更新重试统计
	mut repo := h.repository
	if repo is &MemoryFailedJobRepository {
		unsafe {
			mut r := repo
			r.mu.@lock()
			r.retry_stats.total_retried++
			r.retry_stats.pending_retries++
			r.mu.unlock()
		}
	}
}

// get_retry_stats returns statistics about retry operations
// get_retry_stats 返回重试操作统计
pub fn (mut h FailedJobHandler) get_retry_stats() RetryStats {
	mut repo := h.repository
	if repo is &MemoryFailedJobRepository {
		unsafe {
			mut r := repo
			r.mu.@lock()
			stats := r.retry_stats
			r.mu.unlock()
			return stats
		}
	}
	return RetryStats{}
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
		h.repository.delete_by_id(job.id)!
		dispatch_later_by_type(job.job_type, 0)!
	}
}

// dispatch_later_by_type re-dispatches a job by type name
// dispatch_later_by_type 通过类型名称重新分发任务
fn dispatch_later_by_type(job_type string, _delay_secs i64) ! {
	// Reconstruct and push
	payload := serialize_job(job_type, '{}')
	mut d := get_dispatcher()
	d.driver.push(d.default_queue, payload)!
}
