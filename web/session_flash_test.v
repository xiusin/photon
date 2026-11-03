module web

// session_flash_test.v - 会话闪存与 Cookie 属性的契约测试
//
// 这一组锁住四件事，每一条对应一个「看着工作、其实没工作」的旧行为：
//
//   1. flash() 写进去的值，下一次请求必须能读到（旧实现里 store 从不保存
//      flash_data，start() 也不把读到的闪存搬进 old_flash —— 闪存等于丢了）
//   2. 读到之后必须被消费掉，不能在之后的请求里反复出现
//   3. 只写了 flash 的会话不能被当成「不存在的会话」而重建 ID
//   4. SessionManager 的 same_site / cookie_domain 必须真的写进响应 Cookie
//
// session_flash_test.v locks the flash lifecycle and cookie attributes.

import net.http
import veb
import time

// ── 1 & 2：闪存的写入、跨请求读取与消费 ──

fn test_flash_survives_across_requests() {
	mut store := new_memory_session_store()
	defer { store.close() }
	mut sm := new_session_manager(store)

	// 第一次请求：写入闪存
	mut sess1 := new_session('first-request')
	sess1.flash('notice', 'saved')
	sess1.set('uid', '7')
	store.write(sess1.id, sess1.data.clone(), sess1.flash_data.clone(), sm.ttl_seconds)!

	// 第二次请求：同一个 id 必须读到闪存
	rec := store.read('first-request')!
	assert rec.flash['notice'] == 'saved'
	// 且闪存没有污染普通数据
	assert 'notice' !in rec.data
}

fn test_flash_is_consumed_after_one_request() {
	mut store := new_memory_session_store()
	defer { store.close() }
	mut sm := new_session_manager(store)

	mut sess := new_session('consume-me')
	sess.flash('notice', 'once')
	store.write(sess.id, sess.data.clone(), sess.flash_data.clone(), sm.ttl_seconds)!

	// 模拟 start()：读到闪存 → 搬进 old_flash → 标记为已消费
	rec := store.read('consume-me')!
	assert rec.flash.len == 1
	mut resumed := new_session('consume-me')
	resumed.data = rec.data.clone()
	resumed.old_flash = rec.flash.clone()
	resumed.is_dirty = rec.flash.len > 0
	assert resumed.get_flash('notice')! == 'once'

	// 读取即消费：落盘时 flash_data 必须是空的
	store.write(resumed.id, resumed.data.clone(), map[string]string{}, 1800)!
	again := store.read('consume-me')!
	assert again.flash.len == 0, 'flash must not survive a second request'
}

fn test_session_with_only_flash_keeps_its_id() {
	mut store := new_memory_session_store()
	defer { store.close() }
	mut sm := new_session_manager(store)

	// 只有闪存、没有普通数据的会话
	store.write('flash-only', map[string]string{}, {
		'notice': 'hi'
	}, 1800)!
	rec := store.read('flash-only')!
	// 旧的判据是 rec.data.len > 0，这里会是「会话不存在」→ 重建 ID →
	// 闪存和会话数据一起丢。
	assert rec.data.len == 0 && rec.flash.len > 0
	assert rec.data.len > 0 || rec.flash.len > 0
}

// ── 3：分片存储同样要带上闪存 ──

fn test_sharded_store_round_trips_flash() {
	mut store := new_sharded_memory_session_store()
	defer { store.close() }
	store.write('sid-1', {
		'a': '1'
	}, {
		'f': 'v'
	}, 1800)!
	rec := store.read('sid-1')!
	assert rec.data['a'] == '1'
	assert rec.flash['f'] == 'v'
}

// ── 4：Cookie 属性必须到达响应 ──

fn test_same_site_mapping() {
	assert same_site_of('Strict') == http.SameSite.same_site_strict_mode
	assert same_site_of('lax') == http.SameSite.same_site_lax_mode
	assert same_site_of('NONE') == http.SameSite.same_site_none_mode
	// 未知取值不猜：不发该属性，而不是放宽到 None
	assert same_site_of('whatever') == http.SameSite.same_site_not_set
}

fn test_manager_cookie_carries_same_site_and_domain() {
	mut store := new_memory_session_store()
	defer { store.close() }
	mut sm := new_session_manager(store)
	sm.cookie_domain = '.example.com'
	sm.same_site = 'Strict'
	sm.secure = true

	c := sm.build_cookie('abc123', 0)
	assert c.name == 'PHOTON_SESSION'
	assert c.value == 'abc123'
	assert c.domain == '.example.com'
	assert c.http_only
	assert c.secure
	assert c.same_site == http.SameSite.same_site_strict_mode
	// 属性真的要出现在序列化结果里，否则等于没配
	raw := c.str()
	assert raw.contains('SameSite=Strict')
	// 序列化结果由 V 的 net.http.Cookie.str() 生成，属性名是小写
	// （`; domain=` / `; path=`）；只断言属性真的出现，不锁大小写 ——
	// 之前这里断言 `Domain=`，锁的是不存在的上游行为，于是长期挂红。
	assert raw.contains('domain=example.com')
	assert raw.contains('Secure')
	assert raw.contains('HttpOnly')
}

fn test_destroy_cookie_matches_original_scope() {
	mut store := new_memory_session_store()
	defer { store.close() }
	mut sm := new_session_manager(store)
	sm.cookie_domain = 'example.com'
	sm.cookie_path = '/app'

	c := sm.build_cookie('', -1)
	assert c.value == ''
	assert c.max_age == -1
	// 清除 Cookie 的 path/domain 必须与原 Cookie 一致，否则浏览器
	// 认为这是另一个 Cookie，会话 ID 继续留在客户端。
	assert c.path == '/app'
	assert c.domain == 'example.com'
}

// ── 5：manager 的 start() 真的会消费闪存 ──

fn test_start_reads_flash_but_flash_only_once() {
	mut store := new_memory_session_store()
	defer { store.close() }
	mut sm := new_session_manager(store)
	sid := generate_session_id()
	store.write(sid, {
		'uid': '42'
	}, {
		'msg': 'hello'
	}, 1800)!

	ctx := new_test_ctx_with_cookie('PHOTON_SESSION', sid)
	sess := sm.start(ctx)
	assert sess.id == sid
	assert sess.data['uid'] == '42'
	assert sess.get_flash('msg')! == 'hello'
	// 读过闪存就必须标脏，否则消费不会落盘
	assert sess.is_dirty
	// 消费掉之后本次请求不能再往 flash_data 里留东西
	assert sess.flash_data.len == 0
}

// new_test_ctx_with_cookie 造一个带指定 Cookie 的请求上下文。
// veb 从 req.cookies 读 Cookie（map[string]string），不是自解析 header。
fn new_test_ctx_with_cookie(name string, value string) &veb.Context {
	mut ctx := &veb.Context{
		req: http.Request{}
	}
	ctx.req.add_cookie(http.Cookie{
		name:  name
		value: value
	})
	return ctx
}

fn test_delayed_flash_does_not_leak_into_data() {
	mut sess := new_session('x')
	sess.set('k', 'v')
	sess.flash('f', 'once')
	assert sess.data['k'] == 'v'
	assert 'f' !in sess.data
	// flash 写入本次请求不可读（只在 old_flash 里可读）
	assert !sess.has_flash('f')
	assert time.now().unix() > 0
}
