# 大师级深度质量优化 Spec（Phase 3）

## Why

经过 Phase 1（Spring 对齐）与 Phase 2（质量与性能）两轮优化后，Photon 框架已具备基础能力且 67/67 测试通过。但三轮深度审查（内存泄漏与生命周期 / Spring 对齐 / 并发正确性）共发现 **71 个问题**：

- **内存泄漏与生命周期**：28 个（5 CRITICAL / 14 HIGH / 9 MEDIUM）
- **Spring 逻辑对齐**：12 个 P0 缺口
- **并发正确性**：31 个（7 CRITICAL / 8 HIGH / 12 MEDIUM / 4 LOW）

其中包含 12 个 CRITICAL 级别问题：调度器协程永不停止、Ticker.stop() 失效、Pool.close() 不释放对象、OrmManager 不关闭连接、Container 双锁同图竞态、TransactionManager.requires_new 破坏并发状态、MemoryCache 读锁下写 map、TaggedCache 无锁保护等。这些问题会直接导致生产环境内存泄漏、数据竞争、死锁与崩溃，必须以大师级标准彻底修复。

## What Changes

### P0 — 正确性与安全（CRITICAL/HIGH 修复）
- **ticker 模块**：修复 `scheduler_run()` 协程永不退出（CRITICAL #1）、`Ticker.stop()` 传入 `when=0` 永不匹配（CRITICAL #2）；引入 `stop_signal` + `WaitGroup` 生命周期管理
- **pool 模块**：`close()` 必须调用 `PooledObject.close()`（CRITICAL #3）；`acquire()` 增加 `is_valid()` 校验（HIGH #13）；实现 `idle_timeout` / `max_lifetime` 清理（HIGH #14）；`stats()` 加锁（M4）
- **orm 模块**：`remove_connection()` 关闭 DB 连接（CRITICAL #4）；新增 `close_all()`；`requires_new` 传播改为上下文栈而非全局 flag（CRITICAL #3 并发）；`is_active()` 改用读锁（M2）
- **core 模块**：消除 `sharded_mu` 与 `mu` 双锁同图竞态（CRITICAL #1 并发）；修复 `resolve_all_by_type()` 锁失衡（CRITICAL #2 并发）；指针字段（event_bus/parent/factory_registry）加锁保护（H8）；`destroy_all()` 调用 `@pre_destroy` + `DisposableBean.destroy()`（CRITICAL #5）
- **cache 模块**：`MemoryCache.get()` 读锁下禁止写 map（CRITICAL #4 并发）；修复过期删除 TOCTOU（C5）；`tag_to_keys` 加锁（C6）；`CacheRegistry` 增加 `unregister()`（M22）
- **locking 模块**：`unlock_and_cleanup()` 修复竞态（HIGH #17）；`LockManager` 自动清理空闲锁
- **queue 模块**：`Worker.running` 加锁（H3）；`registry`/`failed_jobs` map 加锁（C7）；`memory_driver.count()` 加锁（M6）；retry sleep 可中断（M25）
- **web 模块**：`frozen` 标志内存可见性（H1）；`MemorySessionStore` 自动 GC（HIGH #10）；`ratelimit` 窗口/尝试次数有界（HIGH #15/#16）；`upload` 过期清理（HIGH #9）
- **storage 模块**：`permissions` map 有界（HIGH #19）
- **event 模块**：`dispatch_async()` 协程追踪（HIGH #7）；监听器可注销（HIGH #8）
- **schedule 模块**：`is_running`/`task_count`/`enabled_count` 加锁（H2/M8）
- **dispatcher 模块**：双重检查锁定加内存屏障（H5）；`DeferredProvider.get()` 修复（H4）
- **db_pool**：`db_pool_id_counter` 原子化（M3）
- **lifecycle**：`SmartLifecycleManager` 加锁（M9）；`stop_all()` 超时（M26）

### P1 — Spring 逻辑对齐（12 个 P0 缺口）
- **生命周期顺序修正**：`before → @post_construct → afterPropertiesSet → after`（P0 1.2）
- **InitializingBean.afterPropertiesSet()** 在 refresh 中调用（P0 1.3）
- **DisposableBean.destroy()** 在 destroy 中调用（P0 1.4）
- **@ConfigurationProperties** 类型安全绑定（P0 3.1）
- **@Conditional** 真实条件判断（P0 4.3）
- **@Transactional** 自动织入事务代理（P0 5.1）
- **@Cacheable** 自动织入缓存代理（P0 5.4）
- **BeanPostProcessor** 真实 AOP 代理生成（P0 1.6/5.1/5.4）
- **@ControllerAdvice** 全局异常处理（P0 6.1）
- **JpaRepository 零回调**（P0 8.3）
- **MockMvc** 测试工具（P0 9.1）
- **example/ 迁移到 DI 容器**（P0 7.1）

### P2 — 大师级质量与心智成本
- **资源池生命周期完整化**：factory → validate → acquire → use → release → idle_timeout → max_lifetime → close 全链路
- **统一关闭顺序**：web → queue → ticker → schedule → cache → orm → pool → core
- **sharded_lock** 改用位运算 `& (shard_count-1)`（L4）
- **off_listener** 支持闭包注销（M23）
- **shutdown** 清理引用切片（M28）
- **refresh** 失败回滚（HIGH #18）
- **unfreeze/off** 监听器方法（M21）

## Impact

- **Affected specs**: deep-optimization-spring-alignment, optimize-quality-and-performance
- **Affected code**:
  - `ticker/bucket.v`, `ticker/schedule.v` — 协程生命周期
  - `pool/pool.v`, `pool/db_pool.v` — 池对象生命周期
  - `orm/orm.v`, `orm/transaction.v`, `orm/repository.v` — 连接与事务
  - `core/core.v`, `core/application_context.v`, `core/lifecycle.v`, `core/event.v`, `core/di_enhanced.v`, `core/condition.v`, `core/environment.v`, `core/post_processor.v`, `core/auto_configuration.v` — 容器核心
  - `cache/memory.v`, `cache/cache.v`, `cache/cache_tags.v`, `cache/singleflight.v` — 缓存
  - `locking/lock.v` — 锁
  - `queue/dispatcher.v`, `queue/worker.v`, `queue/failed_jobs.v`, `queue/memory_driver.v` — 队列
  - `web/kernel.v`, `web/session.v`, `web/ratelimit.v`, `web/upload.v`, `web/exception.v`, `web/testing.v`, `web/middleware.v` — Web
  - `storage/local_adapter.v` — 存储
  - `example/*.v` — 示例迁移

## ADDED Requirements

### Requirement: 资源生命周期全链路管理
框架 SHALL 对所有后台协程、连接池、缓存条目、会话、上传文件、限流窗口提供完整的生命周期管理，包括创建、验证、使用、释放、空闲超时、最大存活、关闭七个阶段，确保无内存泄漏、无协程泄漏、无连接泄漏。

#### Scenario: 调度器协程随容器关闭而退出
- **WHEN** 容器调用 `shutdown()`
- **THEN** `scheduler_run()` 协程在 100ms 内退出，`WaitGroup` 等待完成

#### Scenario: 池对象关闭时释放底层资源
- **WHEN** `Pool.close()` 被调用
- **THEN** 所有空闲池对象的 `PooledObject.close()` 被调用，底层连接/句柄释放

#### Scenario: 过期缓存条目自动清理
- **WHEN** 缓存条目超过 TTL
- **THEN** 后台 GC 协程定期清理，`tag_to_keys` 反向索引同步更新

### Requirement: 并发正确性保证
框架 SHALL 保证所有共享状态在并发访问下正确同步，禁止在读锁下写共享数据，禁止双锁同图，禁止 TOCTOU 竞态，所有 bool 标志在弱内存架构下通过锁或原子操作保证可见性。

#### Scenario: 读锁下不写 map
- **WHEN** `MemoryCache.get()` 在读锁下访问 entries
- **THEN** 仅读取，hit_count 更新通过单独的原子计数器或写锁

#### Scenario: 事务传播不破坏并发
- **WHEN** 多个协程同时使用 `requires_new` 传播
- **THEN** 每个协程拥有独立的事务上下文栈，互不干扰

### Requirement: Spring 生命周期完整对齐
框架 SHALL 完整实现 Spring Bean 生命周期：实例化 → 属性填充 → Aware → BeanPostProcessor.before → @PostConstruct → InitializingBean.afterPropertiesSet → initMethod → BeanPostProcessor.after → 就绪 → @PreDestroy → DisposableBean.destroy → destroyMethod。

#### Scenario: afterPropertiesSet 在 @PostConstruct 之后调用
- **WHEN** Bean 同时标注 `@[post_construct]` 并实现 `InitializingBean`
- **THEN** 先执行 `@PostConstruct` 方法，再执行 `afterPropertiesSet()`

### Requirement: 注解驱动 AOP 自动织入
框架 SHALL 在编译期通过 comptime 扫描 `@[transactional]` / `@[cacheable]` 注解，自动生成代理包装，开发者无需手动调用事务/缓存 API。

#### Scenario: @Transactional 自动开启事务
- **WHEN** 方法标注 `@[transactional]`
- **THEN** 方法执行前自动 `begin()`，正常返回 `commit()`，抛异常 `rollback()`

### Requirement: 类型安全配置绑定
框架 SHALL 通过 `@[configuration_properties]` 注解将配置前缀自动绑定到结构体字段，支持嵌套、数组、基本类型，无需手动 `bind_to`。

#### Scenario: 配置绑定到结构体
- **WHEN** 结构体标注 `@[configuration_properties('app.datasource')]`
- **THEN** `app.datasource.url`、`app.datasource.pool_size` 等自动绑定到对应字段

### Requirement: 零回调仓库
框架 SHALL 提供 `JpaRepository[T]` 基类，开发者继承即可获得 CRUD 能力，无需提供任何回调函数。

#### Scenario: 零配置仓库
- **WHEN** 开发者定义 `struct UserRepo { JpaRepository[User] }`
- **THEN** 自动获得 `find_by_id` / `save` / `delete` / `find_all` 方法

## MODIFIED Requirements

### Requirement: 容器关闭顺序
容器 `shutdown()` SHALL 按以下顺序关闭资源：web → queue → ticker → schedule → event → cache → orm → pool → core，每阶段超时 5s，全部完成后返回。

### Requirement: 双重检查锁定
所有双重检查锁定 SHALL 在 bool 标志读取时使用锁或 `sync.atomic` 保证内存可见性，禁止裸读 bool 标志。

## REMOVED Requirements

### Requirement: 手动 bind_to 配置绑定
**Reason**: 被 `@[configuration_properties]` 类型安全绑定取代
**Migration**: 旧 `bind_to` 保留但标记 `@[deprecated]`，新代码使用注解绑定
