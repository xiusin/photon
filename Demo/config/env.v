module config

// config/env.v — 环境变量读取辅助函数
//
// 提供 env_or / env_or_int / env_or_bool 三个工具函数，
// 用于从环境变量读取配置值并支持默认值回退。

import os

// env_or 读取字符串环境变量，缺失时返回默认值
pub fn env_or(key string, default_value string) string {
	value := os.getenv(key)
	if value.len == 0 {
		return default_value
	}
	return value
}

// env_or_int 读取整型环境变量，缺失或解析失败时返回默认值
pub fn env_or_int(key string, default_value int) int {
	value := os.getenv(key)
	if value.len == 0 {
		return default_value
	}
	return value.int()
}

// env_or_bool 读取布尔型环境变量，缺失时返回默认值
// 接受 "true"/"1"/"yes"（不区分大小写）作为真值，其余为假值
pub fn env_or_bool(key string, default_value bool) bool {
	value := os.getenv(key)
	if value.len == 0 {
		return default_value
	}
	lower := value.to_lower()
	return lower == 'true' || lower == '1' || lower == 'yes'
}
