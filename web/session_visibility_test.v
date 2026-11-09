module web

import os

// session_visibility_test.v — 读得到的键，写也必须作用得到
//
// 为什么单独一个文件
// ------------------
// `Session` 有两张 map：`data`（普通负载）和 `old_flash`（本请求的闪存收件箱）。
// `get()` / `has()` 两张都看，`delete()` / `clear()` 原先只看 `data`，`all()`
// 也只返回 `data`。于是出现一个很奇怪的状态：某些键「读得到、删不掉」，
// 而且 `all()` 说会话是空的、`get()` 却还能取到值。
//
// 这类缺陷不会让任何返回值变成错的 —— `delete()` 返回成功，`clear()` 返回
// 成功，`all()` 返回一个合法的空 map。坏掉的是「这些操作合起来是否自洽」，
// 而没有断言在看那件事。
//
// 修法是一条规则：**读取方观察到的范围，就是写入方的作用范围。**

// 把会话置成「save() 已经跑完、响应还没生成」的状态：
// 本轮的 flash() 已经搬进 old_flash，flash_data 清空。
fn session_after_save(sess &Session) {
	unsafe {
		mut s := sess
		s.old_flash = s.flash_data.clone()
		s.flash_data = map[string]string{}
	}
}

// ── delete() 必须删掉它读得到的一切 ──

fn test_delete_removes_flash_key_from_inbox() {
	mut sess := new_session('sid')
	sess.set('user_id', '42')
	sess.flash('notice', '保存成功')
	session_after_save(sess)

	// 前提：闪存键此刻是读得到的
	assert sess.has('notice')
	assert sess.get('notice')! == '保存成功'

	sess.delete('notice')

	assert !sess.has('notice'), 'delete() 之后 has() 仍为 true —— 只删了 data'
	assert sess.get('notice') or { '' } == '', 'delete() 之后 get() 仍返回旧闪存'
	assert !sess.has_flash('notice')
	// 普通负载不受影响
	assert sess.get('user_id')! == '42'
}

fn test_delete_missing_key_is_noop() {
	mut sess := new_session('sid')
	sess.set('a', '1')
	sess.delete('never-existed')
	assert sess.get('a')! == '1'
}

// ── clear() 的「全部」就是读取方观察到的全部 ──

fn test_clear_empties_flash_inbox() {
	mut sess := new_session('sid')
	sess.set('user_id', '42')
	sess.flash('notice', '保存成功')
	session_after_save(sess)

	sess.clear()

	assert sess.data.len == 0
	assert !sess.has('notice'), 'clear() 之后闪存键仍可读'
	assert sess.get('notice') or { '' } == ''
	assert sess.all().len == 0, 'clear() 之后 all() 仍非空'
	assert sess.is_dirty
}

fn test_clear_drops_pending_flash_too() {
	// flash_data 里待落盘的闪存也是会话数据 —— clear() 之后不该再写进存储
	mut sess := new_session('sid')
	sess.flash('notice', '待落盘')
	assert sess.flash_data.len == 1

	sess.clear()

	assert sess.flash_data.len == 0, 'clear() 之后待落盘的闪存仍会写进存储'
}

// ── all() 与 get()/has() 必须自洽 ──

fn test_all_agrees_with_get_and_has() {
	mut sess := new_session('sid')
	sess.set('user_id', '42')
	sess.old_flash['notice'] = '保存成功'

	all := sess.all()

	// all() 里有的，get() 必须取得到
	for key, val in all {
		assert sess.has(key), 'all() 返回了 ${key}，但 has() 说没有'
		assert sess.get(key)! == val
	}
	// get() 取得到的，all() 里必须有
	for key in ['user_id', 'notice'] {
		assert key in all, 'get() 能取到 ${key}，但 all() 里没有'
	}
}

fn test_all_prefers_data_when_key_in_both() {
	mut sess := new_session('sid')
	sess.data['k'] = 'from-data'
	sess.old_flash['k'] = 'from-flash'
	assert sess.all()['k'] == 'from-data', 'all() 与 get() 对同名键取值不一致'
	assert sess.get('k')! == 'from-data'
}

// ── 结构断言：读写的可见范围写在同一个地方 ──
//
// 行为用例覆盖不了「将来有人又给 Session 加第三张 map」这件事。
// 这条断言直接读源码，要求 delete() / clear() / all() 都提到 old_flash ——
// 少一处就会红，并在报错里点名是哪个函数。

fn test_session_read_write_surfaces_stay_aligned() {
	src := 'web/session.v'
	content := read_source_or_empty(src)
	if content.len == 0 {
		assert false, 'cannot read ${src}; run tests from the repository root (sh scripts/run-tests.sh)'
	}
	for fname in ['delete', 'clear', 'all', 'get', 'has'] {
		mut idx := content.index('fn (s &Session) ${fname}(') or { -1 }
		if idx < 0 {
			idx = content.index('fn (mut s Session) ${fname}(') or { -1 }
		}
		if idx < 0 {
			assert false, 'session.v 里找不到函数 ${fname}'
			return
		}
		body := content[idx..].all_before('\n}')
		assert body.contains('old_flash'),
			'${fname}() 没有涉及 old_flash —— 读取方与写入方的可见范围又开始分叉了'
	}
}

// read_source_or_empty 读源码文件，失败返回空串 —— 由调用方断言报错，
// 不在这里静默吞掉。
fn read_source_or_empty(path string) string {
	return os.read_file(path) or { '' }
}
