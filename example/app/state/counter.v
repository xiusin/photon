module state

// 请求计数放在独立的叶子包里：controllers 和 app 都要用它，
// 而 app 又 import controllers —— 计数若留在 app 根包就会成环。
__global (
	g_req_count int
)

pub fn inc() {
	g_req_count++
}

pub fn get() int {
	return g_req_count
}
