module logger

// json_encoder.v - JSON Encoder (inspired by zap's JSON encoder)
//
// Produces structured JSON log output. Each log entry is a single JSON
// object line for easy parsing by log aggregators (ELK, Loki, etc.).

// JSONEncoder produces structured JSON log output
@[heap]
pub struct JSONEncoder {
pub mut:
	config EncoderConfig
}

// new_json_encoder creates a JSONEncoder with default config
pub fn new_json_encoder() &JSONEncoder {
	return &JSONEncoder{
		config: EncoderConfig{}
	}
}

// new_json_encoder_with_config creates a JSONEncoder with custom config
pub fn new_json_encoder_with_config(config EncoderConfig) &JSONEncoder {
	return &JSONEncoder{
		config: config
	}
}

// encode serializes a LogEntry as JSON
pub fn (je &JSONEncoder) encode(entry &LogEntry) string {
	cfg := &je.config

	mut parts := []string{cap: 4 + entry.fields.len}
	parts << '"${cfg.time_key}":"${fmt_time(entry.timestamp, cfg.time_format)}"'
	parts << '"${cfg.level_key}":"${entry.level.str()}"'
	parts << '"${cfg.name_key}":"${entry.logger_name}"'
	parts << '"${cfg.message_key}":"${escape_json(entry.message)}"'

	for key, value in entry.fields {
		parts << '"${key}":"${escape_json(value)}"'
	}

	return '{${parts.join(',')}}'
}

// config returns a reference to the encoder config
pub fn (je &JSONEncoder) config() &EncoderConfig {
	return &je.config
}

// clone returns a copy of the encoder
pub fn (je &JSONEncoder) clone() &Encoder {
	return &JSONEncoder{
		config: je.config
	}
}

// ============================================================
// JSON escaping helpers
// ============================================================

fn escape_json(s string) string {
	// Pre-allocate with worst-case estimate (each char could become 2 chars for escaping)
	mut buf := []u8{cap: s.len * 2}
	for ch in s {
		match ch {
			`"` {
				buf << `\\`
				buf << `"`
			}
			`\\` {
				buf << `\\`
				buf << `\\`
			}
			`\n` {
				buf << `\\`
				buf << `n`
			}
			`\r` {
				buf << `\\`
				buf << `r`
			}
			`\t` {
				buf << `\\`
				buf << `t`
			}
			else {
				buf << u8(ch)
			}
		}
	}
	return buf.bytestr()
}
