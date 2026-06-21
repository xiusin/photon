module config

import os

// env_or 读取环境变量，不存在时返回默认值
pub fn env_or(key string, default_val string) string {
	val := os.getenv(key)
	if val == '' {
		return default_val
	}
	return val
}

// env_or_int 读取环境变量为 int，不存在或无效时返回默认值
pub fn env_or_int(key string, default_val int) int {
	val := os.getenv(key)
	if val == '' {
		return default_val
	}
	return val.int()
}

// env_or_bool 读取环境变量为 bool，不存在时返回默认值
pub fn env_or_bool(key string, default_val bool) bool {
	val := os.getenv(key)
	if val == '' {
		return default_val
	}
	return val in ['true', '1', 'yes', 'on', 'True', 'TRUE']
}
