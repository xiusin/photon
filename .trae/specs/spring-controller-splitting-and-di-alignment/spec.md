# Spring 级控制器任意包拆分与 DI 深度对齐 Spec

## Why

Photon 框架当前 Web 模块存在一个**核心架构缺陷**：所有路由声明方法（`@[get]`/`@[post]`/`@['/path']`）必须挂在传递给 `veb.run_at[A, X]` 的**单一 `App` 结构体**上。这是 V 标准库 `veb` 的固有限制——veb 的 comptime 路由扫描只检查一个类型 `A`。当前 `example/routes.v` 与 `demo/controllers.v` 采用"瘦委托"模式：在 `App` 上为每个路由写一行转发方法，再委托给独立控制器。这导致：

1. **控制器无法真正解耦**：每新增一个端点都要修改 `App` 所在模块的 `routes.v`/`controllers.v`，违反开闭原则。
2. **无法在任意包组织控制器**：Spring 允许 `@RestController` 散落在任意包，由 `@ComponentScan` 自动发现；Photon 则强制所有路由方法集中在 `App` 类型上。
3. **`WebModule` + `RouteRegistry` + `Controller` 接口是空壳**：`web/web.v`、`web/router.v`、`web/dispatcher.v` 定义了一套并行路由系统，但**没有任何应用使用它**，`mount_controller` 只是 `Controller.register_routes()` 的别名，无 comptime 扫描。

同时，Core 模块的 DI 虽已对标 Spring 60%，但仍有**关键缺口**：字段注入按字段名而非类型解析（`scanner.v:786` 把 `field.name` 当作 `type_name`）、无构造器注入、`BeanPostProcessor` 多为空壳标记、Request 作用域未在 core 实现、无 `@[order]` 注解。这些缺口使 DI 体验与 Spring 仍有差距。

本次变更借鉴 [xiusin/very](https://github.com/xiusin/very) 框架的 `mount[T]()` comptime 机制（**不照搬代码**，仅取设计灵感），在 Photon 中实现**真正的任意包控制器拆分**，并补齐 Core DI 的 Spring 级能力，最后通过 `example/` 完整测试套件（含真实 HTTP 请求验证）确保编译与运行正常。

## What Changes

### A. Web 模块——任意包控制器拆分（核心）

- **A1**：实现 `web.mount[T](mut app, mut ctx, opts MountOptions)` comptime 函数，扫描控制器类型 `T` 的方法注解（`@[get]`/`@[post]`/`@[put]`/`@[delete]`/`@[patch]`/`@['/path']`），为每个路由方法生成包装闭包，注册到 `RouteRegistry`。
- **A2**：包装闭包在每次请求时**新建控制器实例**（prototype 语义），通过 comptime 注入 `veb.Context`（嵌入字段）与 `@[autowired]` 服务字段（从 `ApplicationContext` 解析）。
- **A3**：支持 `@[controller]` 类级注解 + `@[group('/api/v1')]` 路由前缀注解（comptime 扫描 `T.attributes`）。
- **A4**：激活 `WebModule` 嵌入模式——`App` 嵌入 `web.WebModule`，覆写 `Context.before_request()` 调用 `wm.handle_request(mut ctx)` 分发到挂载的控制器；未匹配时回退到 veb 原生路由（向后兼容）。
- **A5**：支持路径参数 `:id`、`*filepath` 通配符，复用现有 `dispatcher.v` 的 `find_route`/`match_route` 引擎并扩展通配符匹配。
- **A6**：支持控制器方法返回 `veb.Result` 或 `!`（错误传播），包装闭包统一处理。
- **A7**：支持中间件注解 `@[middleware('auth', 'cors')]` 在控制器方法/类级别声明，挂载时织入路由。

### B. Core 模块——DI 深度对齐 Spring

- **B1**：**修复字段注入按类型解析**——`scan_and_register[T]()` 中 `Dependency.type_name` 改为通过 comptime `$if field.typ is X` 分支获取字段类型名（`T.name`），而非字段名；保留 `@[qualifier]` 按名解析能力。
- **B2**：**实现构造器注入**——新增 `@[autowired]` 标注的 `init(opts ...)` 风格构造方法扫描，comptime 生成 `new[T](mut ctx) !&T` 工厂闭包，从容器解析构造参数。
- **B3**：**激活 `BeanPostProcessor`**——`AutowiredAnnotationPostProcessor.post_process_after_initialization` 真正执行字段注入（comptime 生成的注入闭包），而非空壳。
- **B4**：**实现 Request 作用域**——`core` 新增 `RequestScope` 接口与 `RequestScopeManager`，Web 模块在请求开始时创建子作用域，结束时清理；`Scope.request` 的 bean 在请求内单例。
- **B5**：**新增 `@[order(n)]` 注解**——comptime 扫描填充 `BeanDefinition.order_`，`resolve_all_by_interface`/`resolve_all_by_tag` 按 order 排序返回。
- **B6**：**新增 `@[profile('dev'|'prod')]` 注解**——作为 `@[conditional_on_profile]` 的语法糖，comptime 扫描时转换为条件。
- **B7**：**ServiceLocator 增强**——`locate_service[T]()` 支持按接口类型解析（扫描所有实现该接口的 bean，`@[primary]` 优先），而非仅按类型名字符串。

### C. Example 测试套件（必须通过编译与运行）

- **C1**：重构 `example/` 为多包控制器结构——将 `HomeController`/`AuthController`/`UserController` 迁移到独立子包 `example/controllers/`，每个控制器用 `@[controller]` + `@[group]` + `@[autowired]` 声明，通过 `web.mount[T]()` 挂载。
- **C2**：删除 `example/routes.v` 的瘦委托方法，改为 `App` 嵌入 `WebModule` + `before_request` 分发。
- **C3**：编写 `example/controllers/controllers_test.v` 单元测试——验证 `mount[T]()` 扫描出正确路由数、路径、HTTP 方法。
- **C4**：编写 `example/integration_test.v` 集成测试——启动真实 HTTP 服务器（`veb.run_at` 在协程中运行），用 `net.http` 客户端发起 GET/POST/PUT/DELETE 请求，断言响应状态码与业务数据（JSON 字段值）。
- **C5**：编写 `example/di_test.v` DI 测试——验证构造器注入、按类型字段注入、`@[order]`、`@[profile]`、Request 作用域、ServiceLocator 按接口解析。
- **C6**：扩展 `example/verify/` 验证套件——新增 `verify_controller_mount`、`verify_di_type_injection`、`verify_request_scope` 验证项。
- **C7**：确保 `v -enable-globals run example/` 与 `v -enable-globals run example/verify` 退出码为 0，所有断言通过。

## Impact

- **Affected specs**：
  - `deep-optimization-spring-alignment`（Phase 1，本变更在其 DI 基础上补齐类型注入与构造器注入）
  - `complete-spring-enterprise-framework`（Phase 4，本变激活其空壳的 `WebModule`/`Controller` 抽象）
  - `create-demo-project` / `upgrade-demo-to-skeleton-grade`（Demo 暂不强制迁移，保留瘦委托模式向后兼容）
- **Affected code**：
  - `web/web.v`（激活 `WebModule`，新增 `mount[T]` 集成）
  - `web/router.v`（新增 `mount[T]` comptime 扫描 + 包装闭包生成）
  - `web/dispatcher.v`（扩展通配符 `*filepath` 匹配）
  - `web/middleware.v`（支持控制器方法级中间件织入）
  - `core/scanner.v`（修复字段类型解析 B1，新增 `@[order]`/`@[profile]` 扫描 B5/B6）
  - `core/core.v`（Request 作用域 B4，`resolve_all` 排序 B5）
  - `core/post_processor.v`（激活 `AutowiredAnnotationPostProcessor` B3）
  - `core/application_context.v`（构造器注入工厂 B2，ServiceLocator 接口解析 B7）
  - `core/service_locator.v`（按接口解析 B7）
  - `example/` 全量重构为多包控制器 + 完整测试套件
- **BREAKING**：
  - `scan_and_register[T]()` 中 `Dependency.type_name` 语义从"字段名"改为"字段类型名"——依赖按类型名注册的旧代码需更新（影响范围小，当前仅 `example/bootstrap.v` 显式注册，未依赖字段名解析）。
  - `WebModule` 从"空壳可嵌入"变为"激活可用"——嵌入 `WebModule` 的 `App` 必须实现 `before_request` 分发，否则挂载的控制器路由不生效（向后兼容：不嵌入则不影响）。

## ADDED Requirements

### Requirement: 任意包控制器挂载（`web.mount[T]`）

系统 SHALL 提供 `web.mount[T](mut app &WebModule, mut ctx &core.ApplicationContext, opts MountOptions)` comptime 函数，扫描控制器类型 `T` 的所有方法，为标注 `@[get]`/`@[post]`/`@[put]`/`@[delete]`/`@[patch]`/`@['/path']` 的方法生成路由并注册到 `RouteRegistry`。

#### Scenario: 挂载单控制器
- **WHEN** 用户定义 `@[controller] @[group('/api/v1/users')] struct UserController { veb.Context; @[autowired] svc &UserService }` 并调用 `web.mount[UserController](mut app, mut ctx)`
- **THEN** `RouteRegistry` 中注册 `UserController` 所有标注方法的路由
- **AND** 路由路径前缀为 `/api/v1/users`
- **AND** 每个请求新建一个 `UserController` 实例，`veb.Context` 字段被填充为请求上下文
- **AND** `svc` 字段从 `ApplicationContext` 按类型解析注入

#### Scenario: 控制器在独立包
- **WHEN** `UserController` 定义在 `module controllers`（独立包），`example/main` 导入该包并调用 `web.mount[controllers.UserController](mut app, mut ctx)`
- **THEN** 路由正常注册，HTTP 请求正常分发，业务逻辑正常执行

#### Scenario: 路径参数匹配
- **WHEN** 控制器方法标注 `@['/:id'; get]`，请求 `GET /api/v1/users/42`
- **THEN** 包装闭包执行，控制器方法可通过 `ctx.params['id']` 获取 `'42'`

#### Scenario: 通配符匹配
- **WHEN** 控制器方法标注 `@['/files/*filepath'; get]`，请求 `GET /files/static/css/app.css`
- **THEN** `ctx.params['filepath']` 为 `'static/css/app.css'`

### Requirement: 控制器类级与方法级注解

系统 SHALL 支持控制器结构体上的 `@[controller]` 标记注解与 `@[group('/prefix')]` 路由前缀注解，以及方法上的 HTTP 方法注解与路径注解。

#### Scenario: 类级前缀
- **WHEN** `@[group('/admin')] struct AdminController` 的方法 `@['/users'; get] fn list()`
- **THEN** 注册的路由路径为 `/admin/users`

#### Scenario: 无前缀
- **WHEN** 控制器无 `@[group]` 注解
- **THEN** 路由路径为方法注解中的原始路径

### Requirement: 控制器 DI 注入

系统 SHALL 在每次请求创建控制器实例时，通过 comptime 扫描控制器字段，对标注 `@[autowired]` 的字段从 `ApplicationContext` 按类型解析并注入。

#### Scenario: 按类型注入服务
- **WHEN** 控制器字段 `@[autowired] user_service &UserService`，容器中注册了 `UserService` 单例
- **THEN** 每次请求创建的控制器实例中 `user_service` 指向该单例

#### Scenario: 按 qualifier 注入
- **WHEN** 控制器字段 `@[autowired] @[qualifier('primary')] cache &Cache`，容器中有多个 `Cache` bean
- **THEN** 注入标记为 `@[primary]` 的那个

#### Scenario: 注入失败报错
- **WHEN** 控制器字段 `@[autowired] missing &MissingService`，容器中无此类型
- **THEN** 请求返回 500，错误信息包含 `cannot autowire field 'missing' of type 'MissingService': no bean registered`

### Requirement: WebModule 嵌入分发

系统 SHALL 提供 `WebModule` 可嵌入结构体，`App` 嵌入后通过覆写 `Context.before_request()` 调用 `wm.handle_request(mut ctx)` 分发到挂载的控制器；未匹配时回退到 veb 原生路由。

#### Scenario: 挂载控制器分发
- **WHEN** `App` 嵌入 `WebModule`，挂载了 `UserController`，请求 `GET /api/v1/users`
- **THEN** `before_request` 中 `wm.handle_request` 匹配并执行控制器方法，返回响应
- **AND** veb 原生路由不再处理该请求

#### Scenario: 未匹配回退
- **WHEN** 请求路径未挂载任何控制器路由，但 `App` 上有 veb 原生路由方法
- **THEN** `handle_request` 返回 `false`，veb 原生路由处理该请求

### Requirement: 控制器方法级中间件

系统 SHALL 支持控制器方法上标注 `@[middleware('auth', 'log')]`，挂载时将命名中间件织入对应路由的处理器链。

#### Scenario: 方法级中间件执行
- **WHEN** 控制器方法 `@['/profile'; get] @[middleware('auth')] fn profile()` 被请求
- **THEN** `auth` 中间件先执行，通过后才执行 `profile` 方法

### Requirement: 按类型字段注入（DI 修复）

系统 SHALL 在 `scan_and_register[T]()` 中通过 comptime 获取字段类型名作为 `Dependency.type_name`，使 `@[autowired]` 字段按类型解析而非按字段名解析。

#### Scenario: 按类型解析字段
- **WHEN** `@[component] struct OrderService { @[autowired] repo &OrderRepository }`，容器注册了 `OrderRepository`
- **THEN** `OrderService` 的 `repo` 字段被注入 `OrderRepository` 实例
- **AND** 即使字段名为 `repo`（与类型名 `OrderRepository` 不同），仍能正确解析

#### Scenario: 接口类型注入
- **WHEN** `@[autowired] cache ICache` 字段类型为接口，容器中有实现 `ICache` 的 bean
- **THEN** 注入该实现实例

### Requirement: 构造器注入

系统 SHALL 支持在 `@[component]` 结构体上标注 `@[autowired]` 的 `init` 方法作为构造器，comptime 生成工厂闭包从容器解析参数并构造实例。

#### Scenario: 单参数构造器
- **WHEN** `@[component] struct UserService { @[autowired] fn init(repo &UserRepository) { self.repo = repo } }`
- **THEN** 容器创建 `UserService` 时先解析 `UserRepository`，再调用 `init(repo)` 构造实例

#### Scenario: 多参数构造器
- **WHEN** `@[autowired] fn init(repo &UserRepository, cache &CacheService)` 有两个依赖
- **THEN** 两个依赖均从容器解析后传入构造

### Requirement: Request 作用域

系统 SHALL 实现 `Scope.request`——Web 请求开始时创建请求级子作用域，请求结束时清理；Request 作用域的 bean 在同一请求内单例，跨请求隔离。

#### Scenario: 请求内单例
- **WHEN** `@[scope('request')] struct RequestContext` 在同一请求中被两次解析
- **THEN** 返回同一实例

#### Scenario: 跨请求隔离
- **WHEN** 两个并发请求各自解析 `RequestContext`
- **THEN** 各自获得独立实例，互不干扰

### Requirement: `@[order(n)]` Bean 排序

系统 SHALL 支持 `@[order(1)]` 注解，comptime 扫描填充 `BeanDefinition.order_`，`resolve_all_by_interface`/`resolve_all_by_tag` 按 order 升序返回。

#### Scenario: 按 order 排序
- **WHEN** 三个 `HealthIndicator` 实现分别标注 `@[order(3)]`/`@[order(1)]`/`@[order(2)]`
- **THEN** `resolve_all_by_interface('HealthIndicator')` 返回顺序为 order=1, 2, 3

### Requirement: `@[profile('dev')]` 注解

系统 SHALL 支持 `@[profile('dev')]` 注解作为 `@[conditional_on_profile('dev')]` 的语法糖，comptime 扫描时转换为条件。

#### Scenario: profile 不匹配不注册
- **WHEN** `@[profile('prod')] struct ProdOnlyService`，当前激活 profile 为 `dev`
- **THEN** 该 bean 不被注册到容器

### Requirement: ServiceLocator 按接口解析

系统 SHALL 增强 `ServiceLocator.locate_service[T]()`，当 `T` 是接口时，扫描所有实现该接口的 bean，返回 `@[primary]` 标记的那个或唯一实现。

#### Scenario: 接口多实现按 primary 解析
- **WHEN** `ICache` 有两个实现 `MemoryCache`（`@[primary]`）与 `RedisCache`，调用 `locate_service[ICache]()`
- **THEN** 返回 `MemoryCache` 实例

### Requirement: Example 多包控制器结构

系统 SHALL 将 `example/` 重构为多包控制器结构，控制器位于独立子包，通过 `web.mount[T]()` 挂载，删除瘦委托路由方法。

#### Scenario: 控制器在独立包
- **WHEN** `example/controllers/user_controller.v` 属于 `module controllers`，定义 `@[controller] @[group('/api/v1/users')] struct UserController`
- **THEN** `example/main.v` 导入 `controllers` 包并调用 `web.mount[controllers.UserController](mut app, mut ctx)` 后，`/api/v1/users` 路由可用

### Requirement: Example 集成测试（真实 HTTP 请求）

系统 SHALL 在 `example/integration_test.v` 中启动真实 HTTP 服务器并发起 HTTP 请求验证业务数据。

#### Scenario: GET 请求验证
- **WHEN** 测试启动服务器后发起 `GET /api/v1/users`
- **THEN** 响应状态码 200，响应体 JSON 包含 `users` 数组

#### Scenario: POST 请求验证
- **WHEN** 测试发起 `POST /api/v1/users` 携带 JSON body `{"name":"Alice","email":"alice@example.com"}`
- **THEN** 响应状态码 201，响应体包含 `id` 字段

#### Scenario: 路径参数验证
- **WHEN** 测试发起 `GET /api/v1/users/42`
- **THEN** 响应体包含 `id: 42` 的用户数据

#### Scenario: DI 注入验证
- **WHEN** 测试发起 `GET /health`
- **THEN** 响应体包含 `status: UP`，证明 `HealthService` 已通过 DI 注入控制器

### Requirement: Example 单元测试套件

系统 SHALL 在 `example/controllers/controllers_test.v` 与 `example/di_test.v` 中提供单元测试，验证控制器挂载与 DI 行为。

#### Scenario: 挂载路由数验证
- **WHEN** 运行 `controllers_test.v` 中 `test_mount_user_controller_routes`
- **THEN** `mount[UserController]` 后 `RouteRegistry.route_count()` 等于 `UserController` 的标注方法数

#### Scenario: 构造器注入验证
- **WHEN** 运行 `di_test.v` 中 `test_constructor_injection`
- **THEN** 通过构造器注入的 `UserService` 其 `repo` 字段非 nil 且类型正确

## MODIFIED Requirements

### Requirement: `scan_and_register[T]()` 字段依赖解析
原实现将 `Dependency.type_name` 设为 `field.name`（字段名）。修改为：通过 comptime `$if field.typ is X` 分支获取字段类型名（如 `&UserService` → `UserService`），作为 `type_name`；保留 `@[qualifier]` 按名解析的旁路。

### Requirement: `WebModule`
原实现为空壳（`register`/`mount` 仅调用 `Controller.register_routes`，无 comptime 扫描）。修改为：新增 `mount[T](mut app, mut ctx, opts)` comptime 函数真正扫描注解并生成包装闭包；`handle_request` 在 `before_request` 中分发。

### Requirement: `AutowiredAnnotationPostProcessor`
原实现 `post_process_after_initialization` 为空操作。修改为：在 `refresh()` 阶段对每个 bean 执行 comptime 生成的字段注入闭包（按类型从容器解析）。

### Requirement: `Scope.request`
原实现 `resolve_unlocked()` 仅特殊处理 `.prototype`，`.request` 回退为单例。修改为：`.request` 作用域从 `RequestScopeManager` 当前请求作用域解析，无活动请求时回退为新建实例。

## REMOVED Requirements

### Requirement: 瘦委托路由模式（example/routes.v）
**Reason**: 每新增端点需修改 `App` 模块的 `routes.v`，违反开闭原则；控制器无法真正解耦。
**Migration**: 改用 `web.mount[T]()` 挂载独立包控制器，`App` 仅嵌入 `WebModule` + 实现 `before_request` 分发；`routes.v` 删除或仅保留 veb 原生路由（如 `/__docs`）。
