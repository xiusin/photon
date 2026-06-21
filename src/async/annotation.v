module async

// annotation.v - @[async] Annotation Support (Spring @Async inspired)
//
// Provides annotation-based asynchronous method execution. Methods
// annotated with @[async] are identified at compile time and can be
// dispatched to a TaskExecutor for background execution.
//
// Supported forms:
//   @[async]                       — default executor
//   @[async: 'emailExecutor']      — named executor (future extension)
//
// Usage:
//   @[service]
//   pub struct EmailService {
//       @[autowired]
//       executor &async.TaskExecutor
//   }
//
//   @[async]
//   pub fn (mut s EmailService) send_email(addr string, body string) {
//       // this method runs on a worker thread
//       smtp.send(addr, body)
//   }
//
// The comptime scanner `extract_async_methods[T]()` discovers all
// @[async] methods on a type. The caller wraps the method body in a
// closure and submits it to a TaskExecutor:
//
//   methods := async.extract_async_methods[EmailService]()
//   te.submit(fn () { service.send_email(addr, body) })!

// attr_async is the V attribute name for @[async].
pub const attr_async = 'async'

// AsyncAttribute holds parsed attributes from @[async].
pub struct AsyncAttribute {
pub mut:
	executor string // named executor; '' means use the default
}

// parse_async_attr parses the @[async] attribute string.
// Accepted forms:
//   ''                       → default executor
//   'emailExecutor'          → named executor
//   '"emailExecutor"'        → quoted name, quotes stripped
pub fn parse_async_attr(attr string) AsyncAttribute {
	mut aa := AsyncAttribute{}
	cleaned := attr.trim_space().trim("'").trim('"').trim_space()
	if cleaned.len > 0 {
		aa.executor = cleaned
	}
	return aa
}

// AsyncMethodInfo describes a method annotated with @[async].
pub struct AsyncMethodInfo {
pub:
	method_name string
	executor    string // resolved executor name ('' = default)
	attrs       []string
}

// has_async_attr checks if a list of method attributes contains @[async].
// Matches 'async', 'async:...', or 'async(...)'.
pub fn has_async_attr(attrs []string) bool {
	for attr in attrs {
		if attr == attr_async || attr.starts_with('async:') || attr.starts_with('async(') {
			return true
		}
	}
	return false
}

// extract_async_attr extracts the @[async] attribute string from a list
// of method attributes. Returns '' if not present.
pub fn extract_async_attr(attrs []string) string {
	for attr in attrs {
		if attr == attr_async {
			return ''
		}
		if attr.starts_with('async:') {
			return attr['async:'.len..].trim_space()
		}
		if attr.starts_with('async(') {
			end_idx := attr.last_index(')') or { attr.len }
			return attr['async('.len..end_idx].trim_space()
		}
	}
	return ''
}

// extract_async_methods scans type T at compile time for methods
// annotated with @[async]. Returns one AsyncMethodInfo per async method.
//
// This is a pure comptime scan — zero runtime reflection. The resolved
// `executor` field is the explicit argument (if any) or '' for default.
//
// V comptime note: method-level attributes are inspected via
// `method.attrs` (a []string) inside `$for method in T.methods`.
//
// Usage:
//   methods := async.extract_async_methods[EmailService]()
//   for m in methods {
//       println('${m.method_name} → executor=${m.executor}')
//   }
pub fn extract_async_methods[T]() []AsyncMethodInfo {
	mut methods := []AsyncMethodInfo{}
	$for method in T.methods {
		if has_async_attr(method.attrs) {
			arg := extract_async_attr(method.attrs)
			parsed := parse_async_attr(arg)
			methods << AsyncMethodInfo{
				method_name: method.name
				executor: parsed.executor
				attrs: method.attrs.clone()
			}
		}
	}
	return methods
}

// is_async_annotated returns true if type T has any @[async] methods.
//
// Usage:
//   if async.is_async_annotated[MyService]() {
//       // T has async methods
//   }
pub fn is_async_annotated[T]() bool {
	return extract_async_methods[T]().len > 0
}

// has_async_method returns true if type T has an @[async] method with
// the given name. The name comparison is exact.
//
// Usage:
//   if async.has_async_method[MyService]('send_email') {
//       // send_email is annotated @[async]
//   }
pub fn has_async_method[T](method_name string) bool {
	methods := extract_async_methods[T]()
	for m in methods {
		if m.method_name == method_name {
			return true
		}
	}
	return false
}
