# Checklist

## Phase A — Spring Boot 自动配置对齐

- [x] `core/scanner.v` 中存在 `extract_auto_configuration[T]()` comptime 函数，能扫描 `@[auto_configuration]` 注解
- [x] `AutoConfigurationManager` 在 `application_context.refresh()` 时自动注册被 `@[auto_configuration]` 标注的类
- [x] `core/auto_configuration_scan_test.v` 通过，验证标注类被自动注册
- [x] `ValueAnnotationPostProcessor.before_initialization` 真正扫描 `@[value('key')]` 字段并注入值
- [x] 支持 string/int/f64/bool 四种类型自动转换
- [x] 缺失键时抛出可读错误 `value injection failed: key '...' not found`
- [x] `core/value_injection_test.v` 通过，覆盖 4 种类型 + 缺失键
- [x] `core/scanner.v` 中存在 `extract_bean_methods[T]()` 返回 `[]BeanMethod`
- [x] `@[bean]` 方法的返回类型被注册为 BeanDefinition，方法参数自动从容器解析
- [x] `core/bean_method_scan_test.v` 通过
- [x] `core/environment.v` 支持 `application-{profile}.toml` 加载
- [x] profile 来自 `PHOTON_PROFILE` 环境变量或 `--profile` 命令行参数
- [x] 属性源优先级链：命令行 > 环境变量 > profile > 默认
- [x] `core/profile_config_test.v` 通过，验证 profile 覆盖默认、命令行覆盖 profile
- [x] 定义了 `auto_configuration_imports.v` 清单文件格式
- [x] `AutoConfigurationManager` 启动时扫描所有模块清单
- [x] `core/starter_pattern_test.v` 通过

## Phase B — Spring Data / ORM 完整性

- [x] `JpaRepository[T]` 存在 `find_all_paged(page PageRequest) Page[T]` 方法
- [x] `Page[T]` 包含 `items`/`total`/`page_number`/`page_size`/`total_pages`
- [x] `orm/jpa_pagination_test.v` 通过，覆盖首页/中间页/末页/越界
- [x] `orm/relation.v` 中 `load_has_many` 执行真实 SQL 并回填，无 `// Map results to items` 桩注释
- [x] `load_belongs_to` 执行真实 SQL
- [x] `load_many_to_many` 执行 JOIN 真实 SQL
- [x] `orm/relation_loader_test.v` 通过，覆盖三种关系
- [x] `orm/transaction.v` 的 `begin` 根据 `isolation` 执行对应 SQL
- [x] `readonly` 事务拦截写操作并抛错
- [x] `timeout` 超时自动回滚
- [x] `rollback_if_needed` 检查 `rollback_for`/`no_rollback_for`
- [x] `orm/transaction_attributes_test.v` 通过，覆盖 4 种属性
- [x] `orm/migration.v` 的 `initialize()` 执行 `CREATE TABLE IF NOT EXISTS _photon_migrations`
- [x] `migrate()` 执行 up SQL 并记录版本
- [x] 重复 `migrate()` 跳过已应用迁移
- [x] 迁移失败时事务回滚
- [x] `orm/migration_execute_test.v` 通过
- [x] `orm/derive.v` 支持 `GreaterThan`/`LessThan`/`GreaterThanOrEqual`/`LessThanOrEqual`
- [x] 支持 `Containing`/`StartingWith`/`EndingWith`（LIKE 模式）
- [x] 支持 `In`/`NotIn`
- [x] 支持 `IsNull`/`IsNotNull`
- [x] `orm/derive_keywords_test.v` 通过，覆盖每个新关键词
- [x] `orm/query.v` 存在并定义 `@[query('...')]` 注解处理
- [x] 命名参数 `:name` 从方法参数按名绑定
- [x] `orm/query_annotation_test.v` 通过
- [x] `orm/entity.v` 定义 `@[entity]`/`@[table]`/`@[column]`/`@[id]` 注解读取
- [x] comptime 提取表名/列名/主键
- [x] `JpaRepository[T]` SQL 生成使用元数据
- [x] `orm/entity_annotation_test.v` 通过
- [x] `@[version]` 字段被 comptime 扫描
- [x] `save()` 的 UPDATE 带 `WHERE id = ? AND version = ?`，SET `version = version + 1`
- [x] 影响行数 0 时抛出 `OptimisticLockException`
- [x] `orm/optimistic_lock_test.v` 通过，覆盖并发冲突

## Phase C — 企业级特性

- [x] `i18n/message_source.v` 存在并定义 `MessageSource` 接口
- [x] `ResourceBundleMessageSource` 加载 `messages_{lang}.toml`
- [x] 支持 `{0}`/`{1}` 占位符替换
- [x] `i18n/message_source_test.v` 通过，覆盖中英文 + 占位符
- [x] `async/task_executor.v` 存在并定义 `TaskExecutor` 线程池
- [x] `@[async]` 方法通过 `TaskExecutor.submit` 异步执行
- [x] `async/task_executor_test.v` 通过，验证不阻塞 + 结果正确
- [x] `retry/retryable.v` 存在并定义 `@[retryable]` 注解
- [x] 支持 `max_attempts`/`delay`/`backoff`/`retry_for`
- [x] `retry/retryable_test.v` 通过，覆盖成功/重试成功/重试耗尽
- [x] `core/scanner.v` 中 `extract_scheduled_expr[T]()` 被实际调用（不再是死代码）
- [x] `application_context.refresh()` 扫描 `@[scheduled]` 方法并注册到 `Scheduler`
- [x] `core/scheduled_auto_register_test.v` 通过，验证任务自动启动
- [x] `cache/annotation.v` 实现表达式求值器（`#result`/`#param`/`==`/`!=`/`null`/`and`/`or`）
- [x] `get_or_compute` 在写入前求值 `condition`
- [x] `put` 在写入前求值 `unless`
- [x] `cache/condition_unless_test.v` 通过，覆盖 condition false / unless true / 正常缓存
- [x] `security/annotations.v` 支持 `hasRole`/`hasAuthority`/`hasAnyRole`/`hasAnyAuthority`/`hasPermission`
- [x] 实现 `@PostAuthorize`，对 `#return` 求值
- [x] `security/method_security_test.v` 通过，覆盖每种表达式 + PostAuthorize
- [x] `web/validation.v` 支持 `@[valid]` 方法注解
- [x] 方法调用前校验参数，违反抛出 `ConstraintViolationException`
- [x] `web/method_validation_test.v` 通过

## Phase D — 生产就绪

- [x] `metrics/meter_registry.v` 存在并定义 `MeterRegistry`/`Counter`/`Gauge`/`Timer` 接口
- [x] `InMemoryMeterRegistry` 线程安全（`sync.RwMutex`）
- [x] `/metrics` 端点返回 Prometheus 文本格式
- [x] `metrics/meter_registry_test.v` 通过，覆盖 Counter/Gauge/Timer + 并发
- [x] `tracing/tracer.v` 存在并定义 `TraceContext`/`Span`/`Tracer` 接口
- [x] `InMemoryTracer` 记录 span 链
- [x] `@[trace]` 注解自动开 span
- [x] `tracing/tracer_test.v` 通过，覆盖 span 创建/嵌套/耗时
- [x] `health/health_indicator.v` 存在并定义 `HealthIndicator` 接口与 `Health` 模型
- [x] 实现 `DbHealthIndicator`/`CacheHealthIndicator`/`DiskHealthIndicator`/`MemoryHealthIndicator`
- [x] `/health` 端点聚合所有指示器，DOWN 时 HTTP 503
- [x] `health/health_indicator_test.v` 通过，覆盖 UP/DOWN/聚合
- [x] `web/server.v` 注册 SIGTERM/SIGINT 信号处理器
- [x] 收到信号后停止接受新连接，等待在途请求（默认 30s）
- [x] 调用 `ApplicationContext.shutdown()` 完整销毁
- [x] `web/graceful_shutdown_test.v` 通过
- [x] `logger/logger.v` 支持按命名空间独立级别
- [x] GET `/loggers` 返回所有 logger 及级别
- [x] POST `/loggers/{name}` 调整级别并立即生效
- [x] `web/loggers_endpoint_test.v` 通过
- [x] `/env` 端点返回所有配置键值（敏感键脱敏）
- [x] `/beans` 端点返回 Bean 列表（name/type/scope/lazy）
- [x] `/mappings` 端点返回所有路由（method/path/handler）
- [x] `web/introspection_test.v` 通过
- [x] 定义 `build.info` 或 comptime 注入 `BuildInfo`
- [x] `/info` 端点返回构建信息
- [x] `web/info_endpoint_test.v` 通过
- [x] `/health/liveness` 存活探针（进程存活即 200）
- [x] `/health/readiness` 就绪探针（所有 `SmartLifecycle.is_running()` 后 200，启动中 503）
- [x] `web/k8s_probe_test.v` 通过

## Phase E — 集成验证与示例迁移

- [x] `example/` 使用 `@[auto_configuration]` + `@[bean]` 替代手动 `register_instance`
- [x] `example/` 使用 `@[value]` 注入配置
- [x] `example/` 启用 Actuator 端点
- [x] `v test core/...` 全部通过（18/18）
- [x] `v test orm/...` 全部通过（20/20）
- [x] `v test cache/...`/`security/...`/`web/...` 全部通过（6/14/28）
- [x] 新增模块 `i18n/`/`async/`/`retry/`/`metrics/`/`tracing/`/`health/` 测试通过
- [x] `example/` 编译验证通过
- [x] `优化文档.md` 追加「Phase 4 — Spring 企业级框架完成」章节
