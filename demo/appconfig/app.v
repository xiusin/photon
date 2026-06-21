module appconfig

// config/app.v — 应用元信息配置
//
// 定义应用名称、版本、环境等元信息配置结构。

// AppConfigBlock 应用元信息配置块
pub struct AppConfigBlock {
pub:
	name    string
	version string
	env     string
}

// default_app_config 返回应用元信息默认配置
pub fn default_app_config(profile string) AppConfigBlock {
	return AppConfigBlock{
		name: env_or('APP_NAME', 'PhotonBlog')
		version: env_or('APP_VERSION', '0.1.0')
		env: env_or('APP_PROFILE', profile)
	}
}
