module config

// config/server.v — HTTP 服务器配置
//
// 定义监听主机、端口等 Web 服务器配置。
// 按环境区分：dev 8080，prod 80，test 0（不启动）。

// ServerConfig HTTP 服务器配置
pub struct ServerConfig {
pub:
	host string
	port int
}

// default_server_config 返回指定 profile 的服务器默认配置
pub fn default_server_config(profile string) ServerConfig {
	mut host := env_or('SERVER_HOST', '0.0.0.0')
	mut port := env_or_int('SERVER_PORT', 8080)

	match profile {
		'prod' {
			host = env_or('SERVER_HOST', '0.0.0.0')
			port = env_or_int('SERVER_PORT', 80)
		}
		'test' {
			host = env_or('SERVER_HOST', '127.0.0.1')
			port = env_or_int('SERVER_PORT', 0)
		}
		else {
			host = env_or('SERVER_HOST', '0.0.0.0')
			port = env_or_int('SERVER_PORT', 8080)
		}
	}

	return ServerConfig{
		host: host
		port: port
	}
}
