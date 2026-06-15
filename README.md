# ⚡ Photon Framework

> **V 语言企业级框架** — 对标 Spring Boot，注解驱动的声明式编程模型，编译期依赖注入与代码生成，零运行时反射开销。

<p align="center">
  <img src="https://img.shields.io/badge/V-0.4.x%2B-5d87bf?style=flat-square" alt="V version">
  <img src="https://img.shields.io/badge/version-0.1.0-blue?style=flat-square" alt="Version">
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="License">
  <a href=".github/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/photon-framework/photon/ci.yml?branch=master&style=flat-square" alt="CI"></a>
</p>

---

**Photon** 是一个面向商业化应用的 V 语言企业级框架，提供完整的中间件生态（缓存、日志、ORM、锁、连接池）和低心智成本的高生产力编程体验。

**核心哲学：** 编译期优于运行期，显式优于隐式，约定优于配置。

---

## 📦 模块架构

```
photon/
├── core/       # 核心容器：DI、AOP、生命周期、事件总线、条件装配、调度器、重试
├── config/     # 多源配置管理、属性绑定、Profile 支持
├── cli/        # Laravel / Symfony 风格 CLI 框架
├── web/        # veb 增强：注解路由、中间件链、Pipeline、过滤器、表单构建
├── orm/        # ORM：实体映射、仓库模式、多驱动、迁移
├── cache/      # 缓存抽象：内存/Redis 多后端，Singleflight 削峰
├── security/   # 安全：JWT、RBAC、CSRF、BCrypt / Argon2 哈希
├── queue/      # 消息队列：任务调度、Worker、失败重试
├── locking/    # 锁：LocalMutex、分布式锁、RAII LockGuard
├── pool/       # 对象/连接池：健康检查、闲置超时
├── storage/    # 文件系统抽象：本地/S3 适配器
├── ticker/     # 高性能定时器：4-ary 堆、64 桶分片
├── http/       # HTTP 客户端
├── support/    # 工具：Collection、Str、Arr、分页、排序
└── example/    # 示例应用
```

---

## 🚀 快速开始

### 前置要求

- [V 语言](https://vlang.io) 0.4.x 或以上

### 安装

```bash
# 克隆仓库
git clone https://github.com/photon-framework/photon.git
cd photon

# 运行测试
v test .

# 构建示例应用
v -o example/example example/
```

### 在项目中使用

```v
import photon
import photon.core
import photon.web
import photon.cache

// 创建应用上下文
mut app := core.new_context('MyApp')

// 注册 Bean
app.register('user_service', core.BeanDefinition{
    factory: fn (mut bf core.BeanFactory) voidptr {
        // 返回你的服务实例
        return unsafe { nil }
    }
})!

// 启动
app.run()!
```

---

## 🏗️ 核心模块

### 1. 核心容器 (Core)

依赖注入容器，支持注解驱动的声明式编程。

**Bean 定义：**

```v
@[component]
pub struct UserService {
    @[autowired]
    user_repo &UserRepository
}
```

**作用域：**
- `@[scope('singleton')]` — 全局唯一实例（默认）
- `@[scope('prototype')]` — 每次注入新实例

**Bean 生命周期：** 实例化 → 属性填充 → `@[post_construct]` → 就绪 → `@[pre_destroy]` → 销毁

**自动装配：**

```v
@[autowired]             // 按字段名注入
@[qualifier('beanName')] // 按名称注入
@[value('config.key')]   // 注入配置值
```

### 2. 条件装配 (Conditional)

类似 Spring 的 `@ConditionalOnProperty` / `@ConditionalOnMissingBean`：

```v
mut registry := core.new_conditional_registry()
registry.add_condition('my_bean', &core.ConditionalOnProperty{
    name: 'feature.enabled'
    having_value: 'true'
})
registry.register_conditional(mut app, 'my_bean', bean_def)!
```

### 3. 事件系统 (Events)

发布/订阅事件系统，支持同步/异步发布：

```v
// 自定义事件
pub struct UserRegisteredEvent {
    core.BaseEvent
pub:
    user_id string
}

// 监听器
pub struct SendWelcomeEmail {
    core.BaseEventListener
}

// 发布
event_bus.publish(&UserRegisteredEvent{
    BaseEvent: core.BaseEvent{evt_type: 'user.registered'}
    user_id: '123'
})!
```

### 4. AOP — 面向切面编程

方法拦截器链，支持日志、性能监控、缓存和事务：

```v
// 通过 Interceptor 接口实现
pub struct LoggingInterceptor {
    core.Interceptor
}

chain := core.new_interceptor_chain()
chain.add(&core.LoggingInterceptor{})
chain.add(&core.TimingInterceptor{})
```

**内置拦截器：**
| 拦截器 | 作用 |
|--------|------|
| `LoggingInterceptor` | 方法调用日志 |
| `TimingInterceptor` | 方法执行时间监控 |
| `TransactionalInterceptor` | 数据库事务管理 |
| `CacheInterceptor` | 方法级缓存 |

### 5. 重试机制 (Retry)

指数退避重试：

```v
retry := core.new_retry_template()
retry.config = core.RetryConfig{
    max_attempts: 3
    backoff_ms:   1000
    multiplier:   2.0
    max_delay_ms: 30000
}
retry.execute(fn () ! {
    // 可能失败的操作
})!
```

### 6. 定时调度 (Scheduling)

Laravel 风格的任务调度，支持 Cron 表达式：

```v
mut s := core.schedule()

// 简单频率
s.command(fn () ! { println('每分钟执行') }).every_minute()
s.command(fn () ! { println('每天执行') }).daily()

// Cron 表达式
s.command(fn () ! { println('自定义时间') }).cron('0 */2 * * *')

// 任务修饰符
s.command(fn () ! { /* ... */ })
    .daily()
    .at('03:00')
    .without_overlapping(3600)
    .run_in_background()
    .on_success(fn () ! { println('成功') })
    .on_failure(fn (msg string) ! { eprintln('失败: ${msg}') })
```

---

## 🌐 Web 模块

基于 V 的 `veb` 框架，提供注解驱动的路由、中间件链、过滤器。

### 注解路由

```v
@[controller]
pub struct UserController {
    web.BaseController
}

@[get('/users')]
pub fn (mut c UserController) list() veb.Result {
    return c.ok('[{"id":1,"name":"Alice"}]')
}

@[post('/users')]
pub fn (mut c UserController) create() veb.Result {
    return c.created('{"id":2,"name":"Bob"}')
}

@[get('/users/:id')]
pub fn (mut c UserController) get_user(id string) veb.Result {
    return c.ok('{"id":${id}}')
}
```

### 路径分组

```v
routes := web.group('/api/v1', [
    web.get('/users', 'list'),
    web.post('/users', 'create'),
    web.group('/admin', [
        web.get('/dashboard', 'admin_dashboard'),
    ]),
])
```

### 路由扫描

```v
// 编译期扫描路由注解
routes := web.scan_controller[UserController]()
web.print_routes(routes)
```

### 统一响应封装

```v
// 成功响应
web.success('{"data": "..."}')          // 200 OK
web.created('{"id": 1}')                // 201 Created
web.no_content()                        // 204 No Content

// 错误响应
web.bad_request('参数错误')              // 400
web.unauthorized('未登录')               // 401
web.forbidden('无权限')                  // 403
web.not_found('资源不存在')              // 404
web.conflict('冲突')                     // 409
web.internal_error('服务器繁忙')         // 500

// 分页响应
web.page('[...]', page=1, page_size=20, total=100)
```

### 中间件链

```v
chain := web.new_chain()
chain.use(web.logging_middleware)
chain.use(web.request_id_middleware)
chain.use(web.cors_middleware)
chain.use(web.auth_middleware)

ctx := web.new_middleware_context(&veb.Context{})
chain.execute(ctx)!
```

**内置中间件：**
| 中间件 | 作用 |
|--------|------|
| `logging_middleware` | 请求日志 |
| `cors_middleware` | CORS 跨域 |
| `auth_middleware` | 认证检查 |
| `recover_middleware` | 错误恢复 |
| `rate_limit_middleware` | 限流 |
| `request_id_middleware` | 请求追踪 ID |
| `compression_middleware` | Gzip 压缩 |
| `timing_middleware` | 响应时间 |

### Pipeline（洋葱中间件）

Laravel 风格的 Pipeline 模式：

```v
mut pipeline := web.new_pipeline()
pipeline.send(request_data)
pipeline.through([mw1, mw2, mw3])
result := pipeline.then(fn (passable voidptr) voidptr {
    // 最终处理器
    return passable
})
```

### 过滤器

```v
fc := web.new_filter_chain()
fc.add_request_filter(web.body_size_filter(10 * 1024 * 1024))
fc.add_request_filter(web.content_type_filter(['application/json']))
fc.add_response_filter(web.security_headers_filter)
```

### HttpKernel 生命周期

```v
kernel := web.new_http_kernel()
kernel.on(.request, fn (name string, data voidptr) {
    println('请求开始')
})
kernel.on(.response, fn (name string, data voidptr) {
    println('响应处理')
})
kernel.handle()!
kernel.terminate()
```

### Controller 内置方法

```v
pub fn (mut c BaseController) ok(data string) veb.Result
pub fn (mut c BaseController) created(data string) veb.Result
pub fn (mut c BaseController) no_content() veb.Result
pub fn (mut c BaseController) bad_request(msg string) veb.Result
pub fn (mut c BaseController) not_found(msg string) veb.Result
pub fn (mut c BaseController) internal_error(msg string) veb.Result
pub fn (mut c BaseController) unauthorized(msg string) veb.Result
pub fn (mut c BaseController) forbidden(msg string) veb.Result
pub fn (mut c BaseController) html(content string) veb.Result
pub fn (mut c BaseController) redirect(url string) veb.Result
```

### Web 测试工具

```v
// 创建测试响应
resp := web.response_from_result(web.success('{"id":1}'))

// 链式断言
resp.assert_status(200)
    .assert_successful()
    .assert_ok()
    .assert_body_contains('id')
    .assert_json('{"id":1}')
    .assert_json_path('id', '1')
    .assert_header('Content-Type', 'application/json')
    .dump()
```

---

## 💾 ORM 模块

多数据库 ORM，支持连接管理、实体映射、仓库模式和事务。

### 连接管理

```v
mut om := orm.new_orm_manager()

// 注册 SQLite 连接
om.register_connection('default', db_conn, .sqlite)!

// 注册 MySQL 连接
om.register_connection('mysql_db', mysql_conn, .mysql)!

// 切换默认连接
om.set_default('mysql_db')!

// 查询连接信息
println(om.driver('default')!)          // .sqlite
println(om.connection_names())          // ['default', 'mysql_db']
println(om.is_sqlite('default'))        // true
```

### 事务管理

```v
mut txm := orm.new_transaction_manager()

txm.execute(fn () ! {
    // 自动事务
    txm.begin()!
    // ... 数据库操作
    txm.commit()!
})!
```

### 迁移

```v
// 支持的迁移操作
migration.create_table('users', [
    orm.Column{name:'id', typ:.int, primary_key: true},
    orm.Column{name:'name', typ:.varchar(255)},
    orm.Column{name:'email', typ:.varchar(255), unique: true},
])!
```

---

## 🔒 安全模块

一站式安全解决方案。

### JWT

```v
mut jm := security.new_jwt_manager('your-secret-key-32-chars-min')

// 生成 Token
token := jm.generate_token('user-123', {'role': 'admin'})

// 验证 Token
claims := jm.validate_token(token)!
println(claims['sub'])   // user-123
println(claims['role'])  // admin

// 刷新 Token
new_token := jm.refresh_token(token, 3600)!
```

### RBAC 权限控制

```v
// 角色层级：admin > editor > user
mut hierarchy := security.new_role_hierarchy()
hierarchy.add('admin', 'editor')
hierarchy.add('editor', 'user')

// 检查权限
has_permission := hierarchy.has_role('editor', 'admin')  // true

// 注解式安全
@[secured]
@[roles_allowed('admin', 'editor')]
pub fn admin_dashboard() { /* ... */ }
```

### CSRF 保护

```v
mut csrf := security.new_csrf_manager()
csrf.config = security.CsrfConfig{
    token_length: 32
    cookie_name: 'XSRF-TOKEN'
    header_name: 'X-CSRF-TOKEN'
}

// 生成 Token
token := csrf.generate_token(session_id)

// 验证请求
valid := csrf.validate_token(session_id, header_token)!
```

### 加密与哈希

```v
// BCrypt 哈希
hasher := security.new_bcrypt_hasher()
hash := hasher.hash('my_password')!
valid := hasher.verify('my_password', hash)! // true

// 对称加密
encrypter := security.new_encrypter('aes-256-cbc-key-32chars')
encrypted := encrypter.encrypt('敏感数据')!
decrypted := encrypter.decrypt(encrypted)!
```

---

## 🗄️ 缓存模块

统一的缓存抽象，支持多后端。

```v
mut cm := cache.new_cache_manager()

// 基本操作
cm.set('key', 'value', 3600)!   // TTL 3600 秒
val := cm.get('key')!           // 'value'
cm.delete('key')!
cm.clear()!
cm.has('key')

// 缓存标签（缓存标签无效化）
tc := cache.new_tagged_cache('users')
tc.set('user:1', '{"name":"Alice"}', 3600)!
tc.flush()!  // 使 tags 缓存失效

// 缓存锁（分布式互斥）
cl := cache.new_cache_lock(cm)
locked := cl.acquire('lock:key', 10_000)!  // 10 秒 TTL
cl.release('lock:key')!

// 缓存标签 + Singleflight 削峰
val := cm.get_or_load('expensive_key', 300, fn () !string {
    // 仅一个请求执行此函数，其余等待
    return compute_expensive_data()
})!
```

### 注册自定义缓存后端

```v
// 实现 Cache 接口
pub struct RedisCache {
    cache.Cache
    // Redis 连接逻辑
}

cm.register('redis', &RedisCache{})
```

---

## 🔗 锁模块

### 本地互斥锁

```v
mut lm := locking.new_lock_manager()

// 阻塞锁
lm.lock('resource_key')
// ... 临界区 ...
lm.unlock('resource_key')!

// 非阻塞尝试锁
if lm.try_lock('resource_key') {
    // 获得锁
    lm.unlock('resource_key')!
}

// 超时锁
locked := lm.lock_with_timeout('resource_key', 5000)!  // 5 秒超时
```

### RAII 锁守卫

```v
{
    guard := locking.new_lock_guard(mut lm, 'resource_key')
    // 离开作用域时自动解锁
}

// 函数守卫
result := locking.guarded_lock[int](mut lm, 'my_lock', fn () !int {
    return 42
})!
```

### 分布式锁

```v
// 通过 DistributedLock 接口注册 Redis 后端
lm.with_distributed_lock(&redis_lock)

lm.dist_lock('global_resource', 30_000)! // 30 秒 TTL
// ... 分布式操作 ...
lm.dist_unlock('global_resource')!
```

---

## 📨 队列模块

Laravel 风格的异步任务队列。

### 定义任务

```v
pub struct SendEmailJob {
    queue.Job
pub:
    email string
    template string
}

pub fn (j &SendEmailJob) job_type() string { return 'send_email' }
pub fn (j &SendEmailJob) handle() ! {
    // 发送邮件逻辑
}
pub fn (j &SendEmailJob) tries() int { return 3 }
pub fn (j &SendEmailJob) backoff() []i64 { return [1, 5, 10] }
```

### 分发任务

```v
dispatcher := queue.new_dispatcher()
dispatcher.dispatch(&SendEmailJob{email: 'user@example.com', template: 'welcome'})!

// 延迟分发
dispatcher.dispatch_delayed(&SendEmailJob{...}, 60)!

// 失败任务处理
failed_repo := queue.new_failed_job_repository()
failed_handler := queue.new_failed_job_handler(failed_repo)
```

### 内置命令

```bash
# 启动队列 Worker
schedule:run

# 队列管理
queue:work
```

---

## 📦 连接池

```v
// 创建连接池
pool := pool.new_pool_with_config('db', factory_fn, min_size=2, max_size=10)

// 初始化
pool.initialize()!

// 获取连接
conn := pool.acquire()!

// 归还连接
pool.release(conn)

// 统计信息
stats := pool.stats()
println('active: ${stats.active} / idle: ${stats.idle} / total: ${stats.total}')
```

---

## 💾 存储模块

Flysystem 风格的文件系统抽象。

```v
mut manager := storage.new_manager()

// 注册适配器
manager.register('local', storage.new_local_adapter('/var/uploads'))
manager.register('s3', storage.new_s3_adapter('my-bucket', 'us-east-1'))

// 文件操作
disk := manager.get('local')!
disk.write('hello.txt', 'Hello World', storage.public_options())!
content := disk.read('hello.txt')!
disk.delete('hello.txt')!
exists := disk.exists('path/to/file.txt')

// 元数据
meta := disk.metadata('file.txt')!
println(meta.size)
println(meta.mime_type)
println(meta.visibility)
```

---

## ⏱️ 定时器模块

Go 风格的高性能定时器。

```v
import photon.ticker

// 一次性定时器
t := ticker.new_timer(1 * time.second)
<-t.c  // 阻塞直到触发

// 周期性定时器
tk := ticker.new_ticker(500 * time.millisecond)
for _ in 0 .. 5 {
    <-tk.c
    println('tick')
}

// 快捷方法
ticker.sleep(100 * time.millisecond)
ch := ticker.after(2 * time.second)
```

**性能特性：** 4-ary 最小堆 + 64 桶分片，零外部依赖。

---

## 🛠️ CLI 模块

Laravel / Symfony 风格的命令行框架。

### 内置命令

```bash
# 查看所有命令
list

# 查看帮助
help <command>

# 启动开发服务器
serve --port=8080
```

### 自定义命令

```v
mut app := cli.new_application('photon', '0.1.0')

// 添加内置命令
app.add_command(cli.new_serve_command())
app.add_command(cli.new_list_command(app))
app.add_command(cli.new_help_command(app))

// 运行
app.run() or { panic(err) }
```

### 交互式输入

```v
answer := cli.ask('请输入名称: ')
confirmed := cli.confirm('确认删除? (y/n): ')
secret := cli.secret('请输入密码: ')
choice := cli.choice('选择颜色:', ['红', '蓝', '绿'])
```

### 代码生成

```bash
make:command SendEmail      # 生成命令
make:controller User        # 生成控制器
make:middleware Auth         # 生成中间件
```

### 进度条

```v
p := progress_bar(100)
for i in 0 .. 100 {
    p.advance()
    time.sleep(50 * time.millisecond)
}
p.finish()
```

---

## ⚙️ 配置模块

多源配置管理。

```v
mut cfg := config.new()

// 添加配置源
cfg.add_source(config_source)

// 设置激活 Profile
cfg.set_profile(['dev', 'local'])

// 加载所有配置
cfg.load()!

// 读取配置
db_host := cfg.get('database.host')
db_port := cfg.get_int_or('database.port', 5432)
debug := cfg.get_bool_or('app.debug', false)

// 设置配置
cfg.set('app.name', 'Photon Demo')
```

---

## 🧩 支持工具

### Collection — 链式集合操作

```v
c := support.collect([1, 2, 3, 4, 5])

result := c.filter(fn (n int) bool { return n > 2 })
    .map(fn (n int) string { return n.str() })
    .all()
// ['3', '4', '5']

// 更多操作
c.first(0)           // 1
c.last(0)            // 5
c.chunk(2)           // [[1,2], [3,4], [5]]
c.sort_by(fn (n int) int { return -n })
c.group_by(fn (n int) string { return if n % 2 == 0 { 'even' } else { 'odd' } })
c.to_json()          // '[1,2,3,4,5]'
```

### 分页

```v
// 简单分页
paginator := support.new_simple_paginator(items, 15)
page_items := paginator.items()
has_more := paginator.has_more()

// 完整分页（含总数）
lp := support.new_length_aware_paginator(items, total, 20)
total_pages := lp.total_pages()
```

### 排序

```v
s := support.new_sort('name', .asc, 'created_at', .desc)
println(s.order_by()) // 'name ASC, created_at DESC'
```

---

## 🧪 测试

所有模块都包含完整的测试套件。

```bash
# 运行全部测试
v test . -stats

# 运行单个模块测试
v test cache/
v test web/
v test orm/
v test security/
v test queue/
```

---

## 📜 注解参考

| 注解 | 作用域 | 说明 |
|------|--------|------|
| `@[component]` | struct | 标记为组件 |
| `@[service]` | struct | 标记为服务 |
| `@[repository]` | struct | 标记为仓库 |
| `@[controller]` | struct | 标记为 Web 控制器 |
| `@[configuration]` | struct | 标记为配置类 |
| `@[autowired]` | field | 自动注入依赖 |
| `@[value('key')]` | field | 注入配置值 |
| `@[qualifier('name')]` | field | 按名称注入 |
| `@[post_construct]` | fn | 初始化回调 |
| `@[pre_destroy]` | fn | 销毁回调 |
| `@[lazy]` | struct/fn | 延迟初始化 |
| `@[scope('singleton'|'prototype')]` | struct | 作用域 |
| `@[get('/path')]` | fn | GET 路由 |
| `@[post('/path')]` | fn | POST 路由 |
| `@[put('/path')]` | fn | PUT 路由 |
| `@[delete('/path')]` | fn | DELETE 路由 |
| `@[patch('/path')]` | fn | PATCH 路由 |
| `@[cacheable]` | fn | 方法级缓存 |
| `@[transactional]` | fn | 事务管理 |
| `@[scheduled('cron')]` | fn | 定时任务 |
| `@[async]` | fn | 异步执行 |
| `@[secured]` | fn | 安全控制 |
| `@[roles_allowed('a','b')]` | fn | 角色限制 |
| `@[permit_all]` | fn | 允许所有人 |
| `@[deny_all]` | fn | 拒绝所有人 |

---

## 🤝 贡献指南

1. Fork 仓库，创建 feature 分支
2. 编写代码并添加测试
3. 运行 `v test .` 确保全部通过
4. 提交 PR，描述变更内容与动机

---

## 📄 开源协议

[MIT License](LICENSE) — 框架核心永久开源免费。

高级特性（分布式锁、集群支持）为开放核心模式，企业版可扩展。

---

<p align="center">
  <strong>Photon Framework</strong> — Build enterprise applications in V, the way they should be built.
</p>
