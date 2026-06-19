# Checklist

## 阶段一：项目骨架重构

- [ ] `Demo/config/`、`Demo/routes/`、`Demo/providers/`、`Demo/app/Http/Controllers/`、`Demo/app/Http/Resources/`、`Demo/app/Http/Middleware/`、`Demo/database/migrations/`、`Demo/database/seeders/`、`Demo/database/factories/`、`Demo/tests/`、`Demo/docs/api/`、`Demo/storage/logs/`、`Demo/bin/` 目录已创建
- [ ] `Demo/.env.example` 存在，包含全部环境变量模板（APP_PROFILE/APP_DEBUG/APP_PORT/DB_PATH/JWT_SECRET/CACHE_DRIVER/MAIL_DRIVER/LOG_LEVEL/LOG_CHANNEL 等）
- [ ] `Demo/.env`（dev 默认值）、`Demo/.env.prod.example`、`Demo/.env.testing` 存在
- [ ] `Demo/.gitignore` 已更新，忽略 `.env`、`bin/`、`storage/logs/*.log`、`storage/uploads/`、`*.db`、`docs/api/`
- [ ] `Demo/config/app.v`/`database.v`/`jwt.v`/`cache.v`/`mail.v`/`storage.v`/`logging.v`/`web.v`/`auth.v` 9 个配置文件存在，按关注点拆分
- [ ] `Demo/config.v` 的 `load_config(profile)` 扫描 `config/*.v` + 加载 `.env` + `Environment.resolve_placeholders` 解析占位符
- [ ] 生产环境密钥校验：`APP_PROFILE=prod` 且 `JWT_SECRET` 为默认值/空时启动失败
- [ ] `Demo/helpers.v` 存在，包含 `generate_request_id`/`generate_slug`/`now_unix`/`cache_remember`/`parse_pagination`/`parse_sort`

## 阶段二：服务提供者与启动流程

- [ ] `Demo/providers/` 目录包含 9 个 ServiceProvider（App/Database/Cache/Web/Auth/Queue/Event/Repository/Service）
- [ ] 每个 Provider 实现 `core.ServiceProvider` 接口（`register()`/`boot()`）
- [ ] `Demo/bootstrap/app.v` 存在，`AppKernel` 注册所有 Provider 并调用 `register_all()` + `boot_all()`
- [ ] `AppKernel.get_service[T](name) !&T` 类型安全服务获取，无 `unsafe { voidptr(x) }` 类型擦除
- [ ] `Demo/bootstrap/console.v` 存在，`print_routes` 从 `web.scan_controller[App]()` 实际结果生成（非硬编码）
- [ ] `Demo/bootstrap.v` 为薄封装，委托给 `bootstrap/app.v`
- [ ] `Demo/routes/api.v` 与 `Demo/routes/web.v` 存在，路由分组定义
- [ ] `Demo/main.v` 重写：加载 .env → load_config → new_app_kernel → bootstrap → 注册中间件组 → 注册路由 → CLI/Web 分发
- [ ] `App.req_count` 数据竞争已修复（`sync.atomic` 或 `sync.Mutex`）

## 阶段三：Web 层升级

- [ ] `Demo/app/Http/Kernel.v` 存在，注册 `ExceptionHandlerRegistry`，覆盖所有 `HttpException` 子类
- [ ] 默认异常处理器捕获未知异常返回 500，生产环境隐藏堆栈
- [ ] `Demo/controllers.v` 所有响应使用 `web.success`/`web.fail`/`web.page`/`web.ok`/`web.created`/`web.bad_request` 等
- [ ] 无手写 JSON 字符串拼接（grep `'{"success"` 无结果）
- [ ] `Demo/models.v` 所有 DTO 标注 `@[validate: '...']` 规则
- [ ] `Demo/controllers.v` 所有校验使用 `web.validate_body[T]` 或 `web.validate[T]`，无内联 `if dto.x.len == 0`
- [ ] `parse_body_or_form` 与 7 个 `build_*_dto` 函数已移除
- [ ] `Demo/app/Http/Middleware/registry.v` 使用 `web.MiddlewareGroupRegistry` 注册 `web`/`api`/`auth`/`admin`/`editor` 命名组
- [ ] 中间件参数从 `config/web.v` 读取（CORS/RateLimit 配置驱动）
- [ ] 使用 `web.throttle_middleware`/`web.role_middleware`/`web.cors_configurable_middleware`
- [ ] `MiddlewareManager` 已移除
- [ ] `JwtAuthMiddleware` 认证成功后将 `user_id`/`username`/`role` 写回 `Context`
- [ ] `Demo/app/Http/Resources/` 包含 UserResource/PostResource/CommentResource/CategoryResource/TagResource
- [ ] `UserResource` 不输出 `password`/`version` 字段
- [ ] `PostResource` 支持嵌套 `author`/`category`/`tags`
- [ ] `Demo/app/Http/Resources/collection.v` 提供 `ResourceCollection[T]`
- [ ] `Demo/controllers.v` 所有 `json.encode(entity)` 改为 `XxxResource(entity).to_json()`
- [ ] `User.password` 字段已私有化（移除 `pub`）
- [ ] 列表端点使用 `support.LengthAwarePaginator[T]`，无手写 `start..end` 切片
- [ ] 分页响应包含 `meta`/`links` 元数据
- [ ] 过滤/排序下沉到 Repository SQL 层，控制器无内存过滤
- [ ] `models.v` 中 `ApiResponseDto`/`success_response`/`error_response` 死代码已移除

## 阶段四：ORM 与数据层升级

- [ ] `Demo/repositories.v` 仓储继承 `orm.EagerRepository[T]`，支持 `with()` 预加载
- [ ] `PostRepository.find_with_filters` 实现过滤/排序/分页下沉到 SQL
- [ ] 实体使用 `orm.SoftDeletableEntity`（`deleted_at` 字段）
- [ ] `Repository.restore(id)`/`force_delete(id)`/`with_trashed()` 方法实现
- [ ] `row_to_*` 手工映射已移除，改用 `orm.OrmAdapter[T]` 自动映射
- [ ] `last_insert_rowid()` SQLite 专属调用已移除
- [ ] `PostService.create_post`/`update_post`/`delete_post` 标注 `@[transactional]`
- [ ] `CommentService.create_comment` 标注 `@[transactional]`
- [ ] `UserService.register` 标注 `@[transactional]`
- [ ] 事务回滚验证通过（模拟失败确认回滚）
- [ ] `Demo/database/migrations/` 包含 6 个时间戳命名的迁移文件
- [ ] `MigrationManager` 自动扫描 `database/migrations/*.v` 按时间戳排序
- [ ] `Demo/database.v` 内联迁移结构体已移除，保留薄封装
- [ ] `Demo/database/seeders/` 包含 Seeder 接口 + DatabaseSeeder/UserSeeder/PostSeeder/CommentSeeder
- [ ] 种子数据账号密码从 `.env` 读取
- [ ] `Demo/database/factories/` 包含 UserFactory/PostFactory/CommentFactory
- [ ] `SeedCommand` 委托给 `DatabaseSeeder.run()`

## 阶段五：缓存、锁与安全升级

- [ ] `PostService.get_post`/`get_posts` 使用 `cache.get_or_load()` + `Singleflight`
- [ ] `StatsService.get_stats` 使用 `cache_remember` + `@[cacheable]` 注解
- [ ] `UserService.get_user` 使用 `cache_remember`
- [ ] `TaggedCache` 标签失效实现（`posts`/`users`/`stats` 标签）
- [ ] 缓存损坏时删除缓存键并重新加载（非返回空实体）
- [ ] `PostService.publish_post`/`update_post` 使用 `locking.new_lock_guard`
- [ ] `StatsService.aggregate_stats` 使用 `LockGuard`
- [ ] 无手写 `lm.lock(key)`/`lm.unlock(key)` 残留
- [ ] `security.CsrfProtection` 集成（Web 表单场景）
- [ ] `security.SecurityFilterChain` 统一过滤链集成
- [ ] JWT 密钥生产环境校验生效
- [ ] 角色层级从 `config/auth.v` 读取（无硬编码）
- [ ] `fetch_github_avatar` 添加超时（5s）与重试（3 次指数退避）

## 阶段六：CLI 命令升级

- [ ] `cli.make:*` 命令注册（make:controller/model/migration/middleware/provider/command/resource/seeder/factory）
- [ ] `MigrateFreshCommand`/`MigrateRefreshCommand`/`MigrateResetCommand` 注册到 CLI
- [ ] `ServeCommand.execute` 实际启动 veb 服务（参数生效）
- [ ] `QueueWorkCommand` 控制流修复（仅 `worker.run()` 阻塞）
- [ ] `SchedulerRunCommand` 添加信号处理（SIGINT/SIGTERM 优雅退出）
- [ ] 所有命令补充 `sig` 签名参数定义
- [ ] `DocsCommand` 实现并注册

## 阶段七：Make 脚本集与容器化

- [ ] `Demo/Makefile` 重写，覆盖 30+ target
- [ ] `setup` target：检查 V 编译器 + 加载 .env + build + migrate + seed
- [ ] `dev` target：watch 模式热重载
- [ ] `build`/`build-release`/`release` target：debug 与优化构建区分
- [ ] `test`/`test-unit`/`test-integration`/`test-coverage` target
- [ ] `migrate`/`migrate-rollback`/`migrate-refresh`/`migrate-fresh`/`migrate-reset`/`migrate-status` target
- [ ] `seed`/`seed-fresh`/`db-shell` target
- [ ] `queue-work`/`queue-restart`/`scheduler-run`/`routes`/`stats` target
- [ ] `lint`/`fmt`/`check` target
- [ ] `docker`/`docker-up`/`docker-down`/`docker-logs` target
- [ ] `clean`/`clean-all`/`distclean` target
- [ ] `install`/`uninstall`/`release-package`/`benchmark`/`watch`/`logs`/`shell`/`docs` target
- [ ] `help` target 自动从 `##` 注释生成分类帮助
- [ ] 所有 target 添加 `.PHONY` 声明
- [ ] `Demo/docker-compose.yml` 存在，定义 app/db/redis/queue/scheduler 五服务
- [ ] `app` 服务 healthcheck 配置（`curl localhost:8080/health`）
- [ ] 卷挂载配置（storage/config/.env）
- [ ] `Demo/docker-compose.prod.yml` 存在（生产覆盖）
- [ ] `Demo/Dockerfile` 优化：多阶段构建、多架构、非 root 用户、healthcheck

## 阶段八：文档与 API 文档

- [ ] `apidoc` 模块集成到 `bootstrap/app.v`
- [ ] 所有控制器方法添加 `@[apidoc]` 注解
- [ ] `DocsCommand` 调用 `apidoc.generate()` 输出到 `docs/api/`
- [ ] `make docs` 生成 `docs/api/index.html` + `openapi.json`
- [ ] `Demo/README.md` 重写：介绍/特性/环境要求/快速开始/目录结构/架构图/API 文档链接/部署指南/故障排查
- [ ] `Demo/docs/architecture.md` 存在：请求生命周期/DI/数据流/调用链/设计决策/与 Laravel 对比
- [ ] `Demo/CONTRIBUTING.md` 存在：开发环境/代码规范/提交规范/PR 流程/测试要求
- [ ] `Demo/CHANGELOG.md` 存在（Keep a Changelog 格式）
- [ ] `Demo/LICENSE` 存在（MIT）
- [ ] `Demo/.editorconfig` 存在（V 语言缩进规范）

## 阶段九：测试升级

- [ ] `Demo/tests/test_case.v` 存在，TestCase 基类实现 `refresh_database`/`acting_as`/`json_request`
- [ ] `Demo/tests/refresh_database.v` 存在，RefreshDatabase trait
- [ ] 所有测试文件继承 TestCase，使用 `acting_as`/`json_request`
- [ ] 测试数据使用 Factory 生成，无内联 `seed_user` 重复
- [ ] `tests/validation_test.v` 测试各验证规则
- [ ] `tests/exception_test.v` 测试异常处理器
- [ ] `tests/resource_test.v` 测试 API Resource 字段脱敏
- [ ] `tests/pagination_test.v` 测试 LengthAwarePaginator 元数据
- [ ] `tests/soft_delete_test.v` 测试软删除查询过滤/restore/force_delete
- [ ] `tests/eager_loading_test.v` 测试预加载 N+1 消除

## 阶段十：最终验证

- [ ] `make setup` 一键初始化成功
- [ ] `make dev` 热重载模式启动
- [ ] `make build` 与 `make release` 均编译成功
- [ ] `make test` 全部测试通过（含新增测试）
- [ ] `make migrate-fresh && make seed` 重置并插入种子
- [ ] `make docker-up` 启动全部服务，`curl localhost:8080/health` 返回 200
- [ ] `make docs` 生成 API 文档，浏览器可访问
- [ ] `make help` 自动生成分类帮助
- [ ] 所有 29 个 API 端点 curl 全量回归通过
- [ ] 所有 9+ 个 CLI 命令功能正常
- [ ] 生产环境 JWT 密钥校验：空密钥启动失败
- [ ] `User.password` 未在任何 API 响应中泄露
- [ ] 无 `unsafe { voidptr(x) }` 类型擦除 DI 残留
- [ ] 无手写 JSON 字符串拼接残留（grep 验证）
- [ ] 无内联校验残留（grep 验证）

## 最终完整性验证

- [ ] 项目无打桩代码（无 TODO/FIXME/stub 注释）
- [ ] 项目无硬编码（所有可配置项通过 config/.env 读取）
- [ ] 项目无简化实现（所有 API 完整实现业务逻辑）
- [ ] 17 个框架模块均被实际使用（含新增 apidoc）
- [ ] 项目可独立运行，无需修改任何框架代码
- [ ] 项目代码遵循 V 语言官方风格指南
- [ ] 目录结构对标 Laravel 骨架（config/routes/providers/app/Http/database/tests/docs）
- [ ] Make 脚本覆盖全生命周期 30+ target
- [ ] 文档体系完整（README/architecture/contributing/changelog/license）
