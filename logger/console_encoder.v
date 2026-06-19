module logger

// console_encoder.v - Console/Text Encoder (inspired by zap's Console encoder)
//
// Produces human-readable log output with optional color support.
// Format: [timestamp] [LEVEL] [logger_name] [key=value ...] message

// ConsoleEncoder produces human-readable text log output
@[heap]
pub struct ConsoleEncoder {
pub mut:
	config  EncoderConfig
	colored bool // enable ANSI color coding
}

// new_console_encoder creates a ConsoleEncoder with default config
pub fn new_console_encoder() &ConsoleEncoder {
	return &ConsoleEncoder{
		config: EncoderConfig{}
	}
}

// new_console_encoder_with_config creates a ConsoleEncoder with custom config
pub fn new_console_encoder_with_config(config EncoderConfig) &ConsoleEncoder {
	return &ConsoleEncoder{
		config: config
	}
}

// set_colored enables or disables colorized output
pub fn (mut ce ConsoleEncoder) set_colored(colored bool) {
	ce.colored = colored
}

// encode serializes a LogEntry as a plain text line
pub fn (ce &ConsoleEncoder) encode(entry &LogEntry) string {
	cfg := &ce.config
	ts := fmt_time(entry.timestamp, cfg.time_format)

	level_str := if ce.colored {
		colorize_level(entry.level)
	} else {
		entry.level.str()
	}

	// Build context string from fields
	mut ctx_str := ''
	if entry.fields.len > 0 {
		mut pairs := []string{}
		for k, v in entry.fields {
			pairs << '${k}=${v}'
		}
		ctx_str = ' [${pairs.join(' ')}]'
	}

	return '[${ts}] [${level_str}] [${entry.logger_name}]${ctx_str} ${entry.message}'
}

// config returns a reference to the encoder config
pub fn (ce &ConsoleEncoder) config() &EncoderConfig {
	return &ce.config
}

// clone returns a copy of the encoder (implements Encoder interface)
pub fn (ce &ConsoleEncoder) clone() &Encoder {
	return &ConsoleEncoder{
		config:  ce.config
		colored: ce.colored
	}
}

// ============================================================
// ANSI Color Support — Precomputed level strings
// ============================================================

const color_debug = '\x1b[90mDEBUG\x1b[0m'
const color_info = '\x1b[36mINFO\x1b[0m'
const color_warn = '\x1b[33mWARN\x1b[0m'
const color_error = '\x1b[31mERROR\x1b[0m'
const color_fatal = '\x1b[31mFATAL\x1b[0m'

@[inline]
fn colorize_level(level Level) string {
	return match level {
		.debug { color_debug }
		.info { color_info }
		.warn { color_warn }
		.error { color_error }
		.fatal { color_fatal }
	}
}
