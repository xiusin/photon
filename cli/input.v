module cli

// input.v - CommandInput — parsed command-line arguments

// CommandInput holds the parsed command-line arguments
pub struct CommandInput {
pub mut:
	command_name string
	args         map[string]string
	options      map[string]string
	flags        map[string]bool
	raw_args     []string
}

// new_input parses os.args into a CommandInput
pub fn new_input(raw_args []string) &CommandInput {
	mut input := CommandInput{
		args:    map[string]string{}
		options: map[string]string{}
		flags:   map[string]bool{}
		raw_args: raw_args
	}

	if raw_args.len == 0 {
		return &CommandInput{
			args:    map[string]string{}
			options: map[string]string{}
			flags:   map[string]bool{}
		}
	}

	input.command_name = raw_args[0]

	mut i := 1
	for i < raw_args.len {
		arg := raw_args[i]

		if arg.starts_with('--') {
			rest := arg[2..]
			if rest.contains('=') {
				parts := rest.split_nth('=', 2)
				input.options[parts[0]] = parts[1]
			} else {
				if i + 1 < raw_args.len && !raw_args[i + 1].starts_with('--') {
					input.options[rest] = raw_args[i + 1]
					i++
				} else {
					input.flags[rest] = true
				}
			}
		} else if arg.starts_with('-') {
			rest := arg[1..]
			if i + 1 < raw_args.len && !raw_args[i + 1].starts_with('-') {
				input.options[rest] = raw_args[i + 1]
				i++
			} else {
				input.flags[rest] = true
			}
		} else {
			key := 'arg_${input.args.len}'
			input.args[key] = arg
		}
		i++
	}

	return &CommandInput{
		command_name: input.command_name
		args: input.args
		options: input.options
		flags: input.flags
		raw_args: input.raw_args
	}
}

// get_arg returns a positional argument by index (0-based)
pub fn (input &CommandInput) get_arg(idx int) string {
	key := 'arg_${idx}'
	return input.args[key] or { '' }
}

// get_option returns an option value
pub fn (input &CommandInput) get_option(name string) string {
	return input.options[name] or { '' }
}

// get_option_or returns an option value with default
pub fn (input &CommandInput) get_option_or(name string, default_val string) string {
	return input.options[name] or { default_val }
}

// has_flag returns true if flag is set
pub fn (input &CommandInput) has_flag(name string) bool {
	return input.flags[name] or { false }
}

// arg_count returns number of positional arguments
pub fn (input &CommandInput) arg_count() int {
	return input.args.len
}
