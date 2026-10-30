module web

// middleware_shortcircuit_test.v - 短路路径上的后置中间件
//
// 前置中间件短路（鉴权失败、CORS 预检、body 解压失败）同样是一次真实
// 响应。后置中间件不是「handler 的收尾」而是「响应的收尾」——CORS 头、
// 压缩、耗时统计都挂在 ctx.res 上。短路时跳过它们的结果是：
// 401 没有 CORS 头，浏览器把本该读到的错误信息拦成不透明失败；
// 预检响应缺 Access-Control-Allow-*，整个跨域请求直接挂掉。
import veb

// 短路一个请求，同时挂一条后置中间件，返回「后置中间件跑了吗」+ 响应体
fn run_short_circuit_case() (bool, string, string) {
	mut rr := new_route_registry()

	rr.register_with_middleware('GET', '/secure', fn (ctx_ptr voidptr, params map[string]string) veb.Result {
		unsafe {
			c := &veb.Context(ctx_ptr)
			c.send_response_to_client('text/plain', 'HANDLER-RAN')
		}
		return veb.no_result()
	}, [
		// 鉴权失败：发 401 并短路
		fn (ctx &MiddlewareContext) !bool {
			unsafe {
				mut c := ctx
				c.ctx.send_response_to_client('application/json', '{"error":"Unauthorized"}')
			}
			return false
		},
	], [], '')

	mut chain := new_chain()
	chain.use_after(fn (ctx &MiddlewareContext) !bool {
		unsafe {
			mut c := ctx
			c.ctx.set_custom_header('X-Trace', 'yes') or {}
		}
		return true
	})

	mut ctx := &veb.Context{}
	handled := rr.dispatch_with_chain('GET', '/secure', '', voidptr(ctx), chain)
	return handled, ctx.res.body, ctx.res.header.get_custom('X-Trace') or { '' }
}

fn test_short_circuit_still_runs_after_middleware() {
	handled, body, trace := run_short_circuit_case()
	assert handled
	// 短路生效：handler 没跑，响应来自中间件
	assert body.contains('Unauthorized')
	assert !body.contains('HANDLER-RAN')
	// 但响应收尾照做
	assert trace == 'yes'
}

fn test_short_circuit_route_level_after_middleware_runs() {
	mut rr := new_route_registry()
	rr.register_with_middleware('GET', '/r', fn (ctx_ptr voidptr, params map[string]string) veb.Result {
		return veb.no_result()
	}, [
		fn (ctx &MiddlewareContext) !bool {
			return false
		},
	], [
		fn (ctx &MiddlewareContext) !bool {
			unsafe {
				mut c := ctx
				c.ctx.set_custom_header('X-Route-After', 'yes') or {}
			}
			return true
		},
	], '')

	chain := new_chain()
	mut ctx := &veb.Context{}
	rr.dispatch_with_chain('GET', '/r', '', voidptr(ctx), chain)
	assert (ctx.res.header.get_custom('X-Route-After') or { '' }) == 'yes'
}
