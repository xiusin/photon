module cli

// command.v - Command trait and helpers
//
// Commands implement the Command interface with a name, description,
// signature, and execute method. Inspired by Symfony Console's Command class.

// Command is the interface that all CLI commands must implement
pub interface Command {
	name() string
	description() string
	signature() string
	execute(input &CommandInput, output &CommandOutput) !
}

// BaseCommand provides default implementations for common command patterns
pub struct BaseCommand {
pub:
	name        string
	description string
pub mut:
	sig         string // signature string
}

// name returns the command name
pub fn (c &BaseCommand) name() string {
	return c.name
}

// description returns the command description
pub fn (c &BaseCommand) description() string {
	return c.description
}

// signature returns the command signature
pub fn (c &BaseCommand) signature() string {
	return c.sig
}
