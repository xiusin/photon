# Photon 框架实战教程

> 从零构建企业级 V 语言应用

---

## 目录

- [1. 30 秒启动](#1-30-秒启动)
- [2. 配置管理](#2-配置管理)
- [3. 日志系统](#3-日志系统)
- [4. Web 开发](#4-web-开发)
- [5. 数据库与 ORM](#5-数据库与-orm)
- [6. 安全模块](#6-安全模块)
- [7. 缓存](#7-缓存)
- [8. 锁](#8-锁)
- [9. 队列](#9-队列)
- [10. 连接池](#10-连接池)
- [11. 文件存储](#11-文件存储)
- [12. HTTP 客户端](#12-http-客户端)
- [13. CLI 工具](#13-cli-工具)
- [14. 定时器](#14-定时器)
- [15. 工具库](#15-工具库)
- [16. 注解速查](#16-注解速查)

---

## 1. 30 秒启动

一个最小的 Photon 应用：

```v
import photon.cli
import photon.config
import photon.log

fn main() {
    mut app := cli.new_application('myapp', '1.0.0')
    app.add_command(cli.new_serve_command())
    app.add_command(cli.new_list_command(app))
    app.add_command(cli.new_help_command(app))
    app.run() or { panic(err) }
}
```

运行：

```bash
v run . serve --port=8080
v run . list
v run . help serve
```

项目结构建议：

```
myapp/
├── main.v           # 入口
├── controllers/     # 控制器
├── models/          # 实体
├── middleware/      # 中间件
└── config/          # 配置文件
```

---

## 2. 配置管理

### 2.1 基本用法

```v
import photon.config

mut cfg := config.new()

// 直接设置
cfg.set('app.name', 'MyApp')
cfg.set('server.port', '8080')

// 读取
cfg.get('app.name')                    // 'MyApp'
cfg.get('missing.key')                 // '' (空串)
cfg.get_or('missing.key', 'default')   // 'default'
cfg.get_int('server.port')!            // 8080
cfg.get_int_or('port', 3000)           // 带默认值的 int
cfg.get_bool_or('debug', false)        // 带默认值的 bool
cfg.get_f64('ratio')!                  // f64
cfg.has('app.name')                    // true
cfg.keys()                             // ['app.name', 'server.port']
```

### 2.2 多配置源

Photon 支持三种内置配置源：Map、文件、环境变量。后添加的源覆盖同 key：

```v
mut cfg := config.new()

// Map 源 —— 适合硬编码或测试
cfg.add_source(config.MapConfigSource{
    data: {
        'app.name':    'MyApp'
        'db.host':     'localhost'
        'db.port':     '5432'
        'debug':       'true'
    }
})

// 环境变量源 —— 自动读取带前缀的环境变量
cfg.add_source(config.EnvConfigSource{
    prefix: 'APP_'    // 读取 APP_DB_HOST -> db.host
})

// 文件源 —— 从 JSON 或 key=value 文件加载
cfg.add_source(config.FileConfigSource{
    filepath: './config.json'
})

cfg.load()!
```

### 2.3 Profile（环境隔离）

```v
cfg.set_profile(['dev', 'local'])
cfg.add_profile('cloud')              // 追加
cfg.profiles                           // ['dev', 'local', 'cloud']
```

### 2.4 Environment（Spring 风格）

```v
mut env := config.new_environment()
env.add_source(my_property_source)
env.add_profile('production')

env.get_property('db.host')                  // ?string
env.get_property_or('db.host', 'localhost')  // string
env.contains_property('db.host')             // bool
env.is_production()                          // 检查是否 prod/production profile
env.resolve_placeholders('host: ${db.host}') // 替换 ${key} 占位符
```

### 2.5 PropertyBinder（注解值绑定）

`@[value('db.host')]` 的底层实现：

```v
binder := config.new_property_binder(cfg)

binder.resolve_value('db.host')                        // 从配置读取
binder.resolve_value('missing.key:localhost')           // key:default 格式
```

---

## 3. 日志系统

### 3.1 基础日志

```v
import photon.log

mut logger := log.new()              // 默认 INFO 级别
logger.set_level(.debug)             // 显示所有级别
logger.set_colored(true)             // 彩色输出
logger.set_output_label('my-app')    // 标签名

logger.debug('调试信息')
logger.info('应用启动')
logger.warn('内存不足')
logger.error('连接失败')
logger.fatal('系统崩溃')
```

格式化输出：

```v
logger.infof('用户 {} 登录成功', username)
logger.errorf('连接 {}:{} 超时', host, port)
```

### 3.2 日志级别

```
debug < info < warn < error < fatal
```

设置 `.warn` 级别后，`debug` 和 `info` 静默丢弃。

```v
logger := log.new_with_level(.warn)  // 只输出 warn/error/fatal
```

### 3.3 MDC（上下文追踪）

```v
mut logger := log.new()
logger.put('request_id', 'abc-123')
logger.put('user_id', '42')
logger.info('处理请求')            // 携带 MDC 上下文
logger.get('request_id')          // 'abc-123'
logger.remove('user_id')
logger.clear_context()            // 清空所有 MDC
```

### 3.4 结构化 JSON 日志

```v
mut logger := log.new()
logger.set_structured(true)        // 输出 JSON 格式
logger.put('trace_id', 'xyz')
logger.info('structured log')      // {"level":"info","msg":"structured log","trace_id":"xyz",...}
```

### 3.5 多通道日志

```v
mut cl := log.new_channel_logger()
cl.add_channel(&log.StderrChannel{})
cl.add_channel(&log.FileChannel{filepath: '/var/log/app.log'})
cl.level = .info
cl.put('env', 'production')
cl.info('多通道输出')              // 同时写 stderr + 文件

// 链式上下文（不修改原始实例）
cl2 := cl.with_context('job', 'import').with_request_id('req-001')
cl2.info('任务开始')
```

### 3.6 敏感信息脱敏

```v
log.mask_sensitive_data('password=admin123&token=xyz')
// 'password=********&token=********'
```

自动脱敏的 key：`password`、`token`、`secret`、`api_key`、`authorization`、`credit_card` 等。

---

## 4. Web 开发

### 4.1 Controller

```v
import veb
import photon.web

pub struct App {
    veb.Context
pub mut:
    logger &log.Logger = log.new()
}

// 首页
@[get; '/']
pub fn (mut app App) index() veb.Result {
    return app.text('Hello Photon')
}

// 带路径参数
@[get; '/users/:id']
pub fn (mut app App) get_user(id string) veb.Result {
    return app.text('User: ${id}')
}
```

### 4.2 统一响应封装

所有 API 统一返回格式，告别手动拼 JSON：

```v
// 成功
web.ok('{"id":1,"name":"Alice"}')         // 200
web.created('{"id":2}')                    // 201
web.no_content()                           // 204

// 错误
web.bad_request('参数错误')                 // 400
web.unauthorized('未登录')                  // 401
web.forbidden('无权限')                     // 403
web.not_found('资源不存在')                 // 404
web.conflict('数据冲突')                    // 409
web.internal_error('服务器繁忙')            // 500

// 分页
web.page('[{...}, {...}]', page: 1, page_size: 20, total: 100)
```

`Result` 结构：

```v
pub struct Result {
    success   bool
    code      int
    message   string
    data      string
    timestamp i64
    path      string
}

r := web.ok('{"name":"Alice"}')
r.to_json()    // JSON 字符串
```

### 4.3 路由注册

手动注册：

```v
routes := [
    web.get('/users', 'list'),
    web.post('/users', 'create'),
    web.get('/users/:id', 'get_user'),
    web.group('/api/v1', [
        web.get('/dashboard', 'dashboard'),
        web.group('/admin', [
            web.get('/settings', 'admin_settings'),
        ]),
    ]),
]
```

编译期自动扫描（通过 `@[get]`、`@[post]` 等注解）：

```v
routes := web.scan_controller[App]()
web.print_routes(routes)
```

### 4.4 中间件

```v
mut chain := web.new_chain()
chain.use(web.request_id_middleware)        // 请求 ID
chain.use(web.logging_middleware)           // 日志
chain.use(web.cors_middleware)              // CORS
chain.use(web.auth_middleware)              // 认证
chain.use(web.request_id_cleanup_middleware)// 清理

mut mctx := web.new_middleware_context(unsafe { nil })
mctx.route_path = '/api/users'
mctx.route_method = 'GET'
mctx.logger = my_logger          // 绑定 logger，request_id_middleware 自动写入 MDC
defer { mctx.logger.remove('request_id') }
chain.execute(mctx) or {}
```

内置中间件一览：

| 中间件 | 作用 |
|--------|------|
| `logging_middleware` | 请求日志 |
| `cors_middleware` | CORS 跨域 |
| `auth_middleware` | 认证检查 |
| `request_id_middleware` | 生成请求追踪 ID |
| `request_id_cleanup_middleware` | 清理请求 ID |
| `recover_middleware` | 错误恢复 |
| `compression_middleware` | Gzip 压缩 |
| `timing_middleware` | 响应时间 |

参数化中间件（工厂模式）：

```v
// 限流：每分钟最多 60 次
chain.use(web.throttle_middleware(60, 1))

// 角色检查：只允许 ADMIN
chain.use(web.role_middleware(['ADMIN']))
```

### 4.5 中间件分组

```v
mut groups := web.new_middleware_group_registry()
groups.register('web', [web.logging_middleware, web.cors_middleware])
groups.register('api', [web.auth_middleware, web.throttle_middleware(100, 1)])
groups.get('web')   // []MiddlewareFunc
```

### 4.6 Pipeline（洋葱模型）

```v
mut pipeline := web.new_pipeline()
pipeline.send(request_data)
pipeline.through([mw1, mw2, mw3])
result := pipeline.then(fn (passable voidptr) voidptr {
    // 最终处理器
    return passable
})
```

### 4.7 过滤器

```v
fc := web.new_filter_chain()
fc.add_request_filter(web.body_size_filter(10 * 1024 * 1024))  // 限制 body 大小
fc.add_request_filter(web.content_type_filter(['application/json']))
fc.add_response_filter(web.security_headers_filter)             // 安全头
```

### 4.8 表单构建与验证

```v
mut f := web.form()
f.add('username', .text).set_required('username', true).add_rule('username', 'min:3')
f.add('email', .email).set_required('email', true)
f.add('password', .password).add_rule('password', 'min:8')
f.add('role', .select_).options = ['user', 'admin']
f.add('agree', .checkbox)
```

字段类型：`.text` `.email` `.password` `.number` `.textarea` `.select_` `.checkbox` `.file` `.hidden`

### 4.9 HttpKernel（事件驱动）

```v
kernel := web.new_http_kernel()
kernel.on(.request, fn (name string, data voidptr) {
    println('请求开始')
})
kernel.on(.response, fn (name string, data voidptr) {
    println('响应处理')
})
kernel.on(.terminate, fn (name string, data voidptr) {
    println('请求结束')
})
kernel.handle()!
kernel.terminate()
```

事件类型：`.request` `.controller` `.response` `.exception` `.terminate`

### 4.10 HTTP 测试

```v
// 从 Result 构造测试响应
mut resp := web.response_from_result(web.ok('{"name":"Alice","age":"30"}'))

// 链式断言
resp.assert_ok()
resp.assert_status(200)
resp.assert_successful()                        // 2xx
resp.assert_json_path('name', 'Alice')          // JSON 路径断言
resp.assert_json_path('data.user.email', 'a@b') // 嵌套路径
resp.assert_json_structure(['name', 'age'])     // 顶层 key 存在
resp.assert_json_count('', 3)                   // 数组长度
resp.dump()                                     // 调试输出

// 错误响应
mut err_resp := web.response_from_result(web.not_found('nope'))
err_resp.assert_not_found()
err_resp.assert_failed()                        // 4xx/5xx

// 从原始数据构造
mut r := web.response_from_raw(201, '{"id":1}')
r.assert_created()

// 带自定义 header
mut r2 := web.response_with_headers(200, '{"ok":true}', {'X-Custom': 'val'})
r2.assert_header('X-Custom', 'val')
```

---

## 5. 数据库与 ORM

### 5.1 连接管理

```v
import photon.orm

mut om := orm.new_orm_manager()

// 注册连接（第一个自动成为 default）
om.register_connection('primary', .sqlite, sqlite_conn)!
om.register_connection('replica', .pg, pg_conn)!
om.register_connection('analytics', .mysql, mysql_conn)!

// 切换默认
om.set_default('replica')!

// 查询
om.driver('primary')!           // .sqlite
om.is_sqlite('primary')         // true
om.is_pg('replica')            // true
om.is_mysql('analytics')       // true
om.connection_names()           // ['primary', 'replica', 'analytics']
om.has_connection('primary')   // true
om.default_conn()!             // replica 的 voidptr
```

### 5.2 实体定义

```v
// 基础实体 —— 自带 id、created_at、updated_at、version
struct User {
    orm.BaseEntity
pub mut:
    name  string
    email string
}

// 软删除实体 —— 额外支持 deleted_at
struct Article {
    orm.SoftDeletableEntity
pub mut:
    title   string
    content string
}
```

实体操作：

```v
mut user := User{name: 'Alice', email: 'alice@test.com'}
user.is_new()        // true（id == 0）
user.touch()         // 自动设置时间戳 + version++
user.created_at      // 已填充
user.version         // 1

mut article := Article{title: 'Hello'}
article.soft_delete()    // is_deleted() == true, deleted_at 已填充
article.restore()        // is_deleted() == false, deleted_at = 0
```

### 5.3 Repository（仓库模式）

```v
// 构造 Repository 需要传入回调函数
mut repo := orm.new_repository[User](
    manager:       om
    db_name:       'default'
    exec_find:     fn (conn voidptr, id int) !User { /* 查询逻辑 */ }
    exec_find_all: fn (conn voidptr) ![]User { /* 查询逻辑 */ }
    exec_insert:   fn (conn voidptr, entity User) ! { /* 插入逻辑 */ }
    exec_update:   fn (conn voidptr, entity User) ! { /* 更新逻辑 */ }
    exec_delete:   fn (conn voidptr, id int) ! { /* 删除逻辑 */ }
    exec_count:    fn (conn voidptr) !int { /* 计数逻辑 */ }
    exec_exists:   fn (conn voidptr, id int) bool { /* 存在性检查 */ }
)!

// CRUD
entity := repo.find_by_id(1)!
all := repo.find_all()!
repo.save(mut new_user)!         // 自动判断 insert/update
repo.update(mut existing_user)!
repo.delete(entity)!
repo.delete_by_id(42)!
repo.count()!                    // int
repo.exists_by_id(1)             // bool
```

> 为什么用回调？V 0.5.x 的 `orm` 模块名与标准库冲突，回调模式绕开 `import orm` 的问题。

### 5.4 OrmAdapter（生命周期钩子）

```v
mut adapter := orm.new_orm_adapter[User](om, 'default')!

// 钩子会在真正的 DB 操作前后自动触发
mut user := User{name: 'Bob'}

// 方式 1：手动调用钩子
adapter.before_insert(mut user)!    // 触发 BeforeCreate + Touchable
// ... 执行 SQL INSERT ...
adapter.after_insert(mut user)!     // 触发 AfterCreate

// 方式 2：wrap 系列方法 = 钩子 + 你的回调
adapter.wrap_insert(mut user, fn (mut u User) ! {
    // 在这里执行 V ORM 的 insert
})!

adapter.wrap_update(mut user, fn (mut u User) ! {
    // 在这里执行 V ORM 的 update
})!

// 自动检测 insert 还是 update
adapter.wrap_save(mut user, fn (mut u User) ! {
    // user.is_new() ? insert : update
})!
```

生命周期钩子接口（实体实现即可自动触发）：

| 接口 | 时机 |
|------|------|
| `BeforeCreateHook` | INSERT 前 |
| `AfterCreateHook` | INSERT 后 |
| `BeforeUpdateHook` | UPDATE 前 |
| `AfterUpdateHook` | UPDATE 后 |
| `BeforeDeleteHook` | DELETE 前 |
| `AfterDeleteHook` | DELETE 后 |
| `AfterFindHook` | SELECT 后 |

### 5.5 派生查询（Spring Data 风格）

```v
parts := orm.parse_method_name('findByNameAndEmail')!
parts.operation              // .find
parts.conditions             // [QueryCondition{property:'name',op:'='}, {property:'email',op:'='}]
parts.to_where_cond()        // 'name = ? AND email = ?'
parts.to_where_param_count() // 2
```

支持的命名模式：

| 方法名 | 操作 | WHERE |
|--------|------|-------|
| `findByName` | SELECT | `name = ?` |
| `findByNameAndAge` | SELECT | `name = ? AND age = ?` |
| `findByNameOrAge` | SELECT | `name = ? OR age = ?` |
| `findTop10ByName` | SELECT LIMIT 10 | `name = ?` |
| `findByNameOrderByCreatedAtDesc` | SELECT ORDER BY | `name = ?` |
| `countByStatus` | COUNT | `status = ?` |
| `existsByEmail` | EXISTS | `email = ?` |
| `deleteByExpired` | DELETE | `expired = ?` |

### 5.6 事务

```v
mut tm := orm.new_transaction_manager()

// 手动控制
tm.begin()!
// ... DB 操作 ...
tm.commit()!
// 或 tm.rollback()!

// 声明式（自动 begin/commit/rollback）
tm.execute(.required, fn () ! {
    // 有事务就加入，没有就新建
})!

// 便捷函数
orm.transactional(fn () ! {
    // 等同于 .required
})!
```

传播行为：

| 传播 | 说明 |
|------|------|
| `.required` | 有事务加入，没有新建（默认） |
| `.requires_new` | 挂起当前事务，新建独立事务 |
| `.nested` | 在当前事务内创建保存点 |
| `.supports` | 有事务就加入，没有就裸跑 |
| `.not_supported` | 挂起当前事务，裸跑 |
| `.mandatory` | 必须在事务内调用，否则报错 |
| `.never` | 必须不在事务内调用，否则报错 |

嵌套事务示例：

```v
tm.execute(.required, fn [mut tm] () ! {
    // 外层事务
    tm.execute(.nested, fn () ! {
        // 内层保存点 —— 可以独立回滚
    })!
})!
```

### 5.7 关系定义

```v
struct User {
    id      int
    posts   orm.HasMany[Post]      // 一对多
    profile orm.HasOne[Profile]    // 一对一
}

struct Post {
    id       int
    author   orm.BelongsTo[User]   // 多对一
    tags     orm.ManyToMany[Tag]   // 多对多
}

// 延迟加载
user.posts.loaded    // false
// 加载后
user.posts.items     // []Post
```

关系配置：

```v
orm.Relationship{
    name:        'posts'
    typ:         'has_many'          // has_many / belongs_to / many_to_many / has_one
    target:      'Post'
    foreign_key: 'user_id'
    local_key:   'id'
    pivot_table: ''                  // many_to_many 需要
}
```

### 5.8 迁移

```v
mut mm := orm.new_migration_manager(om)
mm.migration_table = 'schema_migrations'   // 可自定义表名

mm.add(my_migration_001)
mm.add(my_migration_002)
```

迁移接口：

```v
pub interface Migration {
    version() int
    name() string
    up(mut manager OrmManager) !
    down(mut manager OrmManager) !
}
```

---

## 6. 安全模块

### 6.1 JWT

```v
import photon.security

jwt_config := security.JwtConfig{
    secret:                         'your-256-bit-secret-key-here-min-32-chars!!'
    issuer:                         'myapp'
    expiration_minutes:             60
    refresh_token_expiration_hours: 168
    audience:                       'myapp-users'
}
mut jm := security.new_jwt_manager(jwt_config)

// 生成 Token
token := jm.create_token('alice', ['USER', 'ADMIN'])!

// 解析 Token
claims := jm.parse_token(token)!
claims.sub           // 'alice'
claims.roles         // ['USER', 'ADMIN']
claims.iss           // 'myapp'
claims.exp           // 过期时间戳

// 验证 Token
username := jm.validate_token(token)!   // 返回 sub

// 角色检查
jm.has_role(token, 'ADMIN')             // true
jm.has_any_role(token, ['ADMIN','MOD']) // true

// Refresh Token
refresh := jm.create_refresh_token('alice')!
```

Token 结构：`header.payload.signature`（三段式，Base64URL 编码）

### 6.2 RBAC 角色层级

```v
mut hierarchy := security.new_role_hierarchy()
hierarchy.add('admin', 'editor')     // admin 继承 editor 权限
hierarchy.add('editor', 'user')      // editor 继承 user 权限

hierarchy.has_role('editor', 'admin')   // true —— editor 拥有 admin 的所有权限
```

安全注解：

```v
@[secured]
@[roles_allowed('admin', 'editor')]
pub fn admin_dashboard() { /* ... */ }

@[permit_all]
pub fn public_page() { /* ... */ }

@[deny_all]
pub fn blocked() { /* ... */ }
```

### 6.3 认证管理

```v
// 用户存储
mut user_service := security.new_in_memory_service()
user_service.add_user(security.new_user('admin', 'admin123', ['ADMIN']))
user_service.add_user(security.new_user('user', 'user123', ['USER']))

// 认证管理器
mut auth_mgr := security.new_auth_manager()
auth_mgr.add_provider(&security.JwtAuthenticationProvider{
    jwt_manager: jwt_mgr
})
auth_mgr.add_provider(&security.UsernamePasswordProvider{
    user_service: user_service
})

// 执行认证
mut auth := security.new_authentication('admin', 'admin123')
auth.is_authenticated()              // false
auth_mgr.authenticate(mut auth)!     // 认证
auth.is_authenticated()              // true
auth.authorities                      // ['ADMIN']
```

### 6.4 CSRF 保护

```v
csrf_config := security.CsrfConfig{
    enabled:      true
    token_length: 32
    cookie_name:  'XSRF-TOKEN'
    header_name:  'X-CSRF-TOKEN'
}
mut csrf := security.new_csrf_manager(csrf_config)

// 生成
token := csrf.create_token()!    // {token: '...', cookie_name: 'XSRF-TOKEN'}

// 验证
csrf.validate_token(session_id, header_token)!
```

### 6.5 SecurityFilterChain（路由安全）

```v
mut chain := security.new_security_filter_chain(auth_mgr, jwt_mgr, csrf_mgr)
chain.with_permit_all('/')                      // 公开
chain.with_permit_all('/health')                // 公开
chain.with_permit_all('/api/auth/login')        // 公开
chain.with_secured('/api/users')                // 需认证
chain.with_roles('/api/admin', ['ADMIN'])       // 需 ADMIN 角色
chain.with_roles('/api/mod', ['ADMIN', 'MODERATOR'])  // 需指定角色
```

### 6.6 密码哈希

```v
// BCrypt
mut hasher := security.BcryptHasher{rounds: 12}
hash := hasher.make('mypassword')!      // $2y$12$...
hasher.check('mypassword', hash)!       // true
hasher.needs_rehash(hash)               // 检查是否需要重哈希

// Argon2id
mut hasher2 := security.Argon2Hasher{
    memory:  65536
    time:    4
    threads: 1
}
hash2 := hasher2.make('mypassword')!    // $argon2id$v=19$m=65536...
hasher2.check('mypassword', hash2)!     // true
```

### 6.7 加密

```v
mut enc := security.new_encrypter('aes-256-cbc-key-32chars-minimum!!')
encrypted := enc.encrypt('敏感数据')!
decrypted := enc.decrypt(encrypted)!
```

### 6.8 SecurityContext

```v
mut holder := security.new_security_context_holder()
holder.context.authentication = my_auth
holder.context.authentication.is_authenticated()  // true
```

---

## 7. 缓存

### 7.1 基本操作

```v
import photon.cache

mut cm := cache.new_cache_manager()

cm.set('user:42', '{"name":"Alice"}', 3600)!   // key, value, TTL 秒
val := cm.get('user:42')!                        // '{"name":"Alice"}'
cm.has('user:42')                                // true
cm.delete('user:42')!
cm.clear()!

// 带默认值
cm.get_or('missing', 'default')    // 不存在时返回默认值（注意：这是 panic 版本，用 ! 版本）
```

### 7.2 内存缓存

```v
mut mc := cache.new_memory_cache('my-cache')
mc.set('key', 'value', 0)!        // TTL 0 = 永不过期
mc.set('key', 'value', -1)!       // TTL 负数 = 永不过期
mc.set('key', 'value', 3600)!     // TTL 3600 秒

mc.evict_expired()                 // 返回清除数量
mc.stats()                         // CacheStats{total_entries, expired_entries, total_hits, max_size}
```

限制容量 + LRU 淘汰：

```v
mut mc := cache.new_memory_cache_with_max('limited', 100)  // 最多 100 条
```

### 7.3 自定义缓存后端

```v
cm.register('redis', &my_redis_cache)     // 注册命名缓存
cm.get_cache('redis')                      // 获取命名缓存
cm.get_cache('nonexistent')               // 回退到 default
```

实现 `Cache` 接口即可：

```v
pub interface Cache {
mut:
    get(key string) !string
    set(key string, value string, ttl_seconds int) !
    delete(key string) !
    has(key string) bool
    clear() !
    keys() []string
    size() int
}
```

### 7.4 缓存标签

标签缓存可以按组批量失效：

```v
mut tc := cache.new_tagged_cache(my_cache, ['users'])
tc.set('user:1', '{"name":"Alice"}', 3600)!
tc.set('user:2', '{"name":"Bob"}', 3600)!
tc.flush()!    // 使 'users' 标签下的所有缓存失效
```

### 7.5 缓存锁

```v
mut cl := cache.new_cache_lock(my_cache, 'import-lock', 10)  // name, TTL 秒

locked := cl.acquire()!         // 非阻塞获取
cl.block(30)!                   // 阻塞获取，30 秒超时
cl.is_acquired()                // bool
cl.get_owner()                  // 持有者标识
cl.release()!                   // 释放（只有 owner 能释放）
cl.force_release()!             // 强制释放
```

### 7.6 get_or_load（缓存穿透削峰）

高并发下只执行一次加载，其他请求等待结果：

```v
val := cm.get_or_load('expensive_key', 300, fn () !string {
    return fetch_from_database()!    // 只有一个请求会执行
})!
```

底层使用 Singleflight：

```v
mut sf := cache.new_singleflight()
sf.do('key', fn () !string {
    return expensive_call()!
})!
sf.has_inflight('key')      // 是否正在执行
sf.inflight_count()          // 当前并发数
```

### 7.7 辅助函数

```v
// 记住（缓存不存在就加载）
cache.remember(mut cm, 'key', 3600, fn () !string {
    return compute()!
})!

// 永久记住
cache.remember_forever(mut cm, 'key', fn () !string {
    return compute()!
})!

// 批量操作
cache.put_many(mut cm, {'k1': 'v1', 'k2': 'v2'}, 3600)!
cache.get_many(mut cm, ['k1', 'k2'])          // map[string]string
cache.delete_many(mut cm, ['k1', 'k2'])!
cache.flush_all(mut cm)!
```

---

## 8. 锁

### 8.1 LockManager（命名锁）

```v
import photon.locking

mut lm := locking.new_lock_manager()

// 阻塞锁
lm.lock('database')
// ... 临界区 ...
lm.unlock('database')!

// 非阻塞尝试
if lm.try_lock('resource') {
    // 获得锁
    lm.unlock('resource')!
} else {
    // 锁被占用
}

// 超时锁
locked := lm.lock_with_timeout('resource', 500)!  // 500ms 超时
```

不同 key 独立互斥：

```v
lm.lock('a')     // 锁 a
lm.lock('b')     // 锁 b —— 不冲突
lm.try_lock('a') // false —— a 已锁
```

### 8.2 LockGuard（RAII 自动释放）

```v
{
    mut guard := locking.new_lock_guard(mut lm, 'critical-section')
    // ... 临界区 ...
    guard.unlock()           // 手动释放（安全，重复调用不会 panic）
}                             // 离开作用域
```

### 8.3 guarded_lock（函数式锁）

锁自动释放，即使函数报错：

```v
result := locking.guarded_lock[int](mut lm, 'my-lock', fn () !int {
    // 临界区代码
    return 42
})!
// 锁已自动释放，result == 42
```

### 8.4 分布式锁

```v
lm.with_distributed_lock(&my_redis_lock)    // 注册分布式后端

lm.dist_lock('global_resource', 30_000)!    // 获取，30 秒 TTL
// ... 分布式操作 ...
lm.dist_unlock('global_resource')!          // 释放
```

实现 `DistributedLock` 接口：

```v
pub interface DistributedLock {
    acquire(key string, ttl_ms int) !bool
    release(key string) !bool
    renew(key string, ttl_ms int) !bool
    is_locked(key string) bool
}
```

### 8.5 LocalMutex（原始互斥锁）

```v
mut mu := locking.new_mutex()
mu.lock()
mu.unlock()
mu.try_lock()    // bool
```

---

## 9. 队列

### 9.1 定义 Job

```v
import photon.queue

struct SendEmailJob {
    queue.Job
pub:
    to       string
    subject  string
    template string
}

fn (j &SendEmailJob) job_type() string { return 'send_email' }
fn (j &SendEmailJob) handle() ! {
    send_email(j.to, j.subject)!
}
fn (j &SendEmailJob) tries() int { return 3 }
fn (j &SendEmailJob) backoff() []i64 { return [i64(1), 5, 10] }
```

### 9.2 分发任务

```v
mut driver := queue.new_memory_driver()
mut d := queue.new_dispatcher(driver)

// 立即分发
d.driver.push(d.default_queue, queue.serialize_job('send_email', '{"to":"a@b.com"}'))!

// 全局便捷函数
queue.dispatch(my_job)!
queue.dispatch_later(my_job, 60)!           // 60 秒后执行
queue.dispatch_chain([job1, job2, job3])!   // 链式分发

batch_id := queue.dispatch_batch([job1, job2])!  // 批量分发，返回 batch_id
queue.count()                               // 队列任务数
queue.clear_queue()!                        // 清空队列
```

### 9.3 Worker

```v
mut w := queue.new_worker()
w.queue_name = 'emails'
w.sleep_secs = 3
w.run()           // 启动循环
w.tick()          // 处理一个任务
w.stop()          // 停止
w.is_running()    // bool
```

### 9.4 失败任务处理

```v
mut repo := queue.new_memory_failed_repo()
mut handler := queue.new_failed_job_handler(repo)

// 记录失败
handler.handle('send_email', payload, err_msg, 'default', 3)!

// 重试
handler.retry(failed_job_id)!
handler.retry_all()!          // 重试所有失败任务

// 查询
repo.all()!                   // []FailedJob
repo.count()                  // int
repo.find_by_id('id')!       // FailedJob
repo.delete_by_id('id')!
repo.clear()!
```

---

## 10. 连接池

### 10.1 通用对象池

```v
import photon.pool

mut p := pool.new_pool_with_config('db-pool', fn () !voidptr {
    return create_expensive_object()
}, 2, 10)     // min_size=2, max_size=10

p.initialize()!            // 预创建 2 个对象

obj := p.acquire()!        // 从池中获取（池空时自动新建）
// ... 使用对象 ...
p.release(obj)             // 归还池

stats := p.stats()
// PoolStats{name, total, active, idle, max_size, min_size, wait_count}

p.close()!                 // 销毁所有对象
p.acquire()                // 报错 —— 池已关闭
```

### 10.2 数据库连接池

```v
mut dp := pool.new_db_pool(.sqlite, 2, 10)
dp.initialize()!
conn := dp.acquire()!
dp.release(conn)
dp.driver_type()    // .sqlite
dp.stats()          // PoolStats
dp.close()!
```

---

## 11. 文件存储

### 11.1 StorageManager

```v
import photon.storage

mut mgr := storage.new_manager()
mgr.register('local', storage.new_local_adapter('/var/www/uploads'))
mgr.register('s3', storage.new_s3_adapter('my-bucket', 'us-east-1'))

disk := mgr.disk('local')!           // 获取适配器
mgr.has_disk('local')                // true
mgr.disk_names()                     // ['local', 's3']
```

### 11.2 文件操作

```v
// 写入
disk.write('hello.txt', 'Hello World', storage.public_options())!
disk.write('secret.txt', 'data', storage.default_options())!   // private

// 读取
content := disk.read('hello.txt')!

// 判断
disk.exists('hello.txt')              // bool

// 删除
disk.delete('hello.txt')!

// 复制 / 移动
disk.copy('a.txt', 'b.txt')!
disk.move('a.txt', 'c.txt')!

// 元数据
meta := disk.metadata('file.txt')!
meta.size           // i64
meta.mime_type      // string
meta.visibility     // .public_ 或 .private_
meta.last_modified  // i64

// 可见性
disk.set_visibility('file.txt', .public_)!
disk.visibility('file.txt')!          // .public_

// 目录操作
disk.create_directory('avatars')!
disk.delete_directory('avatars')!
disk.list_contents('avatars')!        // []&FileMetadata

// URL
disk.url('avatars/me.jpg')                    // 本地路径
disk.temporary_url('private.pdf', 3600)!      // 临时签名 URL

// 大小 & MIME
disk.size('file.txt')!                // i64
disk.mime_type('file.txt')!           // string
```

### 11.3 S3 适配器

```v
mut s3 := storage.new_s3_compatible_adapter('bucket', 'us-east-1', 'https://s3.example.com', 'AKID', 'SECRET')
s3.set_credentials('new_key', 'new_secret')   // 动态更换凭证
s3.bucket_url()                               // bucket URL
```

### 11.4 MIME 类型检测

```v
storage.detect_mime_type('/path/to/image.png')             // 'image/png'
storage.detect_mime_type_from_filename('report.pdf')       // 'application/pdf'
storage.is_image('image/png')                              // true
storage.is_video('video/mp4')                              // true
storage.is_audio('audio/mpeg')                             // true
storage.is_text('text/plain')                              // true
storage.extension_from_mime('application/json')            // 'json'
```

---

## 12. HTTP 客户端

### 12.1 Fluent Builder

```v
import photon.http

mut c := http.new_client()
c.with_base_url('https://api.example.com')
c.with_json()
c.with_token('my-jwt-token')
c.retry(3, 100)          // 重试 3 次，间隔 100ms
c.timeout_sec(60)         // 超时 60 秒

// 请求
resp := c.get('/users')!
resp := c.post('/users', '{"name":"Alice"}')!
resp := c.put('/users/1', '{"name":"Bob"}')!
resp := c.delete('/users/1')!
resp := c.patch('/users/1', '{"role":"admin"}')!

// 响应
resp.status_code        // int
resp.body               // string
resp.headers            // map[string]string
resp.is_success()       // 2xx
resp.is_client_error()  // 4xx
resp.is_server_error()  // 5xx
```

### 12.2 认证方式

```v
// Bearer Token
c.with_token('my-jwt')

// Basic Auth
c.with_basic_auth('admin', 'secret')

// 自定义 Header
c.with_header('X-API-Key', 'abc123')
```

---

## 13. CLI 工具

### 13.1 创建 CLI 应用

```v
import photon.cli

mut app := cli.new_application('myapp', '1.0.0')
app.add_command(cli.new_serve_command())
app.add_command(cli.new_list_command(app))
app.add_command(cli.new_help_command(app))
app.add_command(cli.new_schedule_command(my_schedule))
app.add_command(cli.new_queue_work_command(my_runner))
app.run()!
```

### 13.2 自定义命令

```v
struct GreetCommand {
    cli.BaseCommand
}

fn (c &GreetCommand) name() string { return 'greet' }
fn (c &GreetCommand) description() string { return 'Say hello' }
fn (c &GreetCommand) signature() string { return 'greet {name} [--shout]' }

fn (c &GreetCommand) execute(input &cli.CommandInput, output &cli.CommandOutput) ! {
    name := input.get_arg(0)
    msg := 'Hello, ${name}!'
    if input.has_flag('shout') {
        output.success(msg.to_upper())
    } else {
        output.success(msg)
    }
}

app.add_command(&GreetCommand{BaseCommand: cli.BaseCommand{name: 'greet'}})
```

### 13.3 解析输入

```v
input := cli.new_input(['greet', 'Alice', '--shout', '--lang=en'])
input.command_name           // 'greet'
input.get_arg(0)             // 'Alice'
input.has_flag('shout')      // true
input.get_option('lang')     // 'en'
input.get_option_or('port', '3000')  // 带默认值
input.arg_count()            // 1
```

### 13.4 输出格式

```v
output := cli.new_output()
output.success('操作成功')     // 绿色
output.error('操作失败')       // 红色
output.warning('警告')         // 黄色
output.info('提示')           // 蓝色
output.title('标题')
output.section('段落')
output.table(['Name', 'Age'], [['Alice', '30'], ['Bob', '25']])
output.line(40)               // 分隔线
```

### 13.5 交互式输入

```v
answer := cli.ask('请输入名称: ')
confirmed := cli.confirm('确认删除？(y/n): ')
password := cli.secret('请输入密码: ')
idx := cli.choice('选择颜色:', ['红', '蓝', '绿'])
answer := cli.ask_with_default('端口', '8080')
val := cli.anticipate('框架', ['Photon', 'Spring', 'Django'])
```

### 13.6 进度条

```v
mut pb := cli.new_progress_bar(100)
for i in 0 .. 100 {
    pb.advance(1)
}
pb.set(75)
pb.finish()
```

### 13.7 代码生成命令

```bash
make:command SendEmail       # 生成命令
make:controller User         # 生成控制器
make:middleware Auth         # 生成中间件
make:provider Database       # 生成服务提供者
make:entity Product          # 生成实体
```

### 13.8 终端颜色

```v
cli.bold_text('醒目')        // 加粗
cli.red_text('错误')         // 红色
cli.green_text('成功')       // 绿色
cli.yellow_text('警告')      // 黄色
cli.blue_text('信息')        // 蓝色
cli.cyan_text('链接')        // 青色
cli.magenta_text('特殊')     // 品红
cli.gray_text('次要')        // 灰色
cli.success_text('完成')     // 绿色加粗
cli.error_text('失败')       // 红色加粗
cli.pad_right('hi', 10)     // 右填充
```

---

## 14. 定时器

### 14.1 Timer（一次性）

```v
import photon.ticker
import time

t := ticker.new_timer(5 * time.second)
<-t.c                    // 阻塞等待
t.reset(3 * time.second) // 重置
t.stop()                 // 停止
```

### 14.2 Ticker（周期性）

```v
tk := ticker.new_ticker(500 * time.millisecond)
for _ in 0 .. 5 {
    <-tk.c
    println('tick')
}
tk.stop()
```

### 14.3 便捷函数

```v
ticker.sleep(2 * time.second)       // 阻塞睡眠
ch := ticker.after(3 * time.second) // 返回 channel，到时触发
ch2 := ticker.tick(1 * time.second) // 周期性 channel
```

### 14.4 延迟执行

```v
ticker.after_func(5 * time.second, fn () {
    println('5 秒后执行')
})
```

> 性能：4-ary 最小堆 + 64 桶分片，零外部依赖。

---

## 15. 工具库

### 15.1 Collection（链式集合）

```v
import photon.support

c := support.collect([1, 2, 3, 4, 5])

// 过滤 + 映射
result := c.filter(fn (n int) bool { return n > 2 })
    .map(fn (n int) string { return n.str() })
    .all()                                          // ['3', '4', '5']

// 聚合
c.first(0)                              // 1
c.last(0)                               // 5
c.count()                               // 5
c.is_empty()                            // false
c.reduce(0, fn (acc int, n int) int { return acc + n })  // 15

// 切分
c.chunk(2)                              // [[1,2], [3,4], [5]]
c.take(3)                               // [1,2,3]
c.skip(2)                               // [3,4,5]
c.slice(1, 4)                           // [2,3,4]

// 排序 & 反转
c.sort_by(fn (n int) int { return -n })  // [5,4,3,2,1]
c.reverse()                              // [5,4,3,2,1]

// 分组
c.group_by(fn (n int) string { return if n % 2 == 0 { 'even' } else { 'odd' } })
// {'odd': [1,3,5], 'even': [2,4]}

c.key_by(fn (n int) string { return n.str() })
// {'1': 1, '2': 2, ...}

// 判断
c.contains(fn (n int) bool { return n == 3 })    // true
c.every(fn (n int) bool { return n > 0 })        // true
c.some(fn (n int) bool { return n > 4 })         // true

// 遍历
c.each(fn (n int) { println(n) })

// 修改
mut c2 := support.collect([1, 2])
c2.push(3)
c2.transform(fn (n int) int { return n * 2 })

// 合并
c.merge(support.collect([6, 7]))
c.concat([6, 7])

// 输出
c.to_json()                             // '[1,2,3,4,5]'
c.join(', ')                            // '1, 2, 3, 4, 5'

// 管道
c.tap(fn (col &support.Collection[int]) { println(col.count()) })
total := c.pipe(fn (col support.Collection[int]) int { return col.count() })
```

### 15.2 分页

```v
// 完整分页（含总数）
mut p := support.new_paginator[int](items, 100, 20, 1)
p.has_more_pages()    // true
p.on_first_page()     // true
p.on_last_page()      // false
p.count()             // 当前页条数
p.from()              // 起始序号
p.to()                // 结束序号
p.next_page_url()     // '?page=2'
p.prev_page_url()     // ''
p.to_json()           // JSON

// 简单分页（不含总数，适合大数据集）
sp := support.new_simple_paginator[int](items, 20, 1, true)
sp.has_more            // true
```

### 15.3 排序

```v
s := support.by('name').ascending().and(support.by_desc('created_at'))
s.to_sql()             // 'name ASC, created_at DESC'
s.is_empty()           // false
s.is_sorted()          // true
```

### 15.4 分页请求

```v
pr := support.page_request(1, 20)
pr.get_offset()        // 0
pr.get_page_number()   // 1
pr.get_page_size()     // 20
pr.has_previous()      // false
pr.next()              // PageRequest{page:2, size:20}

pr2 := support.page_request_with_sort(1, 20, support.by_desc('created_at'))
pr2.get_sort()         // Sort
```

### 15.5 Str（字符串工具）

```v
import photon.support

support.slug('Hello World')                // 'hello-world'
support.snake('camelCase')                 // 'camel_case'
support.camel('hello world')               // 'helloWorld'
support.studly('hello_world')              // 'HelloWorld'
support.kebab('Hello World')               // 'hello-world'
support.limit('Long text here', 8)         // 'Long tex...'
support.words('one two three four', 2)     // 'one two'
support.contains('hello world', 'world')   // true
support.starts_with('hello', 'he')         // true
support.ends_with('hello', 'llo')          // true
support.after('hello@world.com', '@')      // 'world.com'
support.before('hello@world.com', '@')     // 'hello'
support.between('(abc)', '(', ')')         // 'abc'
support.finish('path/', '/')               // 'path/'（确保以指定字符结尾）
support.replace_first('abcabc', 'b', 'X')  // 'aXcabc'
support.replace_last('abcabc', 'b', 'X')   // 'abcabX'
support.random(16)                         // 随机字符串
support.mask('13812345678', '*', 3, 4)     // '138****5678'
support.is_json('{"ok":true}')             // true
support.lower('HELLO')                     // 'hello'
support.upper('hello')                     // 'HELLO'
support.title('hello world')               // 'Hello World'
```

### 15.6 Arr（数组/Map 工具）

```v
// Map 操作
support.get_string(my_map, 'key', 'default')
support.set_string(mut my_map, 'key', 'value')
support.forget_string(mut my_map, 'key')
support.has_string(my_map, 'key')
support.only_string(my_map, ['name', 'email'])       // 只保留指定 key
support.except_string(my_map, ['password'])          // 排除指定 key
support.pluck([{'name':'A'}, {'name':'B'}], 'name')  // ['A', 'B']
support.merge_string(map1, map2)                     // 合并
support.keys_string(my_map)                          // []string
support.values_string(my_map)                        // []string

// 数组操作
support.first([1,2,3], fn (n int) bool { return n > 1 }, 0)  // 2
support.last([1,2,3], fn (n int) bool { return n > 1 }, 0)   // 3
support.filter_items([1,2,3], fn (n int) bool { return n > 1 })  // [2,3]
support.flatten([[1,2], [3,4]])                       // [1,2,3,4]
support.chunk([1,2,3,4,5], 2)                         // [[1,2],[3,4],[5]]
support.shuffle([1,2,3])
support.unique_string(['a', 'b', 'a'])               // ['a', 'b']
support.reverse([1,2,3])                              // [3,2,1]
support.take([1,2,3,4,5], 3)                          // [1,2,3]
support.skip([1,2,3,4,5], 2)                          // [3,4,5]
```

---

## 16. 注解速查

| 注解 | 作用域 | 说明 |
|------|--------|------|
| `@[component]` | struct | 标记组件 |
| `@[service]` | struct | 标记服务 |
| `@[repository]` | struct | 标记仓库 |
| `@[controller]` | struct | 标记控制器 |
| `@[configuration]` | struct | 标记配置类 |
| `@[autowired]` | field | 自动注入 |
| `@[value('key')]` | field | 注入配置值，支持 `key:default` |
| `@[qualifier('name')]` | field | 按名称注入 |
| `@[post_construct]` | fn | 初始化回调 |
| `@[pre_destroy]` | fn | 销毁回调 |
| `@[lazy]` | struct/fn | 延迟初始化 |
| `@[scope('singleton')]` | struct | 单例（默认） |
| `@[scope('prototype')]` | struct | 每次注入新实例 |
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
| `@[primary_key]` | field | ORM 主键 |
| `@[sql: 'col_name']` | field | SQL 列名映射 |
| `@[sql_type: 'TEXT']` | field | SQL 类型映射 |

---

## 完整应用示例

把所有模块串起来的真实应用：

```v
import veb
import photon.core
import photon.config
import photon.log
import photon.security
import photon.cli
import photon.web
import photon.orm
import photon.cache
import photon.locking
import photon.queue

struct DemoUser {
    orm.BaseEntity
pub mut:
    name  string
    email string
}

fn start_server() {
    // 配置
    mut cfg := config.new()
    cfg.set_profile(['dev'])
    cfg.add_source(config.MapConfigSource{
        data: {
            'app.name':    'PhotonApp'
            'server.port': '8080'
            'jwt.secret':  'your-256-bit-secret-key-here-min-32-chars!!'
        }
    })
    cfg.load()!

    // 日志
    mut logger := log.new()
    logger.set_level(.debug)
    logger.set_colored(true)
    logger.put('app', cfg.get('app.name'))

    // 安全
    jwt_cfg := security.JwtConfig{
        secret:             cfg.get_or('jwt.secret', 'default-secret!!')
        expiration_minutes: 60
    }
    jwt_mgr := security.new_jwt_manager(jwt_cfg)

    mut user_svc := security.new_in_memory_service()
    user_svc.add_user(security.new_user('admin', 'admin123', ['ADMIN']))

    mut auth_mgr := security.new_auth_manager()
    auth_mgr.add_provider(&security.JwtAuthenticationProvider{jwt_manager: jwt_mgr})

    mut sec_chain := security.new_security_filter_chain(auth_mgr, jwt_mgr,
        security.new_csrf_manager(security.CsrfConfig{enabled: true}))
    sec_chain.with_permit_all('/')
    sec_chain.with_permit_all('/api/auth/login')
    sec_chain.with_secured('/api/users')
    sec_chain.with_roles('/api/admin', ['ADMIN'])

    // 缓存
    mut cm := cache.new_cache_manager()

    // 锁
    mut lm := locking.new_lock_manager()

    // 队列
    mut driver := queue.new_memory_driver()
    mut disp := queue.new_dispatcher(driver)

    // 中间件
    mut chain := web.new_chain()
    chain.use(web.request_id_middleware)
    chain.use(web.logging_middleware)
    chain.use(web.cors_middleware)
    chain.use(web.request_id_cleanup_middleware)

    // ORM
    mut om := orm.new_orm_manager()
    om.register_connection('default', .sqlite, voidptr(0))!

    logger.info('应用初始化完成')

    port := cfg.get_int_or('server.port', 8080)
    veb.run[App](port)
}

pub struct App {
    veb.Context
pub mut:
    logger   &log.Logger = log.new()
    jwt_mgr  &security.JwtManager
    csrf_mgr &security.CsrfManager
}

@[get; '/']
pub fn (mut app App) index() veb.Result {
    return app.text('Hello Photon')
}

@[post; '/api/auth/login']
pub fn (mut app App) login() veb.Result {
    token := app.jwt_mgr.create_token('admin', ['ADMIN']) or {
        return app.text('{"error":"auth failed"}')
    }
    csrf := app.csrf_mgr.create_token() or { return app.text('{"error":"csrf"}') }
    return app.text('{"token":"${token}","csrf":"${csrf.token}"}')
}

@[get; '/api/users']
pub fn (mut app App) user_list() veb.Result {
    return app.text('{"users":[{"id":1,"name":"Alice"}]}')
}

@[get; '/api/admin']
pub fn (mut app App) admin_dashboard() veb.Result {
    return app.text('{"dashboard":"admin"}')
}

fn main() {
    mut app := cli.new_application('photon', '0.1.0')
    app.add_command(cli.new_serve_command())
    app.add_command(cli.new_list_command(app))
    app.add_command(cli.new_help_command(app))
    app.run() or { panic(err) }
}
```

---

> **Photon Framework** — 用 V 语言构建企业应用，本该如此简单。
