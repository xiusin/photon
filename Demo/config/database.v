module main

// config/database.v — 数据库配置
//
// 定义数据库驱动、路径、连接池等配置。
// 支持 ${DB_PATH} 占位符，由 .env 文件提供实际值。

// DatabaseConfig 数据库配置
pub struct DatabaseConfig {
pub:
	driver    string
	path      string
	max_conns int
}

// default_database_config 返回指定 profile 的数据库默认配置
pub fn default_database_config(profile string) DatabaseConfig {
	mut path := env_or('DB_PATH', ':memory:')
	mut max_conns := env_or_int('DB_MAX_CONNS', 10)

	match profile {
		'dev' {
			path = env_or('DB_PATH', ':memory:')
		}
		'prod' {
			path = env_or('DB_PATH', './photonblog.db')
			max_conns = env_or_int('DB_MAX_CONNS', 20)
		}
		'test' {
			path = env_or('DB_PATH', ':memory:')
			max_conns = env_or_int('DB_MAX_CONNS', 5)
		}
		else {
			path = env_or('DB_PATH', ':memory:')
		}
	}

	return DatabaseConfig{
		driver: env_or('DB_DRIVER', 'sqlite')
		path: path
		max_conns: max_conns
	}
}
