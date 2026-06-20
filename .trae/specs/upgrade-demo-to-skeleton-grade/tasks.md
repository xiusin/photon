# Tasks

## 阶段一：项目骨架重构（目录结构 + 环境文件 + 配置目录）

- [x] Task 1: 创建骨架目录结构与 .env 文件体系
  - [x] SubTask 1.1: 创建 `Demo/config/`、`Demo/routes/`、`Demo/providers/`、`Demo/app/Http/Controllers/`、`Demo/app/Http/Resources/`、`Demo/app/Http/Middleware/`、`Demo/database/migrations/`、`Demo/database/seeders/`、`Demo/database/factories/`、`Demo/tests/`、`Demo/docs/api/`、`Demo/storage/logs/`、`Demo/storage/uploads/`、`Demo/bin/` 目录
  - [x] SubTask 1.2: 创建 `Demo/.env.example`（含全部环境变量模板：APP_PROFILE/APP_DEBUG/APP_PORT/APP_HOST/DB_PATH/DB_DRIVER/JWT_SECRET/JWT_TTL/CACHE_DRIVER/MAIL_DRIVER/MAIL_HOST/MAIL_PORT/MAIL_USER/MAIL_PASS/STORAGE_PATH/LOG_LEVEL/LOG_CHANNEL 等）
  - [x] SubTask 1.3: 创建 `Demo/.env`（dev 默认值，JWT_SECRET 留空提示）、`Demo/.env.prod.example`、`Demo/.env.testing`
  - [x] SubTask 1.4: 更新 `Demo/.gitignore`（忽略 `.env`、`bin/`、`storage/logs/*.log`、`storage/uploads/`、`*.db`、`docs/api/` 生成物）

- [x] Task 2: 实现 config/ 目录按关注点拆分配置文件
  - [x] SubTask 2.1: 创建 `Demo/config/app.v`（AppConfig：name/version/profile/debug）
  - [x] SubTask 2.2: 创建 `Demo/config/database.v`（DatabaseConfig：driver/path/max_connections，占位符 `${DB_PATH}`）
  - [x] SubTask 2.3: 创建 `Demo/config/jwt.v`（JwtConfig：secret/ttl/issuer，占位符 `${JWT_SECRET}`，生产环境校验逻辑）
  - [x] SubTask 2.4: 创建 `Demo/config/cache.v`（CacheConfig：driver/ttl/prefix）
  - [x] SubTask 2.5: 创建 `Demo/config/mail.v`（MailConfig：driver/host/port/user/pass/from）
  - [x] SubTask 2.6: 创建 `Demo/config/storage.v`（StorageConfig：driver/path/max_size/allowed_extensions）
  - [x] SubTask 2.7: 创建 `Demo/config/logging.v`（LoggingConfig：level/channel/file_path/json_format）
  - [x] SubTask 2.8: 创建 `Demo/config/web.v`（WebConfig：cors/rate_limit/middleware_groups）
  - [x] SubTask 2.9: 创建 `Demo/config/auth.v`（AuthConfig：role_hierarchy/guards/providers）
  - [x] SubTask 2.10: 重写 `Demo/config.v`，实现 `load_config(profile)` 扫描 `config/*.v` + 加载 `.env` + `Environment.resolve_placeholders` 解析占位符 + 生产环境密钥校验

- [x] Task 3: 实现 helpers.v 工具函数集中文件
  - [x] SubTask 3.1: 创建 `Demo/helpers.v`，迁移 `generate_request_id`、`generate_slug`、`now_unix` 工具函数
  - [x] SubTask 3.2: 新增 `cache_remember[T](cm, key, ttl, loader fn() !T) !T` 泛型缓存辅助
  - [x] SubTask 3.3: 新增 `parse_pagination(ctx) (int, int)` 解析 page/page_size 查询参数
  - [x] SubTask 3.4: 新增 `parse_sort(ctx, allowed []string) (string, string)` 解析排序参数

## 阶段二：服务提供者与启动流程重构

- [x] Task 4: 实现 ServiceProvider 拆分 bootstrap God Function
  - [x] SubTask 4.1: 创建 `Demo/providers/app_service_provider.v`（AppServiceProvider：注册 AppConfig/Logger/Environment）
  - [x] SubTask 4.2: 创建 `Demo/providers/database_service_provider.v`（DatabaseServiceProvider：注册 OrmManager/MigrationManager，执行迁移）
  - [x] SubTask 4.3: 创建 `Demo/providers/cache_service_provider.v`（CacheServiceProvider：注册 CacheManager/TaggedCache/Singleflight）
  - [x] SubTask 4.4: 创建 `Demo/providers/web_service_provider.v`（WebServiceProvider：注册 MiddlewareGroupRegistry/ExceptionHandlerRegistry/Router）
  - [x] SubTask 4.5: 创建 `Demo/providers/auth_service_provider.v`（AuthServiceProvider：注册 JwtManager/AuthenticationManager/RoleHierarchy/BcryptHasher，角色层级从 config/auth.v 读取）
  - [x] SubTask 4.6: 创建 `Demo/providers/queue_service_provider.v`（QueueServiceProvider：注册 QueueDispatcher/Worker）
  - [x] SubTask 4.7: 创建 `Demo/providers/event_service_provider.v`（EventServiceProvider：注册 EventBus + 监听器映射）
  - [x] SubTask 4.8: 创建 `Demo/providers/repository_service_provider.v`（RepositoryServiceProvider：注册所有 Repository）
  - [x] SubTask 4.9: 创建 `Demo/providers/service_service_provider.v`（ServiceServiceProvider：注册所有 Service）

- [x] Task 5: 实现 bootstrap/app.v 启动入口
  - [x] SubTask 5.1: 创建 `Demo/bootstrap/app.v`，实现 `new_app_kernel(cfg) !&AppKernel`，创建 ProviderRegistry，按序注册所有 Provider
  - [x] SubTask 5.2: 实现 `AppKernel.bootstrap()` 调用 `register_all()` + `boot_all()`，移除 `unsafe { voidptr(x) }` 类型擦除
  - [x] SubTask 5.3: 实现 `AppKernel.get_service[T](name) !&T` 类型安全的服务获取
  - [x] SubTask 5.4: 迁移 `print_banner`/`print_routes` 到 `bootstrap/console.v`，路由表从 `web.scan_controller[App]()` 实际结果生成（移除硬编码）
  - [x] SubTask 5.5: 重写 `Demo/bootstrap.v` 为薄封装，委托给 `bootstrap/app.v` 的 AppKernel

- [x] Task 6: 重写 main.v 入口与路由分离
  - [x] SubTask 6.1: 创建 `Demo/routes/api.v`，定义 API 路由分组（`/api/v1` 前缀 + `api` 中间件组），注册 auth/users/posts/comments/categories/tags/uploads 控制器
  - [x] SubTask 6.2: 创建 `Demo/routes/web.v`，定义 Web 路由（`/`/`/health`/`/ping`/`/stats`）
  - [x] SubTask 6.3: 重写 `Demo/main.v`，加载 `.env` → `load_config(profile)` → `new_app_kernel(cfg)` → `kernel.bootstrap()` → 注册中间件组 → 注册路由 → CLI/Web 双模式分发
  - [x] SubTask 6.4: 修复 `App.req_count` 数据竞争，改用 `sync.atomic` 或 `sync.Mutex`

## 阶段三：Web 层升级（统一响应 + 验证 + 异常 + 中间件组 + Resource）

- [x] Task 7: 实现统一响应与异常处理
  - [x] SubTask 7.1: 创建 `Demo/app/Http/Kernel.v`，注册 `ExceptionHandlerRegistry`，为 `BadRequestException`/`NotFoundException`/`ValidationException`/`UnauthorizedException`/`ForbiddenException`/`ConflictException`/`RateLimitExceededException` 注册处理器
  - [x] SubTask 7.2: 注册默认异常处理器，捕获未知异常返回 500（生产环境隐藏堆栈）
  - [x] SubTask 7.3: 重写 `Demo/controllers.v` 所有 `ok_resp`/`err_resp` 调用为 `web.success`/`web.fail`/`web.page`/`web.ok`/`web.created`/`web.bad_request`/`web.not_found`/`web.unauthorized`/`web.forbidden`
  - [x] SubTask 7.4: 移除 `controllers.v` 中所有手写 JSON 字符串拼接（`'{"success":...}'`），改用 `json.encode(struct)` + `web.Result`
  - [x] SubTask 7.5: 移除 `models.v` 中未使用的 `ApiResponseDto`/`success_response`/`error_response` 死代码

- [x] Task 8: 实现表单请求验证
  - [x] SubTask 8.1: 在 `Demo/models.v` 为所有 DTO 标注 `@[validate: '...']` 规则（CreateUserDto: `username|required|min_len:3|max_len:32`，`email|required|email`，`password|required|min_len:6`；CreatePostDto: `title|required|min_len:1|max_len:255`，`content|required`；CreateCommentDto: `content|required|min_len:1` 等）
  - [x] SubTask 8.2: 重写 `Demo/controllers.v` 所有内联校验（`if dto.x.len == 0`）为 `web.validate_body[T](ctx)` 或 `web.validate[T](ctx)`，校验失败抛 `ValidationException`
  - [x] SubTask 8.3: 移除 `parse_body_or_form` 双路径解析，统一用 `web.validate_body[T]`（框架已处理 JSON/form）
  - [x] SubTask 8.4: 移除所有 `build_*_dto` form 回退函数（7 个），由框架验证器统一处理

- [x] Task 9: 实现中间件组与参数化中间件
  - [x] SubTask 9.1: 创建 `Demo/app/Http/Middleware/registry.v`，使用 `web.MiddlewareGroupRegistry` 注册命名组：`web`（CORS+RequestId+RequestLog）、`api`（web+RateLimit）、`auth`（JwtAuth）、`admin`（auth+RoleAuth[ADMIN]）、`editor`（auth+RoleAuth[EDITOR,ADMIN]）
  - [x] SubTask 9.2: 中间件参数从 `config/web.v` 读取（CORS allowed_origins/methods/headers、RateLimit max_requests/window_secs）
  - [x] SubTask 9.3: 使用 `web.throttle_middleware`/`web.role_middleware`/`web.cors_configurable_middleware` 替换手写中间件
  - [x] SubTask 9.4: 移除 `Demo/middleware.v` 中的 `MiddlewareManager`（保留中间件实现，改由组注册管理）
  - [x] SubTask 9.5: 移除 `app.v` 中重复的 `request_id` 生成逻辑，统一由 `RequestIdMiddleware` 处理
  - [x] SubTask 9.6: `JwtAuthMiddleware` 认证成功后将 `user_id`/`username`/`role` 写回 `Context`，控制器直接读取（移除重复查库）

- [ ] Task 10: 实现 API Resource 转换层
  - [ ] SubTask 10.1: 创建 `Demo/app/Http/Resources/user_resource.v`（UserResource：输出 id/username/email/nickname/avatar/role/status/created_at，**隐藏 password/version**）
  - [ ] SubTask 10.2: 创建 `Demo/app/Http/Resources/post_resource.v`（PostResource：输出 id/title/summary/status/views/created_at + 嵌套 author/category/tags）
  - [ ] SubTask 10.3: 创建 `Demo/app/Http/Resources/comment_resource.v`（CommentResource：输出 id/content/created_at + 嵌套 user/replies）
  - [ ] SubTask 10.4: 创建 `Demo/app/Http/Resources/category_resource.v` 与 `tag_resource.v`
  - [ ] SubTask 10.5: 创建 `Demo/app/Http/Resources/collection.v`（ResourceCollection[T]：批量转换 + 分页元数据）
  - [ ] SubTask 10.6: 重写 `Demo/controllers.v` 所有 `json.encode(entity)` 为 `XxxResource(entity).to_json()` 或 `ResourceCollection(entities).to_json()`
  - [ ] SubTask 10.7: 私有化 `User.password` 字段（移除 `pub`，仅通过 `BcryptHasher.verify` 校验）

- [ ] Task 11: 实现分页器集成
  - [ ] SubTask 11.1: 重写 `Demo/controllers.v` 列表端点（`GET /users`/`GET /posts`/`GET /comments`），使用 `support.LengthAwarePaginator[T]` 替换手写 `start..end` 切片
  - [ ] SubTask 11.2: 分页响应使用 `web.page(json.encode(paginator.data), page, page_size, total)`，追加 `meta`/`links` 元数据
  - [ ] SubTask 11.3: 过滤/排序参数下沉到 Repository（`find_by_criteria(criteria)`/`find_with_sort(sort_field, sort_dir)`），移除控制器内存过滤

## 阶段四：ORM 与数据层升级

- [ ] Task 12: 实现仓储层升级（预加载 + 事务 + 软删除 + SQL 过滤）
  - [ ] SubTask 12.1: 重写 `Demo/repositories.v`，所有仓储继承 `orm.EagerRepository[T]`，支持 `with(['author','category','tags'])` 预加载
  - [ ] SubTask 12.2: 新增 `PostRepository.find_with_filters(filters map[string]string, sort string, page int, page_size int) LengthAwarePaginator[Post]`，过滤/排序/分页下沉到 SQL
  - [ ] SubTask 12.3: 新增 `UserRepository.find_with_filters(filters, sort, page, page_size)`、`CommentRepository.find_by_post_with_filters(...)`
  - [ ] SubTask 12.4: 实体改用 `orm.SoftDeletableEntity`（添加 `deleted_at` 字段），`delete()` 设置 `deleted_at`，查询自动过滤
  - [ ] SubTask 12.5: 新增 `Repository.restore(id)`、`Repository.force_delete(id)`、`Repository.with_trashed()` 方法
  - [ ] SubTask 12.6: 移除 `repositories.v` 中 `row_to_*` 手工映射重复代码，改用 `orm.OrmAdapter[T]` 自动映射
  - [ ] SubTask 12.7: 移除 `last_insert_rowid()` SQLite 专属调用，改用 `OrmAdapter` 抽象

- [ ] Task 13: 实现事务注解与多步操作原子性
  - [ ] SubTask 13.1: 在 `Demo/services.v` 的 `PostService.create_post`/`update_post`/`delete_post` 标注 `@[transactional]`
  - [ ] SubTask 13.2: 在 `CommentService.create_comment` 标注 `@[transactional]`（创建评论 + 更新文章评论数）
  - [ ] SubTask 13.3: 在 `UserService.register` 标注 `@[transactional]`（创建用户 + 初始化统计）
  - [ ] SubTask 13.4: 验证事务回滚：模拟 `register` 第二步失败，确认用户未创建

- [ ] Task 14: 实现数据库迁移目录化
  - [ ] SubTask 14.1: 创建 `Demo/database/migrations/20260101000001_create_users_table.v`（迁移自 `database.v` 的 CreateUsersTable，添加 `deleted_at` 列）
  - [ ] SubTask 14.2: 创建 `Demo/database/migrations/20260101000002_create_posts_table.v`
  - [ ] SubTask 14.3: 创建 `Demo/database/migrations/20260101000003_create_comments_table.v`
  - [ ] SubTask 14.4: 创建 `Demo/database/migrations/20260101000004_create_categories_table.v`
  - [ ] SubTask 14.5: 创建 `Demo/database/migrations/20260101000005_create_tags_table.v`
  - [ ] SubTask 14.6: 创建 `Demo/database/migrations/20260101000006_create_post_tags_table.v`
  - [ ] SubTask 14.7: 实现 `MigrationManager` 自动扫描 `database/migrations/*.v` 目录，按文件名时间戳排序加载
  - [ ] SubTask 14.8: 移除 `Demo/database.v` 中内联的 6 个迁移结构体（保留 `init_database`/`run_migrations`/`rollback_migrations` 薄封装）

- [ ] Task 15: 实现数据库种子与工厂
  - [ ] SubTask 15.1: 创建 `Demo/database/seeders/seeder.v`（Seeder 接口：`run() !`）
  - [ ] SubTask 15.2: 创建 `Demo/database/seeders/database_seeder.v`（DatabaseSeeder：调用 UserSeeder/PostSeeder/CommentSeeder）
  - [ ] SubTask 15.3: 创建 `Demo/database/seeders/user_seeder.v`（UserSeeder：1 ADMIN + 2 EDITOR + 5 USER，账号密码从 `.env` 读取）
  - [ ] SubTask 15.4: 创建 `Demo/database/seeders/post_seeder.v`（PostSeeder：10 篇文章，使用 UserFactory 随机作者）
  - [ ] SubTask 15.5: 创建 `Demo/database/seeders/comment_seeder.v`（CommentSeeder：20 条评论）
  - [ ] SubTask 15.6: 创建 `Demo/database/factories/user_factory.v`（UserFactory：`new()`/`with_role(role)`/`create() !User`/`make() User`）
  - [ ] SubTask 15.7: 创建 `Demo/database/factories/post_factory.v`（PostFactory）
  - [ ] SubTask 15.8: 创建 `Demo/database/factories/comment_factory.v`（CommentFactory）
  - [ ] SubTask 15.9: 重写 `Demo/commands.v` 的 `SeedCommand`，委托给 `DatabaseSeeder.run()`

## 阶段五：缓存、锁与安全升级

- [ ] Task 16: 实现缓存削峰与标签失效
  - [ ] SubTask 16.1: 重写 `Demo/services.v` 的 `PostService.get_post`/`get_posts`，使用 `cache.get_or_load()` + `Singleflight` 替换手写 `if cm.has(key) {...} else {...}`
  - [ ] SubTask 16.2: 重写 `StatsService.get_stats`，使用 `cache_remember` 辅助函数 + `@[cacheable]` 注解
  - [ ] SubTask 16.3: 重写 `UserService.get_user`，使用 `cache_remember`
  - [ ] SubTask 16.4: 实现 `TaggedCache` 标签失效：文章更新调用 `tagged_cache.flush('posts')`，用户更新调用 `flush('users')`，统计更新调用 `flush('stats')`
  - [ ] SubTask 16.5: 修复缓存损坏静默返回空 bug：`json.decode` 失败时删除缓存键并重新加载，而非返回空实体

- [ ] Task 17: 实现锁守卫 RAII
  - [ ] SubTask 17.1: 重写 `Demo/services.v` 的 `PostService.publish_post`/`update_post`，使用 `locking.new_lock_guard(mut lm, key)` 替换手写 `lock`/`unlock`
  - [ ] SubTask 17.2: 重写 `StatsService.aggregate_stats`，使用 `LockGuard`
  - [ ] SubTask 17.3: 移除所有手写 `lm.lock(key)`/`lm.unlock(key)` 调用

- [ ] Task 18: 实现安全升级
  - [ ] SubTask 18.1: 集成 `security.CsrfProtection`，对非 API 路由（Web 表单）启用 CSRF Token
  - [ ] SubTask 18.2: 集成 `security.SecurityFilterChain`，统一安全过滤链（CORS+CSRF+JwtAuth+RoleAuth）
  - [ ] SubTask 18.3: 实现 JWT 密钥生产环境校验：`APP_PROFILE=prod` 且 `JWT_SECRET` 为默认值/空时启动失败
  - [ ] SubTask 18.4: 角色层级从 `config/auth.v` 读取（移除 `bootstrap.v` 硬编码 `rh.add_role('ADMIN', ['EDITOR'])`）
  - [ ] SubTask 18.5: `fetch_github_avatar` 添加超时（5s）与重试（3 次指数退避），失败不阻塞注册

## 阶段六：CLI 命令升级

- [ ] Task 19: 实现 CLI 代码生成命令与命令完善
  - [ ] SubTask 19.1: 在 `Demo/commands.v` 注册 `cli.make:*` 命令（`make:controller`/`make:model`/`make:migration`/`make:middleware`/`make:provider`/`make:command`/`make:resource`/`make:seeder`/`make:factory`）
  - [ ] SubTask 19.2: 新增 `MigrateFreshCommand`（drop 所有表 + 重新迁移）、`MigrateRefreshCommand`（回滚 + 重新迁移）、`MigrateResetCommand`（回滚所有），注册到 CLI
  - [ ] SubTask 19.3: 重写 `ServeCommand.execute`，实际启动 veb 服务（移除空实现误导，参数 `--port`/`--host` 生效）
  - [ ] SubTask 19.4: `QueueWorkCommand` 修复控制流：仅 `worker.run()` 阻塞，移除多余 `for worker.is_running() { worker.tick() }`
  - [ ] SubTask 19.5: `SchedulerRunCommand` 添加信号处理（SIGINT/SIGTERM 优雅退出）
  - [ ] SubTask 19.6: 所有命令补充 `sig` 签名参数定义（如 `sig: '[--port=8080] [--host=0.0.0.0]'`）
  - [ ] SubTask 19.7: 新增 `DocsCommand`（生成 API 文档，调用 `apidoc` 模块）

## 阶段七：Make 脚本集与容器化

- [x] Task 20: 实现 Makefile 全生命周期覆盖
  - [ ] SubTask 20.1: 重写 `Demo/Makefile`，定义变量（`V`/`VFLAGS`/`BIN`/`BIN_DIR`/`PROFILE`/`DB_PATH`），支持 `PROFILE=dev|prod|test` 切换
  - [ ] SubTask 20.2: 实现环境初始化 target：`setup`（检查 V 编译器 + 加载 .env + build + migrate + seed）、`install`（编译安装到 `/usr/local/bin`）、`uninstall`
  - [ ] SubTask 20.3: 实现开发 target：`dev`（watch 模式热重载，`v -enable-globals watch .`）、`run`/`serve`（build + 启动）、`watch`（文件监听重启）
  - [ ] SubTask 20.4: 实现构建 target：`build`（debug 构建）、`build-release`/`release`（`-d release -cflags "-O2"` 优化构建到 `bin/demo`）、`release-package`（tar 打包 bin + config + .env.example）
  - [ ] SubTask 20.5: 实现测试 target：`test`、`test-unit`（仅 `*_test.v` 单元测试）、`test-integration`（仅 `integration_test.v`）、`test-coverage`（覆盖率报告）
  - [ ] SubTask 20.6: 实现数据库 target：`migrate`、`migrate-rollback`、`migrate-refresh`、`migrate-fresh`、`migrate-reset`、`migrate-status`、`seed`、`seed-fresh`（migrate-fresh + seed）、`db-shell`（sqlite3 CLI）
  - [ ] SubTask 20.7: 实现运行时 target：`queue-work`、`queue-restart`、`scheduler-run`、`routes`、`stats`
  - [ ] SubTask 20.8: 实现代码质量 target：`lint`（`v vet`）、`fmt`（`v fmt -w .`）、`check`（lint + fmt + test）
  - [ ] SubTask 20.9: 实现容器化 target：`docker`（build 镜像）、`docker-up`（docker-compose up -d）、`docker-down`、`docker-logs`（支持 `service=` 过滤）
  - [ ] SubTask 20.10: 实现清理 target：`clean`（移除 bin + *.db）、`clean-all`/`distclean`（clean + storage/logs + storage/uploads + docs/api）
  - [ ] SubTask 20.11: 实现辅助 target：`logs`（tail storage/logs/app.log）、`shell`（进入应用 shell）、`benchmark`/`bench`（性能基准）、`docs`（生成 API 文档）
  - [ ] SubTask 20.12: 实现 `help` target 自动从 target 注释 `##` 生成分类帮助列表
  - [ ] SubTask 20.13: 所有 target 添加 `.PHONY` 声明，确保正确触发

- [x] Task 21: 实现 docker-compose.yml 多服务编排
  - [ ] SubTask 21.1: 创建 `Demo/docker-compose.yml`，定义服务：`app`（Web 服务，端口 8080）、`db`（SQLite 卷挂载 或 PostgreSQL）、`redis`（缓存/队列后端）、`queue`（队列 Worker，复用 app 镜像）、`scheduler`（定时调度器）
  - [ ] SubTask 21.2: 配置 `app` 服务 healthcheck（`curl localhost:8080/health`）、`queue`/`scheduler` 依赖 `app` 健康后启动
  - [ ] SubTask 21.3: 配置卷挂载：`./storage:/app/storage`、`./config:/app/config`、`./.env:/app/.env:ro`
  - [ ] SubTask 21.4: 创建 `Demo/docker-compose.prod.yml`（生产覆盖：资源限制、重启策略、日志驱动）
  - [ ] SubTask 21.5: 更新 `Demo/Dockerfile`：多阶段构建优化（builder 用 V 编译器，runtime 用 distroless 或 alpine）、多架构支持（`linux/amd64`+`linux/arm64`）、非 root 用户、healthcheck

## 阶段八：文档与 API 文档

- [ ] Task 22: 实现 API 文档自动生成
  - [ ] SubTask 22.1: 集成 `apidoc` 模块到 `bootstrap/app.v`，注册 API 文档收集器
  - [ ] SubTask 22.2: 为所有控制器方法添加 `@[apidoc]` 注解（summary/description/params/responses/tags）
  - [ ] SubTask 22.3: 实现 `DocsCommand`，调用 `apidoc.generate()` 输出到 `docs/api/`
  - [ ] SubTask 22.4: 验证 `make docs` 生成 `docs/api/index.html` + `openapi.json`

- [ ] Task 23: 完善文档体系
  - [ ] SubTask 23.1: 重写 `Demo/README.md`：项目介绍、特性列表、环境要求、快速开始（make setup/dev/run）、目录结构、架构图（Mermaid）、API 文档链接、部署指南（Docker/二进制）、故障排查、贡献指南链接
  - [ ] SubTask 23.2: 创建 `Demo/docs/architecture.md`：Demo 级架构文档（请求生命周期、DI 容器、数据流、调用链、设计决策、与 Laravel 对比）
  - [ ] SubTask 23.3: 创建 `Demo/CONTRIBUTING.md`：开发环境搭建、代码规范、提交规范、PR 流程、测试要求
  - [ ] SubTask 23.4: 创建 `Demo/CHANGELOG.md`：版本变更记录（Keep a Changelog 格式）
  - [ ] SubTask 23.5: 创建 `Demo/LICENSE`（MIT）
  - [ ] SubTask 23.6: 创建 `Demo/.editorconfig`（V 语言缩进规范：tab 缩进、UTF-8、LF 换行）

## 阶段九：测试升级

- [ ] Task 24: 实现测试基类与工厂集成
  - [ ] SubTask 24.1: 创建 `Demo/tests/test_case.v`（TestCase 基类：`setup`/`teardown`/`refresh_database`/`acting_as(user)`/`json_request(method, path, body) !TestResponse`）
  - [ ] SubTask 24.2: 创建 `Demo/tests/refresh_database.v`（RefreshDatabase trait：每个测试前 migrate:fresh）
  - [ ] SubTask 24.3: 重写所有测试文件（`auth_test.v`/`controller_test.v`/`integration_test.v` 等）继承 `TestCase`，使用 `acting_as`/`json_request` 替换手写请求
  - [ ] SubTask 24.4: 测试数据改用 Factory 生成（`UserFactory.new().with_role('admin').create()`），移除内联 `seed_user` 重复代码
  - [ ] SubTask 24.5: 新增 `tests/validation_test.v`（测试 `web.validate[T]` 各规则：required/email/min_len/max_len/confirmed 等）
  - [ ] SubTask 24.6: 新增 `tests/exception_test.v`（测试异常处理器：各 HttpException 返回正确状态码与格式）
  - [ ] SubTask 24.7: 新增 `tests/resource_test.v`（测试 API Resource 字段脱敏：UserResource 不输出 password）
  - [ ] SubTask 24.8: 新增 `tests/pagination_test.v`（测试 LengthAwarePaginator 元数据正确性）
  - [ ] SubTask 24.9: 新增 `tests/soft_delete_test.v`（测试软删除查询过滤、restore、force_delete）
  - [ ] SubTask 24.10: 新增 `tests/eager_loading_test.v`（测试预加载 N+1 消除，SQL 计数）

## 阶段十：最终验证

- [ ] Task 25: 全量验证与回归测试
  - [ ] SubTask 25.1: 验证 `make setup` 一键初始化成功（编译 + 迁移 + 种子）
  - [ ] SubTask 25.2: 验证 `make dev` 热重载模式启动
  - [ ] SubTask 25.3: 验证 `make build` 与 `make release` 均编译成功，release 二进制为优化构建
  - [ ] SubTask 25.4: 验证 `make test` 全部测试通过（含新增验证/异常/Resource/分页/软删除/预加载测试）
  - [ ] SubTask 25.5: 验证 `make migrate-fresh && make seed` 重置数据库并插入种子数据
  - [ ] SubTask 25.6: 验证 `make docker-up` 启动全部服务，`curl localhost:8080/health` 返回 200
  - [ ] SubTask 25.7: 验证 `make docs` 生成 API 文档，浏览器可访问
  - [ ] SubTask 25.8: 验证 `make help` 自动生成分类帮助列表
  - [ ] SubTask 25.9: 验证所有 29 个 API 端点功能正常（curl 全量回归）
  - [ ] SubTask 25.10: 验证所有 9+ 个 CLI 命令功能正常（serve/migrate/seed/queue/scheduler/stats/routes/make:*）
  - [ ] SubTask 25.11: 验证生产环境 JWT 密钥校验：`APP_PROFILE=prod JWT_SECRET= ./demo serve` 启动失败
  - [ ] SubTask 25.12: 验证 `User.password` 字段未在任何 API 响应中泄露
  - [ ] SubTask 25.13: 验证无 `unsafe { voidptr(x) }` 类型擦除 DI 残留
  - [ ] SubTask 25.14: 验证无手写 JSON 字符串拼接残留（grep `'{"success"` 应无结果）
  - [ ] SubTask 25.15: 验证无内联校验残留（grep `if dto.*.len == 0` 应无结果）

# Task Dependencies

- Task 2 依赖 Task 1（config/ 目录需要骨架目录）
- Task 3 依赖 Task 2（helpers 引用 config 类型）
- Task 4 依赖 Task 2, 3（Provider 需要 config 与 helpers）
- Task 5 依赖 Task 4（AppKernel 注册 Provider）
- Task 6 依赖 Task 5（main.v 调用 AppKernel）
- Task 7-11 依赖 Task 6（Web 层升级需要新启动流程）
- Task 12 依赖 Task 11（仓储升级支持分页）
- Task 13 依赖 Task 12（事务标注在 Service）
- Task 14 依赖 Task 12（迁移目录化需要新实体定义）
- Task 15 依赖 Task 14（Seeder/Factory 需要迁移就绪）
- Task 16-18 依赖 Task 13（缓存/锁/安全升级在 Service 层）
- Task 19 依赖 Task 15（CLI 命令调用 Seeder）
- Task 20 依赖 Task 19（Makefile target 调用 CLI 命令）
- Task 21 依赖 Task 20（docker-compose 依赖 Makefile）
- Task 22 依赖 Task 7（API 文档需要控制器注解）
- Task 23 依赖 Task 21（文档引用 Make 与 Docker）
- Task 24 依赖 Task 15, 22（测试用 Factory + 验证 API）
- Task 25 依赖 Task 1-24（最终验证需要全部完成）

# 可并行任务

- Task 2（config/ 拆分）与 Task 3（helpers）可并行
- Task 7（响应/异常）与 Task 8（验证）可并行（不同文件区域）
- Task 9（中间件组）与 Task 10（API Resource）可并行
- Task 14（迁移目录化）与 Task 15（Seeder/Factory）部分可并行（Seeder 依赖迁移但 Factory 不依赖）
- Task 16（缓存）与 Task 17（锁）可并行
- Task 22（API 文档）与 Task 23（文档体系）可并行
- Task 24 的各 SubTask（新增测试文件）可并行
