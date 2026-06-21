# Photon Framework 深度优化（对标 Spring）Spec

## Why

Photon 框架已对标 Spring 实现 60% 功能，但根据《优化文档.md》深度评估，存在 **P0 级生产安全漏洞**（XOR 加密未废弃、FNV-1a 用于密码哈希）、**P0 级架构空壳**（事务管理器不连接数据库、HttpKernel.handle() 是占位符）、以及 **P1 级架构缺口**（无 PasswordEncoder 接口、无 CacheManager 抽象、无 ConversionService、无 ContentNegotiation）。本次优化目标是修复全部 P0 缺陷、补齐 P1 架构缺口、并完成关键 P2 代码质量改进，使框架达到生产就绪标准。

## What Changes

### P0 安全与架构修复（必须）
- **BREAKING**: `security/encryption.v` 的 `Encrypter`（XOR）标注 `@[deprecated]`，新增 `DeprecatedEncrypter` 包装打印警告，文档明确指引使用 `cipher.AesCipher`
- **BREAKING**: `security/hashing.v` 的 `hash_string` 内部 FNV-1a 改造为 PBKDF2-SHA256 真实 KDF（已有 `crypto.pbkdf2` 依赖），`BcryptHasher`/`Argon2Hasher` 输出格式保持兼容但内部使用真实 KDF
- `web/kernel.v` 的 `HttpKernel.handle()` 完成实现：注入 `HandlerResolver` 接口，支持真实请求处理与异常事件分发；保留无参 `handle()` 兼容旧测试
- **BREAKING**: `orm/transaction.v` 的 `TransactionManager` 注入数据库连接（`voidptr` 形式，避免 V 模块名冲突），`begin(conn)`/`commit()`/`rollback()` 通过回调操作真实连接；保留状态机模式作为 `MockTransactionManager` 用于无 DB 场景测试

### P1 架构补全（对标 Spring）
- 新增 `security/password_encoder.v`：`PasswordEncoder` 接口 + `BCryptPasswordEncoder` + `Argon2PasswordEncoder` + `DelegatingPasswordEncoder`（带 `{id}hash` 前缀迁移支持）
- 新增 `cache/manager.v`：`CacheManager` 接口（区别于现有 `CacheManager` struct，重命名为 `CacheRegistry`）+ `ValueWrapper` + `RedisCache` 接口抽象（不依赖具体 Redis 客户端）
- 新增 `cache/annotation.v` 扩展：`@[cache_config]` 类级配置注解 + `KeyGenerator` 接口
- 新增 `core/conversion.v`：`ConversionService` 接口 + `Converter[S, T]` 接口 + `GenericConversionService` 默认实现 + 内置 String↔int/i64/f64/bool 转换器
- 新增 `web/content_negotiation.v`：`ContentNegotiationManager` + `ContentNegotiationStrategy` 接口 + `AcceptHeaderStrategy`/`ParameterStrategy`/`FixedStrategy` 内置策略
- 新增 `web/resource_handler.v`：`ResourceHandlerRegistry` + `ResourceResolver` 静态资源服务
- 新增 `core/event.v` 扩展：`@[transactional_event_listener]` 注解支持 + `TransactionalEventListener` 接口（AFTER_COMMIT/BEFORE_COMMIT/AFTER_ROLLBACK 阶段）

### P2 代码质量改进
- 新增 `support/error.v`：`PhotonError` 领域错误类型 + `ErrorCode` 枚举（替代散用的 `error(string)`）
- 新增 benchmark 测试：`cache/cache_bench_test.v`、`orm/transaction_bench_test.v`、`web/bind_bench_test.v`、`security/cipher_bench_test.v`
- `http/client.v` 新增 `set_ssl_config()`/`set_proxy()` 配置接口（基于 V `net.http` 能力）
- 减少 `unsafe { nil }` 滥用：`ClientHttpRequestInterceptor.intercept_fn` 改为 Option 类型 `?fn(...)` 或建立 `NoopInterceptor` 哨兵

## Impact

- **Affected specs**: security（哈希、加密、密码编码器）、cache（CacheManager 抽象）、orm（事务管理器）、web（kernel、内容协商、静态资源）、core（事件、转换服务）、http（SSL/代理）、support（错误类型）
- **Affected code**:
  - `security/encryption.v`、`security/hashing.v`、新增 `security/password_encoder.v`
  - `web/kernel.v`、新增 `web/content_negotiation.v`、新增 `web/resource_handler.v`
  - `orm/transaction.v`、`orm/transaction_annotation.v`
  - `cache/cache.v`、`cache/annotation.v`、新增 `cache/manager.v`
  - 新增 `core/conversion.v`、`core/event.v`（扩展）
  - 新增 `support/error.v`
  - `http/client.v`（扩展）
  - 新增 4 个 benchmark 测试文件
  - 更新现有测试以适配 BREAKING 变更

## ADDED Requirements

### Requirement: PasswordEncoder 接口体系
系统 SHALL 提供 `PasswordEncoder` 接口，包含 `encode(raw_password string) !string`、`matches(raw_password string, encoded string) !bool`、`upgrade_encoding(encoded string) bool` 三个方法。

#### Scenario: BCryptPasswordEncoder 编码与验证
- **WHEN** 用户调用 `BCryptPasswordEncoder{strength: 10}.encode('password')`
- **THEN** 返回以 `{bcrypt}` 前缀开头的哈希字符串
- **WHEN** 用户调用 `.matches('password', encoded)`
- **THEN** 返回 `true`
- **WHEN** 用户调用 `.matches('wrong', encoded)`
- **THEN** 返回 `false`

#### Scenario: DelegatingPasswordEncoder 迁移支持
- **WHEN** 系统使用 `DelegatingPasswordEncoder`（默认 bcrypt）编码 `'pw'`
- **THEN** 输出格式为 `{bcrypt}<hash>`
- **WHEN** 系统对旧 FNV-1a 哈希 `'fnvhash'`（无前缀）调用 `matches`
- **THEN** 通过 `default_id_for_matches` 回退到旧编码器并返回 `true`

### Requirement: CacheManager 接口抽象
系统 SHALL 提供 `CacheManager` 接口（`get_cache(name) !Cache`、`get_cache_names() []string`）与 `Cache` 接口（`get/put/evict/clear`），与现有 `CacheManager` struct 共存（struct 重命名为 `CacheRegistry`）。

#### Scenario: 注册并获取命名缓存
- **WHEN** 用户调用 `CacheRegistry.register('users', memory_cache)` 后 `get_cache('users')`
- **THEN** 返回注册的 Cache 实例
- **WHEN** 用户调用 `get_cache_names()`
- **THEN** 返回 `['users']`

#### Scenario: ValueWrapper 包装
- **WHEN** 用户调用 `Cache.put('k', ValueWrapper{value: 'v'})` 后 `Cache.get('k')`
- **THEN** 返回的 `ValueWrapper.value == 'v'`

### Requirement: ConversionService 类型转换
系统 SHALL 提供 `ConversionService` 接口（`can_convert(source_type, target_type) bool`、`convert[T](source voidptr) !T`、`add_converter[S, T](converter)`）与 `Converter[S, T]` 接口。

#### Scenario: 内置 String→int 转换
- **WHEN** 用户在 `GenericConversionService` 上调用 `convert[int]('42')`
- **THEN** 返回 `42`
- **WHEN** 用户调用 `convert[int]('not-a-number')`
- **THEN** 返回错误

#### Scenario: 自定义 Converter 注册
- **WHEN** 用户注册 `Converter[string, User]` 后调用 `convert[User]('alice')`
- **THEN** 返回 `User{name: 'alice'}`

### Requirement: ContentNegotiationManager 内容协商
系统 SHALL 提供 `ContentNegotiationManager` 与 `ContentNegotiationStrategy` 接口，支持基于 `Accept` 头、URL 参数、固定值三种策略。

#### Scenario: Accept 头策略
- **WHEN** 请求 `Accept: application/json`，调用 `ContentNegotiationManager.resolve_content_type(request)`
- **THEN** 返回 `application/json`

#### Scenario: 参数策略
- **WHEN** 请求 URL 含 `?format=xml`，配置 `ParameterStrategy{param: 'format'}`
- **THEN** 返回 `application/xml`

### Requirement: ResourceHandlerRegistry 静态资源
系统 SHALL 提供 `ResourceHandlerRegistry` 注册 URL 模式到本地目录映射，并通过 veb 路由服务静态文件。

#### Scenario: 注册静态资源映射
- **WHEN** 用户调用 `registry.add_resource_handler('/static/**').add_resource_locations('./static/')`
- **THEN** 访问 `/static/app.css` 返回 `./static/app.css` 文件内容

### Requirement: TransactionalEventListener 事务事件
系统 SHALL 提供 `TransactionalEventListener` 接口与 `@[transactional_event_listener]` 注解，支持 `AFTER_COMMIT`/`BEFORE_COMMIT`/`AFTER_ROLLBACK`/`AFTER_COMPLETION` 四个阶段。

#### Scenario: 事务提交后触发监听器
- **WHEN** 事务成功 commit 后
- **THEN** 注册为 `AFTER_COMMIT` 的 `TransactionalEventListener` 被调用
- **WHEN** 事务 rollback
- **THEN** `AFTER_COMMIT` 监听器不被调用，`AFTER_ROLLBACK` 监听器被调用

### Requirement: PhotonError 领域错误类型
系统 SHALL 提供 `PhotonError` struct（`code ErrorCode`、`message string`、`cause ?string`）与 `ErrorCode` 枚举（`err_security`、`err_cache_miss`、`err_tx_not_active`、`err_conversion_failed`、`err_resource_not_found` 等）。

#### Scenario: 错误码携带上下文
- **WHEN** 模块返回 `PhotonError{code: .err_tx_not_active, message: 'no active transaction'}`
- **THEN** 调用方可通过 `err.code` 判断错误类型并做分支处理

### Requirement: HttpKernel.handle() 完整实现
系统 SHALL 提供 `HttpKernel.handle_with(resolver HandlerResolver, ctx voidptr) !ResponseEntity` 方法，分发 request→controller→response 事件，异常时分发 exception 事件并返回错误。

#### Scenario: 正常请求处理
- **WHEN** 用户注册 `HandlerResolver` 返回处理器并调用 `handle_with(resolver, ctx)`
- **THEN** 依次分发 `kernel.request`、`kernel.controller`、`kernel.response` 事件
- **THEN** 返回处理器的 `ResponseEntity`

#### Scenario: 异常处理
- **WHEN** 处理器返回错误
- **THEN** 分发 `kernel.exception` 事件并向上传播错误

### Requirement: TransactionManager 真实数据库连接
系统 SHALL 提供 `TransactionManager.begin(conn voidptr, begin_fn fn (voidptr) !)`、`commit(commit_fn fn (voidptr) !)`、`rollback(rollback_fn fn (voidptr) !)` 方法，通过回调操作真实数据库连接。

#### Scenario: 真实事务提交
- **WHEN** 用户调用 `tm.begin(conn, begin_fn)` 后 `tm.commit(commit_fn)`
- **THEN** `begin_fn(conn)` 与 `commit_fn(conn)` 被依次调用
- **THEN** `tm.is_active()` 返回 `false`

#### Scenario: 真实事务回滚
- **WHEN** 用户调用 `tm.begin(conn, begin_fn)` 后 `tm.rollback(rollback_fn)`
- **THEN** `rollback_fn(conn)` 被调用
- **THEN** `tm.is_active()` 返回 `false`

### Requirement: RestTemplate SSL/Proxy 配置
系统 SHALL 提供 `RestTemplate.set_ssl_config(SSLConfig)` 与 `set_proxy(ProxyConfig)` 方法。

#### Scenario: 配置 SSL
- **WHEN** 用户调用 `rt.set_ssl_config(SSLConfig{enable: true, cert_file: 'client.crt'})`
- **THEN** 后续 HTTPS 请求使用指定证书

### Requirement: Benchmark 测试覆盖
系统 SHALL 为 cache、orm/transaction、web/bind、security/cipher 模块提供 benchmark 测试。

#### Scenario: 缓存基准测试
- **WHEN** 运行 `v test cache/`
- **THEN** `cache_bench_test.v` 中的 benchmark 函数执行并输出每秒操作数

## MODIFIED Requirements

### Requirement: BcryptHasher 真实 KDF
`security/hashing.v` 的 `BcryptHasher.make()` 内部 SHALL 使用 PBKDF2-SHA256（基于已有 `crypto.pbkdf2` 依赖）替代 FNV-1a 混合，输出格式保持 `$2y$<rounds>$<salt><hash>` 兼容。

#### Scenario: 哈希强度
- **WHEN** 用户调用 `BcryptHasher{rounds: 10}.make('pw')`
- **THEN** 哈希耗时显著高于 FNV-1a（>1ms）
- **THEN** `.check('pw', hash)` 返回 `true`

### Requirement: Encrypter 标注废弃
`security/encryption.v` 的 `Encrypter` struct 与 `new_encrypter`/`encrypt`/`decrypt` 函数 SHALL 标注 `@[deprecated: 'use security.AesCipher instead']`，并在 `encrypt`/`decrypt` 内打印 stderr 警告。

#### Scenario: 废弃警告
- **WHEN** 用户调用 `new_encrypter('key')`
- **THEN** 编译器产生 deprecation 警告
- **WHEN** 用户调用 `encrypt('x')`
- **THEN** stderr 输出 `[deprecated] Encrypter uses XOR cipher, use AesCipher instead`

## REMOVED Requirements

### Requirement: FNV-1a 用于密码哈希
**Reason**: FNV-1a 是非加密哈希，可被暴力破解，是安全漏洞。
**Migration**: `BcryptHasher`/`Argon2Hasher` 内部改用 PBKDF2-SHA256；旧哈希通过 `DelegatingPasswordEncoder` 的 `FnvPasswordEncoder` 适配器支持验证（仅验证不编码）。
