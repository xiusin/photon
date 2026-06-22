module config

// config/storage.v — 文件存储配置
//
// 定义存储驱动、路径、大小限制、允许扩展名等配置。

// StorageConfigBlock 文件存储配置块
pub struct StorageConfigBlock {
pub:
	driver      string
	base_path   string
	max_size    int
	allowed_ext []string
}

// default_storage_config 返回存储默认配置
pub fn default_storage_config() StorageConfigBlock {
	allowed_ext_str := env_or('STORAGE_ALLOWED_EXT', 'jpg,jpeg,png,gif,webp')
	allowed_ext := allowed_ext_str.split(',').map(it.trim_space()).filter(it.len > 0)

	return StorageConfigBlock{
		driver: env_or('STORAGE_DRIVER', 'local')
		base_path: env_or('STORAGE_BASE_PATH', './storage/uploads')
		max_size: env_or_int('STORAGE_MAX_SIZE', 5242880)
		allowed_ext: allowed_ext
	}
}
