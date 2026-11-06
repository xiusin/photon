module cli

// progress.v - ProgressBar for CLI operations

// ProgressBar renders an animated progress indicator like:
//   [=====>      ] 45% 450/1000
//
// 为什么要能「只算不画」
// ----------------------
// 渲染结果原先直接 `print()` 到进程 fd，用例只能断言 `current` 而看不到那行
// 字 —— 于是 `total == 0` 时 `render()` 静默返回（既没有 0% 也没有 100%），
// `forward == total` 时出现 `[====]` 而不是 `[===>]`，全都没人发现。现在渲染
// 拆成纯函数 `render_text()`，`advance`/`set`/`finish` 负责画。
pub struct ProgressBar {
pub:
	total int
pub mut:
	current int
	width   int = 40
}

// new_progress_bar creates a new ProgressBar
pub fn new_progress_bar(total int) &ProgressBar {
	return &ProgressBar{
		total:   total
		current: 0
		width:   40
	}
}

// advance increments the progress bar by n steps
pub fn (mut pb ProgressBar) advance(n int) {
	pb.current += n
	pb.clamp()
	pb.render()
}

// set sets the progress bar to a specific value
pub fn (mut pb ProgressBar) set(value int) {
	pb.current = value
	pb.clamp()
	pb.render()
}

// finish completes the progress bar at 100%
pub fn (mut pb ProgressBar) finish() {
	pb.current = pb.total
	pb.clamp()
	pb.render()
	print('\n')
}

// clamp 把 current 夹进 [0, total]
//
// 下界和上界一样重要：`advance(-5)` 在旧代码里能一路走到负数，接着
// `filled` 变负、空槽循环次数反而变多，最后画出比 width 更长的进度条。
fn (mut pb ProgressBar) clamp() {
	if pb.total <= 0 {
		pb.current = 0
		return
	}
	if pb.current < 0 {
		pb.current = 0
	}
	if pb.current > pb.total {
		pb.current = pb.total
	}
}

// render draws the current progress bar state
fn (pb &ProgressBar) render() {
	print(pb.render_text())
}

// render_text 返回当前进度条的那一行（不含结尾换行）
//
// 空进度（total <= 0）返回 '0%'：旧实现直接 return，什么都不画，调用方看到的是
// 一片空白 —— 和「进度条根本没用起来」长得一模一样。
pub fn (pb &ProgressBar) render_text() string {
	if pb.width <= 0 {
		return '${pb.percentage()}%'
	}
	filled := pb.filled_width()
	mut bar := '\r['
	for _ in 0 .. filled {
		bar += '='
	}
	// 只在还没走完时画箭头，走完后整条都是 '='
	if filled < pb.width {
		bar += '>'
	}
	for _ in 0 .. pb.width - filled - if filled < pb.width { 1 } else { 0 } {
		bar += ' '
	}
	bar += ']'
	return '${bar} ${green_text('${pb.percentage()}%')} ${pb.count_text()}'
}

// percentage 返回 0~100 的整数百分比
//
// 两个坑都在这里：total <= 0 时没有分母（定义成 0%，不抛错也不除零）；
// `cur * 100` 在 total 超过 int 上限 / 100 时会溢出成负数，于是「走完了」被
// 算成 0% —— 用 `大数 * 100 / 大数` 复现过。先判两端，剩下才做乘法。
pub fn (pb &ProgressBar) percentage() int {
	if pb.total <= 0 {
		return 0
	}
	cur := pb.current_clamped()
	if cur <= 0 {
		return 0
	}
	if cur >= pb.total {
		return 100
	}
	return int(u64(cur) * u64(100) / u64(pb.total))
}

// filled_width 返回进度条里已填充的格数
//
// 旧实现用 `cur * width / total`，在 cur 刚好等于 total 时因为 `filled < width`
// 不成立而少画一格箭头，留下的空槽也是对的；但 cur * width 在超大 total 上
// 会溢出。改成先算比例再乘宽度。
pub fn (pb &ProgressBar) filled_width() int {
	if pb.total <= 0 || pb.width <= 0 {
		return 0
	}
	cur := pb.current_clamped()
	if cur >= pb.total {
		return pb.width
	}
	return int(u64(cur) * u64(pb.width) / u64(pb.total))
}

// count_text 返回 'current/total'
pub fn (pb &ProgressBar) count_text() string {
	return '${pb.current_clamped()}/${pb.total}'
}

// current_clamped 返回夹紧后的 current（不修改自身，渲染是只读的）
fn (pb &ProgressBar) current_clamped() int {
	if pb.total <= 0 || pb.current < 0 {
		return 0
	}
	if pb.current > pb.total {
		return pb.total
	}
	return pb.current
}
