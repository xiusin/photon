# Checklist

## Phase P0 — 正确性与安全

### Task 1: ticker 协程生命周期
- [x] `ticker/bucket.v` `scheduler_run()` 通过 `stop_signal` 可退出
- [x] `ticker/bucket.v` `Ticker.stop()` 传入正确 `when` 值
- [x] `ticker/bucket.v` `TimerScheduler` 使用 `WaitGroup` 等待协程退出
- [x] `ticker/bucket.v` `running` 标志线程安全
- [x] `ticker_lifecycle_test.v` 验证 stop 后无协程泄漏

### Task 2: pool 对象生命周期
- [x] `pool/pool.v` `close()` 调用每个 `PooledObject.close()`
- [x] `pool/pool.v` `acquire()` 调用 `is_valid()` 校验
- [x] `pool/pool.v` 后台 GC 清理 `idle_timeout` 对象
- [x] `pool/pool.v` `max_lifetime` 限制对象存活时间
- [x] `pool/pool.v` `stats()` 加锁读取
- [x] `pool/pool.v` `release()` 检查池关闭状态
- [x] `pool_lifecycle_test.v` 验证完整生命周期

### Task 3: orm 连接与事务并发
- [x] `orm/orm.v` `remove_connection()` 关闭 DB 连接
- [x] `orm/orm.v` `close_all()` 关闭所有连接
- [x] `orm/orm.v` 实现 `DisposableBean.destroy()`
- [x] `orm/transaction.v` `requires_new` 使用协程本地事务栈
- [x] `orm/transaction.v` `is_active()` 使用读锁
- [x] `orm/transaction.v` `begin/commit/rollback` 操作事务栈
- [x] `transaction_concurrency_test.v` 验证多协程并发

### Task 4: core 容器双锁竞态与生命周期
- [x] `core/core.v` 消除 `sharded_mu` 与 `mu` 双锁同图
- [x] `core/core.v` `resolve_all_by_type()` 锁平衡
- [x] `core/core.v` 指针字段（event_bus/parent/factory_registry）加锁保护
- [x] `core/application_context.v` `destroy_all()` 调用 `@pre_destroy`
- [x] `core/application_context.v` `destroy_all()` 调用 `DisposableBean.destroy()`
- [x] `core/application_context.v` `shutdown()` 清理引用切片
- [x] `container_lifecycle_test.v` 验证 destroy 调用顺序

### Task 5: cache 并发与生命周期
- [x] `cache/memory.v` `get()` 读锁下不写 map
- [x] `cache/memory.v` 过期删除无 TOCTOU
- [x] `cache/cache_tags.v` `tag_to_keys` 加锁保护
- [x] `cache/cache_tags.v` `flush_tag()` 同步更新反向索引
- [x] `cache/cache_tags.v` TTL 过期同步更新反向索引
- [x] `cache/cache.v` `CacheRegistry.unregister()` 存在
- [x] `cache/memory.v` 后台 GC 协程清理过期条目
- [x] `cache_concurrency_test.v` 验证并发一致性

### Task 6: locking/queue/web/storage 资源泄漏
- [x] `locking/lock.v` `unlock_and_cleanup()` 无竞态
- [x] `locking/lock.v` `LockManager` 自动清理空闲锁
- [x] `queue/worker.v` `running` 线程安全
- [x] `queue/worker.v` `registry` map 加锁
- [x] `queue/failed_jobs.v` `jobs` 切片加锁
- [x] `queue/memory_driver.v` `count()` 加读锁
- [x] `queue/worker.v` retry sleep 可中断
- [x] `web/kernel.v` `frozen` 标志线程安全
- [x] `web/kernel.v` `unfreeze()`/`off()` 方法存在
- [x] `web/session.v` `MemorySessionStore` 自动 GC
- [x] `web/ratelimit.v` `attempts` 有界
- [x] `web/ratelimit.v` `windows` 定期清理
- [x] `web/upload.v` 过期上传清理
- [x] `storage/local_adapter.v` `permissions` 有界
- [x] `core/event.v` `dispatch_async()` 协程追踪
- [x] `core/event.v` `off_listener()` 真正注销
- [x] `resource_lifecycle_test.v` 验证清理

### Task 7: schedule/dispatcher/di_enhanced 并发
- [x] `ticker/schedule.v` `is_running` 加锁（lines 298-300 rlock/runlock，由 Task 1 修复）
- [x] `ticker/schedule.v` `task_count()`/`enabled_count()` 加读锁（lines 402-423 rlock/runlock，由 Task 1 修复）
- [x] `queue/dispatcher.v` 双重检查锁定内存可见（`dispatcher_mu` 改为 RwMutex，快速路径 rlock）
- [x] `core/di_enhanced.v` `DeferredProvider.get()` 双重检查锁定修复（rlock 快速路径 + @lock 双重检查）
- [x] `core/lifecycle.v` `SmartLifecycleManager` 加锁（`mu sync.RwMutex`，回调在锁外执行）
- [x] `core/lifecycle.v` `stop_all()` 超时（goroutine + chan + 5s 轮询）
- [x] `pool/db_pool.v` `db_pool_id_counter` 原子化（`db_pool_id_mu sync.Mutex` 保护）
- [x] `core/sharded_lock.v` shard 选择用位运算（`& (shard_count - 1)` + power-of-2 assert）
- [x] `concurrency_correctness_test.v` 验证（8 个测试函数，全部通过）

### Task 8: application_context 生命周期与回滚
- [x] `core/application_context.v` `refresh()` 失败回滚
- [x] `core/application_context.v` 生命周期顺序：before → @post_construct → afterPropertiesSet → after
- [x] `core/application_context.v` `refresh()` 调用 `afterPropertiesSet()`
- [x] `core/application_context.v` `destroy_all()` 调用 `DisposableBean.destroy()`
- [x] `core/application_context.v` `shutdown()` 清理引用
- [x] `lifecycle_order_test.v` 验证顺序

## Phase P1 — Spring 逻辑对齐

### Task 9: @ConfigurationProperties
- [x] `core/environment.v` `bind_to_struct[T]` 泛型函数存在
- [x] 支持嵌套结构体、数组、基本类型
- [x] 支持 `@[config_field]` 自定义键
- [x] `core/core.v` 自动绑定 `@[configuration_properties]` bean
- [x] 旧 `bind_to` 标记 `@[deprecated]`
- [x] `config_binding_test.v` 验证

### Task 10: @Conditional
- [x] `core/condition.v` `OnClassCondition` 真实检查
- [x] `OnBeanCondition`/`OnPropertyCondition` 存在
- [x] `core/core.v` 注册时评估条件
- [x] `conditional_test.v` 验证

### Task 11: BeanPostProcessor AOP
- [x] `core/post_processor.v` `AnnotationAwarePostProcessor.before()` 扫描注解
- [x] `@[transactional]` 自动织入事务代理
- [x] `@[cacheable]` 自动织入缓存代理
- [x] `after()` 调用 `afterPropertiesSet()` 与 `@post_construct`
- [x] `aop_proxy_test.v` 验证事务回滚、缓存命中

### Task 12: @ControllerAdvice
- [x] `web/exception.v` `@[controller_advice]` 注解与 `ExceptionHandler` trait
- [x] `ExceptionResolver` 注册全局 advice
- [x] 替换 `typeof(err).name` 字符串匹配
- [x] `controller_advice_test.v` 验证

### Task 13: JpaRepository
- [x] `orm/repository.v` `JpaRepository[T]` 基类存在
- [x] comptime 生成 SQL
- [x] 自动注入 `OrmManager`
- [x] `jpa_repository_test.v` 验证零配置 CRUD

### Task 14: MockMvc
- [x] `web/testing.v` `MockMvc` 结构体存在
- [x] `MockMvc.perform()` 返回 `MockResult`
- [x] `MockResult` 提供 `assert_status`/`assert_json_contains`/`assert_header`
- [x] `mockmvc_test.v` 验证

### Task 15: example/ 迁移
- [x] `example/main.v` 使用 `application_context`
- [x] `example/bootstrap.v` 使用 `@[configuration]` + `@[bean]`
- [x] `example/controllers.v` 使用 `@[controller]` + `@[autowired]`
- [x] `example/services.v` 使用 `@[service]` + `@[transactional]`
- [x] example 编译运行功能等价

## Phase P2 — 大师级质量

### Task 16: 统一关闭顺序
- [x] `core/application_context.v` `shutdown()` 按 web → queue → ticker → schedule → event → cache → orm → pool → core 顺序
- [x] 每阶段超时 5s
- [x] `shutdown_order_test.v` 验证顺序

### Task 17: 资源池完整化
- [x] `pool/pool.v` 七阶段完整：factory → validate → acquire → use → release → idle_timeout → max_lifetime → close
- [x] `pool_full_lifecycle_test.v` 验证
- [x] 所有后台协程 shutdown 后退出

### Task 18: 最终验证
- [x] `v test photon/...` 全部通过
- [x] `v fmt -w photon/...` 格式验证
- [x] `优化文档.md` 更新 Phase 3 记录
- [x] example/ 编译运行通过
