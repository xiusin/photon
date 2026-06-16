module web

// pipeline.v - Pipeline (Laravel Onion Middleware)
//
// Implements the pipeline pattern where middleware wraps the handler
// in an onion-like fashion:
//   Request → MW1 → MW2 → Handler → MW2(response) → MW1(response) → Response
//
// Inspired by Illuminate\Pipeline\Pipeline.

// PipeFunc is a single middleware step: takes passable + next handler
pub type PipeFunc = fn (passable voidptr, next fn (voidptr) voidptr) voidptr

// Pipeline executes middleware in an onion-like pattern
pub struct Pipeline {
mut:
	pipes    []PipeFunc
	passable voidptr
}

// new_pipeline creates a new Pipeline
pub fn new_pipeline() &Pipeline {
	return &Pipeline{}
}

// send sets the initial passable through the pipeline
pub fn (mut p Pipeline) send(passable voidptr) &Pipeline {
	p.passable = passable
	return p
}

// through sets the array of pipes (middleware) to run
pub fn (mut p Pipeline) through(pipes []PipeFunc) &Pipeline {
	p.pipes = pipes.clone()
	return p
}

// then executes the pipeline with the final destination callback.
// Builds the onion closure chain — each middleware wraps the next.
// The chain is built once per then() call; closures are lightweight
// in V (capture-by-value) and the overhead is negligible for typical
// middleware counts (5-10).
pub fn (p &Pipeline) then(destination fn (voidptr) voidptr) voidptr {
	mut carry := destination

	for i := p.pipes.len; i > 0; i-- {
		pipe := p.pipes[i - 1]
		prev := carry
		carry = fn [pipe, prev](passable voidptr) voidptr {
			return pipe(passable, prev)
		}
	}

	return carry(p.passable)
}
