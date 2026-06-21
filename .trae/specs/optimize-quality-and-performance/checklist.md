# Checklist

## P0 正确性与安全修复

- [x] `cache/memory.v` 的 `get`/`has`/`keys`/`size`/`stats` 中 rlock 后用 runlock 释放（非 unlock）
- [x] `cache/memory.v` 的 `get` 过期删除分支锁升级正确（rlock→runlock→lock→unlock）
- [x] `orm/orm.v` 的 `OrmManager` 添加 `mu sync.RwMutex` 保护 `connections` map
- [x] `orm/orm.v` 的 `register_connection`/`remove_connection` 用写锁
- [x] `orm/orm.v` 的 `connection`/`get_conn`/`has_connection`/`connection_names` 用读锁
- [x] `orm/transaction.v` 的 `TransactionManager` 添加 `mu sync.Mutex` 保护 `active`/`savepoint_count`
- [x] `cache/cache.v` 的 `CacheRegistry` 添加 `mu sync.RwMutex` 保护 `caches` map
- [x] `web/session.v` 的 `Session` 添加 `mu sync.RwMutex` 保护 `data`/`flash_data` map
- [x] `ticker/bucket.v` 的 `get_scheduler()` 用 sync.Once 或 mutex 保护初始化
- [x] `ticker/bucket.v` 的 `counter` 递增用原子操作或加锁
- [x] `ticker/schedule.v` 的 `Scheduler` 添加 `mu sync.RwMutex` 保护 `tasks`/`is_running`
- [x] `security/jwt.v` 使用 `crypto.sha256` 替换自实现 SHA-256
- [x] `security/jwt.v` 使用 `crypto.hmac` 替换自实现 HMAC-SHA256
- [x] `security/jwt.v` 删除自实现的 K 常量与哈希循环（jwt.v:213-365）
- [x] `apidoc/storage.v` 的 `get_entry`/`get_or_create_entry` 不返回锁外可变引用
- [x] `v test cache/ orm/ ticker/ security/ apidoc/` 全部通过

## P0 性能热点修复

- [x] `cache/memory.v` 的 `get` 仅持读锁返回值（采样更新元数据）
- [x] `cache/memory.v` 实现 O(1) LRU（双向链表 + 哈希表）
- [x] `cache/memory.v` 移除 `evict_one_unsafe()` 的 O(n) 全表扫描
- [x] `cache/singleflight.v` 用 channel 阻塞唤醒 follower（非 1ms 轮询）
- [x] `cache/singleflight.v` 删除 `time.sleep(1 * time.millisecond)` 轮询
- [x] `cache/cache_tags.v` 添加 `tag_to_keys` 反向索引
- [x] `cache/cache_tags.v` 的 `flush(tag)` 为 O(k) 而非 O(n*m)
- [x] `web/kernel.v` 添加 `frozen_listeners` 冻结快照字段
- [x] `web/kernel.v` 的 `dispatch()` 优先读冻结快照无克隆
- [x] 实现公共 `fnv1a_str(s string) u64` 零拷贝哈希函数
- [x] `web/ratelimit.v` 的 `shard_for()` 使用 `fnv1a_str`
- [x] `core/sharded_lock.v` 的 `shard_index()` 使用 `fnv1a_str`
- [x] `core/application_context.v` 的 `topological_sort` 用索引游标替代 `queue.delete(0)`
- [x] `core/core.v` 的 `check_circular_dependencies` 用索引游标替代 `queue.delete(0)`
- [x] `logger/logger.v` 的 `LogEntry.fields` 持有 `&map` 不可变引用
- [x] `logger/logger.v` 的 MDC 写入时 COW 复制，日志读取零拷贝
- [x] `v test cache/ web/ core/ logger/` 全部通过

## P1 设计模式与代码质量

- [x] `core/core.v` 的 `resolve`/`has`/`get_definition` 使用 `sharded_mu.rlock(key)`/`runlock(key)`
- [x] `core/core.v` 的 `register`/`set_instance` 使用 `sharded_mu.@lock(key)`/`unlock(key)`
- [x] `core/core.v` 仅 `destroy_all`/`bean_names` 保留全局 `mu` 锁
- [x] `locking/lock.v` 的 `LocalMutex` 使用 `sync.Mutex` 原生实现
- [x] `locking/lock.v` 删除自旋+backoff 逻辑
- [x] `locking/lock.v` 删除 `lock_with_timeout` 不可达的 `return false`
- [x] `web/upload.v` 的 `init_upload` 先 mkdir 再加锁插入 map
- [x] `web/upload.v` 的 `assemble` 加锁取出 info 后解锁再做文件 I/O
- [x] `pool/pool.v` 的 `acquire` 解锁后调用 factory 再加锁存入
- [x] `queue/dispatcher.v` 用 sync.Once 初始化全局 dispatcher
- [x] `core/core.v` 的 `Container.factory_registry`/`parent`/`type_index`/`event_bus` 改为 `?&T`
- [x] `orm/repository.v` 的 `BaseRepository` exec_* 字段改为 Option 或构造时强制注入
- [x] `logger/logger.v` 的 `encoder` 默认值改为 `ConsoleEncoder{}` 哨兵
- [x] 移除 `cache/manager.v` 的 `new_named_cache_adapter`/`new_cache_registry_adapter` 中 `unsafe { }`
- [x] 移除 `cache/annotation.v`/`security/filter.v`/`web/upload.v`/`queue/dispatcher.v`/`web/session.v` 中纯字段赋值的 `unsafe { }`
- [x] 移除 `core/core.v` 的 `set_event_bus` 中 `unsafe { bus }`
- [x] 移除 `cache/cache.v` 的 `has_immutable` 中 `unsafe { }`
- [x] `core/post_processor.v` 删除或实现空壳 BeanPostProcessor 方法
- [x] `web/middleware.v` 删除 `recover_middleware` 空操作
- [x] `support/str.v` 的 `snake`/`camel`/`studly`/`kebab`/`title` 改用 `[]u8` 缓冲区
- [x] `orm/derive.v` 的条件解析与 `camel_to_snake` 改用 `strings.Builder`
- [x] `cache/cache_tags.v` 的 `get_namespace`/`tagged_key` 改用 `strings.Builder`
- [x] `v test core/ locking/ web/ pool/ queue/ support/ orm/ cache/` 全部通过

## P1 API 可用性

- [x] `orm/repository.v` 定义 `RepositoryConfig[T]` 结构体
- [x] `orm/repository.v` 新增 `new_repository_with_config[T]` 构造函数
- [x] `orm/repository.v` 旧 `new_repository` 标注 `@[deprecated]`
- [x] `queue/dispatcher.v` 的 `driver` 字段类型为 `&QueueDriver` 接口
- [x] `queue/dispatcher.v` 的 `new_dispatcher` 参数为 `&QueueDriver` 接口
- [x] `v test orm/ queue/` 全部通过

## 集成验证

- [x] `v -enable-globals test .` 全量测试通过
- [x] `v fmt -verify .` 格式验证通过
- [x] `优化文档.md` 末尾追加「质量与性能优化执行记录」章节
