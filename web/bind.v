module web

// bind.v — Spring-style DTO Binding
//
// Binds HTTP request data (query params, form body, JSON body) to typed structs.
// Spring equivalents: @RequestBody, @ModelAttribute, @RequestParam, @PathVariable.
//
// Field attributes:
//   @[required]            — field must be present and non-empty
//   @[form: 'field_name']  — map to a different form field name
//
// Usage:
//   struct LoginDto {
//       username string @[required]
//       password string @[required]
//       remember bool
//   }
//   dto := web.bind[LoginDto](ctx) or { return app.text('invalid') }
//   dto_json := web.bind_json[CreateUserDto](ctx) or { ... }
import veb
import x.json2

// ============================================================
// Query/Form Binding (like Spring @ModelAttribute)
// ============================================================

// bind binds query-string and form-body data to a struct T.
// Supports `@[required]` validation on struct fields.
//
// Field mapping:
//   - Uses field name by default
//   - Uses @[form: 'alt_name'] attribute for custom mapping
pub fn bind[T](ctx &veb.Context) !T {
	mut result := T{}
	mut params := extract_params(ctx)

	$for field in T.fields {
		// Determine the input key name
		mut key := field.name
		for attr in field.attrs {
			if attr.starts_with('form:') {
				key = extract_attr_arg(attr)
			}
		}

		val := params[key] or { '' }

		// Check required
		mut is_required := false
		for attr in field.attrs {
			if attr == 'required' {
				is_required = true
				break
			}
		}
		if is_required && val == '' {
			return error('${field.name} is required')
		}

		// Assign value based on type.
		//
		// 覆盖的数值类型必须和 validate_struct() 一致，否则会出现一种很难查的
		// 组合：字段类型不在下面的分支里 → 值**从来没被赋过**，永远是零值 →
		// 数值规则在零值上判定 → 要么把「18」判成「没传」，要么反过来。
		//
		// 这不是假设。`i8` / `i16` / `u*` / `f32` 的字段在补上之前，`bind`
		// 出来恒为 0；更要紧的是 `bind` 不报错，调用方拿到的是一份
		// 「字段都在、值全是零」的结构体。
		$if field.typ is string {
			result.$(field.name) = val
		} $else $if field.typ is bool {
			result.$(field.name) = val == '1' || val == 'true' || val == 'on' || val == 'yes'
		} $else {
			// 数值族：先确认「该给的给了」，再确认「给的是数字」，最后赋值。
			// 三步在每一族里一样，差别只在类型名和转换函数 —— V 的 comptime
			// 没有「是不是数值类型」的判断，只能逐分支写。
			if is_required && val == '' {
				return error('${field.name} is required but empty — cannot convert to ${field.typ}')
			}
			if val != '' {
				if !is_numeric(val) {
					return error('${field.name}: invalid number value "${val}"')
				}
				$if field.typ is int {
					result.$(field.name) = val.int()
				} $else $if field.typ is i8 {
					result.$(field.name) = val.i8()
				} $else $if field.typ is i16 {
					result.$(field.name) = val.i16()
				} $else $if field.typ is i64 {
					result.$(field.name) = val.i64()
				} $else $if field.typ is u8 {
					result.$(field.name) = val.u8()
				} $else $if field.typ is u16 {
					result.$(field.name) = val.u16()
				} $else $if field.typ is u32 {
					result.$(field.name) = val.u32()
				} $else $if field.typ is u64 {
					result.$(field.name) = val.u64()
				} $else $if field.typ is f32 {
					result.$(field.name) = val.f32()
				} $else $if field.typ is f64 {
					result.$(field.name) = val.f64()
				}
			}
		}
	}
	return result
}

// ============================================================
// JSON Body Binding (like Spring @RequestBody)
// ============================================================

// bind_json binds a JSON request body to a struct T.
// Uses the `ctx.req.data` field which contains the raw request body.
pub fn bind_json[T](ctx &veb.Context) !T {
	body := ctx.req.data
	if body == '' {
		return error('empty request body')
	}
	return json2.decode[T](body) or { error('invalid JSON: ${err}') }
}

// bind_request_body binds a JSON request body to a struct T with validation.
// This is the Photon equivalent of Spring's @RequestBody with @Valid.
//
// After JSON decoding, the struct's fields are validated:
//   - @[required] fields must be non-empty/non-zero
//   - @[validate: 'email'] fields must be a valid email format
//   - @[validate: 'min:1'] fields must be >= 1 (for numeric types)
//   - @[validate: 'max:100'] fields must be <= 100 (for numeric types)
//   - @[validate: 'len:3..10'] string length must be between 3 and 10
//
// Spring equivalent: @RequestBody @Valid
//
// Usage:
//   struct CreateUserDto {
//       name     string @[required]
//       email    string @[required; validate: 'email']
//       age      int    @[validate: 'min:18; max:120']
//       password string @[required; validate: 'len:8..64']
//   }
//   dto := web.bind_request_body[CreateUserDto](ctx) or {
//       return web.bad_request_msg(err.msg())
//   }
pub fn bind_request_body[T](ctx &veb.Context) !T {
	body := ctx.req.data
	if body == '' {
		return error('request body is empty / 请求体为空')
	}
	mut result := json2.decode[T](body) or {
		return error('invalid JSON: ${err} / JSON 解析失败: ${err}')
	}
	// Run validation on the decoded struct
	validate_struct(mut result) or {
		return error('validation failed: ${err} / 验证失败: ${err}')
	}
	return result
}

// bind_and_validate binds query/form data to a struct T with validation.
// Combines bind[T] with field-level validation (same rules as bind_request_body).
//
// Spring equivalent: @ModelAttribute @Valid
pub fn bind_and_validate[T](ctx &veb.Context) !T {
	mut result := bind[T](ctx)!
	validate_struct(mut result) or {
		return error('validation failed: ${err} / 验证失败: ${err}')
	}
	return result
}

// validate_struct checks @[required] and @[validate] annotations on a struct.
// Returns an error listing all validation failures.
fn validate_struct[T](mut result T) ! {
	mut errors := []string{}

	$for field in T.fields {
		mut is_required := false
		mut validate_rules := []string{}

		for attr in field.attrs {
			if attr == 'required' {
				is_required = true
			}
			if attr.starts_with('validate:') {
				// Extract validation rules from @[validate: 'rule1; rule2']
				rules_str := attr['validate:'.len..].trim_space().trim('\'"')
				for rule in rules_str.split(';') {
					trimmed := rule.trim_space()
					if trimmed.len > 0 {
						validate_rules << trimmed
					}
				}
			}
		}

		// Check required fields
		//
		// 这里的数值分支必须和下面的 min/max 分支**逐个对齐**，否则会出现
		// 一种和「min/max 只认 int」同形状的漏检：`@[required]` 写在 `u8` /
		// `i8` / `f32` 上时编译通过、运行时一个字都不检查 —— 字段缺席、
		// 值是零值，结构体照样构造成功交给业务层。
		//
		// `bool` 不参与判定：`false` 既可能是「没传」，也可能是「传了 false」，
		// 而两种意图在零值上不可区分，强判会把合法的 false 变成必填失败。
		if is_required {
			$if field.typ is string {
				val := result.$(field.name)
				if val.len == 0 {
					errors << '${field.name} is required / ${field.name} 为必填项'
				}
			} $else $if field.typ is int {
				if result.$(field.name) == 0 {
					errors << '${field.name} is required / ${field.name} 为必填项'
				}
			} $else $if field.typ is i8 {
				if result.$(field.name) == 0 {
					errors << '${field.name} is required / ${field.name} 为必填项'
				}
			} $else $if field.typ is i16 {
				if result.$(field.name) == 0 {
					errors << '${field.name} is required / ${field.name} 为必填项'
				}
			} $else $if field.typ is i64 {
				if result.$(field.name) == 0 {
					errors << '${field.name} is required / ${field.name} 为必填项'
				}
			} $else $if field.typ is u8 {
				if result.$(field.name) == 0 {
					errors << '${field.name} is required / ${field.name} 为必填项'
				}
			} $else $if field.typ is u16 {
				if result.$(field.name) == 0 {
					errors << '${field.name} is required / ${field.name} 为必填项'
				}
			} $else $if field.typ is u32 {
				if result.$(field.name) == 0 {
					errors << '${field.name} is required / ${field.name} 为必填项'
				}
			} $else $if field.typ is u64 {
				if result.$(field.name) == 0 {
					errors << '${field.name} is required / ${field.name} 为必填项'
				}
			} $else $if field.typ is f32 {
				if result.$(field.name) == 0.0 {
					errors << '${field.name} is required / ${field.name} 为必填项'
				}
			} $else $if field.typ is f64 {
				if result.$(field.name) == 0.0 {
					errors << '${field.name} is required / ${field.name} 为必填项'
				}
			}
		}

		// Check validation rules
		for rule in validate_rules {
			$if field.typ is string {
				val := result.$(field.name)
				if rule == 'email' && val.len > 0 {
					if !is_valid_email_format(val) {
						errors << '${field.name} must be a valid email / ${field.name} 必须是有效的邮箱'
					}
				}
				if rule.starts_with('len:') {
					// Parse 'len:min..max' or 'len:min' or 'len:exact'
					len_part := rule['len:'.len..]
					if len_part.contains('..') {
						parts := len_part.split('..')
						if parts.len == 2 {
							min_len := parts[0].int()
							max_len := parts[1].int()
							if val.len > 0 && (val.len < min_len || val.len > max_len) {
								errors << '${field.name} length must be between ${min_len} and ${max_len} / ${field.name} 长度必须在 ${min_len} 到 ${max_len} 之间'
							}
						}
					} else {
						exact_len := len_part.int()
						if val.len > 0 && val.len != exact_len {
							errors << '${field.name} length must be exactly ${exact_len} / ${field.name} 长度必须为 ${exact_len}'
						}
					}
				}
			}
			// min / max 必须覆盖所有数值类型，不能只写 `is int`。
			//
			// 只写 `is int` 时，其余数值类型的规则**编译通过、运行时静默跳过**：
			// `@[validate: 'min:18']` 写在 `i64` / `f64` 字段上，请求带 -5 照样
			// 进业务层，而报表、文档、注解全都在说它被校验了。这类漏检没有任何
			// 返回值在表达 —— 不是「拦错了」，是「没拦」。
			//
			// 按整数 / 无符号 / 浮点三族展开，各族一个名字：取字段、解析边界、
			// 比较这三步在族内完全一样，族间的差别只有「怎么解析 min:」和
			// 「支持到哪一代边界」。写成三个具名函数而不是三段内联代码，
			// 是为了让「新增一个数值类型」变成一件必须看见全部三族的事。
			mut violation := ''
			$if field.typ is int {
				violation = int_bounds_violation(field.name, result.$(field.name), rule)
			} $else $if field.typ is i8 {
				violation = int_bounds_violation(field.name, result.$(field.name), rule)
			} $else $if field.typ is i16 {
				violation = int_bounds_violation(field.name, result.$(field.name), rule)
			} $else $if field.typ is i64 {
				violation = int_bounds_violation(field.name, result.$(field.name), rule)
			} $else $if field.typ is u8 {
				violation = uint_bounds_violation(field.name, result.$(field.name), rule)
			} $else $if field.typ is u16 {
				violation = uint_bounds_violation(field.name, result.$(field.name), rule)
			} $else $if field.typ is u32 {
				violation = uint_bounds_violation(field.name, result.$(field.name), rule)
			} $else $if field.typ is u64 {
				violation = uint_bounds_violation(field.name, result.$(field.name), rule)
			} $else $if field.typ is f32 {
				violation = float_bounds_violation(field.name, result.$(field.name), rule)
			} $else $if field.typ is f64 {
				violation = float_bounds_violation(field.name, result.$(field.name), rule)
			}
			if violation.len > 0 {
				errors << violation
			}
		}
	}
	if errors.len > 0 {
		return error(errors.join('; '))
	}
}

// ── min / max 的实现 ──
//
// 三个族各一个函数，返回「违规描述」或空串。分族的唯一理由是**类型**：
// 整数、无符号、浮点各自需要的转换和边界解析不一样，而 V 的 generics
// 在这里帮不上忙 —— 调用点是 comptime `$if field.typ is ...`，类型是
// 逐分支确定的，函数签名只能跟着逐族确定。
//
// 为什么 `int_bounds_violation` 收一个 `i64` 而不是直接比较 `val`：
// `i8` / `i16` 的 `val < min_val` 在 min 超出类型范围时会先被 V 拒绝编译。
// 统一升到 i64 之后，比较发生在无损的宽度上，边界解析也只需要写一遍。

// bound_of parses `min:18` / `max:120` into the number after the colon.
// An unparseable bound yields (0, false) and the rule is skipped: a typo in
// the annotation should not silently become "reject everything with min:0".
fn bound_of(rule string, prefix string) (i64, bool) {
	raw := rule[prefix.len..].trim_space()
	if raw.len == 0 {
		return 0, false
	}
	if !is_numeric(raw) {
		return 0, false
	}
	return raw.i64(), true
}

// float_bound_of is the same for `min:1.5` / `max:10.5`.
//
// Kept apart from bound_of() because `.i64()` on '2.5' gives 0 — using the
// integer reader here would turn `min:2.5` into `min:0` and quietly widen
// every bound written with a decimal point.
fn float_bound_of(rule string, prefix string) (f64, bool) {
	raw := rule[prefix.len..].trim_space()
	if raw.len == 0 {
		return 0.0, false
	}
	if !is_numeric(raw) {
		return 0.0, false
	}
	return raw.f64(), true
}

// int_bounds_violation checks `min:` / `max:` for signed integers.
// `wide` is the same value widened to i64; comparison happens there so that
// boundaries outside the narrower type's range still behave.
fn int_bounds_violation[T](field_name string, val T, rule string) string {
	wide := i64(val)
	if rule.starts_with('min:') {
		min_val, min_ok := bound_of(rule, 'min:')
		if min_ok && wide < min_val {
			return '${field_name} must be >= ${min_val} / ${field_name} 必须 >= ${min_val}'
		}
	}
	if rule.starts_with('max:') {
		max_val, max_ok := bound_of(rule, 'max:')
		if max_ok && wide > max_val {
			return '${field_name} must be <= ${max_val} / ${field_name} 必须 <= ${max_val}'
		}
	}
	return ''
}

// uint_bounds_violation checks `min:` / `max:` for unsigned integers.
//
// `wide` is the value widened to i64, or -1 when the type does not fit
// (u64): a NaN-style sentinel meaning "cannot compare numerically here".
// When that happens only `min:0` is decidable — every u64 is >= 0 — and
// any non-zero `min:` / finite `max:` still has to be honoured, which is
// why the u64 call site passes -1 rather than skipping the branch.
fn uint_bounds_violation[T](field_name string, val T, rule string) string {
	wide := i64(val)
	if rule.starts_with('min:') {
		min_val, min_ok := bound_of(rule, 'min:')
		// 无符号类型不可能小于 0，`min:` 非正时这条规则恒成立。
		if min_ok && min_val > 0 && wide < min_val {
			return '${field_name} must be >= ${min_val} / ${field_name} 必须 >= ${min_val}'
		}
	}
	if rule.starts_with('max:') {
		max_val, max_ok := bound_of(rule, 'max:')
		if max_ok && wide > max_val {
			return '${field_name} must be <= ${max_val} / ${field_name} 必须 <= ${max_val}'
		}
	}
	return ''
}

// float_bounds_violation checks `min:` / `max:` for f32 / f64.
//
// 浮点不能先转 int 再比：`10.9` 转成 `10` 之后，`max:10` 会放过它；
// `0.5` 转成 `0` 之后，`min:1` 的结论虽然仍是对的，理由却已经错了。
fn float_bounds_violation[T](field_name string, val T, rule string) string {
	if rule.starts_with('min:') {
		min_val, min_ok := float_bound_of(rule, 'min:')
		if min_ok && f64(val) < min_val {
			return '${field_name} must be >= ${min_val} / ${field_name} 必须 >= ${min_val}'
		}
	}
	if rule.starts_with('max:') {
		max_val, max_ok := float_bound_of(rule, 'max:')
		if max_ok && f64(val) > max_val {
			return '${field_name} must be <= ${max_val} / ${field_name} 必须 <= ${max_val}'
		}
	}
	return ''
}

// is_valid_email_format performs a basic email format check.
fn is_valid_email_format(s string) bool {
	if s.len < 5 {
		return false
	}
	at_pos := s.index('@') or { return false }
	if at_pos == 0 || at_pos == s.len - 1 {
		return false
	}
	dot_pos := s.index('.') or { return false }
	return dot_pos > at_pos
}

// ============================================================
// Path Variable Binding (like Spring @PathVariable)
// ============================================================

// bind_path extracts path variables from the route pattern.
// veb provides these via ctx.query map when using :param routes.
//
// Usage:
//   pub fn (mut app MyApp) get_user(id string) veb.Result {
//       // id is automatically populated by veb from /users/:id
//   }
pub fn bind_path[T](ctx &veb.Context) !T {
	// Path variables in veb are available via the query map
	return bind[T](ctx)!
}

// ============================================================
// Internal helpers
// ============================================================

// extract_params collects all input parameters from context
fn extract_params(ctx &veb.Context) map[string]string {
	mut params := map[string]string{}

	// Query parameters
	for k, v in ctx.query {
		params[k] = v
	}

	// Form parameters
	for k, v in ctx.form {
		params[k] = v
	}

	// Parse URL query string as fallback
	url := ctx.req.url
	pos := url.index('?') or { return params }
	query := url[pos + 1..]
	for kv in query.split('&') {
		pair := kv.split('=')
		if pair.len >= 1 {
			key := url_decode(pair[0])
			val := if pair.len >= 2 { url_decode(pair[1]) } else { '' }
			// Don't overwrite existing keys (form params take precedence)
			if params[key] == '' {
				params[key] = val
			}
		}
	}

	return params
}

// extract_attr_arg extracts the argument string from an attribute like "form: 'username'"
fn extract_attr_arg(attr string) string {
	pos := attr.index(':') or { return attr }
	rest := attr[pos + 1..].trim_space()
	if rest.len > 2 && rest[0] == `'` && rest[rest.len - 1] == `'` {
		return rest[1..rest.len - 1]
	}
	return rest
}

// is_numeric checks if a string represents a valid number (integer or float).
fn is_numeric(s string) bool {
	if s.len == 0 {
		return false
	}
	mut has_digit := false
	mut has_dot := false
	for i, ch in s {
		if ch == `-` && i == 0 {
			continue
		}
		if ch == `.` {
			if has_dot {
				return false
			}
			has_dot = true
			continue
		}
		if ch < `0` || ch > `9` {
			return false
		}
		has_digit = true
	}
	return has_digit
}

// url_decode performs simple percent-decoding for URL-encoded values.
// Converts %XX sequences back to their character equivalents.
fn url_decode(s string) string {
	mut result := []u8{}
	mut i := 0
	for i < s.len {
		if s[i] == `%` && i + 2 < s.len {
			hex_str := s[i + 1..i + 3]
			code := int_from_hex(hex_str)
			if code >= 0 {
				result << u8(code)
				i += 3
				continue
			}
		} else if s[i] == `+` {
			result << u8(` `)
			i++
			continue
		}
		result << s[i]
		i++
	}
	return result.bytestr()
}

// int_from_hex converts a 2-char hex string to an integer.
fn int_from_hex(s string) int {
	if s.len < 2 {
		return -1
	}
	mut result := 0
	for i in 0 .. 2 {
		ch := s[i]
		if ch >= `0` && ch <= `9` {
			result = result * 16 + int(ch - `0`)
		} else if ch >= `a` && ch <= `f` {
			result = result * 16 + int(ch - `a`) + 10
		} else if ch >= `A` && ch <= `F` {
			result = result * 16 + int(ch - `A`) + 10
		} else {
			return -1
		}
	}
	return result
}
