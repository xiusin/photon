module orm

import strings

// query.v - @[query('SELECT ...')] Annotation Handling (Task B6)
//
// Provides native SQL query support with named parameters for
// JpaRepository[T].  Inspired by Spring Data's @Query annotation.
//
// ── Annotation Format ──
//
// V stores the @[query('SELECT ...')] attribute as a single string:
//
//   query: 'SELECT * FROM users WHERE age > :age'
//   query: "SELECT * FROM users WHERE name = :name"
//
// The attribute name (`query`) is separated from its argument by
// `: `, and the SQL is wrapped in single or double quotes.
//
// ── Named Parameters ──
//
// Named parameters use the `:name` syntax inside the SQL string:
//
//   SELECT * FROM users WHERE age > :age AND name LIKE :name
//
// At execution time, named parameters are converted to positional
// `?` placeholders and bound from a map[string]string supplied by
// the caller:
//
//   repo.execute_named_query(
//       'SELECT * FROM users WHERE age > :age AND name LIKE :name',
//       {'age': '18', 'name': 'J%'}
//   )!
//
// All user values are passed as positional `?` parameters to the
// underlying SqlQueryFn — never string-interpolated — preventing
// SQL injection.
//
// ── Comptime Extraction ──
//
// extract_query_annotation[T](method_name) scans T's methods at
// compile time via `$for method in T.methods` and returns the
// QueryAnnotation for the named method, or `none` if the method
// has no @[query] attribute.

// QueryAnnotation holds the parsed contents of a @[query('...')]
// attribute: the SQL string and the list of named parameters
// (e.g. ['age', 'name']) extracted from `:age`, `:name` tokens.
//
// The SQL field is named `sql_text` because `sql` is a reserved
// keyword in V (used by `sql db { ... }` blocks).
pub struct QueryAnnotation {
pub:
	sql_text     string
	named_params []string // e.g. ['age', 'name'] from :age, :name
}

// parse_query_annotation parses a V method attribute string into a
// QueryAnnotation.
//
// V stores @[query('SELECT ...')] as one of:
//   query: 'SELECT * FROM users WHERE age > :age'
//   query: "SELECT * FROM users WHERE name = :name"
//
// Returns `none` if the attribute is not a query annotation.
pub fn parse_query_annotation(attr string) ?QueryAnnotation {
	// Strip leading/trailing whitespace for robustness.
	trimmed := attr.trim_space()
	// Accept both `query:` (V's actual storage format) and `query(`
	// (defensive — handles the literal annotation syntax too).
	mut sql_raw := ''
	if trimmed.starts_with('query:') {
		// Format: query: 'SELECT ...'  or  query: "SELECT ..."
		rest := trimmed[6..].trim_space()
		sql_raw = strip_quotes(rest)
	} else if trimmed.starts_with('query(') {
		// Format: query('SELECT ...')  or  query("SELECT ...")
		// Remove leading 'query(' and trailing ')'.
		if !trimmed.ends_with(')') {
			return none
		}
		inner := trimmed[6..trimmed.len - 1].trim_space()
		sql_raw = strip_quotes(inner)
	} else {
		return none
	}
	if sql_raw.len == 0 {
		return none
	}
	return QueryAnnotation{
		sql_text: sql_raw
		named_params: extract_named_params(sql_raw)
	}
}

// strip_quotes removes a single layer of surrounding single or
// double quotes from `s`.  If `s` is not quoted, it is returned
// unchanged.
fn strip_quotes(s string) string {
	if s.len >= 2 && s[0] == `'` && s[s.len - 1] == `'` {
		return s[1..s.len - 1]
	}
	if s.len >= 2 && s[0] == `"` && s[s.len - 1] == `"` {
		return s[1..s.len - 1]
	}
	return s
}

// extract_named_params scans `sql_str` for `:name` tokens and returns
// the list of parameter names in order of appearance.
//
// A parameter name consists of letters, digits, and underscores,
// and must start with a letter or underscore (so `:1` is not a
// named parameter — it would be a literal).
pub fn extract_named_params(sql_str string) []string {
	mut params := []string{}
	mut i := 0
	for i < sql_str.len {
		if sql_str[i] == `:` {
			i++
			start := i
			for i < sql_str.len && (sql_str[i].is_letter() || sql_str[i] == `_` || sql_str[i].is_digit()) {
				i++
			}
			// Require at least one character, and the first must be
			// a letter or underscore (not a digit) to qualify as a
			// named parameter rather than a literal `:123`.
			if i > start && (sql_str[start].is_letter() || sql_str[start] == `_`) {
				params << sql_str[start..i]
			}
		} else {
			i++
		}
	}
	return params
}

// convert_named_to_positional rewrites `:name` tokens in `sql_str` as
// positional `?` placeholders, returning the rewritten SQL and the
// list of parameter names in the order their `?` placeholders
// appear.
//
// Example:
//   sql_in  := 'SELECT * FROM users WHERE age > :age AND name = :name'
//   sql_out, names := convert_named_to_positional(sql_in)
//   // sql_out == 'SELECT * FROM users WHERE age > ? AND name = ?'
//   // names  == ['age', 'name']
pub fn convert_named_to_positional(sql_str string) (string, []string) {
	mut sb := strings.new_builder(sql_str.len)
	mut params := []string{}
	mut i := 0
	for i < sql_str.len {
		if sql_str[i] == `:` {
			i++
			start := i
			for i < sql_str.len && (sql_str[i].is_letter() || sql_str[i] == `_` || sql_str[i].is_digit()) {
				i++
			}
			if i > start && (sql_str[start].is_letter() || sql_str[start] == `_`) {
				params << sql_str[start..i]
				sb.write_string('?')
			} else {
				// Not a valid named param — emit the ':' literally.
				sb.write_byte(`:`)
				sb.write_string(sql_str[start..i])
			}
		} else {
			sb.write_byte(sql_str[i])
			i++
		}
	}
	return sb.str(), params
}

// extract_query_annotation scans T's methods at compile time and
// returns the QueryAnnotation for the method named `method_name`,
// or `none` if the method has no @[query] attribute.
//
// Usage:
//   annotation := extract_query_annotation[UserRepo]('find_by_age') or {
//       return error('no @[query] on find_by_age')
//   }
//   users := repo.execute_named_query(annotation.sql_text, {'age': '18'})!
pub fn extract_query_annotation[T](method_name string) ?QueryAnnotation {
	$for method in T.methods {
		if method.name == method_name {
			for attr in method.attrs {
				if qa := parse_query_annotation(attr) {
					return qa
				}
			}
		}
	}
	return none
}

// ── JpaRepository[T] query execution methods ──
//
// execute_query and execute_named_query are defined in repository.v
// (not here) because V 0.5.1 requires generic methods on a generic
// type to be declared in the same file as the type definition.
// The parsing helpers (parse_query_annotation, convert_named_to_positional,
// extract_named_params) and the comptime extractor
// (extract_query_annotation[T]) live here in query.v.
