# Tasks — Photon 深度优化 v2

> 基于 Spring Framework 6 + Hyperf 3.1 设计理念对标
> 详细方案见 `DEEP_OPTIMIZATION_PLAN.md`

## Phase 1: IoC/DI 容器深度改造 (P0)

- [ ] Task 1.1: BeanFactory 接口分层
  - [ ] SubTask 1.1.1: 在 `core/core.v` 新增 `BeanFactory` / `ListableBeanFactory` / `HierarchicalBeanFactory` 接口定义
  - [ ] SubTask 1.1.2: `Container` 实现三个接口（现有方法已满足，需添加 `impl` 声明）
  - [ ] SubTask 1.1.3: 创建 `core/bean_factory_interface_test.v` 验证接口实现
  - [ ] SubTask 1.1.4: 运行 `v test core/` 验证通过

- [ ] Task 1.2: @Bean 方法注解支持
  - [ ] SubTask 1.2.1: 在 `core/scanner.v` 新增 `extract_bean_methods[T]()` comptime 函数，扫描 `@[bean]` 注解方法
  - [ ] SubTask 1.2.2: 提取方法返回类型作为 bean type_name，方法参数作为依赖
  - [ ] SubTask 1.2.3: 在 `register_component[T]()` 中自动注册 @[bean] 方法产生的 bean
  - [ ] SubTask 1.2.4: 创建 `core/bean_method_test.v` 验证 @[bean] 方法扫描注册、参数注入、跨 bean 引用
  - [ ] SubTask 1.2.5: 运行 `v test core/` 验证通过

- [ ] Task 1.3: BeanDefinitionRegistryPostProcessor
  - [ ] SubTask 1.3.1: 在 `core/post_processor.v` 新增 `BeanDefinitionRegistryPostProcessor` 接口
  - [ ] SubTask 1.3.2: 在 `ApplicationContext` 新增 `registry_post_processors []&BeanDefinitionRegistryPostProcessor` 字段
  - [ ] SubTask 1.3.3: 在 `refresh()` 步骤 1 之前调用所有 RegistryPostProcessor
  - [ ] SubTask 1.3.4: 创建 `core/registry_post_processor_test.v` 验证动态注册新 BeanDefinition
  - [ ] SubTask 1.3.5: 运行 `v test core/` 验证通过

- [ ] Task 1.4: @Profile 注解驱动
  - [ ] SubTask 1.4.1: 在 `core/condition.v` 新增 `OnProfileCondition` 条件评估器
  - [ ] SubTask 1.4.2: 在 `core/scanner.v` 新增 `@[profile('dev')]` 注解解析，转换为 `OnProfileCondition`
  - [ ] SubTask 1.4.3: 在 `register_component[T]()` 中检查 `@[profile]` 并自动添加条件
  - [ ] SubTask 1.4.4: 创建 `core/profile_annotation_test.v` 验证激活/未激活 Profile 场景
  - [ ] SubTask 1.4.5: 运行 `v test core/` 验证通过

- [ ] Task 1.5: 简易表达式引擎 (Photon EL)
  - [ ] SubTask 1.5.1: 新建 `core/expression.v`，实现表达式词法分析器
  - [ ] SubTask 1.5.2: 实现属性访问 `#{config.db.host}` 解析
  - [ ] SubTask 1.5.3: 实现算术运算 `#{1 + 2}`、比较 `#{a == b}`、逻辑 `#{a and b}`
  - [ ] SubTask 1.5.4: 实现字符串字面量 `#{'literal'}` 和拼接
  - [ ] SubTask 1.5.5: 集成到 `@[value]` 注解（`@[value('#{app.name}')]`）
  - [ ] SubTask 1.5.6: 新增 `@[conditional_on_expression('env == prod')]` 条件
  - [ ] SubTask 1.5.7: 创建 `core/expression_test.v` 覆盖所有表达式类型
  - [ ] SubTask 1.5.8: 运行 `v test core/` 验证通过

## Phase 2: AOP 面向切面编程增强 (P1)

- [ ] Task 2.1: 声明式切面 (@Aspect + @Pointcut)
  - [ ] SubTask 2.1.1: 新建 `core/aop.v`，定义 `Aspect` / `MethodBeforeAdvice` / `MethodAfterAdvice` / `MethodAroundAdvice` 接口
  - [ ] SubTask 2.1.2: 实现切点表达式解析器（`execution(*.Service.*)` / `annotation(cacheable)` / `within(controller)`）
  - [ ] SubTask 2.1.3: 在 `core/scanner.v` 新增 `@[aspect]` 注解扫描
  - [ ] SubTask 2.1.4: 在 `autowire_bean[T]()` 中检测匹配的 Aspect 并织入通知
  - [ ] SubTask 2.1.5: 创建 `core/aop_aspect_test.v` 验证切面注册、切点匹配、通知执行顺序
  - [ ] SubTask 2.1.6: 运行 `v test core/` 验证通过

- [ ] Task 2.2: @Pointcut 注解和切点组合
  - [ ] SubTask 2.2.1: 支持 `@[pointcut('execution(*.UserService.*))]` 命名切点
  - [ ] SubTask 2.2.2: 支持切点组合 `&&` / `||` / `!`
  - [ ] SubTask 2.2.3: 支持通配符 `*` 匹配
  - [ ] SubTask 2.2.4: 创建 `core/aop_pointcut_test.v` 验证组合表达式
  - [ ] SubTask 2.2.5: 运行 `v test core/` 验证通过

## Phase 3: ORM 查询构造器与仓库模式优化 (P0)

- [ ] Task 3.1: Specification 动态查询模式
  - [ ] SubTask 3.1.1: 新建 `orm/specification.v`，定义 `Specification[T]` 接口和 `QueryPredicate` struct
  - [ ] SubTask 3.1.2: 定义 `QueryOperator` 枚举（.eq, .ne, .gt, .lt, .like, .in, .is_null, .between）
  - [ ] SubTask 3.1.3: 实现 `Specifications.where()` / `.and()` / `.or()` 链式组合器
  - [ ] SubTask 3.1.4: 在 `BaseRepository[T]` 新增 `find_all_with_spec(spec Specification[T]) ![]T`
  - [ ] SubTask 3.1.5: 在 `BaseRepository[T]` 新增 `count_with_spec(spec Specification[T]) !int`
  - [ ] SubTask 3.1.6: 创建 `orm/specification_test.v` 验证单条件/多条件/排序/分页
  - [ ] SubTask 3.1.7: 运行 `v test orm/` 验证通过

- [ ] Task 3.2: 标准化 Pageable / Sort
  - [ ] SubTask 3.2.1: 新建 `orm/pageable.v`，定义 `PageRequest` / `Page[T]` / `Sort` / `SortOrder` 类型
  - [ ] SubTask 3.2.2: `BaseRepository[T]` 新增 `find_all_paged(pageable PageRequest) !Page[T]`
  - [ ] SubTask 3.2.3: 自动生成 count 查询填充 `Page[T].total`
  - [ ] SubTask 3.2.4: 计算 `total_pages` / `has_next` / `has_previous`
  - [ ] SubTask 3.2.5: 创建 `orm/pageable_test.v` 验证分页、排序、边界
  - [ ] SubTask 3.2.6: 运行 `v test orm/` 验证通过

- [ ] Task 3.3: @Modifying 查询标记
  - [ ] SubTask 3.3.1: 在 `orm/query.v` 新增 `@[modifying]` 注解解析
  - [ ] SubTask 3.3.2: `execute_named_query` 检查 modifying 标记，返回影响行数
  - [ ] SubTask 3.3.3: 在 comptime 扫描时区分查询型和修改型方法
  - [ ] SubTask 3.3.4: 创建 `orm/modifying_query_test.v` 验证 UPDATE/DELETE 执行
  - [ ] SubTask 3.3.5: 运行 `v test orm/` 验证通过

- [ ] Task 3.4: DTO 投影支持
  - [ ] SubTask 3.4.1: 在 `BaseRepository[T]` 新增 `find_projected[P](query string, params map[string]string) ![]P`
  - [ ] SubTask 3.4.2: comptime 生成器利用 `json.decode[P]` 将查询结果映射到 DTO
  - [ ] SubTask 3.4.3: 支持接口投影（只查询指定字段）
  - [ ] SubTask 3.4.4: 创建 `orm/projection_test.v` 验证 DTO 映射
  - [ ] SubTask 3.4.5: 运行 `v test orm/` 验证通过

- [ ] Task 3.5: 读写分离路由
  - [ ] SubTask 3.5.1: 在 `orm/orm.v` 新增 `RoutingPolicy` 接口和 `ReadWriteRoutingPolicy` 实现
  - [ ] SubTask 3.5.2: 在 `OrmManager` 新增 `set_routing_policy(policy &RoutingPolicy)`
  - [ ] SubTask 3.5.3: 在 `BaseRepository[T]` 保存/查询时根据 RoutingPolicy 选择连接
  - [ ] SubTask 3.5.4: 集成 `@[transactional(readonly: true)]` 注解到路由决策
  - [ ] SubTask 3.5.5: 创建 `orm/read_write_split_test.v` 验证路由策略
  - [ ] SubTask 3.5.6: 运行 `v test orm/` 验证通过

## Phase 4: Web MVC 与中间件链改造 (P0)

- [ ] Task 4.1: 方法参数绑定与 @RequestBody
  - [ ] SubTask 4.1.1: 在 `web/bind.v` 新增 `@[request_body]` / `@[path_param]` / `@[query_param]` 注解解析
  - [ ] SubTask 4.1.2: 在 comptime 路由扫描时检测方法参数注解并生成绑定代码
  - [ ] SubTask 4.1.3: `@[request_body]` 自动调用 `json.decode[T](ctx.body)` 反序列化
  - [ ] SubTask 4.1.4: `@[path_param]` 自动从路由参数提取并类型转换（int/bool/string）
  - [ ] SubTask 4.1.5: `@[query_param]` 自动从 URL 查询参数提取
  - [ ] SubTask 4.1.6: 绑定失败时返回 400 Bad Request + ProblemDetail
  - [ ] SubTask 4.1.7: 创建 `web/param_binding_test.v` 验证各类型绑定
  - [ ] SubTask 4.1.8: 运行 `v test web/` 验证通过

- [ ] Task 4.2: ResponseEntity 链式构建器
  - [ ] SubTask 4.2.1: 新建 `web/response_entity.v`，定义 `ResponseEntity` struct
  - [ ] SubTask 4.2.2: 实现 `ok()` / `created()` / `no_content()` / `bad_request()` 等工厂方法
  - [ ] SubTask 4.2.3: 实现 `header()` / `status_code()` / `body()` 链式方法
  - [ ] SubTask 4.2.4: 实现 `build()` 转换为 `veb.Result`
  - [ ] SubTask 4.2.5: 创建 `web/response_entity_test.v` 验证链式构建
  - [ ] SubTask 4.2.6: 运行 `v test web/` 验证通过

- [ ] Task 4.3: HandlerInterceptor 三阶段中间件
  - [ ] SubTask 4.3.1: 新建 `web/interceptor.v`，定义 `HandlerInterceptor` 接口
  - [ ] SubTask 4.3.2: 实现 `InterceptorRegistry` 管理注册的拦截器
  - [ ] SubTask 4.3.3: 实现 `pre_handle` / `post_handle` / `after_completion` 三阶段调度
  - [ ] SubTask 4.3.4: 与现有 `MiddlewareChain` 集成（全局 Middleware + 路由级 Interceptor）
  - [ ] SubTask 4.3.5: 创建 `web/interceptor_test.v` 验证三阶段执行
  - [ ] SubTask 4.3.6: 运行 `v test web/` 验证通过

- [ ] Task 4.4: @RestController 复合注解
  - [ ] SubTask 4.4.1: 新增 `@[rest_controller]` 注解 = `@[controller]` + JSON 响应模式
  - [ ] SubTask 4.4.2: comptime 扫描时检测 `@[rest_controller]`，设置 Content-Type: application/json
  - [ ] SubTask 4.4.3: 方法返回 struct 时自动 JSON 序列化
  - [ ] SubTask 4.4.4: 创建 `web/rest_controller_test.v` 验证自动序列化
  - [ ] SubTask 4.4.5: 运行 `v test web/` 验证通过

- [ ] Task 4.5: WebMvcConfigurer 统一配置接口
  - [ ] SubTask 4.5.1: 新建 `web/configurer.v`，定义 `WebMvcConfigurer` 接口
  - [ ] SubTask 4.5.2: 包含 `configure_interceptors` / `configure_content_negotiation` / `configure_resource_handlers` / `configure_argument_resolvers`
  - [ ] SubTask 4.5.3: `ApplicationContext` 在 refresh 时扫描 `@[web_configurer]` Bean
  - [ ] SubTask 4.5.4: 创建 `web/configurer_test.v` 验证自定义配置
  - [ ] SubTask 4.5.5: 运行 `v test web/` 验证通过

## Phase 5: 缓存抽象层深度封装 (P1)

- [ ] Task 5.1: @CacheConfig 类级缓存配置
  - [ ] SubTask 5.1.1: 在 `cache/annotation.v` 新增 `parse_cache_config_attr()` 解析 `@[cache_config]`
  - [ ] SubTask 5.1.2: comptime 扫描时将类级配置应用于所有 `@[cacheable]` 方法
  - [ ] SubTask 5.1.3: 方法级配置覆盖类级配置
  - [ ] SubTask 5.1.4: 创建 `cache/cache_config_test.v` 验证继承和覆盖
  - [ ] SubTask 5.1.5: 运行 `v test cache/` 验证通过

- [ ] Task 5.2: sync 同步加载注解
  - [ ] SubTask 5.2.1: `@[cacheable]` 新增 `sync: true` 属性解析
  - [ ] SubTask 5.2.2: 启用 sync 时使用 `singleflight.do()` 确保单次加载
  - [ ] SubTask 5.2.3: 创建 `cache/sync_cacheable_test.v` 验证并发安全
  - [ ] SubTask 5.2.4: 运行 `v test cache/` 验证通过

- [ ] Task 5.3: 缓存统计与 Actuator 集成
  - [ ] SubTask 5.3.1: `Cache` 接口新增 `stats() CacheStats` 方法
  - [ ] SubTask 5.3.2: `MemoryCache` 实现统计计数（hits/misses/evictions）
  - [ ] SubTask 5.3.3: 在 `web/actuator_metrics.v` 新增 `/actuator/cache` 端点
  - [ ] SubTask 5.3.4: 创建 `cache/cache_stats_test.v` 验证统计准确性
  - [ ] SubTask 5.3.5: 运行 `v test cache/ web/` 验证通过

- [ ] Task 5.4: CachingConfigurer 全局配置接口
  - [ ] SubTask 5.4.1: 新建 `cache/configurer.v`，定义 `CachingConfigurer` 接口
  - [ ] SubTask 5.4.2: `ApplicationContext` 扫描 `@[caching_configurer]` Bean
  - [ ] SubTask 5.4.3: 创建 `cache/configurer_test.v` 验证自定义 KeyGenerator / CacheManager
  - [ ] SubTask 5.4.4: 运行 `v test cache/` 验证通过

## Phase 6: 事件机制增强 (P1)

- [ ] Task 6.1: 类型化事件 (TypedEvent[T])
  - [ ] SubTask 6.1.1: 新建 `core/typed_event.v`，定义 `TypedEvent[T]` 和 `TypedEventListener[T]`
  - [ ] SubTask 6.1.2: `EventBus` 新增 `on_typed[T]()` 和 `dispatch_typed[T]()` 方法
  - [ ] SubTask 6.1.3: 创建 `core/typed_event_test.v` 验证类型安全
  - [ ] SubTask 6.1.4: 运行 `v test core/` 验证通过

- [ ] Task 6.2: @EventListener 条件表达式
  - [ ] SubTask 6.2.1: `@[event_listener]` 注解新增 `condition` 属性
  - [ ] SubTask 6.2.2: 使用 Phase 1 的表达式引擎评估条件
  - [ ] SubTask 6.2.3: 创建 `core/event_condition_test.v` 验证条件匹配
  - [ ] SubTask 6.2.4: 运行 `v test core/` 验证通过

- [ ] Task 6.3: 事件继承传播
  - [ ] SubTask 6.3.1: 建立事件类型层级关系（利用 type_index）
  - [ ] SubTask 6.3.2: `dispatch()` 时递归查找父事件监听器
  - [ ] SubTask 6.3.3: 创建 `core/event_inheritance_test.v` 验证父子事件传播
  - [ ] SubTask 6.3.4: 运行 `v test core/` 验证通过

## Phase 7: 配置管理与属性绑定增强 (P1)

- [ ] Task 7.1: Placeholder 解析器
  - [ ] SubTask 7.1.1: 新建 `config/placeholder.v`，实现 `resolve_placeholders()` 函数
  - [ ] SubTask 7.1.2: 支持 `${key}` / `${key:default}` / `${key:-default}` 格式
  - [ ] SubTask 7.1.3: 支持嵌套 placeholder 解析
  - [ ] SubTask 7.1.4: 在 `Environment.get_property()` 中自动解析
  - [ ] SubTask 7.1.5: 在 `@[value]` 注入时解析
  - [ ] SubTask 7.1.6: 创建 `config/placeholder_test.v` 验证各种格式
  - [ ] SubTask 7.1.7: 运行 `v test config/` 验证通过

- [ ] Task 7.2: @ConfigurationProperties 验证
  - [ ] SubTask 7.2.1: 在 `bind_to_struct[T]()` 后自动执行字段验证
  - [ ] SubTask 7.2.2: 扫描 `@[not_blank]` / `@[min(1)]` / `@[max(100)]` / `@[email]` 注解
  - [ ] SubTask 7.2.3: 验证失败返回详细错误（字段名 + 违反约束）
  - [ ] SubTask 7.2.4: 创建 `config/validation_binding_test.v` 验证约束检查
  - [ ] SubTask 7.2.5: 运行 `v test config/` 验证通过

- [ ] Task 7.3: PropertySource 优先级
  - [ ] SubTask 7.3.1: `ConfigSource` 接口新增 `priority() int` 方法
  - [ ] SubTask 7.3.2: `Config.load()` 按优先级从低到高加载
  - [ ] SubTask 7.3.3: 标准优先级：环境变量 > 命令行 > Profile 文件 > 默认文件
  - [ ] SubTask 7.3.4: 创建 `config/priority_test.v` 验证优先级覆盖
  - [ ] SubTask 7.3.5: 运行 `v test config/` 验证通过

- [ ] Task 7.4: 环境变量约定覆盖
  - [ ] SubTask 7.4.1: 支持 `PHOTON_` 前缀环境变量映射到配置
  - [ ] SubTask 7.4.2: `PHOTON_DB_HOST` → `db.host`，`__` 转为 `.`
  - [ ] SubTask 7.4.3: 在 `Config.load()` 时自动扫描
  - [ ] SubTask 7.4.4: 创建 `config/env_override_test.v` 验证映射
  - [ ] SubTask 7.4.5: 运行 `v test config/` 验证通过

## Phase 8: 日志系统增强 (P2)

- [ ] Task 8.1: 多 Appender 输出
  - [ ] SubTask 8.1.1: 新建 `logger/appender.v`，定义 `Appender` 接口
  - [ ] SubTask 8.1.2: 实现 `ConsoleAppender`（标准输出）
  - [ ] SubTask 8.1.3: 实现 `FileAppender`（文件写入 + flush）
  - [ ] SubTask 8.1.4: 实现 `CompositeAppender`（多路输出）
  - [ ] SubTask 8.1.5: `Logger` 持有 `[]Appender`，每次日志写入所有 appender
  - [ ] SubTask 8.1.6: 创建 `logger/appender_test.v` 验证多路输出
  - [ ] SubTask 8.1.7: 运行 `v test logger/` 验证通过

- [ ] Task 8.2: 异步日志
  - [ ] SubTask 8.2.1: 实现 `AsyncAppender`，包装其他 Appender
  - [ ] SubTask 8.2.2: 使用 `async.TaskExecutor` 作为写入线程池
  - [ ] SubTask 8.2.3: 有界队列 + 丢弃策略（防 OOM）
  - [ ] SubTask 8.2.4: 创建 `logger/async_test.v` 验证异步写入
  - [ ] SubTask 8.2.5: 运行 `v test logger/` 验证通过

- [ ] Task 8.3: 日志轮转
  - [ ] SubTask 8.3.1: `FileAppender` 新增 `RollingPolicy` 配置
  - [ ] SubTask 8.3.2: 按大小轮转：`max_size` bytes 触发新文件
  - [ ] SubTask 8.3.3: 按时间轮转：每日一个文件
  - [ ] SubTask 8.3.4: 保留最近 N 个日志文件
  - [ ] SubTask 8.3.5: 创建 `logger/rolling_test.v` 验证轮转
  - [ ] SubTask 8.3.6: 运行 `v test logger/` 验证通过

- [ ] Task 8.4: 运行时级别调整
  - [ ] SubTask 8.4.1: `Logger` 新增 `set_level(level Level)` 方法（线程安全）
  - [ ] SubTask 8.4.2: 集成 `/actuator/loggers` POST 端点动态修改
  - [ ] SubTask 8.4.3: 创建 `logger/dynamic_level_test.v` 验证动态调整
  - [ ] SubTask 8.4.4: 运行 `v test logger/ web/` 验证通过

- [ ] Task 8.5: 结构化字段 API
  - [ ] SubTask 8.5.1: `Logger` 新增 `with_field(key, val) &Logger` 方法
  - [ ] SubTask 8.5.2: 返回带预设字段的子 Logger（不修改原 Logger）
  - [ ] SubTask 8.5.3: `log()` 时将预设字段与 MDC 合并
  - [ ] SubTask 8.5.4: 创建 `logger/fields_test.v` 验证链式字段
  - [ ] SubTask 8.5.5: 运行 `v test logger/` 验证通过

## Phase 9: 异常处理体系统一 (P0)

- [ ] Task 9.1: ProblemDetail (RFC 7807)
  - [ ] SubTask 9.1.1: 新建 `web/problem_detail.v`，定义 `ProblemDetail` struct
  - [ ] SubTask 9.1.2: 实现 `problem()` 工厂方法和 `with_ext()` 链式方法
  - [ ] SubTask 9.1.3: 实现 `to_json()` 序列化
  - [ ] SubTask 9.1.4: `ExceptionHandler` 默认输出 ProblemDetail JSON
  - [ ] SubTask 9.1.5: Content-Type: `application/problem+json`
  - [ ] SubTask 9.1.6: 创建 `web/problem_detail_test.v` 验证序列化
  - [ ] SubTask 9.1.7: 运行 `v test web/` 验证通过

- [ ] Task 9.2: @ResponseStatus 注解
  - [ ] SubTask 9.2.1: 新增 `@[status_code(404)]` 注解标注自定义异常
  - [ ] SubTask 9.2.2: comptime 扫描异常 struct 的 `@[status_code]` 注解
  - [ ] SubTask 9.2.3: `ExceptionResolver` 优先使用注解状态码
  - [ ] SubTask 9.2.4: 创建 `web/status_code_annotation_test.v` 验证映射
  - [ ] SubTask 9.2.5: 运行 `v test web/` 验证通过

- [ ] Task 9.3: 方法级 @ExceptionHandler
  - [ ] SubTask 9.3.1: 在 `@[controller_advice]` 类中支持 `@[exception_handler('NotFoundError')]` 方法注解
  - [ ] SubTask 9.3.2: comptime 扫描方法参数类型确定处理异常类型
  - [ ] SubTask 9.3.3: `ExceptionResolver` 按异常类型精确匹配
  - [ ] SubTask 9.3.4: 创建 `web/method_exception_handler_test.v` 验证方法级处理
  - [ ] SubTask 9.3.5: 运行 `v test web/` 验证通过

- [ ] Task 9.4: 异常处理链优先级
  - [ ] SubTask 9.4.1: `ExceptionResolver` 支持多 Handler，按优先级排序
  - [ ] SubTask 9.4.2: 优先级：控制器方法级 > 类级 > 全局 > 默认
  - [ ] SubTask 9.4.3: 最精确匹配优先（子异常 > 父异常）
  - [ ] SubTask 9.4.4: 创建 `web/exception_priority_test.v` 验证优先级
  - [ ] SubTask 9.4.5: 运行 `v test web/` 验证通过

## Phase 10: 协程与异步任务增强 (P2)

- [ ] Task 10.1: Future 返回型异步
  - [ ] SubTask 10.1.1: 新建 `async/future.v`，定义 `Future[T]` struct
  - [ ] SubTask 10.1.2: 实现 `await()` / `await_timeout()` / `is_ready()` 方法
  - [ ] SubTask 10.1.3: `TaskExecutor` 新增 `submit_with_result[T]()` 方法
  - [ ] SubTask 10.1.4: 创建 `async/future_test.v` 验证 await/超时
  - [ ] SubTask 10.1.5: 运行 `v test async/` 验证通过

- [ ] Task 10.2: 上下文传播
  - [ ] SubTask 10.2.1: 新建 `async/context.v`，定义 `AsyncContext` struct
  - [ ] SubTask 10.2.2: 实现 `current_context()` 和 `propagate()` 方法
  - [ ] SubTask 10.2.3: `TaskExecutor.submit()` 时自动复制上下文
  - [ ] SubTask 10.2.4: 创建 `async/context_propagation_test.v` 验证传播
  - [ ] SubTask 10.2.5: 运行 `v test async/` 验证通过

- [ ] Task 10.3: 线程池监控
  - [ ] SubTask 10.3.1: `TaskExecutor` 新增 `stats() ExecutorStats` 方法
  - [ ] SubTask 10.3.2: 集成 `/actuator/executor` 端点
  - [ ] SubTask 10.3.3: 创建 `async/executor_stats_test.v` 验证统计
  - [ ] SubTask 10.3.4: 运行 `v test async/ web/` 验证通过

## Phase 11: 服务发现与注册中心 (P3)

- [ ] Task 11.1: ServiceRegistry 抽象
  - [ ] SubTask 11.1.1: 新建 `discovery/` 模块，定义 `ServiceRegistry` 接口和 `ServiceInstance` struct
  - [ ] SubTask 11.1.2: 实现 `InMemoryServiceRegistry`（开发/测试用）
  - [ ] SubTask 11.1.3: 预留 Consul/Etcd 接口
  - [ ] SubTask 11.1.4: 创建 `discovery/registry_test.v` 验证注册/注销/查询
  - [ ] SubTask 11.1.5: 运行 `v test discovery/` 验证通过

- [ ] Task 11.2: 客户端负载均衡
  - [ ] SubTask 11.2.1: 新建 `discovery/loadbalancer.v`，定义 `LoadBalancer` 接口
  - [ ] SubTask 11.2.2: 实现 RoundRobin / Random / Weighted 策略
  - [ ] SubTask 11.2.3: 集成 HTTP 客户端自动选择实例
  - [ ] SubTask 11.2.4: 创建 `discovery/loadbalancer_test.v` 验证策略
  - [ ] SubTask 11.2.5: 运行 `v test discovery/` 验证通过

- [ ] Task 11.3: @ServiceClient 声明式客户端
  - [ ] SubTask 11.3.1: `@[service_client('service-name')]` 标注接口
  - [ ] SubTask 11.3.2: comptime 生成代理 struct，方法调用自动转发
  - [ ] SubTask 11.3.3: 创建 `discovery/service_client_test.v` 验证转发
  - [ ] SubTask 11.3.4: 运行 `v test discovery/` 验证通过

## Phase 12: 请求客户端封装 (P2)

- [ ] Task 12.1: 链式 HTTP 客户端
  - [ ] SubTask 12.1.1: 重构 `http/client.v`，提供链式 API
  - [ ] SubTask 12.1.2: 支持 `.header()` / `.query()` / `.json_body()` / `.timeout()` / `.retry()`
  - [ ] SubTask 12.1.3: 创建 `http/client_chain_test.v` 验证链式构建
  - [ ] SubTask 12.1.4: 运行 `v test http/` 验证通过

- [ ] Task 12.2: 请求/响应拦截器
  - [ ] SubTask 12.2.1: 定义 `ClientInterceptor` 接口
  - [ ] SubTask 12.2.2: 实现请求拦截器修改 header、响应拦截器记录日志
  - [ ] SubTask 12.2.3: 创建 `http/interceptor_test.v` 验证拦截
  - [ ] SubTask 12.2.4: 运行 `v test http/` 验证通过

- [ ] Task 12.3: 类型化响应反序列化
  - [ ] SubTask 12.3.1: 新增 `get_typed[T](url) !T` 方法
  - [ ] SubTask 12.3.2: 自动 `json.decode[T]` 反序列化
  - [ ] SubTask 12.3.3: 错误响应自动转换为 HttpException
  - [ ] SubTask 12.3.4: 创建 `http/typed_response_test.v` 验证反序列化
  - [ ] SubTask 12.3.5: 运行 `v test http/` 验证通过
