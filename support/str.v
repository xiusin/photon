module support

// str.v - String Helpers (Laravel Str class inspired)

import rand

// is_upper_char checks if a byte is an uppercase ASCII letter
fn is_upper_char(ch u8) bool {
	return ch >= `A` && ch <= `Z`
}

// slug converts a string to a URL-friendly slug
pub fn slug(s string) string {
	mut result := ''
	mut last_was_sep := false
	for ch in s.to_lower() {
		if ch.is_letter() || ch.is_digit() {
			result += ch.ascii_str()
			last_was_sep = false
		} else if ch == ` ` || ch == `-` || ch == `_` || ch == `.` {
			if !last_was_sep && result.len > 0 {
				result += '-'
				last_was_sep = true
			}
		}
	}
	return result.trim_right('-')
}

// snake converts PascalCase or camelCase to snake_case
pub fn snake(s string) string {
	if s.len == 0 {
		return ''
	}
	mut result := ''
	for i, ch in s {
		if is_upper_char(ch) && i > 0 {
			result += '_'
		}
		result += ch.ascii_str().to_lower()
	}
	return result
}

// camel converts snake_case or kebab-case to camelCase
pub fn camel(s string) string {
	if s.len == 0 {
		return ''
	}
	mut result := ''
	mut next_upper := false
	for i, ch in s {
		if ch == `_` || ch == `-` {
			next_upper = true
			continue
		}
		if i == 0 {
			result += ch.ascii_str().to_lower()
		} else if next_upper {
			result += ch.ascii_str().to_upper()
			next_upper = false
		} else {
			result += ch.ascii_str()
		}
	}
	return result
}

// studly converts snake_case or kebab-case to PascalCase
pub fn studly(s string) string {
	if s.len == 0 {
		return ''
	}
	mut result := ''
	mut next_upper := true
	for ch in s {
		if ch == `_` || ch == `-` {
			next_upper = true
			continue
		}
		if next_upper {
			result += ch.ascii_str().to_upper()
			next_upper = false
		} else {
			result += ch.ascii_str()
		}
	}
	return result
}

// kebab converts PascalCase or snake_case to kebab-case
pub fn kebab(s string) string {
	mut result := ''
	mut last_was_sep := false
	for i, ch in s {
		mut cs := ch.ascii_str()
		if is_upper_char(ch) && i > 0 {
			if !last_was_sep {
				result += '-'
			}
			cs = cs.to_lower()
		}
		if ch == `_` || ch == `-` {
			if !last_was_sep && result.len > 0 {
				result += '-'
				last_was_sep = true
			}
			continue
		}
		result += cs.to_lower()
		last_was_sep = false
	}
	return result.trim_right('-')
}

// limit truncates a string to n characters and appends "..."
pub fn limit(s string, n int) string {
	if s.len <= n {
		return s
	}
	if n < 3 {
		return s[..n]
	}
	return s[..n - 3] + '...'
}

// words returns the first n words of a string
pub fn words(s string, n int) string {
	if n <= 0 {
		return ''
	}
	mut count := 0
	mut i := 0
	for i < s.len {
		if s[i] == ` ` {
			count++
			if count >= n {
				return s[..i]
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

// random generates a random alphanumeric string
pub fn random(length int) string {
	chars := 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
	mut result := ''
	for _ in 0 .. length {
		idx := rand.intn(chars.len) or { 0 }
		result += chars[idx].ascii_str()
	}
	return result
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
	return (trimmed.starts_with('{') && trimmed.ends_with('}')) ||
		(trimmed.starts_with('[') && trimmed.ends_with(']'))
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

// title converts to Title Case
pub fn title(s string) string {
	mut result := ''
	mut capitalize := true
	for ch in s {
		if ch == ` ` || ch == `_` || ch == `-` {
			result += ' '
			capitalize = true
		} else if capitalize {
			result += ch.ascii_str().to_upper()
			capitalize = false
		} else {
			result += ch.ascii_str()
		}
	}
	return result
}

// repeat repeats s n times
pub fn repeat_str(s string, n int) string {
	return s.repeat(n)
}

// pad_left pads on the left
pub fn pad_left_str(s string, length int, pad string) string {
	if s.len >= length {
		return s
	}
	mut result := ''
	for result.len + s.len < length {
		result += pad
	}
	return result + s
}

// pad_right_str pads on the right
pub fn pad_right_str(s string, length int, pad string) string {
	if s.len >= length {
		return s
	}
	mut result := s
	for result.len < length {
		result += pad
	}
	return result
}
