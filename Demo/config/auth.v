module main

// config/auth.v — 认证授权配置
//
// 定义角色层级（RBAC）等认证配置。
// 角色层级格式：ADMIN>EDITOR>USER（> 表示前者包含后者的所有权限）

// AuthConfig 认证授权配置
pub struct AuthConfig {
pub:
	role_hierarchy string
}

// default_auth_config 返回认证默认配置
pub fn default_auth_config() AuthConfig {
	return AuthConfig{
		role_hierarchy: env_or('AUTH_ROLE_HIERARCHY', 'ADMIN>EDITOR>USER')
	}
}

// parse_role_hierarchy 解析角色层级字符串为 (role, subordinates) 列表
// 格式：ADMIN>EDITOR>USER
// 返回：[('ADMIN', ['EDITOR', 'USER']), ('EDITOR', ['USER']), ('USER', [])]
pub fn parse_role_hierarchy(hierarchy string) [](string, []string) {
	mut result := [](string, []string){}
	roles := hierarchy.split('>').map(it.trim_space()).filter(it.len > 0)
	for i, role in roles {
		mut subordinates := []string{}
		for j in i + 1 .. roles.len {
			subordinates << roles[j]
		}
		result << (role, subordinates)
	}
	return result
}
