module cli

// format.v - ANSI color and text formatting helpers

// ANSI escape codes
const reset = '\x1b[0m'
const bold = '\x1b[1m'
const dim = '\x1b[2m'
const italic = '\x1b[3m'

// Foreground colors
const black = '\x1b[30m'
const red = '\x1b[31m'
const green = '\x1b[32m'
const yellow = '\x1b[33m'
const blue = '\x1b[34m'
const magenta = '\x1b[35m'
const cyan = '\x1b[36m'
const white = '\x1b[37m'
const gray = '\x1b[90m'

// Background colors
const bg_red = '\x1b[41m'
const bg_green = '\x1b[42m'
const bg_yellow = '\x1b[43m'

// Text styling functions
@[inline]
pub fn bold_text(s string) string {
	return '${bold}${s}${reset}'
}

@[inline]
pub fn dim_text(s string) string {
	return '${dim}${s}${reset}'
}

@[inline]
pub fn red_text(s string) string {
	return '${red}${s}${reset}'
}

@[inline]
pub fn green_text(s string) string {
	return '${green}${s}${reset}'
}

@[inline]
pub fn yellow_text(s string) string {
	return '${yellow}${s}${reset}'
}

@[inline]
pub fn blue_text(s string) string {
	return '${blue}${s}${reset}'
}

@[inline]
pub fn cyan_text(s string) string {
	return '${cyan}${s}${reset}'
}

@[inline]
pub fn magenta_text(s string) string {
	return '${magenta}${s}${reset}'
}

@[inline]
pub fn gray_text(s string) string {
	return '${gray}${s}${reset}'
}

@[inline]
pub fn white_text(s string) string {
	return '${white}${s}${reset}'
}

// Status text helpers
@[inline]
pub fn success_text(s string) string {
	return '${green}${bold}${s}${reset}'
}

@[inline]
pub fn error_text(s string) string {
	return '${red}${bold}${s}${reset}'
}

@[inline]
pub fn warning_text(s string) string {
	return '${yellow}${s}${reset}'
}

@[inline]
pub fn info_text(s string) string {
	return '${cyan}${s}${reset}'
}

// Padding helper
@[inline]
pub fn pad_right(s string, width int) string {
	if s.len >= width {
		return s
	}
	mut result := s
	for result.len < width {
		result += ' '
	}
	return result
}
