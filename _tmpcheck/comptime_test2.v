module main

struct Counter {
mut:
	count int
}

@[scheduled('* * * * *')]
fn (mut c Counter) tick() {
	c.count++
}

fn main() {
	mut c := Counter{}
	$for method in Counter.methods {
		// Try to take a method reference
		f := &Counter.$method
		f(mut c)
		println('count after call: ${c.count}')
	}
}
