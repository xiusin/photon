module web

// k8s_probe_test.v - Tests for K8s liveness & readiness probes (SubTask D8.3)
//
// Verifies that the K8s probe endpoints:
//   - /health/liveness always returns 200 UP (process is alive)
//   - /health/readiness returns 200 UP when ready, 503 OUT_OF_SERVICE when not
//   - Both set Content-Type: application/json
//   - The mock handler dispatches both probes correctly
//   - Unknown paths return 404
//   - ApplicationContext.is_readiness_ready() reflects state + SmartLifecycle
//   - Liveness and readiness behave differently (liveness never 503)
import core

// ── serve_liveness unit tests ──

fn test_serve_liveness_returns_200() {
	body, ct, code := serve_liveness()
	assert code == 200
	assert ct == probe_content_type
	assert body.len > 0
}

fn test_serve_liveness_content_type_is_json() {
	_, ct, _ := serve_liveness()
	assert ct == probe_content_type
}

fn test_serve_liveness_body_contains_up() {
	body, _, _ := serve_liveness()
	assert body.contains('"UP"')
}

fn test_serve_liveness_body_is_valid_json() {
	body, _, _ := serve_liveness()
	assert body == '{"status":"UP"}'
}

fn test_serve_liveness_never_returns_503() {
	// Liveness is a pure process-alive check — if the server can respond,
	// the process is alive. It must never return 503.
	_, _, code := serve_liveness()
	assert code != 503
	assert code == 200
}

// ── serve_readiness unit tests ──

fn test_serve_readiness_ready_returns_200() {
	mut ctx := core.new_application_context()
	ctx.refresh()!
	// No SmartLifecycle beans registered → ready as soon as state is .ready

	body, ct, code := serve_readiness(ctx)
	assert code == 200
	assert ct == probe_content_type
	assert body.contains('"UP"')
}

fn test_serve_readiness_not_ready_returns_503() {
	mut ctx := core.new_application_context()
	// Don't refresh — state is .created, so not ready

	body, ct, code := serve_readiness(ctx)
	assert code == 503
	assert ct == probe_content_type
	assert body.contains('"OUT_OF_SERVICE"')
}

fn test_serve_readiness_content_type_is_json() {
	mut ctx := core.new_application_context()
	ctx.refresh()!

	_, ct, _ := serve_readiness(ctx)
	assert ct == probe_content_type
}

fn test_serve_readiness_ready_body_is_valid_json() {
	mut ctx := core.new_application_context()
	ctx.refresh()!

	body, _, _ := serve_readiness(ctx)
	assert body == '{"status":"UP"}'
}

fn test_serve_readiness_not_ready_body_is_valid_json() {
	mut ctx := core.new_application_context()

	body, _, _ := serve_readiness(ctx)
	assert body == '{"status":"OUT_OF_SERVICE"}'
}

fn test_serve_readiness_nil_context_returns_503() {
	nil_ctx := unsafe { &core.ApplicationContext(nil) }
	body, _, code := serve_readiness(nil_ctx)
	assert code == 503
	assert body.contains('"OUT_OF_SERVICE"')
}

// ── MockMvc liveness probe tests ──

fn test_liveness_probe_returns_200() {
	mut ctx := core.new_application_context()

	mut mvc := new_mockmvc()
	mvc.get('/health/liveness', k8s_probe_mock_handler(ctx))

	result := mvc.perform(mock_request('GET', '/health/liveness'))!
	result.assert_status(200)!
}

fn test_liveness_probe_content_type_is_json() {
	mut ctx := core.new_application_context()

	mut mvc := new_mockmvc()
	mvc.get('/health/liveness', k8s_probe_mock_handler(ctx))

	result := mvc.perform(mock_request('GET', '/health/liveness'))!
	result.assert_header('Content-Type', probe_content_type)!
}

fn test_liveness_probe_body_contains_up() {
	mut ctx := core.new_application_context()

	mut mvc := new_mockmvc()
	mvc.get('/health/liveness', k8s_probe_mock_handler(ctx))

	result := mvc.perform(mock_request('GET', '/health/liveness'))!
	result.assert_body_contains('"UP"')!
}

fn test_liveness_probe_always_200_regardless_of_context_state() {
	// Liveness must return 200 even when the context is not ready —
	// a dead process can't respond, so a response means it's alive.
	mut ctx := core.new_application_context()
	// Context is in .created state (not refreshed)

	mut mvc := new_mockmvc()
	mvc.get('/health/liveness', k8s_probe_mock_handler(ctx))

	result := mvc.perform(mock_request('GET', '/health/liveness'))!
	result.assert_status(200)!
}

// ── MockMvc readiness probe tests ──

fn test_readiness_probe_ready_returns_200() {
	mut ctx := core.new_application_context()
	ctx.refresh()!

	mut mvc := new_mockmvc()
	mvc.get('/health/readiness', k8s_probe_mock_handler(ctx))

	result := mvc.perform(mock_request('GET', '/health/readiness'))!
	result.assert_status(200)!
}

fn test_readiness_probe_not_ready_returns_503() {
	mut ctx := core.new_application_context()
	// Not refreshed — state is .created

	mut mvc := new_mockmvc()
	mvc.get('/health/readiness', k8s_probe_mock_handler(ctx))

	result := mvc.perform(mock_request('GET', '/health/readiness'))!
	result.assert_status(503)!
}

fn test_readiness_probe_ready_content_type_is_json() {
	mut ctx := core.new_application_context()
	ctx.refresh()!

	mut mvc := new_mockmvc()
	mvc.get('/health/readiness', k8s_probe_mock_handler(ctx))

	result := mvc.perform(mock_request('GET', '/health/readiness'))!
	result.assert_header('Content-Type', probe_content_type)!
}

fn test_readiness_probe_not_ready_content_type_is_json() {
	mut ctx := core.new_application_context()

	mut mvc := new_mockmvc()
	mvc.get('/health/readiness', k8s_probe_mock_handler(ctx))

	result := mvc.perform(mock_request('GET', '/health/readiness'))!
	result.assert_header('Content-Type', probe_content_type)!
}

fn test_readiness_probe_ready_body_contains_up() {
	mut ctx := core.new_application_context()
	ctx.refresh()!

	mut mvc := new_mockmvc()
	mvc.get('/health/readiness', k8s_probe_mock_handler(ctx))

	result := mvc.perform(mock_request('GET', '/health/readiness'))!
	result.assert_body_contains('"UP"')!
}

fn test_readiness_probe_not_ready_body_contains_out_of_service() {
	mut ctx := core.new_application_context()

	mut mvc := new_mockmvc()
	mvc.get('/health/readiness', k8s_probe_mock_handler(ctx))

	result := mvc.perform(mock_request('GET', '/health/readiness'))!
	result.assert_body_contains('"OUT_OF_SERVICE"')!
}

// ── MockMvc unknown path test ──

fn test_k8s_probe_unknown_path_returns_404() {
	mut ctx := core.new_application_context()

	mut mvc := new_mockmvc()
	mvc.get('/health/liveness', k8s_probe_mock_handler(ctx))
	mvc.get('/health/readiness', k8s_probe_mock_handler(ctx))

	result := mvc.perform(mock_request('GET', '/health/unknown'))!
	result.assert_not_found()!
}

// ── ApplicationContext.is_readiness_ready() tests ──

fn test_is_readiness_ready_true_when_refreshed() {
	mut ctx := core.new_application_context()
	ctx.refresh()!
	assert ctx.is_readiness_ready() == true
}

fn test_is_readiness_ready_false_when_not_refreshed() {
	mut ctx := core.new_application_context()
	// State is .created
	assert ctx.is_readiness_ready() == false
}

fn test_is_readiness_ready_true_with_running_lifecycle() {
	mut ctx := core.new_application_context()
	ctx.add_smart_lifecycle('AlwaysRunning', &core.SmartLifecycle(&AlwaysRunningLifecycle{
		phase_val: 1
	}))
	ctx.refresh()!
	// After refresh: state is .ready AND lifecycle reports is_running() == true
	assert ctx.is_readiness_ready() == true
}

fn test_is_readiness_ready_false_with_not_running_lifecycle() {
	mut ctx := core.new_application_context()
	ctx.add_smart_lifecycle('NeverRunning', &core.SmartLifecycle(&NeverRunningLifecycle{
		phase_val: 1
	}))
	ctx.refresh()!
	// After refresh: state is .ready BUT lifecycle reports is_running() == false
	assert ctx.is_readiness_ready() == false
}

fn test_is_readiness_ready_false_with_mixed_lifecycles() {
	mut ctx := core.new_application_context()
	ctx.add_smart_lifecycle('AlwaysRunning', &core.SmartLifecycle(&AlwaysRunningLifecycle{
		phase_val: 1
	}))
	ctx.add_smart_lifecycle('NeverRunning', &core.SmartLifecycle(&NeverRunningLifecycle{
		phase_val: 2
	}))
	ctx.refresh()!
	// One running, one not → not ready
	assert ctx.is_readiness_ready() == false
}

fn test_is_readiness_ready_false_after_shutdown() {
	mut ctx := core.new_application_context()
	ctx.refresh()!
	assert ctx.is_readiness_ready() == true

	ctx.shutdown()
	// State is .closed after shutdown
	assert ctx.is_readiness_ready() == false
}

// ── SmartLifecycleManager.all_running() tests ──

fn test_smart_lifecycle_all_running_empty_returns_false() {
	mut mgr := core.new_smart_lifecycle_manager()
	// No beans registered → not ready (nothing has started yet)
	assert mgr.all_running() == false
}

fn test_smart_lifecycle_all_running_true_when_all_running() {
	mut mgr := core.new_smart_lifecycle_manager()
	mgr.register('svc1', &core.SmartLifecycle(&AlwaysRunningLifecycle{
		phase_val: 1
	}))
	mgr.register('svc2', &core.SmartLifecycle(&AlwaysRunningLifecycle{
		phase_val: 2
	}))
	assert mgr.all_running() == true
}

fn test_smart_lifecycle_all_running_false_when_one_not_running() {
	mut mgr := core.new_smart_lifecycle_manager()
	mgr.register('svc1', &core.SmartLifecycle(&AlwaysRunningLifecycle{
		phase_val: 1
	}))
	mgr.register('svc2', &core.SmartLifecycle(&NeverRunningLifecycle{
		phase_val: 2
	}))
	assert mgr.all_running() == false
}

// ── Liveness vs Readiness difference ──

fn test_liveness_vs_readiness_difference_when_not_ready() {
	// When the app is not ready, liveness should still return 200
	// (process is alive) but readiness should return 503 (not ready).
	mut ctx := core.new_application_context()
	// Not refreshed — state is .created

	mut mvc := new_mockmvc()
	mvc.get('/health/liveness', k8s_probe_mock_handler(ctx))
	mvc.get('/health/readiness', k8s_probe_mock_handler(ctx))

	live_result := mvc.perform(mock_request('GET', '/health/liveness'))!
	ready_result := mvc.perform(mock_request('GET', '/health/readiness'))!

	live_result.assert_status(200)!
	ready_result.assert_status(503)!
}

fn test_liveness_vs_readiness_same_when_ready() {
	// When the app is ready, both probes return 200.
	mut ctx := core.new_application_context()
	ctx.refresh()!

	mut mvc := new_mockmvc()
	mvc.get('/health/liveness', k8s_probe_mock_handler(ctx))
	mvc.get('/health/readiness', k8s_probe_mock_handler(ctx))

	live_result := mvc.perform(mock_request('GET', '/health/liveness'))!
	ready_result := mvc.perform(mock_request('GET', '/health/readiness'))!

	live_result.assert_status(200)!
	ready_result.assert_status(200)!
}

fn test_liveness_vs_readiness_difference_with_not_running_lifecycle() {
	// When a SmartLifecycle bean is not running, liveness still returns 200
	// but readiness returns 503.
	mut ctx := core.new_application_context()
	ctx.add_smart_lifecycle('NeverRunning', &core.SmartLifecycle(&NeverRunningLifecycle{
		phase_val: 1
	}))
	ctx.refresh()!

	mut mvc := new_mockmvc()
	mvc.get('/health/liveness', k8s_probe_mock_handler(ctx))
	mvc.get('/health/readiness', k8s_probe_mock_handler(ctx))

	live_result := mvc.perform(mock_request('GET', '/health/liveness'))!
	ready_result := mvc.perform(mock_request('GET', '/health/readiness'))!

	live_result.assert_status(200)!
	ready_result.assert_status(503)!
}

// ── Test helper: SmartLifecycle implementations ──

// AlwaysRunningLifecycle is a SmartLifecycle that always reports is_running() == true.
// Used to simulate a healthy, running background service.
struct AlwaysRunningLifecycle {
pub:
	phase_val int
}

pub fn (al &AlwaysRunningLifecycle) is_running() bool {
	return true
}

pub fn (al &AlwaysRunningLifecycle) start() ! {
	// Already running — no-op
}

pub fn (al &AlwaysRunningLifecycle) stop() ! {
	// No-op for test
}

pub fn (al &AlwaysRunningLifecycle) phase() int {
	return al.phase_val
}

// NeverRunningLifecycle is a SmartLifecycle that always reports is_running() == false.
// Used to simulate a service that hasn't started yet (or failed to start).
// start() is a no-op so is_running() stays false even after refresh().
struct NeverRunningLifecycle {
pub:
	phase_val int
}

pub fn (nl &NeverRunningLifecycle) is_running() bool {
	return false
}

pub fn (nl &NeverRunningLifecycle) start() ! {
	// Intentionally does NOT set running=true — simulates a service
	// that is still initializing or failed to start.
}

pub fn (nl &NeverRunningLifecycle) stop() ! {
	// No-op for test
}

pub fn (nl &NeverRunningLifecycle) phase() int {
	return nl.phase_val
}
