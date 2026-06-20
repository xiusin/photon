# Checklist

## Phase A — Spring Boot 自动配置对齐

- [ ] `core/scanner.v` 中存在 `extract_auto_configuration[T]()` comptime 函数，能扫描 `@[auto_configuration]` 注解
- [ ] `AutoConfigurationManager` 在 `application_context.refresh()` 时自动注册被 `@[auto_configuration]` 标注的类
- [ ] `core/auto_configuration_scan_test.v` 通过，验证标注类被自动注册
- [x] `ValueAnnotationPostProcessor.before_initialization` 真正扫描 `@[value('key')]` 字段并注入值
- [x] 支持 string/int/f64/bool 四种类型自动转换
- [x] 缺失键时抛出可读错误 `value injection failed: key '...' not found`
- [x] `core/value_injection_test.v` 通过，覆盖 4 种类型 + 缺失键
- [ ] `core/scanner.v` 中存在 `extract_bean_methods[T]()` 返回 `[]BeanMethod`
- [ ] `@[bean]` 方法的返回类型被注册为 BeanDefinition，方法参数自动从容器解析
- [ ] `core/bean_method_scan_test.v` 通过
- [ ] `core/environment.v` 支持 `application-{profile}.toml` 加载
- [ ] profile 来自 `PHOTON_PROFILE` 环境变量或 `--profile` 命令行参数
- [ ] 属性源优先级链：命令行 > 环境变量 > profile > 默认
- [ ] `core/profile_config_test.v` 通过，验证 profile 覆盖默认、命令行覆盖 profile
- [ ] 定义了 `auto_configuration_imports.v` 清单文件格式
- [ ] `AutoConfigurationManager` 启动时扫描所有模块清单
- [ ] `core/starter_pattern_test.v` 通过

## Phase B — Spring Data / ORM 完整性

- [ ] `JpaRepository[T]` 存在 `find_all_paged(page PageRequest) Page[T]` 方法
- [ ] `Page[T]` 包含 `items`/`total`/`page_number`/`page_size`/`total_pages`
- [ ] `orm/jpa_pagination_test.v` 通过，覆盖首页/中间页/末页/越界
- [ ] `orm/relation.v` 中 `load_has_many` 执行真实 SQL 并回填，无 `// Map results to items` 桩注释
- [ ] `load_belongs_to` 执行真实 SQL
- [ ] `load_many_to_many` 执行 JOIN 真实 SQL
- [ ] `orm/relation_loader_test.v` 通过，覆盖三种关系
- [ ] `orm/transaction.v` 的 `begin` 根据 `isolation` 执行对应 SQL
- [ ] `readonly` 事务拦截写操作并抛错
- [ ] `timeout` 超时自动回滚
- [ ] `rollback_if_needed` 检查 `rollback_for`/`no_rollback_for`
- [ ] `orm/transaction_attributes_test.v` 通过，覆盖 4 种属性
- [ ] `orm/migration.v` 的 `initialize()` 执行 `CREATE TABLE IF NOT EXISTS _photon_migrations`
- [ ] `migrate()` 执行 up SQL 并记录版本
- [ ] 重复 `migrate()` 跳过已应用迁移
- [ ] 迁移失败时事务回滚
- [ ] `orm/migration_execute_test.v` 通过
- [ ] `orm/derive.v` 支持 `GreaterThan`/`LessThan`/`GreaterThanOrEqual`/`LessThanOrEqual`
- [ ] 支持 `Containing`/`StartingWith`/`EndingWith`（LIKE 模式）
- [ ] 支持 `In`/`NotIn`
- [ ] 支持 `IsNull`/`IsNotNull`
- [ ] `orm/derive_keywords_test.v` 通过，覆盖每个新关键词
- [ ] `orm/query.v` 存在并定义 `@[query('...')]` 注解处理
- [ ] 命名参数 `:name` 从方法参数按名绑定
- [ ] `orm/query_annotation_test.v` 通过
- [ ] `orm/entity.v` 定义 `@[entity]`/`@[table]`/`@[column]`/`@[id]` 注解读取
- [ ] comptime 提取表名/列名/主键
- [ ] `JpaRepository[T]` SQL 生成使用元数据
- [ ] `orm/entity_annotation_test.v` 通过
- [ ] `@[version]` 字段被 comptime 扫描
- [ ] `save()` 的 UPDATE 带 `WHERE id = ? AND version = ?`，SET `version = version + 1`
- [ ] 影响行数 0 时抛出 `OptimisticLockException`
- [ ] `orm/optimistic_lock_test.v` 通过，覆盖并发冲突

## Phase C — 企业级特性

- [ ] `i18n/message_source.v` 存在并定义 `MessageSource` 接口
- [ ] `ResourceBundleMessageSource` 加载 `messages_{lang}.toml`
- [ ] 支持 `{0}`/`{1}` 占位符替换
- [ ] `i18n/message_source_test.v` 通过，覆盖中英文 + 占位符
- [ ] `async/task_executor.v` 存在并定义 `TaskExecutor` 线程池
- [ ] `@[async]` 方法通过 `TaskExecutor.submit` 异步执行
- [ ] `async/task_executor_test.v` 通过，验证不阻塞 + 结果正确
- [ ] `retry/retryable.v` 存在并定义 `@[retryable]` 注解
- [ ] 支持 `max_attempts`/`delay`/`backoff`/`retry_for`
- [ ] `retry/retryable_test.v` 通过，覆盖成功/重试成功/重试耗尽
- [ ] `core/scanner.v` 中 `extract_scheduled_expr[T]()` 被实际调用（不再是死代码）
- [ ] `application_context.refresh()` 扫描 `@[scheduled]` 方法并注册到 `Scheduler`
- [ ] `core/scheduled_auto_register_test.v` 通过，验证任务自动启动
- [ ] `cache/annotation.v` 实现表达式求值器（`#result`/`#param`/`==`/`!=`/`null`/`and`/`or`）
- [ ] `get_or_compute` 在写入前求值 `condition`
- [ ] `put` 在写入前求值 `unless`
- [ ] `cache/condition_unless_test.v` 通过，覆盖 condition false / unless true / 正常缓存
- [ ] `security/annotations.v` 支持 `hasRole`/`hasAuthority`/`hasAnyRole`/`hasAnyAuthority`/`hasPermission`
- [ ] 实现 `@PostAuthorize`，对 `#return` 求值
- [ ] `security/method_security_test.v` 通过，覆盖每种表达式 + PostAuthorize
- [ ] `web/validation.v` 支持 `@[valid]` 方法注解
- [ ] 方法调用前校验参数，违反抛出 `ConstraintViolationException`
- [ ] `web/method_validation_test.v` 通过

## Phase D — 生产就绪

- [ ] `metrics/meter_registry.v` 存在并定义 `MeterRegistry`/`Counter`/`Gauge`/`Timer` 接口
- [ ] `InMemoryMeterRegistry` 线程安全（`sync.RwMutex`）
- [ ] `/metrics` 端点返回 Prometheus 文本格式
- [ ] `metrics/meter_registry_test.v` 通过，覆盖 Counter/Gauge/Timer + 并发
- [ ] `tracing/tracer.v` 存在并定义 `TraceContext`/`Span`/`Tracer` 接口
- [ ] `InMemoryTracer` 记录 span 链
- [ ] `@[trace]` 注解自动开 span
- [ ] `tracing/tracer_test.v` 通过，覆盖 span 创建/嵌套/耗时
- [ ] `health/health_indicator.v` 存在并定义 `HealthIndicator` 接口与 `Health` 模型
- [ ] 实现 `DbHealthIndicator`/`CacheHealthIndicator`/`DiskHealthIndicator`/`MemoryHealthIndicator`
- [ ] `/health` 端点聚合所有指示器，DOWN 时 HTTP 503
- [ ] `health/health_indicator_test.v` 通过，覆盖 UP/DOWN/聚合
- [ ] `web/server.v` 注册 SIGTERM/SIGINT 信号处理器
- [ ] 收到信号后停止接受新连接，等待在途请求（默认 30s）
- [ ] 调用 `ApplicationContext.shutdown()` 完整销毁
- [ ] `web/graceful_shutdown_test.v` 通过
- [ ] `logger/logger.v` 支持按命名空间独立级别
- [ ] GET `/loggers` 返回所有 logger 及级别
- [ ] POST `/loggers/{name}` 调整级别并立即生效
- [ ] `web/loggers_endpoint_test.v` 通过
- [ ] `/env` 端点返回所有配置键值（敏感键脱敏）
- [ ] `/beans` 端点返回 Bean 列表（name/type/scope/lazy）
- [ ] `/mappings` 端点返回所有路由（method/path/handler）
- [ ] `web/introspection_test.v` 通过
- [ ] 定义 `build.info` 或 comptime 注入 `BuildInfo`
- [ ] `/info` 端点返回构建信息
- [ ] `web/info_endpoint_test.v` 通过
- [ ] `/health/liveness` 存活探针（进程存活即 200）
- [ ] `/health/readiness` 就绪探针（所有 `SmartLifecycle.is_running()` 后 200，启动中 503）
- [ ] `web/k8s_probe_test.v` 通过

## Phase E — 集成验证与示例迁移

- [ ] `example/` 使用 `@[auto_configuration]` + `@[bean]` 替代手动 `register_instance`
- [ ] `example/` 使用 `@[value]` 注入配置
- [ ] `example/` 启用 Actuator 端点
- [ ] `v test core/...` 全部通过
- [ ] `v test orm/...` 全部通过
- [ ] `v test cache/...`/`security/...`/`web/...` 全部通过
- [ ] 新增模块 `i18n/`/`async/`/`retry/`/`metrics/`/`tracing/`/`health/` 测试通过
- [ ] `example/` 编译验证通过
- [ ] `优化文档.md` 追加「Phase 4 — Spring 企业级框架完成」章节
