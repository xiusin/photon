module cli

// output.v - CommandOutput — styled output for console commands

// OutputStyle controls output verbosity
pub enum OutputStyle {
	normal
	quiet
	verbose
}

// CommandOutput provides styled output methods for commands
pub struct CommandOutput {
pub mut:
	style OutputStyle = .normal
}

// new_output creates a new CommandOutput
pub fn new_output() &CommandOutput {
	return &CommandOutput{}
}

// writeln writes a line to stdout
pub fn (o &CommandOutput) writeln(s string) {
	eprintln(s)
}

// write writes text to stdout without newline
pub fn (o &CommandOutput) write(s string) {
	eprint(s)
}

// success writes a green success message
pub fn (o &CommandOutput) success(msg string) {
	if o.style != .quiet {
		eprintln('${green}[SUCCESS]${reset} ${msg}')
	}
}

// error writes a red error message
pub fn (o &CommandOutput) error(msg string) {
	eprintln('${red}[ERROR]${reset} ${msg}')
}

// warning writes a yellow warning message
pub fn (o &CommandOutput) warning(msg string) {
	if o.style != .quiet {
		eprintln('${yellow}[WARNING]${reset} ${msg}')
	}
}

// info writes a cyan info message (only in verbose mode)
pub fn (o &CommandOutput) info(msg string) {
	if o.style == .verbose {
		eprintln('${cyan}[INFO]${reset} ${msg}')
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
