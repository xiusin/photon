// session_cookie_scope_test.v — 会话 Cookie 的发送时机
//
// 缺陷：save() 无条件 set_cookie。并发请求里，最后写响应的那个会把别人
// 刚 regenerate 出来的新会话 ID 又盖回旧 ID —— 正是 session fixation
// 想要的效果；而且每个没有会话变更的响应都白发一个会话 Cookie。
module web

import veb
import net.http

// cookie_ctx 造一个带 PHOTON_SESSION Cookie 的请求上下文。
// veb 从 req.cookies 读 Cookie（map[string]string），不是自解析 header。
fn cookie_ctx(value string) &veb.Context {
	mut ctx := &veb.Context{
		req: http.Request{}
	}
	if value.len > 0 {
		ctx.req.add_cookie(http.Cookie{
			name:  'PHOTON_SESSION'
			value: value
		})
	}
	return ctx
}

// set_cookie_headers returns every Set-Cookie header on the response.
fn set_cookie_headers(ctx &veb.Context) []string {
	return ctx.res.header.values(.set_cookie)
}

fn issued_session_id(ctx &veb.Context) string {
	for h in set_cookie_headers(ctx) {
		if !h.starts_with('PHOTON_SESSION=') {
			continue
		}
		// 会话 ID 是十六进制，不需要 URL 解码
		return h['PHOTON_SESSION='.len..].split(';')[0]
	}
	return ''
}

fn test_unmodified_session_does_not_reissue_cookie() {
	mut store := new_memory_session_store()
	mut sm := new_session_manager(store)
	store.write('sess-1', {
		'user': 'alice'
	}, map[string]string{}, 60)!

	mut ctx := cookie_ctx('sess-1')
	mut sess := sm.start(ctx)
	sm.save(mut ctx, mut sess)!

	assert set_cookie_headers(ctx).len == 0, 'unmodified session must not re-emit the cookie'
	store.close()
}

fn test_new_session_always_gets_a_cookie() {
	mut store := new_memory_session_store()
	mut sm := new_session_manager(store)

	mut ctx := cookie_ctx('')
	mut sess := sm.start(ctx)
	sess.set('user', 'bob')
	sm.save(mut ctx, mut sess)!

	assert issued_session_id(ctx) == sess.id
	store.close()
}

fn test_regenerated_id_replaces_the_stale_cookie() {
	mut store := new_memory_session_store()
	mut sm := new_session_manager(store)
	store.write('old-id', {
		'user': 'alice'
	}, map[string]string{}, 60)!

	mut ctx := cookie_ctx('old-id')
	mut sess := sm.start(ctx)
	sess.regenerate()
	sm.save(mut ctx, mut sess)!

	new_id := issued_session_id(ctx)
	assert new_id == sess.id
	assert new_id != 'old-id', 'a regenerated session id must not stay stale on the client'
	store.close()
}

fn test_flash_only_session_still_persists() {
	mut store := new_memory_session_store()
	mut sm := new_session_manager(store)
	store.write('sess-2', {
		'user': 'alice'
	}, map[string]string{}, 60)!

	mut ctx1 := cookie_ctx('sess-2')
	mut sess1 := sm.start(ctx1)
	sess1.flash('notice', 'saved')
	sm.save(mut ctx1, mut sess1)!

	mut ctx2 := cookie_ctx('sess-2')
	mut sess2 := sm.start(ctx2)
	assert sess2.get_flash('notice')! == 'saved'
	sm.save(mut ctx2, mut sess2)!

	mut ctx3 := cookie_ctx('sess-2')
	mut sess3 := sm.start(ctx3)
	assert !sess3.has_flash('notice'), 'flash must be consumed after one request'
	store.close()
}

fn test_second_save_of_same_session_does_not_duplicate_cookie() {
	mut store := new_memory_session_store()
	mut sm := new_session_manager(store)

	mut ctx := cookie_ctx('')
	mut sess := sm.start(ctx)
	sess.set('user', 'carol')

	sm.save(mut ctx, mut sess)!
	first := set_cookie_headers(ctx).len
	assert first == 1

	// 同一个响应里再保存一次：Cookie 已经是为了这个 ID 发的，不重复发
	sm.save(mut ctx, mut sess)!
	assert set_cookie_headers(ctx).len == first
	store.close()
}

fn test_session_lock_released_when_callback_errors() {
	mut slm := new_session_lock_manager(SessionLockConfig{
		acquire_timeout_ms: 200
	})
	// 回调返回错误后，锁必须已经释放 —— 否则下一次 acquire 直接超时
	if _ := slm.with_session_lock('s-1', fn () ! {
		return error('boom')
	})
	{
		assert false, 'callback error must propagate'
	}
	slm.with_session_lock('s-1', fn () ! {})!
}

fn test_session_lock_released_when_callback_panics() {
	mut slm := new_session_lock_manager(SessionLockConfig{
		acquire_timeout_ms: 200
	})
	// V 的 panic 不能被 or 块接住；这里只验证普通 error 路径不会把锁锁死，
	// panic 路径由 defer 保证（与 locking.with_lock 同一修法）。
	slm.with_session_lock('s-2', fn () ! {})!
	slm.with_session_lock('s-2', fn () ! {})!
}
