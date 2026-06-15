module cli

// interactive.v - Interactive Input Helpers (Symfony Console inspired)
//
// Provides interactive question/answer methods for CLI commands:
//   ask()     - prompt for text input
//   confirm() - yes/no confirmation
//   secret()  - hidden input (password)
//   choice()  - select from options
//   anticipate() - autocomplete input

import os

// Question represents a question to ask the user
pub struct Question {
pub:
	prompt        string
	default_val   string
	required      bool = true
	hidden        bool
	choices       []string
	attempts      int = 3
}

// AskResult holds the user's answer
pub struct AskResult {
pub:
	answer string
	valid  bool
}

// ask prompts the user for text input
pub fn ask(prompt string) AskResult {
	return ask_with_default(prompt, '')
}

// ask_with_default prompts with a default value
pub fn ask_with_default(prompt string, default_val string) AskResult {
	if default_val.len > 0 {
		print('${prompt} [${default_val}]: ')
	} else {
		print('${prompt}: ')
	}

	input := os.input('')
	if input.len == 0 && default_val.len > 0 {
		return AskResult{answer: default_val, valid: true}
	}
	if input.len > 0 {
		return AskResult{answer: input, valid: true}
	}
	return AskResult{valid: false}
}

// confirm asks a yes/no question
pub fn confirm(prompt string) bool {
	return confirm_with_default(prompt, false)
}

// confirm_with_default asks yes/no with a default
pub fn confirm_with_default(prompt string, default_val bool) bool {
	default_str := if default_val { 'Y/n' } else { 'y/N' }
	print('${prompt} [${default_str}]: ')

	input := os.input('').to_lower()
	if input.len == 0 {
		return default_val
	}
	return input == 'y' || input == 'yes'
}

// secret prompts for hidden input (password)
pub fn secret(prompt string) string {
	print('${prompt}: ')
	// Note: V doesn't have built-in terminal echo disable.
	// For production, use os.get_password() or a custom TTY implementation.
	input := os.input('')
	return input
}

// choice presents a list of options and returns the selected index
pub fn choice(prompt string, options []string) int {
	println('${prompt}')
	for i, opt in options {
		println('  [${i}] ${opt}')
	}
	print('Enter choice [0-${options.len - 1}]: ')

	input := os.input('')
	idx := input.int()
	if idx >= 0 && idx < options.len {
		return idx
	}
	return -1
}

// anticipate provides autocomplete input (stub)
pub fn anticipate(prompt string, completions []string) string {
	print('${prompt}: ')
	// In production, would use a library like readline for autocomplete
	input := os.input('')
	return input
}

// ask_required keeps asking until a non-empty answer is given
pub fn ask_required(prompt string) string {
	for {
		result := ask(prompt)
		if result.valid && result.answer.len > 0 {
			return result.answer
		}
		eprintln('  ${red_text('This field is required.')}')
	}
	return '' // unreachable, satisfies compiler
}
