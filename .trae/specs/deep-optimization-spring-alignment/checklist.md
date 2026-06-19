# Checklist

## P0 安全与架构修复

- [x] `security/encryption.v` 的 `Encrypter` struct 标注 `@[deprecated]`
- [x] `security/encryption.v` 的 `new_encrypter`/`encrypt`/`decrypt` 函数标注 `@[deprecated]`
- [x] `encrypt`/`decrypt` 函数体首行输出 stderr 废弃警告
- [x] `security/hashing.v` 的 `hash_string` 改用 PBKDF2-SHA256 真实 KDF
- [x] `BcryptHasher.make`/`check` 往返一致（旧测试通过）
- [x] `Argon2Hasher.make`/`check` 往返一致（旧测试通过）
- [x] `web/kernel.v` 新增 `HandlerResolver` 接口与 `HandlerFn` 类型
- [x] `web/kernel.v` 新增 `handle_with(resolver, ctx) !voidptr` 方法
- [x] `web/kernel.v` 保留无参 `handle()` 向后兼容
- [x] `handle_with` 异常时分发 `kernel.exception` 事件
- [x] `orm/transaction.v` 的 `TransactionManager` 新增 `conn`/`begin_fn`/`commit_fn`/`rollback_fn` 字段
- [x] `orm/transaction.v` 新增 `begin(conn, begin_fn) !` 方法
- [x] `orm/transaction.v` 的 `commit`/`rollback` 调用真实回调（若已设置）
- [x] `orm/transaction.v` 保留无 DB 纯状态机模式（`new_transaction_manager()` 无参）
- [x] `orm/transaction_test.v` 新增真实连接回调测试
- [x] `v test security/ web/ orm/` 全部通过

## P1 架构补全

- [x] `security/password_encoder.v` 定义 `PasswordEncoder` 接口（encode/matches/upgrade_encoding）
- [x] `BCryptPasswordEncoder` 输出 `{bcrypt}<hash>` 前缀格式
- [x] `Argon2PasswordEncoder` 输出 `{argon2id}<hash>` 前缀格式
- [x] `FnvPasswordEncoder` 仅支持 `matches`（验证旧哈希），`encode` 返回升级提示错误
- [x] `DelegatingPasswordEncoder` 的 `encode` 输出 `{id}hash`，`matches` 解析前缀路由
- [x] `DelegatingPasswordEncoder` 支持无前缀旧哈希通过 `default_id_for_matches` 回退
- [x] `cache/manager.v` 定义 `CacheManager` 接口与 `NamedCache` 接口
- [x] `cache/manager.v` 定义 `ValueWrapper` struct
- [x] `cache/cache.v` 的 `CacheManager` struct 重命名为 `CacheRegistry` 并实现新接口
- [x] `cache/annotation.v` 的 `CacheableInterceptor` 字段类型更新为 `&CacheRegistry`
- [x] `cache/cache_test.v` 适配 `CacheRegistry` 重命名
- [x] `cache/annotation.v` 新增 `CacheConfigAttribute` 与 `parse_cache_config_attr`
- [x] `cache/annotation.v` 定义 `KeyGenerator` 接口与 `SimpleKeyGenerator` 实现
- [x] `core/conversion.v` 定义 `Converter[S, T]` 接口
- [x] `core/conversion.v` 定义 `ConversionService` 接口
- [x] `core/conversion.v` 实现 `GenericConversionService`
- [x] `core/conversion.v` 内置 String→int/i64/f64/bool 转换器
- [x] `web/content_negotiation.v` 定义 `ContentNegotiationStrategy` 接口
- [x] `web/content_negotiation.v` 实现 `AcceptHeaderStrategy`/`ParameterStrategy`/`FixedStrategy`
- [x] `web/content_negotiation.v` 实现 `ContentNegotiationManager`
- [x] `web/resource_handler.v` 定义 `ResourceHandlerMapping` 与 `ResourceHandlerRegistry`
- [x] `web/resource_handler.v` 实现 `resolve(path) ?string` 与 `serve(path) !string`
- [x] `core/event.v` 新增 `TransactionPhase` 枚举
- [x] `core/event.v` 定义 `TransactionalEventListener` 接口
- [x] `core/event.v` 的 `EventBus` 新增 `on_transactional` 与 `dispatch_transactional` 方法
- [x] `orm/transaction_annotation.v` 新增 `parse_transactional_event_listener_attr`
- [x] `v test security/ cache/ core/ web/ orm/` 全部通过

## P2 代码质量改进

- [x] `support/error.v` 定义 `ErrorCode` 枚举（至少 9 个错误码）
- [x] `support/error.v` 定义 `PhotonError` struct（code/message/cause）
- [x] `support/error.v` 提供构造函数 `new_photon_error` 与 `new_photon_error_with_cause`
- [x] `cache/cache_bench_test.v` 包含 set/get/get_or_load benchmark
- [x] `orm/transaction_bench_test.v` 包含 execute(.required) 嵌套 benchmark
- [x] `web/bind_bench_test.v` 包含 bind/bind_json benchmark
- [x] `security/cipher_bench_test.v` 包含 AesCipher/BcryptHasher benchmark
- [x] `http/client.v` 新增 `SSLConfig` 与 `ProxyConfig` struct
- [x] `RestTemplate` 新增 `ssl_config`/`proxy_config` 字段与 `set_ssl_config`/`set_proxy` 方法
- [x] `execute(entity)` 方法应用 SSL/Proxy 配置
- [x] `http/client.v` 新增 `NoopInterceptor` 哨兵
- [x] `ClientHttpRequestInterceptor.intercept_fn` 默认值改为 NoopInterceptor（消除 unsafe nil）
- [x] `orm/repository.v` 的 `BaseRepository` exec_* 字段添加运行时 nil 检查
- [x] `v test .` 全量测试通过
- [x] `v fmt -verify .` 格式验证通过

## 文档同步

- [x] `README.md` 安全章节说明 PasswordEncoder 体系与 Encrypter 废弃
- [x] `ARCHITECTURE.md` 模块拓扑新增 password_encoder.v、manager.v、conversion.v、content_negotiation.v、resource_handler.v、error.v
- [x] `优化文档.md` 末尾追加「优化执行记录」章节
