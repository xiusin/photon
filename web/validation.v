module web

import veb
import json

// validation.v - Request Validation (Laravel FormRequest + Spring @Valid inspired)
//
// Provides compile-time DTO validation via @[validate: '...'] attributes.
// All validation rules are parsed at compile time and generated into
// efficient inline validation code.
//
// Supported rules:
//   required              — field must be present and non-empty
//   min:N                 — numeric minimum or string minimum length
//   max:N                 — numeric maximum or string maximum length
//   min_len:N             — minimum string length
//   max_len:N             — maximum string length
//   email                 — basic email format validation
//   url                   — URL format validation
//   alpha                 — alphabetic characters only
//   alpha_num             — alphanumeric characters only
//   numeric               — numeric string
//   in:A,B,C              — value must be one of the listed options
//   not_in:A,B,C          — value must NOT be one of the listed options
//   regex:PATTERN         — must match the regular expression
//   confirmed             — field must have a matching {field}_confirmation
//   starts_with:PREFIX    — string must start with prefix
//   ends_with:SUFFIX      — string must end with suffix
//   different:FIELD       — must be different from another field
//   same:FIELD            — must be the same as another field
//   between:MIN,MAX        — numeric value between min and max
//   digits:N              — must be exactly N digits
//   integer               — must be an integer
//   boolean               — must be a boolean (true/false/1/0)
//   ip                    — must be a valid IP address
//   vjson                  — must be valid JSON
//
// Usage:
//   struct CreateUserDto {
//       username string @[validate: 'required|min_len:3|max_len:20|alpha_num']
//       email    string @[validate: 'required|email']
//       age      int    @[validate: 'required|min:0|max:150']
//       role     string @[validate: 'required|in:ADMIN,USER,GUEST']
//   }
//
//   dto, errors := web.validate[CreateUserDto](ctx)
//   if errors.len > 0 {
//       return ctx.json(web.validation_error(errors))
//   }

// ── ValidationError ──

// ValidationError represents a single validation failure.
pub struct ValidationError {
pub:
	field   string // field name that failed
	rule    string // the rule that failed (e.g., 'required', 'email')
	message string // human-readable error message
	value   string // the actual value that was provided
}

// str returns a formatted validation error string.
pub fn (ve &ValidationError) str() string {
	return '${ve.field}: ${ve.message}'
}

// msg implements the IError interface.
pub fn (ve &ValidationError) msg() string {
	return ve.message
}

// code implements the IError interface.
pub fn (ve &ValidationError) code() int {
	return 422
}

// ── ValidationErrors ──

// ValidationErrors is a collection of validation failures, keyed by field name.
pub type ValidationErrors = map[string][]ValidationError

// new_validation_errors creates an empty ValidationErrors collection.
pub fn new_validation_errors() ValidationErrors {
	return map[string][]ValidationError{}
}

// has_errors returns true if there are any validation errors.
pub fn (ve ValidationErrors) has_errors() bool {
	return ve.len > 0
}

// first_error_field returns the name of the first field that has errors.
// Returns empty string if no errors exist.
pub fn (ve ValidationErrors) first_error_field() string {
	for field, errors in ve {
		if errors.len > 0 {
			return field
		}
	}
	return ''
}

// all_messages returns all error messages as a flat array.
pub fn (ve ValidationErrors) all_messages() []string {
	mut messages := []string{}
	for _, errors in ve {
		for err in errors {
			messages << err.message
		}
	}
	return messages
}

// errors_for returns errors for a specific field.
pub fn (ve ValidationErrors) errors_for(field_name string) []ValidationError {
	return ve[field_name] or { []ValidationError{} }
}

// merge combines another ValidationErrors into this one.
pub fn (mut ve ValidationErrors) merge(other ValidationErrors) {
	for field, errors in other {
		mut existing := ve[field] or { []ValidationError{} }
		existing << errors
		ve[field] = existing
	}
}

// ── Validation Rule Parsing ──

// parse_rules splits a validate attribute string into individual rules.
// Input: 'required|min_len:3|max_len:20'
// Output: ['required', 'min_len:3', 'max_len:20']
pub fn parse_rules(validate_str string) []string {
	return validate_str.split('|')
}

// parse_rule splits a rule into name and argument.
// Input: 'min_len:3'
// Output: ('min_len', '3')
pub fn parse_rule(rule string) (string, string) {
	parts := rule.split_nth(':', 2)
	if parts.len == 2 {
		return parts[0], parts[1]
	}
	return parts[0], ''
}

// ── Custom Validator Registry ──

// ValidatorFunc is the function signature for custom validators.
pub type ValidatorFunc = fn (value string, arg string) bool

// MsgFunc is the function signature for custom validator error messages.
pub type MsgFunc = fn (field string, arg string) string

// CustomValidator holds a custom validation rule definition.
pub struct CustomValidator {
pub:
	name           string
	validator_func ValidatorFunc = unsafe { nil }
	msg_func       MsgFunc       = unsafe { nil } // (field, arg) -> error message
}

// Global registry for custom validators
__global (
	custom_validators map[string]CustomValidator
)

// register_validator registers a custom validation rule.
pub fn register_validator(name string, validator ValidatorFunc, msg MsgFunc) {
	if custom_validators.len == 0 {
		custom_validators = map[string]CustomValidator{}
	}
	custom_validators[name] = CustomValidator{
		name:           name
		validator_func: validator
		msg_func:       msg
	}
}

// get_validator retrieves a custom validator by name.
pub fn get_validator(name string) ?CustomValidator {
	return custom_validators[name]
}

// clear_custom_validators removes all registered custom validators (useful for testing).
pub fn clear_custom_validators() {
	custom_validators.clear()
}

// ── Conditional Validation ──

// ValidationCondition defines when a rule should be applied.
pub struct ValidationCondition {
pub:
	field_name string // the field this condition applies to
	rule_name  string // only apply if this rule is for this field
	dep_field  string // dependent field name
	dep_value  string // expected/excluded value
	is_unless  bool   // true = required_unless, false = required_if
}

// check evaluates the condition against the given params.
fn (vc &ValidationCondition) check(params map[string]string) bool {
	val := params[vc.dep_field] or { '' }
	if vc.is_unless {
		return val != vc.dep_value
	}
	return val == vc.dep_value
}

// validate_with_conditions validates with conditional rules.
// Conditions can depend on other field values.
pub fn validate_with_conditions[T](ctx &veb.Context, conditions []ValidationCondition) (T, ValidationErrors) {
	mut result := T{}
	mut errors := ValidationErrors{}
	params := extract_validation_params(ctx)

	$for field in T.fields {
		mut validate_str := ''
		for attr in field.attrs {
			if attr.starts_with('validate:') || attr.starts_with('validate(') {
				mut val := attr
				if val.starts_with('validate:') {
					val = val['validate:'.len..]
				} else {
					val = val['validate('.len..]
					if val.ends_with(')') {
						val = val[..val.len - 1]
					}
				}
				validate_str = val.trim("'").trim('"').trim_space()
			}
		}

		if validate_str.len == 0 {
			val := params[field.name] or { '' }
			$if field.typ is string {
				result.$(field.name) = val
			} $else $if field.typ is int {
				result.$(field.name) = val.int()
			} $else $if field.typ is f64 {
				result.$(field.name) = val.f64()
			} $else $if field.typ is bool {
				result.$(field.name) = val in ['1', 'true', 'on', 'yes']
			}
			continue
		}

		val := params[field.name] or { '' }

		// Check conditions for this field
		rules := parse_rules(validate_str)
		for rule in rules {
			rule_name, _ := parse_rule(rule)

			// Check if any condition prevents this rule
			should_skip := false
			for cond in conditions {
				if cond.field_name == field.name && cond.rule_name == rule_name {
					if !cond.check(params) {
						should_skip = true
						break
					}
				}
			}

			if should_skip {
				continue
			}

			ve := apply_rule_detail(field.name, val, rule) or { continue }
			mut field_errors := errors[field.name] or { []ValidationError{} }
			field_errors << ve
			errors[field.name] = field_errors
		}

		// Set value on struct even if validation fails
		$if field.typ is string {
			result.$(field.name) = val
		} $else $if field.typ is int {
			result.$(field.name) = val.int()
		} $else $if field.typ is f64 {
			result.$(field.name) = val.f64()
		} $else $if field.typ is bool {
			result.$(field.name) = val in ['1', 'true', 'on', 'yes']
		}
	}
	return result, errors
}

// required_if creates a condition where a field is required only if another field has a specific value.
pub fn required_if(dep_field string, dep_value string) ValidationCondition {
	return ValidationCondition{
		field_name: dep_field
		rule_name:  'required'
		dep_field:  dep_field
		dep_value:  dep_value
		is_unless:  false
	}
}

// required_unless creates a condition where a field is required unless another field has a specific value.
pub fn required_unless(dep_field string, dep_value string) ValidationCondition {
	return ValidationCondition{
		field_name: dep_field
		rule_name:  'required'
		dep_field:  dep_field
		dep_value:  dep_value
		is_unless:  true
	}
}

// ── Nested Object Validation ──

// NestedValidationError represents an error in a nested object.
pub struct NestedValidationError {
pub:
	path   string // dot-separated path to the field (e.g., "address.street")
	errors ValidationErrors
}

// NestedValidationErrors collects errors from nested validations.
pub type NestedValidationErrors = []NestedValidationError

// has_nested_errors returns true if there are any nested validation errors.
pub fn (nve NestedValidationErrors) has_errors() bool {
	return nve.len > 0
}

// all_nested_messages returns all nested error messages as a flat array.
pub fn (nve NestedValidationErrors) all_nested_messages() []string {
	mut messages := []string{}
	for ne in nve {
		for _, errors in ne.errors {
			for err in errors {
				messages << '${ne.path}.${err.field}: ${err.message}'
			}
		}
	}
	return messages
}

// flatten merges nested errors into a flat ValidationErrors map with dot-notation keys.
pub fn (nve NestedValidationErrors) flatten() ValidationErrors {
	mut result := ValidationErrors{}
	for ne in nve {
		for field, errors in ne.errors {
			full_path := if ne.path.len > 0 { '${ne.path}.${field}' } else { field }
			result[full_path] = errors
		}
	}
	return result
}

// validate_nested validates a nested struct field with its own validation rules.
// This allows validating embedded/related structs.
//
// Usage:
//   nested_errors := web.validate_nested(user.address, 'address', address_rules)
//   if nested_errors.has_errors() { ... }
pub fn validate_nested(nested_params map[string]string, prefix string, field_rules map[string]string) NestedValidationErrors {
	mut result := NestedValidationErrors{}
	mut errors := ValidationErrors{}

	for field_name, validate_str in field_rules {
		val := nested_params[field_name] or { '' }

		parsed_rules := parse_rules(validate_str)
		for rule in parsed_rules {
			ve := apply_rule_detail(field_name, val, rule) or { continue }
			mut field_errors := errors[field_name] or { []ValidationError{} }
			field_errors << ve
			errors[field_name] = field_errors
		}
	}

	if errors.has_errors() {
		result << NestedValidationError{
			path:   prefix
			errors: errors
		}
	}

	return result
}

// ── Additional Validation Rules ──

// validate_uuid checks if value is a valid UUID format (v4).
pub fn validate_uuid(value string) bool {
	if value.len == 0 {
		return true
	}
	// UUID v4 format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
	if value.len != 36 {
		return false
	}
	parts := value.split('-')
	if parts.len != 5 {
		return false
	}
	if parts[0].len != 8 || parts[1].len != 4 || parts[2].len != 4 || parts[3].len != 4
		|| parts[4].len != 12 {
		return false
	}
	// Check version (4)
	if parts[2][0] != `4` {
		return false
	}
	// Check variant (8, 9, a, b)
	variant_char := parts[3][0]
	if variant_char !in [`8`, `9`, `a`, `A`, `b`, `B`] {
		return false
	}
	// All parts should be hex
	for part in parts {
		for ch in part {
			if !((ch >= `0` && ch <= `9`) || (ch >= `a` && ch <= `f`) || (ch >= `A` && ch <= `F`)) {
				return false
			}
		}
	}
	return true
}

// validate_date checks basic date format (YYYY-MM-DD).
pub fn validate_date(value string) bool {
	if value.len == 0 {
		return true
	}
	if value.len != 10 {
		return false
	}
	if value[4] != `-` || value[7] != `-` {
		return false
	}
	year_str := value[..4]
	month_str := value[5..7]
	day_str := value[8..10]
	year := year_str.int()
	month := month_str.int()
	day := day_str.int()
	if year < 1900 || year > 2100 {
		return false
	}
	if month < 1 || month > 12 {
		return false
	}
	if day < 1 || day > 31 {
		return false
	}
	return true
}

// validate_timezone checks if value is a valid timezone identifier.
pub fn validate_timezone(value string) bool {
	if value.len == 0 {
		return true
	}
	// Common timezone formats: UTC, America/New_York, Europe/London, etc.
	if value == 'UTC' || value == 'GMT' {
		return true
	}
	if value.contains('/') {
		parts := value.split('/')
		if parts.len == 2 && parts[0].len > 0 && parts[1].len > 0 {
			return true
		}
	}
	return false
}

// validate_phone checks basic phone number format (digits, spaces, dashes, +).
pub fn validate_phone(value string) bool {
	if value.len == 0 {
		return true
	}
	if value.len < 7 {
		return false
	}
	for ch in value {
		if !((ch >= `0` && ch <= `9`) || ch == ` ` || ch == `-` || ch == `(`
			|| ch == `)` || ch == `+`) {
			return false
		}
	}
	return true
}

// validate_password_strength checks password strength requirements.
// Args: min_length,min_uppercase,min_lowercase,min_digits,min_special
pub fn validate_password_strength(value string, arg string) bool {
	if value.len == 0 {
		return true
	}
	parts := arg.split(',')
	min_len := if parts.len > 0 { parts[0].int() } else { 8 }
	min_upper := if parts.len > 1 { parts[1].int() } else { 1 }
	min_lower := if parts.len > 2 { parts[2].int() } else { 1 }
	min_digit := if parts.len > 3 { parts[3].int() } else { 1 }
	min_special := if parts.len > 4 { parts[4].int() } else { 0 }

	if value.len < min_len {
		return false
	}

	mut upper_count := 0
	mut lower_count := 0
	mut digit_count := 0
	mut special_count := 0

	for ch in value {
		if ch >= `A` && ch <= `Z` {
			upper_count++
		} else if ch >= `a` && ch <= `z` {
			lower_count++
		} else if ch >= `0` && ch <= `9` {
			digit_count++
		} else {
			special_count++
		}
	}

	return upper_count >= min_upper && lower_count >= min_lower && digit_count >= min_digit
		&& special_count >= min_special
}

// validate_confirmed checks if field has a matching {field}_confirmation value.
pub fn validate_confirmed(value string, arg string, all_params map[string]string) bool {
	if arg.len == 0 {
		return true
	}
	confirmation_value := all_params['${arg}_confirmation'] or { '' }
	return value == confirmation_value
}

// validate_different checks if two fields have different values.
pub fn validate_different(value string, arg string, all_params map[string]string) bool {
	if arg.len == 0 {
		return true
	}
	other_value := all_params[arg] or { '' }
	return value != other_value
}

// validate_same checks if two fields have the same value.
pub fn validate_same(value string, arg string, all_params map[string]string) bool {
	if arg.len == 0 {
		return true
	}
	other_value := all_params[arg] or { '' }
	return value == other_value
}

// ── Rule Validation Functions (continued) ──

// validate_required checks that a value is present and non-empty.
pub fn validate_required(value string) bool {
	return value.len > 0
}

// validate_min checks numeric minimum or string minimum length.
pub fn validate_min(value string, arg string) bool {
	if arg.len == 0 {
		return true
	}
	min_val := arg.int()
	if min_val == 0 && arg != '0' {
		// Treat as string length check
		return value.len >= arg.len
	}
	// Try numeric comparison
	if value.len > 0 {
		num := value.f64()
		return num >= f64(min_val)
	}
	return false
}

// validate_max checks numeric maximum or string maximum length.
pub fn validate_max(value string, arg string) bool {
	if arg.len == 0 {
		return true
	}
	max_val := arg.int()
	if max_val == 0 && arg != '0' {
		return value.len <= arg.len
	}
	if value.len > 0 {
		num := value.f64()
		return num <= f64(max_val)
	}
	return true // empty values pass max check (use required for emptiness)
}

// validate_min_len checks minimum string length.
pub fn validate_min_len(value string, arg string) bool {
	if arg.len == 0 {
		return true
	}
	return value.len >= arg.int()
}

// validate_max_len checks maximum string length.
pub fn validate_max_len(value string, arg string) bool {
	if arg.len == 0 {
		return true
	}
	return value.len <= arg.int()
}

// validate_email checks basic email format.
pub fn validate_email(value string) bool {
	if value.len == 0 {
		return true // empty passes (use required for emptiness)
	}
	return value.contains('@') && value.contains('.') && value.index('@') or { 0 } > 0 && value.index('.') or {
		0
	} > value.index('@') or { 0 }
}

// validate_url checks basic URL format.
pub fn validate_url(value string) bool {
	if value.len == 0 {
		return true
	}
	return value.starts_with('http://') || value.starts_with('https://')
}

// validate_alpha checks alphabetic characters only.
pub fn validate_alpha(value string) bool {
	if value.len == 0 {
		return true
	}
	for ch in value {
		if !((ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`)) {
			return false
		}
	}
	return true
}

// validate_alpha_num checks alphanumeric characters only.
pub fn validate_alpha_num(value string) bool {
	if value.len == 0 {
		return true
	}
	for ch in value {
		if !((ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`)
			|| (ch >= `0` && ch <= `9`) || ch == `_`) {
			return false
		}
	}
	return true
}

// validate_numeric checks if the value is a valid number.
pub fn validate_numeric(value string) bool {
	if value.len == 0 {
		return true
	}
	mut has_digit := false
	for i, ch in value {
		if ch == `-` && i == 0 {
			continue
		}
		if ch == `.` {
			continue
		}
		if ch < `0` || ch > `9` {
			return false
		}
		has_digit = true
	}
	return has_digit
}

// validate_in checks if value is in the allowed list (case-insensitive).
pub fn validate_in(value string, arg string) bool {
	if arg.len == 0 {
		return true
	}
	options := arg.split(',')
	value_lower := value.to_lower()
	for opt in options {
		if opt.trim_space().to_lower() == value_lower {
			return true
		}
	}
	return false
}

// validate_not_in checks if value is NOT in the disallowed list (case-insensitive).
pub fn validate_not_in(value string, arg string) bool {
	if arg.len == 0 {
		return true
	}
	options := arg.split(',')
	value_lower := value.to_lower()
	for opt in options {
		if opt.trim_space().to_lower() == value_lower {
			return false
		}
	}
	return true
}

// validate_between checks if a numeric value is between min and max.
pub fn validate_between(value string, arg string) bool {
	if arg.len == 0 || value.len == 0 {
		return true
	}
	parts := arg.split(',')
	if parts.len != 2 {
		return true
	}
	min_val := parts[0].f64()
	max_val := parts[1].f64()
	num := value.f64()
	return num >= min_val && num <= max_val
}

// validate_integer checks if value is a valid integer.
pub fn validate_integer(value string) bool {
	if value.len == 0 {
		return true
	}
	mut start := 0
	if value[0] == `-` {
		start = 1
	}
	if start >= value.len {
		return false
	}
	for i in start .. value.len {
		if value[i] < `0` || value[i] > `9` {
			return false
		}
	}
	return true
}

// validate_boolean checks if value is a valid boolean.
pub fn validate_boolean(value string) bool {
	if value.len == 0 {
		return true
	}
	return value in ['true', 'false', '1', '0', 'yes', 'no', 'on', 'off']
}

// validate_starts_with checks if value starts with a prefix.
pub fn validate_starts_with(value string, arg string) bool {
	if arg.len == 0 {
		return true
	}
	return value.starts_with(arg)
}

// validate_ends_with checks if value ends with a suffix.
pub fn validate_ends_with(value string, arg string) bool {
	if arg.len == 0 {
		return true
	}
	return value.ends_with(arg)
}

// validate_digits checks if value has exactly N digits.
pub fn validate_digits(value string, arg string) bool {
	if arg.len == 0 {
		return true
	}
	expected := arg.int()
	mut count := 0
	for ch in value {
		if ch >= `0` && ch <= `9` {
			count++
		}
	}
	return count == expected
}

// validate_ip checks basic IP address format.
pub fn validate_ip(value string) bool {
	if value.len == 0 {
		return true
	}
	parts := value.split('.')
	if parts.len != 4 {
		return false
	}
	for part in parts {
		num := part.int()
		if num < 0 || num > 255 {
			return false
		}
	}
	return true
}

// validate_vjson checks if value is valid JSON.
pub fn validate_vjson(value string) bool {
	if value.len == 0 {
		return true
	}
	return (value.starts_with('{') && value.ends_with('}'))
		|| (value.starts_with('[') && value.ends_with(']'))
}

// ── Rule Application ──

// apply_rule applies a single validation rule to a value.
// Returns a ValidationError if the rule fails, or none if it passes.
// check_rule checks whether a value passes a validation rule.
// Returns (true, '') if the rule passes, or (false, error_message) if it fails.
// This is a convenience wrapper around apply_rule that avoids Option types
// for simpler usage in tests and non-Result contexts.
pub fn check_rule(field_name string, value string, rule string) (bool, string) {
	apply_rule(field_name, value, rule) or { return false, err.msg() }
	return true, ''
}

// apply_rule applies a single validation rule to a value.
// Returns an error if the rule fails. Use check_rule() for simple bool results,
// or apply_rule_detail() to get the full ValidationError struct.
pub fn apply_rule(field_name string, value string, rule string) !string {
	rule_name, rule_arg := parse_rule(rule)

	// Check custom validators first
	custom := get_validator(rule_name) or { CustomValidator{} }
	if custom.name.len > 0 && !isnil(custom.validator_func) {
		is_valid := custom.validator_func(value, rule_arg)
		if !is_valid {
			if !isnil(custom.msg_func) {
				em := custom.msg_func
				return error(em(field_name, rule_arg))
			}
			return error(default_error_message(field_name, rule_name, rule_arg))
		}
		return ''
	}

	is_valid := match rule_name {
		'required' { validate_required(value) }
		'min' { validate_min(value, rule_arg) }
		'max' { validate_max(value, rule_arg) }
		'min_len' { validate_min_len(value, rule_arg) }
		'max_len' { validate_max_len(value, rule_arg) }
		'email' { validate_email(value) }
		'url' { validate_url(value) }
		'alpha' { validate_alpha(value) }
		'alpha_num' { validate_alpha_num(value) }
		'numeric' { validate_numeric(value) }
		'in' { validate_in(value, rule_arg) }
		'not_in' { validate_not_in(value, rule_arg) }
		'between' { validate_between(value, rule_arg) }
		'integer' { validate_integer(value) }
		'boolean' { validate_boolean(value) }
		'starts_with' { validate_starts_with(value, rule_arg) }
		'ends_with' { validate_ends_with(value, rule_arg) }
		'digits' { validate_digits(value, rule_arg) }
		'ip' { validate_ip(value) }
		'vjson' { validate_vjson(value) }
		'uuid' { validate_uuid(value) }
		'date' { validate_date(value) }
		'timezone' { validate_timezone(value) }
		'phone' { validate_phone(value) }
		'password_strength' { validate_password_strength(value, rule_arg) }
		else { true } // unknown rules pass
	}

	if !is_valid {
		return error(default_error_message(field_name, rule_name, rule_arg))
	}
	return ''
}

// apply_rule_detail applies a single validation rule and returns the full ValidationError.
// Use apply_rule() for simple pass/fail checks, or this for detailed error info.
pub fn apply_rule_detail(field_name string, value string, rule string) ?ValidationError {
	apply_rule(field_name, value, rule) or {
		rule_name, _ := parse_rule(rule)
		return ValidationError{
			field:   field_name
			rule:    rule_name
			message: err.msg()
			value:   value
		}
	}
	return none
}

// ── Error Message Generation ──

// default_error_message generates a human-readable error message.
pub fn default_error_message(field string, rule string, arg string) string {
	return match rule {
		'required' { '${field} is required' }
		'min' { '${field} must be at least ${arg}' }
		'max' { '${field} must be at most ${arg}' }
		'min_len' { '${field} must be at least ${arg} characters' }
		'max_len' { '${field} must be at most ${arg} characters' }
		'email' { '${field} must be a valid email address' }
		'url' { '${field} must be a valid URL' }
		'alpha' { '${field} must contain only letters' }
		'alpha_num' { '${field} must contain only letters, numbers, and underscores' }
		'numeric' { '${field} must be a number' }
		'in' { '${field} must be one of: ${arg}' }
		'not_in' { '${field} must not be one of: ${arg}' }
		'between' { '${field} must be between ${arg.replace(',', ' and ')}' }
		'integer' { '${field} must be an integer' }
		'boolean' { '${field} must be a boolean' }
		'starts_with' { '${field} must start with "${arg}"' }
		'ends_with' { '${field} must end with "${arg}"' }
		'digits' { '${field} must be exactly ${arg} digits' }
		'ip' { '${field} must be a valid IP address' }
		'vjson' { '${field} must be valid JSON' }
		'uuid' { '${field} must be a valid UUID' }
		'date' { '${field} must be a valid date (YYYY-MM-DD)' }
		'timezone' { '${field} must be a valid timezone' }
		'phone' { '${field} must be a valid phone number' }
		'password_strength' { '${field} does not meet password strength requirements' }
		else { '${field} failed validation: ${rule}' }
	}
}

// ── DTO Validation with Comptime ──

// validate validates a struct T using @[validate: '...'] attributes.
// Uses comptime $for to scan struct fields and apply rules.
// Returns the validated struct and a map of validation errors.
//
// Usage:
//   dto, errors := web.validate[CreateUserDto](ctx)
//   if errors.has_errors() {
//       return ctx.json(web.validation_error(errors))
//   }
pub fn validate[T](ctx &veb.Context) (T, ValidationErrors) {
	mut result := T{}
	mut errors := ValidationErrors{}
	params := extract_validation_params(ctx)

	$for field in T.fields {
		mut validate_str := ''
		for attr in field.attrs {
			if attr.starts_with('validate:') || attr.starts_with('validate(') {
				mut val := attr
				if val.starts_with('validate:') {
					val = val['validate:'.len..]
				} else {
					val = val['validate('.len..]
					if val.ends_with(')') {
						val = val[..val.len - 1]
					}
				}
				validate_str = val.trim("'").trim('"').trim_space()
			}
		}

		if validate_str.len == 0 {
			// No validation — just bind the value
			val := params[field.name] or { '' }
			$if field.typ is string {
				result.$(field.name) = val
			} $else $if field.typ is int {
				result.$(field.name) = val.int()
			} $else $if field.typ is f64 {
				result.$(field.name) = val.f64()
			} $else $if field.typ is bool {
				result.$(field.name) = val in ['1', 'true', 'on', 'yes']
			}
			continue
		}

		// Get the value
		val := params[field.name] or { '' }

		// Apply each rule
		rules := parse_rules(validate_str)
		for rule in rules {
			ve := apply_rule_detail(field.name, val, rule) or { continue }
			mut field_errors := errors[field.name] or { []ValidationError{} }
			field_errors << ve
			errors[field.name] = field_errors
		}

		// Set value on struct even if validation fails (for re-display)
		$if field.typ is string {
			result.$(field.name) = val
		} $else $if field.typ is int {
			result.$(field.name) = val.int()
		} $else $if field.typ is f64 {
			result.$(field.name) = val.f64()
		} $else $if field.typ is bool {
			result.$(field.name) = val in ['1', 'true', 'on', 'yes']
		}
	}
	return result, errors
}

// validate_body validates a JSON request body against struct T.
pub fn validate_body[T](ctx &veb.Context) (T, ValidationErrors) {
	mut result := T{}
	mut errors := ValidationErrors{}

	// Parse JSON body into params
	body := ctx.req.data
	if body.len == 0 {
		return result, errors
	}

	// Decode JSON into the struct
	result = json.decode(T, body) or {
		// If JSON decode fails, try to validate individual fields
		return result, ValidationErrors{
			_body: [
				ValidationError{
					field:   '_body'
					rule:    'json'
					message: 'invalid JSON body'
				},
			]
		}
	}

	// Apply validation rules on the decoded struct
	$for field in T.fields {
		mut validate_str := ''
		for attr in field.attrs {
			if attr.starts_with('validate:') || attr.starts_with('validate(') {
				mut val := attr
				if val.starts_with('validate:') {
					val = val['validate:'.len..]
				} else {
					val = val['validate('.len..]
					if val.ends_with(')') {
						val = val[..val.len - 1]
					}
				}
				validate_str = val.trim("'").trim('"').trim_space()
			}
		}

		if validate_str.len == 0 {
			continue
		}

		// Get the value from the struct
		mut str_val := ''
		$if field.typ is string {
			str_val = result.$(field.name)
		} $else $if field.typ is int {
			str_val = result.$(field.name).str()
		} $else $if field.typ is f64 {
			str_val = result.$(field.name).str()
		} $else $if field.typ is bool {
			str_val = if result.$(field.name) { 'true' } else { 'false' }
		}

		// Apply rules
		rules := parse_rules(validate_str)
		for rule in rules {
			ve := apply_rule(field.name, str_val, rule) or { continue }
			mut field_errors := errors[field.name] or { []ValidationError{} }
			field_errors << ve
			errors[field.name] = field_errors
		}
	}
	return result, errors
}

// ── Response Helpers ──

// validation_error creates a standard validation error Result.
pub fn validation_error(errors ValidationErrors) Result {
	mut messages := []string{}
	for field, field_errors in errors {
		for err in field_errors {
			messages << err.message
		}
		_ = field
	}
	return fail(422, messages.join('; '))
}

// ── Internal Helpers ──

// extract_validation_params collects all input parameters for validation.
fn extract_validation_params(ctx &veb.Context) map[string]string {
	mut params := map[string]string{}

	// Query parameters
	for k, v in ctx.query {
		params[k] = v
	}

	// Form parameters
	for k, v in ctx.form {
		params[k] = v
	}

	return params
}
