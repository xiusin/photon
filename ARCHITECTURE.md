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
│   ├── response_entity.v # ResponseEntity[T] 链式构建器（见 8.13）
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
| pool | 无 | 纯标准库；DbPool 用 driver_label 字符串，不依赖 orm |
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
| web | 58 | V built-in test + TestResponse 助手（含 ResponseEntity 首次覆盖、Session 读写可见范围、错误响应状态行）|
| orm | 33 | V built-in test |
| core | 31 | V built-in test（含 ServiceLocator 首次覆盖） |
| security | 17 | V built-in test |
| cache | 17 | V built-in test |
| queue | 9 | V built-in test |
| strutil | 9 | V built-in test（含下游安装布局的端到端编译）|
| pageable | 2 | V built-in test |
| config | 6 | V built-in test |
| locking | 6 | V built-in test |
| ticker | 6 | V built-in test |
| logger | 5 | V built-in test |
| pool | 7 | V built-in test（含 DbPool、零 orm 依赖校验、PooledGuard 契约） |
| storage | 5 | V built-in test |
| http | 4 | V built-in test |
| async | 4 | V built-in test |
| metrics | 3 | V built-in test |
| mailer | 3 | V built-in test |
| apidoc / health / photon_i18n / retry / tracing | 2 各 | V built-in test |
| cli | 6 | V built-in test（含对生成产物的真实编译） |
| core/tests | 2 | V built-in test（黑盒集成） |
| **合计** | **243** | |

> 口径：表格含 `core/tests/` 的 2 个黑盒用例。`scripts/run-tests.sh` 的
> `ALL_MODULES` 不扫子目录，逐文件跑的是 241 个；`core/tests` 由
> `make test-core-tests` 单独跑。

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

`run-tests.sh` 会**自动**给 VFLAGS 追加
`-path @vlib|@vmodules|<photon 查找根>`（见 8.11），让框架源码里的
`import photon.<x>` 在任意检出目录名下都能解析。调用方自带的 `VFLAGS` 里
若已有 `-path`，脚本不再重复注入。

另外，两个「运行时内部再起 V 编译」的端到端用例
（`cli/make_stub_compiles_test.v`、`strutil/downstream_import_test.v`）有单独
的运行预算 `PHOTON_E2E_TEST_TIMEOUT`（默认 120s），其余文件保持 30s。
理由：30s 是拿来抓死锁的，而这两条慢在真实编译（实测 ~27s / ~52s），
放宽全局会让真死锁两分钟后才被报出来。

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

### 8.10 模块命名：support 不许复活，撞 vlib 名的模块必须全限定

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

- `support/` 目录一旦复活就红，报错信息直接写清它为什么会打断下游构建
- 公开模块名单逐个断言存在，防止误改名
- **与 vlib 重名的模块（`cli` / `orm` / `pool`）不许出现裸 `import <dir>`**，
  框架源码一律写 `import photon.<dir>`
- **`run-tests.sh` 不许丢掉 photon 查找根**（见 8.11）

这里有一条禁令被这一轮反转了：上一版禁止任何 `import photon.<dir>`，理由是
「双重身份」。复核后发现那只在**不带 -path 的仓库内视角**下成立；统一全限定名
并给测试脚本注入查找根后，两张模块表不再打架。详见 8.11。

变异验证：造 `support/` 目录 → 红；把某个 `import photon.pool` 退回裸
`import pool` → 红；把 `run-tests.sh` 的 `-path` 删掉 → 红；清理后 → 绿。

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

### 8.11 两种编译视角：仓库内 vs 下游安装

这是 Photon 里最容易自欺的一处盲区，也是好几轮 bug 的共同土壤。

**仓库内**（`v test web/`、`sh scripts/run-tests.sh`）编译时，V 的模块查找把
「导入方所在项目」排在前面，于是裸 `import pool` 解析到本仓库的 `pool/`。
**下游**（用户工程里写 `import photon.web`）时，查找根是用户的工程目录，
同样那行落到 **vlib/pool**（里面只有 `ConnectionPool`，没有 `Pool` /
`PoolStats`）：

```
unknown type `pool.PoolStats`
unknown type `pool.Pool`
```

`pool/db_pool.v` 的裸 `import orm` 同理，落到 vlib/orm（没有 `DriverType`）。
用户什么都没改，却在自己的构建里收到一堆没碰过的文件里的错。

#### 上一轮说「修不动」，这一轮修掉了

`130e35b` 在这里钉了三条「已知编不过」的断言，理由是这张表：

| 写法 | 仓库内 | 下游 |
|---|---|---|
| 裸名 `import pool` | ✅ | ❌ |
| `import photon.pool` | ❌ | ✅ |

**第二行是错的。** 「仓库内红」只是因为 `run-tests.sh` 不带 `-path`：V 按
`<查找根>/<module_path>` 拼 `import photon.pool`，而工作区叫 `/workspace`
不叫 `photon`，于是找不到。给编译命令一个把仓库挂成 `photon` 的查找根，
`import photon.pool` 在仓库内也能解析。

这个机制其实**早就在仓库里**：`cli/make_stub_compiles_test.v` 的
`stub_photon_module_root()` 为了让生成器产物里的 `import photon.cli` 能编，
做的就是同一件事。上一轮只在「改 import 写法」和「不加 -path」两个选项里
选，没把已有机制接到 import 修正上。

#### 这一轮的处置

1. **`pool/` 去掉 orm 依赖。** `DbPool` 对 orm 的全部使用只是给池起个名字，
   连 `orm.Connection` 都不碰。改成持有 `driver_label string`，`pool/`
   只剩标准库 import。顺带发现它从没被测试过、TUTORIAL 里那段示例也编不过
   （少传 factory、`.sqlite` 无枚举上下文），已补 `pool/db_pool_test.v` 并修对示例。
2. **框架源码统一全限定名。** `web/request_pool.v`、`web/request_pool_test.v`、
   `photon.v` 里所有裸 `import cli/orm/pool` 改成 `import photon.<dir>`。
   全部统一、不留半个 —— 混用才会让同一目录注册两张模块表。
3. **所有编译入口共用一份查找根。** `scripts/photon-lookup.sh` 在目录名恰为
   `photon` 时用父目录，否则在仓库内临时目录放一个叫 `photon` 的符号链接，
   `run-tests.sh`、`ci-test.sh`、`Makefile` 都把它的输出拼进
   `-path @vlib|@vmodules|<lookup>`。用链接在这里是安全的：要的只是
   「仓库内解析到本仓库」，不是模拟下游安装布局。
   收敛到一份脚本是刻意的：第一次只改了 `run-tests.sh`，`example/` 的
   dev/-prod 构建立刻报 `cannot import module "photon.pool"` —— 半套修复
   比不修更糟。`strutil/module_identity_test.v` 会检查这个共享脚本还在。
4. **顺手修掉 `import photon`（聚合入口）。** `photon.v` 里有一行
   `pub type Repository = orm.Repository`，而 `orm.Repository[T]` 是泛型
   struct，V 0.5.2 明确报 `generic type aliases are not yet implemented`。
   这行从没编过 —— 只有 `import photon` 时才会编译它。已删并注明原因。

现在五个下游入口（含聚合入口）在真实拷贝布局下都能编：
`photon.pool` / `photon.web` / `photon.orm` / `photon.cli` / `photon`。

**过程中撞到一次真的双重身份，值得记下来。** 只改框架源码时，`example/`
主应用能编，`example/verify` 却报 `unknown type photon.pool.Pool`。差别是
`verify_infra.v` 里有一行裸 `import pool` —— **混用裸名与全限定名**让同一
目录注册了两张模块表。把 `example/` 与 `example/verify` 里剩下的
`import orm` / `import cli` / `import pool` 全部统一后，dev / `-prod` / verify
才一起绿。所以 `module_identity_test.v` 现在扫的是**整个仓库**（含 example），
不再只扫框架源码：`example/` 是仓库内应用，但混用一样会炸。

#### 防回归：`strutil/downstream_import_test.v`

三条「known_to_fail」升级成正向断言：

- 五个公开入口共用一份下游拷贝（一次 `cp -a`，不是符号链接），逐个要求编得过。
  `photon.web` 与 `photon` 合编一次 —— 两者都要编整棵 web 依赖树，分开编会把
  用例推过 30s 运行预算，那会被误报成「用例挂死」。
- `test_repo_side_import_still_works` 带同样的查找根，守仓库内视角。
- `locking/redis_lock_client.v` 用到的 vendored `xiusin.vredis` 会在下游
  查找根上补齐，否则缺 vendor 会让 `import photon.web` 假红。

**为什么必须用拷贝**：用符号链接时 `<lookup>/photon/web/x.v` 的 real path
仍是 `/workspace/web/x.v`，V 顺着 `/workspace` 往上找，会看见本仓库的
`pool/` / `orm/` —— 缺陷被链接本身掩盖。同一份代码，链接进来绿、`cp -a`
拷进去红。**「我的复现是绿的」有时候只说明复现方式不对。**

变异验证：把 `request_pool.v` 退回裸 `import pool` → 14 个 `unknown type
pool.*`；给 `pool/` 加回 `import orm` → 下游编不过（并触发 V 检查器卡死）；
删掉 `run-tests.sh` 的 `-path` → 结构断言红、仓库内 `photon.pool` 编不过。

#### 一句修正

上一轮这里写的是「**一个不够彻底的模拟，比不模拟更危险**」。这一轮要补的是：
比不模拟更危险的，还有**把一个可改变的前提当成物理约束**。

「仓库内一律编不过 `photon.pool`」这句话，成立条件只是「编译命令不带 -path」
和「检出目录恰好不叫 photon」。两者都不是 V 的限制，是脚本自己的选择。
而同一个仓库里另一个测试文件早就解决了它 —— 结论被写成「修不动」，
是因为没去问「有没有别处已经做过」。

### 8.12 ServiceLocator 的沉默区，以及「下一轮该摸哪里」也要验证

用静态扫描找「定义了、但整个仓库零引用的 `pub fn`」，撞到
`core/service_locator.v`：三个模块级便利函数、`new_service_locator`、
`ServiceLocator` 的四个实例方法，在 `core/context_test.v` 的 200+ 条用例里
**一条都没被调用过**（那个文件头写着 ServiceLocator，测的是 ApplicationContext
和 BindingRegistry）。逐个拿真实编译器调一遍，`ApplicationContext{}` 零值构造
一进去就段错误。

根因是签名把它引导成了误用：

```v
// 原来：按值收
pub fn has_service_from(mut ctx ApplicationContext, name string) bool
```

收值很自然让调用方写 `ApplicationContext{}` 传进去；而 `ApplicationContext`
的 `container` / `event_bus` / `environment` 都是 `&X = unsafe { nil }`，
`ctx.has()` 直接解引用 nil。另外按值会把两把 `sync.RwMutex`、`resolve_cache`、
`is_frozen` 全复制一份，副本上的锁和缓存与原对象脱节。

改成 `mut ctx &ApplicationContext`（与 `new_application_context() &ApplicationContext`
对齐）后，零值构造在编译期就传不进来。`core/service_locator_test.v` 第一次
覆盖整套 API，并用一条结构断言锁住签名：改回按值，断言立刻红；去掉
`ServiceLocator` 的 nil 保护，`test_service_locator_without_context_is_safe`
会段错误。两轮变异都验证过。

**同一轮里另一件被推翻的事。** 上一轮（#18）结尾建议「给 `photon.v` 里其余
re-export 加一条逐个实例化的编译探针，它们是和泛型 `Repository` 同一批从没
被编译过的声明」。实测结论：

- V 0.5.2 的 `import photon` 会**立即**解析所有 `pub type X = y.X` 别名。
  指向不存在的类型、或泛型 struct 不带类型参数，都在 import 时就报错 ——
  `strutil/downstream_import_test.v` 里 `['photon.web', 'photon']` 那组已经能抓。
- 把 116 个 re-export 逐个实例化（struct `{}` / enum `X(0)` / interface 与 map
  别名走签名引用）、再逐个调方法，全部能编能跑。

所以**没有**加那条探针：它相对现有入口断言是恒过的，而恒过的用例比没有用例
更坏。上一轮那句「同一批从没被编译过」是把一个坏声明的性状顺手外推到一整片，
没验证过。这也说明「下一轮该摸哪里」这个建议本身，同样可能是一条未经实测的
外推 —— 和前面几轮修的「看起来已经做了」是同一种沉默，只是发生在计划里。

顺手删掉 `photon.v` 里三个从未被活跃引用的 import（`strutil` / `http` /
`photon.pool`，只出现在注释掉的占位 re-export 里）。它们让每个下游
`import photon` 都多收三条 unused-import warning。

### 8.13 ResponseEntity：一个泛型 struct 怎么让整条链式 API 一起消失

`web/response_entity.v` 是 Spring `ResponseEntity<T>` 的对等物：7 个状态码工厂
（`ok_entity` / `created_entity` / `accepted_entity` / `no_content_entity` /
`bad_request_entity` / `not_found_entity` / `server_error_entity`）+ 5 个链式
构建器（`header` / `content_type` / `location` / `etag` / `set_status`）
+ 2 个转换（`to_result` / `to_json_result`）。

**它整块编译不过，而且从没有任何调用方。** 全仓库对它的引用只有 `photon.v`
里那行 `pub type ResponseEntity = web.ResponseEntity` —— 而 re-export 类型名的
存在不会实例化泛型。所以它没被编译过，也就不可能在任何一轮「全量全绿」里出声。

触发条件很反直觉：**哪怕只调一个工厂函数，5 个链式方法也一起报错。**

```v
e := web.ok_entity[string]('hi')
// web/response_entity.v:132:5: error: field `headers` of struct
//   `&web.ResponseEntity[string]` is immutable
```

V 在实例化泛型 struct 时会连同**全部**方法体做检查，所以「有一条方法写错」
等于「这个类型不可用」，而不是「这条方法不可用」。

两个根因，都是 V 语义而不是笔误：

1. **`pub:` 字段只读。** 构建器写 `re.headers[k] = v`，只在 `pub mut:` 下合法。
2. **工厂返回的是值，而构建器是 `mut` 接收者。** 于是文件头文档承诺的
   `web.created[User](user).header(...)` 在 V 里不成立 —— 编译器直接拒绝
   「把表达式当 `mut` 传」（`cannot pass expression as 'mut'`）。

修法是让形状和用法对上，而不是在调用侧写 `mut e := ...` 绕过去：

```v
@[heap]                              // 工厂要返回 &T，V 不许指针逃出栈
pub struct ResponseEntity[T] {
pub mut:
	status  int = 200
	headers map[string]string        // 链式方法原地改这两个
pub:
	body     T
	has_body bool = true
}

pub fn ok_entity[T](body T) &ResponseEntity[T]            // 返回指针
pub fn (re &ResponseEntity[T]) header(...) &ResponseEntity[T] {
	unsafe {
		mut r := re
		r.headers[key] = value
	}
	return re
}
```

`&ResponseEntity[T]` 接收者 + `unsafe { mut r := re }` 是 V 里「不可变左值也能
原地改并返回 self」的标准写法。这样 `ok_entity[string]('x').header('K','v')`
直接成立，与 Spring / Laravel 的 fluent 体感一致，调用方不需要 `mut` 变量。

`web/response_entity_test.v` 用两层断言钉住这件事：

- **行为层**：状态码、`has_body`、链式合流、`to_result` 写回 `ctx.res.status_code`、
  两个实体不共享 headers。
- **结构层**：直接读源码断言「工厂返回 `&ResponseEntity[T]`」「链式方法以
  `&ResponseEntity[T]` 为接收者」「struct 有 `pub mut:` 段」。

结构层不是洁癖：行为用例可以用 `mut e := ...` 绕开，绕开之后把签名改回按值
`mut` 接收者，行为断言照样全绿 —— 缺陷会悄悄回来。三轮变异都验证过：

```
链式接收者改回 (mut re ResponseEntity[T])   → 编译期红（cannot pass expression as mut）
ok_entity 改回返回值类型                    → 结构断言红，报出违规那一行
struct 改回纯 pub:                          → 编译期红（field `headers` is immutable）
```

顺带修掉文件头那段「示例」：它写的是 `web.response_entity[User]{...}` /
`web.created[User](user)` / `web.not_found[string]()`，三个名字**从未存在**过
（真实名是 `ok_entity` / `created_entity` / `not_found_entity`）。文档里的示例
现在逐个实跑过，四个片段都能编能跑。

这一条和第 8.12 是同一个形状，但更彻底一步：ServiceLocator 至少还有签名，
可以被静态扫描看见；ResponseEntity 连「被谁用」都没有 —— 它的验收标准是
「文件存在，且长得像 Spring」。**泛型类型的沉默比普通函数更彻底：它连
「零引用」都表现为一种正常状态，因为没人实例化它。**

### 8.14 PooledGuard：一条挂在「推荐用法」上的数据串号

`pool/guard.v` 的 `PooledGuard[T]` 不是泛型沉默区 —— 它在 `example/verify`
里被调用过，`web/request_pool.v` 也天天用它。这轮它出现在这里，是因为
**被调用过的地方只走了三条直线路径**，而 `release()` 里有两个分支从头到尾
没人踩进去：

1. **`reset_on_release`**（归还前清数据）
2. **临时 guard**（创建对象时池已耗尽，guard 里没有 pool）

#### 第一条：推荐用法和「会清数据」的用法，是两条不同的路

`web/request_pool.v` 文件头写的用法是：

```v
mut guard := rp.acquire[Session]('session')!
defer { guard.release() }
sess := guard.get()
sess.set('user_id', '42')
```

而 `reset_fn` 当时只挂在 `rp.release(name, obj)` 上。于是：

| 归还路径 | 是否调 reset | 后果 |
|---|---|---|
| `rp.release(name, obj)` | 是 | 正确 |
| `guard.release()`（文档推荐、`defer` 的标准写法） | **否** | 上一个请求的 `user_id` 被下一个请求读到 |

这不是「算错了」，是**对象确实归还了、计数确实对、`is_released()` 确实是 true**，
所有可观测信号都正常，只有池化对象里的数据没清。`web/request_pool_test.v`
原有的 `with_acquired` 用例断言的是「回调执行了」，也没碰这件事。

修法是把 reset 挂到**归还的那条路径本身**，而不是挂在调用方要记得走的另一条
路径上：

```v
pub struct PooledGuard[T] {
pub mut:
	obj              voidptr
	released         bool
	is_temporary     bool
	reset_on_release fn (voidptr) = unsafe { nil }   // 归还前跑一次
}
```

`release()` 里 reset 在锁外执行：`reset_fn` 会碰对象，`Pool.release()` 会拿池的
互斥锁，任一在 `g.mu` 下面做都会引入守卫与池的锁序反转。

#### 第二条：临时 guard 的 `release()` 是个静默 no-op

池耗尽时 `acquire` 会造一个回退对象，并返回 `new_pooled_guard(nil, obj)`。
而 `release()` 的第一行是：

```v
if g.released || isnil(g.pool) || isnil(g.obj) {
	return          // ← 连 released 都没置位
}
```

`isnil(g.pool)` 在条件里，等于「临时对象永远不算被释放」。调用方按 RAII 契约写
`assert guard.is_released()` 永远拿不到 true，也没法区分「还在手上」和「已经没了」；
对它调用 `release()` 既不归还也不销毁，对象就这么漏了。

`web/request_pool_test.v` 里原有的临时对象用例只断言 `isnil(guard.get())` 不崩，
所以这条一直绿。

修法是把「回退对象」建成一个显式的形状，而不是用「nil pool」隐式表达：

```v
pub fn new_temporary_guard[T](obj voidptr) PooledGuard[T]   // is_temporary: true
```

`release()` 现在把 `isnil(g.obj)` 作为唯一短路条件，`temporary || isnil(pool)` 时
`free` 掉对象再返回 —— 回退对象能做的事只有一件（被销毁），现在它真的做了。
`web.RequestPool.with_acquired` 的池耗尽分支同样补上了 reset 与 `free`
（那条路径直接建对象、调回调、丢掉，既不进池也不再经过任何 release 钩子）。

#### 用例与变异

`pool/guard_test.v` 12 条（首次覆盖整个守卫 API）+ `web/request_pool_test.v`
新增 5 条。六轮变异，每轮都让对应用例变红、恢复后绿：

```
release() 条件加回 isnil(g.pool)         → 临时守卫三连红
acquire 不再给守卫挂 reset_on_release     → 复用对象残留 42
release() 不调 reset_on_release           → 上面 + 池守卫的 reset 用例
回退对象不 free（release 静默 no-op）      → 段错误 / is_released 断言红
get() 去掉 g.released 判断                → 需要把 g.obj 填回去才抓得住（见下）
with_acquired 临时分支去掉 reset           → mark.n == 1（应为 0）
```

第二、五两条各值得说一句：

- **`acquire` 那条变异，行为用例本来就该红。** 它一直绿，是因为没人写过
  「第二个请求能不能读到第一个请求的数据」这一句。
- **`get()` 那条第一版没红。** 因为 `release()` 顺手把 `g.obj` 清空了，只查
  `isnil(g.obj)` 的实现看起来也对。用例得手动把 `g.obj` 填回去才能证明
  `released` 是独立条件 —— 否则测的是「obj 被清空了」，不是「released 被检查了」。

这一条的形状和前几轮不同：前几轮沉默的是「没人调的代码」「没人看的输出」
「看起来太可信的表格」。这次的代码天天被调用，**沉默的是它的第二条路径** ——
被推荐的那条。`.release()` 在几乎每个示例里都写对了，只是没有一个示例写过
`defer { guard.release() }` 之后再去读一次对象。

### 8.15 RequestPool：一个「关闭」被两个地方各记一半

上一轮结尾留的方向是「`RequestPool` 的 `pool_stats()` 和 `stats` 字段谁在写」，标明是推测。
验完的结论分两半：

**`pool_stats()` 是健康的。** 它就是遍历 `entries` 逐个问 `Pool.stats()`，读数和
直接调 `pool.Pool.stats()` 完全一致。这条推测错了。

**`stats` 字段是真的死了。** `pub mut: stats map[string]pool.PoolStats` 从构造起
置空，全仓库没有任何写入方，也没有任何读取方。麻烦的不只是「多一个没用的字段」——
它出现在公开 struct 上，读者会以为 `pool_stats()` 只是把 `stats` 抄出来一份。
两个名字讲同一件事，其中一个永远为空。

### 真正踩到的是 `close_all()`

它只调了内部 `Pool.close()`，**没有把池从 `entries` / `pools` 里摘掉**。于是之后的
每一次 `acquire()` 都是这个流程：

```
entries 里还能查到 entry            → 拿到一个句柄
问这个已关闭的 Pool                 → error: pool "x" is closed
这个 error 落进 `or` 块             → 被当成「耗尽」处理
降级成临时对象                       → 返回给调用方
```

调用方拿到一个完全可用的对象，**一个错误都收不到**。池早就关了，而没有任何人能察觉。
`pool_stats()` 也照样报告这个已经关掉的池（`total=0 active=0`，看起来非常「健康」）。

修法是把「关闭」做成一件只有一个地方记住的事：`close_all()` 在同一把写锁里先
`entries.clear()` + `pools.clear()`，出锁之后再去关内部池。这样「已关闭」不是某个
布尔标志的两份拷贝，而是「注册表里没有」这一个可查的事实。之后 `acquire` /
`acquire_raw` / `with_acquired` 都报 `not found or already closed`。

一个必须保留的能力：**已经在用的对象仍要能在 `close_all()` 之后 `release()`**，
否则关闭就等于把持有者手里的对象拿走。这条单独有断言。

### 用例与变异

`web/request_pool_test.v` 新增 8 条（`acquire_raw` 耗尽语义 1 条 + 关闭语义 7 条）。
四轮变异：

```
close_all 不摘除 entries/pools        → pools.len 断言红（2 != 0）
is_closed() 恒返回 false              → 「close() 之后必须为 true」红
把 stats 字段加回 struct              → 源码结构断言红
acquire_raw 耗尽时改走错误通道        → 耗尽返回 nil 的断言红
```

第三条是源码结构断言（读 `web/request_pool.v` 找 `\tstats map[string]pool.PoolStats`）。
行为用例绕不过「字段存在但永远为空」这件事，只能读源码。

### 一个写进注释就被删掉的分支

第一版在 `acquire` / `acquire_raw` / `with_acquired` 里都加了 `if pg.is_closed()`
提前报错。变异验证时不红——**因为关闭的池已经从 `entries` 摘除了，那条分支根本
不可达**。三处都是死代码，已全部删掉，只留注释说明「为什么这里不需要」。

`Pool.is_closed()` 本身保留：它对 `pool` 模块是公开 API，且 `acquire()` 在并发下
「读到 entry 之后、问到 Pool 之前」池被关掉时仍是唯一的判断依据。这条单独有断言。

### 顺手修的文档

`docs/pages/pool.html` 第 6 节的 RequestPool 示例**原样抄下来编不过**，三处：

```
rp := new_request_pool(...)                  → 必须 mut（register_pool/acquire 改状态）
register_pool[Session](...)                  → Session 不 import，是 web.Session
sess := guard.get(); sess.set(...)           → set() 要 mut 接收者
fn (sess &Session) ! { ... }                 → with_acquired 要 mut &T
```

改成实跑通过的版本，并按同样的方式抽出来真编真跑过一遍。

**这一轮的形状和前面几轮不一样。** 前几轮沉默的是「没人调的代码」「没人看的输出」
「看起来太可信的表格」「验收标准是它自己说成功了」。这次的两件事都还在正常返回值里：

`close_all()` 的 bug 里，每个函数的返回值都是对的。`acquire` 返回了对象，
`pool_stats` 返回了统计，`close_all` 没有 panic。坏掉的是一件**没有任何返回值在表达
的事**：这个对象还在池体系里吗。它靠 `entries` 和内部 `Pool.closed` 两个地方各记一半，
而这两半在 `close_all()` 之后立刻不一致——`Pool` 说「我关了」，`entries` 说「我还在」。

**两处各记一半的状态，不会报错，只会漂。** 它不会让某一个返回值变成错的，只会让
「所有返回值都对」和「系统是对的」之间出现一个缝隙。而没有人写断言去检查那个缝隙，
因为缝隙里没有返回值可断。

下一个值得摸的（只是推测，没验）：`RequestPool` 的 `session` 池和 `web/session.v` 的
实际 session 生命周期到底有没有接上？现在 `reset_session`、`reset_middleware_context`、
`reset_input` 三个预置函数都测过了，但「谁在请求结束的时候真的调到了它们」这条链路
还没有一条端到端用例。

### 8.16 预置 reset 函数：清了不该清的东西，一次没清干净

上一轮那条推测「三个预置 reset 只有单元用例、没有端到端链路」被这轮验成了真的，
而且顺着那条链路找到了两个缺陷 —— 方向相反，同一个原因：**这三个函数从来没被
问过「到底该清什么」。**

#### 一、`reset_session()` 把 `old_flash` 清掉了

链路补上之后故障立刻可复现：一次登录请求里 `flash('notice', '登录成功')`，会话回池，
下一个请求 `get_flash('notice')` 拿到 `flash key not found`。

`old_flash` 不是「上一个请求留下的垃圾」，它是**当前请求的闪存收件箱**：

```
save()   → flash_data 落盘 → 搬进 old_flash → 清空 flash_data
get_flash() → 读 old_flash
```

而会话被 release 的时候，响应还没生成 —— 模板是在之后才渲染的。所以在这里清掉
`old_flash`，等于在提示被读到之前把它擦掉。原有的单测断言的正是
`old_flash.len == 0`，**方向反了**，一直在替这个缺陷背书。

留存它也不会跨请求泄漏：`start()` 会覆盖它；纯池化用法从 `new_session()` 拿到的
本来就是空 map。真正的请求级状态（`data`）仍然照清。

#### 二、`reset_middleware_context()` 只清了 `data`

`route_path` / `route_method` 由 `dispatch_with_chain` 填，`logger` 由请求日志中间件
填，全是「本次请求」的属性。它们没被清，于是下一个复用这个对象的请求一开始就
以为自己已经被路由到 `/admin/secret`、握着写向别人上下文的 logger。而
`MiddlewareContext.reset()`（after_completion 走的那条路）有一模一样的盲区 ——
两条清理路径都只看着 `data`。

两处一起补齐，`route_path` / `route_method` / `logger` / `ctx` 全部归零。

#### 三、用例与变异

`web/request_pool_test.v` 新增 4 条：

- `test_reset_session_keeps_old_flash`（并把原来反向的那条改对）
- `test_reset_middleware_context_clears_route_and_logger`
- `test_mctx_reset_clears_route_and_logger`
- `test_session_flash_survives_acquire_release_roundtrip` —— 端到端：`acquire` →
  `flash` → 模拟 `save()` → `release()` → 再 `acquire`，走的是真实的
  `guard.reset_on_release`，不是手调 reset 函数

三轮变异，各自让对应断言变红、恢复后绿：

```
reset_session 又清 old_flash                              → 收件箱用例 + 端到端用例双红
reset_middleware_context 不清 route_path/route_method      → assert mctx.route_path == ''
MiddlewareContext.reset 不清 route_path/route_method       → assert mctx.route_path == ''
```

`example/verify` 247/247，全量 239 个测试文件全绿。

#### 四、这轮的形状

前几轮说过几种沉默：没人调的代码、没人看的输出、看起来太可信的表格、验收标准是
它自己说成功了、以及「两处各记一半的状态只会漂」。

这轮是另一种：**用例本身把错误的行为钉成了事实。** `assert sess.old_flash.len == 0`
不是漏写，是写得很认真的一条断言 —— 它只是把「清得越干净越好」这个直觉当成了规格。
和它配对的是「只测了函数本身，没测谁在什么时候调它」。两者一合力，缺陷就有了
一份绿色的证书。

**清理类函数的规格不是「清得干净」，而是「清对边界」：带走这个请求带进来的东西，
留下这个请求还没用完的东西。**

### 8.17 Session 的读写可见范围：一个删不掉的键

上一轮结尾标了「推测，没验」的方向是 `reset_input()` 有没有像 `reset_middleware_context()`
那样的字段盲区。**验完是推翻了**：`Input` 从头到尾只有一个字段 `ctx &veb.Context`，
没有「一批解析出来的绑定值」。`reset_input()` 清那一个引用就已经清完了全部。

但上一轮那条推论的形状是对的，只是在**同一层**的另一个 struct 上：`Session`。

#### 一、缺陷：两处各记一半，这次是「读得到、删不掉」

`Session` 有两张 map：`data`（普通负载）和 `old_flash`（本请求的闪存收件箱）。
读写对它们的看法不一致：

```
get()     → data，回落 old_flash
has()     → data || old_flash
delete()  → 只删 data          ← 漏
clear()   → 只清 data          ← 漏
all()     → 只返回 data        ← 漏
```

于是 `delete()` / `clear()` 对「读得到的键」是无效的。实测（改之前）：

```
clear 后 get(user_id) = <none>
clear 后 get(notice)  = 已保存   <- 应为 <none>
clear 后 has(notice)  = true     <- 应为 false
delete 后 has(notice) = true     <- 应为 false
all() 含 old_flash?  {}          <- get() 取得到，all() 里没有
```

这不是理论问题。`old_flash` 的语义（「下一次请求读一次就消失」）意味着用户唯一
的手段是「读一次」，而框架从来不提供「我不想读、把它丢掉」的路径 —— 两条写入
API 都对它无效。

它和 8.16 里 `reset_session()` 清掉 `old_flash` 是**镜像缺陷**：那一处清得太多
（在提示被读到之前擦掉），这一处清得太少（提示读完之后再也删不掉）。两处都是
在「`old_flash` 该不该动」上判断失误，只是结论相反。

#### 二、修法：一条规则，不是三个补丁

**读取方观察到的范围，就是写入方的作用范围。**

- `delete()` 从 `data` 和 `old_flash` 两处删
- `clear()` 清 `data` + `old_flash` + `flash_data`（待落盘的也是会话数据）
- `all()` 合并两张 map，同名键以 `data` 为准（与 `get()` 的回落顺序一致）

#### 三、为什么这是一条结构断言

行为用例覆盖不了「将来有人又给 `Session` 加第三张 map」。所以
`web/session_visibility_test.v` 的最后一条直接读 `web/session.v` 源码，
要求 `get` / `has` / `delete` / `clear` / `all` 五个函数体里都出现 `old_flash`：

```v
assert body.contains('old_flash'),
    '${fname}() 没有涉及 old_flash —— 读取方与写入方的可见范围又开始分叉了'
```

#### 四、用例与变异

`web/session_visibility_test.v` 7 条。三轮变异，每轮都让对应用例变红、恢复后绿：

```
delete() 不删 old_flash          → 行为断言红 + 结构断言红（报「delete() 没有涉及 old_flash」）
clear() 不清 old_flash/flash_data → 3 条红（可见性 + 待落盘闪存 + 结构）
all() 只返回 data                → 2 条红（all 与 get 不自洽 + 结构）
```

#### 五、这轮的形状

前几轮说过几种沉默：没人调的代码、没人看的输出、看起来太可信的表格、验收标准是
它自己说成功了、两处各记一半的状态只会漂、用例把错误行为钉成事实。

这轮的是里面最朴素的一种，也最容易被当成「不是 bug」：

**没有人给「删除」写过一条「删完之后还读得到吗」的用例。**

`test_session_delete` 只断言了 `!sess.has('key')` —— 而那个 `key` 是 `set()` 写进
`data` 的。同一族里另一条 `test_session_clear` 也只断言 `data.len == 0`。
两条用例都写得很认真，覆盖的是**它们自己造出来的那种键**。缺陷藏在另一种键上：
不是 `set()` 写的，是上一个请求 `flash()` 写、`save()` 搬过来的。

**同一族 API 的用例，往往只覆盖了取值路径最短的那个键。** `delete('key')` 绿不说明
`delete()` 对，只说明它对 `set()` 写的键是对的。

### 8.18 错误响应的状态行：正文说拒绝，状态行说成功

上一轮结尾标了「推测，没验」的方向是 `SessionManager.save()` 里 `is_new` 的赋值顺序。
**验完是推翻了**：`sess.is_new = false` 之后读 `is_new` 确实恒为 false，看起来那条
`if is_new || ...` 是死的 —— 但同一个条件里还有 `current_id != cookie_id && !already_sent`，
新会话的 `current_id != cookie_id` 恰好兜住了它。实测两个新会话（含同一响应里连存两次）
Cookie 都只发一次、且值正确。这条不是缺陷。

真正的东西是在**端到端跑一次 example 服务**时撞到的：`curl -i` 打出来的状态行。

#### 一、缺陷：`json_error(code, msg)` 把 `code` 扔了

```
$ curl -i http://127.0.0.1:8080/api/v1/users          # 不带 token，应 403
HTTP/1.1 200 OK
{"code":"403","message":"Authorization header required"}
```

鉴权是生效的（`apply_role` 真的执行了，正文也真的写着 403）。错的是**状态行**。

根因在 veb 的语义里：`ctx.json[T]()` 只负责编码正文，不碰 `ctx.res.status_code`；
而 `send_response_to_client` 只在 `status_code == 0` 时才补一个 `.ok`。于是

```v
ctx.json({'code': '403', 'message': '...'})   // 状态行 = 200
```

是最省事的写法，也是错得最隐蔽的写法。框架原有的 `web.error_json()` 只返回字符串，
没有任何函数能把它连着状态码一起发出去 —— 所以 example 里每个 `json_error` 都在
「正文带错误码、状态码 200」上。

影响面：**所有只读正文、不读状态行的都正常，所有只读状态行的都错**。浏览器端 JS 按
业务 code 分支时一切正常，所以它活得很好；而网关的 4xx 计数、CDN 的缓存判定、客户端
重试策略、K8s 探针、APM 错误率面板读的全是状态行，会一致地把拒绝当成成功。

#### 二、修法：状态码和正文由同一个参数决定

`web/exception.v` 新增三个函数：

```v
web.json_status(mut ctx, 403, payload)                 // 任意 payload + 显式状态码
web.error_result(mut ctx, 403, 'permission denied')    // 标准错误信封 + 同一状态码
web.error_result_with_details(mut ctx, 422, msg, map)  // 同上带 details
```

顺序是**先 `set_status` 再发送** —— `send_response_to_client` 只在状态为 0 时补 `.ok`，
先设好就不会被覆盖。`error_result` 的状态行和正文 `code` 是同一个入参，两者不可能漂。

顺带一条：整数状态码不直接 `http.Status(code)` 强转。那是不校验的枚举转换，`499`、`700`
这类未分配的码会得到一个「有值但无意义」的状态行 —— 比不发更糟。改走
`http.status_from_int()`，`unassigned` 退到 500（那种响应一定是服务端没按预期处理）。

#### 三、用例与变异

`web/error_status_test.v` 9 条。只断言正文里 `code == 403` 的用例在缺陷存在时**照样
全绿**，所以断言全部落在 `ctx.res.status_code` 上。三轮变异：

```
json_status 去掉 set_status                    → 3 条红（状态行 200 vs 403/500）+ 结构断言 panic
error_result 去掉 set_status                   → 401/400/500 全部红，报「状态行是 200」
http_status 退回 unsafe { http.Status(code) }  → 499 原样漏出去，断言红
```

最后一条值得记：变异时 `http.Status(code)` 在 V 里必须包 `unsafe`，第一版变异脚本没加，
报的是编译错误而不是断言失败 —— 那会让人误以为「变异没生效」。变异本身也要能跑起来。

另有一条**结构断言**读 `web/exception.v`，要求三个入口的 `set_status` 出现在发送之前。
行为断言可以被绕开：`send_response_to_client` 把正文写进 `ctx.res.body` 时，即使状态码
是后补的，进程内读 `ctx.res.status_code` 也看不到差别（缺陷只在网络上）。所以这条必须
看源码顺序。

#### 四、顺带清掉的一处残留

PR #18 声称「全仓库统一全限定名 `photon.x`」，实际漏了 11 处：`photon.v` 里的 13 个裸
import、`web/actuator_*.v` 与 `web/mount.v` 的 `import core` / `import logger` /
`import metrics`、`core/application_context.v` 的 `import ticker`、`orm/repository.v` 的
`import pageable`、`cli/make_commands.v` 的 `import strutil`、`web/session_lock.v` 的
`import locking`。这些一行不改，`import photon.core` 和 `import core` 就会把同一个目录
装进两份模块表，报错是「`&ticker.Scheduler` 不能当 `&ticker.Scheduler`」这种看不出所以
然的话 —— 正是 §8.10 记的那个双重身份。

**这一轮的触发条件是「混用」，不是「用了全限定名」。** 同一个文件里既有裸名又有全限定
名时才会分叉；统一到任一边都是自洽的。现在 example / verify / 各模块测试文件全部改用
`photon.x`，`strutil/downstream_import_test.v` 的五个入口断言继续守这件事。

#### 五、这轮的形状

前几轮说过几种沉默：没人调的代码、没人看的输出、看起来太可信的表格、验收标准是它自己
说成功了、两处各记一半的状态只会漂、用例把错误行为钉成事实。

这轮的是第一种「**错误信号被拆成两半、各自看都正常**」：

正文里那个 `403` 是认真的，鉴权逻辑也是对的，唯一错的是网络上那个数字。而**没有任何
一条用例在看那个数字** —— `json` 是把 map 编码成字符串，用例断言的是字符串内容，状态行
从头到尾没进过断言视野。

它比前几轮的缺陷都更值得修，因为它在安全边界上：一个把所有 401/403 报成 200 的服务，
在监控面板上看起来 100% 健康。**错得不只是响应，还有对这个服务的全部观测。**

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
| web/response_entity.v | 274 | ResponseEntity[T] 链式构建器（Spring 对齐，见 8.13）|
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
| pool/db_pool.v | 96 | DbPool |
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
