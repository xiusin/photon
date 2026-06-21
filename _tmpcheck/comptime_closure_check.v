module main

import sync

struct Foo {
mut:
	mu sync.Mutex
	x  int
}

@[scheduled('* * * * *')]
fn (mut f Foo) bar() {
	f.mu.@lock()
	f.x++
	f.mu.unlock()
}

@[scheduled('0 * * * *')]
fn (mut f Foo) baz() {
	f.mu.@lock()
	f.x += 10
	f.mu.unlock()
}

fn extract_scheduled_expr(attrs []string) string {
	for attr in attrs {
		if attr.starts_with('scheduled:') || attr.starts_with('scheduled(') {
			mut val := attr
			if val.starts_with('scheduled:') {
				val = val['scheduled:'.len..]
			} else if val.starts_with('scheduled(') {
				val = val['scheduled('.len..]
				if val.ends_with(')') {
					val = val[..val.len - 1]
				}
			}
			return val.trim("'").trim('"').trim_space()
		}
	}
	return ''
}

type Callback = fn () !

fn dispatch_scheduled_method[T](bean_ptr voidptr, method_name string) ! {
	mut bean := unsafe { &T(bean_ptr) }
	$for method in T.methods {
		if method_name == method.name {
			bean.$method()
		}
	}
}

struct Context {
}

fn (mut ctx Context) register_scheduled[T](bean_ptr voidptr) []Callback {
	mut callbacks := []Callback{}
	dispatcher := dispatch_scheduled_method[T]
	$for method in T.methods {
		cron_expr := extract_scheduled_expr(method.attrs)
		if cron_expr.len > 0 {
			method_name := method.name
			cb := Callback(fn [bean_ptr, method_name, dispatcher] () ! {
				dispatcher(bean_ptr, method_name)!
			})
			callbacks << cb
		}
	}
	return callbacks
}

fn main() {
	mut ctx := Context{}
	mut foo := &Foo{}
	cbs := ctx.register_scheduled[Foo](foo)
	println('num callbacks: ${cbs.len}')
	for cb in cbs {
		cb() or { println('err: $err') }
	}
	foo.mu.@lock()
	x := foo.x
	foo.mu.unlock()
	println('final x = ${x}')
}
