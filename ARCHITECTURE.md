# Photon Framework — 技术架构文档

> 生成日期: 2025-04-08 | 版本: 0.1.0 | V 语言版本: weekly.2025.06 (V 0.5.x)
> 为 AI Agent 快速启动而编写，避免重复扫描源码

---

## 目录

1. [项目概览](#1-项目概览)
2. [模块拓扑](#2-模块拓扑)
3. [核心模块详解](#3-核心模块详解)
4. [模块间依赖关系](#4-模块间依赖关系)
5. [数据流与生命周期](#5-数据流与生命周期)
6. [注解系统](#6-注解系统)
7. [关键设计决策](#7-关键设计决策)
8. [测试策略](#8-测试策略)
9. [CI/CD 与部署](#9-cicd-与部署)
10. [模块成熟度矩阵](#10-模块成熟度矩阵)

---

## 1. 项目概览

### 1.1 定位

Photon 是**面向商业应用的 V 语言企业级框架**，对标 Spring Boot。核心设计哲学：
- **编译期优于运行期**：DI、路由匹配在编译期完成，零运行时反射开销
- **显式优于隐式**：注解驱动、声明式编程
- **约定优于配置**：框架提供合理默认值

### 1.2 入口

```v
// photon.v — 统一导出所有模块的公开类型
module photon
// 以 type alias 形式 re-export 全部模块核心类型
// 用户只需 import photon 即可使用全部功能
```

### 1.3 启动方式

支持两种启动模式：

**Web 模式**（`web.run[T](port)`）：
```v
import photon.web
web.run[MyApp](8080) // 单泛型封装，用户无需直接接触 veb
```

**CLI 模式**（`cli.new_application`）：
```v
mut app := cli.new_application('photon', '0.1.0')
app.add_command(cli.new_serve_command())
app.run() or { panic(err) }
```

### 1.4 v.mod

```v
Module {
    name: 'photon'
    description: 'Photon Framework - A commercial-grade Spring-like application framework for V language'
    version: '0.1.0'
    license: 'MIT'
    repo_url: 'https://github.com/photon-framework/photon'
    dependencies: [] // 零外部依赖
}
```

### 1.5 第三方依赖：vendor 在仓库内

框架唯一的第三方代码是 Redis 客户端 `xiusin.vredis`，它被 vendor 进
`vendor/modules/xiusin/vredis/` 由本仓库维护，`v.mod` 的 `dependencies` 因此是空的。

| 项 | 说明 |
| --- | --- |
| 位置 | `vendor/modules/xiusin/vredis/`（module 名保持 `vredis`） |
| 消费者 | `cache/redis_cache.v`（`import xiusin.vredis`） |
| 接入 | `sh scripts/sync-vendor.sh` 把它链接进 `~/.vmodules/xiusin/vredis` |
| 测试 | `vendor/modules/xiusin/vredis/vredis_test.v`（27 用例 / 135 断言，需真实 Redis） |

目录布局为什么是 `vendor/modules/<owner>/<mod>`：V 的模块搜索只认
`<project>/` 与 `<project>/modules/`，且只认一层目录名。`modules/` 让 V 把
`vendor/` 当成模块根，`xiusin/vredis` 让 `import xiusin.vredis` 的模块名原样命中。
单目录测试模式（`v test vendor/modules/.../`）只拿文件所在目录当搜索根、找不到
`x.json2`，所以统一走符号链接把两边搜索根对齐。

**为什么不继续 `v install` + 补丁脚本**：三处（本地 / CI / Docker）各自打补丁，
上游一次静默改动就能让补丁失配，而失配时报的错离真因很远。vendor 之后一份源码、
一处修改、一套测试。

详见 [vendor/README.md](vendor/README.md)。

---

## 2. 模块拓扑

### 2.1 完整模块列表（18 个模块，160+ 个 .v 文件）

```
photon/
├── photon.v              # 统一入口，re-export 所有模块类型
├── AGENTS.md             # 开发规范宪法
├── ARCHITECTURE.md       # 本文档
├── README.md             # 用户文档（924 行）
├── Makefile              # 构建/测试/部署自动化
├── v.mod                 # 模块描述文件
│
├── core/                 # [Beta] 核心容器（DI、生命周期、注解引擎）
│   ├── core.v            # Container (IoC) + BeanDefinition + Scope + Dependency
│   ├── core_entry.v      # 模块入口 + API 文档
│   ├── application_context.v # ApplicationContext（统一上下文：Container+EventBus+Lifecycle+Environment）
│   ├── environment.v     # Environment（Profile + Property + Placeholder 解析）
│   ├── scanner.v         # 编译期 Bean 扫描 + 属性解析
│   ├── lifecycle.v       # LifecycleManager + SmartLifecycle + ContextRefreshedEvent
│   ├── event.v           # EventBus（Spring ApplicationEvent 风格 + TransactionalEventListener）
│   ├── conversion.v      # ConversionService + Converter 接口 + GenericConversionService（Spring 对齐）
│   ├── condition.v       # 条件装配（@conditional_on_* 系列注解）
│   ├── post_processor.v  # BeanPostProcessor + BeanFactoryPostProcessor（AOP 基础）
│   ├── factory_bean.v    # FactoryBean（工厂 Bean + FactoryBeanRegistry）
│   ├── service_locator.v # ServiceLocator（Laravel app() 风格）+ BindingRegistry
│   ├── auto_configuration.v # AutoConfiguration（Spring Boot 自动配置）
│   └── *._test.v         # 测试文件（含 event_transactional_test）
│
├── config/               # [Beta] 配置管理
│   ├── config.v          # Config 主结构：多源合并、类型转换
│   ├── environment.v     # Environment：Spring Environment 风格
│   ├── property.v        # PropertyBinder：@[value] 绑定
│   ├── source.v          # FileConfigSource / MapConfigSource / EnvConfigSource
│   └── config_test.v
│
├── web/                  # [Beta] Web 层（veb 增强）
│   ├── web.v             # 模块入口
│   ├── server.v          # web.run[T] 单泛型包装器
│   ├── router.v          # RouteRegistry + 编译期注解路由扫描
│   ├── controller.v      # BaseController（Spring 风格响应助手）
│   ├── middleware.v       # MiddlewareChain + MiddlewareContext
│   ├── middleware_groups.v # 中间件组 + CORS + 参数化中间件
│   ├── filter.v          # FilterChain（请求/响应过滤器）
│   ├── pipeline.v        # 洋葱模型管道
│   ├── kernel.v          # HttpKernel（事件驱动 + HandlerResolver + handle_with）
│   ├── content_negotiation.v # ContentNegotiationManager（Spring 对齐：Accept/Parameter/Fixed 策略）
│   ├── resource_handler.v # ResourceHandlerRegistry（Spring 对齐：静态资源映射）
│   ├── result.v          # 统一 API 响应封装（Result/PageResult）
│   ├── bind.v            # DTO 绑定 @[required] @[form:'name']
│   ├── model_binding.v   # 路由模型绑定
│   ├── input.v           # Laravel 风格请求参数访问
│   ├── form.v            # FormBuilder 表单构建器
│   ├── ratelimit.v       # RateLimiter 限流
│   ├── events.v          # 内核事件常量定义
│   ├── testing.v         # TestResponse 链式断言
│   └── *._test.v         # 测试文件（含 bind_bench_test）
│
├── orm/                  # [Beta] ORM + 实体映射
│   ├── orm.v             # OrmManager（多连接管理）、DriverType、OrmConnection
│   ├── entity.v          # Entity/Identifiable/Touchable 接口 + BaseEntity + SoftDeletableEntity
│   ├── adapter.v         # OrmAdapter[T]（生命周期钩子包装器）
│   ├── query_builder.v   # QueryBuilder（链式查询构建 + ParamValue 类型安全 SQL）
│   ├── repository.v      # Repository[T] 接口 + BaseRepository + DerivedRepository
│   ├── derive.v          # Spring Data 风格方法名解析（findByNameAndAge → WHERE）
│   ├── transaction.v     # TransactionManager（7 种传播行为 + 真实 DB 连接回调）
│   ├── relation.v        # HasMany[T] / BelongsTo[T] / ManyToMany[T]
│   ├── eager.v           # EagerLoader（N+1 问题预防）
│   ├── migration.v       # MigrationManager（版本化迁移）
│   └── *._test.v         # 测试文件（含 transaction_bench_test）
│
├── security/             # [Beta] 安全模块
│   ├── security.v        # 模块入口
│   ├── principal.v       # UserDetails 接口 + SimpleUserDetails + InMemoryUserDetailsService
│   ├── jwt.v             # JwtManager + JwtConfig + JwtClaims（HMAC-SHA256，零依赖实现）
│   ├── auth.v            # AuthenticationManager + AuthenticationProvider + PasswordEncoder
│   ├── role.v            # RoleHierarchy + AccessDecisionManager + 默认角色/权限
│   ├── csrf.v            # CsrfManager + CookieCsrfTokenRepository + Double-Submit Cookie
│   ├── encryption.v      # Encrypter（XOR + hex 对称加密，@[deprecated] 迁移至 AesCipher）
│   ├── hashing.v         # BcryptHasher / Argon2Hasher（PBKDF2-SHA256 真实 KDF）
│   ├── password_encoder.v # PasswordEncoder 接口体系（Spring 对齐：BCrypt/Argon2/Fnv/Delegating）
│   ├── cipher.v          # AesCipher（AES-256-CBC + HMAC，推荐加密器）
│   ├── filter.v          # SecurityFilterChain（veb 集成过滤器）
│   ├── annotations.v     # Security 注解解析
│   ├── context.v         # SecurityContext + SecurityContextHolder
│   ├── *._test.v         # 每个文件对应测试（12 个测试文件）
│
├── cache/                # [Beta] 缓存模块
│   ├── cache.v           # Cache 接口 + CacheRegistry（原 CacheManager 重命名）
│   ├── cache_chain.v     # CacheOperation（链式缓存操作 builder：remember/put/chain）
│   ├── manager.v         # CacheManager/NamedCache 接口 + ValueWrapper + RedisCache 抽象（Spring 对齐）
│   ├── memory.v          # MemoryCache（RwMutex 并发安全 + LRU 淘汰 + TTL）
│   ├── annotation.v      # CacheableInterceptor + CacheConfigAttribute + KeyGenerator（Spring 对齐）
│   ├── cache_tags.v      # TaggedCache + CacheLock + remember/remember_forever/sear
│   ├── singleflight.v    # Singleflight（Go singleflight 风格削峰）
│   ├── *._test.v         # 测试文件（含 benchmark）
│
├── queue/                # [Beta] 队列模块
│   ├── queue.v           # JobPayload + Job 接口
│   ├── driver.v          # QueueDriver 接口 + serialize/deserialize
│   ├── memory_driver.v   # MemoryDriver（内存驱动）
│   ├── redis_driver_client.v # VRedisQueueClient（vendored vredis 的 QueueRedisClient 实现）
│   ├── redis_driver.v    # RedisDriver（Redis 队列驱动：LPUSH/RPOP）
│   ├── dispatcher.v      # QueueDispatcher（全局单例 + dispatch/batch/chain/later）
│   ├── worker.v          # QueueWorker（轮询执行器）
│   ├── failed_jobs.v     # FailedJob + FailedJobRepository + MemoryFailedJobRepository + FailedJobHandler
│   └── queue_test.v
│
├── locking/              # [Beta] 锁模块
│   ├── lock.v            # LockManager + LocalMutex + DistributedLock 接口 + LockGuard（RAII）
│   ├── redis_lock.v      # RedisDistributedLock（Redis 分布式锁 + Lua 脚本原子操作）
│   ├── redis_lock_client.v # VRedisLockClient（vendored vredis 的 RedisClient 实现）
│   └── lock_test.v
│
├── pool/                 # [Beta] 连接池
│   ├── pool.v            # Pool（泛型对象池）+ PoolStats + PooledObject 接口
│   ├── db_pool.v         # DbPool（数据库连接池专用包装）
│   └── pool_test.v
│
├── storage/              # [Beta] 文件存储
│   ├── storage.v         # Storage 接口 + StorageManager + FileMetadata + Visibility
│   ├── local_adapter.v   # LocalAdapter（本地文件系统）
│   ├── mime.v            # MIME 类型检测
│   └── storage_test.v
│
├── ticker/               # [Beta] 高性能定时器
│   ├── ticker.v          # 入口
│   ├── heap.v            # TimerHeap（4-ary min-heap + TimerEntry + TimerCallback）
│   ├── bucket.v          # TimerScheduler（64 桶分片 + 后台调度循环）
│   ├── optimizer.v       # BucketHeadHeap（O(log 64) 桶头优化）
│   ├── timer.v           # Timer/Ticker（Go 兼容 API）+ after/after_func/sleep/tick
│   └── ticker_test.v
│
├── strutil/              # [Beta] 支持工具（字符串 / 数组 / 集合 / 错误）
│   ├── strutil.v         # 入口（模块名为什么不是 support，见 8.10）
│   ├── error.v           # PhotonError + ErrorCode 枚举（统一领域错误类型，实现 IError）
│   ├── hash.v            # fnv1a_str（零分配）
│   ├── arr.v             # 数组工具（dot-notation get/set/has + reverse/take/skip）
│   ├── str.v             # 字符串工具（slug/snake/camel/studly/kebab + 截断/填充）
│   ├── collection.v      # Collection[T]（Laravel 风格链式集合操作：map/filter/reduce/sort/groupBy）
│   ├── module_identity_test.v  # 防回归：顶层模块名不得被 photon.<dir> 撞上
│   └── *._test.v         # 测试文件
│
├── pageable/             # [Beta] 分页与排序（Spring Data 风格）
│   ├── sort.v            # Sort + SortOrder + PageRequest
│   ├── page.v            # Page[T] + Slice[T]
│   └── pagination.v      # LengthAwarePaginator[T] + SimplePaginator[T]（已弃用，迁移到 Page[T]）
│
├── http/                 # [Alpha] HTTP 客户端（Spring RestTemplate 对齐）
│   ├── http.v            # 入口
│   ├── client.v          # RestTemplate（fluent API + SSLConfig/ProxyConfig + NoopInterceptor）
│   └── *._test.v         # 测试文件（含 ssl_proxy_test）
│
├── tracing/              # [Alpha] 链路追踪
│   ├── tracing.v         # 入口
│   ├── exporter.v        # SpanExporter 接口 + ConsoleExporter
│   ├── span.v            # Span 数据结构（TraceID/SpanID/Attributes）
│   └── *._test.v         # 测试文件
│
├── cli/                  # [Beta] CLI 框架
│   ├── cli.v             # 入口
│   ├── application.v     # CliApplication（命令注册/分发/帮助显示）
│   ├── command.v         # Command 接口 + BaseCommand
│   ├── input.v           # CommandInput（参数/选项/标志解析）
│   ├── output.v          # CommandOutput（ANSI 彩色输出 + 表格 + 进度）
│   ├── format.v          # ANSI 格式化（color_text/bold/dim/green/red/table）
│   ├── interactive.v     # ask/confirm/secret/choice 交互式输入
│   ├── progress.v        # ProgressBar
│   ├── builtin.v         # ListCommand + HelpCommand + ServeCommand
│   ├── make_commands.v   # MakeCommandCommand + MakeControllerCommand + MakeMiddlewareCommand
│   ├── schedule_command.v # ScheduleCommand
│   ├── queue_commands.v  # QueueWorkCommand
│   └── cli_test.v
│
├── example/              # [Demo] 示例应用
│   ├── main.v            # 373 行全功能演示（Web + ORM + 安全 + 事务 + 队列 + 缓存）
│   └── main              # 编译产物
│
├── .github/workflows/ci.yml  # CI 配置
├── Dockerfile            # 多阶段构建
├── systemd/photon.service    # systemd 服务单元
└── ci-test.sh            # 本地 CI 模拟脚本
```

### 2.2 模块分层（按成熟度）

| 层级 | 模块 | 描述 |
|------|------|------|
| **核心层** | config, strutil, pageable | 所有模块依赖的基础工具 |
| **基础设施层** | cache, pool, locking, ticker | 通用中间件原语 |
| **业务抽象层** | orm, security, queue, storage, http | 业务能力抽象 |
| **展现层** | web, cli | 对外交互接口 |
| **应用层** | example, core (待实现) | 整合示例 + DI 容器 |

---

## 3. 核心模块详解

### 3.1 Config 模块（config/）

**设计**：Spring Environment 风格的多源配置管理。

**核心类型**：
```
ConfigSource (interface)
  ├── FileConfigSource    # JSON / key=value 文件
  ├── EnvConfigSource     # 环境变量
  └── MapConfigSource     # 内存 map

Environment (interface)
  └── get_property() / contains_property() / resolve_placeholders()

PropertyBinder → @[value('key')] 字段绑定
```

**配置加载流程**：
```
Config.add_source(source) → Config.load() → 遍历 sources → 合并 map → properties
```

**Profile 支持**：
```v
config.set_profile(['prod', 'us-east'])
config.is_production()  // 检查 'prod' 或 'production' profile
```

### 3.2 Web 模块（web/）

**三个核心子系统**：

#### A. 路由系统（router.v）
```
RouteInfo         — 单条路由（method/path/handler/middlewares）
RouteRegistry     — 路由注册中心
RouterConfig      — 扫描配置

scan_routes[T]()  — 编译期 $for 扫描 @[get/post/put/delete/patch] 注解
```

**注解路由风格**：
```v
@[get('/users/:id')]
pub fn (mut app MyApp) show(id int) veb.Result { ... }

@[post('/users')]
@[middleware('auth')] // 路由级中间件
pub fn (mut app MyApp) create() veb.Result { ... }
```

#### B. HTTP 请求生命周期

```
web.run[T](port)
  ↓
veb 启动
  ↓
HttpKernel.handle()
  ├── kernel.request 事件
  ├── SecurityFilterChain.filter()  ← security 模块
  ├── FilterChain.apply_request_filters()  ← web/filter.v
  ├── MiddlewareChain.run()  ← web/middleware.v
  │   └── Pipeline(onion)  ← web/pipeline.v
  ├── Handler 执行
  ├── FilterChain.apply_response_filters()
  ├── kernel.response 事件
  └── kernel.terminate 事件
```

#### C. 中间件系统

三种中间件模式：

| 模式 | 文件 | 风格 | 特点 |
|------|------|------|------|
| **MiddlewareChain** | middleware.v | 线性链 | MiddlewareContext + 共享 data map |
| **Pipeline** | pipeline.v | 洋葱模型 | 请求→MW1→MW2→Handler→MW2→MW1→响应 |
| **FilterChain** | filter.v | 双向过滤器 | RequestFilter / ResponseFilter 独立注册 |

**内置中间件**：
```v
request_id_middleware       // 注入 request_id
request_id_cleanup_middleware // 清理 request_id
compression_middleware      // gzip 压缩
timing_middleware           // X-Response-Time 头部
cors_middleware(origins, methods, headers) // CORS
```

#### D. 响应封装（result.v）
```
Result         — { success, code, message, data, timestamp, path }
PageResult     — Result + pagination
success() / fail() / ok() / not_found() / unauthorized() / forbidden() / ...
```

#### E. DTO 绑定（bind.v）
```v
struct LoginDto {
    username string @[required]
    password string @[required]
    remember bool
}

dto := web.bind[LoginDto](ctx)!       // 查询/表单绑定
dto_json := web.bind_json[Dto](ctx)!  // JSON body 绑定
```

#### F. 测试工具（testing.v）
```
TestResponse — 链式断言 API
  .assert_status(200)
  .assert_successful()
  .assert_ok()
  .assert_json_path('$.data.users[0].id', value)
  .assert_json_count('$.data.users', 10)
  .assert_header('Content-Type', 'application/json')
  .assert_body_contains('hello')
```

### 3.3 ORM 模块（orm/）

**架构**：

```
OrmManager — 多连接管理器（by name）
  ├── register_connection(name, driver, db)
  ├── connection(name) → OrmConnection
  ├── driver(name) → DriverType (.sqlite / .mysql / .pg)
  └── is_sqlite() / is_mysql() / is_pg()

DriverType: sqlite | mysql | pg (+ 版本检测函数)
```

**实体系统**：

```
Entity (interface) → Identifiable → id() + is_new()
                    └── table_name()

BaseEntity — 默认实现
  ├── id int + created_at + updated_at (Touchable.touch())
  └── SoftDeletableEntity — extends BaseEntity
       └── deleted_at + is_deleted() + soft_delete() + restore()

生命周期钩子接口：
  BeforeCreateHook / AfterCreateHook
  BeforeUpdateHook / AfterUpdateHook
  BeforeDeleteHook / AfterDeleteHook
  AfterFindHook
```

**OrmAdapter[T]**（关键设计：**不导入 V 标准 orm**——因 V 0.5.1 同名模块冲突）：
```
adapter = OrmAdapter[T](manager, db_name)
  ├── get_conn() → voidptr
  ├── wrap_insert(entity, callback)  → before → callback → after
  ├── wrap_update(entity, callback)  → before → callback → after
  ├── wrap_save(entity, callback)    → is_new ? insert : update
  └── wrap_delete(entity, callback)  → before → callback → after
```

**Repository 模式**：
```
Repository[T] (interface)
  ├── find_by_id(id) → T
  ├── find_all() → []T
  ├── save(entity) → T
  ├── delete(id)
  ├── count() → int
  └── exists(id) → bool

BaseRepository[T] — 标准实现 + 自定义 ORM 函数注入

DerivedRepository[T] — 方法名派生查询
  ├── find_by(method, params...) — 解析 "findByNameAndAge"
  ├── count_by(method, params...)
  ├── exists_by(method, params...)
  └── delete_by(method, params...)
```

**方法名解析**（derive.v）：
```
"findByNameAndAge" → 
  QueryParts{operation: .find, 
             conditions: [{property: "name", operator: "="}, 
                          {property: "age", operator: "=", logic: "AND"}]}

"findTop10ByOrderByCreatedAtDesc" →
  QueryParts{operation: .find, limit_val: 10,
             order_by: [{property: "created_at", direction: "DESC"}]}

"countByStatus" → QueryParts{operation: .count, conditions: [{property: "status"}]}
```

**事务管理**（transaction.v）：
```
Propagation:
  required | requires_new | nested | supports | not_supported | mandatory | never

Isolation:
  default | read_uncommitted | read_committed | repeatable_read | serializable

TransactionManager
  ├── execute(propagation, fn)
  └── transactional(fn)  — 便捷包装
  
// 使用
tm.execute(.required, fn () ! {
    // 事务内代码
    tm.execute(.nested, fn () ! { /* 嵌套事务 */ })!
})!
```

**关系映射**（relation.v）：
```
HasMany[T]     — 一对多
BelongsTo[T]   — 多对一
ManyToMany[T]  — 多对多（pivot_table）
```

**Eager Loading**（eager.v）：
```
EagerLoader[T]
  └── with(['comments', 'author']) 预防 N+1 问题
```

**迁移系统**（migration.v）：
```
Migration 接口 → version() + name() + up() + down()
MigrationManager → add() + migrate() + rollback() + status() + reset()
```
> 注意：目前为 stub 状态，需要真实数据库驱动。

**QueryBuilder（query_builder.v）**：

链式查询构建器，支持 ParamValue 类型安全 SQL 参数：

```
QueryBuilder — 链式查询构建
  ├── new_query_builder(mgr, db_name, table) → &QueryBuilder
  ├── select_(columns) / where_(cond, param) / or_where(cond, param)
  ├── order_by(col, dir) / group_by(cols) / having(cond, param)
  ├── limit(n) / offset(n)
  ├── join(table, on_cond) / left_join / right_join
  ├── get() → []map / first() → map / count() → int
  └── to_sql() → (string, []ParamValue) — 调试用 SQL 输出

ParamValue — 类型安全参数包装
  ├── string_param(s) / int_param(n) / f64_param(f) / bool_param(b)
  └── nil_param() — NULL 值

使用示例：
users := orm.new_query_builder(mgr, 'default', 'users')
    .select_(['id', 'name', 'email'])
    .where_('age > ?', 18)
    .order_by('name', .asc)
    .limit(10)
    .get()!
```

### 3.4 Security 模块（security/）

**完整安全栈**（Spring Security 风格）：

```
SecurityFilterChain (veb filter 集成)
  ├── 1. 检查 public 端点
  ├── 2. deny_all 阻止
  ├── 3. CSRF 验证
  ├── 4. JWT 提取 + 验证
  ├── 5. AuthenticationManager.authenticate()
  ├── 6. SecurityContextHolder 设置
  ├── 7. 角色/权限校验 (AccessDecisionManager)
  └── 8. 继续或拒绝

用户模型：
  UserDetails (interface)
    ├── username() / password() / authorities()
    ├── is_enabled() / is_account_non_expired() / is_account_non_locked()
    └── SimpleUserDetails (默认实现)
  
  UserDetailsService (interface)
    ├── load_user_by_username()
    └── InMemoryUserDetailsService (默认实现)

认证：
  AuthenticationManager
    └── authenticate(auth) → Authentication
    
  AuthenticationProvider (interface)
    └── UsernamePasswordAuthenticationProvider
         ├── 密码校验 (PasswordEncoder)
         ├── 账户状态检查
         └── 返回已认证结果

JWT:
  JwtManager
    ├── create_token(username, roles, ttl_secs)
    ├── create_refresh_token(username)
    ├── parse_token(token) → JwtClaims
    ├── validate_token(token) → username
    ├── has_role(token, role)
    └── has_any_role(token, roles)
    
  JwtConfig: { secret, issuer, access_token_ttl, refresh_token_ttl }
  JwtClaims: { sub, roles, iss, exp, nbf, iat, jti }
  
  签名算法：HMAC-SHA256（纯 V 实现，零外部依赖）
  SHA-256 实现：自行实现（FIPS 180-4 标准）

RBAC:
  RoleHierarchy
    ├── ADMIN → MODERATOR → USER → GUEST (默认层级)
    └── get_reachable_roles(role)
  
  AccessDecisionManager
    ├── has_role(user_roles, required_role)
    ├── has_permission(user_roles, permission)
    └── has_all_permissions(user_roles, permissions)
    
  默认权限矩阵:
    ADMIN:    ['*', 'user:read', 'user:write', 'user:delete', 'admin:settings', 'admin:users']
    MODERATOR: ['user:read', 'user:write']
    USER:      ['user:read', 'self:write']
    GUEST:     ['public:read']

CSRF:
  CsrfManager
    ├── Double-Submit Cookie 模式
    ├── CookieCsrfTokenRepository
    ├── 忽略方法: GET/HEAD/OPTIONS/TRACE
    └── 可配置: cookie_name, header_name, form_field_name, secure, same_site

安全注解:
  @[secured]         — 需要认证
  @[roles_allowed('ADMIN','MODERATOR')] — 需要角色
  @[permit_all]      — 公开
  @[deny_all]        — 全部拒绝
  @[pre_authorize]   — 预留

加密/哈希:
  Encrypter — XOR + hex 对称加密（AES stub）
  BcryptHasher — FNV-1a 哈希（bcrypt 格式 stub）
  Argon2Hasher — 同上（Argon2 stub）
```

### 3.5 Cache 模块（cache/）

**架构**：
```
Cache (interface) — 核心缓存操作
  ├── get/set/delete/has/clear/keys/size
  
CacheManager — 统一缓存管理
  ├── register(name, cache) — 注册命名缓存
  ├── get_cache(name) — 获取命名缓存
  ├── default_cache — MemoryCache 默认
  ├── singleflight — 削峰组件
  └── 便捷方法: get/set/delete/has/clear + get_or_load

MemoryCache — 内存实现
  ├── sync.RwMutex 并发安全
  ├── TTL 过期 + LRU 淘汰
  ├── 统计信息（hits/expired/total）
  └── reclaim() 清理过期条目

TaggedCache — 缓存标签
  ├── 批量无效化：flush() 清除所有带标签的 key
  └── 自动 key 前缀拼接

Singleflight — 削峰（缓存击穿防护）
  └── do(key, fn) — 同 key 并发请求合并为一次执行

CacheLock — 基于缓存的分布式锁
  ├── acquire(key, ttl_ms)
  └── release(key)

回调辅助函数：
  remember(mut cm, key, ttl_secs, callback)  — 取/设
  remember_forever(mut cm, key, callback)     — 永久缓存
  sear(mut cm, key, callback)                 — 取/永久存
  put_many / get_many / delete_many / flush_all

CacheOperation（cache_chain.v）— 链式 Builder：

```
CacheOperation — 链式缓存操作构建器
  ├── chain() → &CacheOperation — 开始链式操作
  ├── put(key, val, ttl) / remember(key, ttl, loader)
  ├── forget(key) / has(key)
  └── get() !string — 终端方法，执行链并返回最终结果

使用示例：
result := cm.chain()
    .put('key1', 'val1', 3600)
    .remember('key2', 600, loader)
    .get()!
```
```

### 3.6 Queue 模块（queue/）

**设计**：Laravel Queue 风格。

```
Job (interface) — 任务契约
  ├── job_type() → string
  ├── handle() → !
  ├── tries() → int
  └── backoff() → []i64

QueueDriver (interface) — 后端
  ├── push / pop / count / clear
  ├── MemoryDriver (默认内存实现)
  └── RedisDriver (Redis 队列驱动：LPUSH/RPOP + 连接池)

RedisDriver — Redis 队列驱动
  ├── push(queue, payload) — LPUSH 入队
  ├── pop(queue) — RPOP 出队（阻塞可选 BRPOP）
  ├── count(queue) — LLEN 队列长度
  └── clear(queue) — DEL 清空队列

QueueDispatcher — 调度器（全局单例）
  ├── dispatch(job) — 立即分发
  ├── dispatch_later(job, delay_secs) — 延迟分发
  ├── dispatch_batch(jobs) — 批量
  ├── dispatch_chain(jobs) — 链式
  └── dispatch_now(job) — 同步执行

QueueWorker — 工作进程
  ├── 轮询间隔可配置（默认 5s）
  └── 支持重试 + backoff

Failed Jobs:
  FailedJobRepository (interface)
    ├── save / all / find_by_id / delete_by_id / clear / count
    └── MemoryFailedJobRepository (默认实现)
  
  FailedJobHandler
    └── retry(id) / retry_all() / forget(id) / flush()
```

### 3.7 Pool 模块（pool/）

```
PooledObject (interface) — 池化对象契约
  ├── close() → !
  └── is_valid() → bool

Pool — 泛型对象池
  ├── min_size / max_size / idle_timeout
  ├── sync.Mutex 线程安全
  ├── acquire() → voidptr
  ├── release(obj)
  ├── close()
  └── stats() → PoolStats

DbPool — 数据库连接池专用包装
  ├── 包装 generic Pool
  ├── driver 类型感知
  └── 复用 Pool 的 acquire/release/close/stats
```

### 3.8 Locking 模块（locking/）

```
DistributedLock (interface) — 分布式锁
  ├── acquire(key, ttl_ms) → bool
  ├── release(key) → bool
  ├── renew(key, ttl_ms) → bool
  └── is_locked(key) → bool

LocalMutex — 本地互斥锁（sync.Mutex 包装）
  ├── lock() / unlock() / try_lock()

LockManager — 统一锁管理器
  ├── 本地锁：lock/unlock/try_lock/lock_with_timeout
  ├── 分布式锁：dist_lock/dist_unlock
  ├── 自动懒创建 mutex（按 key）
  └── sync.RwMutex 保护 map

LockGuard — RAII 守卫
  ├── new_lock_guard(mut manager, key) — 构造时 lock
  └── unlock() — 析构时 unlock

guarded_lock[T](mut manager, key, fn) — defer 确保释放

RedisDistributedLock（redis_lock.v）— Redis 分布式锁：

```
RedisDistributedLock — 实现 DistributedLock 接口
  ├── acquire(key, ttl_ms) → bool
  │     ├── SET key <random-token> NX PX ttl_ms
  │     └── 成功后把 token 记进本实例的 owned 表
  ├── release(key) → bool
  │     ├── 从 owned 表取出 token（没有 → 直接 false，绝不去删别人的键）
  │     └── Lua 脚本：GET 比对 token → DEL
  ├── renew(key, ttl_ms) → bool
  │     ├── 读 owned 表里的 token（没有 → false）
  │     └── Lua 脚本：GET 比对 token → PEXPIRE
  └── is_locked(key) → bool
       └── GET key != ''

token 归属是整套机制的前提：老实现 release/renew 先 GET 出 token、
再拿这个 token 去比对 —— 比的是同一个值，永远相等，任何客户端都能
释放/续期别人的锁。现在只有真正 acquire 成功的那一方持有 token。

使用方式（客户端开箱可用，无需自己写适配器）：
  client := locking.new_vredis_lock_client(locking.VRedisLockOpt{ db: 0 })!
  defer { client.close() }
  redis_lock := locking.new_redis_lock(client)
  lm.with_distributed_lock(redis_lock)
  lm.dist_lock('resource', 30_000)!
  defer { lm.dist_unlock('resource')! }
```

> `VRedisLockClient` 是 `RedisClient` 接口的 vendored `xiusin.vredis` 实现（连接池
> + NX/PX 语义），位于 `redis_lock_client.v`。保留接口是为了让用户换别的 Redis 客户端。

### 3.9 Storage 模块（storage/）

```
Storage (interface) — 统一文件系统抽象
  ├── read / write / delete / exists
  ├── copy / move
  ├── size / mime_type / last_modified / metadata
  ├── set_visibility / visibility
  ├── list_contents / create_directory / delete_directory
  ├── url / temporary_url
  └── read_stream / write_stream / put / put_file

StorageManager — 多磁盘管理
  ├── register(name, adapter)
  ├── disk(name) / get(name) / must_get(name)
  └── has_disk / disk_names

适配器:
  LocalAdapter — 本地文件系统
    ├── root 目录限定
    ├── chmod 权限控制（public=0o644, private=0o600）
    ├── MIME 类型检测
    └── 完整目录操作

> 云存储适配器（S3 / GCS / Azure Blob）**不在仓库内**：这些实现要么是 stub，
> 要么需要 AWS Signature V4 与 XML 解析，仓库里没有可信的测试路径，留着只会
> 让调用方以为能用。`Storage` 接口本身就是扩展点，用户在自己的项目里实现
> 后 `manager.register('s3', my_adapter)` 即可。

FileMetadata — 文件元数据
  ├── path / size / mime_type / etag
  ├── last_modified / visibility
  └── extra (adapter-specific)

Visibility: public_ | private_
```

### 3.10 Ticker 模块（ticker/）

**Go 运行时定时器风格的高性能实现**。

```
数据结构：
  TimerHeap — 4-ary min-heap
    ├── 优于 binary heap: log_4(N) vs log_2(N) 比较次数更少
    ├── 缓存局部性更好
    ├── ~5% 性能优势（50K+ 条目，libev 基准）
    └── sync.Mutex 保护
    
  TimerScheduler — 64 桶分片调度
    ├── 减少锁竞争（64 个独立桶）
    ├── 后台 goroutine 轮询
    └── 懒检测：用户阻塞 channel 时才检查
    
  BucketHeadHeap — C10k 优化
    ├── 桶头最小堆，O(log 64) 轮询
    └── 避免 64 个锁全部获取

Timer / Ticker — Go 兼容 API:
  new_timer(d)        — 一次性定时器
  new_ticker(d)       — 周期定时器
  timer.reset(d)      — 重置
  timer.stop()        — 停止
  ticker.reset(d)     — 重置
  ticker.stop()       — 停止
  
  便捷函数:
    after(d)           → chan Time — d 后触发
    after_func(d, fn)  → &Timer  — d 后执行回调
    sleep(d)           — 阻塞等待
    tick(d)            → chan Time — 周期通道
```

### 3.11 支持模块（strutil/ + pageable/）

**Collection[T]** — Laravel 风格链式集合（315 行）：
```
collect(items) → Collection[T]
  .all() / .count() / .is_empty() / .is_not_empty()
  .map(fn) / .filter(fn) / .reject(fn) / .each(fn) / .reduce(initial, fn)
  .transform(fn) — 原地修改
  .first() / .last() / .nth(n)
  .sort(fn) / .sort_by(fn) / .sort_desc(fn)
  .unique() / .unique_by(fn)
  .chunk(size) → [][]T
  .group_by(fn) → map
  .concat() / .push() / .pop()
  .pluck(field) — 提取字段
  .avg() / .sum() / .min() / .max()
  .contains(val) / .contains_by(fn)
  .diff(other) / .intersect(other)
  .tap(fn) / .pipe(fn)
  .to_vec() / .to_json() / .join(sep)
```

**Str** — 字符串工具（309 行）：
```
slug(s)     — URL 友好的 slug
snake(s)    — CamelCase → snake_case
camel(s)    — snake_case → camelCase
studly(s)   — PascalCase
kebab(s)    — kebab-case
title(s)    — 标题大小写
limit(s, n) — 截断
words(s, n) — 按单词截断
contains_all(s, needles) / contains_any(s, needles)
starts_with(s, prefix) / ends_with(s, suffix)
is_json(s)
random(length) — 随机字符串
pad_left / pad_right / repeat
```

**Arr** — 数组工具：
```
get(map, key, default)         — dot-notation 访问
set_string / forget_string     — map 写入/删除
has_string / only / except
collapse / flatten / wrap
reverse / take / skip
```

**分页 + 排序**（Spring Data 风格）：
```
LengthAwarePaginator[T]
  ├── items / total / per_page / current_page / last_page
  └── has_more_pages / on_first_page / on_last_page / to_json

SimplePaginator[T] — 仅 has_more（无 total）

Direction: asc | desc
SortOrder: {property, direction}
Sort: by() / by_desc() / ascending() / descending() / and() / or_()

PageRequest: {page, size, sort}
  ├── of(page, size) / of_sorted(page, size, sort)
  ├── next() / previous()
  └── has_previous() / get_sort()
```

### 3.12 HTTP 客户端（http/）

真实调用 V 标准库 `net.http`（`vhttp.fetch`），Spring RestTemplate 形态：

```
RestTemplate — 不可变配置，线程安全，可当单例复用
  ├── new_rest_template()
  ├── set_base_url / set_default_header(s)
  ├── set_connect_timeout / set_read_timeout（记录，V 的 FetchConfig 尚未暴露）
  ├── set_retry(max_retries, base_delay_ms) — 只对幂等方法重试（GET/HEAD/OPTIONS/PUT/DELETE）
  ├── set_error_handler(ResponseErrorHandler) — 错误响应策略
  ├── add_interceptor(ClientHttpRequestInterceptor) — 拦截器链（正向包裹）
  ├── set_uri_template_handler / set_ssl_config / set_proxy
  └── exchange(RequestEntity) → ResponseEntity

RequestEntity — 链式构建
  ├── request_entity(method, url)
  ├── .header(k, v) / .headers_from(map) / .body_str(s) / .body_json[T](v)
  └── .uri_var(k, v) / .uri_vars_from(map) — /users/{id} → /users/42

ResponseEntity:
  ├── status_code / status_text / headers / body
  ├── is_2xx() / is_4xx() / is_5xx()
  └── body_as[T]() / header_value(name)

便捷方法: get_for_object[T] / get_for_entity / post_for_object[T] /
          post_for_entity / put / delete / patch_for_entity /
          head_for_headers / options_for_allow
```
> 未覆盖：真实 TLS 校验开关与代理转发 —— V 的 `net.http.FetchConfig` 目前没有
> 对应字段，配置会被记录并打日志，但不会生效。

### 3.13 CLI 模块（cli/）

```
CliApplication
  ├── add_command(cmd)
  ├── find_command(name)
  ├── run() — 入口（解析 os.args → 分发）
  ├── print_help() / print_command_help()
  └── print_commands_table()

Command (interface)
  ├── name() / description() / signature()
  └── execute(input, output) → !

BaseCommand — 默认实现

内置命令:
  list     — 列出所有命令（绿色高亮名称）
  help     — 显示命令详情
  serve    — 启动 Web 服务器（--port=8080 --host=localhost）
  schedule:run  — 运行调度器
  queue:work    — 启动队列 Worker

代码生成命令:
  make:command     — 脚手架生成 Command
  make:controller  — 脚手架生成 Controller
  make:middleware  — 脚手架生成 Middleware

CLI 输出系统:
  CommandOutput
    ├── writeln / write / success(green) / error(red) / info(blue) / warning(yellow)
    ├── table(headers, rows) — 自动列宽
    ├── line(length) — 水平线
    └── progress — ProgressBar

  ANSI 格式化 (format.v):
    bold_text / dim_text / green_text / red_text / blue_text / yellow_text
    color_text / bg_color / underline_text / blink_text

交互式输入 (interactive.v):
  ask(prompt, default) → string
  confirm(prompt, default) → bool
  secret(prompt) → string
  choice(prompt, options, default) → string
```

### 3.14 Tracing 模块（tracing/）

**OpenTelemetry 风格的链路追踪**。

```
Span — 跨度数据结构
  ├── trace_id / span_id / parent_span_id
  ├── name / kind（client/server/internal/producer/consumer）
  ├── start_time / end_time
  ├── attributes — map[string]string
  ├── events — []SpanEvent（带时间戳的日志事件）
  └── status — SpanStatus（ok / error）

SpanExporter (interface) — 导出器抽象
  ├── export(spans []&Span) !
  └── shutdown() !

ConsoleExporter — 控制台导出器
  ├── export(spans) — 格式化输出 Span 到 stdout/stderr
  ├── 支持彩色/JSON 两种输出格式
  └── 适合开发调试

使用示例：
mut exporter := tracing.new_console_exporter()
span := tracing.new_span('db.query')
span.set_attribute('db.system', 'postgresql')
span.set_attribute('db.statement', 'SELECT * FROM users')
span.end()
exporter.export([span])!
```

---

## 4. 模块间依赖关系

### 4.1 显式依赖图

```
        photon（统一导出）
        │
    ┌───┼───┬───────┬───────┬──────┬──────┬──────┬──────┬──────┐
    │   │   │       │       │      │      │      │      │      │
  core config log  cache  orm    web   cli   queue storage http tracing
                    │      │      │      │      │
                    │      │      ├──core│      ├──core
                    │      │      │(plan)│      │(plan)
                    │      │      │      │      │
                    │  ┌───┘      │      └───┬──┘
                    │  │          │          │
                  pool  └──orm────┘      └───┘
                   │         │          queue
                   │         │         (worker内置)
                   │      security
                   │         │
                   │      web/filter
                   │
                 locking
                    │
                cache(可选)

strutil: 零依赖，所有模块都可使用
pageable: 零依赖（Sort / Page[T] / PageRequest）
ticker:  零依赖（纯 V channel/goroutine）
```

### 4.2 依赖说明

| 模块 | 依赖 | 说明 |
|------|------|------|
| config | 无 | 纯标准库 |
| strutil | 无 | 纯标准库（刻意零 import）|
| pageable | 无 | 纯标准库 |
| ticker | 无 | 纯 V channel |
| cache | xiusin.vredis（vendored） | 仅 RedisStore 需要；内存后端零依赖 |
| pool | orm (db_pool) | 仅 DbPool 依赖 orm.DriverType |
| locking | 无 | cache 可选（分布式锁后端） |
| queue | 无 | 无外部依赖 |
| storage | 无 | 标准库 os |
| http | 无 | 依赖 V 标准库 net.http |
| tracing | 无 | 零外部依赖 |
| security | 无 | web/filter 可选集成 |
| orm | 无 | V 标准 orm 不可用（同名冲突） |
| web | 无 | veb 外部依赖 |
| cli | 无 | 标准库 os |

> **外部依赖**：唯一第三方代码是仓库内 vendored 的 `xiusin.vredis`（见 `vendor/README.md`）。
> 直接 import 它的有 `cache/redis_cache.v`（`RedisStore`）、`locking/redis_lock_client.v`
> （`VRedisLockClient`）、`queue/redis_driver_client.v`（`VRedisQueueClient`）三处。
> 锁与队列仍然面向接口编程（`RedisClient` / `QueueRedisClient`），内建适配器只是
> 让「开箱可用」成立，用户仍可换成自己的 Redis 客户端。
>
> **Redis 集成测试**：`cache/redis_cache_integration_test.v`、
> `locking/redis_lock_integration_test.v`、`queue/redis_driver_integration_test.v`
> 都真连真用（各占一个独立 db），Redis 不可达时整体 skip 并打印原因 ——
> 不会把「本机没装 Redis」伪装成通过。

> **关键限制**：由于 V 0.5.1 不允许同名模块 import，`photon/orm` (module orm) 无法 import V 标准 `orm`。ORM 通过 `OrmAdapter[T]` 包装 + 用户手动调用 V ORM 的方式实现。

---

## 5. 数据流与生命周期

### 5.1 HTTP 请求完整流程

```
① CLI: app.run() → 解析 os.args → 匹配命令
    
② serve: web.run[App](8080)
    │
    ┌─ veb 框架接管 HTTP ──────────────────────────────┐
    │                                                    │
    │  ③ HttpKernel.handle()                             │
    │     ├─ dispatch(kernel.request)                     │
    │     │                                              │
    │     ├─ SecurityFilterChain.filter()  [security]     │
    │     │   ├─ is_public? → 跳过                       │
    │     │   ├─ is_deny_all? → 403                      │
    │     │   ├─ CSRF 校验                               │
    │     │   ├─ JWT 提取 + 验证                         │
    │     │   ├─ AuthenticationManager.authenticate()    │
    │     │   ├─ SecurityContextHolder.set()              │
    │     │   └─ AccessDecisionManager 角色/权限校验      │
    │     │                                              │
    │     ├─ FilterChain.apply_request_filters()          │
    │     │   └─ cors / content_type / custom             │
    │     │                                              │
    │     ├─ MiddlewareChain.run()                        │
    │     │   ├─ request_id_middleware                    │
    │     │   ├─ compression_middleware                   │
    │     │   ├─ timing_middleware                        │
    │     │   ├─ [自定义中间件]                           │
    │     │   └─ Pipeline (洋葱)                         │
    │     │                                              │
    │     ├─ Controller Handler                           │
    │     │   ├─ Route 匹配 → 路由参数                    │
    │     │   ├─ Model Binding（:id → Entity）            │
    │     │   ├─ DTO Binding（bind[T] / bind_json[T]）    │
    │     │   └─ 业务逻辑执行                             │
    │     │       ├─ Repository.find_by_id()              │
    │     │       ├─ OrmAdapter.wrap_*() (hooks)          │
    │     │       └─ Result.success() / .fail()           │
    │     │                                              │
    │     ├─ dispatch(kernel.controller)                  │
    │     │                                              │
    │     ├─ FilterChain.apply_response_filters()         │
    │     ├─ dispatch(kernel.response)                    │
    │     └─ dispatch(kernel.terminate)                   │
    └────────────────────────────────────────────────────┘
```

### 5.2 请求数据处理流（Input → Bind → Controller）

```
HTTP Request
    │
    ├─ Query String (?name=alice&page=1)
    ├─ Form Body (POST form data)
    ├─ JSON Body ({"name": "alice"})
    └─ Route Params (/users/:id)
         │
         ▼
    web.input(ctx)  — Input 包装器
         │
         ├─ .all()      — 合并 query + form
         ├─ .get(key)   — 键访问（query > form > URL）
         ├─ .integer() / .boolean()
         ├─ .only(keys) / .except(keys)
         ├─ .has(key) / .filled(key) / .missing(key)
         └─ .file(key) / .has_file(key)
         │
         ▼
    web.bind[T](ctx)  — DTO 绑定
         │
         ├─ 编译期 $for field in T.fields 扫描字段
         ├─ @[required] 校验 → 字段必须非空
         ├─ @[form: 'alt_name'] 自定义映射
         └─ bind_json[T](ctx) — JSON body 绑定
         │
         ▼
    Controller 方法参数 / 结构体字段
```

### 5.3 ORM 实体生命周期

```
new Entity()
    │
    ├─ BaseEntity: id=0, created_at=0, updated_at=0  (is_new() = true)
    │
    ▼
wrap_insert(entity, callback)
    ├─ before_insert(entity)  → BeforeCreateHook
    │     └─ touch() → set created_at + updated_at
    ├─ callback(entity)       → V 标准 ORM insert
    └─ after_insert(entity)   → AfterCreateHook
         │
         ▼
    (entity.id 已分配，is_new() = false)
         │
         ▼
wrap_update(entity, callback)
    ├─ before_update(entity)  → BeforeUpdateHook
    │     └─ touch() → update updated_at
    ├─ callback(entity)       → V 标准 ORM update
    └─ after_update(entity)   → AfterUpdateHook
         │
         ▼
wrap_delete(entity, callback)
    ├─ before_delete(entity)  → BeforeDeleteHook
    ├─ callback()             → V 标准 ORM delete
    └─ after_delete(entity)   → AfterDeleteHook
```

### 5.4 缓存读写流程

```
get_or_load(key, ttl, loader)
    │
    ├─ 快速路径: cache.has(key) → 直接返回
    │
    └─ 缓存未命中:
         └─ singleflight.do(key, fn)
              ├─ 第一个请求: 执行 loader()
              ├─ 并发请求: 等待第一个结果
              └─ 结果写入缓存 + 返回
```

---

## 6. 注解系统

### 6.1 注解分类

| 类别 | 注解 | 作用域 | 说明 |
|------|------|--------|------|
| **Web 路由** | `@[get('/path')]` | fn | GET 路由 |
| | `@[post('/path')]` | fn | POST 路由 |
| | `@[put('/path')]` | fn | PUT 路由 |
| | `@[delete('/path')]` | fn | DELETE 路由 |
| | `@[patch('/path')]` | fn | PATCH 路由 |
| | `@[middleware('name')]` | fn | 路由级中间件 |
| **安全** | `@[secured]` | fn | 需要认证 |
| | `@[roles_allowed('ADMIN','USER')]` | fn | 角色限制 |
| | `@[permit_all]` | fn | 公开 |
| | `@[deny_all]` | fn | 全部拒绝 |
| | `@[pre_authorize]` | fn | 预留 |
| **DTO 绑定** | `@[required]` | field | 必填字段 |
| | `@[form: 'alt_name']` | field | 字段名映射 |
| **配置** | `@[value('config.key')]` | field | 注入配置值 |
| **ORM** | `@[sql: 'col_name']` | field | SQL 列名 |
| | `@[sql_type: 'TEXT']` | field | SQL 类型 |
| | `@[table: 'table_name']` | struct | 表名 |
| **组件 (已实现)** | `@[component]` | struct | 标记为组件 |
| | `@[service]` | struct | 标记为服务 |
| | `@[repository]` | struct | 标记为仓库 |
| | `@[controller]` | struct | 标记为控制器 |
| | `@[configuration]` | struct | 标记为配置类 |
| | `@[auto_configuration]` | struct | 自动配置类 |
| | `@[autowired]` | field | 自动注入 |
| | `@[lazy]` | struct/fn | 延迟初始化 |
| | `@[scope('singleton')]` | struct | 作用域 |
| | `@[qualifier('name')]` | field | 限定符 |
| | `@[post_construct]` | fn | 初始化回调 |
| | `@[pre_destroy]` | fn | 销毁回调 |
| | `@[required]` | field | 必须注入（配合 @[autowired]）|
| | `@[event_listener]` | fn | 事件监听器 |
| **条件装配** | `@[conditional_on_profile('prod')]` | struct | Profile 条件 |
| | `@[conditional_on_property('key')]` | struct | 属性存在条件 |
| | `@[conditional_on_property('key','val')]` | struct | 属性值条件 |
| | `@[conditional_on_bean('Name')]` | struct | Bean 存在条件 |
| | `@[conditional_on_missing_bean('X')]` | struct | Bean 不存在条件 |
| | `@[conditional_on_expression('key==val')]` | struct | 表达式条件 |
| | `@[conditional_on_class('Type')]` | struct | 类存在条件 |
| | `@[conditional_on_missing_class('Type')]` | struct | 类不存在条件 |
| | `@[conditional_on_cloud_platform('aws')]` | struct | 云平台条件 |
| **横切** | `@[cacheable]` | fn | 方法级缓存 |
| | `@[transactional]` | fn | 事务 |
| | `@[scheduled('cron')]` | fn | 定时任务 |
| **ORM 实体** | `@[entity]` | struct | 标记为实体 |
| | `@[table('name')]` | struct | 表名映射 |
| | `@[column('name')]` | field | 列名映射 |
| | `@[id]` | field | 主键标注 |
| | `@[primary_key]` | field | 主键标注（别名） |
| | `@[generated_value]` | field | 自增主键 |
| | `@[version]` | field | 乐观锁版本号 |
| | `@[created_at]` | field | 创建时间自动填充 |
| | `@[updated_at]` | field | 更新时间自动填充 |
| | `@[soft_delete]` | field | 软删除标记 |
| | `@[size(255)]` | field | 字段长度约束 |
| | `@[nullable]` | field | 允许为空 |
| | `@[unique]` | field | 唯一约束 |
| **DTO 验证** | `@[required]` | field | 必填字段 |
| | `@[email]` | field | 邮箱格式验证 |
| | `@[min(0)]` | field | 最小值 |
| | `@[max(100)]` | field | 最大值 |
| | `@[pattern('regex')]` | field | 正则匹配 |
| | `@[length(1, 255)]` | field | 字符串长度范围 |
| **队列** | `@[job]` | struct | 标记为 Job Bean |
| | `@[job: 'queue_name']` | struct | 指定队列名称 |
| | `@[retry: '3']` | struct | 重试次数 |
| | `@[backoff: '1000,5000']` | struct | 退避策略 |
| | `@[timeout: '30']` | struct | 超时时间 |
| **CLI** | `@[command]` | struct | 标记为命令 |
| | `@[command: 'name']` | struct | 指定命令名称 |
| | `@[description('help')]` | struct | 命令描述 |
| | `@[option('name')]` | field | 命令选项 |
| | `@[argument]` | field | 位置参数 |

### 6.2 扫描机制

所有注解通过 V 编译期反射 `comptime $for` 扫描：

```v
// router.v 示例
pub fn scan_routes[T]() []RouteInfo {
    mut routes := []RouteInfo{}
    $for method in T.methods {
        mut found_route := false
        mut http_method := ''
        mut path := ''
        for attr in method.attrs {
            if attr.starts_with('get:') || attr.starts_with('post:') || ... {
                found_route = true
                http_method = attr.before(':').to_upper()
                path = attr.after(':').trim(' ')
            }
        }
        if found_route {
            routes << RouteInfo{method: http_method, path: path, handler_name: method.name}
        }
    }
    return routes
}
```

### 6.3 当前状态

> 路由、安全、DTO 绑定注解已在代码中使用。组件 DI、条件装配、事件监听器注解已在 `core/` 模块实现运行时支持，完整的编译期自动装配由 comptime scanner 驱动。

---

## 7. 关键设计决策

### 7.1 零反射原则

所有框架能力在**编译期**通过 `comptime $for` 实现，不使用运行时类型反射（TypeInfo）。这保证了：
- 启动速度快（无类加载/注解扫描开销）
- 二进制体积小（无反射元数据）
- 编译期错误检查

### 7.2 V 0.5.1 同名模块冲突

**关键限制**：`photon/orm` 的模块名为 `orm`，V 0.5.1 不允许 import `vlib/orm`（同名冲突）。解决策略：
- `OrmAdapter[T]` 不直接调用 V ORM，只提供生命周期钩子包装
- 用户在自己的代码中 import V 标准 `orm`，自行创建 `QueryBuilder`
- 用户调用 `adapter.wrap_insert(entity, fn [mut qb] (mut e T) ! { qb.insert(e)! })!`
- 未来 V 支持 import 别名后可升级

### 7.3 零外部依赖

当前版本 **零外部依赖**（`v.mod` 的 `dependencies: []` 为空）。SHA-256、Base64、时间轮调度器均自行实现。这确保了：
- 编译极快
- 无依赖冲突
- 部署简单（单二进制）

### 7.4 web 模块的 veb 集成策略

V 的 `veb` 框架要求 app struct 嵌入 `veb.Context`。Photon 通过 `web.run[T](port)` 单泛型包装隐藏这一细节：
```v
// 用户代码
pub struct MyApp {
    veb.Context
}
web.run[MyApp](8080)

// 等价于
mut app := &MyApp{}
veb.run[MyApp, MyApp](mut app, 8080)
```

### 7.5 多后端抽象模式

Cache、Queue、Locking、Storage 均遵循相同模式：
```
interface 定义契约 → Manager 管理多后端 → 具体实现
```
这使得用户可以在开发时使用内存后端，生产环境切换到 Redis/S3 等。

---

## 8. 测试策略

### 8.1 测试分布

| 模块 | 测试文件数 | 测试框架 |
|------|-----------|----------|
| web | 55 | V built-in test + TestResponse 助手 |
| orm | 33 | V built-in test |
| core | 30 | V built-in test |
| security | 17 | V built-in test |
| cache | 17 | V built-in test |
| queue | 9 | V built-in test |
| strutil | 8 | V built-in test |
| pageable | 2 | V built-in test |
| config | 6 | V built-in test |
| locking | 6 | V built-in test |
| ticker | 6 | V built-in test |
| logger | 5 | V built-in test |
| pool | 5 | V built-in test |
| storage | 5 | V built-in test |
| http | 4 | V built-in test |
| async | 4 | V built-in test |
| metrics | 3 | V built-in test |
| mailer | 3 | V built-in test |
| apidoc / health / photon_i18n / retry / tracing | 2 各 | V built-in test |
| cli | 6 | V built-in test（含对生成产物的真实编译） |
| core/tests | 2 | V built-in test（黑盒集成） |
| **合计** | **236** | |

### 8.2 测试模式

```v
// V 语言测试：v -enable-globals test <module>/

// 标准测试文件命名：<feature>_test.v
// 测试函数：fn test_<name>() {

// 运行时需 -enable-globals flag（因为 queue 使用了 __global）
```

### 8.3 运行方式

```bash
# 单个模块
v -enable-globals test web/

# 全部模块：逐文件跑，编译与运行分开计时
#   PHOTON_BUILD_TIMEOUT  编译预算（默认 180s）
#   PHOTON_TEST_TIMEOUT   运行预算（默认 30s）
sh scripts/run-tests.sh
sh scripts/run-tests.sh web orm        # 只跑指定模块

# 沙箱里 `cc` 读 .rsp 后不产出二进制时（症状：所有文件都「编译失败」但 v run 正常）：
VFLAGS="-enable-globals -no-rsp" sh scripts/run-tests.sh

# 本机没有可用的 gc 库时（预编译 gc 缺 sigsetjmp 符号）：
VFLAGS="-enable-globals -gc none" sh scripts/run-tests.sh
```

**为什么要逐文件跑。** `v test mod/` 把整个模块的用例编进一个二进制，
只要里面有 1 个用例死锁，整个模块就挂住，CI 只能等到全局限时才失败 ——
既拿不到「是谁卡的」，也会把后面的模块一起拖死。

**为什么编译与运行要分开计时。** `v test file_test.v` 是「编译 + 运行」两段，
web 模块冷编译本身就要 10~15 秒。合成一个 30 秒预算时，慢机器上的编译就会
吃光预算并被标签成「多半是死锁」，于是有人去查一个并不存在的死锁。

### 8.4 功能验证套件（example/verify）

`example/verify/` 是一个独立的自验证程序（`module main`，与 `example/` 的
Web 应用分开），用断言逐项验证 DI、注解、控制器挂载、ORM 链式查询、安全、
缓存等模块的**真实用法**——不只是「能编译」。当前 **247 项断言**。

```bash
make verify                                  # v run example/verify
sh scripts/apply-v-patches.sh                # 先打编译器补丁（见下）
```

**它需要一份编译器补丁，这不是可选项。** 验证套件跑的是框架的核心约定：

```v
@[get: '/users/:id']
pub fn (mut c Ctrl) show(mut ctx veb.Context, params map[string]string) veb.Result
```

而 V 0.5.2 的 `checker.fn_decl()` 把**任何**返回 `veb.Result` 的方法都当成
veb app 方法，只放行 `string / 整数 / bool`。于是这 7 个方法整包编不过。

这条约束没法在框架里绕开——把参数改成 `string` 就等于放弃路径参数，
那不是「绕开检查」，是把框架能力砍掉。所以补丁放在编译器一侧：
`scripts/v-patches/0001-*.patch`，用 `scripts/apply-v-patches.sh` 应用。
补丁只在方法带路由属性时跳过该检查，veb 自身的约束不变。

**这条套件长期没人跑，所以它坏了很久没人知道**——`locate_controller[T]` 曾经
只存在于文档里、原型作用域的 bean 曾被缓存成单例、`run_with_graceful_shutdown()`
曾经整块编不过。三个都是它第一次跑起来时才暴露的。

### 8.5 启动入口的可测试性（web/server.v）

`web.run[A, X](port)`、`web.run_with_routes[A, X](port)` 曾经没有任何用例，
原因不是没人想写，而是**写不出来**：端口、监听地址、启动横幅全写死在函数体
里，一调用就独占端口且永不返回。于是它们和当年的 `run_with_graceful_shutdown`
一样，处在「没人调用 → 没有用例 → 每次全绿都跟它无关」的循环里。

现在把「怎么起」和「真的去起」拆开：

```v
// 参数与校验：端口非法时不会去碰监听
params := web.new_server_run_params(8080).with_host('127.0.0.1').with_routes(true)
params.validate()!

// run_by 收一个可注入的启动器；测试传假的，生产传 veb_starter
web.run_by[App, Context](params, web.veb_starter[App, Context]())!

// 生产入口不变
web.run[App, Context](8080)
web.run_with_routes[App, Context](8080)
web.run_with_params[App, Context](params)!
```

`ServerStarter` 的返回类型是 `!string` 而不是 `!void`：V 里 `!void` 的 `or`
块只能拿到 void，错误无法干净地上抛给 `run_by` 的调用方，而「端口被占要
原样传回」正是这里必须验的事。

`web/server_run_params_test.v` 的 12 条用例覆盖：默认值、`with_*` 的不可变
语义、端口边界、参数透传、**校验先于启动**、启动错误上抛、路由表扫描。

**顺带修掉的两个展示层缺陷**（写这组用例时才暴露）：

1. `scan_controller` 只认「分离式」`@[get]` + `@['/x']`，把「合并式」
   `@[get: '/x']` 整条漏掉。而 `mount_controller` 走的是
   `parse_route_attrs`，它认三种写法 —— 于是出现「路由能访问，
   启动横幅和 actuator `/mappings` 里却一条都没有」的错位。
2. `scan_controller` 不拼控制器前缀 `@[prefix: '/api/v1']`，展示的路径比
   真实可访问路径短一段。

### 8.6 注解驱动的 CLI（cli/cli.v · cli/input.v）

**这两块代码在 0.5.2 下从来没编过。**

`scan_command[T]()` 和 `bind_input[T]()` 是把「struct 上的注解」变成「命令元数据
和强类型参数」的入口，也是 Photon CLI 与 Spring Shell / Laravel Artisan 对齐的
关键。但它们把 `field.attrs` 当成 `[]VAttribute` 用（读 `.name` / `.args`），
而 0.5.2 里它的实际类型是 `[]string`：

```
field.attrs   → []string   ["option: 'env'", "default: 'production'"]
T.attributes  → []VAttribute { name, has_arg, arg, kind }
```

因为没有任何用例、也没有任何 example 实例化过这两个函数，编译器从没被要求
编过它们 —— 又一个「没人调用 → 没有用例 → 全绿与它无关」的循环。

修掉之后暴露的问题比编译本身更多：

1. **布尔选项永远绑不上。** `--verbose` 在 argv 上是裸的，`new_input` 把它归进
   `flags`，而 `bind_input` 只查 `options`。于是所有 `bool` 字段恒为 false。
2. **「名字声明过」说明不了「要不要吞下一个 token」。** 旧的 schema 是
   `map[string]bool`，`--verbose v2` 里 `verbose` 确实被声明过，于是 `v2` 被
   当成它的值吃掉，位置参数从此错位。现在 `OptionSchema` 区分
   `declare_flag_option` / `declare_value_option`。
3. **位置参数按字段名查，不按声明顺序。** 编译期循环里不允许 `break` /
   `continue`，所以序号必须整段扫完再定位（`arg_index_of[T]`）。
4. **回退命名带模块前缀。** 没有 `@[command: 'x']` 时用 `T.name`，拿到的是
   `cli.PlainCmd`，用户得敲 `app cli.PlainCmd`。现在剥掉前缀。

对外新增的入口：

```v
// 推荐：类型自己出解析表，再解析 argv —— 调用方不必知道哪个选项是布尔
cmd := cli.bind_input_from_args[DeployCmd](os.args[1..])!

// 已经解析好 argv 时
schema := cli.schema_for[DeployCmd]()
input := cli.new_input_with_schema(argv, schema)
cmd := cli.bind_input[DeployCmd](input)!
```

`bind_input_from_args` 存在的理由不是好看：`bind_input` 拿到的是**已经解析错的**
结果，被吞掉的那个 token 补不回来。只有让类型参与解析，`--verbose v2` 才可能正确。

**顺带让 CLI 变得可测**（否则上面这些一条都验不了）：

- `run()` → `run_args(args)` / `run_args_with_output(args, mut output)`：
  `run()` 直接读 `os.args`，用例一调就分发到「上个测试的 argv」。
- `CommandOutput` 增加内存收集（`new_capturing_output()` / `collected()`）：
  原先所有输出直接 `println` 落进程 fd，用例拿不到「它到底印了什么」。
- `app.option_schema_for(command)` 抽成独立方法：这是「布尔还是取值」的
  唯一判断点，单独暴露才能被用例锁住。

`cli/annotated_command_test.v` 共 23 条用例。做过五轮变异验证：布尔不查 flags、
schema 忽略 takes_value、位置参数不按声明顺序、命令名不剥前缀、application 不区分
布尔选项 —— 每一条都让对应用例变红，恢复后绿。

### 8.7 交互式输入与进度条（cli/interactive.v · cli/progress.v）

这两个文件之前一条用例都没有 —— 和 `CommandOutput` 是同一个病症，只是还没被碰到：
它们直接读写进程的 stdin/stdout。

| 文件 | 之前的写法 | 后果 |
|---|---|---|
| `interactive.v` | 直接 `os.input()` | 用例一调就挂在 stdin 上等输入 |
| `progress.v` | 直接 `print()` | 用例只能断言 `current`，看不到那一行 |

所以先把「算」和「画/读」拆开：`*_from` / `parse_*` / `render_text()` 是纯函数，
`ask()` / `confirm()` / `advance()` 之类保留原签名，内部只是一层薄薄的 IO。
用例因此可以既提供答案、又断言问了什么。

**拆开之后暴露的四个逻辑缺陷：**

1. **`choice` 的 `for {}` 没有出口。** 空行、字母、越界数字都走不到返回，
   终端里就是一个死循环；选项列表为空时提示语自身先吐 `[0--1]`。
   现在最多重问 `max_choice_attempts` 轮，用尽返回 -1。
2. **字母被当成第 0 项。** `'abc'.int()` 在 V 里返回 `0` 而不是报错，
   于是 `choice` 把任何非数字输入都选中第一项。现在先按十进制校验形态再判越界，
   前导 `0`（`'00'` / `'03'`）也一并拒绝 —— 它们同样不是任何一个选项号。
3. **`confirm` 只认 `y` / `yes`。** 旧实现是 `input == 'y' || input == 'yes'`，
   `yeah` / `yep` 落到 false，而 `[Y/n]` 给用户的暗示是「回车即 yes」。
   现在空输入回落默认值，其余看首字母。
4. **`ask_required` 与 `choice` 分不清 EOF 和空行。** `os.input()` 在 EOF 时返回
   字面量 `<EOF>`，于是 `ask_required` 会把 `<EOF>` 当答案交给调用方。
   改用 `os.input_opt()`，并且两条循环都有轮数上限。

**进度条第 5、6 个缺陷更隐蔽，因为它们只在极端值上现形：**

5. **走完了显示 0%。** `percentage()` 用 `cur * 100 / total`，`cur` 接近 int 上限
   时乘积溢出成负数（`2000000000 * 100` → `-1863462912`），除回去得到 0。
   先判两端（`cur <= 0` → 0、`cur >= total` → 100）再乘法。
6. **进度条不等宽。** `cur == total` 时 `filled` 正好等于 `width`，代码里
   `if filled < pb.width` 不成立，于是少画一格箭头、空槽循环也多跑一格 ——
   画出来是 `[====]` 而不是 `[===>]`，而且宽度随进度漂移。另外 `advance(-5)`
   能把 `current` 推成负数，空槽反而变多。现在 `clamp()` 双向夹紧，
   `render_text()` 的条形区恒为 `width + 2` 个字符。

`cli/interactive_test.v` 21 条 + `cli/progress_test.v` 15 条。八轮变异验证：
不再拒绝字母、`confirm` 退回 `== y`、`percentage` 退回乘法、`cur==total` 仍画箭头、
去掉下界夹紧、去掉前导 0 拒绝、空选项提示语、空进度静默返回 —— 每一条都变红，
恢复后绿。

### 8.9 脚手架产物的编译验证（cli/make_commands.v）

`make:*` 是脚手架命令：用户敲一条，拿到一份可以直接开工的代码。因此对它唯一
有意义的验收标准是「**产出的文件能编译**」，而不是「命令返回 0」。

这 10 个生成器产出的 80 个文件里，曾有 **48 个编不过**：

| 目录 | 原因 |
|---|---|
| `commands/`、`database/seeders/` | `output` 参数缺 `mut`（"output is immutable"） |
| `middleware/` | 签名与 `web.MiddlewareFunc = fn (ctx &MiddlewareContext) !bool` 不匹配 |
| `database/factories/` | 返回栈上接收者的引用；返回类型 `factories.XxxResource` 不存在 |
| `repositories/` | 实体写成包内名字，实际在 `entities` 包 |
| `database/migrations/` | `phorm.TableBuilder`、`phorm.execute_schema` 都不存在 |

它们能一直躺着，是因为用例只断言过「命令名对」，从没断言过「产物能编」。
`cli/make_stub_compiles_test.v` 补上的是这件事：真调一次生成器，再用真实的
V 编译器编一次产物（`-shared -o`，因为模块包本来就没有 `main`）。找不到
`v` 可执行文件时**跳过并打印原因**，不在没有编译器的环境里假装通过。

同一批用例还锁住了三个语义缺陷：

- `to_snake_case` 早先是手写实现，每个大写字母前插下划线，`HTMLParser` →
  `h_t_m_l_parser`、`UserDOB` → `user_d_o_b`，生成的文件叫
  `controllers/user_d_o_b.v`。`cli_test.v` 里那条
  `assert to_snake_case('HTMLParser') == 'h_t_m_l_parser'` 把这个 bug 锁成了
  「正确行为」——**把现状写成断言，就等于把缺陷升格成契约**。现在委托给
  `support.snake`，缩写连读。
- 迁移版本号写死 `return 100` 并留了句 TODO。版本号是 `MigrationManager`
  排序与去重的唯一依据，每个迁移都是 100 就等于「只有第一个会执行」。改为
  由名字哈希得出，同名稳定、异名不撞。
- `make:migration` 用 `time.format_ss()` 当文件名，得到
  `2026-11-06 14:57:47`，中间的空格把路径切成两段。改为 `YYYYMMDDHHMMSS`。

变异验证（每条都让对应用例变红、恢复后绿）：

```
to_snake_case 退回原样返回      → 5 条红
生成器去掉 mut output           → 红，报 "output is immutable"
迁移退回 phorm.TableBuilder     → 红，报 "unknown method TableBuilder.id"
```

### 8.10 模块命名：任何顶层目录都不能被 `photon.<dir>` 撞上

`photon.v` 声明 `module photon`，仓库根目录就是 photon 模块的目录。于是任何
顶层目录 `X/` 会**同时**被注册成两个名字：

```
import X          → <root>/X
import photon.X   → <root>/X     （同一个目录，两张模块表）
```

两条路径同时被加载时，V 会解析到 `photon.X` 那份**空的**函数表。报出来的不是
「找不到模块」，而是更难查的一串：

```
orm/entity.v:358:17: error: unknown function: support.snake
orm/entity.v:358:2:  error: `support.snake(field_name)` used as value
```

历史上 `support/` 就是这个形状，任何 `import photon.web` 的下游用户都编不过。
当时的处置是给 orm / web / core 各留一份 `fnv1a_str` 副本绕开 —— 那治的是症。

**根治方式是改名。** `support/` 现在是 `strutil/`，`Sort` / `Page[T]` /
`PageRequest` 这套分页类型挪进了新的 `pageable/`。这两个名字都不会和
`photon.<x>` 撞车，双重身份这条路径彻底不存在了。

`orm/local_hash.v`、`web/ratelimit.v`、`core/sharded_lock.v`、`cache/memory.v`
里的本地哈希/snake_case 副本**保留**，但理由换了：从「绕开编译缺陷」变成
「热路径不绕一层跨模块调用」。副本一致性靠 `orm/local_hash_test.v` 与
`strutil/str_case_test.v` 两边各自的字符向量表互相钉住。

#### 防回归：`strutil/module_identity_test.v`

光把目录改名不够 —— 下一个人完全可以再建一个同形状的目录，然后一切照旧。
所以有一组用例直接扫仓库：

- 任何顶层目录里若有 `module <dir>`，就不许出现顶格的 `import photon.<dir>`
  （字符串字面量会先被剥掉，`cli/make_commands.v` 的生成器模板不算）
- `support/` 目录一旦复活就红，报错信息直接写清它为什么会打断下游构建
- 公开模块名单逐个断言存在，防止误改名

变异验证：造 `support/` 目录 → 红；造 `mymod/` 并让 `core/core.v` 真的
`import photon.mymod` → 红；清理后 → 绿。

#### 顺带撞出来的两件事

1. **`mut` 闭包捕获在 V 0.5.2 下是副本。** 这组用例的第一版用
   `fn [mut acc] (path string) { acc.paths << path }` 收集文件，结果恒为空表，
   用例恒过。最小复现：

   ```v
   mut c := 0
   f := fn [mut c] () { c++ }
   f()
   f()
   println(c) // 0
   ```

   闭包内部的 `c` 确实在累加（打印 1、2），外部始终是 0。前几轮记录里说
   「没能证明闭包捕获是副本」，这一轮证到了。绕法是用指针
   （`acc &VFileAcc` + `unsafe { mut a := acc }`）。

2. **生成器模板里的 `import` 必须写 `photon.<mod>`，不能写裸名。**
   `cli` / `orm` / `pool` 这三个模块名与 **vlib 自带模块同名**。仓库外的用户
   写 `import orm` 会解析到 `vlib/orm`（里面没有 `DriverType`），而且是静默的
   —— 报的是 `unknown enum orm.DriverType`，看不出「你import 错了模块」。
   所以 `make:*` 生成的 stub 一律写 `import photon.cli` / `import photon.orm as phorm`，
   前提是框架以 `~/.vmodules/photon` 的形式被安装。

### 8.8 测试环境的两个硬前提（踩坑记录）

`scripts/run-tests.sh` 之外，还有两条不写下来每次都会重踩的：

- **`-no-rsp` 是必须的。** V 0.5.2 会把 C 编译参数写进 `@<out>.rsp` 响应文件再交给
  `cc`；在部分沙箱里 `cc` 读完响应文件返回 0，但**不产出二进制**，`v` 于是报
  编译成功、脚本报「产物不存在」。表现是「所有测试文件都编译失败，但直接
  `v run` 又能跑」。所以跑测试时用
  `VFLAGS="-enable-globals -no-rsp" sh scripts/run-tests.sh`。
- **`thirdparty/tcc/lib/libgc.a` 得手工补一个归档。** 删掉 `thirdparty/tcc` 回退
  系统 `cc` 之后，链接仍会去找这个路径。编一次 `thirdparty/libgc/gc.o`
  （`-DGC_THREADS=1`，不能带 `-DTHREAD_LOCAL_ALLOC=1`），再
  `ar rcs thirdparty/tcc/lib/libgc.a thirdparty/libgc/gc.o` 放到位。

### 8.4 Web 测试工具

```v
// testing.v 提供了链式断言
mut res := web.TestResponse{}

res.assert_status(200)
   .assert_successful()
   .assert_json_path('data.user.name', 'Alice')
   .assert_json_count('data.users', 5)
   .assert_header('Content-Type', 'application/json')
   .assert_body_contains('success')
```

---

## 9. CI/CD 与部署

### 9.1 CI 流程（.github/workflows/ci.yml）

```
Stage 1 — Test (矩阵: 14 个模块, 并行)
  ├── 每个模块独立运行 v test
  └── 汇总检查 all passed

Stage 2 — Build (push to main/master)
  ├── 仅在 test 通过后执行
  └── v -prod -o bin/photon example/main.v

Stage 3 — Docker Build & Push
  ├── ghcr.io 推送
  └── 标签: latest + commit SHA
```

### 9.2 部署方式

**Docker 多阶段构建**：
```
Stage 1 (builder): ubuntu:22.04 + V 编译器 → 编译
Stage 2 (runtime): ubuntu:22.04 + 仅 binary + ca-certificates
  └── 非 root 用户 photon
  └── HEALTHCHECK → /health endpoint
  └── 默认端口 8080
```

**systemd 服务**：
```
Type=simple
User=www-data
WorkingDirectory=/opt/photon
Security hardening:
  ├── NoNewPrivileges=yes
  ├── ProtectSystem=strict
  ├── ProtectHome=yes
  ├── PrivateTmp=yes
  └── ReadWritePaths=/opt/photon/data /opt/photon/logs
Resource limits:
  ├── LimitNOFILE=65535
  └── LimitNPROC=4096
```

**Makefile 目标**：
```
build    — 编译 example → bin/photon-example
run      — v run example/main.v
test     — ORM 快速测试
test-all — 全部模块测试
check    — 类型检查（无执行）
service  — 生产编译 → systemd 部署
docker   — Docker 镜像构建
```

---

## 10. 模块成熟度矩阵

| 模块 | 成熟度 | 功能完整性 | 测试覆盖 | 生产就绪 |
|------|--------|-----------|---------|---------|
| config | Beta | 高 | 中 | 部分 |
| web | Beta | 高 | 高 | 部分 |
| orm | Beta | 高 | 高 | 受限（V orm 冲突）|
| security | Beta | 高 | 高 | 部分 |
| cache | Beta | 高 | 中 | 是 |
| queue | Beta | 中 | 低 | 开发 |
| pool | Beta | 中 | 低 | 部分 |
| locking | Beta | 中 | 中 | 部分 |
| storage | Beta | 高 | 中 | 是（仅本地磁盘；云存储留作扩展点）|
| ticker | Beta | 高 | 中 | 是 |
| strutil | Beta | 高 | 高 | 是 |
| pageable | Beta | 高 | 高 | 是 |
| cli | Beta | 高 | 低 | 是 |
| http | Beta | 高 | 中 | 部分（TLS/代理配置未生效）|
| tracing | Alpha | 中 | 低 | 否（新模块）|
| core | Beta | ApplicationContext + Container + Environment + EventBus + Lifecycle + BeanPostProcessor + FactoryBean + ServiceLocator + AutoConfiguration | 37 | 是 |

### 成熟度定义

- **Alpha**：实验性，API 可能变更，核心功能未完成
- **Beta**：功能完整，接受反馈，可能有小缺陷
- **GA**：生产就绪，长期支持（当前无 GA 模块）

---

## 附录

### A. 核心文件速查

| 文件 | 行数 | 关键内容 |
|------|------|---------|
| photon.v | 136 | 统一 re-export（约 50 个 type alias） |
| web/router.v | 149 | RouteRegistry + compile-time scan_routes[T] |
| web/middleware.v | 193 | MiddlewareChain + request_id/compression/timing |
| web/result.v | 144 | Result + PageResult + 全部 HTTP 状态码 |
| web/testing.v | 602 | TestResponse 链式断言（含 JSON 路径断言） |
| web/bind.v | 151 | DTO 绑定 + @[required] 校验 |
| web/server.v | 200 | web.run[T] 包装器 + 可注入启动参数 |
| web/filter.v | 111 | FilterChain + CORS / Content-Type 过滤器 |
| web/middleware_groups.v | 157 | 中间件组 + 参数化 CORS/Throttle |
| web/pipeline.v | 52 | 洋葱模型管道 |
| web/input.v | 222 | Laravel 风格请求输入 |
| web/ratelimit.v | 94 | 内存限流器 |
| web/model_binding.v | 111 | 路由模型绑定 |
| web/kernel.v | 71 | HttpKernel 事件生命周期 |
| orm/orm.v | 683 | OrmManager + DriverType 类型检测 |
| orm/entity.v | 117 | Entity 接口 + BaseEntity + SoftDeletable + 6 种钩子 |
| orm/adapter.v | 250 | OrmAdapter[T] 生命周期包装器 |
| orm/repository.v | 367 | Repository[T] + BaseRepository + DerivedRepository |
| orm/derive.v | 243 | 方法名解析（findByNameAndAge → QueryParts）|
| orm/transaction.v | 167 | 7 种传播行为 + 隔离级别 |
| orm/relation.v | 132 | HasMany / BelongsTo / ManyToMany |
| orm/eager.v | 166 | EagerLoader N+1 预防 |
| orm/migration.v | 85 | Migration + MigrationManager（stub）|
| security/jwt.v | 334 | JWT 完整实现（HMAC-SHA256，纯 V）|
| security/auth.v | 158 | AuthenticationManager + Provider + PasswordEncoder |
| security/role.v | 171 | RoleHierarchy + AccessDecisionManager + 默认权限 |
| security/filter.v | 190 | SecurityFilterChain（veb filter 集成）|
| security/csrf.v | 153 | CsrfManager + Double-Submit Cookie |
| security/context.v | 110 | SecurityContext + SecurityContextHolder |
| security/annotations.v | 97 | 安全注解解析 |
| security/encryption.v | 75 | XOR 加密 |
| security/hashing.v | 124 | Bcrypt + Argon2 密码哈希 |
| security/principal.v | 108 | UserDetails + UserDetailsService |
| cache/cache.v | 100 | Cache + CacheManager |
| cache/memory.v | 232 | MemoryCache（RwMutex + TTL + LRU + stats）|
| cache/cache_tags.v | 247 | TaggedCache + CacheLock + remember/sear |
| cache/singleflight.v | 108 | 缓存削峰 |
| queue/queue.v | 46 | Job + JobPayload |
| queue/driver.v | 25 | QueueDriver 接口 + 序列化工具 |
| queue/dispatcher.v | 100 | QueueDispatcher（全局单例）|
| queue/memory_driver.v | 56 | MemoryDriver |
| queue/worker.v | 66 | QueueWorker |
| queue/failed_jobs.v | 140 | 失败任务持久化 + 重放 |
| locking/lock.v | 189 | LockManager + LocalMutex + LockGuard(RAII) |
| pool/pool.v | 160 | Pool + PoolStats |
| pool/db_pool.v | 61 | DbPool |
| storage/storage.v | 204 | Storage + StorageManager + FileMetadata |
| storage/local_adapter.v | 291 | LocalAdapter（完整文件系统操作）|

| ticker/timer.v | 196 | Timer/Ticker（Go 兼容 API）|
| ticker/heap.v | 173 | 4-ary min-heap |
| ticker/bucket.v | 134 | 64 桶调度器 |
| ticker/optimizer.v | 126 | 桶头最小堆优化 |
| strutil/collection.v | 315 | 链式集合（30+ 方法）|
| strutil/str.v | 309 | 字符串工具（20+ 方法）|
| strutil/arr.v | 232 | 数组工具 |
| pageable/pagination.v | 126 | 分页器（已弃用，迁移到 Page[T]）|
| pageable/sort.v | 171 | Sort + PageRequest |
| pageable/page.v | 130 | Page[T] + Slice[T] |
| cli/application.v | 226 | CliApplication + 可测的解析入口 |
| cli/command.v | 38 | Command 接口 |
| cli/input.v | 388 | CommandInput 参数解析 + OptionSchema |
| cli/attrs.v | 76 | 编译期属性解析（两侧共用） |
| cli/output.v | 172 | CommandOutput 彩色输出 + 内存收集 |
| cli/format.v | ~60 | ANSI 格式化 |
| cli/interactive.v | ~80 | ask/confirm/secret/choice |
| cli/progress.v | ~40 | ProgressBar |
| cli/builtin.v | 132 | list/help/serve 命令 |
| http/client.v | 650 | RestTemplate + RequestEntity/ResponseEntity + 拦截器 |
| example/main.v | 373 | 全功能演示 |
| AGENTS.md | 172 | 开发规范宪法 |
| Makefile | 148 | 构建/测试/部署自动化 |
| ci.yml | 154 | GitHub Actions 矩阵测试 |

### B. 当前架构缺口

1. **core/** DI 容器已实现 — ApplicationContext + Container + Environment + EventBus + Lifecycle + BeanPostProcessor + FactoryBean + ServiceLocator + AutoConfiguration 均已就绪
2. **http client** — 依赖 V `net.http`；TLS 校验开关 / 代理配置尚未生效（V 侧无对应字段）
3. **orm 迁移** — SQL 路径需要外部注入 `exec_fn`/`query_fn`（photon/orm 无法 import V 的 db 驱动）
4. **云存储** — 仓库内只有 `LocalAdapter`；S3 等由用户在 `Storage` 接口上自行实现
5. **Encrypter（XOR）** 已标 `@[deprecated]`，迁移到 `security.AesCipher`（AES-256-CBC + HMAC）
6. **web filter 链** 未完全集成到 server.v 中

### C. 为 AI Agent 准备的快速启动提示词

```
你正在参与 Photon 框架（V 语言企业级框架）的开发。
参照 /ARCHITECTURE.md 了解完整架构。
核心原则：编译期优于运行期，零反射。
当前版本 0.1.0 (Beta)，V 语言 weekly.2025.06。
所有模块在 photon/ 目录下，入口 photon.v。
注意 V 0.5.1 同名模块限制（orm 模块不能 import vlib/orm）。
```

---

*本文档由 AtomCode 自动生成，基于对 125 个源文件的深度扫描。*
