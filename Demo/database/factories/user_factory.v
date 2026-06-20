module main

// user_factory.v — UserFactory 模型工厂
//
// Laravel 风格的模型工厂，用于测试与种子数据生成。
//
// 用法：
//   // 创建默认 USER 角色用户
//   user := new_user_factory(boot).create()!
//
//   // 创建 ADMIN 用户
//   user := new_user_factory(boot).with_role('ADMIN').create()!
//
//   // 自定义用户名
//   user := new_user_factory(boot).with_username('alice').create()!
//
//   // 仅构建实体不持久化
//   user := new_user_factory(boot).make()

import photon.security
import time

// UserFactory 用户模型工厂
pub struct UserFactory {
pub:
	bootstrap &Bootstrap
mut:
	username string
	email    string
	password string
	nickname string
	role     string
	github   string
}

// new_user_factory 创建用户工厂实例，填充默认随机属性
pub fn new_user_factory(boot &Bootstrap) UserFactory {
	suffix := time.now().unix().str() + '_' + rand_int_str(4)
	return UserFactory{
		bootstrap: boot
		username:  'user_${suffix}'
		email:     'user_${suffix}@factory.dev'
		password:  'Password123!'
		nickname:  'Factory User ${suffix}'
		role:      'USER'
		github:    ''
	}
}

// with_role 设置角色（支持链式调用）
pub fn (f UserFactory) with_role(role string) UserFactory {
	mut result := f
	result.role = role
	return result
}

// with_username 设置用户名（支持链式调用）
pub fn (f UserFactory) with_username(username string) UserFactory {
	mut result := f
	result.username = username
	if result.email.starts_with('user_') {
		result.email = '${username}@factory.dev'
	}
	return result
}

// with_email 设置邮箱（支持链式调用）
pub fn (f UserFactory) with_email(email string) UserFactory {
	mut result := f
	result.email = email
	return result
}

// with_password 设置密码（支持链式调用）
pub fn (f UserFactory) with_password(password string) UserFactory {
	mut result := f
	result.password = password
	return result
}

// with_nickname 设置昵称（支持链式调用）
pub fn (f UserFactory) with_nickname(nickname string) UserFactory {
	mut result := f
	result.nickname = nickname
	return result
}

// with_github 设置 GitHub 用户名（自动获取头像）
pub fn (f UserFactory) with_github(github string) UserFactory {
	mut result := f
	result.github = github
	return result
}

// make 构建用户实体（不持久化），密码已哈希
pub fn (f UserFactory) make() User {
	hasher := security.BcryptHasher{}
	hashed := hasher.make(f.password)
	return User{
		username: f.username
		email:    f.email
		password: hashed
		nickname: if f.nickname.len > 0 { f.nickname } else { f.username }
		avatar:   ''
		status:   1
		role:     f.role
	}
}

// create 持久化用户到数据库并返回实体
//
// 通过 UserService.register() 持久化，自动处理密码哈希、
// 唯一性校验、事件分发。若用户名已存在则返回错误。
pub fn (f UserFactory) create() !User {
	dto := CreateUserDto{
		username: f.username
		email:    f.email
		password: f.password
		nickname: f.nickname
		role:     f.role
		github:   f.github
	}
	mut svc := unsafe { f.bootstrap.user_svc }
	user, _ := svc.register(dto)!
	return user
}

// create_or_first 幂等创建：若用户名已存在则返回已有用户
pub fn (f UserFactory) create_or_first() !User {
	if f.bootstrap.user_repo.exists_by_username(f.username) {
		return f.bootstrap.user_repo.find_by_username(f.username)!
	}
	return f.create()!
}

// rand_int_str 生成指定位数的随机数字字符串
fn rand_int_str(digits int) string {
	mut result := ''
	mut seed := int(time.now().unix())
	for _ in 0 .. digits {
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		result += ((seed >> 16) % 10).str()
	}
	return result
}
