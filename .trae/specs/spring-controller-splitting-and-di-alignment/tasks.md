# Tasks

## Phase A — Web 模块任意包控制器拆分

- [ ] Task A1: 实现 `web.mount[T]` comptime 控制器挂载核心
  - [ ] SubTask A1.1: 在 `web/router.v` 新增 `MountOptions` 结构体（`prefix string`、`middlewares []string`）与 `mount[T](mut rr &RouteRegistry, mut ctx &core.ApplicationContext, opts MountOptions)` comptime 函数签名
  - [ ] SubTask A1.2: 实现 comptime 扫描逻辑——`$for method in T.methods` 检测 `@[get]`/`@[post]`/`@[put]`/`@[delete]`/`@[patch]` 与 `@['/path']` 属性，解析 HTTP 方法与路径
  - [ ] SubTask A1.3: 实现 `@[group('/prefix')]` 类级注解扫描——`$for attr in T.attributes` 提取前缀，与 `opts.prefix` 合并
  - [ ] SubTask A1.4: 实现包装闭包生成器 `warp_handler[T](method, ctx)`——每次请求 `mut ctrl := T{}`，通过 comptime 填充 `veb.Context` 嵌入字段与 `@[autowired]` 服务字段，调用控制器方法
  - [ ] SubTask A1.5: 将生成的路由注册到 `RouteRegistry`（复用 `rr.register(method, path, handler)`）
- [ ] Task A2: 扩展 `dispatcher.v` 支持通配符 `*filepath`
  - [ ] SubTask A2.1: `RouteSegment` 新增 `is_wildcard bool` 字段
  - [ ] SubTask A2.2: `parse_path` 识别 `*name` 段为通配符段
  - [ ] SubTask A2.3: `match_route` 支持通配符段匹配剩余所有路径并捕获为参数
- [ ] Task A3: 激活 `WebModule` 嵌入分发模式
  - [ ] SubTask A3.1: `WebModule` 新增 `mount[T](mut ctx, opts)` 方法委托到 `router.mount[T]`
  - [ ] SubTask A3.2: `handle_request` 增强——匹配成功返回 true，未匹配返回 false（向后兼容 veb 原生路由）
  - [ ] SubTask A3.3: 在 `web/web.v` 文档注释更新使用示例
- [ ] Task A4: 控制器方法级中间件织入
  - [ ] SubTask A4.1: `scan_controller`/`mount[T]` 扫描方法 `@[middleware('name1','name2')]` 属性
  - [ ] SubTask A4.2: `RouteDef` 新增 `middlewares []string` 字段
  - [ ] SubTask A4.3: `dispatch` 执行路由前按序调用命名中间件（从 `MiddlewareGroupRegistry` 解析）
- [ ] Task A5: 控制器方法返回值兼容
  - [ ] SubTask A5.1: 包装闭包支持控制器方法返回 `veb.Result`
  - [ ] SubTask A5.2: 包装闭包支持控制器方法返回 `!`（错误传播，转换为 500 响应）
  - [ ] SubTask A5.3: 包装闭包支持控制器方法返回 `!veb.Result`

## Phase B — Core DI 深度对齐 Spring

- [ ] Task B1: 修复字段注入按类型解析
  - [ ] SubTask B1.1: `scanner.v` `scan_and_register[T]` 中通过 comptime `$if field.typ is &X` 分支提取类型名，替换 `field.name` 作为 `Dependency.type_name`
  - [ ] SubTask B1.2: 保留 `@[qualifier('name')]` 按名解析旁路（`Dependency.qualifier` 非空时优先按名）
  - [ ] SubTask B1.3: 更新 `autowire_bean[T]`（`application_context.v`）按新 `type_name` 解析
  - [ ] SubTask B1.4: 编写 `core/di_type_injection_test.v` 验证按类型注入
- [ ] Task B2: 实现构造器注入
  - [ ] SubTask B2.1: `scanner.v` 新增 `extract_constructor[T](mut def BeanDefinition)`——扫描 `@[autowired]` 标注的 `init` 方法，提取参数类型作为构造依赖
  - [ ] SubTask B2.2: `BeanDefinition` 新增 `constructor_params []Dependency` 字段
  - [ ] SubTask B2.3: `application_context.v` `create_and_wire[T]` 改为：若有构造器，comptime 解析参数后调用 `T.init(dep1, dep2)`；否则保持 `T{}` 零值 + 字段注入
  - [ ] SubTask B2.4: 编写 `core/di_constructor_injection_test.v` 验证单参数与多参数构造器
- [ ] Task B3: 激活 `AutowiredAnnotationPostProcessor`
  - [ ] SubTask B3.1: `post_processor.v` `post_process_after_initialization` 改为调用 comptime 生成的字段注入闭包
  - [ ] SubTask B3.2: 验证 `refresh()` 阶段 bean 字段被正确注入
- [ ] Task B4: 实现 Request 作用域
  - [ ] SubTask B4.1: `core/core.v` 新增 `RequestScopeManager` 结构体（线程本地请求作用域栈）
  - [ ] SubTask B4.2: `RequestScopeManager.begin_request()` / `end_request()` 管理请求作用域生命周期
  - [ ] SubTask B4.3: `resolve_unlocked` 对 `.request` 作用域 bean 从 `RequestScopeManager` 当前作用域解析
  - [ ] SubTask B4.4: `web` 模块在 `before_request` 调用 `begin_request`，`after_request` 调用 `end_request`
  - [ ] SubTask B4.5: 编写 `core/di_request_scope_test.v` 验证请求内单例与跨请求隔离
- [ ] Task B5: 新增 `@[order(n)]` 注解
  - [ ] SubTask B5.1: `scanner.v` 新增 `attr_order` 常量与 `extract_order[T]()` 函数
  - [ ] SubTask B5.2: `scan_and_register` 填充 `BeanDefinition.order_`
  - [ ] SubTask B5.3: `resolve_all_by_interface`/`resolve_all_by_tag` 按 `order_` 升序排序返回
  - [ ] SubTask B5.4: 编写 `core/di_order_test.v` 验证排序
- [ ] Task B6: 新增 `@[profile('dev')]` 注解
  - [ ] SubTask B6.1: `scanner.v` 新增 `attr_profile` 常量，`scan_and_register` 扫描后转换为 `conditional_on_profile` 条件
  - [ ] SubTask B6.2: 编写 `core/di_profile_test.v` 验证 profile 不匹配时不注册
- [ ] Task B7: ServiceLocator 按接口解析增强
  - [ ] SubTask B7.1: `service_locator.v` `locate_service[T]()` 当 `T` 是接口时，调用 `resolve_all_by_interface` 并返回 `@[primary]` 或唯一实现
  - [ ] SubTask B7.2: 编写 `core/di_service_locator_interface_test.v` 验证

## Phase C — Example 多包控制器重构与测试

- [ ] Task C1: 创建 `example/controllers/` 子包
  - [ ] SubTask C1.1: 新建 `example/controllers/user_controller.v`（`module controllers`），迁移 `UserController` 并标注 `@[controller] @[group('/api/v1/users')]`，字段 `@[autowired]`
  - [ ] SubTask C1.2: 新建 `example/controllers/auth_controller.v`，迁移 `AuthController`，标注 `@[controller] @[group('/api/v1/auth')]`
  - [ ] SubTask C1.3: 新建 `example/controllers/home_controller.v`，迁移 `HomeController`，标注 `@[controller]`
  - [ ] SubTask C1.4: 新建 `example/controllers/mod.v` 作为模块入口（如 V 需要）
- [ ] Task C2: 重构 `example/main.v` 与删除瘦委托
  - [ ] SubTask C2.1: `App` 结构体嵌入 `web.WebModule`，删除控制器指针字段
  - [ ] SubTask C2.2: `Context` 结构体新增 `app &App` 反向引用
  - [ ] SubTask C2.3: 实现 `Context.before_request()` 调用 `app.WebModule.handle_request(mut ctx)`
  - [ ] SubTask C2.4: `main()` 中调用 `web.mount[controllers.HomeController](mut app, mut ctx)`、`web.mount[controllers.AuthController](...)`、`web.mount[controllers.UserController](...)`
  - [ ] SubTask C2.5: 删除 `example/routes.v` 中瘦委托方法（保留 `/__docs` 等 veb 原生路由）
- [ ] Task C3: 编写控制器单元测试
  - [ ] SubTask C3.1: 新建 `example/controllers/controllers_test.v`，验证 `mount[UserController]` 后 `route_count()` 正确
  - [ ] SubTask C3.2: 验证 `scan_controller[UserController]` 返回的路径、HTTP 方法、handler_name 正确
  - [ ] SubTask C3.3: 验证 `@[group]` 前缀正确合并
- [ ] Task C4: 编写 DI 单元测试
  - [ ] SubTask C4.1: 新建 `example/di_test.v`，验证构造器注入（`UserService` 通过构造器注入 `UserRepository`）
  - [ ] SubTask C4.2: 验证按类型字段注入（`OrderService.repo` 注入 `OrderRepository`）
  - [ ] SubTask C4.3: 验证 `@[order]` 排序（多个 `HealthIndicator` 按 order 返回）
  - [ ] SubTask C4.4: 验证 `@[profile]` 过滤（`prod` only bean 在 `dev` profile 下不注册）
  - [ ] SubTask C4.5: 验证 Request 作用域（同一请求内单例，跨请求隔离）
  - [ ] SubTask C4.6: 验证 ServiceLocator 按接口解析
- [ ] Task C5: 编写集成测试（真实 HTTP 请求）
  - [ ] SubTask C5.1: 新建 `example/integration_test.v`，在 `testsuite` 中启动 HTTP 服务器（`veb.run_at` 在协程，主线程等待端口就绪）
  - [ ] SubTask C5.2: 测试 `GET /` 返回 200 + 首页内容
  - [ ] SubTask C5.3: 测试 `GET /health` 返回 200 + `{"status":"UP"}`
  - [ ] SubTask C5.4: 测试 `GET /api/v1/users` 返回 200 + 用户列表 JSON
  - [ ] SubTask C5.5: 测试 `POST /api/v1/users` 创建用户返回 201 + `id`
  - [ ] SubTask C5.6: 测试 `GET /api/v1/users/:id` 路径参数返回对应用户
  - [ ] SubTask C5.7: 测试 `POST /api/v1/auth/login` 登录返回 token
  - [ ] SubTask C5.8: 测试 `PUT /api/v1/users/:id` 更新用户
  - [ ] SubTask C5.9: 测试 `DELETE /api/v1/users/:id` 删除用户
  - [ ] SubTask C5.10: 测试未挂载路径回退 veb 原生路由（`/__docs`）
- [ ] Task C6: 扩展 `example/verify/` 验证套件
  - [ ] SubTask C6.1: 新增 `verify_controller_mount.v`——验证 `mount[T]` 扫描路由数、路径、方法
  - [ ] SubTask C6.2: 新增 `verify_di_type_injection.v`——验证按类型字段注入
  - [ ] SubTask C6.3: 新增 `verify_request_scope.v`——验证 Request 作用域
  - [ ] SubTask C6.4: 在 `verify/main.v` 注册新验证函数
- [ ] Task C7: 编译与运行验证
  - [ ] SubTask C7.1: `v -enable-globals build example/` 编译成功
  - [ ] SubTask C7.2: `v -enable-globals run example/verify` 退出码 0
  - [ ] SubTask C7.3: `v -enable-globals test example/` 所有测试通过
  - [ ] SubTask C7.4: `v -enable-globals test core/` 所有现有测试仍通过（无回归）
  - [ ] SubTask C7.5: `v -enable-globals test web/` 所有现有测试仍通过（无回归）

# Task Dependencies

- Task A1（mount[T] 核心）是 A2/A3/A4/A5 的前置
- Task B1（字段类型解析）是 B2（构造器注入）的前置——构造器参数也需按类型解析
- Task B4（Request 作用域）依赖 B1 完成（避免回归）
- Task C1（控制器子包）依赖 A1 完成（需 mount[T] 可用）
- Task C2（main 重构）依赖 C1 与 A3（WebModule 激活）
- Task C5（集成测试）依赖 C2 完成（需可运行服务器）
- Task C7（编译运行验证）依赖所有前置任务完成

# Parallelizable Work

- Phase A（A1→A2/A3/A4/A5）与 Phase B（B1→B2/B5/B6，B4 独立，B7 独立）可并行推进
- Task C3/C4 单元测试可与 C5 集成测试并行编写（但 C5 运行依赖 C2）
