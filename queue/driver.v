module queue

// driver.v - Queue Driver Interface

// QueueDriver is the backend interface for queue storage
pub interface QueueDriver {
	push(queue_name string, payload string) !
	pop(queue_name string) !string
	count(queue_name string) int
	clear(queue_name string) !
}

// serialize_job serializes a job to a pipe-delimited string
fn serialize_job(job_type string, data string) string {
	return '${job_type}||${data}'
}

// deserialize_job extracts job_type and data from serialized payload
fn deserialize_job(payload string) !(string, string) {
	parts := payload.split('||')
	if parts.len < 2 {
		return error('invalid job payload format')
	}
	return parts[0], parts[1]
}
