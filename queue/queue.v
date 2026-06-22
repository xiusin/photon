module queue

// queue.v - Photon Queue Module Entry (Laravel Queue inspired)
// queue.v - Photon 队列模块入口（灵感来自 Laravel Queue）
//
// A job queue system with:
//   - Job dispatching (immediate, delayed, chain, batch)
//   - Serialization for transport
//   - Retry with configurable backoff
//   - Background worker (poll + execute)
//   - Pluggable backends (in-memory default)
//   - Comptime job scanning & auto-registration via @[job] annotations
//
// 队列系统功能：
//   - 任务分发（即时、延迟、链式、批量）
//   - 传输序列化
//   - 可配置退避的重试机制
//   - 后台 Worker（轮询 + 执行）
//   - 可插拔后端（默认内存）
//   - 编译期 @[job] 注解扫描与自动注册

// JobPayload wraps job data for transport
// JobPayload 包装任务数据用于传输
pub struct JobPayload {
pub:
	id       string
	job_type string
	data     string // JSON serialized / JSON 序列化数据
	attempts int
pub mut:
	delay_secs i64
}

// Job is the interface all queue jobs must implement
// Job 是所有队列任务必须实现的接口
pub interface Job {
	job_type() string
	handle() !
	tries() int
	backoff() []i64
}

// ============================================================
// Job Annotation & Comptime Scanning
// Job 注解与编译期扫描
// ============================================================
//
// Supported annotations / 支持的注解：
//   @[job]                    — Mark struct as a Job Bean / 标记 struct 为 Job Bean
//   @[job: 'queue_name']      — Specify target queue / 指定目标队列名称
//   @[retry(3)]               — Max retry count / 最大重试次数
//   @[backoff('1000,5000,10000')] — Backoff strategy (ms) / 退避策略（毫秒）
//   @[timeout(30)]            — Job timeout in seconds / 任务超时时间（秒）

// JobMetadata holds comptime-scanned metadata for a Job struct
// JobMetadata 保存编译期扫描的 Job 元数据
pub struct JobMetadata {
pub:
	job_type    string   // Job type name / 任务类型名称
	queue_name  string   // Target queue name / 目标队列名称
	max_retries int      // Max retry attempts / 最大重试次数
	backoff_ms  []int    // Backoff delays in ms / 退避延迟（毫秒）
	timeout_secs int     // Job timeout in seconds / 任务超时时间（秒）
}

// default_job_metadata returns a JobMetadata with sensible defaults
// default_job_metadata 返回带有合理默认值的 JobMetadata
pub fn default_job_metadata(job_type string) JobMetadata {
	return JobMetadata{
		job_type:     job_type
		queue_name:   'default'
		max_retries:  3
		backoff_ms:   [1000, 5000, 10000]
		timeout_secs: 30
	}
}

// scan_job scans a Job struct's comptime attributes and returns JobMetadata.
// Uses V 0.5.x `$for attr in T.attributes` to read @[job], @[retry], @[backoff], @[timeout].
//
// scan_job 扫描 Job struct 的编译期属性，返回 JobMetadata。
// 使用 V 0.5.x 的 `$for attr in T.attributes` 读取 @[job]、@[retry]、@[backoff]、@[timeout]。
pub fn scan_job[T]() JobMetadata {
	mut meta := default_job_metadata(T.name)

	$for attr in T.attributes {
		if attr.name == 'job' {
			if attr.has_arg {
				meta.queue_name = attr.arg
			}
		}
		if attr.name == 'retry' {
			if attr.has_arg {
				meta.max_retries = attr.arg.int()
			}
		}
		if attr.name == 'backoff' {
			if attr.has_arg {
				parts := attr.arg.split(',')
				mut delays := []int{}
				for p in parts {
					delays << p.trim_space().int()
				}
				if delays.len > 0 {
					meta.backoff_ms = delays
				}
			}
		}
		if attr.name == 'timeout' {
			if attr.has_arg {
				meta.timeout_secs = attr.arg.int()
			}
		}
	}

	return meta
}

// register_job auto-registers a Job type with the QueueDispatcher.
// Scans comptime attributes and registers the job factory.
//
// register_job 自动注册 Job 类型到 QueueDispatcher。
// 扫描编译期属性并注册任务工厂。
pub fn register_job[T](mut dispatcher QueueDispatcher) {
	meta := scan_job[T]()
	factory := fn () &Job {
		mut j := T{}
		return &j
	}
	dispatcher.register_job_factory(meta, factory)
}
