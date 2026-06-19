# Tasks

## 阶段一：项目脚手架与配置（基础）

- [x] Task 1: 创建 Demo 目录结构与 v.mod
  - [x] SubTask 1.1: 创建 `Demo/` 目录及 `v.mod`（module main, 依赖 photon）
  - [x] SubTask 1.2: 创建 `.gitignore`（忽略二进制、storage/uploads、*.db、logs）
  - [x] SubTask 1.3: 创建 `Makefile`（build/run/test/clean/docker 目标）
  - [x] SubTask 1.4: 创建 `Dockerfile`（多阶段构建，ubuntu:22.04 + V 编译器）
  - [x] SubTask 1.5: 创建 `README.md`（项目说明、快速开始、API 列表、架构图）

- [x] Task 2: 实现配置系统（config 模块集成）
  - [x] SubTask 2.1: 创建 `config.v`，定义 `AppConfig` 结构（app/server/database/jwt/cache/mail/storage 配置块）
  - [x] SubTask 2.2: 实现 `load_config(profile string)` 函数，使用 MapConfigSource 加载默认值
  - [x] SubTask 2.3: 集成 EnvConfigSource，支持 `APP_*` 前缀环境变量覆盖
  - [x] SubTask 2.4: 实现 dev/prod/test 三套配置（debug、日志级别、数据库路径、端口）

## 阶段二：核心容器与启动流程（DI + Bootstrap）

- [x] Task 3: 实现 ApplicationContext 装配（core 模块集成）
  - [x] SubTask 3.1: 创建 `bootstrap.v`，定义 `Bootstrap` 结构持有所有组件引用
  - [x] SubTask 3.2: 实现 `new_bootstrap(cfg AppConfig) !&Bootstrap`，初始化 Logger、CacheManager、OrmManager、EventBus、LockManager、StorageManager、Mailer、Scheduler
  - [x] SubTask 3.3: 使用 `core.ApplicationContext` 注册所有 Bean（BeanDefinition + 依赖关系）
  - [x] SubTask 3.4: 调用 `app.refresh()` 完成单例实例化与生命周期回调
  - [x] SubTask 3.5: 实现 `print_banner()` 与 `print_routes()` 启动信息输出

- [x] Task 4: 实现 App 结构与 veb 集成
  - [x] SubTask 4.1: 创建 `app.v`，定义 `App` 结构（嵌入 `veb.Context` + `veb.Middleware[Context]`）
  - [x] SubTask 4.2: 定义 `Context` 结构（请求级上下文，嵌入 `veb.Context`）
  - [x] SubTask 4.3: 实现 `before_request()` 与 `after_request()` 生命周期钩子（请求 ID 注入、日志记录）
  - [x] SubTask 4.4: 实现 `main()` 入口，组装 CLI + Bootstrap + veb.run_at

## 阶段三：数据模型与 ORM（持久层）

- [x] Task 5: 定义实体模型（orm.BaseEntity 继承）
  - [x] SubTask 5.1: 创建 `models.v`，定义 `User` 实体（id/username/email/password/nickname/avatar/status/role + BaseEntity）
  - [x] SubTask 5.2: 定义 `Post` 实体（id/title/content/summary/author_id/category_id/status/views + BaseEntity）
  - [x] SubTask 5.3: 定义 `Comment` 实体（id/post_id/user_id/content/parent_id/status + BaseEntity）
  - [x] SubTask 5.4: 定义 `Category` 实体（id/name/slug/description + BaseEntity）
  - [x] SubTask 5.5: 定义 `Tag` 实体（id/name/slug + BaseEntity）与 `PostTag` 关联表实体
  - [x] SubTask 5.6: 定义所有 DTO（CreateUserDto/LoginDto/CreatePostDto/UpdatePostDto/CreateCommentDto 等）含 `@[required]` 校验

- [x] Task 6: 实现数据库连接与迁移
  - [x] SubTask 6.1: 创建 `database.v`，实现 `init_database(cfg) !&orm.OrmManager`，注册 SQLite 连接
  - [x] SubTask 6.2: 实现 5 个迁移结构体（CreateUsersTable/CreatePostsTable/CreateCommentsTable/CreateCategoriesTable/CreateTagsTable），每个实现 `Migration` 接口（version/name/up/down）
  - [x] SubTask 6.3: 使用 `orm.Schema` 构建器生成 CREATE TABLE SQL，包含主键、索引、唯一约束、外键
  - [x] SubTask 6.4: 实现 `run_migrations(mm) !` 与 `rollback_migrations(mm) !` 函数

- [x] Task 7: 实现仓储层（BaseRepository + OrmAdapter）
  - [x] SubTask 7.1: 创建 `repositories.v`，实现 `UserRepository`（BaseRepository[User] + 用户提供的 CRUD 回调）
  - [x] SubTask 7.2: 实现 `PostRepository`（含 find_by_author/find_by_category/find_by_status 派生查询）
  - [x] SubTask 7.3: 实现 `CommentRepository`（含 find_by_post/find_by_parent 派生查询）
  - [x] SubTask 7.4: 实现 `CategoryRepository` 与 `TagRepository`
  - [x] SubTask 7.5: 所有仓储通过 `OrmAdapter[T]` 包装，启用 before_insert/before_update 自动 touch 时间戳

## 阶段四：业务服务层（Service + 事件 + 队列）

- [x] Task 8: 实现核心业务服务
  - [x] SubTask 8.1: 创建 `services.v`，实现 `UserService`（注册/登录/查询/更新/删除/密码校验，依赖 UserRepository + BcryptHasher + EventBus）
  - [x] SubTask 8.2: 实现 `AuthService`（JWT 生成/验证/刷新，依赖 JwtManager + UserService + RoleHierarchy）
  - [x] SubTask 8.3: 实现 `PostService`（CRUD + 缓存 + 锁，依赖 PostRepository + CacheManager + LockManager + EventBus）
  - [x] SubTask 8.4: 实现 `CommentService`（CRUD + 嵌套评论，依赖 CommentRepository + EventBus）
  - [x] SubTask 8.5: 实现 `CategoryService` 与 `TagService`
  - [x] SubTask 8.6: 实现 `StatsService`（统计聚合，依赖 CacheManager + 各 Repository）
  - [x] SubTask 8.7: 实现 `UploadService`（文件上传，依赖 StorageManager + UploadHandler）

- [x] Task 9: 实现事件系统
  - [x] SubTask 9.1: 创建 `events.v`，定义事件常量（`user.registered`/`user.logged_in`/`post.published`/`post.updated`/`comment.posted`）
  - [x] SubTask 9.2: 实现 `UserRegisteredListener`（分发 SendWelcomeEmailJob + 更新统计）
  - [x] SubTask 9.3: 实现 `PostPublishedListener`（清除文章缓存 + 推送通知）
  - [x] SubTask 9.4: 实现 `CommentPostedListener`（分发通知邮件给文章作者）
  - [x] SubTask 9.5: 在 Bootstrap 中注册所有监听器到 EventBus

- [x] Task 10: 实现队列任务
  - [x] SubTask 10.1: 创建 `jobs.v`，定义 `SendWelcomeEmailJob`（实现 Job 接口，handle 调用 Mailer）
  - [x] SubTask 10.2: 定义 `SendCommentNotificationJob`（通知文章作者有新评论）
  - [x] SubTask 10.3: 定义 `StatsAggregationJob`（聚合用户/文章/评论数到缓存）
  - [x] SubTask 10.4: 定义 `CleanupExpiredTokensJob`（清理过期 JWT，演示用）
  - [x] SubTask 10.5: 所有 Job 实现 `tries()` 返回 3，`backoff()` 返回 [1, 5, 10]

## 阶段五：Web 层（控制器 + 中间件 + 路由）

- [x] Task 11: 实现中间件链
  - [x] SubTask 11.1: 创建 `middleware.v`，实现 `RequestLogMiddleware`（请求日志 + 耗时统计）
  - [x] SubTask 11.2: 实现 `CorsMiddleware`（CORS 跨域，可配置 allowed_origins/methods/headers）
  - [x] SubTask 11.3: 实现 `RequestIdMiddleware`（生成 UUID 风格 request_id，注入 logger MDC）
  - [x] SubTask 11.4: 实现 `RateLimitMiddleware`（基于 IP 的滑动窗口限流，60 次/分钟）
  - [x] SubTask 11.5: 实现 `JwtAuthMiddleware`（提取 Bearer token，调用 AuthService.validate_token）
  - [x] SubTask 11.6: 实现 `RoleAuthMiddleware`（基于 RoleHierarchy 的角色校验，ADMIN > EDITOR > USER）
  - [x] SubTask 11.7: 实现 `MiddlewareManager` 统一管理器，提供 `apply_global`/`apply_auth`/`apply_role`/`apply_rate_limit` 方法

- [x] Task 12: 实现首页与系统控制器
  - [x] SubTask 12.1: 创建 `controllers.v`，实现 `index()` 返回 API 信息（版本/端点列表）
  - [x] 12.2: 实现 `health()` 健康检查（状态/版本/uptime/时间戳）
  - [x] SubTask 12.3: 实现 `ping()` 连通性测试返回 'pong'
  - [x] SubTask 12.4: 实现 `stats()` 服务器统计（请求数/用户数/文章数/评论数/缓存命中率）

- [x] Task 13: 实现认证控制器
  - [x] SubTask 13.1: 实现 `POST /api/v1/auth/register`（注册，触发 user.registered 事件）
  - [x] SubTask 13.2: 实现 `POST /api/v1/auth/login`（登录，返回 JWT）
  - [x] SubTask 13.3: 实现 `POST /api/v1/auth/refresh`（刷新 token）
  - [x] SubTask 13.4: 实现 `GET /api/v1/auth/profile`（获取当前用户信息，需 JWT）
  - [x] SubTask 13.5: 实现 `POST /api/v1/auth/logout`（登出，客户端清除 token）

- [x] Task 14: 实现用户管理控制器
  - [x] SubTask 14.1: 实现 `GET /api/v1/users`（分页列表，需 ADMIN，支持 keyword/status/role 过滤）
  - [x] SubTask 14.2: 实现 `GET /api/v1/users/:id`（用户详情，需 ADMIN）
  - [x] SubTask 14.3: 实现 `POST /api/v1/users`（创建用户，需 ADMIN）
  - [x] SubTask 14.4: 实现 `PUT /api/v1/users/:id`（更新用户，需 ADMIN）
  - [x] SubTask 14.5: 实现 `DELETE /api/v1/users/:id`（删除用户，需 ADMIN，软删除）

- [x] Task 15: 实现文章控制器
  - [x] SubTask 15.1: 实现 `GET /api/v1/posts`（分页列表，公开，支持 category/tag/keyword/status 过滤 + 排序）
  - [x] SubTask 15.2: 实现 `GET /api/v1/posts/:id`（详情，公开，自增 views，缓存命中）
  - [x] SubTask 15.3: 实现 `POST /api/v1/posts`（创建，需 EDITOR+，触发 post.published 事件）
  - [x] SubTask 15.4: 实现 `PUT /api/v1/posts/:id`（更新，需 EDITOR+，清除缓存）
  - [x] SubTask 15.5: 实现 `DELETE /api/v1/posts/:id`（删除，需 ADMIN）

- [x] Task 16: 实现评论控制器
  - [x] SubTask 16.1: 实现 `GET /api/v1/posts/:id/comments`（评论列表，公开，支持嵌套）
  - [x] SubTask 16.2: 实现 `POST /api/v1/posts/:id/comments`（创建评论，需 USER+，触发 comment.posted 事件）
  - [x] SubTask 16.3: 实现 `DELETE /api/v1/comments/:id`（删除评论，需 ADMIN 或作者本人）

- [x] Task 17: 实现分类与标签控制器
  - [x] SubTask 17.1: 实现 `GET /api/v1/categories`（分类列表，公开）
  - [x] SubTask 17.2: 实现 `POST /api/v1/categories`（创建分类，需 ADMIN）
  - [x] SubTask 17.3: 实现 `GET /api/v1/tags`（标签列表，公开）
  - [x] SubTask 17.4: 实现 `POST /api/v1/tags`（创建标签，需 EDITOR+）

- [x] Task 18: 实现文件上传控制器
  - [x] SubTask 18.1: 实现 `POST /api/v1/uploads/avatar`（头像上传，需 USER+，限制 2MB，.jpg/.png）
  - [x] SubTask 18.2: 实现 `POST /api/v1/uploads/image`（文章配图上传，需 EDITOR+，限制 5MB）
  - [x] SubTask 18.3: 实现 `GET /api/v1/uploads/:file`（访问已上传文件）

## 阶段六：CLI 命令与定时任务

- [x] Task 19: 实现 CLI 命令系统
  - [x] SubTask 19.1: 创建 `commands.v`，实现 `ServeCommand`（启动 Web 服务，--port/--host 参数）
  - [x] SubTask 19.2: 实现 `MigrateCommand`（执行迁移）
  - [x] SubTask 19.3: 实现 `MigrateRollbackCommand`（回滚迁移）
  - [x] SubTask 19.4: 实现 `MigrateStatusCommand`（迁移状态）
  - [x] SubTask 19.5: 实现 `SeedCommand`（种子数据：1 个 ADMIN + 2 个 EDITOR + 5 个 USER + 10 篇文章 + 20 条评论）
  - [x] SubTask 19.6: 实现 `QueueWorkCommand`（启动队列 Worker）
  - [x] SubTask 19.7: 实现 `SchedulerRunCommand`（启动定时调度器）
  - [x] SubTask 19.8: 实现 `StatsCommand`（输出统计信息到控制台）
  - [x] SubTask 19.9: 实现 `RoutesCommand`（打印所有路由表）
  - [x] SubTask 19.10: 在 main() 中注册所有命令到 CliApplication

- [x] Task 20: 实现定时调度任务
  - [x] SubTask 20.1: 创建 `scheduler.v`，实现 `new_scheduler(stats_svc &StatsService, cache_mgr &CacheManager) !&ticker.Scheduler`
  - [x] SubTask 20.2: 注册每分钟任务：`StatsAggregationJob` 执行
  - [x] SubTask 20.3: 注册每小时任务：缓存预热（热门文章）
  - [x] SubTask 20.4: 注册 Cron 任务 `0 3 * * *`：清理过期数据
  - [x] SubTask 20.5: 实现 `start_scheduler(sched) ` 在独立 goroutine 启动

## 阶段七：HTTP 客户端与邮件（集成演示）

- [x] Task 21: 实现 HTTP 客户端集成
  - [x] SubTask 21.1: 在 `services.v` 中实现 `fetch_github_avatar(username string) !string`，使用 `http.HttpClient` 调用 GitHub API
  - [x] SubTask 21.2: 在用户注册流程中，若提供 github 字段，调用该函数获取头像 URL

- [x] Task 22: 实现邮件发送集成
  - [x] SubTask 22.1: 在 `bootstrap.v` 中初始化 `mailer.Mailer`（dev 用 LogTransport，prod 用 SmtpTransport）
  - [x] SubTask 22.2: 实现 `send_welcome_email(mailer, user)` 使用 `mailer.send_to` + `template_welcome` 模板
  - [x] SubTask 22.3: 实现 `send_comment_notification(mailer, post_author, comment)` 通知邮件

## 阶段八：测试与文档

- [ ] Task 23: 实现测试套件
  - [ ] SubTask 23.1: 创建 `auth_test.v`，测试注册/登录/刷新/权限校验
  - [ ] SubTask 23.2: 创建 `post_test.v`，测试文章 CRUD + 缓存命中 + 分页
  - [ ] SubTask 23.3: 创建 `comment_test.v`，测试评论创建 + 嵌套查询
  - [ ] SubTask 23.4: 创建 `middleware_test.v`，测试 JWT 中间件 + 角色校验 + 限流
  - [ ] SubTask 23.5: 创建 `repository_test.v`，测试仓储 CRUD + 派生查询
  - [ ] SubTask 23.6: 所有测试使用 `web.TestResponse` 链式断言，确保 `v -enable-globals test Demo/` 全部通过

- [ ] Task 24: 完善文档与最终验证
  - [ ] SubTask 24.1: 完善 `README.md`，包含功能列表、架构图、API 文档、部署指南
  - [ ] SubTask 24.2: 验证 `make build` 编译成功
  - [ ] SubTask 24.3: 验证 `make run` 启动成功，路由表打印正确
  - [ ] SubTask 24.4: 验证 `./demo migrate` 创建所有表
  - [ ] SubTask 24.5: 验证 `./demo seed` 插入种子数据
  - [ ] SubTask 24.6: 验证 `./demo serve` 启动后 curl 各端点返回正确响应
  - [ ] SubTask 24.7: 验证 `make test` 全部测试通过
  - [ ] SubTask 24.8: 验证 `docker build` 构建成功

# Task Dependencies

- Task 2 依赖 Task 1（需要目录结构）
- Task 3 依赖 Task 2（Bootstrap 需要 AppConfig）
- Task 4 依赖 Task 3（App 需要 Bootstrap）
- Task 6 依赖 Task 5（迁移需要实体定义）
- Task 7 依赖 Task 6（仓储需要数据库连接）
- Task 8 依赖 Task 7（服务需要仓储）
- Task 9 依赖 Task 8（事件监听器需要服务）
- Task 10 依赖 Task 8（Job 需要服务）
- Task 11 依赖 Task 8（中间件需要 AuthService）
- Task 12-18 依赖 Task 4, 8, 11（控制器需要 App/Service/Middleware）
- Task 19 依赖 Task 4, 6, 8（命令需要各组件）
- Task 20 依赖 Task 8, 10（调度器需要服务与 Job）
- Task 21, 22 依赖 Task 8（集成需要服务）
- Task 23 依赖 Task 12-18（测试需要控制器）
- Task 24 依赖 Task 1-23（最终验证需要全部完成）

# 可并行任务

- Task 5（实体模型）与 Task 11（中间件）可并行
- Task 9（事件）与 Task 10（队列）可并行
- Task 12-18（各控制器）在依赖就绪后可并行
- Task 21（HTTP 客户端）与 Task 22（邮件）可并行
