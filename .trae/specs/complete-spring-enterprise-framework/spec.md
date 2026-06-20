# 完成 Spring 级别企业级框架 Spec（Phase 4）

## Why

经过 Phase 1-3 的深度优化，Photon 框架已在 DI 容器、生命周期、并发安全、资源池化、AOP 代理、JpaRepository 基础、MockMvc、ControllerAdvice 等方面达到 Spring 对齐水准，200+ 测试全部通过。

但 Phase 4 四路深度审查发现：框架仍存在 **50+ 项 Spring Boot/Spring Data/Spring Enterprise/Production-Ready 级别的缺口**，其中多数为「文档承诺但代码未交付」的空壳实现（如 `@[auto_configuration]` 注解扫描从未被 comptime 调用、`ValueAnnotationPostProcessor` 是空壳、关系加载器是 `// Map results to items` 注释桩、迁移系统不执行 SQL、`@Async`/`@Retryable`/`MessageSource` 完全缺失、Metrics/Tracing/HealthCheck/优雅停机全部缺失）。

要真正成为「Spring 级别企业级框架」，必须把这些承诺全部落地，让开发者用注解就能拿到生产可用的能力，而不是「看起来像 Spring，用起来是桩」。

## What Changes

### Phase A — Spring Boot 自动配置对齐（Auto-Configuration）
- **A1**：实现 `@[auto_configuration]` 注解的 comptime 扫描，`AutoConfigurationManager` 真正注册被标注的配置类
- **A2**：实现 `ValueAnnotationPostProcessor`，对 `@[value('key')]` 字段做编译期属性绑定（替代当前空壳）
- **A3**：实现 `@[configuration]` + `@[bean]` 方法扫描，自动把 `@[bean]` 方法的返回类型注册为 BeanDefinition
- **A4**：实现 Profile 特化配置（`application-{profile}.toml` 加载）与属性源优先级链（命令行 > 环境变量 > profile > 默认）
- **A5**：实现 Starter 模式与 `auto_configuration_imports.v` 清单文件，支持跨模块自动发现

### Phase B — Spring Data / ORM 完整性
- **B1**：`JpaRepository[T]` 集成 `PageRequest`/`Page[T]`，实现 `find_all(page PageRequest) Page[T]`
- **B2**：落地关系加载器 `load_has_many`/`load_belongs_to`/`load_many_to_many`，删除桩注释
- **B3**：事务属性真正执行 — `isolation`/`readonly`/`timeout`/`rollback_for`/`no_rollback_for` 在 `begin`/`commit`/`rollback` 中生效
- **B4**：迁移系统执行真实 SQL — `initialize()` 建历史表，`migrate()` 执行 up SQL 并记录版本
- **B5**：扩展派生查询关键词 — `GreaterThan`/`LessThan`/`Containing`/`StartingWith`/`EndingWith`/`In`/`NotIn`/`IsNull`/`IsNotNull`/`OrderBy`/`TopN`
- **B6**：实现 `@[query('SELECT ... WHERE ...')]` 注解，支持原生 SQL 与命名参数
- **B7**：JPA 实体注解 `@[entity]`/`@[table('name')]`/`@[column('name')]`/`@[id]` 在 comptime 读取并影响 SQL 生成
- **B8**：`@[version]` 乐观锁，UPDATE 带 `WHERE version = ?` 并自增

### Phase C — 企业级特性
- **C1**：`MessageSource` 接口 + `ResourceBundleMessageSource` 实现，支持 i18n 多语言消息解析
- **C2**：`@[async]` 注解 + `TaskExecutor` 线程池，方法异步执行
- **C3**：`@[retryable]` 注解（max_attempts/backoff/delay/retry_for），方法重试
- **C4**：`@[scheduled('cron')]` 扫描器接入 `Scheduler`，启动时自动注册任务
- **C5**：缓存 `condition`/`unless` SpEL 表达式在 `get_or_compute`/`put` 中真正求值
- **C6**：`@PreAuthorize` 支持 `hasRole`/`hasAuthority`/`hasAnyRole`/`hasAnyAuthority`；实现 `@PostAuthorize`
- **C7**：方法级校验 — `@[valid]` 注解触发参数校验（不只是 DTO 层）

### Phase D — 生产就绪
- **D1**：`MeterRegistry`/`Meter`/`Counter`/`Gauge`/`Timer` 抽象 + 内存实现 + `/metrics` 端点
- **D2**：`TraceContext`/`Span` 抽象 + 内存 tracer，`@Trace` 注解自动开 span
- **D3**：`HealthIndicator` 接口 + `Health` 模型 + 真实健康检查（DB/Cache/Disk/Memory），`/health` 端点聚合
- **D4**：Web 服务器 SIGTERM/SIGINT 优雅停机 — 拒新请求 + 等待在途 + 超时强制关闭
- **D5**：`/loggers` 端点 — 运行时查询/调整日志级别
- **D6**：自省端点 `/env`（配置）、`/beans`（Bean 列表）、`/mappings`（路由表）
- **D7**：`/info` 端点 — 构建信息（版本/提交/构建时间）
- **D8**：K8s 探针 `/health/liveness` 与 `/health/readiness`，区分存活与就绪

## Impact

- **Affected specs**：
  - `deep-optimization-spring-alignment`（Phase 1，已完成，本阶段在其基础上补齐自动配置）
  - `optimize-quality-and-performance`（Phase 2，已完成，本阶段复用其锁/池基础设施）
  - `audit-master-quality-optimization`（Phase 3，已完成，本阶段复用其生命周期/AOP/条件装配）
- **Affected code**：
  - `core/auto_configuration.v`、`core/scanner.v`、`core/post_processor.v`、`core/environment.v`、`core/application_context.v`
  - `orm/repository.v`、`orm/relation.v`、`orm/transaction.v`、`orm/migration.v`、`orm/derive.v`、`orm/query.v`（新增）、`orm/entity.v`（新增）
  - `cache/annotation.v`、`cache/cache.v`
  - `security/annotations.v`、`security/method_security.v`（新增）
  - `web/server.v`、`web/actuator.v`（新增）、`web/endpoint_*.v`（新增）
  - `i18n/message_source.v`（新增）、`async/task_executor.v`（新增）、`retry/retryable.v`（新增）
  - `metrics/meter_registry.v`（新增）、`tracing/tracer.v`（新增）、`health/health_indicator.v`（新增）
  - `example/` 全量迁移到自动配置 + Actuator 演示
- **BREAKING**：无对外 API 破坏性变更；所有新增能力均通过新注解/新端点/新接口提供，旧 API 保持兼容。

## ADDED Requirements

### Requirement: 自动配置注解扫描
系统 SHALL 在编译期通过 comptime `$for` 扫描所有标注 `@[auto_configuration]` 的类型，并将其注册到 `AutoConfigurationManager`，无需用户手动 `register()`。

#### Scenario: 用户标注自动配置类
- **WHEN** 用户在某个模块定义 `@[auto_configuration] struct DbAutoConfig { @[bean] fn datasource() &DataSource }`
- **THEN** 应用启动时该配置类被自动发现，`@[bean]` 方法返回的 `&DataSource` 被注册为 Bean
- **AND** 用户无需在 `bootstrap()` 中手动注册

### Requirement: `@[value]` 属性注入
系统 SHALL 通过 `ValueAnnotationPostProcessor` 在 Bean 初始化后，对 `@[value('key')]` 字段从 `Environment` 注入值，支持字符串/整型/布尔/浮点类型自动转换。

#### Scenario: 注入字符串配置
- **WHEN** 用户定义 `@[value('app.name')] name string`
- **AND** 配置源中 `app.name = "Photon"`
- **THEN** Bean 初始化后 `name == "Photon"`

#### Scenario: 缺失键报错
- **WHEN** `@[value('app.missing')]` 字段无对应配置
- **THEN** 启动失败并输出可读错误 `value injection failed: key 'app.missing' not found`

### Requirement: `@[configuration]` + `@[bean]` 方法扫描
系统 SHALL 扫描 `@[configuration]` 类的 `@[bean]` 方法，把每个方法的返回类型注册为 BeanDefinition，方法参数自动从容器解析。

#### Scenario: Bean 方法依赖其他 Bean
- **WHEN** `@[bean] fn user_service(repo &UserRepository) &UserService`
- **THEN** 容器先解析 `&UserRepository`，再调用方法注册 `&UserService`

### Requirement: Profile 特化配置
系统 SHALL 支持 `application-{profile}.toml` 文件加载，profile 由 `PHOTON_PROFILE` 环境变量或命令行 `--profile` 指定。

#### Scenario: 激活 prod profile
- **WHEN** `PHOTON_PROFILE=prod` 且存在 `application-prod.toml`
- **THEN** `application.toml` 先加载，`application-prod.toml` 覆盖同名键
- **AND** `app.env == "prod"`

### Requirement: Starter 模式与自动配置清单
系统 SHALL 支持模块通过 `auto_configuration_imports.v` 文件声明本模块提供的自动配置类全限定名，框架启动时扫描所有模块的清单并加载。

#### Scenario: 第三方模块提供 Starter
- **WHEN** `redis` 模块在 `auto_configuration_imports.v` 中声明 `RedisAutoConfig`
- **THEN** 用户引入 `redis` 模块后无需任何配置，`&RedisClient` 自动可用

### Requirement: JpaRepository 分页
系统 SHALL 提供 `find_all(page PageRequest) Page[T]` 方法，返回 `Page[T]` 包含 `items []T`/`total u64`/`page_number u32`/`page_size u32`/`total_pages u32`。

#### Scenario: 查询第 2 页
- **WHEN** `repo.find_all(PageRequest{page_number: 2, page_size: 10})`
- **THEN** 返回的 `Page[T]` 包含第 11-20 条记录，`total` 为全表计数，`total_pages` 正确

### Requirement: 关系加载
系统 SHALL 实现 `load_has_many`/`load_belongs_to`/`load_many_to_many`，通过外键或中间表执行真实 SQL 并回填到实体字段。

#### Scenario: 加载一对多
- **WHEN** `User` 有 `@[has_many] posts []Post`
- **THEN** `load_has_many(user, "posts")` 执行 `SELECT * FROM posts WHERE user_id = ?` 并填充 `user.posts`

### Requirement: 事务属性执行
系统 SHALL 在 `begin` 时设置 `isolation` 级别，在 `commit` 前检查 `readonly`（只读事务调用写操作报错），`timeout` 超时自动回滚，`rollback` 时按 `rollback_for`/`no_rollback_for` 决定是否回滚。

#### Scenario: 只读事务写操作
- **WHEN** `@[transactional(readonly: true)]` 方法执行 INSERT
- **THEN** 抛出错误 `readonly transaction cannot perform write operation`

### Requirement: 迁移系统执行 SQL
系统 SHALL 在 `initialize()` 创建 `_photon_migrations` 历史表，`migrate()` 执行每个迁移的 up SQL 并记录版本号，重复执行跳过已应用迁移。

#### Scenario: 首次迁移
- **WHEN** 存在迁移 `001_create_users` 的 up SQL
- **THEN** 执行 SQL 建表，`_photon_migrations` 表插入版本 `001`
- **AND** 再次 `migrate()` 跳过该迁移

### Requirement: 派生查询关键词扩展
系统 SHALL 在 `derive.v` 中支持 `GreaterThan`/`LessThan`/`Containing`/`StartingWith`/`EndingWith`/`In`/`NotIn`/`IsNull`/`IsNotNull`/`OrderBy`/`TopN` 关键词，生成对应 SQL 谓词。

#### Scenario: Containing 查询
- **WHEN** 方法名 `find_by_name_containing(name string)`
- **THEN** 生成 `SELECT * FROM ... WHERE name LIKE '%' || ? || '%'`

### Requirement: `@[query]` 原生 SQL
系统 SHALL 支持 `@[query('SELECT * FROM users WHERE age > :age ORDER BY name')]` 注解，命名参数 `:age` 从方法参数绑定。

#### Scenario: 命名参数查询
- **WHEN** `@[query('SELECT * FROM users WHERE age > :age')] fn find_older_than(age int) []User`
- **THEN** 执行 SQL，`age` 绑定到 `:age` 占位符

### Requirement: JPA 实体注解
系统 SHALL 识别 `@[entity]`/`@[table('name')]`/`@[column('name')]`/`@[id]` 注解，影响 SQL 生成（表名、列名、主键）。

#### Scenario: 自定义表名
- **WHEN** `@[table('t_user')] struct User`
- **THEN** 生成的 SQL 使用 `t_user` 而非 `user`

### Requirement: `@[version]` 乐观锁
系统 SHALL 在 UPDATE 时带 `WHERE id = ? AND version = ?`，并自增 version；若影响行数为 0，抛出 `OptimisticLockException`。

#### Scenario: 并发更新冲突
- **WHEN** 两个事务同时读取 version=1 的实体并更新
- **THEN** 第一个事务成功，version 变为 2
- **AND** 第二个事务 UPDATE 影响行数为 0，抛出 `OptimisticLockException`

### Requirement: MessageSource 国际化
系统 SHALL 提供 `MessageSource` 接口与 `ResourceBundleMessageSource` 实现，支持按 locale 加载 `messages_{lang}.toml` 并解析 `{0}`/`{1}` 占位符。

#### Scenario: 解析中文消息
- **WHEN** `messages_zh.toml` 含 `greeting = "你好,{0}"`
- **AND** `message_source.resolve('greeting', locale: .zh, args: ['张三'])`
- **THEN** 返回 `"你好,张三"`

### Requirement: `@[async]` 异步执行
系统 SHALL 提供 `TaskExecutor` 线程池，`@[async]` 注解的方法通过 `TaskExecutor` 异步执行，调用方立即返回。

#### Scenario: 异步方法不阻塞
- **WHEN** `@[async] fn send_email(to string)` 被调用
- **THEN** 调用方立即返回，邮件在后台线程池执行

### Requirement: `@[retryable]` 重试
系统 SHALL 支持 `@[retryable(max_attempts: 3, delay: 100ms, backoff: .exponential, retry_for: [NetworkError])]`，方法失败时按配置重试。

#### Scenario: 重试成功
- **WHEN** 方法前两次抛出 `NetworkError`，第三次成功
- **THEN** 总共调用 3 次，返回第三次的结果

### Requirement: `@[scheduled]` 自动注册
系统 SHALL 在启动时扫描 `@[scheduled('cron')]` 方法，自动注册到 `Scheduler`，无需用户手动 `add_task()`。

#### Scenario: 定时任务自动启动
- **WHEN** `@[scheduled('0 * * * *')] fn cleanup()`
- **THEN** 应用启动后每分钟执行 `cleanup()`

### Requirement: 缓存条件求值
系统 SHALL 在 `get_or_compute`/`put` 中对 `condition`/`unless` 表达式求值，`condition` 为 false 时不缓存，`unless` 为 true 时不缓存。

#### Scenario: unless 阻止缓存
- **WHEN** `@[cacheable(unless: '#result == null')]` 方法返回 null
- **THEN** 结果不写入缓存

### Requirement: `@PreAuthorize` 完整支持
系统 SHALL 支持 `hasRole`/`hasAuthority`/`hasAnyRole`/`hasAnyAuthority`/`hasPermission` 表达式，并实现 `@PostAuthorize` 在方法返回后鉴权。

#### Scenario: hasRole 鉴权
- **WHEN** `@PreAuthorize('hasRole("ADMIN")')` 方法被非 ADMIN 用户调用
- **THEN** 抛出 `AccessDeniedException`

### Requirement: 方法级校验
系统 SHALL 支持 `@[valid]` 注解对方法参数做校验（不只是 DTO 层），违反约束时抛出 `ConstraintViolationException`。

#### Scenario: 参数校验
- **WHEN** `@[valid] fn create(@[min(1)] id int)` 传入 `id = 0`
- **THEN** 抛出 `ConstraintViolationException`

### Requirement: Metrics 指标
系统 SHALL 提供 `MeterRegistry`/`Counter`/`Gauge`/`Timer` 抽象与内存实现，`/metrics` 端点返回 Prometheus 文本格式。

#### Scenario: 计数器递增
- **WHEN** `counter.increment()` 调用 3 次
- **THEN** `/metrics` 返回 `photon_counter_total 3`

### Requirement: 分布式追踪
系统 SHALL 提供 `TraceContext`/`Span` 抽象与内存 tracer，`@[trace]` 注解自动开启 span 并记录耗时。

#### Scenario: Trace 注解开 span
- **WHEN** `@[trace] fn handle_request()` 被调用
- **THEN** tracer 记录一个名为 `handle_request` 的 span，包含开始/结束时间

### Requirement: 健康检查
系统 SHALL 提供 `HealthIndicator` 接口，`/health` 端点聚合所有指示器结果，状态为 UP/DOWN，DOWN 时 HTTP 503。

#### Scenario: DB 健康检查
- **WHEN** DB 连接正常
- **THEN** `/health` 返回 `{"status":"UP","components":{"db":{"status":"UP"}}}`

### Requirement: 优雅停机
系统 SHALL 在收到 SIGTERM/SIGINT 时停止接受新请求，等待在途请求完成（默认 30s），超时强制关闭。

#### Scenario: SIGTERM 触发停机
- **WHEN** 进程收到 SIGTERM
- **THEN** 停止监听新连接
- **AND** 等待在途请求完成或 30s 超时
- **AND** 调用所有 `DisposableBean.destroy()` 与 `@pre_destroy`
- **AND** 进程退出码 0

### Requirement: `/loggers` 运行时日志级别
系统 SHALL 提供 `/loggers` 端点，GET 返回所有 logger 及其级别，POST `{level: "DEBUG"}` 调整指定 logger 级别。

#### Scenario: 调整级别
- **WHEN** POST `/loggers/com.photon.db` body `{"level":"DEBUG"}`
- **THEN** 后续 `com.photon.db` 的 DEBUG 日志输出

### Requirement: 自省端点
系统 SHALL 提供 `/env`（配置键值）、`/beans`（Bean 列表含类型/作用域/懒加载）、`/mappings`（所有路由表）端点。

#### Scenario: 查询 Bean 列表
- **WHEN** GET `/beans`
- **THEN** 返回 JSON 数组，每项含 `name`/`type`/`scope`/`lazy`

### Requirement: `/info` 端点
系统 SHALL 提供 `/info` 端点，返回构建信息（version/commit/build_time），信息来自编译期注入或 `build.info` 文件。

#### Scenario: 查询构建信息
- **WHEN** GET `/info`
- **THEN** 返回 `{"build":{"version":"0.4.0","commit":"abc123","time":"2026-06-20T10:00:00Z"}}`

### Requirement: K8s 探针
系统 SHALL 提供 `/health/liveness`（存活探针，进程存活即 200）与 `/health/readiness`（就绪探针，所有 `SmartLifecycle` 就绪后 200）端点。

#### Scenario: 就绪探针
- **WHEN** 应用启动完成且所有 `SmartLifecycle.is_running() == true`
- **THEN** `/health/readiness` 返回 200
- **AND** 启动中返回 503

## MODIFIED Requirements

### Requirement: AutoConfigurationManager
原实现仅提供数据结构，无 comptime 扫描。修改为：启动时通过 comptime `$for` 扫描所有 `@[auto_configuration]` 类型并自动注册，按 `@Conditional` 决定是否激活。

### Requirement: ValueAnnotationPostProcessor
原实现为空壳（before/after 直接返回 bean）。修改为：comptime 扫描 `@[value('key')]` 字段，从 `Environment` 取值并类型转换后注入。

### Requirement: JpaRepository[T]
原实现仅 `find_by_id`/`save`/`delete`/`find_all`/`count`/`create_table`。新增 `find_all(page PageRequest) Page[T]`、`find_by_<field>_<keyword>(...)` 派生查询、`@[query]` 原生 SQL、`@[version]` 乐观锁。

### Requirement: 事务管理
原实现 `isolation`/`readonly`/`timeout`/`rollback_for` 仅解析不执行。修改为：`begin` 设置 isolation，`readonly` 拦截写操作，`timeout` 超时回滚，`rollback` 按 `rollback_for`/`no_rollback_for` 决策。

### Requirement: 迁移系统
原实现 `initialize()` 不建表、`migrate()` 仅内存跟踪。修改为：`initialize()` 建 `_photon_migrations` 表，`migrate()` 执行 up SQL 并记录版本。

### Requirement: 缓存注解
原实现 `condition`/`unless` 解析但不求值。修改为：在 `get_or_compute`/`put` 中对表达式求值，决定是否缓存。

### Requirement: 安全注解
原实现 `@PreAuthorize` 仅支持 `hasPermission()`。修改为：支持 `hasRole`/`hasAuthority`/`hasAnyRole`/`hasAnyAuthority`/`hasPermission`，新增 `@PostAuthorize`。

### Requirement: Web 服务器
原实现 `veb.run_at` 阻塞且无信号处理。修改为：注册 SIGTERM/SIGINT 处理器，收到信号后优雅停机。

### Requirement: 健康检查
原实现 `HealthService.health()` 返回硬编码 `status: 'UP'`。修改为：聚合所有 `HealthIndicator` 结果，真实反映 DB/Cache/Disk/Memory 状态。

### Requirement: 日志系统
原实现单全局 `level`。修改为：支持按命名空间（`com.photon.db`）独立级别，`/loggers` 端点运行时调整。

## REMOVED Requirements

无删除项。所有变更均为新增或增强，保持向后兼容。
