module cli

// output.v - CommandOutput — styled output for console commands

// OutputStyle controls output verbosity
pub enum OutputStyle {
	normal
	quiet
	verbose
}

// CommandOutput provides styled output methods for commands
//
// 默认写到标准输出。capture 为 true 时改为收集到 collected_lines —— 命令行
// 程序最难测的部分正是「它到底印了什么」：`println` 直接落进程 fd，用例没法
// 断言。加一个可选的收集器后，`run_args` 这类入口才可能被端到端验证。
pub struct CommandOutput {
pub mut:
	style OutputStyle = .normal
	// capture 为 true 时写入 collected_lines 而不是 stdout
	capture bool
	collected_lines []string
}

// new_output creates a new CommandOutput
pub fn new_output() &CommandOutput {
	return &CommandOutput{}
}

// new_capturing_output creates an output that collects everything in memory
// instead of writing to stdout. Read it back with collected().
pub fn new_capturing_output() &CommandOutput {
	return &CommandOutput{
		capture: true
	}
}

// collected returns everything written so far (only meaningful when capturing)
pub fn (o &CommandOutput) collected() string {
	return o.collected_lines.join('')
}

// emit writes one chunk to stdout or to the capture buffer
fn (mut o CommandOutput) emit(s string) {
	if o.capture {
		o.collected_lines << s
	} else {
		print(s)
	}
}

// emit_line writes one line to stdout or to the capture buffer
fn (mut o CommandOutput) emit_line(s string) {
	if o.capture {
		o.collected_lines << s + '\n'
	} else {
		println(s)
	}
}

// writeln writes a line to stdout
pub fn (mut o CommandOutput) writeln(s string) {
	o.emit_line(s)
}

// write writes text to stdout without newline
pub fn (mut o CommandOutput) write(s string) {
	o.emit(s)
}

// success writes a green success message
pub fn (mut o CommandOutput) success(msg string) {
	if o.style != .quiet {
		o.emit_line('${green}[SUCCESS]${reset} ${msg}')
	}
}

// error writes a red error message
pub fn (mut o CommandOutput) error(msg string) {
	o.emit_line('${red}[ERROR]${reset} ${msg}')
}

// warning writes a yellow warning message
pub fn (mut o CommandOutput) warning(msg string) {
	if o.style != .quiet {
		o.emit_line('${yellow}[WARNING]${reset} ${msg}')
	}
}

// info writes a cyan info message (only in verbose mode)
pub fn (mut o CommandOutput) info(msg string) {
	if o.style == .verbose {
		o.emit_line('${cyan}[INFO]${reset} ${msg}')
	}
}

// title writes a bold title with underline
pub fn (o &CommandOutput) title(msg string) {
	if o.style != .quiet {
		eprintln('')
		eprintln(bold_text(msg))
		eprintln('-'.repeat(msg.len))
	}
}

// section writes a section header
pub fn (o &CommandOutput) section(msg string) {
	if o.style != .quiet {
		eprintln('')
		eprintln(bold_text(msg))
	}
}

// table writes a formatted table
pub fn (o &CommandOutput) table(headers []string, rows [][]string) {
	if o.style == .quiet || headers.len == 0 {
		return
	}

	mut widths := []int{len: headers.len}
	for i, h in headers {
		widths[i] = h.len + 2
	}
	for row in rows {
		for i, cell in row {
			if i < widths.len && cell.len + 2 > widths[i] {
				widths[i] = cell.len + 2
			}
		}
	}

	mut header_line := ''
	for i, h in headers {
		header_line += pad_right(h, widths[i])
	}
	eprintln(bold_text(header_line))

	mut sep_line := ''
	for w in widths {
		sep_line += '-'.repeat(w)
	}
	eprintln(dim_text(sep_line))

	for row in rows {
		mut row_line := ''
		for i, cell in row {
			if i < widths.len {
				row_line += pad_right(cell, widths[i])
			}
		}
		eprintln(row_line)
	}
	eprintln('')
}

// line writes a horizontal line
pub fn (o &CommandOutput) line(length int) {
	if o.style != .quiet {
		eprintln(dim_text('-'.repeat(length)))
	}
}
