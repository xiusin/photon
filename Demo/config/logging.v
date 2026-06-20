module main

// config/logging.v — 日志配置
//
// 定义日志级别、输出通道（stdout/file）、文件路径、JSON 格式等配置。
// 按环境区分：dev 彩色控制台，prod JSON 文件。

// LoggingConfig 日志配置
pub struct LoggingConfig {
pub:
	level       string
	channel     string // stdout | file
	file_path   string
	json_format bool
}

// default_logging_config 返回指定 profile 的日志默认配置
pub fn default_logging_config(profile string) LoggingConfig {
	mut level := env_or('LOG_LEVEL', 'debug')
	mut channel := env_or('LOG_CHANNEL', 'stdout')
	mut json_format := env_or_bool('LOG_JSON_FORMAT', false)

	match profile {
		'prod' {
			level = env_or('LOG_LEVEL', 'info')
			channel = env_or('LOG_CHANNEL', 'file')
			json_format = env_or_bool('LOG_JSON_FORMAT', true)
		}
		'test' {
			level = env_or('LOG_LEVEL', 'error')
			channel = env_or('LOG_CHANNEL', 'stdout')
			json_format = env_or_bool('LOG_JSON_FORMAT', false)
		}
		else {
			level = env_or('LOG_LEVEL', 'debug')
			channel = env_or('LOG_CHANNEL', 'stdout')
			json_format = env_or_bool('LOG_JSON_FORMAT', false)
		}
	}

	return LoggingConfig{
		level: level
		channel: channel
		file_path: env_or('LOG_FILE_PATH', './storage/logs/app.log')
		json_format: json_format
	}
}
