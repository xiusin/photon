# Tasks

## 阶段 1：P0 安全与架构修复

- [x] Task 1: 废弃 XOR Encrypter 并新增 DeprecatedEncrypter 包装
  - [x] SubTask 1.1: 为 `security/encryption.v` 的 `Encrypter` struct、`new_encrypter`、`encrypt`、`decrypt` 添加 `@[deprecated: 'use security.AesCipher instead']` 属性
  - [x] SubTask 1.2: 在 `encrypt`/`decrypt` 函数体首行添加 `eprintln('[deprecated] Encrypter uses XOR cipher, use security.AesCipher instead')`
  - [x] SubTask 1.3: 更新 `security/encryption_test.v`，保留现有测试但添加注释说明废弃状态
  - [x] SubTask 1.4: 运行 `v test security/` 验证通过

- [x] Task 2: 修复 BcryptHasher/Argon2Hasher 使用真实 KDF
  - [x] SubTask 2.1: 重写 `security/hashing.v` 的 `hash_string` 函数，改用 `crypto.pbkdf2` + `crypto.sha256` 进行真实密钥派生（迭代次数 = rounds * 1000）
  - [x] SubTask 2.2: 保持 `$2y$<rounds>$<salt><hash>` 与 `$argon2id$v=19$m=...,t=...,p=...$<salt>$<hash>` 输出格式兼容
  - [x] SubTask 2.3: 验证 `BcryptHasher.check` 与 `Argon2Hasher.check` 仍能正确验证旧格式哈希
  - [x] SubTask 2.4: 更新 `security/hashing_test.v` 测试用例（确保 `make`+`check` 往返一致）
  - [x] SubTask 2.5: 运行 `v test security/` 验证通过

- [x] Task 3: 完成 HttpKernel.handle() 实现
  - [x] SubTask 3.1: 在 `web/kernel.v` 新增 `HandlerResolver` 接口（`resolve(ctx voidptr) !HandlerFn`）与 `HandlerFn` 类型（`fn (ctx voidptr) !voidptr`）
  - [x] SubTask 3.2: 新增 `handle_with(resolver HandlerResolver, ctx voidptr) !voidptr` 方法：分发 request→controller→response，异常时分发 exception
  - [x] SubTask 3.3: 保留无参 `handle()` 方法用于向后兼容（仅分发事件，不调用 resolver）
  - [x] SubTask 3.4: 更新 `web/web_ext_test.v` 添加 `handle_with` 测试用例（mock resolver 返回成功/失败两种场景）
  - [x] SubTask 3.5: 运行 `v test web/` 验证通过

- [x] Task 4: TransactionManager 注入真实数据库连接
  - [x] SubTask 4.1: 在 `orm/transaction.v` 的 `TransactionManager` 添加 `conn voidptr`、`begin_fn fn (voidptr) !`、`commit_fn fn (voidptr) !`、`rollback_fn fn (voidptr) !` 字段
  - [x] SubTask 4.2: 新增 `begin(conn voidptr, begin_fn fn (voidptr) !) !` 方法：调用 `begin_fn(conn)` 并设置 `active = true`
  - [x] SubTask 4.3: 新增 `commit() !` 方法：调用 `commit_fn(conn)` 并设置 `active = false`（保持旧签名兼容，若 `commit_fn` 为 nil 则仅切换状态）
  - [x] SubTask 4.4: 新增 `rollback() !` 方法：调用 `rollback_fn(conn)` 并设置 `active = false`
  - [x] SubTask 4.5: 更新 `execute(propagation, f)` 方法以使用新的 begin/commit/rollback 签名
  - [x] SubTask 4.6: 保留 `new_transaction_manager()` 无参构造（无 DB 场景，纯状态机模式）
  - [x] SubTask 4.7: 更新 `orm/transaction_test.v` 添加真实连接回调测试（mock begin/commit/rollback 函数）
  - [x] SubTask 4.8: 运行 `v test orm/` 验证通过

## 阶段 2：P1 架构补全

- [x] Task 5: 新增 PasswordEncoder 接口体系
  - [x] SubTask 5.1: 创建 `security/password_encoder.v`，定义 `PasswordEncoder` 接口（`encode/!string`、`matches/!bool`、`upgrade_encoding/bool`）
  - [x] SubTask 5.2: 实现 `BCryptPasswordEncoder`（基于 `BcryptHasher`，输出 `{bcrypt}<hash>` 前缀格式）
  - [x] SubTask 5.3: 实现 `Argon2PasswordEncoder`（基于 `Argon2Hasher`，输出 `{argon2id}<hash>` 前缀格式）
  - [x] SubTask 5.4: 实现 `FnvPasswordEncoder`（适配旧 FNV-1a 哈希，仅用于 `matches` 验证，`encode` 返回错误提示升级）
  - [x] SubTask 5.5: 实现 `DelegatingPasswordEncoder`（`default_encoder`、`encoders map[string]PasswordEncoder`、`id_for_encode` 字段，`encode` 输出 `{id}hash`，`matches` 解析前缀路由）
  - [x] SubTask 5.6: 创建 `security/password_encoder_test.v` 测试所有编码器的 encode/matches/upgrade_encoding 往返
  - [x] SubTask 5.7: 运行 `v test security/` 验证通过

- [x] Task 6: 新增 CacheManager 接口抽象
  - [x] SubTask 6.1: 创建 `cache/manager.v`，定义 `CacheManager` 接口（`get_cache(name) !&NamedCache`、`get_cache_names() []string`）
  - [x] SubTask 6.2: 定义 `NamedCache` 接口（`get/!ValueWrapper`、`put/!`、`evict/!`、`clear/!`）与 `ValueWrapper` struct
  - [x] SubTask 6.3: 将现有 `cache/cache.v` 的 `CacheManager` struct 重命名为 `CacheRegistry`，实现新的 `CacheManager` 接口
  - [x] SubTask 6.4: 定义 `RedisCache` 接口（`get/set/del/expire` 抽象方法，不依赖具体 Redis 客户端）
  - [x] SubTask 6.5: 更新 `cache/cache.v` 中所有引用 `CacheManager` struct 的地方为 `CacheRegistry`
  - [x] SubTask 6.6: 更新 `cache/annotation.v` 的 `CacheableInterceptor.cache_manager` 字段类型为 `&CacheRegistry`
  - [x] SubTask 6.7: 更新 `cache/cache_test.v` 测试用例适配重命名
  - [x] SubTask 6.8: 创建 `cache/manager_test.v` 测试 CacheRegistry 实现 CacheManager 接口
  - [x] SubTask 6.9: 运行 `v test cache/` 验证通过

- [x] Task 7: 扩展 cache 注解（@[cache_config] + KeyGenerator）
  - [x] SubTask 7.1: 在 `cache/annotation.v` 新增 `CacheConfigAttribute` struct（`cache_names []string`、`key_generator string`）
  - [x] SubTask 7.2: 新增 `parse_cache_config_attr(attr string) CacheConfigAttribute` 解析函数
  - [x] SubTask 7.3: 定义 `KeyGenerator` 接口（`generate(method_name string, args ...string) string`）
  - [x] SubTask 7.4: 实现 `SimpleKeyGenerator`（默认：`method_name::arg1,arg2,...`）
  - [x] SubTask 7.5: 创建 `cache/annotation_config_test.v` 测试
  - [x] SubTask 7.6: 运行 `v test cache/` 验证通过

- [x] Task 8: 新增 ConversionService 类型转换
  - [x] SubTask 8.1: 创建 `core/conversion.v`，定义 `Converter[S, T]` 接口（`convert(source S) !T`）
  - [x] SubTask 8.2: 定义 `ConversionService` 接口（`can_convert(source_type, target_type string) bool`、`convert[T](source voidptr) !T`、`add_converter[S, T](converter Converter[S, T])`）
  - [x] SubTask 8.3: 实现 `GenericConversionService`：内部 `map[string]voidptr` 存储转换器（key = `source_type->target_type`）
  - [x] SubTask 8.4: 实现内置转换器：`StringToIntConverter`、`StringToI64Converter`、`StringToF64Converter`、`StringToBoolConverter`
  - [x] SubTask 8.5: 创建 `core/conversion_test.v` 测试内置转换器与自定义转换器注册
  - [x] SubTask 8.6: 运行 `v test core/` 验证通过

- [x] Task 9: 新增 ContentNegotiationManager 内容协商
  - [x] SubTask 9.1: 创建 `web/content_negotiation.v`，定义 `ContentNegotiationStrategy` 接口（`resolve_content_type(accept_header string, params map[string]string) !string`）
  - [x] SubTask 9.2: 实现 `AcceptHeaderStrategy`（解析 `Accept` 头，返回最高优先级媒体类型）
  - [x] SubTask 9.3: 实现 `ParameterStrategy`（从 URL 参数读取，如 `?format=xml`）
  - [x] SubTask 9.4: 实现 `FixedStrategy`（返回固定媒体类型）
  - [x] SubTask 9.5: 实现 `ContentNegotiationManager`（持有 `strategies []ContentNegotiationStrategy`，按顺序尝试直到成功）
  - [x] SubTask 9.6: 创建 `web/content_negotiation_test.v` 测试三种策略
  - [x] SubTask 9.7: 运行 `v test web/` 验证通过

- [x] Task 10: 新增 ResourceHandlerRegistry 静态资源
  - [x] SubTask 10.1: 创建 `web/resource_handler.v`，定义 `ResourceHandlerMapping` struct（`pattern string`、`locations []string`）
  - [x] SubTask 10.2: 定义 `ResourceHandlerRegistry` struct（`mappings []ResourceHandlerMapping`）与 `add_resource_handler(pattern string)` 链式方法
  - [x] SubTask 10.3: 实现 `resolve(path string) ?string` 方法：匹配 pattern，返回第一个存在的文件路径
  - [x] SubTask 10.4: 实现 `serve(path string) !string` 方法：读取文件内容并返回
  - [x] SubTask 10.5: 创建 `web/resource_handler_test.v` 测试（使用临时目录创建测试文件）
  - [x] SubTask 10.6: 运行 `v test web/` 验证通过

- [x] Task 11: 新增 TransactionalEventListener 事务事件
  - [x] SubTask 11.1: 在 `core/event.v` 新增 `TransactionPhase` 枚举（`before_commit`、`after_commit`、`after_rollback`、`after_completion`）
  - [x] SubTask 11.2: 定义 `TransactionalEventListener` 接口（`phase() TransactionPhase`、`handle(event &Event)`）
  - [x] SubTask 11.3: 在 `EventBus` 新增 `on_transactional(event_name string, listener TransactionalEventListener)` 方法
  - [x] SubTask 11.4: 在 `EventBus` 新增 `dispatch_transactional(event &Event, phase TransactionPhase) int` 方法
  - [x] SubTask 11.5: 在 `orm/transaction_annotation.v` 新增 `parse_transactional_event_listener_attr(attr string) TransactionPhase` 解析函数
  - [x] SubTask 11.6: 创建 `core/event_transactional_test.v` 测试四个阶段触发
  - [x] SubTask 11.7: 运行 `v test core/` 与 `v test orm/` 验证通过

## 阶段 3：P2 代码质量改进

- [x] Task 12: 新增 PhotonError 领域错误类型
  - [x] SubTask 12.1: 创建 `support/error.v`，定义 `ErrorCode` 枚举（`err_security`、`err_cache_miss`、`err_cache_set`、`err_tx_not_active`、`err_tx_already_active`、`err_conversion_failed`、`err_resource_not_found`、`err_invalid_argument`、`err_not_implemented`）
  - [x] SubTask 12.2: 定义 `PhotonError` struct（`code ErrorCode`、`message string`、`cause ?string`）实现 `str()` 与 `IError` 接口（若 V 支持）
  - [x] SubTask 12.3: 提供构造函数 `new_photon_error(code ErrorCode, message string) PhotonError` 与 `new_photon_error_with_cause(code, message, cause) PhotonError`
  - [x] SubTask 12.4: 创建 `support/error_test.v` 测试
  - [x] SubTask 12.5: 运行 `v test support/` 验证通过

- [x] Task 13: 新增 benchmark 测试
  - [x] SubTask 13.1: 创建 `cache/cache_bench_test.v`：benchmark `MemoryCache.set`/`get`/`CacheManager.get_or_load`（含 singleflight）
  - [x] SubTask 13.2: 创建 `orm/transaction_bench_test.v`：benchmark `TransactionManager.execute(.required)` 嵌套调用
  - [x] SubTask 13.3: 创建 `web/bind_bench_test.v`：benchmark `web.bind[LoginDto]` 与 `web.bind_json[CreateUserDto]`
  - [x] SubTask 13.4: 创建 `security/cipher_bench_test.v`：benchmark `AesCipher.encrypt`/`decrypt` 与 `BcryptHasher.make`/`check`
  - [x] SubTask 13.5: 运行 `v test cache/ orm/ web/ security/` 验证 benchmark 函数可执行

- [x] Task 14: RestTemplate SSL/Proxy 配置
  - [x] SubTask 14.1: 在 `http/client.v` 新增 `SSLConfig` struct（`enable bool`、`cert_file string`、`key_file string`、`ca_file string`、`insecure_skip_verify bool`）
  - [x] SubTask 14.2: 新增 `ProxyConfig` struct（`host string`、`port int`、`username string`、`password string`）
  - [x] SubTask 14.3: 在 `RestTemplate` 新增 `ssl_config ?SSLConfig` 与 `proxy_config ?ProxyConfig` 字段
  - [x] SubTask 14.4: 新增 `set_ssl_config(SSLConfig) RestTemplate` 与 `set_proxy(ProxyConfig) RestTemplate` 链式方法
  - [x] SubTask 14.5: 在 `execute(entity)` 方法中应用 SSL/Proxy 配置到 V `net.http` 客户端
  - [x] SubTask 14.6: 创建 `http/ssl_proxy_test.v` 测试配置链式调用与字段赋值
  - [x] SubTask 14.7: 运行 `v test http/` 验证通过

- [x] Task 15: 减少 unsafe { nil } 滥用
  - [x] SubTask 15.1: 在 `http/client.v` 新增 `NoopInterceptor` 哨兵 struct，实现 `ClientHttpRequestInterceptor` 接口的 `intercept_fn` 为透传 next
  - [x] SubTask 15.2: 将 `ClientHttpRequestInterceptor.intercept_fn` 默认值从 `unsafe { nil }` 改为 `NoopInterceptor.intercept` 函数引用
  - [x] SubTask 15.3: 在 `orm/repository.v` 的 `BaseRepository` 各 exec_* 字段保留 `unsafe { nil }` 但添加运行时 nil 检查与明确错误（避免静默失败）
  - [x] SubTask 15.4: 运行 `v test http/ orm/` 验证通过

## 阶段 4：集成验证

- [x] Task 16: 全量测试与文档同步
  - [x] SubTask 16.1: 运行 `v test .` 全量测试，确保所有模块通过
  - [x] SubTask 16.2: 运行 `v fmt -verify .` 验证代码格式
  - [x] SubTask 16.3: 更新 `README.md` 的安全模块章节，说明 PasswordEncoder 体系与 Encrypter 废弃
  - [x] SubTask 16.4: 更新 `ARCHITECTURE.md` 模块拓扑，新增 password_encoder.v、manager.v、conversion.v、content_negotiation.v、resource_handler.v、error.v
  - [x] SubTask 16.5: 在 `优化文档.md` 末尾追加「优化执行记录」章节，标注已完成项

# Task Dependencies

- Task 2 依赖 Task 1（同模块，避免冲突）
- Task 5 依赖 Task 2（PasswordEncoder 复用 BcryptHasher）
- Task 6 依赖 Task 7（CacheRegistry 与 cache_config 注解同模块）
- Task 11 依赖 Task 4（TransactionalEventListener 与 TransactionManager 协作）
- Task 13 依赖 Task 1/2/3/4（benchmark 验证 P0 修复后的实现）
- Task 14/15 可与 Task 5-12 并行
- Task 16 依赖所有前置任务完成
