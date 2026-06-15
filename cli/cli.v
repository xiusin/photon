module cli

// cli.v - Photon CLI Module Entry
//
// A Laravel/Symfony-inspired console CLI framework for V.
// Provides:
//   - Command registration and dispatch
//   - Argument/option parsing
//   - Styled output with ANSI colors
//   - Built-in commands: serve, list, help, schedule:run, queue:work
//   - Interactive input: ask, confirm, secret, choice
//   - Code generation: make:command, make:controller, make:middleware, etc.
//   - ProgressBar helper
//
// Usage:
//   import photon.cli
//
//   mut app := cli.new_application('myapp', '1.0.0')
//   app.add_command(my_command)
//   app.run() or { panic(err) }
