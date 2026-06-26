module security

// auth_bridge.v — veb.auth 桥接层
//
// 桥接 veb.auth 的密码哈希和 Token 管理能力：
//   - SHA256 + salt 密码哈希
//   - 常量时间比较（防时序攻击）
//   - 加密安全的随机种子
//   - Token 生成与验证工具函数
//
// 与 veb.auth.Auth[T] 的区别：
//   - veb.auth.Auth[T] 需要数据库后端（SQL 存储 Token）
//   - Photon 的 AuthBridge 提供无状态工具函数，Token 存储由用户选择
//   - 可配合 Photon ORM 模块实现完整的有状态 Token 管理
//
// 用法：
//   // 密码哈希
//   salt := security.generate_salt()
//   hashed := security.hash_password('mypassword', salt)
//   ok := security.verify_password('mypassword', salt, hashed)
//
//   // Token 生成
//   token := security.generate_token()
//   ok := security.validate_token_format(token)
import rand
import crypto.rand as crypto_rand
import crypto.hmac
import crypto.sha256

// max_safe_unsigned_integer 用于加密安全随机数生成
const max_safe_unsigned_integer = u32(4_294_967_295)

// AuthBridge 提供无状态的认证工具函数。
// 桥接 veb.auth.Auth[T] 的静态方法部分。
//
// 不包含数据库操作，Token 存储由用户选择（可使用 Photon ORM）。
pub struct AuthBridge {}

// new_auth_bridge 创建认证桥接器。
pub fn new_auth_bridge() AuthBridge {
	return AuthBridge{}
}

// generate_auth_salt 生成随机 salt。
// 桥接 veb.auth.generate_salt()。
//
// 用法：
//   salt := security.generate_auth_salt()
pub fn generate_auth_salt() string {
	return rand.i64().str()
}

// auth_hash_password 使用 SHA256 + salt 哈希密码。
// 桥接 veb.auth.hash_password_with_salt()。
//
// 安全特性：
//   - 使用 SHA256 哈希（不可逆）
//   - 每个用户独立 salt（防彩虹表攻击）
//   - 返回十六进制字符串
//
// 用法：
//   salt := security.generate_auth_salt()
//   hashed := security.auth_hash_password('user_password', salt)
pub fn auth_hash_password(plain_text_password string, salt string) string {
	salted_password := '${plain_text_password}${salt}'
	return sha256.sum(salted_password.bytes()).hex().str()
}

// auth_verify_password 验证密码是否匹配哈希值。
// 桥接 veb.auth.compare_password_with_hash()。
//
// 安全特性：
//   - 使用常量时间比较（hmac.equal）
//   - 防止时序攻击（timing attack）
//
// 用法：
//   ok := security.auth_verify_password('input_password', stored_salt, stored_hash)
pub fn auth_verify_password(plain_text_password string, salt string, hashed string) bool {
	digest := auth_hash_password(plain_text_password, salt)
	// 常量时间比较，防时序攻击
	return hmac.equal(digest.bytes(), hashed.bytes())
}

// generate_token 生成随机认证 Token。
// 桥接 veb.auth.add_token() 中的 UUID v4 生成逻辑。
//
// 用法：
//   token := security.generate_token()
pub fn generate_token() string {
	set_rand_crypto_safe_seed()
	return rand.uuid_v4()
}

// validate_token_format 验证 Token 格式是否合法。
// UUID v4 格式：xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
//
// 用法：
//   if security.validate_token_format(token) {
//       // Token 格式合法
//   }
pub fn validate_token_format(token string) bool {
	if token.len != 36 {
		return false
	}
	// 检查连字符位置
	if token[8] != `-` || token[13] != `-` || token[18] != `-` || token[23] != `-` {
		return false
	}
	// 检查版本号（UUID v4 的第 14 位字符应为 '4'）
	if token[14] != `4` {
		return false
	}
	// 检查变体（第 19 位应为 8, 9, a, b）
	variant := token[19]
	if variant != `8` && variant != `9` && variant != `a` && variant != `b` {
		return false
	}
	return true
}

// set_rand_crypto_safe_seed 使用加密安全的随机数设置全局种子。
// 桥接 veb.auth.set_rand_crypto_safe_seed()。
//
// 在生成 Token 之前调用，确保随机数不可预测。
pub fn set_rand_crypto_safe_seed() {
	first_seed := generate_crypto_safe_int_u32()
	second_seed := generate_crypto_safe_int_u32()
	rand.seed([first_seed, second_seed])
}

// generate_crypto_safe_int_u32 生成加密安全的 u32 随机数。
fn generate_crypto_safe_int_u32() u32 {
	return u32(crypto_rand.int_u64(max_safe_unsigned_integer) or { 0 })
}

// ============================================================
// Token 管理接口（配合 ORM 使用）
// ============================================================

// TokenRepository Token 存储接口。
// 用户可使用 Photon ORM 实现此接口，将 Token 存储到数据库。
//
// 桥接 veb.auth.Auth[T] 的 Token 管理方法。
//
// 用法：
//   struct PgTokenRepository {
//       db &photon.orm.Database
//   }
//   fn (r &PgTokenRepository) save_token(user_id int, token string) ! {
//       // SQL INSERT...
//   }
//   fn (r &PgTokenRepository) find_token(token string) ?int {
//       // SQL SELECT...
//   }
//   fn (r &PgTokenRepository) delete_tokens(user_id int) ! {
//       // SQL DELETE...
//   }
pub interface TokenRepository {
	save_token(user_id int, token string) !
	find_token(token string) ?int
	delete_tokens(user_id int) !
}

// TokenManager 管理 Token 生命周期。
// 桥接 veb.auth.Auth[T] 的有状态 Token 管理。
//
// 用法：
//   repo := &PgTokenRepository{db: db}
//   tm := security.new_token_manager(repo)
//   token := tm.issue_token(42)!
//   user_id := tm.verify_token(token) or { 0 }
//   tm.revoke_tokens(42)!
@[heap]
pub struct TokenManager {
mut:
	repo &TokenRepository = unsafe { nil }
}

// new_token_manager 创建 Token 管理器。
pub fn new_token_manager(repo &TokenRepository) &TokenManager {
	mut tm := &TokenManager{}
	unsafe { tm.repo = repo }
	return tm
}

// issue_token 为用户生成并存储 Token。
// 桥接 veb.auth.Auth[T].add_token()。
pub fn (tm &TokenManager) issue_token(user_id int) !string {
	token := generate_token()
	tm.repo.save_token(user_id, token)!
	return token
}

// verify_token 验证 Token 并返回关联的用户 ID。
// 桥接 veb.auth.Auth[T].find_token()。
pub fn (tm &TokenManager) verify_token(token string) ?int {
	if !validate_token_format(token) {
		return none
	}
	return tm.repo.find_token(token)
}

// revoke_tokens 撤销用户的所有 Token。
// 桥接 veb.auth.Auth[T].delete_tokens()。
pub fn (tm &TokenManager) revoke_tokens(user_id int) ! {
	tm.repo.delete_tokens(user_id)!
}
