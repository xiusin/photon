# Tasks

## 阶段 1：P0 正确性与安全修复

- [x] Task 1: 修复 cache/memory.v 的 rlock/unlock 配对错误
  - [x] SubTask 1.1: 将 `get()`/`has()`/`keys()`/`size()`/`stats()` 中所有 `@rlock()` 后的 `unlock()` 改为 `runlock()`
  - [x] SubTask 1.2: 验证 `get()` 中过期删除分支的锁升级（rlock→runlock→lock→unlock）正确
  - [x] SubTask 1.3: 运行 `v test cache/` 验证通过

- [x] Task 2: 为 ORM 模块添加缺失的同步保护
  - [x] SubTask 2.1: 在 `orm/orm.v` 的 `OrmManager` 添加 `mu sync.RwMutex` 字段，`register_connection`/`remove_connection` 用写锁，`connection`/`get_conn`/`has_connection`/`connection_names` 用读锁
  - [x] SubTask 2.2: 在 `orm/transaction.v` 的 `TransactionManager` 添加 `mu sync.Mutex` 字段，保护 `active`/`savepoint_count` 的读写
  - [x] SubTask 2.3: 运行 `v test orm/` 验证通过

- [x] Task 3: 为 CacheRegistry 与 Session 添加同步保护
  - [x] SubTask 3.1: 在 `cache/cache.v` 的 `CacheRegistry` 添加 `mu sync.RwMutex`，`register` 用写锁，`get_cache`/`get_cache_names` 用读锁
  - [x] SubTask 3.2: 在 `web/session.v` 的 `Session` 添加 `mu sync.RwMutex`，`get`/`get_all`/`has` 用读锁，`set`/`remove`/`flash`/`clear` 用写锁
  - [x] SubTask 3.3: 运行 `v test cache/ web/` 验证通过

- [x] Task 4: 修复 ticker 模块竞态条件
  - [x] SubTask 4.1: 在 `ticker/bucket.v` 用 `sync.Once` 或全局 mutex 保护 `get_scheduler()` 初始化
  - [x] SubTask 4.2: 在 `ticker/bucket.v` 用 `sync.atomic` 保护 `counter` 递增（或加锁）
  - [x] SubTask 4.3: 在 `ticker/schedule.v` 的 `Scheduler` 添加 `mu sync.RwMutex`，`register`/`stop` 用写锁，`tick` 用读锁遍历
  - [x] SubTask 4.4: 运行 `v test ticker/` 验证通过

- [x] Task 5: 迁移 security/jwt.v 自实现加密到 crypto 模块
  - [x] SubTask 5.1: 在 `security/jwt.v` 添加 `import crypto.sha256` 与 `import crypto.hmac`
  - [x] SubTask 5.2: 用 `sha256.sum()` 替换自实现 `sha256_hash()` 函数（删除 jwt.v:213-365 的 K 常量与哈希循环）
  - [x] SubTask 5.3: 用 `hmac.new()` 或等效 API 替换自实现 `hmac_sha256()` 函数
  - [x] SubTask 5.4: 运行 `v test security/` 验证 JWT 签名/验证往返一致

- [x] Task 6: 修复 apidoc/storage.v 返回可变引用后释放锁
  - [x] SubTask 6.1: 将 `get_entry`/`get_or_create_entry` 改为返回值拷贝而非 `&ApiDocEntry`，或为每个 entry 添加独立锁
  - [x] SubTask 6.2: 运行 `v test apidoc/` 验证通过

## 阶段 2：P0 性能热点修复

- [x] Task 7: 优化 cache/memory.v 的 get 双锁与 LRU
  - [x] SubTask 7.1: 将 `get()` 的访问元数据更新改为采样模式（每 64 次命中才更新），仅持读锁返回值
  - [x] SubTask 7.2: 实现 O(1) LRU：用 `map[string]&LruNode` + 双向链表，`set` 时移到头部，淘汰时删尾部
  - [x] SubTask 7.3: 移除 `evict_one_unsafe()` 的 O(n) 全表扫描
  - [x] SubTask 7.4: 运行 `v test cache/` 验证通过

- [x] Task 8: 优化 cache/singleflight.v 轮询为 channel 唤醒
  - [x] SubTask 8.1: 在 `Call` 结构添加 `done_ch chan bool`（或用 `sync.Cond`）
  - [x] SubTask 8.2: leader 完成后 `done_ch.close()` 或 `cond.signal()`
  - [x] SubTask 8.3: follower 阻塞在 `done_ch.recv()` 或 `cond.wait()`，删除 `time.sleep(1ms)` 轮询
  - [x] SubTask 8.4: 运行 `v test cache/` 验证通过

- [x] Task 9: 优化 cache/cache_tags.v 的 flush 为反向索引
  - [x] SubTask 9.1: 在 `TaggedCache` 添加 `tag_to_keys map[string][]string` 反向索引（注：原计划 `map[string]map[string]bool`，因 V 禁止拷贝 map 值且 `v fmt` 会将链式访问 `m[k][k2]=v` 反糖为提取/修改/回写模式导致编译失败，改用 `[]string` 数组，数组可自由拷贝，功能等价）
  - [x] SubTask 9.2: `set` 时维护反向索引（O(1) 追加），`flush(tag)` 直接取出 key 列表删除（O(k)）
  - [x] SubTask 9.3: 运行 `v test cache/` 验证通过（4 passed, 4 total）

- [x] Task 10: 优化 web/kernel.v 每请求克隆监听器
  - [x] SubTask 10.1: 在 `HttpKernel` 添加 `frozen_listeners map[string][]EventListener` 字段
  - [x] SubTask 10.2: 提供 `freeze_listeners()` 方法在启动后冻结监听器快照
  - [x] SubTask 10.3: `dispatch()` 优先读冻结快照，无克隆；未冻结时回退到 RwMutex 读锁
  - [x] SubTask 10.4: 运行 `v test web/` 验证通过

- [x] Task 11: 实现零拷贝 fnv1a_str 哈希函数
  - [x] SubTask 11.1: 在 `support/` 或 `core/` 创建公共 `fnv1a_str(s string) u64` 函数，直接遍历字符串字节不分配 `[]u8`
  - [x] SubTask 11.2: 在 `web/ratelimit.v` 的 `shard_for()` 与 `core/sharded_lock.v` 的 `shard_index()` 中使用 `fnv1a_str`
  - [x] SubTask 11.3: 运行 `v test web/ core/` 验证通过

- [x] Task 12: 修复 core/application_context.v 拓扑排序 O(n²) → O(n)
  - [x] SubTask 12.1: 在 `topological_sort` 用索引游标 `head := 0` 替代 `queue.delete(0)`，`node := queue[head]; head++`
  - [x] SubTask 12.2: 同样修复 `core/core.v` 的 `check_circular_dependencies()` 中的 `queue.delete(0)`
  - [x] SubTask 12.3: 运行 `v test core/` 验证通过

- [x] Task 13: 优化 logger/logger.v 每条日志 context.clone()
  - [x] SubTask 13.1: 将 `LogEntry.fields` 改为持有 `&map[string]string` 不可变引用
  - [x] SubTask 13.2: MDC `with()`/`set()` 时 COW 复制 map，日志读取零拷贝
  - [x] SubTask 13.3: 运行 `v test logger/` 验证通过

## 阶段 3：P1 设计模式与代码质量

- [x] Task 14: 启用 core/core.v 的 ShardedRwMutex
  - [x] SubTask 14.1: 将 `resolve`/`has`/`get_definition` 等按 key 操作改用 `sharded_mu.rlock(key)`/`runlock(key)`
  - [x] SubTask 14.2: 将 `register`/`set_instance` 等改用 `sharded_mu.@lock(key)`/`unlock(key)`
  - [x] SubTask 14.3: 仅 `destroy_all`/`bean_names` 等全量操作保留 `mu` 全局锁
  - [x] SubTask 14.4: 运行 `v test core/` 验证通过

- [x] Task 15: 修复 LocalMutex 自旋锁为原生 mutex
  - [x] SubTask 15.1: 在 `locking/lock.v` 将 `LocalMutex` 改用 `sync.Mutex` 的 `@lock`/`unlock`，删除自旋+backoff 逻辑
  - [x] SubTask 15.2: 用 channel（容量1）实现 `try_lock` 与 `lock_with_timeout`（若 V sync.Mutex 仍不可用）
  - [x] SubTask 15.3: 删除 `lock_with_timeout` 中不可达的 `return false`
  - [x] SubTask 15.4: 运行 `v test locking/` 验证通过

- [x] Task 16: 收窄锁范围（I/O 移出锁）
  - [x] SubTask 16.1: 在 `web/upload.v` 的 `init_upload` 先 `os.mkdir_all` 再加锁插入 map
  - [x] SubTask 16.2: 在 `web/upload.v` 的 `assemble` 加锁取出 info 并从 map 删除，解锁后再做文件 I/O
  - [x] SubTask 16.3: 在 `pool/pool.v` 的 `acquire` 先锁内检查是否需创建，解锁后调用 factory，再加锁存入
  - [x] SubTask 16.4: 在 `queue/dispatcher.v` 用 `sync.Once` 初始化全局 dispatcher，之后直接返回指针无需加锁
  - [x] SubTask 16.5: 运行 `v test web/ pool/ queue/` 验证通过

- [x] Task 17: 移除 unsafe nil 滥用 → Option 类型
  - [x] SubTask 17.1: 在 `core/core.v` 将 `Container.factory_registry`/`parent`/`type_index`/`event_bus` 改为 `?&T`
  - [x] SubTask 17.2: 在 `orm/repository.v` 将 `BaseRepository` 的 exec_* 字段改为 Option 类型或构造时强制注入
  - [x] SubTask 17.3: 在 `logger/logger.v` 将 `encoder` 默认值改为 `ConsoleEncoder{}` 哨兵，消除 nil 检查
  - [x] SubTask 17.4: 运行 `v test core/ orm/ logger/` 验证通过

- [x] Task 18: 移除不必要的 unsafe 块
  - [x] SubTask 18.1: 移除 `cache/manager.v` 的 `new_named_cache_adapter`/`new_cache_registry_adapter` 中的 `unsafe { }`
  - [x] SubTask 18.2: 移除 `cache/annotation.v`、`security/filter.v`、`web/upload.v`、`queue/dispatcher.v`、`web/session.v` 中纯字段赋值的 `unsafe { }`
  - [x] SubTask 18.3: 移除 `core/core.v` 的 `set_event_bus` 中 `unsafe { bus }`
  - [x] SubTask 18.4: 移除 `cache/cache.v` 的 `has_immutable` 中 `unsafe { }`
  - [x] SubTask 18.5: 运行相关模块测试验证通过

- [x] Task 19: 删除空壳抽象
  - [x] SubTask 19.1: 在 `core/post_processor.v` 删除或实现 `AutowiredAnnotationPostProcessor`/`ValueAnnotationPostProcessor`/`LifecycleAnnotationPostProcessor`/`EventListenerPostProcessor` 的空操作方法（改为文档说明注入在编译期完成）
  - [x] SubTask 19.2: 在 `web/middleware.v` 删除 `recover_middleware` 空操作（或实现真正 recover 逻辑）
  - [x] SubTask 19.3: 运行 `v test core/ web/` 验证通过

- [x] Task 20: 热路径字符串拼接优化
  - [x] SubTask 20.1: 在 `support/str.v` 将 `snake`/`camel`/`studly`/`kebab`/`title` 改用 `[]u8` 缓冲区（参考 `slug()` 实现）
  - [x] SubTask 20.2: 在 `orm/derive.v` 将条件解析与 `camel_to_snake` 改用 `strings.Builder`
  - [x] SubTask 20.3: 在 `cache/cache_tags.v` 将 `get_namespace`/`tagged_key` 改用 `strings.Builder`
  - [x] SubTask 20.4: 运行 `v test support/ orm/ cache/` 验证通过

## 阶段 4：P1 API 可用性

- [x] Task 21: 引入 RepositoryConfig 简化构造器
  - [x] SubTask 21.1: 在 `orm/repository.v` 定义 `RepositoryConfig[T]` 结构体（含 exec_find/exec_find_all/exec_insert/exec_update/exec_delete/exec_count/exec_exists 字段）
  - [x] SubTask 21.2: 新增 `new_repository_with_config[T](manager, db_name, config RepositoryConfig[T]) !&BaseRepository[T]`
  - [x] SubTask 21.3: 保留旧 `new_repository` 但标注 `@[deprecated]`
  - [x] SubTask 21.4: 运行 `v test orm/` 验证通过

- [x] Task 22: QueueDispatcher 改用接口类型
  - [x] SubTask 22.1: 在 `queue/dispatcher.v` 将 `driver` 字段类型从 `&MemoryDriver` 改为 `&QueueDriver`
  - [x] SubTask 22.2: 将 `new_dispatcher` 参数改为 `&QueueDriver`
  - [x] SubTask 22.3: 运行 `v test queue/` 验证通过

## 阶段 5：集成验证

- [x] Task 23: 全量测试与文档同步
  - [x] SubTask 23.1: 运行 `v -enable-globals test .` 全量测试，确保所有模块通过
  - [x] SubTask 23.2: 运行 `v fmt -verify .` 验证代码格式
  - [x] SubTask 23.3: 在 `优化文档.md` 末尾追加「质量与性能优化执行记录」章节

# Task Dependencies

- Task 7 依赖 Task 1（同文件 cache/memory.v，避免冲突）
- Task 9 依赖 Task 3（同模块 cache，先加锁再优化）
- Task 14 依赖 Task 17（先改 Option 类型再启用分片锁）
- Task 16 可与 Task 14/15 并行
- Task 20 可与 Task 14-19 并行
- Task 21/22 可与 Task 14-20 并行
- Task 23 依赖所有前置任务完成
