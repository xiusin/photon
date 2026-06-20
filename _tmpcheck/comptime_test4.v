module main

struct Counter {
mut:
	count int
}

@[scheduled('* * * * *')]
fn (mut c Counter) tick() {
	c.count++
}

@[scheduled('0 * * * *')]
fn (mut c Counter) tock() {
	c.count += 10
}

fn call_method[T](bean voidptr, method_name string) ! {
	mut b := unsafe { &T(bean) }
	$for method in T.methods {
		$if method.name == method_name {
			b.$method()
			return
		}
	}
	return error('method not found')
}

fn main() {
	mut c := Counter{}
	call_method[Counter](voidptr(&c), 'tick')!
	println('after tick: ${c.count}')
	call_method[Counter](voidptr(&c), 'tock')!
	println('after tock: ${c.count}')
}
