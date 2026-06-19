# Demo 骨架项目升级（对标 Laravel）Spec

## Why

当前 `Demo/` 项目功能完整（16 模块全覆盖、29 端点、9 命令、180 测试），但深度审查发现其**未充分利用框架已提供的大量高级抽象**：手写 JSON 字符串拼接、内联校验、`unsafe { voidptr(x) }` 类型擦除 DI、手写分页、God Function 装配、硬编码中间件参数、缺 `.env` 与 `config/` 目录、Makefile 仅 8 个 target。与 Laravel / Spring Boot Starter 骨架的"低心智成本、声明式编程、开箱即用"标准差距显著。框架能力（`web.validate[T]`、`web.Result`、`web.ExceptionHandlerRegistry`、`web.MiddlewareGroupRegistry`、`core.ServiceProvider`、`support.LengthAwarePaginator`、`orm.EagerLoader`、`orm.@[transactional]`、`cache.Singleflight`、`cache.TaggedCache`、`cli.make:*`）均已就绪，Demo 主要是"未采用"而非"框架缺失"。

本变更将 Demo 升级为**生产级骨架项目**：采用框架高级能力消除重复代码、补齐 Laravel 级工程化结构（`.env`、`config/`、`routes/`、`providers/`、`database/migrations/`、`database/seeders/`、`app/Http/Resources/`）、生成覆盖全生命周期的 Make 脚本集（setup/dev/build/release/run/test/migrate/seed/queue/scheduler/lint/docker/clean/help），并完善文档与 API 文档自动生成。

## What Changes

### 架构与工程化重构
- 新增 `.env.example` / `.env` / `.env.dev` / `.env.prod` / `.env.testing` 环境文件，集成 `config.Environment` + `PropertySource` 自动加载
- 新增 `config/` 目录，按关注点拆分配置文件（`app.v`/`database.v`/`jwt.v`/`cache.v`/`mail.v`/`storage.v`/`logging.v`/`web.v`）
- 新增 `routes/` 目录，分离路由定义（`web.v`/`api.v`），支持路由分组与中间件组绑定
- 新增 `providers/` 目录，将 `bootstrap.v` 的 God Function 拆分为 `core.ServiceProvider` 实现（`AppServiceProvider`/`DatabaseServiceProvider`/`CacheServiceProvider`/`WebServiceProvider`/`AuthServiceProvider`/`QueueServiceProvider`/`EventServiceProvider`）
- 新增 `helpers.v` 集中工具函数（`generate_request_id`/`generate_slug`/`cache_remember`/`now_unix` 等）
- 新增 `bootstrap/app.v`，作为应用启动入口（注册 Provider、加载配置、初始化内核）

### Web 层升级（采用框架高级抽象）
- 控制器响应改用 `web.Result` / `web.success` / `web.fail` / `web.page` / `web.ok` / `web.created` / `web.bad_request` 等，**移除所有手写 JSON 字符串拼接**
- 控制器校验改用 `web.validate[T]` / `web.validate_body[T]` + DTO 标注 `@[validate: 'required|email|min_len:3']`，**移除所有内联 `if dto.x.len == 0` 校验**
- 异常处理改用 `web.HttpException` 体系（`BadRequestException`/`NotFoundException`/`ValidationException`/`UnauthorizedException`/`ForbiddenException`）+ `ExceptionHandlerRegistry` 统一处理，**移除所有 `ctx.send_err(...)` 手写错误响应**
- 中间件改用 `web.MiddlewareGroupRegistry` 命名组（`web`/`api`/`auth`/`admin`），**移除自造 `MiddlewareManager`**
- 中间件参数化改用 `web.throttle_middleware`/`web.role_middleware`/`web.cors_configurable_middleware`，配置驱动
- 新增 `app/Http/Resources/` 目录，实现 `UserResource`/`PostResource`/`CommentResource` 等 API Resource，**隐藏 `password`/`version` 等内部字段**
- 分页改用 `support.LengthAwarePaginator[T]`，**移除手写 `start..end` 切片**

### ORM 与数据层升级
- 仓储查询改用 `orm.EagerLoader[T]` + `with()` 防 N+1（文章列表预加载 author/category/tags）
- 多步操作改用 `orm.TransactionManager` + `@[transactional]` 注解（文章发布、评论创建、用户注册）
- 软删除改用 `orm.SoftDeletableEntity`（`deleted_at` 字段），统一软删除语义
- 仓储派生查询下沉过滤/排序到 SQL 层（`WHERE`/`ORDER BY`），**移除控制器内存过滤**
- 新增 `database/migrations/` 目录，一文件一迁移（时间戳命名 `20260101000001_create_users_table.v`）
- 新增 `database/seeders/` 目录与 Seeder 类（`DatabaseSeeder`/`UserSeeder`/`PostSeeder`/`CommentSeeder`），**移除 `commands.v` 内联种子逻辑**
- 新增 `database/factories/` 目录与 Factory 类（`UserFactory`/`PostFactory`），用于测试数据生成

### 缓存与锁升级
- 缓存读取改用 `cache.get_or_load()` + `Singleflight` 削峰，**移除手写 `if cm.has(key) {...} else {...}` 模式**
- 缓存失效改用 `cache.TaggedCache` 标签批量失效（`posts`/`users`/`stats` 标签）
- 新增 `cache_remember(key, ttl, loader)` 辅助函数，统一缓存模式
- 锁改用 `locking.LockGuard` / `locking.guarded_lock[T]()` RAII，**移除手写 lock/unlock**
- 服务方法标注 `@[cacheable]` 注解（如 `StatsService.get_stats`）

### 安全升级
- 集成 `security.CsrfProtection`（Web 表单场景）
- 集成 `security.SecurityFilterChain` 统一过滤链
- `User.password` 字段私有化，仅通过 `BcryptHasher` 校验，API Resource 不输出
- JWT 密钥生产环境强制校验（默认密钥启动失败）
- 角色层级由配置驱动（`config/auth.v`）

### CLI 命令升级
- 集成 `cli.make:*` 代码生成命令（`make:controller`/`make:model`/`make:migration`/`make:middleware`/`make:provider`/`make:command`）
- 命令补充签名参数定义（`sig: '[--port=8080] [--host=0.0.0.0]'`）
- 新增 `migrate:fresh`/`migrate:refresh`/`migrate:reset` 命令注册
- `ServeCommand.execute` 实际启动服务（移除空实现误导）
- 种子数据配置驱动（账号/密码从 `config` 或 `.env` 读取）

### Make 脚本集（全生命周期）
- 重写 `Makefile`，覆盖 30+ target：`setup`/`dev`/`build`/`build-release`/`release`/`run`/`serve`/`test`/`test-unit`/`test-integration`/`test-coverage`/`migrate`/`migrate-rollback`/`migrate-refresh`/`migrate-fresh`/`migrate-reset`/`migrate-status`/`seed`/`seed-fresh`/`queue-work`/`queue-restart`/`scheduler-run`/`routes`/`stats`/`lint`/`fmt`/`check`/`docker`/`docker-up`/`docker-down`/`docker-logs`/`clean`/`clean-all`/`install`/`uninstall`/`release-package`/`benchmark`/`watch`/`db-shell`/`logs`/`shell`/`help`
- `help` target 自动从 target 注释生成
- 区分 `dev`/`prod` 构建标志（`-gc boehm`/`-cflags "-O2"`/`-d release`）
- 新增 `docker-compose.yml`（多服务编排：app/db/redis/queue/scheduler）
- 新增 `.env.example` 作为环境变量模板

### 文档与 API 文档
- 集成 `apidoc` 模块，自动生成 OpenAPI/Swagger 风格 API 文档
- 新增 `docs/api/` 目录存放生成的 API 文档
- 完善 `README.md`：环境搭建、架构图、API 文档链接、部署指南、故障排查
- 新增 `CONTRIBUTING.md`、`CHANGELOG.md`、`LICENSE`
- 新增 `docs/architecture.md` Demo 级架构文档（数据流、调用链、设计决策）

### 测试升级
- 新增 `tests/` 目录与测试基类 `TestCase`（封装 `web.TestResponse` + `RefreshDatabase` trait）
- 测试数据改用 Factory 生成，**移除内联 `seed_user` 重复代码**
- 新增 `tests/TestCase.v` 提供 `refresh_database()`/`acting_as(user)`/`json_request(method, path, body)` 辅助
- 测试覆盖率报告生成

### **BREAKING** 变更
- 控制器响应格式微调：分页响应追加 Laravel 风格元数据（`meta`/`links`），保留 `data`/`total`/`current_page`/`last_page`/`has_more` 向后兼容
- 软删除语义变更：`User.status=-1` 改为 `deleted_at IS NOT NULL`，需新增迁移添加 `deleted_at` 列
- `MiddlewareManager` 移除，改用 `web.MiddlewareGroupRegistry`（外部调用方需更新）
- 配置加载方式变更：从内联 map 改为 `config/` 目录文件 + `.env` 覆盖

## Impact

- Affected specs: `create-demo-project`（原 Demo 创建 spec，本次为其升级版）
- Affected code:
  - `Demo/` 全部源文件重构（保留功能，升级实现）
  - 新增 `Demo/config/`、`Demo/routes/`、`Demo/providers/`、`Demo/app/Http/Resources/`、`Demo/database/migrations/`、`Demo/database/seeders/`、`Demo/database/factories/`、`Demo/tests/`、`Demo/docs/` 目录
  - 重写 `Demo/Makefile`、新增 `Demo/docker-compose.yml`、`Demo/.env.example`
  - 不修改 `/workspace/` 框架模块代码（仅消费已存在 API）
- 依赖模块：core, config, logger, cache, orm, web, security, queue, locking, pool, storage, ticker, http, support, cli, mailer, apidoc（17 个模块，新增 apidoc）

## ADDED Requirements

### Requirement: 环境文件与多源配置

系统 SHALL 通过 `config.Environment` + `PropertySource` 加载 `.env` 文件，支持 `.env`/`.env.dev`/`.env.prod`/`.env.testing` 多环境文件，环境变量覆盖配置文件值。

#### Scenario: 加载 .env 文件
- **WHEN** 应用启动且 `Demo/.env` 文件存在
- **THEN** `.env` 中所有 `KEY=VALUE` 被加载为环境变量，配置可通过 `${KEY}` 占位符引用

#### Scenario: 环境特定文件覆盖
- **WHEN** `APP_PROFILE=prod` 启动且 `.env.prod` 存在
- **THEN** `.env.prod` 的值覆盖 `.env` 的同名键

#### Scenario: 生产环境密钥强制校验
- **WHEN** `APP_PROFILE=prod` 且 `JWT_SECRET` 为默认值或空
- **THEN** 应用启动失败，输出错误："生产环境必须设置 JWT_SECRET 环境变量"

### Requirement: 配置目录与按关注点拆分

系统 SHALL 提供 `config/` 目录，按关注点拆分配置文件：`app.v`/`database.v`/`jwt.v`/`cache.v`/`mail.v`/`storage.v`/`logging.v`/`web.v`/`auth.v`，每个文件返回对应配置结构体。

#### Scenario: 加载配置目录
- **WHEN** 应用启动调用 `load_config('prod')`
- **THEN** 读取 `config/*.v` 所有文件，合并为 `AppConfig`，`.env` 覆盖最终值

#### Scenario: 配置占位符解析
- **WHEN** `config/database.v` 中 `path: '${DB_PATH}'`
- **THEN** `Environment.resolve_placeholders` 解析为 `.env` 中 `DB_PATH` 的值

### Requirement: 服务提供者模式

系统 SHALL 使用 `core.ServiceProvider` 接口拆分启动装配，每个 Provider 负责一个领域的 Bean 注册与初始化，通过 `ProviderRegistry.register_all()` + `boot_all()` 按序执行。

#### Scenario: Provider 注册与启动
- **WHEN** 应用启动执行 `bootstrap/app.v`
- **THEN** `AppServiceProvider`/`DatabaseServiceProvider`/`CacheServiceProvider`/`WebServiceProvider`/`AuthServiceProvider`/`QueueServiceProvider`/`EventServiceProvider` 按 `register()` → `boot()` 顺序执行

#### Scenario: Provider 延迟加载
- **WHEN** Provider 实现 `DeferredServiceProvider`
- **THEN** 仅在对应 Bean 首次被请求时实例化

### Requirement: 统一响应封装

系统 SHALL 使用 `web.Result` / `web.PageResult` 作为所有 API 响应的唯一出口，通过 `web.success`/`web.fail`/`web.page`/`web.ok`/`web.created`/`web.bad_request`/`web.not_found`/`web.unauthorized`/`web.forbidden` 构造，**禁止控制器内手写 JSON 字符串**。

#### Scenario: 成功响应
- **WHEN** 控制器返回 `web.success(json.encode(data))`
- **THEN** 响应体为 `{"success":true,"code":200,"message":"success","data":...,"timestamp":...}`

#### Scenario: 分页响应
- **WHEN** 控制器返回 `web.page(json.encode(items), page, page_size, total)`
- **THEN** 响应体包含 `data`/`page`/`page_size`/`total`/`last_page`/`has_more` 字段

### Requirement: 表单请求验证

系统 SHALL 使用 `web.validate[T]` / `web.validate_body[T]` + DTO 标注 `@[validate: 'required|email|min_len:3|max_len:255']` 进行声明式校验，校验失败抛出 `ValidationException` 由异常处理器统一响应。

#### Scenario: 校验失败
- **WHEN** POST `/api/v1/auth/register` 提交 `email` 字段格式错误
- **THEN** 返回 422，响应体 `{"success":false,"code":422,"message":"Validation failed","errors":{"email":["email format invalid"]}}`

#### Scenario: 校验通过
- **WHEN** DTO 所有字段通过校验规则
- **THEN** 返回解码后的 DTO，控制器直接使用

### Requirement: 统一异常处理

系统 SHALL 使用 `web.ExceptionHandlerRegistry` 注册全局异常处理器，捕获 `HttpException` 体系（`BadRequestException`/`NotFoundException`/`ValidationException`/`UnauthorizedException`/`ForbiddenException`/`ConflictException`/`RateLimitExceededException`）并转换为统一响应格式。

#### Scenario: 未捕获异常
- **WHEN** 控制器抛出 `NotFoundException`
- **THEN** 异常处理器捕获，返回 404 + `{"success":false,"code":404,"message":"..."}`

#### Scenario: 未知异常
- **WHEN** 控制器抛出非 `HttpException` 异常
- **THEN** 默认处理器返回 500 + `{"success":false,"code":500,"message":"Internal Server Error"}`，生产环境隐藏堆栈

### Requirement: 中间件组与别名

系统 SHALL 使用 `web.MiddlewareGroupRegistry` 注册命名中间件组（`web`/`api`/`auth`/`admin`），路由通过组名绑定中间件链，**移除自造 `MiddlewareManager`**。

#### Scenario: 路由绑定中间件组
- **WHEN** 路由声明 `middleware: ['api', 'auth']`
- **THEN** 请求依次经过 `api` 组（CORS+RequestId+RequestLog+RateLimit）和 `auth` 组（JwtAuth）

#### Scenario: 参数化中间件
- **WHEN** 路由声明 `middleware: ['throttle:120,1']`
- **THEN** `parse_middleware_params` 解析为 `max_attempts=120, decay_minutes=1`，应用限流

### Requirement: API Resource 转换层

系统 SHALL 提供 `app/Http/Resources/` 目录，每个实体对应一个 Resource 类（`UserResource`/`PostResource`/`CommentResource`/`CategoryResource`/`TagResource`），负责实体到响应数组的转换与字段脱敏。

#### Scenario: 字段脱敏
- **WHEN** `UserResource(user).to_json()` 序列化
- **THEN** 输出 `id`/`username`/`email`/`nickname`/`avatar`/`role`/`status`/`created_at`，**不输出 `password`/`version`**

#### Scenario: 关系嵌套
- **WHEN** `PostResource(post).with(['author', 'category', 'tags'])`
- **THEN** 输出包含嵌套的 `author`/`category`/`tags` Resource

### Requirement: ORM 预加载与事务

系统 SHALL 使用 `orm.EagerLoader[T]` + `with()` 预加载关联防止 N+1 查询，使用 `orm.TransactionManager` + `@[transactional]` 注解保证多步操作原子性。

#### Scenario: 预加载关联
- **WHEN** 查询文章列表 `repo.with(['author', 'category']).find_all()`
- **THEN** 仅执行 3 条 SQL（文章 + 作者 IN + 分类 IN），非 N+1 条

#### Scenario: 事务回滚
- **WHEN** `@[transactional]` 标注的方法内某步失败
- **THEN** 事务自动回滚，已执行的操作全部撤销

### Requirement: 软删除统一语义

系统 SHALL 使用 `orm.SoftDeletableEntity`（`deleted_at` 字段）实现软删除，所有查询自动过滤 `deleted_at IS NULL`，`delete()` 设置 `deleted_at` 而非物理删除。

#### Scenario: 软删除查询过滤
- **WHEN** 查询 `User.find_all()`
- **THEN** 自动追加 `WHERE deleted_at IS NULL`，已软删除记录不返回

#### Scenario: 软删除恢复
- **WHEN** 调用 `repo.restore(id)`
- **THEN** `deleted_at` 置空，记录重新可见

### Requirement: 缓存削峰与标签失效

系统 SHALL 使用 `cache.get_or_load()` + `Singleflight` 实现缓存击穿保护，使用 `cache.TaggedCache` 实现标签批量失效，使用 `@[cacheable]` 注解声明式缓存。

#### Scenario: 缓存击穿保护
- **WHEN** 100 个并发请求同时访问未缓存的文章详情
- **THEN** 仅 1 个请求查数据库，其余 99 个等待 singleflight 结果

#### Scenario: 标签批量失效
- **WHEN** 文章更新后调用 `tagged_cache.flush('posts')`
- **THEN** 所有 `posts` 标签下的缓存条目（`post:1`/`post:2`/`posts:list`）全部清除

#### Scenario: 声明式缓存
- **WHEN** `StatsService.get_stats()` 标注 `@[cacheable]`
- **THEN** 首次调用执行方法体并缓存结果，后续调用直接返回缓存

### Requirement: 锁守卫 RAII

系统 SHALL 使用 `locking.LockGuard` / `locking.guarded_lock[T]()` 实现锁的自动释放，**移除手写 lock/unlock**。

#### Scenario: 自动解锁
- **WHEN** 使用 `guard := locking.new_lock_guard(mut lm, 'post:publish:1')`
- **THEN** 离开作用域自动解锁，即使发生异常也不死锁

### Requirement: 路由分离与分组

系统 SHALL 提供 `routes/` 目录分离路由定义（`web.v`/`api.v`），支持路由分组（前缀、中间件组、命名空间），控制器通过注解路由注册。

#### Scenario: 路由分组
- **WHEN** `routes/api.v` 定义 `Route::group(['prefix' => 'api/v1', 'middleware' => ['api', 'auth']], fn() { ... })`
- **THEN** 组内所有路由自动添加 `/api/v1` 前缀和 `api`+`auth` 中间件

### Requirement: 数据库迁移目录化

系统 SHALL 提供 `database/migrations/` 目录，每个迁移一个文件，文件名遵循 `YYYYMMDDHHMMSS_create_xxx_table.v` 命名约定，迁移管理器自动扫描目录加载。

#### Scenario: 自动扫描迁移
- **WHEN** 执行 `./demo migrate`
- **THEN** 扫描 `database/migrations/*.v`，按文件名时间戳排序执行未应用的迁移

#### Scenario: 迁移状态
- **WHEN** 执行 `./demo migrate:status`
- **THEN** 输出表格：迁移名 / 批次 / 是否已应用

### Requirement: 数据库种子与工厂

系统 SHALL 提供 `database/seeders/` 目录与 Seeder 类（`DatabaseSeeder`/`UserSeeder`/`PostSeeder`/`CommentSeeder`），提供 `database/factories/` 目录与 Factory 类用于测试数据生成。

#### Scenario: 种子数据
- **WHEN** 执行 `./demo seed`
- **THEN** `DatabaseSeeder` 按依赖顺序调用 `UserSeeder`/`PostSeeder`/`CommentSeeder`，插入配置驱动的种子数据

#### Scenario: 工厂生成测试数据
- **WHEN** 测试调用 `UserFactory.new().create()`
- **THEN** 生成并保存一个随机属性的用户，返回 `User` 实体

### Requirement: CLI 代码生成命令

系统 SHALL 集成 `cli.make:*` 命令，提供 `make:controller`/`make:model`/`make:migration`/`make:middleware`/`make:provider`/`make:command`/`make:resource`/`make:seeder`/`make:factory` 代码生成能力。

#### Scenario: 生成控制器
- **WHEN** 执行 `./demo make:controller PostController`
- **THEN** 在 `app/Http/Controllers/` 生成 `post_controller.v`，包含 RESTful 方法骨架

#### Scenario: 生成迁移
- **WHEN** 执行 `./demo make:migration create_posts_table`
- **THEN** 在 `database/migrations/` 生成带时间戳前缀的迁移文件，包含 `up()`/`down()` 骨架

### Requirement: Make 脚本全生命周期覆盖

系统 SHALL 提供 `Makefile` 覆盖项目全生命周期 30+ target，按类别分组：环境初始化（setup/install）、开发（dev/run/serve/watch）、构建（build/build-release/release）、测试（test/test-unit/test-integration/test-coverage）、数据库（migrate/migrate-rollback/migrate-refresh/migrate-fresh/migrate-reset/migrate-status/seed/seed-fresh）、运行时（queue-work/queue-restart/scheduler-run/routes/stats）、代码质量（lint/fmt/check）、容器化（docker/docker-up/docker-down/docker-logs）、清理（clean/clean-all/distclean）、发布（release-package）、辅助（db-shell/logs/shell/help）。

#### Scenario: 一键初始化
- **WHEN** 执行 `make setup`
- **THEN** 检查 V 编译器、加载 `.env`、编译项目、执行迁移、运行种子

#### Scenario: 开发热重载
- **WHEN** 执行 `make dev`
- **THEN** 以 watch 模式启动，文件变更自动重新编译重启

#### Scenario: 生产构建
- **WHEN** 执行 `make release`
- **THEN** 以 `-d release -cflags "-O2"` 编译优化二进制到 `bin/demo`

#### Scenario: 自动生成帮助
- **WHEN** 执行 `make help`
- **THEN** 从 target 注释自动生成分类帮助列表

### Requirement: Docker Compose 多服务编排

系统 SHALL 提供 `docker-compose.yml` 编排多服务：`app`（Web 服务）、`db`（SQLite/PostgreSQL）、`redis`（缓存/队列）、`queue`（队列 Worker）、`scheduler`（定时调度器），支持 `docker-compose up -d` 一键启动。

#### Scenario: 一键启动全栈
- **WHEN** 执行 `make docker-up`
- **THEN** 启动 app/db/redis/queue/scheduler 五个服务，健康检查通过

#### Scenario: 查看日志
- **WHEN** 执行 `make docker-logs`
- **THEN** 输出所有服务日志，支持 `service=` 参数过滤

### Requirement: API 文档自动生成

系统 SHALL 集成 `apidoc` 模块，从控制器注解自动生成 OpenAPI/Swagger 风格 API 文档，输出到 `docs/api/` 目录，提供 `make docs` 命令生成。

#### Scenario: 生成 API 文档
- **WHEN** 执行 `make docs`
- **THEN** 扫描所有控制器注解，生成 `docs/api/index.html` + JSON 规范文件

#### Scenario: 访问 API 文档
- **WHEN** 浏览器访问 `docs/api/index.html`
- **THEN** 显示交互式 API 文档，含端点、参数、响应示例

### Requirement: 测试基类与工厂

系统 SHALL 提供 `tests/TestCase.v` 测试基类，封装 `web.TestResponse` + `RefreshDatabase` trait + `acting_as(user)` + `json_request(method, path, body)` 辅助方法，测试数据通过 Factory 生成。

#### Scenario: 刷新数据库
- **WHEN** 测试类使用 `RefreshDatabase` trait
- **THEN** 每个测试方法执行前回滚数据库到干净状态

#### Scenario: 认证用户请求
- **WHEN** 测试调用 `acting_as(user).json_request('GET', '/api/v1/auth/profile')`
- **THEN** 请求自动携带该用户的 JWT，返回 200

### Requirement: 日志配置化

系统 SHALL 通过 `config/logging.v` 配置日志通道（stdout/file/json）、级别（debug/info/warn/error）、文件路径、轮转策略，按环境区分（dev 彩色控制台，prod JSON 文件）。

#### Scenario: 生产日志
- **WHEN** `APP_PROFILE=prod` 启动
- **THEN** 日志以 JSON 格式输出到 `storage/logs/app.log`，级别 `info`

#### Scenario: 开发日志
- **WHEN** `APP_PROFILE=dev` 启动
- **THEN** 日志以彩色控制台格式输出到 stdout，级别 `debug`

## MODIFIED Requirements

### Requirement: 分页响应元数据
分页响应在保留原有 `data`/`total`/`current_page`/`last_page`/`has_more` 字段基础上，追加 Laravel 风格的 `meta`（`per_page`/`from`/`to`/`path`）和 `links`（`first`/`last`/`prev`/`next`）字段，向后兼容。

### Requirement: 软删除语义
`User.status=-1` 表示删除的约定改为 `orm.SoftDeletableEntity` 的 `deleted_at IS NOT NULL`，需新增迁移为所有业务表添加 `deleted_at` 列，`delete()` 设置 `deleted_at` 而非修改 `status`。

## REMOVED Requirements

### Requirement: 手写 JSON 响应拼接
**Reason**: 控制器内手写 `'{"success":false,"code":...}'` 字符串拼接易出错、无转义、与统一响应格式重复定义。
**Migration**: 全部改用 `web.Result` + `web.success`/`web.fail`/`web.page` 构造。

### Requirement: 内联校验
**Reason**: `if dto.x.len == 0 { return err_resp(...) }` 内联校验重复、不可复用、无统一错误格式。
**Migration**: 全部改用 `web.validate[T]` + `@[validate: '...']` 声明式校验。

### Requirement: 自造 MiddlewareManager
**Reason**: 框架已提供 `web.MiddlewareGroupRegistry`，自造管理器重复造轮子且不支持命名组与参数化。
**Migration**: 改用 `web.MiddlewareGroupRegistry` + `throttle_middleware`/`role_middleware`/`cors_configurable_middleware`。

### Requirement: God Function 装配
**Reason**: `new_bootstrap` 270 行单函数装配所有组件，违反单一职责，难以维护与扩展。
**Migration**: 拆分为 `core.ServiceProvider` 实现，每个 Provider 负责一个领域。

### Requirement: 类型擦除 DI
**Reason**: `unsafe { voidptr(x) }` 注册 Bean 丢失类型信息，字符串键名易错，无编译期检查。
**Migration**: 改用 `core.ApplicationContext` 类型安全的注册 API 或 `ServiceProvider.register()` 模式。

### Requirement: 内联种子数据
**Reason**: 种子逻辑塞在 `commands.v` 的 `SeedCommand` 内，不可复用、不可测试。
**Migration**: 拆分到 `database/seeders/` 目录的 Seeder 类。
