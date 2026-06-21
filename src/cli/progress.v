module cli

// progress.v - ProgressBar for CLI operations

// ProgressBar renders an animated progress indicator like:
//   [=====>      ] 45% 450/1000
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
	if pb.current > pb.total {
		pb.current = pb.total
	}
	pb.render()
}

// set sets the progress bar to a specific value
pub fn (mut pb ProgressBar) set(value int) {
	pb.current = value
	if pb.current > pb.total {
		pb.current = pb.total
	}
	pb.render()
}

// finish completes the progress bar at 100%
pub fn (mut pb ProgressBar) finish() {
	pb.current = pb.total
	pb.render()
	print('\n')
}

// render draws the current progress bar state
fn (pb &ProgressBar) render() {
	if pb.total == 0 {
		return
	}

	percentage := pb.current * 100 / pb.total
	filled := pb.current * pb.width / pb.total
	mut empty := pb.width - filled

	mut bar := '\r['
	for _ in 0 .. filled {
		bar += '='
	}
	if filled < pb.width {
		bar += '>'
		empty--
	}
	for _ in 0 .. empty {
		bar += ' '
	}
	bar += ']'

	pct_str := '${percentage}%'
	count_str := '${pb.current}/${pb.total}'

	print('${bar} ${green_text(pct_str)} ${count_str}')
}
