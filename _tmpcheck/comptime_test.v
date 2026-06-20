module main

struct Counter {
mut:
	count int
}

@[scheduled('* * * * *')]
fn (mut c Counter) tick() {
	c.count++
}

fn extract_scheduled_expr(attrs []string) string {
	for attr in attrs {
		if attr.starts_with('scheduled(') {
			start := attr.index_after('(')
			end := attr.last_index(')')
			if start > 0 && end > start {
				inner := attr[start..end]
				if inner.len >= 2 && (inner[0] == `'` || inner[0] == `"`) {
					return inner[1..inner.len - 1]
				}
				return inner
			}
		}
	}
	return ''
}

fn main() {
	mut c := Counter{}
	$for method in Counter.methods {
		cron_expr := extract_scheduled_expr(method.attrs)
		if cron_expr.len > 0 {
			println('Found scheduled method: ${method.name}, cron: ${cron_expr}')

			// Test: closure with captured bean
			task_fn := fn [mut c] () {
				c.$method()
			}
			task_fn()
			println('After closure call: ${c.count}')
		}
	}
}
