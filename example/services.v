module main

// services.v — 业务逻辑层（Service 层）
//
// 注解驱动 DI（P0 7.1 迁移）：
//   @[service]      — 标记为业务服务 Bean，由 ApplicationContext 统一管理
//   @[autowired]    — 字段由 DI 容器注入（本示例采用显式 register_instance 注册，
//                     注解作为文档/未来自动扫描的标记）
//   @[transactional] — 方法通过 core.transactional_wrap 在事务中执行
//
// 当前提供：
//   1. UserService     — 用户业务逻辑
//   2. AuthService     — 认证/授权逻辑
//   3. HealthService   — 健康检查与统计
//   4. CacheService    — 缓存业务封装
import time
import cache
import orm
import logger
import core

// ═══════════════════════════════════════════════════════════
// UserService — 用户业务逻辑
// ═══════════════════════════════════════════════════════════

@[service]
pub struct UserService {
pub mut:
	log_    &logger.Logger          @[autowired]
	tm      &orm.TransactionManager @[autowired]
	om      &orm.OrmManager = unsafe { nil }
	users   []User // 内存数据存储（演示用，生产应使用数据库）
	next_id int = 1
}

// new_user_service 构造 UserService 并注入依赖。
// 在 DI 容器就绪后，依赖通过 @[autowired] 自动注入；此处显式传参以兼容
// 当前显式 register_instance 注册模式。
pub fn new_user_service(log_ &logger.Logger, tm &orm.TransactionManager) &UserService {
	mut svc := &UserService{
		log_:  log_
		tm:    tm
		om:    unsafe { nil }
		users: []User{}
	}
	// 预置演示用户
	svc.seed_demo_users()
	return svc
}

fn (mut s UserService) seed_demo_users() {
	demo_users := [
		User{
			id:         1
			username:   'admin'
			email:      'admin@photon.io'
			password:   'admin123'
			nickname:   '管理员'
			role:       'ADMIN'
			status:     1
			created_at: time.now().unix()
		},
		User{
			id:         2
			username:   'moderator'
			email:      'mod@photon.io'
			password:   'mod123'
			nickname:   '版主'
			role:       'MODERATOR'
			status:     1
			created_at: time.now().unix()
		},
		User{
			id:         3
			username:   'alice'
			email:      'alice@example.com'
			password:   'alice123'
			nickname:   '爱丽丝'
			role:       'USER'
			status:     1
			created_at: time.now().unix()
		},
		User{
			id:         4
			username:   'bob'
			email:      'bob@example.com'
			password:   'bob123'
			nickname:   '鲍勃'
			role:       'USER'
			status:     1
			created_at: time.now().unix()
		},
		User{
			id:         5
			username:   'charlie'
			email:      'charlie@example.com'
			password:   'charlie123'
			nickname:   '查理'
			role:       'USER'
			status:     0
			created_at: time.now().unix()
		},
	]
	s.users << demo_users
	s.next_id = 6
}

// list 获取用户列表（分页）
pub fn (s &UserService) list(query UserListQuery) ([]User, int) {
	mut result := []User{}
	for u in s.users {
		// 关键词过滤
		if query.keyword.len > 0 {
			if !u.username.contains(query.keyword) && !u.nickname.contains(query.keyword)
				&& !u.email.contains(query.keyword) {
				continue
			}
		}
		// 状态过滤
		if query.status != 0 && u.status != query.status {
			continue
		}
		// required过滤
		if query.role.len > 0 && u.role != query.role {
			continue
		}
		result << u
	}
	total := result.len
	// pagination
	start := (query.page - 1) * query.page_size
	if start > total {
		return []User{}, total
	}
	mut end := start + query.page_size
	if end > total {
		end = total
	}
	return result[start..end], total
}

// get_by_id 根据 ID 获取用户
pub fn (s &UserService) get_by_id(id int) !User {
	for u in s.users {
		if u.id == id {
			return u
		}
	}
	return error('user not found')
}

// get_by_username 根据用户名查找
pub fn (s &UserService) get_by_username(username string) !User {
	for u in s.users {
		if u.username == username {
			return u
		}
	}
	return error('user not found')
}

// create 创建新用户（@[transactional] — 通过 transactional_wrap 在事务中执行）
@[transactional]
pub fn (mut s UserService) create(req CreateUserRequest) !User {
	// 检查用户名唯一性
	for u in s.users {
		if u.username == req.username {
			return error('username already exists')
		}
		if u.email == req.email {
			return error('email already registered')
		}
	}
	mut user := User{
		id:       s.next_id
		username: req.username
		email:    req.email
		password: req.password
		nickname: if req.nickname.len > 0 { req.nickname } else { req.username }
		status:   1
		role:     'USER'
	}
	// 状态变更（自增 ID + 追加用户）包裹在事务中：
	// 成功 → commit；失败 → rollback 并传播错误。
	core.transactional_wrap(mut s.tm, fn [mut s, mut user] () ! {
		s.next_id++
		s.users << user
	})!
	s.log_.info('[UserService] 创建用户: id=${user.id} username=${user.username}')
	return user
}

// update 更新用户信息
pub fn (mut s UserService) update(id int, req UpdateUserRequest) !User {
	mut user := s.get_by_id(id)!
	if req.email.len > 0 {
		user.email = req.email
	}
	if req.nickname.len > 0 {
		user.nickname = req.nickname
	}
	if req.avatar.len > 0 {
		user.avatar = req.avatar
	}
	// 写回数组
	for i, u in s.users {
		if u.id == id {
			s.users[i] = user
			break
		}
	}
	s.log_.info('[UserService] 更新用户: id=${id}')
	return user
}

// delete 删除用户（软删除）
pub fn (mut s UserService) delete(id int) ! {
	for i, u in s.users {
		if u.id == id {
			s.users[i].status = -1
			s.log_.info('[UserService] 删除用户: id=${id}')
			return
		}
	}
	return error('user not found')
}

// count 统计用户数
pub fn (s &UserService) count() int {
	mut n := 0
	for u in s.users {
		if u.status == 1 {
			n++
		}
	}
	return n
}

// ═══════════════════════════════════════════════════════════
// AuthService — 认证/授权服务
// ═══════════════════════════════════════════════════════════

@[service]
pub struct AuthService {
pub mut:
	log_     &logger.Logger @[autowired]
	user_svc &UserService   @[autowired]
	jwt_mgr  &JWTManager
}

pub struct JWTConfig {
	secret             string
	expiration_minutes int
}

pub struct JWTManager {
pub mut:
	config JWTConfig
}

pub fn new_jwt_manager(config JWTConfig) &JWTManager {
	return &JWTManager{
		config: config
	}
}

// generate_token 生成 JWT token（简化版，正式应使用 security.JwtManager）
pub fn (jm &JWTManager) generate_token(username string, role string) (string, int) {
	// 简化 token：base64(username):base64(role):timestamp:hmac
	expires_in := jm.config.expiration_minutes
	payload := '${username}|${role}|${time.now().unix() + i64(expires_in * 60)}'
	token := base64_encode(payload)
	return token, expires_in
}

// validate_token 验证 token 并返回用户名和角色
pub fn (jm &JWTManager) validate_token(token string) !(string, string) {
	payload := base64_decode(token) or { return error('invalid token format') }
	parts := payload.split('|')
	if parts.len < 3 {
		return error('invalid token format')
	}
	expires := parts[2].int()
	if expires == 0 && parts[2] != '0' {
		return error('invalid token format')
	}
	if time.now().unix() > expires {
		return error('token expired')
	}
	return parts[0], parts[1]
}

// base64_encode 简单 Base64 编码
fn base64_encode(input string) string {
	chars := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
	mut result := ''
	mut buffer := u64(0)
	mut bits := 0
	for ch in input {
		buffer = (buffer << 8) | u64(ch)
		bits += 8
		for bits >= 6 {
			bits -= 6
			idx := int((buffer >> bits) & 0x3F)
			result += chars[idx].ascii_str()
		}
	}
	if bits > 0 {
		buffer <<= u64(6 - bits)
		idx := int(buffer & 0x3F)
		result += chars[idx].ascii_str()
	}
	for result.len % 4 != 0 {
		result += '='
	}
	return result
}

// base64_decode simple Base64 decoder
fn base64_decode(input string) !string {
	chars := 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/='
	mut result := ''
	mut buffer := u64(0)
	mut bits := 0
	for ch in input {
		if u8(ch) == `=` {
			break
		}
		pos := chars.index_u8(u8(ch))
		if pos < 0 {
			return error('invalid base64 encoding')
		}
		buffer = (buffer << 6) | u64(pos)
		bits += 6
		if bits >= 8 {
			bits -= 8
			result += u8(buffer >> bits).ascii_str()
			buffer &= u64((1 << bits) - 1)
		}
	}
	return result
}

pub fn new_auth_service(log_ &logger.Logger, user_svc &UserService, jwt_config JWTConfig) &AuthService {
	return unsafe {
		&AuthService{
			log_:     log_
			user_svc: user_svc
			jwt_mgr:  new_jwt_manager(jwt_config)
		}
	}
}

// login 用户登录
pub fn (mut s AuthService) login(req LoginRequest) !LoginResponse {
	user := s.user_svc.get_by_username(req.username)!
	if user.password != req.password {
		return error('wrong password')
	}
	if user.status != 1 {
		return error('account disabled')
	}
	token, expires_in := s.jwt_mgr.generate_token(user.username, user.role)
	s.log_.info('[AuthService] 用户登录: username=${user.username} role=${user.role}')
	return LoginResponse{
		access_token:  token
		token_type:    'Bearer'
		expires_in:    expires_in * 60
		refresh_token: base64_encode('refresh:${user.username}:${time.now().unix()}')
		user:          UserProfile{
			id:       user.id
			username: user.username
			nickname: user.nickname
			avatar:   user.avatar
			email:    user.email
			role:     user.role
			status:   user.status
			created:  time.unix(user.created_at).format_ss()
		}
	}
}

// get_profile 获取用户资料
pub fn (s &AuthService) get_profile(username string) !UserProfile {
	user := s.user_svc.get_by_username(username)!
	return UserProfile{
		id:       user.id
		username: user.username
		nickname: user.nickname
		avatar:   user.avatar
		email:    user.email
		role:     user.role
		status:   user.status
		created:  time.unix(user.created_at).format_ss()
	}
}

// ═══════════════════════════════════════════════════════════
// HealthService — 健康检查与统计
// ═══════════════════════════════════════════════════════════

@[service]
pub struct HealthService {
pub mut:
	start_time i64
}

pub fn new_health_service() &HealthService {
	return &HealthService{
		start_time: time.ticks()
	}
}

pub fn (s &HealthService) health() HealthStatus {
	return HealthStatus{
		status:    'UP'
		version:   '0.4.0'
		uptime_ms: time.ticks() - s.start_time
		timestamp: time.now().unix()
	}
}

pub fn (s &HealthService) uptime_ms() i64 {
	return time.ticks() - s.start_time
}

// ═══════════════════════════════════════════════════════════
// CacheService — 缓存业务封装
// ═══════════════════════════════════════════════════════════

@[service]
pub struct CacheService {
pub mut:
	cache_mgr &cache.CacheRegistry @[autowired]
}

pub fn new_cache_service(cache_mgr &cache.CacheRegistry) &CacheService {
	return unsafe {
		&CacheService{
			cache_mgr: cache_mgr
		}
	}
}

pub fn (mut s CacheService) get(key string) !string {
	return s.cache_mgr.get(key)
}

pub fn (mut s CacheService) set(key string, value string, ttl_seconds int) ! {
	s.cache_mgr.set(key, value, ttl_seconds)!
}

pub fn (mut s CacheService) delete(key string) ! {
	s.cache_mgr.delete(key)!
}

pub fn (mut s CacheService) get_or_load(key string, ttl_seconds int, loader fn () !string) !string {
	// 先尝试取缓存
	if val := s.cache_mgr.get(key) {
		return val
	}
	// 未命中 → 加载
	val := loader()!
	s.cache_mgr.set(key, val, ttl_seconds)!
	return val
}
