# Photon Framework — 深度优化方案

> 生成日期: 2026-06-24 | 版本: 0.2.0-rc | 基于 Spring Framework 6 + Hyperf 3.1 设计理念对标
>
> 本文档是对 Photon 框架现有 16 个模块进行深度对比分析后的优化方案，不盲目开发，
> 每个任务都标注了对应的 Spring/Hyperf 等价实现和现有 Photon 类比实现。

---

## 目录

1. [现有架构评估总结](#1-现有架构评估总结)
2. [Phase 1: IoC/DI 容器深度改造](#phase-1-iocdi-容器深度改造)
3. [Phase 2: AOP 面向切面编程增强](#phase-2-aop-面向切面编程增强)
4. [Phase 3: ORM 查询构造器与仓库模式优化](#phase-3-orm-查询构造器与仓库模式优化)
5. [Phase 4: Web MVC 与中间件链改造](#phase-4-web-mvc-与中间件链改造)
6. [Phase 5: 缓存抽象层深度封装](#phase-5-缓存抽象层深度封装)
7. [Phase 6: 事件机制增强](#phase-6-事件机制增强)
8. [Phase 7: 配置管理与属性绑定增强](#phase-7-配置管理与属性绑定增强)
9. [Phase 8: 日志系统增强](#phase-8-日志系统增强)
10. [Phase 9: 异常处理体系统一](#phase-9-异常处理体系统一)
11. [Phase 10: 协程与异步任务增强](#phase-10-协程与异步任务增强)
12. [Phase 11: 服务发现与注册中心](#phase-11-服务发现与注册中心)
13. [Phase 12: 请求客户端封装](#phase-12-请求客户端封装)
14. [测试策略与验收标准](#测试策略与验收标准)
15. [文档更新清单](#文档更新清单)

---

## 1. 现有架构评估总结

### 1.1 已完成的优化（前序阶段）

| 阶段 | 完成项 | 状态 |
|------|--------|------|
| P0 安全修复 | XOR Encrypter 废弃、BcryptHasher 真实 KDF、JWT 迁移 crypto | ✅ |
| P0 正确性 | TransactionManager 真实 DB 连接、HttpKernel.handle() 实现 | ✅ |
| P1 架构补全 | PasswordEncoder 体系、CacheManager 接口、ConversionService | ✅ |
| P1 架构补全 | ContentNegotiationManager、ResourceHandlerRegistry | ✅ |
| P1 架构补全 | TransactionalEventListener、条件装配增强 | ✅ |
| P2 性能优化 | ShardedRwMutex、LRU O(1)、Singleflight channel 唤醒 | ✅ |
| P2 性能优化 | HttpKernel 冻结快照、拓扑排序 O(n)、Logger 零拷贝 MDC | ✅ |
| P2 代码质量 | 锁范围收窄、unsafe nil → Option/哨兵、fnv1a 零拷贝 | ✅ |

### 1.2 现有模块成熟度

| 模块 | 行数(估) | 测试文件数 | 成熟度 | 与 Spring 差距 |
|------|----------|-----------|--------|---------------|
| core | ~3500 | 15 | Beta | 中等 — 缺 AOP 代理、SpEL、BeanDefinitionRegistryPostProcessor |
| web | ~4000 | 20 | Beta | 中等 — 缺 @RequestBody、ResponseEntity、HandlerInterceptor |
| orm | ~3000 | 15 | Beta | 较大 — 缺 Specification、Criteria、Projection、@Modifying |
| cache | ~800 | 8 | Beta | 较小 — 缺 sync=true、@CacheConfig、统计 |
| security | ~2000 | 12 | Beta | 中等 — 缺 SecurityFilterChain 集成、MethodSecurity |
| config | ~500 | 4 | Alpha | 较大 — 缺 @ConfigurationProperties 验证、placeholder 解析 |
| logger | ~600 | 2 | Alpha | 较大 — 缺异步日志、日志轮转、多输出 |
| async | ~300 | 2 | Alpha | 较大 — 缺 Future 返回、上下文传播 |
| queue | ~800 | 3 | Beta | 中等 — 缺延迟队列精度、死信队列 |
| event | ~500 | 4 | Beta | 较小 — 缺类型化事件、条件监听 |

---

## Phase 1: IoC/DI 容器深度改造

### 对标分析

| Spring 特性 | Hyperf 特性 | Photon 现状 | 差距 |
|------------|-----------|------------|------|
| BeanFactory → ListableBeanFactory → ApplicationContext 层级 | Container 实现 PSR-11 | Container + ApplicationContext 扁平 | 缺少 BeanFactory 接口分层 |
| @Configuration + @Bean 方法注解 | #[Configuration] + #[Bean] | 有 @[configuration] 但无 @[bean] 方法注解 | 缺方法级 Bean 声明 |
| BeanDefinitionRegistryPostProcessor | 无直接等价 | 有 BeanFactoryPostProcessor | 缺注册后处理器 |
| SpEL 表达式解析 | 无 | 无 | 缺表达式引擎 |
| @Profile 注解驱动 | env 配置驱动 | 编程式 set_profiles | 缺注解式 Profile |
| 三级缓存解决循环依赖 | 无（协程无此问题） | 编译期检测 + 运行期 instantiating 标记 | 可借鉴三级缓存支持 setter 循环依赖 |

### Task 1.1: BeanFactory 接口分层

**Spring 类比**: `BeanFactory` → `ListableBeanFactory` → `HierarchicalBeanFactory` → `ApplicationContext`

**Photon 现有类比**: `Container` 直接包含所有功能，无接口抽象

**改动细节**:
- 在 `core/core.v` 新增 `BeanFactory` 接口：
  ```v
  pub interface BeanFactory {
      get_bean(type_name string) !voidptr
      contains_bean(type_name string) bool
  }
  pub interface ListableBeanFactory {
      bean_names() []string
      bean_count() int
      beans_for_interface(interface_name string) []string
      beans_for_tag(tag string) []string
  }
  pub interface HierarchicalBeanFactory {
      parent_factory() &BeanFactory
      set_parent(parent &BeanFactory)
  }
  ```
- `Container` 实现以上三个接口
- `ApplicationContext` 通过组合 `Container` 间接满足接口

**测试用例**:
- `core/bean_factory_interface_test.v`: 验证 Container 实现三个接口
- 验证 ApplicationContext 可通过 BeanFactory 接口访问 bean
- 验证 HierarchicalBeanFactory 的 parent 链查找

### Task 1.2: @Bean 方法注解支持

**Spring 类比**: `@Configuration` 类中的 `@Bean` 方法自动注册为 Bean

**Photon 现有类比**: `@[configuration]` 标注 struct，但无方法级 `@[bean]` 注解

**改动细节**:
- 在 `core/scanner.v` 新增 `extract_bean_methods[T]()` comptime 函数
- 扫描 `@[bean]` 注解的方法，提取返回类型作为 bean type_name
- 在 `register_component[T]()` 中自动注册 @[bean] 方法产生的 bean
- 支持方法参数的自动注入（从容器 resolve 参数类型）

**示例**:
```v
@[configuration]
pub struct AppConfig {
    @[autowired]
    env &Environment
}

@[bean]
pub fn (c &AppConfig) datasource() &DataSource {
    return new_datasource(c.env.get_property('db.url'))
}
```

**测试用例**:
- `core/bean_method_test.v`: 验证 @[bean] 方法被扫描注册
- 验证 @[bean] 方法参数自动注入
- 验证 @[bean] 方法返回的实例可被其他 bean @[autowired]

### Task 1.3: BeanDefinitionRegistryPostProcessor

**Spring 类比**: `BeanDefinitionRegistryPostProcessor` — 在 bean 定义注册后、实例化前修改注册表

**Photon 现有类比**: 有 `BeanFactoryPostProcessor`（修改已注册定义），但无法在此阶段新增定义

**改动细节**:
- 在 `core/post_processor.v` 新增接口：
  ```v
  pub interface BeanDefinitionRegistryPostProcessor {
      post_process_bean_definition_registry(mut ctx ApplicationContext)
  }
  ```
- 在 `ApplicationContext.refresh()` 步骤 1 之前调用所有 RegistryPostProcessor
- 应用场景：动态注册条件 Bean、第三方模块扩展

**测试用例**:
- `core/registry_post_processor_test.v`: 验证 PostProcessor 可动态注册新 BeanDefinition
- 验证注册的新 Bean 在后续 refresh 流程中被实例化

### Task 1.4: @Profile 注解驱动

**Spring 类比**: `@Profile("dev")` 在 Bean 上声明激活条件

**Photon 现有类比**: 有 `ConditionalOnProperty` 条件装配，但无直接的 Profile 注解

**改动细节**:
- 在 `core/scanner.v` 新增 `@[profile('dev')]` 注解解析
- 在 `register_component[T]()` 中检查 `@[profile]` 并转换为 `OnProfileCondition`
- 在 `core/condition.v` 新增 `OnProfileCondition` 条件评估器
- 与 `Environment.get_active_profiles()` 联动

**测试用例**:
- `core/profile_annotation_test.v`: 验证 @[profile] 标注的 Bean 在激活对应 Profile 时注册
- 验证未激活 Profile 时 Bean 被跳过
- 验证多 Profile 组合（`@[profile('dev', 'test')]`）

### Task 1.5: 简易表达式引擎 (Photon EL)

**Spring 类比**: SpEL (Spring Expression Language) 用于 `@Value("#{...}")`、`@Conditional` 等

**Hyperf 类比**: 无直接等价，使用 PHP 原生表达式

**Photon 现有类比**: `@[value('key')]` 仅支持简单属性键，不支持表达式

**改动细节**:
- 新建 `core/expression.v`，实现轻量级表达式解析器
- 支持：属性访问 `#{config.db.host}`、字面量 `#{'literal'}`、算术 `#{1 + 2}`
- 支持：比较 `#{env == 'prod'}`、逻辑 `#{a and b}`
- 不支持：方法调用、集合操作（保持低心智成本）
- 集成到 `@[value]` 注解和 `@[conditional_on_expression]`

**测试用例**:
- `core/expression_test.v`: 属性访问、算术、比较、逻辑组合
- 验证 `@[value('#{app.name}-suffix}')]` 表达式注入
- 验证 `@[conditional_on_expression('env == prod')]` 条件评估

---

## Phase 2: AOP 面向切面编程增强

### 对标分析

| Spring AOP | Hyperf AOP | Photon 现状 | 差距 |
|-----------|-----------|------------|------|
| @Aspect + @Pointcut + @Around/@Before/@After | #[Aspect] + #[PointCut] + AbstractAspect | Interceptor 接口 + InterceptorChain | 缺切点表达式、缺注解驱动 |
| 代理工厂 (JDK/CGLIB) | AOP 代理类生成（编译期） | 无代理生成 | V 编译期无法生成代理类 |
| @Pointcut 表达式 | #[PointCut] 注解 | 手动注册 Interceptor | 缺声明式切点 |

### Task 2.1: 声明式切面 (@Aspect + @Pointcut)

**Spring 类比**: `@Aspect` 标注切面类，`@Pointcut` 定义切点，`@Around`/`@Before`/`@After` 定义通知

**Photon 现有类比**: `Interceptor` 接口 + 手动 `InterceptorChain.add()`

**改动细节**:
- 新建 `core/aop.v`，定义：
  ```v
  pub interface Aspect {
      pointcut() string  // 切点表达式
  }
  pub interface MethodBeforeAdvice {
      before(method_name string, args []voidptr)
  }
  pub interface MethodAfterAdvice {
      after(method_name string, result voidptr, err IError)
  }
  pub interface MethodAroundAdvice {
      around(method_name string, args []voidptr, proceed fn () !voidptr) !voidptr
  }
  ```
- 切点表达式支持：
  - `execution(*.UserService.*)` — 匹配 UserService 的所有方法
  - `annotation(cacheable)` — 匹配带 @[cacheable] 注解的方法
  - `within(controller)` — 匹配 @[controller] 标注的类
- 在 `register_component[T]()` 中扫描 `@[aspect]` 注解
- 在 `ApplicationContext.refresh()` 中注册 Aspect 到 InterceptorChain

**V 语言适配**:
由于 V 无法在运行时生成代理类，AOP 通过 comptime 在 `autowire_bean[T]()` 时织入：
- 扫描 T 的方法是否有匹配的 Aspect
- 为匹配的方法生成包装闭包，在调用前后插入通知

**测试用例**:
- `core/aop_aspect_test.v`: 验证 @[aspect] 注册和切点匹配
- 验证 @Before/@After/@Around 通知执行顺序
- 验证 @[cacheable] 注解匹配的切面

### Task 2.2: @Pointcut 注解和切点组合

**改动细节**:
- 支持 `@[pointcut('execution(*.UserService.*))]` 定义命名切点
- 支持 `&&` / `||` / `!` 切点组合
- 支持通配符 `*` 匹配

**测试用例**:
- `core/aop_pointcut_test.v`: 切点表达式解析、组合、通配符

---

## Phase 3: ORM 查询构造器与仓库模式优化

### 对标分析

| Spring Data JPA | Hyperf Database | Photon 现状 | 差距 |
|----------------|-----------------|------------|------|
| Specification (Criteria API) | 无（使用 QueryBuilder 链式） | 无 | 缺动态查询组合 |
| Pageable / Sort | 无 | 有 SimplePaginator | 缺标准化 Pageable |
| Projection (DTO 投影) | 无 | 无 | 缺 DTO 投影 |
| @Modifying | 无 | 无 | 缺修改型查询标记 |
| @Query countQuery | 无 | 无 | 缺分页 count 优化 |
| Entity Listener | Model 事件 | 有 OrmAdapter hooks | 缺独立监听器 |
| 读分离 (Read Replica) | 无 | 有多连接管理 | 缺自动读写分离路由 |

### Task 3.1: Specification 动态查询模式

**Spring 类比**: `Specification<T>` 接口，`JpaSpecificationExecutor<T>` 扩展接口

**Photon 现有类比**: `BaseRepository[T]` 有 `find_all()` 但无动态条件组合

**改动细节**:
- 新建 `orm/specification.v`:
  ```v
  pub interface Specification[T] {
      to_predicate() QueryPredicate
  }
  pub struct QueryPredicate {
  pub mut:
      conditions []QueryCondition
      orders     []QueryOrder
      limit_     int
      offset_    int
  }
  pub struct QueryCondition {
  pub:
      field    string
      operator QueryOperator  // .eq, .ne, .gt, .lt, .like, .in, .is_null
      value    string
  }
  ```
- 在 `BaseRepository[T]` 新增 `find_all_with_spec(spec Specification[T]) ![]T`
- 提供 `Specifications.where()` / `.and()` / `.or()` 组合器
- comptime 生成器将 QueryPredicate 转换为 V ORM QueryBuilder 调用

**测试用例**:
- `orm/specification_test.v`: 单条件、多条件 AND/OR、排序、分页
- 验证 Specification 与现有 derive.v 的兼容性

### Task 3.2: 标准化 Pageable / Sort

**Spring 类比**: `Pageable` 接口 + `PageRequest` 工厂 + `Page<T>` 结果

**Photon 现有类比**: `support.new_simple_paginator` / `support.new_length_aware_paginator`

**改动细节**:
- 在 `orm/` 新建 `pageable.v`:
  ```v
  pub struct PageRequest {
  pub:
      page      int = 1
      page_size int = 20
      sort      Sort
  }
  pub struct Page[T] {
  pub:
      content      []T
      total        int
      page         int
      page_size    int
      total_pages  int
      has_next     bool
      has_previous bool
  }
  pub struct Sort {
  pub:
      orders []SortOrder
  }
  pub struct SortOrder {
  pub:
      property  string
      direction SortDirection  // .asc, .desc
  }
  ```
- `BaseRepository[T]` 新增 `find_all_paged(pageable PageRequest) !Page[T]`
- 自动生成 count 查询

**测试用例**:
- `orm/pageable_test.v`: 分页查询、排序、总数计算、边界条件

### Task 3.3: @Modifying 查询标记

**Spring 类比**: `@Modifying` 标注 UPDATE/DELETE 查询方法

**改动细节**:
- 在 `orm/query.v` 新增 `@[modifying]` 注解解析
- `execute_named_query` 检查 `@[modifying]` 标记，返回影响行数而非查询结果
- 在 comptime 扫描时区分查询型和修改型方法

**测试用例**:
- `orm/modifying_query_test.v`: UPDATE/DELETE 查询执行、返回影响行数

### Task 3.4: DTO 投影支持

**Spring 类比**: 查询结果直接映射到 DTO struct（非实体）

**Photon 现有类比**: 无

**改动细节**:
- 在 `BaseRepository[T]` 新增泛型方法 `find_projected[P](query string, params map[string]string) ![]P`
- comptime 生成器利用 V 的 `json.decode` 将查询结果映射到 DTO struct P
- 支持接口投影（只查询指定字段）

**测试用例**:
- `orm/projection_test.v`: DTO struct 映射、部分字段查询

### Task 3.5: 读写分离路由

**Spring 类比**: `@Transactional(readOnly=true)` + AbstractRoutingDataSource

**Photon 现有类比**: `OrmManager` 支持多连接注册，但无自动路由

**改动细节**:
- 在 `orm/orm.v` 新增 `RoutingPolicy` 接口:
  ```v
  pub interface RoutingPolicy {
      resolve(method_name string, is_readonly bool) string
  }
  ```
- 实现 `ReadWriteRoutingPolicy`: readonly → 'replica', write → 'default'
- 在 `BaseRepository[T]` 保存操作时根据 RoutingPolicy 选择连接
- 集成 `@[transactional(readonly: true)]` 注解

**测试用例**:
- `orm/read_write_split_test.v`: readonly 查询路由到 replica，写操作路由到 default

---

## Phase 4: Web MVC 与中间件链改造

### 对标分析

| Spring MVC | Hyperf HTTP | Photon 现状 | 差距 |
|-----------|------------|------------|------|
| @RequestBody JSON 反序列化 | #[AutoController] + 参数自动绑定 | 有 bind.v 但无方法参数绑定 | 缺方法参数 JSON 绑定 |
| ResponseEntity 构建器 | Hyperf\HttpMessage\Response | 有 web.success() 等 | 缺链式 Builder |
| @ExceptionHandler 方法级 | ExceptionHandler 中间件 | 有 @[controller_advice] | 缺方法级异常处理 |
| HandlerInterceptor | 中间件 | 有 MiddlewareChain | 缺 pre/post/afterCompletion 三阶段 |
| @PathVariable 类型转换 | 参数自动绑定 | 仅 string | 缺 int/bool 等类型 |
| WebMvcConfigurer | ConfigProvider | 无 | 缺统一配置接口 |
| @RestController 复合注解 | #[AutoController] | 无 | 缺复合注解 |
| DeferredResult 异步 | 协程天然异步 | 无 | 缺异步请求处理 |

### Task 4.1: 方法参数绑定与 @RequestBody

**Spring 类比**: `@RequestBody User user` 自动从 JSON 反序列化

**Photon 现有类比**: `web/bind.v` 有 DTO 绑定，但需要手动调用

**改动细节**:
- 在 `web/bind.v` 新增 `@[request_body]` 注解解析
- 在 comptime 路由扫描时检测方法参数的 `@[request_body]` 注解
- 自动调用 `json.decode[T](ctx.body)` 进行反序列化
- 新增 `@[path_param]` 注解，自动从路由参数提取并类型转换
- 新增 `@[query_param]` 注解，自动从 URL 查询参数提取

**示例**:
```v
@[post('/users')]
pub fn (mut c UserController) create(#[request_body] user User) veb.Result {
    // user 已自动从 JSON body 反序列化
    return c.created(user)
}
```

**测试用例**:
- `web/param_binding_test.v`: JSON body 反序列化、path param 类型转换、query param 提取
- 验证绑定失败时返回 400 Bad Request

### Task 4.2: ResponseEntity 链式构建器

**Spring 类比**: `ResponseEntity.ok().header("X-Custom", "val").body(data)`

**Photon 现有类比**: `web.success(data)` 返回 `veb.Result`

**改动细节**:
- 新建 `web/response_entity.v`:
  ```v
  pub struct ResponseEntity {
  pub mut:
      status  int = 200
      headers map[string]string
      body    string
  }
  pub fn ok(body string) ResponseEntity
  pub fn created(body string) ResponseEntity
  pub fn (mut r ResponseEntity) header(key string, val string) &ResponseEntity
  pub fn (mut r ResponseEntity) status_code(code int) &ResponseEntity
  pub fn (mut r ResponseEntity) build() veb.Result
  ```

**测试用例**:
- `web/response_entity_test.v`: 链式构建、header 设置、状态码

### Task 4.3: HandlerInterceptor 三阶段中间件

**Spring 类比**: `HandlerInterceptor.preHandle()` / `postHandle()` / `afterCompletion()`

**Photon 现有类比**: `MiddlewareFunc` 只有 `fn (ctx) !bool` 单阶段

**改动细节**:
- 新建 `web/interceptor.v`:
  ```v
  pub interface HandlerInterceptor {
      pre_handle(ctx &veb.Context) bool  // false = 中断请求
      post_handle(ctx &veb.Context, result voidptr)
      after_completion(ctx &veb.Context, err IError)
  }
  ```
- `InterceptorRegistry` 管理注册的拦截器
- 与现有 `MiddlewareChain` 并存：Middleware 用于全局，Interceptor 用于路由级

**测试用例**:
- `web/interceptor_test.v`: pre_handle 中断、post_handle 修改结果、after_completion 清理

### Task 4.4: @RestController 复合注解

**改动细节**:
- `@[rest_controller]` = `@[controller]` + 默认 JSON 响应
- comptime 扫描时检测 `@[rest_controller]`，自动设置 Content-Type: application/json
- 方法返回值自动 JSON 序列化（如果返回的是 struct 而非 veb.Result）

**测试用例**:
- `web/rest_controller_test.v`: 验证返回 struct 自动序列化为 JSON

### Task 4.5: WebMvcConfigurer 统一配置接口

**Spring 类比**: `WebMvcConfigurer` 接口允许自定义拦截器、格式化器、资源处理器等

**Photon 现有类比**: 各组件独立注册，无统一配置入口

**改动细节**:
- 新建 `web/configurer.v`:
  ```v
  pub interface WebMvcConfigurer {
      configure_interceptors(registry &InterceptorRegistry)
      configure_content_negotiation(manager &ContentNegotiationManager)
      configure_resource_handlers(registry &ResourceHandlerRegistry)
      configure_argument_resolvers(resolvers &[]ArgumentResolver)
  }
  ```
- `ApplicationContext` 在 refresh 时扫描 `@[web_configurer]` 标注的 Bean
- 依次调用各配置方法

**测试用例**:
- `web/configurer_test.v`: 自定义拦截器注册、资源处理器配置

---

## Phase 5: 缓存抽象层深度封装

### 对标分析

| Spring Cache | Hyperf Cache | Photon 现状 | 差距 |
|-------------|-------------|------------|------|
| @CacheConfig 类级共享配置 | #[Cache] | 无 | 缺类级缓存配置 |
| sync=true 同步加载 | 无 | 有 singleflight | 缺注解级 sync 控制 |
| CacheStatisticsActuator | 无 | 无 | 缺缓存统计 |
| @Cacheable condition SpEL | 无 | 有 condition 字符串 | 缺 SpEL 表达式 |
| 多缓存管理器 | 无 | 有 CacheRegistry | 已有 |
| CachingConfigurer 全局定制 | 无 | 无 | 缺全局配置接口 |

### Task 5.1: @CacheConfig 类级缓存配置

**改动细节**:
- 在 `cache/annotation.v` 新增 `parse_cache_config_attr()` 解析 `@[cache_config]`
- `CacheConfigAttribute` 持有: `cache_names []string`, `key_generator string`, `default_ttl int`
- comptime 扫描时将类级配置应用于该类所有 `@[cacheable]` 方法

**测试用例**:
- `cache/cache_config_test.v`: 类级配置继承、方法级覆盖

### Task 5.2: sync 同步加载注解

**改动细节**:
- `@[cacheable]` 新增 `sync: true` 属性
- 启用 sync 时，使用 `singleflight.do()` 确保同一 key 只有一个 loader 执行
- 当前 `get_or_load` 已有 singleflight，需在注解层暴露控制

**测试用例**:
- `cache/sync_cacheable_test.v`: 并发请求同一 key，验证只有一个 loader 执行

### Task 5.3: 缓存统计与 Actuator 集成

**改动细节**:
- `Cache` 接口新增 `stats() CacheStats`
- `CacheStats` 持有: `hits int`, `misses int`, `evictions int`, `size int`
- 在 `web/actuator_metrics.v` 新增 `/actuator/cache` 端点
- 返回所有命名缓存的统计信息

**测试用例**:
- `cache/cache_stats_test.v`: 命中/未命中计数、淘汰计数

### Task 5.4: CachingConfigurer 全局配置接口

**改动细节**:
- 新建 `cache/configurer.v`:
  ```v
  pub interface CachingConfigurer {
      cache_manager() &CacheManager
      key_generator() &KeyGenerator
      cache_resolver() &CacheResolver
  }
  ```
- `ApplicationContext` 扫描 `@[caching_configurer]` 标注的 Bean

**测试用例**:
- `cache/configurer_test.v`: 自定义 KeyGenerator、自定义 CacheManager

---

## Phase 6: 事件机制增强

### 对标分析

| Spring Events | Hyperf Event | Photon 现状 | 差距 |
|--------------|-------------|------------|------|
| ApplicationEvent<T> 类型化事件 | 无泛型事件 | Event 持有 voidptr payload | 缺类型安全 |
| @EventListener(condition) | 无 | 无 | 缺条件监听 |
| @EventListener(id) | 无 | 无 | 缺监听器 ID |
| 事件继承 | 无 | 无 | 缺父事件触发 |
| GenericApplicationListener | 无 | 无 | 缺泛型监听器 |
| 事件发布器独立 | EventEmitter | EventBus 内嵌 | 已有独立 EventBus |

### Task 6.1: 类型化事件 (TypedEvent[T])

**改动细节**:
- 新建 `core/typed_event.v`:
  ```v
  pub struct TypedEvent[T] {
  pub:
      name    string
      payload T
      timestamp i64
  }
  pub type TypedEventListener[T] = fn (event &TypedEvent[T])
  ```
- `EventBus` 新增 `on_typed[T](event_name string, listener TypedEventListener[T])` 方法
- `dispatch_typed[T](event &TypedEvent[T])` 方法
- 编译期类型安全，避免 voidptr 强转

**测试用例**:
- `core/typed_event_test.v`: 类型化事件发布/订阅、类型不匹配编译错误

### Task 6.2: @EventListener 条件表达式

**改动细节**:
- `@[event_listener]` 注解新增 `condition` 属性
- 使用 Phase 1 的表达式引擎评估条件
- 仅当条件为 true 时执行监听器

**测试用例**:
- `core/event_condition_test.v`: 条件匹配/不匹配场景

### Task 6.3: 事件继承传播

**改动细节**:
- 支持事件类型层级：发布子事件时，父事件的监听器也被触发
- 使用 bean type_index 机制建立事件类型继承关系
- 在 `dispatch()` 时递归查找父事件监听器

**测试用例**:
- `core/event_inheritance_test.v`: 父子事件传播、多级继承

---

## Phase 7: 配置管理与属性绑定增强

### 对标分析

| Spring Environment | Hyperf Config | Photon 现状 | 差距 |
|-------------------|--------------|------------|------|
| @ConfigurationProperties + Validation | config/autoload + env() | 有 bind_to_struct | 缺验证 |
| Placeholder ${key:default} | env(key, default) | 无 | 缺 placeholder |
| 环境变量覆盖 (SPRING_前缀) | .env 文件 | 无 | 缺约定式覆盖 |
| @RefreshScope 热刷新 | ConfigProvider reload | 无 | 缺热刷新 |
| ConfigTree 层级配置 | 无 | 无 | 缺树形结构 |
| PropertySource 优先级 | 无 | 有 ConfigSource | 缺优先级排序 |

### Task 7.1: Placeholder 解析器

**改动细节**:
- 在 `config/` 新建 `placeholder.v`:
  ```v
  pub fn resolve_placeholders(value string, properties map[string]string) string
  // ${key} → 查找 properties[key]
  // ${key:default} → 查找失败时使用 default
  // ${key:-default} → 同上（bash 风格）
  ```
- 在 `Environment.get_property()` 中自动解析 placeholder
- 在 `@[value('${db.url:localhost}')]` 注入时解析

**测试用例**:
- `config/placeholder_test.v`: 嵌套 placeholder、默认值、缺失 key

### Task 7.2: @ConfigurationProperties 验证

**改动细节**:
- 在 `bind_to_struct[T]()` 后自动执行验证
- 扫描 T 的字段注解 `@[not_blank]`, `@[min(1)]`, `@[max(100)]`, `@[email]`
- 验证失败返回详细错误信息（字段名 + 违反的约束）
- 集成 `web/validation.v` 已有的验证逻辑

**测试用例**:
- `config/validation_binding_test.v`: 必填字段验证、范围验证、邮箱格式验证

### Task 7.3: PropertySource 优先级

**改动细节**:
- `ConfigSource` 接口新增 `priority() int` 方法
- `Config.load()` 按优先级从低到高加载，高优先级覆盖低优先级
- 标准优先级：环境变量 > 命令行参数 > Profile 配置文件 > 默认配置文件

**测试用例**:
- `config/priority_test.v`: 多源优先级覆盖、同优先级后加载覆盖

### Task 7.4: 环境变量约定覆盖

**改动细节**:
- 支持 `PHOTON_` 前缀的环境变量自动映射到配置属性
- `PHOTON_DB_HOST` → `db.host`
- 双下划线 `__` 转换为层级分隔符 `.`
- 在 `Config.load()` 时自动扫描 `PHOTON_` 前缀的环境变量

**测试用例**:
- `config/env_override_test.v`: 环境变量映射、嵌套 key 覆盖

---

## Phase 8: 日志系统增强

### 对标分析

| Spring Boot Logging | Hyperf Logger | Photon 现状 | 差距 |
|--------------------|--------------|------------|------|
| logback 多 appender | 多 channel | 单一输出 | 缺多输出 |
| 异步日志 (AsyncAppender) | 无 | 无 | 缺异步 |
| 日志轮转 | 无 | 无 | 缺轮转 |
| 结构化字段 (kv) | 无 | 有 MDC | 缺字段 API |
| 运行时级别调整 | 无 | 无 | 缺动态级别 |
| trace_id 集成 | trace_id | 无 | 缺 trace 集成 |

### Task 8.1: 多 Appender 输出

**改动细节**:
- 新建 `logger/appender.v`，定义 `Appender` 接口:
  ```v
  pub interface Appender {
      write(entry &LogEntry, encoded string)
      flush()
  }
  ```
- 实现 `ConsoleAppender`（标准输出）
- 实现 `FileAppender`（文件写入）
- 实现 `CompositeAppender`（多路输出）
- `Logger` 持有 `[]Appender`，每次日志写入所有 appender

**测试用例**:
- `logger/appender_test.v`: 多路输出、文件写入、flush

### Task 8.2: 异步日志

**改动细节**:
- 实现 `AsyncAppender`，包装其他 Appender
- 使用 `async.TaskExecutor` 作为日志写入线程池
- 日志写入不阻塞业务线程
- 有界队列 + 丢弃策略（防 OOM）

**测试用例**:
- `logger/async_test.v`: 异步写入验证、队列满丢弃策略

### Task 8.3: 日志轮转

**改动细节**:
- `FileAppender` 新增 `RollingPolicy` 配置
- 按大小轮转：`max_size` bytes，超出时创建新文件
- 按时间轮转：每日一个文件
- 保留最近 N 个日志文件

**测试用例**:
- `logger/rolling_test.v`: 大小触发轮转、文件保留数量

### Task 8.4: 运行时级别调整

**改动细节**:
- `Logger` 新增 `set_level(level Level)` 方法（线程安全）
- 集成 `web/actuator_loggers.v` 已有的 `/actuator/loggers` 端点
- 支持 POST 请求动态修改日志级别

**测试用例**:
- `logger/dynamic_level_test.v`: 运行时修改级别、立即生效

### Task 8.5: 结构化字段 API

**改动细节**:
- `Logger` 新增 `with_field(key string, val string) &Logger` 方法
- 返回带预设字段的子 Logger（不修改原 Logger）
- `log()` 时将预设字段与 MDC 合并输出

**测试用例**:
- `logger/fields_test.v`: 链式字段添加、子 Logger 隔离

---

## Phase 9: 异常处理体系统一

### 对标分析

| Spring Exception | Hyperf Exception | Photon 现状 | 差距 |
|-----------------|-----------------|------------|------|
| @ResponseStatus | ExceptionHandler | 无 | 缺注解式状态码 |
| ResponseStatusException | HttpException | 有 HttpException | 缺链式构建 |
| @ExceptionHandler 方法级 | 异常处理中间件 | 有 @[controller_advice] | 缺方法级处理 |
| ProblemDetail (RFC 7807) | 无 | 无 | 缺标准错误格式 |
| 异常优先级 | 无 | 无 | 缺优先级排序 |

### Task 9.1: ProblemDetail (RFC 7807)

**改动细节**:
- 新建 `web/problem_detail.v`:
  ```v
  pub struct ProblemDetail {
  pub:
      type_    string = 'about:blank'
      title    string
      status   int
      detail   string
      instance string
  pub mut:
      extensions map[string]string
  }
  pub fn problem(status int, title string, detail string) ProblemDetail
  pub fn (mut p ProblemDetail) with_ext(key string, val string) &ProblemDetail
  pub fn (p ProblemDetail) to_json() string
  ```
- `ExceptionHandler` 默认输出 ProblemDetail JSON 格式
- Content-Type: `application/problem+json`

**测试用例**:
- `web/problem_detail_test.v`: JSON 序列化、扩展字段、Content-Type

### Task 9.2: @ResponseStatus 注解

**改动细节**:
- 新增 `@[status_code(404)]` 注解标注自定义异常
- comptime 扫描异常 struct 的 `@[status_code]` 注解
- `ExceptionResolver` 优先使用注解声明的状态码

**测试用例**:
- `web/status_code_annotation_test.v`: 注解状态码映射

### Task 9.3: 方法级 @ExceptionHandler

**改动细节**:
- 在 `@[controller_advice]` 类中支持 `@[exception_handler('NotFoundError')]` 方法注解
- comptime 扫描方法参数类型确定处理的异常类型
- `ExceptionResolver` 按异常类型精确匹配方法级处理器

**测试用例**:
- `web/method_exception_handler_test.v`: 方法级异常处理、优先级匹配

### Task 9.4: 异常处理链优先级

**改动细节**:
- `ExceptionResolver` 支持多个 Handler，按优先级排序
- 优先级：控制器方法级 > 控制器类级 > 全局 @[controller_advice] > 默认处理
- 最精确匹配优先（子异常 > 父异常）

**测试用例**:
- `web/exception_priority_test.v`: 多级异常处理优先级

---

## Phase 10: 协程与异步任务增强

### 对标分析

| Spring Async | Hyperf Coroutine | Photon 现状 | 差距 |
|-------------|-----------------|------------|------|
| @Async 返回 Future | 协程天然异步 | 有 TaskExecutor.submit() | 缺 Future 返回 |
| AsyncTaskExecutor 超时 | 协程超时控制 | 无 | 缺超时控制 |
| 上下文传播 (RequestContext) | 协程上下文 Context | 无 | 缺上下文传播 |
| @Scheduled + @Async | Crontab + 协程 | 有独立实现 | 缺组合 |
| 线程池监控 | 协程监控 | 无 | 缺监控 |

### Task 10.1: Future 返回型异步

**改动细节**:
- 新建 `async/future.v`:
  ```v
  pub struct Future[T] {
  pub mut:
      value ?T
      err   IError
      done  chan bool
  }
  pub fn (f &Future[T]) await() !T
  pub fn (f &Future[T]) await_timeout(timeout time.Duration) !T
  pub fn (f &Future[T]) is_ready() bool
  ```
- `TaskExecutor` 新增 `submit_with_result[T](fn () !T) !&Future[T]`
- Future 内部使用 goroutine + channel 实现

**测试用例**:
- `async/future_test.v`: await 阻塞等待、超时取消、is_ready 轮询

### Task 10.2: 上下文传播

**改动细节**:
- 新建 `async/context.v`:
  ```v
  pub struct AsyncContext {
  pub mut:
      data map[string]string
  mut:
      mu sync.RwMutex
  }
  pub fn current_context() &AsyncContext  // 线程/协程局部
  pub fn propagate(parent &AsyncContext) &AsyncContext  // 创建子上下文
  ```
- `TaskExecutor.submit()` 时自动复制当前线程的 AsyncContext
- 支持请求 ID、用户 ID、Trace ID 等上下文跨线程传播

**测试用例**:
- `async/context_propagation_test.v`: 上下文跨线程传播、子上下文修改不影响父

### Task 10.3: 线程池监控

**改动细节**:
- `TaskExecutor` 新增 `stats() ExecutorStats`
- `ExecutorStats`: `active_workers int`, `queued_tasks int`, `completed_tasks int`, `rejected_tasks int`
- 集成 `/actuator/executor` 端点

**测试用例**:
- `async/executor_stats_test.v`: 统计准确性、并发安全

---

## Phase 11: 服务发现与注册中心

### 对标分析

| Spring Cloud | Hyperf Service Governance | Photon 现状 | 差距 |
|-------------|------------------------|------------|------|
| ServiceRegistry | ServiceClient | 无 | 完全缺失 |
| @EnableDiscoveryClient | #[ServiceClient] | 无 | 完全缺失 |
| LoadBalancer | 负载均衡 | 无 | 完全缺失 |
| HealthIndicator | 健康检查 | 有 health 模块 | 缺服务健康检查 |
| @FeignClient | #[ServiceClient] | 无 | 完全缺失 |

### Task 11.1: ServiceRegistry 抽象

**改动细节**:
- 新建 `discovery/` 模块:
  ```v
  pub interface ServiceRegistry {
      register(instance ServiceInstance) !
      deregister(instance_id string) !
      get_instances(service_name string) ![]ServiceInstance
      health_check(instance ServiceInstance) bool
  }
  pub struct ServiceInstance {
  pub:
      id          string
      name        string
      host        string
      port        int
      metadata    map[string]string
      healthy     bool
  }
  ```
- 实现 `InMemoryServiceRegistry`（开发/测试用）
- 预留 `ConsulServiceRegistry` / `EtcdServiceRegistry` 接口

**测试用例**:
- `discovery/registry_test.v`: 注册/注销/查询实例、健康检查

### Task 11.2: 客户端负载均衡

**改动细节**:
- 新建 `discovery/loadbalancer.v`:
  ```v
  pub interface LoadBalancer {
      choose(instances []ServiceInstance) ?ServiceInstance
  }
  pub struct RoundRobinLoadBalancer {}
  pub struct RandomLoadBalancer {}
  pub struct WeightedLoadBalancer {}
  ```
- 集成 HTTP 客户端，自动选择实例并转发请求

**测试用例**:
- `discovery/loadbalancer_test.v`: 轮询/随机/加权策略

### Task 11.3: @ServiceClient 声明式客户端

**Hyperf 类比**: `#[ServiceClient]` 注解 + 接口定义自动生成代理

**改动细节**:
- `@[service_client('user-service')]` 标注接口
- comptime 生成代理 struct，方法调用自动通过 LoadBalancer 转发
- 方法参数自动序列化为 HTTP 请求
- 返回值自动反序列化

**测试用例**:
- `discovery/service_client_test.v`: 接口方法调用转发、负载均衡选择

---

## Phase 12: 请求客户端封装

### 对标分析

| Spring WebClient | Hyperf HttpClient | Photon 现有 http/ | 差距 |
|-----------------|------------------|-----------------|------|
| 链式构建器 | 协程客户端 | 有 client.v | 缺链式 API |
| 请求/响应拦截器 | 无 | 无 | 缺拦截器 |
| 连接池 | 连接池 | 无 | 缺连接池 |
| 超时/重试 | 超时 | 无 | 缺超时重试 |
| 类型化响应 | 无 | 无 | 缺类型反序列化 |

### Task 12.1: 链式 HTTP 客户端

**改动细节**:
- 重构 `http/client.v`，提供链式 API:
  ```v
  resp := http.client('https://api.example.com')
      .header('Authorization', 'Bearer token')
      .query('page', '1')
      .json_body({'name': 'Alice'})
      .timeout(30 * time.second)
      .retry(3, 1 * time.second)
      .post()!
  ```

**测试用例**:
- `http/client_chain_test.v`: 链式构建、header/query/body 设置

### Task 12.2: 请求/响应拦截器

**改动细节**:
- 定义 `ClientInterceptor` 接口:
  ```v
  pub interface ClientInterceptor {
      intercept_request(req &ClientRequest) !ClientRequest
      intercept_response(resp &ClientResponse) !ClientResponse
  }
  ```
- 用例：自动添加认证头、日志记录、请求/响应压缩

**测试用例**:
- `http/interceptor_test.v`: 请求拦截器修改 header、响应拦截器记录日志

### Task 12.3: 类型化响应反序列化

**改动细节**:
- 新增 `get_typed[T](url string) !T` 方法
- 自动调用 `json.decode[T](response.body)` 反序列化
- 支持错误响应自动转换为 HttpException

**测试用例**:
- `http/typed_response_test.v`: JSON 响应反序列化、错误处理

---

## 测试策略与验收标准

### 全局测试规范

每个 Task 完成后必须：

1. **单元测试**: 新增/修改的每个公开函数必须有测试用例
2. **集成测试**: 涉及多模块交互的 Task 必须有集成测试
3. **并发测试**: 涉及共享状态的 Task 必须有并发安全测试
4. **回归测试**: 所有修改不得破坏现有测试

### 测试执行命令

```bash
# 运行全部测试
v test . -stats

# 运行单个模块测试
v test core/
v test web/
v test orm/
v test cache/
v test config/
v test logger/
v test async/
v test http/

# 运行特定测试文件
v test core/expression_test.v
v test orm/specification_test.v
```

### 验收标准

| 阶段 | 验收项 | 标准 |
|------|--------|------|
| Phase 1 | IoC 容器 | BeanFactory 接口分层 + @Bean 方法 + @Profile + 表达式引擎 |
| Phase 2 | AOP | @Aspect 切面 + 切点表达式 + 通知织入 |
| Phase 3 | ORM | Specification + Pageable + @Modifying + 投影 + 读写分离 |
| Phase 4 | Web MVC | 参数绑定 + ResponseEntity + Interceptor + @RestController |
| Phase 5 | 缓存 | @CacheConfig + sync + 统计 + Configurer |
| Phase 6 | 事件 | 类型化事件 + 条件监听 + 事件继承 |
| Phase 7 | 配置 | Placeholder + 验证 + 优先级 + 环境变量覆盖 |
| Phase 8 | 日志 | 多 Appender + 异步 + 轮转 + 动态级别 + 字段 API |
| Phase 9 | 异常 | ProblemDetail + @ResponseStatus + 方法级处理 + 优先级 |
| Phase 10 | 异步 | Future + 上下文传播 + 监控 |
| Phase 11 | 服务发现 | Registry + LoadBalancer + @ServiceClient |
| Phase 12 | HTTP 客户端 | 链式 API + 拦截器 + 连接池 + 类型化响应 |

---

## 文档更新清单

每个 Phase 完成后需要更新的文档：

| 文档 | 更新内容 |
|------|---------|
| `README.md` | 新增注解列表、新增模块说明、示例代码 |
| `ARCHITECTURE.md` | 模块拓扑更新、数据流更新、设计决策记录 |
| `AGENTS.md` | 新增注解命名规范、编码规范补充 |
| `TUTORIAL.md` | 新特性实战教程 |
| `docs/pages/` | 每个新特性一篇详细文档 |

---

## 实施优先级

| 优先级 | Phase | 理由 |
|--------|-------|------|
| P0 | Phase 1 (IoC) + Phase 4 (Web MVC) | 核心基础设施，其他模块依赖 |
| P0 | Phase 3 (ORM) + Phase 9 (异常) | 数据层和错误处理是业务核心 |
| P1 | Phase 2 (AOP) + Phase 6 (事件) | 横切关注点，提升框架表达力 |
| P1 | Phase 5 (缓存) + Phase 7 (配置) | 中间件生态完善 |
| P2 | Phase 8 (日志) + Phase 10 (异步) | 运维和性能增强 |
| P2 | Phase 12 (HTTP 客户端) | 外部通信增强 |
| P3 | Phase 11 (服务发现) | 微服务能力，可延后 |

---

## 附录: Spring/Hyperf 设计理念借鉴要点

### 从 Spring 借鉴
1. **接口分层**: BeanFactory → ApplicationContext，每层职责清晰
2. **PostProcessor 扩展点**: 允许第三方无侵入扩展
3. **注解驱动**: @Configuration/@Bean/@Conditional 声明式编程
4. **生命周期完整性**: refresh → start → stop → close 完整状态机
5. **条件装配**: @ConditionalOn* 系列条件，实现自动配置
6. **SpEL 表达式**: 统一的表达式引擎贯穿配置、条件、缓存

### 从 Hyperf 借鉴
1. **协程优先**: 所有 I/O 操作协程化，同步写法异步执行
2. **AOP 编译期织入**: 无运行时代理开销
3. **注解 + DI 深度集成**: 注解直接驱动容器行为
4. **PSR 标准契约**: 接口标准化，组件可替换
5. **ConfigProvider 模式**: 模块化配置注入，类似 Spring Boot Starter
6. **连接池复用**: 数据库/Redis/HTTP 连接池化，减少握手开销

### Photon 特有优势（保持）
1. **编译期 DI**: V comptime $for 零运行时反射
2. **单二进制部署**: 无外部依赖
3. **内存安全**: V 的所有权系统保证
4. **高性能定时器**: 4-ary 堆 + 64 桶分片
5. **ShardedRwMutex**: 分片锁减少争用

---

> **本方案是 Photon 框架 0.2.0 版本的深度优化路线图，每个 Phase 可独立实施和测试。**
