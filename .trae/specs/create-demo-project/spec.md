# Demo 示例项目（PhotonBlog）Spec

## Why

Photon 框架目前仅有一个 `example/` 目录的简化演示，未充分展示框架的全部能力（DI 容器、ORM 仓储、安全、缓存、队列、事件、调度、存储、锁、邮件、CLI 等），且未提供"开箱即用"的完整应用脚手架。需要新建一个名为 `Demo` 的目录，构建一个对标 Spring Boot / Laravel 的完整示例应用，让使用者克隆后即可运行，覆盖框架所有核心模块的真实使用场景。

## What Changes

- 新建 `Demo/` 目录，包含一个完整的 V 语言应用 `module main`
- 实现 **PhotonBlog API Server**：博客/CMS 系统，覆盖框架全部 16 个模块
- 提供多 Profile 配置（dev / prod / test），支持环境变量覆盖
- 提供完整 CLI 命令（serve / migrate / seed / worker / scheduler / stats / routes）
- 提供完整数据库迁移脚本（SQLite，开箱即用，零外部依赖）
- 提供完整中间件链（CORS / 日志 / 请求 ID / 限流 / JWT 认证 / 角色授权）
- 提供完整业务模块：用户、文章、评论、分类、标签、文件上传、统计
- 提供完整事件系统：用户注册、文章发布、评论提交事件 + 监听器
- 提供完整队列任务：欢迎邮件、通知分发、统计聚合、清理任务
- 提供完整定时任务：每日统计、过期清理、缓存预热
- 提供完整测试套件：API 集成测试 + 单元测试
- 提供 Dockerfile + Makefile + README，支持一键构建运行
- **BREAKING**：无（新建目录，不影响现有代码）

## Impact

- Affected specs: 无（首个 spec）
- Affected code: 新建 `Demo/` 目录，不修改任何现有模块代码
- 依赖模块：core, config, logger, cache, orm, web, security, queue, locking, pool, storage, ticker, http, support, cli, mailer（全部 16 个模块）

## ADDED Requirements

### Requirement: 项目脚手架与构建系统

系统 SHALL 提供完整的 V 语言项目脚手架，包含 `v.mod`、`Makefile`、`Dockerfile`、`.gitignore`、`README.md`，支持 `make build`、`make run`、`make test`、`make docker` 一键操作。

#### Scenario: 项目可独立编译
- **WHEN** 开发者在 `Demo/` 目录执行 `v -enable-globals .`
- **THEN** 项目编译成功，生成可执行二进制文件

#### Scenario: 项目可一键运行
- **WHEN** 开发者执行 `make run` 或 `v -enable-globals run .`
- **THEN** 应用启动，HTTP 服务监听 8080 端口，CLI 显示启动横幅与路由表

### Requirement: 多源配置管理

系统 SHALL 使用 `config` 模块的多源配置能力，支持 MapConfigSource + EnvConfigSource + FileConfigSource 三种来源，支持 dev/prod/test 三种 Profile 切换。

#### Scenario: 默认 dev profile 加载
- **WHEN** 应用启动未指定 profile
- **THEN** 加载 dev profile 配置，开启 debug 日志，使用 SQLite 内存数据库

#### Scenario: 环境变量覆盖配置
- **WHEN** 设置环境变量 `APP_SERVER_PORT=9090`
- **THEN** 服务在 9090 端口启动，覆盖配置文件中的默认值

### Requirement: 依赖注入与服务注册

系统 SHALL 使用 `core.ApplicationContext` 作为统一 DI 容器，通过 `BeanDefinition` 注册所有服务、仓储、中间件，支持 singleton 作用域与构造器依赖注入。

#### Scenario: 服务自动装配
- **WHEN** 应用启动执行 `app.refresh()`
- **THEN** 所有注册的 Bean（UserService、PostService、AuthService、JwtManager 等）按依赖顺序实例化并缓存

#### Scenario: 依赖注入解析
- **WHEN** 控制器请求 `PostService`
- **THEN** PostService 及其依赖（PostRepository、CacheManager、EventBus）被正确注入

### Requirement: Web 路由与控制器

系统 SHALL 使用 `web` 模块的注解路由（`@[get]`/`@[post]`/`@[put]`/`@[delete]`）+ veb 框架，提供完整的 RESTful API，覆盖首页、认证、用户、文章、评论、上传、统计等控制器。

#### Scenario: 注解路由扫描
- **WHEN** 应用启动调用 `web.scan_controller[App]()`
- **THEN** 所有标注 `@[get]`/`@[post]` 的方法被扫描并打印路由表

#### Scenario: 统一响应封装
- **WHEN** 任意 API 返回数据
- **THEN** 响应体遵循 `{"success":bool,"code":int,"message":string,"data":...,"timestamp":i64}` 格式

### Requirement: ORM 与仓储模式

系统 SHALL 使用 `orm` 模块的 `OrmManager` + `BaseRepository[T]` + `OrmAdapter[T]` 生命周期钩子，实现 User/Post/Comment/Category/Tag 五张表的完整 CRUD，使用 SQLite 作为默认数据库。

#### Scenario: 实体生命周期钩子
- **WHEN** 创建新文章 `repo.save(mut post)`
- **THEN** `before_insert` 钩子触发，自动设置 `created_at` 和 `updated_at`，`version` 自增

#### Scenario: 仓储派生查询
- **WHEN** 调用 `repo.find_by_username('alice')`
- **THEN** 通过方法名解析生成 `WHERE username = ?` 查询并返回结果

### Requirement: 数据库迁移

系统 SHALL 使用 `orm.MigrationManager` + `Schema` 构建器，提供版本化迁移脚本，包括 users、posts、comments、categories、tags 五张表，支持 `migrate`、`rollback`、`reset`、`fresh` 命令。

#### Scenario: 首次迁移
- **WHEN** 执行 `./demo migrate`
- **THEN** 创建 `schema_migrations` 跟踪表，按版本顺序执行所有 up() 迁移，创建 5 张业务表

#### Scenario: 数据库回滚
- **WHEN** 执行 `./demo migrate:rollback`
- **THEN** 回滚最后一个 batch 的迁移，执行对应 down()

### Requirement: 安全认证与授权

系统 SHALL 使用 `security` 模块的 `JwtManager` + `AuthenticationManager` + `RoleHierarchy` + `BcryptHasher`，实现 JWT 登录、RBAC 三级角色（ADMIN/EDITOR/USER）、密码哈希、CSRF 保护。

#### Scenario: 用户登录获取 JWT
- **WHEN** POST `/api/v1/auth/login` 提交正确用户名密码
- **THEN** 返回 `{"access_token":"...","token_type":"Bearer","expires_in":3600,"user":{...}}`

#### Scenario: 角色权限校验
- **WHEN** USER 角色用户访问 `DELETE /api/v1/users/:id`
- **THEN** 返回 403 Forbidden，提示需要 ADMIN 角色

#### Scenario: 密码哈希存储
- **WHEN** 用户注册提交明文密码
- **THEN** 数据库存储 BcryptHasher 生成的哈希值，明文不落库

### Requirement: 缓存抽象与削峰

系统 SHALL 使用 `cache` 模块的 `CacheManager` + `MemoryCache` + `Singleflight` + `TaggedCache`，对热点数据（文章详情、用户信息、统计计数）进行缓存，支持缓存标签批量失效与 singleflight 削峰。

#### Scenario: 文章详情缓存
- **WHEN** 首次 GET `/api/v1/posts/1`
- **THEN** 从数据库加载并写入缓存 `post:1`，TTL 300 秒

#### Scenario: 缓存命中
- **WHEN** 再次 GET `/api/v1/posts/1`
- **THEN** 直接从缓存返回，不查数据库，响应时间 < 1ms

#### Scenario: 标签批量失效
- **WHEN** 文章更新后调用 `tagged_cache.flush()`
- **THEN** 所有 `posts` 标签下的缓存条目被清除

### Requirement: 队列与异步任务

系统 SHALL 使用 `queue` 模块的 `QueueDispatcher` + `MemoryDriver` + `QueueWorker`，实现异步任务分发，包括欢迎邮件、评论通知、统计聚合、定期清理。

#### Scenario: 注册后异步发邮件
- **WHEN** 用户注册成功
- **THEN** `SendWelcomeEmailJob` 被分发到队列，不阻塞注册响应

#### Scenario: Worker 消费任务
- **WHEN** 执行 `./demo queue:work`
- **THEN** Worker 轮询队列，执行 Job 的 `handle()` 方法，失败重试最多 3 次

### Requirement: 事件系统

系统 SHALL 使用 `core.EventBus`，实现发布/订阅模式，包括 `user.registered`、`post.published`、`comment.posted` 事件及对应监听器（发邮件、更新统计、推送通知）。

#### Scenario: 用户注册触发事件
- **WHEN** 新用户注册成功
- **THEN** 发布 `user.registered` 事件，监听器异步发送欢迎邮件并写入统计

#### Scenario: 事件传播停止
- **WHEN** 监听器调用 `event.stop_propagation()`
- **THEN** 后续监听器不再执行

### Requirement: 定时调度任务

系统 SHALL 使用 `ticker.Scheduler`，实现定时任务：每分钟统计更新、每小时缓存预热、每天凌晨清理过期数据。

#### Scenario: 定时统计任务
- **WHEN** 启动 `./demo scheduler:run`
- **THEN** 每分钟执行 `StatsAggregationJob`，更新 `stats:daily` 缓存

#### Scenario: Cron 表达式任务
- **WHEN** 配置 `cron('0 3 * * *')` 任务
- **THEN** 每天凌晨 3 点执行清理任务

### Requirement: 锁与并发控制

系统 SHALL 使用 `locking.LockManager` + `LockGuard`，对并发敏感操作（文章发布、库存扣减、统计更新）加锁，防止竞态条件。

#### Scenario: 文章发布加锁
- **WHEN** 多个请求同时发布同一篇文章
- **THEN** 通过 `lock_manager.lock('post:publish:1')` 串行化，仅一个请求执行

#### Scenario: RAII 锁守卫
- **WHEN** 使用 `locking.new_lock_guard(mut lm, key)`
- **THEN** 离开作用域自动解锁，即使发生异常也不死锁

### Requirement: 文件存储与上传

系统 SHALL 使用 `storage.StorageManager` + `LocalAdapter` + `web.UploadHandler`，实现文件上传（头像、文章配图），支持大小限制、扩展名校验、MIME 检测、SHA-256 去重。

#### Scenario: 头像上传
- **WHEN** POST `/api/v1/uploads/avatar` 上传图片
- **THEN** 文件保存到 `storage/uploads/avatars/`，返回 `{"path":"...","hash":"...","size":...}`

#### Scenario: 非法文件拒绝
- **WHEN** 上传 `.exe` 文件
- **THEN** 返回 400 错误，提示扩展名不允许

### Requirement: 邮件发送

系统 SHALL 使用 `mailer.Mailer` + `LogTransport`（开发环境），实现欢迎邮件、评论通知邮件发送，支持模板渲染。

#### Scenario: 发送欢迎邮件
- **WHEN** `SendWelcomeEmailJob` 执行
- **THEN** 调用 `mailer.send_to(user.email, '欢迎', template_welcome())`，日志记录邮件内容

### Requirement: CLI 命令系统

系统 SHALL 使用 `cli.CliApplication`，提供完整命令：`serve`、`migrate`、`migrate:rollback`、`migrate:status`、`seed`、`queue:work`、`scheduler:run`、`stats`、`routes`、`list`、`help`。

#### Scenario: 启动 Web 服务
- **WHEN** 执行 `./demo serve --port=8080`
- **THEN** HTTP 服务在 8080 端口启动

#### Scenario: 数据库种子
- **WHEN** 执行 `./demo seed`
- **THEN** 插入预置管理员、示例文章、示例评论数据

### Requirement: 日志与请求追踪

系统 SHALL 使用 `logger.Logger` + MDC 上下文，实现结构化日志，每个请求注入 `request_id`，支持 JSON 格式输出（生产）和彩色控制台输出（开发）。

#### Scenario: 请求 ID 注入
- **WHEN** 请求进入中间件链
- **THEN** 自动生成 `request_id` 并通过 `logger.put('request_id', id)` 注入 MDC

#### Scenario: 请求日志
- **WHEN** 请求处理完成
- **THEN** 输出 `[INFO] GET /api/v1/posts | request_id=abc123 | 12ms` 格式日志

### Requirement: HTTP 客户端集成

系统 SHALL 使用 `http.HttpClient`，演示外部 API 调用场景（如获取 GitHub 用户信息作为头像来源），展示 fluent API 用法。

#### Scenario: 调用外部 API
- **WHEN** 用户注册时提供 GitHub 用户名
- **THEN** 通过 `http.with_base_url('https://api.github.com').get('/users/xxx')` 获取头像 URL

### Requirement: 支持工具集

系统 SHALL 使用 `support.Collection`、`support.LengthAwarePaginator`、`support.Sort`，实现列表分页、排序、链式集合操作。

#### Scenario: 分页查询
- **WHEN** GET `/api/v1/posts?page=2&page_size=10`
- **THEN** 返回 `LengthAwarePaginator` 结构，包含 `data`、`total`、`current_page`、`last_page`、`has_more`

### Requirement: 测试套件

系统 SHALL 提供完整测试套件，覆盖认证、用户、文章、评论、上传等核心 API，使用 V 内置测试框架 + `web.TestResponse` 链式断言。

#### Scenario: 认证 API 测试
- **WHEN** 运行 `v -enable-globals test Demo/`
- **THEN** 所有测试通过，包括登录、注册、权限校验、JWT 验证

### Requirement: 容器化部署

系统 SHALL 提供 Dockerfile 多阶段构建，支持 `docker build` 一键构建镜像，镜像大小 < 50MB，包含 healthcheck。

#### Scenario: Docker 构建
- **WHEN** 执行 `docker build -t photonblog .`
- **THEN** 构建成功，镜像可 `docker run -p 8080:8080 photonblog` 启动

## MODIFIED Requirements

无（全新项目）

## REMOVED Requirements

无
