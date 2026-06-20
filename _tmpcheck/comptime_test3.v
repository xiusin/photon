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

fn main() {
	mut c := Counter{}
	$for method in Counter.methods {
		// Try comptime if with method.name
		$if method.name == 'tick' {
			c.tick()
			println('called tick, count=${c.count}')
		} $else $if method.name == 'tock' {
			c.tock()
			println('called tock, count=${c.count}')
		}
	}
}
