# PhotonBlog 测试套件检查清单

## Task 23: 测试套件实现

### SubTask 23.1: config_test.v ✅
- [x] 三套 profile 加载（dev/prod/test）
- [x] 环境变量覆盖（APP_SERVER_PORT）
- [x] 默认值回退
- [x] 配置校验（必填字段）
- [x] 邮件配置差异
- [x] JWT 配置
- [x] 存储配置
- **7 个测试函数**

### SubTask 23.2: models_test.v ✅
- [x] User 实体创建与默认值
- [x] Post 实体创建与状态默认值
- [x] Comment 实体创建与嵌套评论
- [x] Category 实体创建
- [x] Tag 实体创建
- [x] DTO 校验（CreateUserDto/CreatePostDto/CreateCommentDto/CreateCategoryDto/CreateTagDto）
- [x] slug 生成（中文/空格/特殊字符）
- [x] API 响应封装（ApiResponse/ApiError/PaginatedResponse）
- **21 个测试函数**

### SubTask 23.3: repository_test.v ✅
- [x] User CRUD + exists_by_username/exists_by_email
- [x] Post CRUD + count_by_status/find_published
- [x] Comment CRUD + find_by_post/find_replies
- [x] Category CRUD + exists_by_slug
- [x] Tag CRUD + attach/find_tags
- [x] 所有测试使用内存 SQLite
- **22 个测试函数**

### SubTask 23.4: service_test.v ✅
- [x] UserService 注册/登录/修改密码/用户名邮箱唯一性
- [x] AuthService JWT 生成/验证/刷新/解析/角色校验
- [x] PostService CRUD + 缓存 + slug 生成
- [x] CommentService 创建/嵌套评论/按文章查询
- [x] CategoryService CRUD + slug 自动生成 + 唯一性
- [x] TagService CRUD + slug 自动生成
- [x] StatsService 聚合统计 + 缓存
- [x] UploadService 上传处理
- **32 个测试函数**

### SubTask 23.5: auth_test.v ✅
- [x] JWT 生成与验证
- [x] JWT 刷新令牌
- [x] JWT 过期处理
- [x] BCrypt 哈希与校验
- [x] 角色层级（ADMIN > EDITOR > USER > GUEST）
- [x] 角色权限校验（has_role/has_any_role/check_permission）
- [x] 令牌解析与 claims
- **14 个测试函数**

### SubTask 23.6: event_test.v ✅
- [x] EventBus 基础注册与派发
- [x] 事件 payload 传递
- [x] 事件 data_map 传递
- [x] 多监听器注册
- [x] 监听器计数
- [x] has_listeners/off
- [x] 事件传播停止（stop_propagation）
- [x] 事件常量定义
- [x] Bootstrap 集成事件监听
- **15 个测试函数**

### SubTask 23.7: job_test.v ✅ (queue_test)
- [x] Job 派发
- [x] Job 序列化/反序列化
- [x] Worker 注册与启动
- [x] 队列计数与清理
- [x] SendWelcomeEmailJob
- [x] SendNewCommentNotificationJob
- [x] ProcessPostViewJob
- [x] CleanupExpiredSessionsJob
- **12 个测试函数**

### SubTask 23.8: middleware_test.v ✅
- [x] CORS 中间件
- [x] 限流中间件（正常请求/超限拒绝/窗口重置）
- [x] JWT 认证中间件（有效令牌/无效令牌/过期令牌/缺失令牌）
- [x] 角色校验中间件
- [x] 全局中间件应用
- **14 个测试函数**

### SubTask 23.9: integration_test.v ✅
- [x] Bootstrap 初始化完整性
- [x] ApplicationContext Bean 注册
- [x] 完整请求生命周期（注册→登录→JWT→角色校验→刷新→响应）
- [x] 跨服务协作（用户+文章+评论+缓存）
- [x] 角色层级权限校验集成
- [x] 缓存失效与一致性
- [x] 数据库迁移与回滚
- [x] 配置驱动行为差异
- [x] 事件驱动集成
- [x] slug 自动生成集成
- [x] 统计服务缓存集成
- [x] 密码修改与重新登录
- **12 个测试函数**

### SubTask 23.10: 所有测试真实运行通过 ✅
- [x] 无空测试体
- [x] 无 TODO/FIXME
- [x] 每个测试包含真实的 setup → act → assert 流程

### 额外测试文件
- cache_test.v: **13 个测试函数**（缓存管理器、内存缓存、TTL、LRU 等）
- controller_test.v: **18 个测试函数**（所有 API 控制器端点测试）

---

## Task 24: 最终验证

### SubTask 24.1: 全量编译 ✅
- [x] `v -enable-globals .` 零错误编译成功

### SubTask 24.2: 全量测试 ✅
- [x] `v -enable-globals test .` 全部 11 个测试文件通过
- [x] 共 180 个测试函数全部通过

### SubTask 24.3: CLI 验证 ✅
- [x] `./demo list` 正常输出所有命令
- [x] `./demo migrate` 正常执行迁移
- [x] `./demo migrate:status` 正常显示状态
- [x] `./demo stats` 正常显示统计
- [x] `./demo routes` 正常列出路由

### SubTask 24.4: HTTP 服务验证 ✅
- [x] `./demo serve` 启动 HTTP 服务成功
- [x] `GET /health` 返回 `{"success":true,"code":200,...}`
- [x] `GET /ping` 返回 `pong`
- [x] `GET /` 返回应用信息 JSON
- [x] `POST /api/v1/auth/register` 注册端点可用
- [x] 29 条路由全部注册

### SubTask 24.5: 无硬编码/打桩/简化 ✅
- [x] 所有测试使用变量而非硬编码值
- [x] 断言使用实际返回值
- [x] 无空测试体或 TODO
- [x] 数据库测试使用 `:memory:` SQLite
- [x] 每个测试独立初始化数据

### SubTask 24.6: Bug 修复记录 ✅
- [x] **Bug 1**: `orm/migration.v` 的 `unique_()` 方法错误地将 UNIQUE 约束标记到最后一列而非指定列 → 已修复
- [x] **Bug 2**: `middleware.v` 的 `RateLimitMiddleware` 字段 `max_requests`/`window_secs` 不可变 → 已修复（改为 `pub mut`）
- [x] **Bug 3**: `event_test.v` 闭包捕获可变变量不生效 → 已修复（使用 `&SharedState` 堆分配结构体）

---

## 测试统计

| 测试文件 | 测试数量 | 状态 |
|---------|---------|------|
| config_test.v | 7 | ✅ |
| models_test.v | 21 | ✅ |
| repository_test.v | 22 | ✅ |
| service_test.v | 32 | ✅ |
| auth_test.v | 14 | ✅ |
| event_test.v | 15 | ✅ |
| job_test.v | 12 | ✅ |
| middleware_test.v | 14 | ✅ |
| integration_test.v | 12 | ✅ |
| cache_test.v | 13 | ✅ |
| controller_test.v | 18 | ✅ |
| **合计** | **180** | **✅** |
