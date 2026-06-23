# Checklist

## Phase A — Web 模块任意包控制器拆分

- [ ] `web/router.v` 存在 `MountOptions` 结构体与 `mount[T](mut rr, mut ctx, opts)` comptime 函数
- [ ] `mount[T]` 通过 `$for method in T.methods` 扫描 `@[get]`/`@[post]`/`@[put]`/`@[delete]`/`@[patch]` 与 `@['/path']` 属性
- [ ] `mount[T]` 通过 `$for attr in T.attributes` 扫描 `@[group('/prefix')]` 类级注解并合并前缀
- [ ] `mount[T]` 为每个路由方法生成包装闭包，闭包内 `mut ctrl := T{}` 创建新实例
- [ ] 包装闭包通过 comptime 填充控制器的 `veb.Context` 嵌入字段
- [ ] 包装闭包通过 comptime 对 `@[autowired]` 字段从 `ApplicationContext` 按类型解析注入
- [ ] `mount[T]` 将路由注册到 `RouteRegistry`（`rr.register(method, path, handler)`）
- [ ] `web/dispatcher.v` `RouteSegment` 含 `is_wildcard bool` 字段
- [ ] `parse_path` 识别 `*name` 段为通配符段
- [ ] `match_route` 支持通配符段匹配剩余所有路径并捕获为参数
- [ ] `WebModule` 含 `mount[T](mut ctx, opts)` 方法委托到 `router.mount[T]`
- [ ] `handle_request` 匹配成功返回 true，未匹配返回 false（向后兼容）
- [ ] `mount[T]` 扫描方法 `@[middleware('name')]` 属性并写入 `RouteDef.middlewares`
- [ ] `dispatch` 执行路由前按序调用命名中间件
- [ ] 包装闭包支持控制器方法返回 `veb.Result`
- [ ] 包装闭包支持控制器方法返回 `!`（错误传播为 500）
- [ ] 包装闭包支持控制器方法返回 `!veb.Result`

## Phase B — Core DI 深度对齐 Spring

- [ ] `scanner.v` `scan_and_register[T]` 中 `Dependency.type_name` 通过 comptime 按字段类型名填充（非 `field.name`）
- [ ] `@[qualifier('name')]` 按名解析旁路保留（`Dependency.qualifier` 非空时优先）
- [ ] `autowire_bean[T]` 按新 `type_name` 解析字段依赖
- [ ] `core/di_type_injection_test.v` 验证按类型注入（字段名与类型名不同时仍解析成功）
- [ ] `core/di_type_injection_test.v` 验证接口类型字段注入
- [ ] `scanner.v` 含 `extract_constructor[T]` 扫描 `@[autowired] init` 方法
- [ ] `BeanDefinition` 含 `constructor_params []Dependency` 字段
- [ ] `create_and_wire[T]` 有构造器时调用 `T.init(dep1, dep2)`，无构造器时保持 `T{}` + 字段注入
- [ ] `core/di_constructor_injection_test.v` 验证单参数构造器注入
- [ ] `core/di_constructor_injection_test.v` 验证多参数构造器注入
- [ ] `AutowiredAnnotationPostProcessor.post_process_after_initialization` 非空操作，执行字段注入
- [ ] `core/core.v` 含 `RequestScopeManager` 结构体
- [ ] `RequestScopeManager.begin_request()` / `end_request()` 管理请求作用域
- [ ] `resolve_unlocked` 对 `.request` 作用域 bean 从 `RequestScopeManager` 解析
- [ ] `web` 模块 `before_request` 调用 `begin_request`，`after_request` 调用 `end_request`
- [ ] `core/di_request_scope_test.v` 验证请求内单例
- [ ] `core/di_request_scope_test.v` 验证跨请求隔离
- [ ] `scanner.v` 含 `attr_order` 常量与 `extract_order[T]()` 函数
- [ ] `scan_and_register` 填充 `BeanDefinition.order_`
- [ ] `resolve_all_by_interface` / `resolve_all_by_tag` 按 `order_` 升序排序
- [ ] `core/di_order_test.v` 验证三个 `@[order(n)]` bean 按 1/2/3 顺序返回
- [ ] `scanner.v` 含 `attr_profile` 常量，`scan_and_register` 扫描后转换为 `conditional_on_profile` 条件
- [ ] `core/di_profile_test.v` 验证 `@[profile('prod')]` bean 在 `dev` profile 下不注册
- [ ] `service_locator.v` `locate_service[T]()` 当 T 是接口时按 `resolve_all_by_interface` + `@[primary]` 解析
- [ ] `core/di_service_locator_interface_test.v` 验证接口多实现按 primary 解析

## Phase C — Example 多包控制器重构与测试

- [ ] `example/controllers/` 目录存在，含 `user_controller.v`、`auth_controller.v`、`home_controller.v`
- [ ] 控制器文件首行为 `module controllers`
- [ ] 每个控制器标注 `@[controller]` 与 `@[group('/prefix')]`（home 无 group）
- [ ] 控制器字段标注 `@[autowired]`，无手动构造函数注入
- [ ] `example/main.v` `App` 嵌入 `web.WebModule`
- [ ] `example/main.v` `Context` 含 `app &App` 反向引用
- [ ] `example/main.v` 实现 `Context.before_request()` 调用 `app.WebModule.handle_request(mut ctx)`
- [ ] `example/main.v` 调用 `web.mount[controllers.HomeController/AuthController/UserController](mut app, mut ctx)`
- [ ] `example/routes.v` 瘦委托方法已删除（仅保留 `/__docs` 等 veb 原生路由，或整个文件删除）
- [ ] `example/controllers/controllers_test.v` 验证 `mount[UserController]` 后 `route_count()` 正确
- [ ] `example/controllers/controllers_test.v` 验证 `scan_controller[UserController]` 路径/方法/handler_name 正确
- [ ] `example/controllers/controllers_test.v` 验证 `@[group]` 前缀合并正确
- [ ] `example/di_test.v` 验证构造器注入
- [ ] `example/di_test.v` 验证按类型字段注入
- [ ] `example/di_test.v` 验证 `@[order]` 排序
- [ ] `example/di_test.v` 验证 `@[profile]` 过滤
- [ ] `example/di_test.v` 验证 Request 作用域
- [ ] `example/di_test.v` 验证 ServiceLocator 按接口解析
- [ ] `example/integration_test.v` 启动真实 HTTP 服务器
- [ ] `example/integration_test.v` 测试 `GET /` 返回 200
- [ ] `example/integration_test.v` 测试 `GET /health` 返回 200 + `status:UP`
- [ ] `example/integration_test.v` 测试 `GET /api/v1/users` 返回 200 + 用户列表
- [ ] `example/integration_test.v` 测试 `POST /api/v1/users` 返回 201 + `id`
- [ ] `example/integration_test.v` 测试 `GET /api/v1/users/:id` 路径参数返回对应用户
- [ ] `example/integration_test.v` 测试 `POST /api/v1/auth/login` 返回 token
- [ ] `example/integration_test.v` 测试 `PUT /api/v1/users/:id` 更新成功
- [ ] `example/integration_test.v` 测试 `DELETE /api/v1/users/:id` 删除成功
- [ ] `example/integration_test.v` 测试未挂载路径回退 veb 原生路由
- [ ] `example/verify/verify_controller_mount.v` 存在并验证 mount 行为
- [ ] `example/verify/verify_di_type_injection.v` 存在并验证类型注入
- [ ] `example/verify/verify_request_scope.v` 存在并验证 Request 作用域
- [ ] `example/verify/main.v` 注册了三个新验证函数

## 编译与运行验证（必须全部通过，不能仅语法检查）

- [ ] `v -enable-globals build example/` 编译成功（退出码 0）
- [ ] `v -enable-globals run example/verify` 退出码 0，所有断言通过
- [ ] `v -enable-globals test example/` 所有测试通过（退出码 0）
- [ ] `v -enable-globals test core/` 所有现有测试仍通过（无回归）
- [ ] `v -enable-globals test web/` 所有现有测试仍通过（无回归）
- [ ] 集成测试中真实 HTTP 请求返回正确的状态码与业务数据（非 mock）
- [ ] 控制器在独立包 `module controllers` 中定义，`example/main` 跨包导入并挂载成功
