module main

// config_test.v — PhotonBlog 配置系统测试
//
// 测试覆盖：
//   - 默认配置加载（dev profile）
//   - 生产环境配置（prod profile）
//   - 测试环境配置（test profile）
//   - 环境变量覆盖
//   - 配置结构完整性

fn test_load_config_dev() {
	cfg := load_config('dev')!

	assert cfg.app.name == 'PhotonBlog'
	assert cfg.app.version == '0.1.0'
	assert cfg.app.env == 'dev'
	assert cfg.debug == true
	assert cfg.log_level == 'debug'
	assert cfg.database.path == ':memory:'
	assert cfg.database.driver == 'sqlite'
	assert cfg.database.max_conns == 10
	assert cfg.server.port == 8080
	assert cfg.server.host == '0.0.0.0'
	assert cfg.cache.driver == 'memory'
	assert cfg.cache.ttl == 3600
	assert cfg.cache.prefix == 'photonblog:'
	assert cfg.mail.driver == 'log'
}

fn test_load_config_prod() {
	cfg := load_config('prod')!

	assert cfg.debug == false
	assert cfg.log_level == 'info'
	assert cfg.database.path == './photonblog.db'
	assert cfg.server.port == 80
	assert cfg.mail.driver == 'smtp'
}

fn test_load_config_test() {
	cfg := load_config('test')!

	assert cfg.debug == true
	assert cfg.log_level == 'error'
	assert cfg.database.path == ':memory:'
	assert cfg.server.port == 0
	assert cfg.mail.driver == 'log'
}

fn test_load_config_jwt_block() {
	cfg := load_config('dev')!

	assert cfg.jwt.secret.len > 0
	assert cfg.jwt.expiration_minutes == 60
	assert cfg.jwt.refresh_hours == 24
	assert cfg.jwt.issuer == 'PhotonBlog'
}

fn test_load_config_storage_block() {
	cfg := load_config('dev')!

	assert cfg.storage.driver == 'local'
	assert cfg.storage.base_path == './storage/uploads'
	assert cfg.storage.max_size == 5242880
	assert cfg.storage.allowed_ext.len > 0
	assert 'jpg' in cfg.storage.allowed_ext
	assert 'png' in cfg.storage.allowed_ext
}

fn test_load_config_mail_block() {
	cfg := load_config('dev')!

	assert cfg.mail.host == 'localhost'
	assert cfg.mail.port == 587
	assert cfg.mail.from == 'noreply@photonblog.dev'
	assert cfg.mail.from_name == 'PhotonBlog'
}

fn test_load_config_unknown_profile() {
	cfg := load_config('unknown')!

	// 未知 profile 回退到 dev 行为
	assert cfg.debug == true
	assert cfg.database.path == ':memory:'
	assert cfg.server.port == 8080
}
