# Tasks

## Phase A — Spring Boot 自动配置对齐

- [ ] Task A1：实现 `@[auto_configuration]` comptime 扫描
  - [ ] SubTask A1.1：在 `core/scanner.v` 中实现 `extract_auto_configuration[T]()` comptime 函数，扫描 `@[auto_configuration]` 注解
  - [ ] SubTask A1.2：在 `core/auto_configuration.v` 的 `AutoConfigurationManager` 增加 `register_from_comptime[T]()` 方法
  - [ ] SubTask A1.3：在 `core/application_context.v` 的 `refresh()` 中调用 comptime 扫描，自动注册配置类
  - [ ] SubTask A1.4：编写 `core/auto_configuration_scan_test.v`，验证标注类被自动注册

- [x] Task A2：实现 `ValueAnnotationPostProcessor` 真正的 `@[value]` 注入
  - [x] SubTask A2.1：在 `core/post_processor.v` 中实现 `before_initialization` comptime 扫描 `@[value('key')]` 字段
  - [x] SubTask A2.2：从 `Environment` 取值，按字段类型（string/int/f64/bool）转换并赋值
  - [x] SubTask A2.3：缺失键时抛出可读错误 `value injection failed: key '...' not found`
  - [x] SubTask A2.4：编写 `core/value_injection_test.v`，覆盖 4 种类型 + 缺失键场景

- [ ] Task A3：实现 `@[configuration]` + `@[bean]` 方法扫描
  - [ ] SubTask A3.1：在 `core/scanner.v` 中实现 `extract_bean_methods[T]()` comptime，返回 `[]BeanMethod`（方法名、返回类型、参数类型列表）
  - [ ] SubTask A3.2：在 `AutoConfigurationManager` 中为每个 `@[bean]` 方法注册 `BeanDefinition`，工厂函数从容器解析参数后调用方法
  - [ ] SubTask A3.3：编写 `core/bean_method_scan_test.v`，验证 Bean 方法返回类型被注册且参数被自动注入

- [ ] Task A4：实现 Profile 特化配置与属性源优先级
  - [ ] SubTask A4.1：在 `core/environment.v` 中支持 `application-{profile}.toml` 加载，profile 来自 `PHOTON_PROFILE` 环境变量或 `--profile` 命令行参数
  - [ ] SubTask A4.2：定义属性源优先级链：命令行 > 环境变量 > profile 配置 > 默认配置
  - [ ] SubTask A4.3：`get_property(key)` 按优先级链查找
  - [ ] SubTask A4.4：编写 `core/profile_config_test.v`，验证 profile 覆盖默认、命令行覆盖 profile

- [ ] Task A5：实现 Starter 模式与 `auto_configuration_imports.v` 清单
  - [ ] SubTask A5.1：定义 `auto_configuration_imports.v` 文件格式（每行一个配置类全限定名）
  - [ ] SubTask A5.2：在 `AutoConfigurationManager` 启动时扫描所有模块的清单文件
  - [ ] SubTask A5.3：编写 `core/starter_pattern_test.v`，模拟第三方模块清单加载

## Phase B — Spring Data / ORM 完整性

- [ ] Task B1：JpaRepository 分页
  - [ ] SubTask B1.1：在 `support/page.v`（或复用现有）确认 `PageRequest`/`Page[T]` 结构（`items`/`total`/`page_number`/`page_size`/`total_pages`）
  - [ ] SubTask B1.2：在 `orm/repository.v` 的 `JpaRepository[T]` 增加 `find_all_paged(page PageRequest) Page[T]`
  - [ ] SubTask B1.3：实现 `SELECT * FROM ... LIMIT ? OFFSET ?` + `SELECT COUNT(*) FROM ...`
  - [ ] SubTask B1.4：编写 `orm/jpa_pagination_test.v`，覆盖首页/中间页/末页/越界

- [ ] Task B2：关系加载器落地
  - [ ] SubTask B2.1：在 `orm/relation.v` 中实现 `load_has_many(parent, field, fk)`，执行 `SELECT * FROM child WHERE {fk} = ?` 并回填
  - [ ] SubTask B2.2：实现 `load_belongs_to(child, field, fk)`，执行 `SELECT * FROM parent WHERE id = ?`
  - [ ] SubTask B2.3：实现 `load_many_to_many(entity, field, join_table, fk, target_fk)`，执行 `SELECT t.* FROM target t JOIN {join_table} j ON t.id = j.{target_fk} WHERE j.{fk} = ?`
  - [ ] SubTask B2.4：编写 `orm/relation_loader_test.v`，覆盖三种关系

- [ ] Task B3：事务属性真正执行
  - [ ] SubTask B3.1：在 `orm/transaction.v` 的 `begin` 中根据 `isolation` 执行 `PRAGMA isolation_level`（SQLite）或 `SET TRANSACTION ISOLATION LEVEL`（其他）
  - [ ] SubTask B3.2：`readonly` 标记下，`execute`/`exec` 拦截并抛出 `readonly transaction cannot perform write operation`
  - [ ] SubTask B3.3：`timeout` 通过 goroutine + timer 实现，超时自动 `rollback`
  - [ ] SubTask B3.4：`rollback_if_needed` 检查 `rollback_for`/`no_rollback_for`，匹配才回滚
  - [ ] SubTask B3.5：编写 `orm/transaction_attributes_test.v`，覆盖 4 种属性

- [ ] Task B4：迁移系统执行真实 SQL
  - [ ] SubTask B4.1：在 `orm/migration.v` 的 `initialize()` 执行 `CREATE TABLE IF NOT EXISTS _photon_migrations (version TEXT PRIMARY KEY, applied_at TIMESTAMP)`
  - [ ] SubTask B4.2：`migrate()` 查询已应用版本，对每个未应用迁移执行 up SQL 并插入版本记录
  - [ ] SubTask B4.3：支持事务内迁移（每个迁移独立事务，失败回滚）
  - [ ] SubTask B4.4：编写 `orm/migration_execute_test.v`，覆盖首次/重复/失败回滚

- [ ] Task B5：派生查询关键词扩展
  - [ ] SubTask B5.1：在 `orm/derive.v` 中增加 `GreaterThan`/`LessThan`/`GreaterThanOrEqual`/`LessThanOrEqual` → `> ?`/`< ?`/`>= ?`/`<= ?`
  - [ ] SubTask B5.2：增加 `Containing`/`StartingWith`/`EndingWith` → `LIKE '%' || ? || '%'`/`LIKE ? || '%'`/`LIKE '%' || ?`
  - [ ] SubTask B5.3：增加 `In`/`NotIn` → `IN (...)`/`NOT IN (...)`
  - [ ] SubTask B5.4：增加 `IsNull`/`IsNotNull` → `IS NULL`/`IS NOT NULL`
  - [ ] SubTask B5.5：增加 `OrderBy`/`TopN` 解析（已有则增强）
  - [ ] SubTask B5.6：编写 `orm/derive_keywords_test.v`，覆盖每个新关键词

- [ ] Task B6：`@[query]` 原生 SQL 注解
  - [ ] SubTask B6.1：在 `orm/query.v`（新增）中定义 `@[query('SELECT ...')]` 注解处理
  - [ ] SubTask B6.2：解析命名参数 `:name`，从方法参数按名绑定
  - [ ] SubTask B6.3：在 `JpaRepository[T]` 中提供 `execute_query[T](sql, params)` 通用方法
  - [ ] SubTask B6.4：编写 `orm/query_annotation_test.v`，覆盖命名参数 + 多结果

- [ ] Task B7：JPA 实体注解
  - [ ] SubTask B7.1：在 `orm/entity.v`（新增）中定义 `@[entity]`/`@[table('name')]`/`@[column('name')]`/`@[id]` 注解读取
  - [ ] SubTask B7.2：comptime 扫描实体类型，提取表名（默认 struct 名小写）、列名（默认字段名）、主键字段
  - [ ] SubTask B7.3：`JpaRepository[T]` 的 SQL 生成使用提取的元数据
  - [ ] SubTask B7.4：编写 `orm/entity_annotation_test.v`，覆盖自定义表名/列名/主键

- [x] Task B8：`@[version]` 乐观锁
  - [x] SubTask B8.1：comptime 扫描 `@[version]` 字段，记录字段名
  - [x] SubTask B8.2：`save()` 时 UPDATE SQL 增加 `WHERE id = ? AND version = ?`，SET 子句 `version = version + 1`
  - [x] SubTask B8.3：影响行数为 0 时抛出 `OptimisticLockException`
  - [x] SubTask B8.4：编写 `orm/optimistic_lock_test.v`，覆盖并发冲突

## Phase C — 企业级特性

- [ ] Task C1：MessageSource 国际化
  - [ ] SubTask C1.1：在 `i18n/message_source.v`（新增）定义 `MessageSource` 接口（`resolve(code, locale, args) string`）
  - [ ] SubTask C1.2：实现 `ResourceBundleMessageSource`，加载 `messages_{lang}.toml`
  - [ ] SubTask C1.3：支持 `{0}`/`{1}` 占位符替换
  - [ ] SubTask C1.4：编写 `i18n/message_source_test.v`，覆盖中英文 + 占位符

- [ ] Task C2：`@[async]` 异步执行
  - [ ] SubTask C2.1：在 `async/task_executor.v`（新增）定义 `TaskExecutor`（线程池 + 任务队列）
  - [ ] SubTask C2.2：comptime 扫描 `@[async]` 方法，包装为 `TaskExecutor.submit(fn)`
  - [ ] SubTask C2.3：编写 `async/task_executor_test.v`，验证异步不阻塞 + 结果正确

- [ ] Task C3：`@[retryable]` 重试
  - [ ] SubTask C3.1：在 `retry/retryable.v`（新增）定义 `@[retryable(max_attempts, delay, backoff, retry_for)]` 注解
  - [ ] SubTask C3.2：comptime 包装方法，按配置重试，指数退避
  - [ ] SubTask C3.3：编写 `retry/retryable_test.v`，覆盖成功/重试成功/重试耗尽

- [ ] Task C4：`@[scheduled]` 自动注册到 Scheduler
  - [ ] SubTask C4.1：在 `core/scanner.v` 中调用已有的 `extract_scheduled_expr[T]()`（当前未被调用）
  - [ ] SubTask C4.2：在 `application_context.refresh()` 中扫描 `@[scheduled]` 方法，注册到 `Scheduler`
  - [ ] SubTask C4.3：编写 `core/scheduled_auto_register_test.v`，验证任务自动启动

- [ ] Task C5：缓存 `condition`/`unless` 求值
  - [ ] SubTask C5.1：在 `cache/annotation.v` 中实现简易表达式求值器（支持 `#result`、`#param`、`==`、`!=`、`null`、`and`/`or`）
  - [ ] SubTask C5.2：`get_or_compute` 在写入前求值 `condition`，false 则不缓存
  - [ ] SubTask C5.3：`put` 在写入前求值 `unless`，true 则不缓存
  - [ ] SubTask C5.4：编写 `cache/condition_unless_test.v`，覆盖 condition false / unless true / 正常缓存

- [ ] Task C6：`@PreAuthorize` 完整 + `@PostAuthorize`
  - [ ] SubTask C6.1：在 `security/annotations.v` 中扩展表达式解析，支持 `hasRole`/`hasAuthority`/`hasAnyRole`/`hasAnyAuthority`/`hasPermission`
  - [ ] SubTask C6.2：实现 `@PostAuthorize`，方法返回后对 `#return` 求值
  - [ ] SubTask C6.3：编写 `security/method_security_test.v`，覆盖每种表达式 + PostAuthorize

- [ ] Task C7：方法级校验
  - [ ] SubTask C7.1：在 `web/validation.v` 中增加 `@[valid]` 方法注解，comptime 扫描方法参数的约束
  - [ ] SubTask C7.2：方法调用前校验参数，违反抛出 `ConstraintViolationException`
  - [ ] SubTask C7.3：编写 `web/method_validation_test.v`，覆盖参数校验

## Phase D — 生产就绪

- [ ] Task D1：Metrics 指标系统
  - [ ] SubTask D1.1：在 `metrics/meter_registry.v`（新增）定义 `MeterRegistry`/`Counter`/`Gauge`/`Timer` 接口
  - [ ] SubTask D1.2：实现 `InMemoryMeterRegistry`，线程安全（`sync.RwMutex`）
  - [ ] SubTask D1.3：在 `web/actuator_metrics.v`（新增）实现 `/metrics` 端点，返回 Prometheus 文本格式
  - [ ] SubTask D1.4：编写 `metrics/meter_registry_test.v`，覆盖 Counter/Gauge/Timer + 并发

- [ ] Task D2：分布式追踪
  - [ ] SubTask D2.1：在 `tracing/tracer.v`（新增）定义 `TraceContext`/`Span`/`Tracer` 接口
  - [ ] SubTask D2.2：实现 `InMemoryTracer`，记录 span 链
  - [ ] SubTask D2.3：comptime 扫描 `@[trace]` 注解，自动开 span
  - [ ] SubTask D2.4：编写 `tracing/tracer_test.v`，覆盖 span 创建/嵌套/耗时

- [ ] Task D3：健康检查
  - [ ] SubTask D3.1：在 `health/health_indicator.v`（新增）定义 `HealthIndicator` 接口（`check() Health`）与 `Health` 模型（status/details）
  - [ ] SubTask D3.2：实现 `DbHealthIndicator`/`CacheHealthIndicator`/`DiskHealthIndicator`/`MemoryHealthIndicator`
  - [ ] SubTask D3.3：在 `web/actuator_health.v` 实现 `/health` 端点，聚合所有指示器，DOWN 时 503
  - [ ] SubTask D3.4：编写 `health/health_indicator_test.v`，覆盖 UP/DOWN/聚合

- [ ] Task D4：优雅停机
  - [ ] SubTask D4.1：在 `web/server.v` 中注册 SIGTERM/SIGINT 信号处理器（`os.signal` 或 `veb` 钩子）
  - [ ] SubTask D4.2：收到信号后停止接受新连接，等待在途请求（默认 30s 超时）
  - [ ] SubTask D4.3：调用 `ApplicationContext.shutdown()` 完整生命周期销毁
  - [ ] SubTask D4.4：编写 `web/graceful_shutdown_test.v`，覆盖信号触发 + 在途完成 + 超时

- [ ] Task D5：`/loggers` 端点
  - [ ] SubTask D5.1：在 `logger/logger.v` 中支持按命名空间独立级别（`map[string]Level` + 默认级别）
  - [ ] SubTask D5.2：在 `web/actuator_loggers.v` 实现 GET `/loggers` 返回所有 logger，POST `/loggers/{name}` 调整级别
  - [ ] SubTask D5.3：编写 `web/loggers_endpoint_test.v`，覆盖查询 + 调整 + 生效

- [ ] Task D6：自省端点 `/env` `/beans` `/mappings`
  - [ ] SubTask D6.1：实现 `/env` 返回所有配置键值（敏感键脱敏）
  - [ ] SubTask D6.2：实现 `/beans` 返回 Bean 列表（name/type/scope/lazy）
  - [ ] SubTask D6.3：实现 `/mappings` 返回所有路由（method/path/handler）
  - [ ] SubTask D6.4：编写 `web/introspection_test.v`，覆盖三个端点

- [ ] Task D7：`/info` 端点
  - [ ] SubTask D7.1：定义 `build.info` 文件格式或 comptime 注入 `BuildInfo{version, commit, time}`
  - [ ] SubTask D7.2：实现 `/info` 端点返回构建信息
  - [ ] SubTask D7.3：编写 `web/info_endpoint_test.v`

- [ ] Task D8：K8s 探针
  - [ ] SubTask D8.1：实现 `/health/liveness`（进程存活即 200）
  - [ ] SubTask D8.2：实现 `/health/readiness`（所有 `SmartLifecycle.is_running() == true` 后 200，启动中 503）
  - [ ] SubTask D8.3：编写 `web/k8s_probe_test.v`，覆盖存活/就绪/启动中

## Phase E — 集成验证与示例迁移

- [ ] Task E1：Example 应用迁移到自动配置
  - [ ] SubTask E1.1：在 `example/` 中使用 `@[auto_configuration]` + `@[bean]` 替代手动 `register_instance`
  - [ ] SubTask E1.2：使用 `@[value]` 注入配置
  - [ ] SubTask E1.3：启用 Actuator 端点（`/health`/`/metrics`/`/info`）

- [ ] Task E2：全量测试回归
  - [ ] SubTask E2.1：运行 `v test core/...` 确保通过
  - [ ] SubTask E2.2：运行 `v test orm/...` 确保通过
  - [ ] SubTask E2.3：运行 `v test cache/...`/`security/...`/`web/...` 确保通过
  - [ ] SubTask E2.4：运行新增模块 `i18n/`/`async/`/`retry/`/`metrics/`/`tracing/`/`health/` 测试
  - [ ] SubTask E2.5：运行 `example/` 编译验证

- [ ] Task E3：更新 `优化文档.md`
  - [ ] SubTask E3.1：追加「Phase 4 — Spring 企业级框架完成」章节，记录所有任务执行结果

# Task Dependencies

- Task A1 → A2 → A3（自动配置扫描链路，A2/A3 依赖 A1 的 comptime 基础设施）
- Task A4 独立（环境配置，可与 A1-A3 并行）
- Task A5 依赖 A1（Starter 清单依赖扫描器）
- Task B1-B8 互相独立，可并行（均依赖 Phase 3 已完成的 JpaRepository 基础）
- Task C1-C7 互相独立，可并行
- Task C4 依赖 Phase 3 的 `Scheduler` 与 `extract_scheduled_expr`（已存在）
- Task D1-D8 互相独立，可并行
- Task D3 依赖 D1（健康检查可选用 Metrics）
- Task E1 依赖 A1-A5 + D1-D3（示例需用自动配置 + Actuator）
- Task E2 依赖所有 A-D 任务完成
- Task E3 依赖 E2 验证通过
