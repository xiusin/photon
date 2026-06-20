# Tasks

## Phase P0 — 正确性与安全（CRITICAL/HIGH 修复）

### 子阶段 P0-A：内存泄漏与协程生命周期（5 CRITICAL + 14 HIGH）

- [x] Task 1: 修复 ticker 模块协程生命周期（CRITICAL #1/#2）
  - [x] SubTask 1.1: `ticker/bucket.v` — `scheduler_run()` 增加 `stop_signal chan bool`，循环改为 `select { stop_signal <- true { break } else {} }`，退出时关闭调度协程
  - [x] SubTask 1.2: `ticker/bucket.v` — `Ticker.stop()` 传入正确的 `when = time.now().unix()`，匹配触发删除
  - [x] SubTask 1.3: `ticker/bucket.v` — `TimerScheduler` 增加 `wg sync.WaitGroup`，`start()` 时 `wg.add(1)`，协程退出 `wg.done()`，`stop()` 调用 `wg.wait()` 确保退出
  - [x] SubTask 1.4: `ticker/bucket.v` — `TimerScheduler.running` 改为 `sync.Mutex` 保护或原子 bool
  - [x] SubTask 1.5: 编写 `ticker_lifecycle_test.v` 验证 stop 后协程退出、无泄漏

- [x] Task 2: 修复 pool 模块对象生命周期（CRITICAL #3 + HIGH #13/#14 + M4）
  - [x] SubTask 2.1: `pool/pool.v` — `close()` 遍历 `idle` 切片，对每个 `PooledObject` 调用 `obj.close()`，清空 `idle` 与 `active_count`
  - [x] SubTask 2.2: `pool/pool.v` — `acquire()` 取出对象后调用 `factory.is_valid(obj)`，无效则 `obj.close()` 并重新创建
  - [x] SubTask 2.3: `pool/pool.v` — 启动后台 GC 协程，定期扫描 `idle`，删除超过 `idle_timeout_seconds` 的对象（调用 `obj.close()`）
  - [x] SubTask 2.4: `pool/pool.v` — `PooledObject` 增加 `created_at` 字段，GC 协程删除超过 `max_lifetime` 的对象
  - [x] SubTask 2.5: `pool/pool.v` — `stats()` 在 `mu.@lock()` 下读取并返回副本
  - [x] SubTask 2.6: `pool/pool.v` — `release()` 检查池是否已关闭，已关闭则直接 `obj.close()`
  - [x] SubTask 2.7: 编写 `pool_lifecycle_test.v` 验证 close 释放对象、idle_timeout 清理、is_valid 校验

- [x] Task 3: 修复 orm 连接与事务并发（CRITICAL #4 + CRITICAL #3 并发 + M2）
  - [x] SubTask 3.1: `orm/orm.v` — `remove_connection()` 在删除前调用 `db.close()` 或 `connection.close()`
  - [x] SubTask 3.2: `orm/orm.v` — 新增 `close_all()` 方法，遍历所有连接并关闭
  - [x] SubTask 3.3: `orm/orm.v` — 实现 `DisposableBean` 接口，`destroy()` 调用 `close_all()`
  - [x] SubTask 3.4: `orm/transaction.v` — `requires_new` 传播改为协程本地事务栈（`stack []Transaction`），不再修改全局 `tm.active`
  - [x] SubTask 3.5: `orm/transaction.v` — `is_active()` 改用 `mu.@rlock()` 读锁
  - [x] SubTask 3.6: `orm/transaction.v` — `begin/commit/rollback` 操作事务栈 push/pop
  - [x] SubTask 3.7: 编写 `transaction_concurrency_test.v` 验证多协程并发事务互不干扰

- [x] Task 4: 修复 core 容器双锁竞态与生命周期（CRITICAL #1/#2/#5 + H8）
  - [x] SubTask 4.1: `core/core.v` — 移除 `sharded_mu`，统一使用 `mu sync.RwMutex` 保护 `definitions/instances/aliases`，或让 `sharded_mu` 与 `mu` 保护不同的数据集（消除双锁同图）
  - [x] SubTask 4.2: `core/core.v` — 修复 `resolve_all_by_type()` 锁失衡：确保每个 `return` 前有 `unlock()`，或使用 `defer` 模式
  - [x] SubTask 4.3: `core/core.v` — `event_bus`/`parent`/`factory_registry` 指针字段读写加 `mu` 保护
  - [x] SubTask 4.4: `core/application_context.v` — `destroy_all()` 调用每个 bean 的 `@pre_destroy` 方法（通过 comptime 检测）
  - [x] SubTask 4.5: `core/application_context.v` — `destroy_all()` 调用实现 `DisposableBean` 的 bean 的 `destroy()`
  - [x] SubTask 4.6: `core/application_context.v` — `shutdown()` 清理引用切片（`instances = []`、`definitions = {}`）
  - [x] SubTask 4.7: 编写 `container_lifecycle_test.v` 验证 destroy 调用顺序、无残留引用

- [x] Task 5: 修复 cache 并发与生命周期（CRITICAL #4 并发 + C5/C6 + M22）
  - [x] SubTask 5.1: `cache/memory.v` — `get()` 读锁下禁止 `unsafe { entries[key].hit_count++ }`，改为读锁下读取 entry 副本，写锁下更新 hit_count，或使用原子计数器
  - [x] SubTask 5.2: `cache/memory.v` — 修复过期删除 TOCTOU：读锁发现过期 → 释放读锁 → 写锁重新检查是否仍存在且过期 → 删除
  - [x] SubTask 5.3: `cache/cache_tags.v` — `tag_to_keys` 反向索引所有读写加 `mu sync.RwMutex`
  - [x] SubTask 5.4: `cache/cache_tags.v` — `flush_tag()` 删除 key 时同步更新 `tag_to_keys`
  - [x] SubTask 5.5: `cache/cache_tags.v` — TTL 过期清理时同步更新 `tag_to_keys`（订阅 memory cache 的删除事件或定期扫描）
  - [x] SubTask 5.6: `cache/cache.v` — `CacheRegistry` 增加 `unregister(name)` 方法
  - [x] SubTask 5.7: `cache/memory.v` — 启动后台 GC 协程定期清理过期条目，stop_signal 控制
  - [x] SubTask 5.8: 编写 `cache_concurrency_test.v` 验证并发读写、tag flush 一致性

- [x] Task 6: 修复 locking/queue/web/storage 资源泄漏（HIGH #7/#8/#9/#10/#15/#16/#17/#19 + C7 + M6/M21/M23/M25）
  - [x] SubTask 6.1: `locking/lock.v` — `unlock_and_cleanup()` 修复竞态：先 unlock 再加写锁删除，或使用 try_lock 检查引用计数
  - [x] SubTask 6.2: `locking/lock.v` — `LockManager` 启动后台清理空闲锁协程
  - [x] SubTask 6.3: `queue/worker.v` — `running` 改为 `sync.Mutex` 保护或原子 bool
  - [x] SubTask 6.4: `queue/worker.v` — `registry` map 加 `sync.RwMutex`
  - [x] SubTask 6.5: `queue/failed_jobs.v` — `jobs` 切片加 `sync.Mutex`
  - [x] SubTask 6.6: `queue/memory_driver.v` — `count()` 加读锁
  - [x] SubTask 6.7: `queue/worker.v` — retry sleep 改为 `select { stop_ch <- true { return } else { time.sleep(retry_delay) } }` 可中断
  - [x] SubTask 6.8: `web/kernel.v` — `frozen` 标志读写加锁，或改为原子 bool
  - [x] SubTask 6.9: `web/kernel.v` — 增加 `unfreeze()` 和 `off(listener)` 方法
  - [x] SubTask 6.10: `web/session.v` — `MemorySessionStore` 启动后台 GC 协程定期清理过期会话
  - [x] SubTask 6.11: `web/ratelimit.v` — `attempts` 切片有界化（超过阈值清理最旧）
  - [x] SubTask 6.12: `web/ratelimit.v` — `FixedWindowLimiter.windows` 定期清理过期窗口
  - [x] SubTask 6.13: `web/upload.v` — 启动后台清理过期上传目录协程
  - [x] SubTask 6.14: `storage/local_adapter.v` — `permissions` map 有界化（LRU 淘汰）
  - [x] SubTask 6.15: `core/event.v` — `dispatch_async()` 使用 `WaitGroup` 追踪协程，`shutdown()` 等待完成
  - [x] SubTask 6.16: `core/event.v` — 增加 `off_listener(id)` 真正注销（返回 listener id 用于注销）
  - [x] SubTask 6.17: 编写 `resource_lifecycle_test.v` 验证各模块清理

### 子阶段 P0-B：并发正确性（7 CRITICAL + 8 HIGH 剩余）

- [x] Task 7: 修复 schedule/dispatcher/di_enhanced 并发（H1/H2/H4/H5 + M8）
  - [x] SubTask 7.1: `ticker/schedule.v` — `is_running` 加锁保护（已由 Task 1 修复：lines 298-300 使用 `sc.mu.rlock()`/`runlock()`）
  - [x] SubTask 7.2: `ticker/schedule.v` — `task_count()`/`enabled_count()` 加读锁（已由 Task 1 修复：lines 402-423 使用 `s.mu.rlock()`/`defer { runlock() }`）
  - [x] SubTask 7.3: `queue/dispatcher.v` — 双重检查锁定改为：写锁内创建 → 释放写锁 → 返回；或使用 `sync.Once` 模式（`dispatcher_mu` 改为 `sync.RwMutex`，快速路径用 rlock 保证内存可见性）
  - [x] SubTask 7.4: `core/di_enhanced.v` — `DeferredProvider.get()` 双重检查锁定修复：写锁内创建实例并赋值，确保内存可见（快速路径 rlock 读 resolved/instance，慢路径 @lock 双重检查）
  - [x] SubTask 7.5: `core/lifecycle.v` — `SmartLifecycleManager` 加 `sync.RwMutex` 保护 `smart_lifecycles`（`entries` 读写均加锁，回调在锁外执行避免死锁）
  - [x] SubTask 7.6: `core/lifecycle.v` — `stop_all()` 增加超时（5s），超时强制退出（goroutine + chan + 5s 轮询超时）
  - [x] SubTask 7.7: `pool/db_pool.v` — `db_pool_id_counter` 改为 `sync.Mutex` 保护或原子操作（新增 `db_pool_id_mu sync.Mutex`）
  - [x] SubTask 7.8: `core/sharded_lock.v` — shard 选择改用 `& (shard_count - 1)` 位运算（要求 shard_count 为 2 的幂，构造函数加 assert）
  - [x] SubTask 7.9: 编写 `concurrency_correctness_test.v` 验证双重检查锁定、schedule 计数（8 个测试函数覆盖 H5/H4/M9/M26/L4/M8）

- [x] Task 8: 修复 application_context 生命周期与回滚（HIGH #18 + M28 + 生命周期顺序）
  - [x] SubTask 8.1: `core/application_context.v` — `refresh()` 失败时回滚：记录已创建的 bean，失败时逆序调用 destroy
  - [x] SubTask 8.2: `core/application_context.v` — 修正生命周期顺序为：`before → @post_construct → afterPropertiesSet → after`
  - [x] SubTask 8.3: `core/application_context.v` — `refresh()` 中调用 `InitializingBean.afterPropertiesSet()`（comptime 检测）
  - [x] SubTask 8.4: `core/application_context.v` — `destroy_all()` 中调用 `DisposableBean.destroy()`（comptime 检测）
  - [x] SubTask 8.5: `core/application_context.v` — `shutdown()` 清理 `instances`/`definitions`/`aliases` 引用
  - [x] SubTask 8.6: 编写 `lifecycle_order_test.v` 验证调用顺序

## Phase P1 — Spring 逻辑对齐（12 个 P0 缺口）

- [x] Task 9: 实现 @ConfigurationProperties 类型安全绑定（P0 3.1）
  - [x] SubTask 9.1: `core/environment.v` — 新增 `bind_to_struct[T](prefix) !T` 泛型函数，comptime 遍历结构体字段，按 `prefix.field_name` 绑定
  - [x] SubTask 9.2: `core/environment.v` — 支持嵌套结构体（递归绑定）、数组、基本类型（string/int/f64/bool）
  - [x] SubTask 9.3: `core/environment.v` — 支持 `@[config_field('custom_key')]` 注解自定义配置键
  - [x] SubTask 9.4: `core/core.v` — 注册 `@[configuration_properties]` 标注的 bean 时自动调用 `bind_to_struct`
  - [x] SubTask 9.5: 旧 `bind_to` 标记 `@[deprecated]`
  - [x] SubTask 9.6: 编写 `config_binding_test.v` 验证嵌套、数组、默认值

- [x] Task 10: 实现 @Conditional 真实条件判断（P0 4.3）
  - [x] SubTask 10.1: `core/condition.v` — `OnClassCondition` 实现真实类存在检查（comptime $exists 或运行时注册表）
  - [x] SubTask 10.2: `core/condition.v` — 新增 `OnBeanCondition`（检查 bean 是否存在）、`OnPropertyCondition`（检查配置值）
  - [x] SubTask 10.3: `core/core.v` — `register_definition()` 时评估 `@[conditional]` 注解，条件不满足则跳过注册
  - [x] SubTask 10.4: 编写 `conditional_test.v` 验证条件注册

- [x] Task 11: 实现 BeanPostProcessor 真实 AOP 代理（P0 1.6/5.1/5.4）
  - [x] SubTask 11.1: `core/post_processor.v` — `AnnotationAwarePostProcessor` 实现 `before()`，扫描 bean 方法注解
  - [x] SubTask 11.2: `core/post_processor.v` — 检测 `@[transactional]` 方法，生成事务包装代理（before: begin, after: commit, error: rollback）
  - [x] SubTask 11.3: `core/post_processor.v` — 检测 `@[cacheable]` 方法，生成缓存包装代理（before: 查缓存, hit: 返回, miss: 执行并缓存）
  - [x] SubTask 11.4: `core/post_processor.v` — `after()` 调用 `InitializingBean.afterPropertiesSet()` 与 `@post_construct`
  - [x] SubTask 11.5: 编写 `aop_proxy_test.v` 验证事务回滚、缓存命中

- [x] Task 12: 实现 @ControllerAdvice 全局异常处理（P0 6.1）
  - [x] SubTask 12.1: `web/exception.v` — 新增 `@[controller_advice]` 注解与 `ExceptionHandler` trait
  - [x] SubTask 12.2: `web/exception.v` — `ExceptionResolver` 注册全局 advice，异常发生时按类型匹配 handler
  - [x] SubTask 12.3: `web/exception.v` — 替换 `extract_http_status` 的 `typeof(err).name` 字符串匹配为类型注册表
  - [x] SubTask 12.4: 编写 `controller_advice_test.v` 验证全局异常处理

- [x] Task 13: 实现 JpaRepository 零回调仓库（P0 8.3）
  - [x] SubTask 13.1: `orm/repository.v` — 新增 `JpaRepository[T]` 基类，内置 `find_by_id`/`save`/`delete`/`find_all`/`count`
  - [x] SubTask 13.2: `orm/repository.v` — 通过 comptime 从 `T` 结构体生成 SQL（字段名、表名、主键）
  - [x] SubTask 13.3: `orm/repository.v` — `JpaRepository[T]` 实现 `@[autowired]` 自动注入 `OrmManager`
  - [x] SubTask 13.4: 编写 `jpa_repository_test.v` 验证零配置 CRUD

- [x] Task 14: 实现 MockMvc 测试工具（P0 9.1）
  - [x] SubTask 14.1: `web/testing.v` — 新增 `MockMvc` 结构体，封装 `mock_request`/`mock_response`
  - [x] SubTask 14.2: `web/testing.v` — `MockMvc.perform(request)` 返回 `MockResult`，含 `status`/`body`/`headers`
  - [x] SubTask 14.3: `web/testing.v` — `MockResult` 提供 `assert_status(code)`/`assert_json_contains(path, value)`/`assert_header(k, v)`
  - [x] SubTask 14.4: 编写 `mockmvc_test.v` 验证模拟请求

- [x] Task 15: example/ 迁移到 DI 容器（P0 7.1）
  - [x] SubTask 15.1: `example/main.v` — 使用 `application_context` 注册 bean，移除手动 wiring
  - [x] SubTask 15.2: `example/bootstrap.v` — 使用 `@[configuration]` + `@[bean]` 声明配置
  - [x] SubTask 15.3: `example/controllers.v` — 使用 `@[controller]` + `@[autowired]`
  - [x] SubTask 15.4: `example/services.v` — 使用 `@[service]` + `@[autowired]` + `@[transactional]`
  - [x] SubTask 15.5: 验证 example 编译运行，功能等价

## Phase P2 — 大师级质量与心智成本

- [x] Task 16: 统一关闭顺序与资源协调
  - [x] SubTask 16.1: `core/application_context.v` — `shutdown()` 按 web → queue → ticker → schedule → event → cache → orm → pool → core 顺序关闭
  - [x] SubTask 16.2: 每阶段超时 5s，超时记录警告并继续
  - [x] SubTask 16.3: 编写 `shutdown_order_test.v` 验证关闭顺序

- [x] Task 17: 资源池生命周期完整化文档与测试
  - [x] SubTask 17.1: `pool/pool.v` — 完善资源池七阶段：factory → validate(is_valid) → acquire → use → release → idle_timeout → max_lifetime → close
  - [x] SubTask 17.2: 编写 `pool_full_lifecycle_test.v` 验证完整链路
  - [x] SubTask 17.3: 验证所有后台协程在 shutdown 后退出（无协程泄漏）

- [x] Task 18: 最终验证与文档更新
  - [x] SubTask 18.1: 运行 `v test photon/...` 确保全部通过
  - [x] SubTask 18.2: 运行 `v fmt -w photon/...` 验证格式
  - [x] SubTask 18.3: 更新 `优化文档.md` 记录 Phase 3 优化执行记录
  - [x] SubTask 18.4: 验证 example/ 编译运行

# Task Dependencies

- Task 1（ticker 生命周期）独立，可并行
- Task 2（pool 生命周期）独立，可并行
- Task 3（orm 事务并发）独立，可并行
- Task 4（core 容器）独立，可并行
- Task 5（cache 并发）独立，可并行
- Task 6（locking/queue/web/storage）独立，可并行
- Task 7（schedule/dispatcher/di_enhanced）独立，可并行
- Task 8（application_context 生命周期）依赖 Task 4（core 容器修复完成）
- Task 9（@ConfigurationProperties）依赖 Task 4
- Task 10（@Conditional）依赖 Task 4
- Task 11（BeanPostProcessor AOP）依赖 Task 8（生命周期顺序修正）
- Task 12（@ControllerAdvice）独立，可并行
- Task 13（JpaRepository）依赖 Task 3（orm 修复完成）
- Task 14（MockMvc）独立，可并行
- Task 15（example 迁移）依赖 Task 9/10/11/13（注解能力就绪）
- Task 16（统一关闭顺序）依赖 Task 1/2/3/4/5/6（各模块生命周期修复完成）
- Task 17（资源池完整化）依赖 Task 2
- Task 18（最终验证）依赖所有前置任务
