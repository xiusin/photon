module main

// providers/auth_service_provider.v — 认证授权服务提供者
//
// 注册 JwtManager 与 RoleHierarchy，角色层级从 config/auth.v 读取（非硬编码）。
//
// Laravel 等价：App\Providers\AuthServiceProvider
// Spring 等价：@EnableWebSecurity + SecurityFilterChain

import photon.core
import photon.security

pub struct AuthServiceProvider {
	ctx &BootContext
}

// new_auth_provider 创建认证授权服务提供者
pub fn new_auth_provider(ctx &BootContext) &AuthServiceProvider {
	return &AuthServiceProvider{
		ctx: ctx
	}
}

// register 创建 JwtManager 与 RoleHierarchy
pub fn (sp &AuthServiceProvider) register(mut app_ctx core.ApplicationContext) ! {
	cfg := sp.ctx.cfg
	log := sp.ctx.log

	// ── JwtManager ──
	jwt_mgr := security.new_jwt_manager(security.JwtConfig{
		secret:                         cfg.jwt.secret
		issuer:                         cfg.jwt.issuer
		expiration_minutes:             cfg.jwt.expiration_minutes
		refresh_token_expiration_hours: cfg.jwt.refresh_hours
	})
	sp.ctx.jwt_mgr = jwt_mgr

	// ── RoleHierarchy（从 config/auth.v 读取，非硬编码） ──
	mut rh := security.new_role_hierarchy()
	// 解析配置中的角色层级字符串（如 "ADMIN>EDITOR>USER"）
	hierarchy_pairs := parse_role_hierarchy(cfg.auth.role_hierarchy)
	for pair in hierarchy_pairs {
		rh.add_role(pair.$0, pair.$1)
	}
	sp.ctx.role_hierarchy = rh
	log.info('JwtManager + RoleHierarchy initialized — ${cfg.auth.role_hierarchy}')

	app_ctx.register_instance('JwtManager', unsafe { voidptr(jwt_mgr) })!
	app_ctx.register_instance('RoleHierarchy', unsafe { voidptr(rh) })!
}

// boot 认证服务无需启动后初始化
pub fn (sp &AuthServiceProvider) boot(mut app_ctx core.ApplicationContext) ! {
}
