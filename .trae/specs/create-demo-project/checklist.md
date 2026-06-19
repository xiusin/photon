# Checklist

## 阶段一：项目脚手架与配置

- [ ] Demo/ 目录已创建，包含 v.mod 文件，声明 `module main` 并依赖 photon
- [ ] .gitignore 文件存在，忽略二进制文件、storage/uploads/、*.db、logs/、.DS_Store
- [ ] Makefile 存在，包含 build/run/test/clean/docker 目标，使用 `-enable-globals` flag
- [ ] Dockerfile 存在，使用多阶段构建（builder + runtime），非 root 用户，包含 healthcheck
- [ ] README.md 存在，包含项目介绍、快速开始、API 列表、架构说明
- [ ] config.v 存在，定义 AppConfig 结构，包含 app/server/database/jwt/cache/mail/storage 配置块
- [ ] load_config 函数实现，支持 MapConfigSource + EnvConfigSource 多源加载
- [ ] dev/prod/test 三套配置可切换，环境变量 APP_* 可覆盖配置

## 阶段二：核心容器与启动流程

- [x] bootstrap.v 存在，定义 Bootstrap 结构持有 Logger/CacheManager/OrmManager/EventBus 等引用
- [x] new_bootstrap 函数实现，正确初始化所有组件并设置依赖关系
- [x] 使用 core.ApplicationContext 注册所有 Bean（UserService/PostService/AuthService 等）
- [x] 调用 app.refresh() 完成单例实例化，无循环依赖错误
- [x] print_banner 输出 ASCII 横幅，print_routes 输出路由表
- [x] app.v 定义 App 结构嵌入 veb.Context + veb.Middleware[Context]
- [x] Context 结构定义，嵌入 veb.Context
- [x] before_request/after_request 钩子实现，注入 request_id 到 logger MDC
- [x] main() 入口组装 CLI + Bootstrap + veb.run_at，无 panic

## 阶段三：数据模型与 ORM

- [x] models.v 定义 User 实体，嵌入 orm.BaseEntity，包含 username/email/password/nickname/avatar/status/role 字段
- [x] Post 实体定义，包含 title/content/summary/author_id/category_id/status/views 字段
- [x] Comment 实体定义，包含 post_id/user_id/content/parent_id/status 字段
- [x] Category 实体定义，包含 name/slug/description 字段
- [x] Tag 实体定义，包含 name/slug 字段
- [x] 所有 DTO 定义（CreateUserDto/LoginDto/CreatePostDto 等）含 @[required] 校验注解
- [x] database.v 实现 init_database，注册 SQLite 连接到 OrmManager
- [x] 5 个迁移结构体实现 Migration 接口（version/name/up/down）
- [x] 迁移使用 orm.Schema 构建器生成 CREATE TABLE SQL，含主键、索引、唯一约束
- [x] run_migrations 与 rollback_migrations 函数实现
- [x] repositories.v 实现 UserRepository（BaseRepository[User] + CRUD 回调）
- [x] PostRepository 实现，含 find_by_author/find_by_category 派生查询
- [x] CommentRepository 实现，含 find_by_post/find_by_parent 派生查询
- [x] CategoryRepository 与 TagRepository 实现
- [x] 所有仓储通过 OrmAdapter[T] 包装，before_insert/before_update 自动 touch 时间戳

## 阶段四：业务服务层

- [ ] services.v 实现 UserService（注册/登录/查询/更新/删除/密码校验）
- [ ] UserService 依赖 UserRepository + BcryptHasher + EventBus，构造器注入
- [ ] AuthService 实现（JWT 生成/验证/刷新），依赖 JwtManager + UserService + RoleHierarchy
- [ ] PostService 实现（CRUD + 缓存 + 锁），依赖 PostRepository + CacheManager + LockManager + EventBus
- [ ] CommentService 实现（CRUD + 嵌套评论），依赖 CommentRepository + EventBus
- [ ] CategoryService 与 TagService 实现
- [ ] StatsService 实现（统计聚合），依赖 CacheManager + 各 Repository
- [ ] UploadService 实现（文件上传），依赖 StorageManager + UploadHandler
- [ ] events.v 定义事件常量（user.registered/post.published/comment.posted 等）
- [ ] UserRegisteredListener 实现（分发 SendWelcomeEmailJob + 更新统计）
- [ ] PostPublishedListener 实现（清除文章缓存 + 推送通知）
- [ ] CommentPostedListener 实现（分发通知邮件给文章作者）
- [ ] 所有监听器在 Bootstrap 中注册到 EventBus
- [ ] jobs.v 定义 SendWelcomeEmailJob（实现 Job 接口，handle 调用 Mailer）
- [ ] SendCommentNotificationJob 实现
- [ ] StatsAggregationJob 实现
- [ ] CleanupExpiredTokensJob 实现
- [ ] 所有 Job 实现 tries() 返回 3，backoff() 返回 [1, 5, 10]

## 阶段五：Web 层

- [x] middleware.v 实现 RequestLogMiddleware（请求日志 + 耗时统计）
- [x] CorsMiddleware 实现（CORS 跨域，可配置）
- [x] RequestIdMiddleware 实现（生成 request_id，注入 logger MDC）
- [x] RateLimitMiddleware 实现（基于 IP 滑动窗口限流，60 次/分钟）
- [x] JwtAuthMiddleware 实现（提取 Bearer token，调用 AuthService.validate_token）
- [x] RoleAuthMiddleware 实现（基于 RoleHierarchy 角色校验，ADMIN > EDITOR > USER）
- [x] MiddlewareManager 统一管理器实现，提供 apply_global/apply_auth/apply_role/apply_rate_limit
- [x] controllers.v 实现 index() 返回 API 信息
- [x] health() 健康检查实现
- [x] ping() 连通性测试实现
- [x] stats() 服务器统计实现
- [x] POST /api/v1/auth/register 实现触发 user.registered 事件
- [x] POST /api/v1/auth/login 实现返回 JWT
- [x] POST /api/v1/auth/refresh 实现刷新 token
- [x] GET /api/v1/auth/profile 实现（需 JWT）
- [x] POST /api/v1/auth/logout 实现
- [x] GET /api/v1/users 实现分页列表（需 ADMIN，支持过滤）
- [x] GET /api/v1/users/:id 实现详情（需 ADMIN）
- [x] POST /api/v1/users 实现创建（需 ADMIN）
- [x] PUT /api/v1/users/:id 实现更新（需 ADMIN）
- [x] DELETE /api/v1/users/:id 实现软删除（需 ADMIN）
- [x] GET /api/v1/posts 实现分页列表（公开，支持过滤排序）
- [x] GET /api/v1/posts/:id 实现详情（公开，自增 views，缓存命中）
- [x] POST /api/v1/posts 实现创建（需 EDITOR+，触发 post.published 事件）
- [x] PUT /api/v1/posts/:id 实现更新（需 EDITOR+，清除缓存）
- [x] DELETE /api/v1/posts/:id 实现删除（需 ADMIN）
- [x] GET /api/v1/posts/:id/comments 实现评论列表（公开，支持嵌套）
- [x] POST /api/v1/posts/:id/comments 实现创建（需 USER+，触发 comment.posted 事件）
- [x] DELETE /api/v1/comments/:id 实现删除（需 ADMIN 或作者）
- [x] GET /api/v1/categories 实现分类列表（公开）
- [x] POST /api/v1/categories 实现创建（需 ADMIN）
- [x] GET /api/v1/tags 实现标签列表（公开）
- [x] POST /api/v1/tags 实现创建（需 EDITOR+）
- [x] POST /api/v1/uploads/avatar 实现头像上传（需 USER+，限制 2MB，.jpg/.png）
- [x] POST /api/v1/uploads/image 实现文章配图上传（需 EDITOR+，限制 5MB）
- [x] GET /api/v1/uploads/:file 实现访问已上传文件

## 阶段六：CLI 命令与定时任务

- [x] commands.v 实现 ServeCommand（--port/--host 参数）
- [x] MigrateCommand 实现（执行迁移）
- [x] MigrateRollbackCommand 实现（回滚迁移）
- [x] MigrateStatusCommand 实现（迁移状态）
- [x] SeedCommand 实现（种子数据：1 ADMIN + 2 EDITOR + 5 USER + 10 文章 + 20 评论）
- [x] QueueWorkCommand 实现（启动队列 Worker）
- [x] SchedulerRunCommand 实现（启动定时调度器）
- [x] StatsCommand 实现（输出统计信息）
- [x] RoutesCommand 实现（打印路由表）
- [x] 所有命令在 main() 中注册到 CliApplication
- [x] scheduler.v 实现 new_scheduler，注册每分钟统计任务
- [x] 注册每小时缓存预热任务
- [x] 注册 Cron 任务 0 3 * * * 清理过期数据
- [x] start_scheduler 在独立 goroutine 启动

## 阶段七：HTTP 客户端与邮件

- [x] fetch_github_avatar 函数实现，使用 http.HttpClient 调用 GitHub API
- [x] 用户注册流程集成 GitHub 头像获取（可选）
- [x] Bootstrap 中初始化 mailer.Mailer（dev 用 LogTransport，prod 用 SmtpTransport）
- [x] send_welcome_email 函数实现，使用 mailer.send_to + template_welcome 模板
- [x] send_comment_notification 函数实现

## 阶段八：测试与文档

- [ ] auth_test.v 测试注册/登录/刷新/权限校验
- [ ] post_test.v 测试文章 CRUD + 缓存命中 + 分页
- [ ] comment_test.v 测试评论创建 + 嵌套查询
- [ ] middleware_test.v 测试 JWT 中间件 + 角色校验 + 限流
- [ ] repository_test.v 测试仓储 CRUD + 派生查询
- [ ] 所有测试使用 web.TestResponse 链式断言
- [ ] README.md 完善功能列表、架构图、API 文档、部署指南
- [ ] make build 编译成功，无错误
- [ ] make run 启动成功，路由表打印正确
- [ ] ./demo migrate 创建所有表
- [ ] ./demo seed 插入种子数据
- [ ] ./demo serve 启动后 curl 各端点返回正确响应
- [ ] make test 全部测试通过
- [ ] docker build 构建成功

## 最终完整性验证

- [ ] 项目无打桩代码（无 TODO/FIXME/stub 注释）
- [ ] 项目无硬编码（所有可配置项通过 config 读取）
- [ ] 项目无简化实现（所有 API 完整实现业务逻辑）
- [ ] 所有 16 个框架模块均被实际使用（core/config/logger/cache/orm/web/security/queue/locking/pool/storage/ticker/http/support/cli/mailer）
- [ ] 项目可独立运行，无需修改任何框架代码
- [ ] 项目代码遵循 V 语言官方风格指南（snake_case 文件名、PascalCase 结构体、pub 标注）
