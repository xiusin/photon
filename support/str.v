module support

// str.v - String Helpers (Laravel Str class inspired)
import rand

// is_upper_char checks if a byte is an uppercase ASCII letter
fn is_upper_char(ch u8) bool {
	return ch >= `A` && ch <= `Z`
}

// slug converts a string to a URL-friendly slug.
// Uses a []u8 buffer to avoid O(n²) string concatenation.
pub fn slug(s string) string {
	mut buf := []u8{cap: s.len}
	mut last_was_sep := false
	for ch in s {
		mut c := ch
		// Convert to lowercase on-the-fly (avoid pre-allocating full lowercase string)
		if c >= `A` && c <= `Z` {
			c += 32
		}
		if c.is_letter() || c.is_digit() {
			buf << c
			last_was_sep = false
		} else if c == ` ` || c == `-` || c == `_` || c == `.` {
			if !last_was_sep && buf.len > 0 {
				buf << `-`
				last_was_sep = true
			}
		}
	}
	// Trim trailing hyphens
	mut end := buf.len
	for end > 0 && buf[end - 1] == `-` {
		end--
	}
	return buf[..end].bytestr()
}

// is_lower_char checks if a byte is a lowercase ASCII letter
fn is_lower_char(ch u8) bool {
	return ch >= `a` && ch <= `z`
}

// is_digit_char checks if a byte is an ASCII digit
fn is_digit_char(ch u8) bool {
	return ch >= `0` && ch <= `9`
}

// word_boundary_at reports whether a word boundary must be inserted before
// s[i]. It also splits an acronym run when its last letter starts a new word
// (`HTTPServer` → `HTTP|Server`).
fn word_boundary_at(s string, i int) bool {
	if i == 0 {
		return false
	}
	if is_upper_char(s[i]) {
		if is_lower_char(s[i - 1]) || is_digit_char(s[i - 1]) {
			return true
		}
		if is_upper_char(s[i - 1]) && i + 1 < s.len && is_lower_char(s[i + 1]) {
			return true
		}
	}
	return is_lower_char(s[i]) && is_digit_char(s[i - 1])
}

// snake converts PascalCase or camelCase to snake_case.
//
// Acronyms stay together instead of being exploded one letter at a time:
// `HTTPServer` → `http_server`, `getHTTPResponseCode` → `get_http_response_code`.
// Uses a []u8 buffer to avoid O(n²) string concatenation.
pub fn snake(s string) string {
	if s.len == 0 {
		return ''
	}
	mut buf := []u8{cap: s.len * 2}
	for i, ch in s {
		if word_boundary_at(s, i) {
			buf << `_`
		}
		mut c := ch
		if is_upper_char(c) {
			c += 32
		}
		buf << c
	}
	return buf.bytestr()
}

// camel converts snake_case or kebab-case to camelCase.
// Uses a []u8 buffer to avoid O(n²) string concatenation.
pub fn camel(s string) string {
	if s.len == 0 {
		return ''
	}
	mut buf := []u8{cap: s.len}
	mut next_upper := false
	mut emitted := false
	for ch in s {
		if ch == `_` || ch == `-` {
			next_upper = true
			continue
		}
		mut c := ch
		if !emitted {
			// 分隔符之后的第一个字母才是真正的首字母（`_user` → `user`），
			// 只有它需要强制小写，其余字符保持原样（`HTTPServer` → `HTTPServer`）。
			if c >= `A` && c <= `Z` {
				c += 32
			}
			emitted = true
			next_upper = false
		} else if next_upper {
			if c >= `a` && c <= `z` {
				c -= 32
			}
			next_upper = false
		}
		buf << c
	}
	return buf.bytestr()
}

// studly converts snake_case or kebab-case to PascalCase.
// Uses a []u8 buffer to avoid O(n²) string concatenation.
pub fn studly(s string) string {
	if s.len == 0 {
		return ''
	}
	mut buf := []u8{cap: s.len}
	mut next_upper := true
	for ch in s {
		if ch == `_` || ch == `-` {
			next_upper = true
			continue
		}
		mut c := ch
		if next_upper {
			if c >= `a` && c <= `z` {
				c -= 32
			}
			next_upper = false
		}
		buf << c
	}
	return buf.bytestr()
}

// kebab converts PascalCase or snake_case to kebab-case.
// Uses a []u8 buffer to avoid O(n²) string concatenation.
pub fn kebab(s string) string {
	mut buf := []u8{cap: s.len * 2}
	mut last_was_sep := false
	for i, ch in s {
		if is_upper_char(ch) && (i > 0 || !last_was_sep) {
			if word_boundary_at(s, i) && !last_was_sep {
				buf << `-`
			}
		}
		if ch == `_` || ch == `-` {
			if !last_was_sep && buf.len > 0 {
				buf << `-`
				last_was_sep = true
			}
			continue
		}
		mut c := ch
		if is_upper_char(c) {
			c += 32
		}
		buf << c
		last_was_sep = false
	}
	return buf.bytestr().trim_right('-')
}

// limit truncates a string to n characters and appends "...".
//
// n is the total length of the result, ellipsis included. When n is smaller
// than the ellipsis itself a bare substring is returned (`limit('hello', 3)`
// used to produce `"..."`, i.e. no payload left at all), and a negative n is
// treated as 0 instead of panicking on the slice bounds.
pub fn limit(s string, n int) string {
	if n <= 0 {
		return ''
	}
	if s.len <= n {
		return s
	}
	if n <= 3 {
		return s[..n]
	}
	return s[..n - 3] + '...'
}

// words returns the first n words of a string.
//
// Any whitespace run separates words, and leading/trailing spaces do not
// count as words — previously only `' '` was treated as a separator, so
// `words("a\tb c", 2)` returned the whole string.
pub fn words(s string, n int) string {
	if n <= 0 {
		return ''
	}
	mut count := 0
	mut i := 0
	mut in_word := false
	for i < s.len {
		c := s[i]
		if c == ` ` || c == `\t` || c == `\n` || c == `\r` {
			in_word = false
		} else if !in_word {
			in_word = true
			count++
			if count > n {
				return s[..i].trim_right(' \t\n\r')
			}
		}
		i++
	}
	return s
}

// contains checks if haystack contains needle (case-sensitive)
@[inline]
pub fn contains(haystack string, needle string) bool {
	return haystack.contains(needle)
}

// starts_with checks if s starts with prefix
@[inline]
pub fn starts_with(s string, prefix string) bool {
	return s.starts_with(prefix)
}

// ends_with checks if s ends with suffix
@[inline]
pub fn ends_with(s string, suffix string) bool {
	return s.ends_with(suffix)
}

// after returns the substring after the first occurrence of search
pub fn after(s string, search string) string {
	idx := s.index(search) or { return '' }
	return s[idx + search.len..]
}

// before returns the substring before the first occurrence of search
pub fn before(s string, search string) string {
	idx := s.index(search) or { return s }
	return s[..idx]
}

// between returns the substring between from and to
pub fn between(s string, from string, to string) string {
	start := s.index(from) or { return '' }
	end := s.index_after(to, start + from.len) or { return '' }
	return s[start + from.len..end]
}

// finish ensures the string ends with cap
pub fn finish(s string, cap string) string {
	if s.ends_with(cap) {
		return s
	}
	return s + cap
}

// start_str ensures the string starts with prefix
pub fn start_str(s string, prefix string) string {
	if s.starts_with(prefix) {
		return s
	}
	return prefix + s
}

// replace_first replaces the first occurrence
pub fn replace_first(s string, search string, replace string) string {
	idx := s.index(search) or { return s }
	return s[..idx] + replace + s[idx + search.len..]
}

// replace_last replaces the last occurrence
pub fn replace_last(s string, search string, replace string) string {
	idx := s.last_index(search) or { return s }
	return s[..idx] + replace + s[idx + search.len..]
}

// random_charset is the character set used by random() for alphanumeric generation
const random_charset = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'

// random generates a random alphanumeric string
pub fn random(length int) string {
	mut buf := []u8{cap: length}
	chars_len := random_charset.len
	for _ in 0 .. length {
		idx := rand.intn(chars_len) or { 0 }
		buf << u8(random_charset[idx])
	}
	return buf.bytestr()
}

// mask masks a portion of the string with the given character
pub fn mask(s string, ch string, idx int, length int) string {
	if s.len == 0 {
		return ''
	}
	if idx < 0 || idx >= s.len {
		return s
	}
	mut end := idx + length
	if end > s.len {
		end = s.len
	}

	mut result := s[..idx]
	for _ in 0 .. (end - idx) {
		result += ch
	}
	if end < s.len {
		result += s[end..]
	}
	return result
}

// is_json checks if a string is valid JSON (heuristic)
pub fn is_json(s string) bool {
	trimmed := s.trim_space()
	return (trimmed.starts_with('{') && trimmed.ends_with('}'))
		|| (trimmed.starts_with('[') && trimmed.ends_with(']'))
}

// lower converts to lowercase
@[inline]
pub fn lower(s string) string {
	return s.to_lower()
}

// upper converts to uppercase
@[inline]
pub fn upper(s string) string {
	return s.to_upper()
}

// title converts to Title Case.
// Uses a []u8 buffer to avoid O(n²) string concatenation.
//
// Word separators (`_`, `-`, whitespace) collapse to a single space, and only
// the first letter of each word is forced to uppercase — the rest keeps its
// original case, so `title('HELLO world')` stays `HELLO World` instead of
// silently mangling acronyms.
pub fn title(s string) string {
	mut buf := []u8{cap: s.len}
	mut capitalize := true
	mut prev_sep := false
	for ch in s {
		if ch == ` ` || ch == `_` || ch == `-` || ch == `\t` || ch == `\n` || ch == `\r` {
			if !prev_sep {
				buf << ` `
			}
			prev_sep = true
			capitalize = true
			continue
		}
		prev_sep = false
		mut c := ch
		if capitalize && c >= `a` && c <= `z` {
			c -= 32
		}
		buf << c
		capitalize = false
	}
	return buf.bytestr()
}

// repeat repeats s n times
pub fn repeat_str(s string, n int) string {
	return s.repeat(n)
}

// pad_left_str pads on the left.
// An empty pad cannot grow the string, so it is returned unchanged — looping
// on it would never terminate.
pub fn pad_left_str(s string, length int, pad string) string {
	if s.len >= length || pad.len == 0 {
		return s
	}
	// Repeat first, then slice: appending in a loop grows quadratically when
	// `length` is large.
	needed := length - s.len
	repeats := (needed + pad.len - 1) / pad.len
	return pad.repeat(repeats)[..needed] + s
}

// pad_right_str pads on the right (empty pad returns the input unchanged).
pub fn pad_right_str(s string, length int, pad string) string {
	if s.len >= length || pad.len == 0 {
		return s
	}
	needed := length - s.len
	repeats := (needed + pad.len - 1) / pad.len
	return s + pad.repeat(repeats)[..needed]
}
