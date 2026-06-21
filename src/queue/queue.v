module queue

// queue.v - Photon Queue Module Entry (Laravel Queue inspired)
//
// A job queue system with:
//   - Job dispatching (immediate, delayed, chain, batch)
//   - Serialization for transport
//   - Retry with configurable backoff
//   - Background worker (poll + execute)
//   - Pluggable backends (in-memory default)

// JobPayload wraps job data for transport
pub struct JobPayload {
pub:
	id       string
	job_type string
	data     string // JSON serialized
	attempts int
pub mut:
	delay_secs i64
}

// Job is the interface all queue jobs must implement
pub interface Job {
	job_type() string
	handle() !
	tries() int
	backoff() []i64
}
