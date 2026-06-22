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

---

## 2. 模块拓扑

### 2.1 完整模块列表（16 个模块，140+ 个 .v 文件）

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
│   ├── dispatcher.v      # QueueDispatcher（全局单例 + dispatch/batch/chain/later）
│   ├── worker.v          # QueueWorker（轮询执行器）
│   ├── failed_jobs.v     # FailedJob + FailedJobRepository + MemoryFailedJobRepository + FailedJobHandler
│   └── queue_test.v
│
├── locking/              # [Beta] 锁模块
│   ├── lock.v            # LockManager + LocalMutex + DistributedLock 接口 + LockGuard（RAII）
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
│   ├── s3_adapter.v      # S3Adapter（S3 兼容云存储，stub）
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
├── support/              # [Beta] 支持工具
│   ├── support.v         # 入口
│   ├── error.v           # PhotonError + ErrorCode 枚举（统一领域错误类型，实现 IError）
│   ├── arr.v             # 数组工具（dot-notation get/set/has + reverse/take/skip）
│   ├── str.v             # 字符串工具（slug/snake/camel/studly/kebab + 截断/填充）
│   ├── collection.v      # Collection[T]（Laravel 风格链式集合操作：map/filter/reduce/sort/groupBy）
│   ├── pagination.v      # LengthAwarePaginator[T] + SimplePaginator[T]
│   ├── sort.v            # Sort + SortOrder + PageRequest（Spring Data 风格）
│   └── *._test.v         # 测试文件
│
├── http/                 # [Alpha] HTTP 客户端（Spring RestTemplate 对齐）
│   ├── http.v            # 入口
│   ├── client.v          # RestTemplate（fluent API + SSLConfig/ProxyConfig + NoopInterceptor）
│   └── *._test.v         # 测试文件（含 ssl_proxy_test）
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
| **核心层** | config, support | 所有模块依赖的基础工具 |
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
  └── MemoryDriver (默认内存实现)

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
```

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
    
  S3Adapter — S3 兼容云存储（stub）
    ├── 支持 AWS S3 + MinIO + DigitalOcean Spaces + Cloudflare R2
    ├── 路径风格兼容（use_path_style）
    └── 预签名 URL 生成

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

### 3.11 Support 模块（support/）

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

```
HttpClient — Fluent API
  ├── with_base_url(url)
  ├── with_header(key, value)
  ├── with_token(token) — Bearer auth
  ├── with_basic_auth(user, pass)
  ├── with_timeout(sec)
  ├── with_retry(times, delay_ms)
  ├── get(path) → HttpResponse
  ├── post(path, body) → HttpResponse
  ├── put/patch/delete
  └── base64_encode (内置)

HttpResponse:
  ├── status_code / body / headers
  ├── is_success() / is_client_error() / is_server_error()
  └── json() / header(name)
```
> 当前为 stub 状态，需要 V `net.http` 做实际网络调用。

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

---

## 4. 模块间依赖关系

### 4.1 显式依赖图

```
        photon（统一导出）
        │
    ┌───┼───┬───────┬───────┬──────┬──────┬──────┬──────┬──────┐
    │   │   │       │       │      │      │      │      │      │
  core config log  cache  orm    web   cli   queue storage http
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

support: 零依赖，所有模块都可使用
ticker:  零依赖（纯 V channel/goroutine）
```

### 4.2 依赖说明

| 模块 | 依赖 | 说明 |
|------|------|------|
| config | 无 | 纯标准库 |
| support | 无 | 纯标准库 |
| ticker | 无 | 纯 V channel |
| cache | 无 | support 可选 |
| pool | orm (db_pool) | 仅 DbPool 依赖 orm.DriverType |
| locking | 无 | cache 可选（分布式锁后端） |
| queue | 无 | 无外部依赖 |
| storage | 无 | 标准库 os |
| http | 无 | stub 状态 |
| security | 无 | web/filter 可选集成 |
| orm | 无 | V 标准 orm 不可用（同名冲突） |
| web | 无 | veb 外部依赖 |
| cli | 无 | 标准库 os |

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
| config | 1 | V built-in test |
| web | 9 | V built-in test + TestResponse 助手 |
| orm | 8 | V built-in test |
| security | 9 | V built-in test |
| cache | 1 | V built-in test |
| queue | 1 | V built-in test |
| pool | 1 | V built-in test |
| locking | 1 | V built-in test |
| storage | 1 | V built-in test |
| ticker | 1 | V built-in test |
| support | 5 | V built-in test |
| cli | 1 | V built-in test |
| http | 1 | V built-in test |
| **合计** | **~40** | |

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

# 全部模块（通过 Makefile）
make test-all

# CI 矩阵测试（14 个模块并行）
# 参见 .github/workflows/ci.yml
```

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
| storage | Beta | 高 | 中 | 部分（s3 stub）|
| ticker | Beta | 高 | 中 | 是 |
| support | Beta | 高 | 高 | 是 |
| cli | Beta | 高 | 低 | 是 |
| http | Alpha | 低 | 低 | 否（stub）|
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
| web/server.v | 104 | web.run[T] 包装器 |
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
| storage/s3_adapter.v | 233 | S3Adapter（stub）|
| ticker/timer.v | 196 | Timer/Ticker（Go 兼容 API）|
| ticker/heap.v | 173 | 4-ary min-heap |
| ticker/bucket.v | 134 | 64 桶调度器 |
| ticker/optimizer.v | 126 | 桶头最小堆优化 |
| support/collection.v | 315 | 链式集合（30+ 方法）|
| support/str.v | 309 | 字符串工具（20+ 方法）|
| support/arr.v | 232 | 数组工具 |
| support/pagination.v | 126 | 分页器 |
| support/sort.v | 171 | Sort + PageRequest |
| cli/application.v | 148 | CliApplication |
| cli/command.v | 38 | Command 接口 |
| cli/input.v | 97 | CommandInput 参数解析 |
| cli/output.v | 123 | CommandOutput 彩色输出 |
| cli/format.v | ~60 | ANSI 格式化 |
| cli/interactive.v | ~80 | ask/confirm/secret/choice |
| cli/progress.v | ~40 | ProgressBar |
| cli/builtin.v | 132 | list/help/serve 命令 |
| http/client.v | 179 | HttpClient fluent API |
| example/main.v | 373 | 全功能演示 |
| AGENTS.md | 172 | 开发规范宪法 |
| Makefile | 148 | 构建/测试/部署自动化 |
| ci.yml | 154 | GitHub Actions 矩阵测试 |

### B. 当前架构缺口

1. **core/** DI 容器已实现 — ApplicationContext + Container + Environment + EventBus + Lifecycle + BeanPostProcessor + FactoryBean + ServiceLocator + AutoConfiguration 均已就绪
2. **http client** 为 stub — 缺少真实 HTTP 网络调用
3. **orm 迁移** 为 stub — 需要真实数据库连接才能运行
4. **S3 adapter** 为 stub — 缺少 AWS Signature V4 签名
5. **加密** 为 XOR（非 AES）— 生产环境需要真实 AES/ChaCha20
6. **密码哈希** 为 FNV-1a（非 bcrypt/argon2）— 生产环境需要 C 库绑定或 V 原生实现
7. **web filter 链** 未完全集成到 server.v 中

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
