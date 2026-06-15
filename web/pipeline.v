module web

// pipeline.v - Pipeline (Laravel Onion Middleware)
//
// Implements the pipeline pattern where middleware wraps the handler
// in an onion-like fashion:
//   Request → MW1 → MW2 → Handler → MW2(response) → MW1(response) → Response
//
// Inspired by Illuminate\Pipeline\Pipeline.

// Pipe is a single middleware step in the pipeline
pub type PipeFunc = fn (passable voidptr, next fn (voidptr) voidptr) voidptr

// Pipeline executes middleware in an onion-like pattern
pub struct Pipeline {
mut:
	pipes      []PipeFunc
	passable   voidptr
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

// then executes the pipeline with the final destination callback
pub fn (p &Pipeline) then(destination fn (voidptr) voidptr) voidptr {
	// Build the onion from last to first
	mut carry := destination

	for i := p.pipes.len - 1; i >= 0; i-- {
		pipe := p.pipes[i]
		prev_carry := carry
		carry = fn [pipe, prev_carry](passable voidptr) voidptr {
			return pipe(passable, prev_carry)
		}
	}

	return carry(p.passable)
}
