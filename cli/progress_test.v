module cli

// progress_test.v — ProgressBar 的渲染与边界
//
// 旧实现的 `render()` 直接 print 到 fd，唯一的断言手段是看 `current`，
// 于是「走完了却显示 0%」「空进度什么都不画」这两件事一直没人看见。
// 现在渲染是纯函数，输出本身就是被测对象。

// strip_ansi 去掉颜色码，避免断言被终端样式绑架
fn strip_ansi(s string) string {
	mut out := s
	for code in ['\x1b[32m', '\x1b[0m'] {
		out = out.replace(code, '')
	}
	return out
}

fn test_render_text_midway() {
	mut pb := new_progress_bar(100)
	pb.current = 50
	assert strip_ansi(pb.render_text()) == '\r[====================>                   ] 50% 50/100'
}

fn test_render_text_at_total_is_full_bar_without_arrow() {
	// 关键回归：`filled = cur * width / total` 在 cur == total 时正好等于
	// width，旧代码因此少画一格箭头、还多留一格空槽 —— 走完了看到 `[====]`。
	mut pb := new_progress_bar(100)
	pb.current = 100
	text := strip_ansi(pb.render_text())
	assert text.starts_with('\r[========================================]')
	assert !text.contains('>')
	assert text.contains('100%')
	assert text.contains('100/100')
}

fn test_render_text_at_zero() {
	pb := new_progress_bar(100)
	text := strip_ansi(pb.render_text())
	assert text == '\r[>                                       ] 0% 0/100'
}

fn test_render_text_zero_total_still_draws() {
	// 旧实现 `if pb.total == 0 { return }`：空进度什么都不画，
	// 和「根本没调用进度条」在输出上无法区分。
	pb := new_progress_bar(0)
	text := strip_ansi(pb.render_text())
	assert text.contains('0%')
	assert text.contains('0/0')
}

fn test_render_text_negative_total() {
	pb := new_progress_bar(-5)
	text := strip_ansi(pb.render_text())
	assert text.contains('0%')
	assert text.contains('0/-5')
}

fn test_advance_negative_clamps_to_zero() {
	// 旧实现没有下界：advance(-5) 让 current 变负，filled 也变负，
	// 空槽循环次数反而变多 —— 画出的条比 width 还长。
	mut pb := new_progress_bar(100)
	pb.advance(10)
	pb.advance(-30)
	assert pb.current == 0
	assert pb.filled_width() == 0
	// 条形区必须正好是 width 个字符：'[' + 内容 + ']'
	line := strip_ansi(pb.render_text())[1..]
	close := line.index(']') or { -1 }
	// '[' + width 个字符 + ']'
	assert close == pb.width + 1
	assert line[..close + 1].len == pb.width + 2
}

fn test_filled_width_never_exceeds_width() {
	mut pb := new_progress_bar(3)
	pb.width = 7
	for i in 0 .. 4 {
		pb.current = i
		assert pb.filled_width() <= 7
	}
}

fn test_percentage_scales_without_overflow() {
	// 关键回归：`cur * 100` 在 cur 接近 int 上限时溢出成负数，
	// 于是「走完了」被算成 0%。这条在旧代码上会得到 0。
	mut pb := new_progress_bar(2000000000)
	pb.current = 2000000000
	assert pb.percentage() == 100
}

fn test_percentage_rounds_down() {
	mut pb := new_progress_bar(3)
	pb.current = 1
	assert pb.percentage() == 33
	pb.current = 2
	assert pb.percentage() == 66
}

fn test_percentage_zero_total() {
	mut pb := new_progress_bar(0)
	pb.current = 5
	assert pb.percentage() == 0
}

fn test_count_text_uses_clamped_value() {
	mut pb := new_progress_bar(10)
	pb.current = 99
	assert pb.count_text() == '10/10'
	pb.current = -3
	assert pb.count_text() == '0/10'
}

fn test_width_zero_renders_percentage_only() {
	mut pb := new_progress_bar(4)
	pb.width = 0
	pb.current = 2
	text := strip_ansi(pb.render_text())
	assert text == '50%'
	assert !text.contains('[')
}

fn test_set_and_finish_are_equivalent_on_current() {
	mut a := new_progress_bar(10)
	mut b := new_progress_bar(10)
	a.set(7)
	b.advance(7)
	assert a.current == b.current
	assert a.render_text() == b.render_text()
}
