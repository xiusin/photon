# 代码质量、设计模式与锁优化 Spec

## Why

Photon 作为基础框架，"好用与性能是第一要素"。经全面审计发现：30 处锁/同步问题（7 处严重正确性 bug）、45 处设计模式反模式（God Object、voidptr 类型擦除、空壳抽象、自实现加密）、40+ 处性能热点（缓存双锁、LRU O(n)、singleflight 轮询、每请求克隆、O(n²) 排序）。这些问题在并发场景下会导致数据竞争、死锁、性能退化，必须系统性修复。

## What Changes

### P0 正确性与安全修复（必须）
- **修复 `cache/memory.v` 的 rlock/unlock 配对错误**（用 unlock 释放 rlock，未定义行为）
- **为 `OrmManager`/`TransactionManager`/`CacheRegistry`/`Session` 添加缺失的同步保护**（数据竞争）
- **修复 `ticker` 模块竞态条件**（全局调度器初始化、counter 递增、Scheduler 无锁）
- **迁移 `security/jwt.v` 自实现 SHA-256/HMAC 到 `crypto` 模块**（安全漏洞）
- **修复 `apidoc/storage.v` 返回可变引用后释放锁**（数据竞争）

### P0 性能热点修复（高影响）
- **`cache/memory.v` get 双锁 → 采样更新**（读路径串行化）
- **`cache/memory.v` LRU O(n) → O(1) 双向链表+哈希表**
- **`cache/singleflight.v` 轮询 → channel 阻塞唤醒**
- **`cache/cache_tags.v` flush O(n*m) → 反向索引 O(k)**
- **`web/kernel.v` 每请求克隆监听器 → 冻结快照**
- **`web/ratelimit.v` key.bytes() → 零拷贝哈希**
- **`core/application_context.v` topological_sort O(n²) → O(n) 索引游标**
- **`logger/logger.v` 每条日志 context.clone() → COW 引用**

### P1 设计模式与代码质量
- **移除 `unsafe { nil }` 滥用 → Option 类型**（Container、BaseRepository、TransactionManager、Logger 等关键字段）
- **移除不必要的 `unsafe { }` 块**（纯字段赋值、接口方法调用）
- **删除空壳抽象**（BeanPostProcessor 空操作、recover_middleware 空操作）
- **修复 `LocalMutex` 自旋锁 → 原生 mutex**
- **收窄锁范围**（I/O 移出锁、factory 调用移出锁）
- **启用 `core/core.v` 的 ShardedRwMutex**（声明但未使用，全局锁瓶颈）
- **热路径字符串拼接 → `strings.Builder`/`[]u8`**（str.v、derive.v、cache_tags.v）

### P1 API 可用性
- **统一构造命名**（new_X 风格）
- **`new_repository` 9 参数 → `RepositoryConfig[T]` 结构体**
- **`QueueDispatcher.driver` 具体类型 → `&QueueDriver` 接口**

## Impact

- **Affected specs**: deep-optimization-spring-alignment（已完成，本次在其基础上深化）
- **Affected code**:
  - `cache/memory.v`, `cache/singleflight.v`, `cache/cache_tags.v`, `cache/cache.v` — 缓存正确性与性能
  - `core/core.v`, `core/application_context.v`, `core/event.v`, `core/sharded_lock.v` — DI 容器并发与性能
  - `orm/orm.v`, `orm/transaction.v`, `orm/repository.v`, `orm/derive.v` — ORM 线程安全与性能
  - `web/kernel.v`, `web/ratelimit.v`, `web/upload.v`, `web/session.v`, `web/pipeline.v` — Web 热路径
  - `security/jwt.v` — 安全修复
  - `logger/logger.v`, `logger/json_encoder.v` — 日志性能
  - `locking/lock.v`, `pool/pool.v` — 锁与池
  - `ticker/heap.v`, `ticker/schedule.v`, `ticker/bucket.v`, `ticker/optimizer.v` — 定时器正确性
  - `support/str.v` — 命名转换性能
  - `apidoc/storage.v` — 文档存储并发

## ADDED Requirements

### Requirement: 缓存模块正确性与性能
系统 SHALL 在 `cache/memory.v` 中正确配对 rlock/runlock，SHALL 使用 O(1) LRU 淘汰算法，SHALL 在 get 路径仅持读锁（采样更新元数据）。

#### Scenario: 高并发读缓存
- **WHEN** 多个 goroutine 并发调用 `MemoryCache.get`
- **THEN** 读锁正确配对（runlock 释放），无未定义行为
- **AND** 访问元数据更新不阻塞并发读
- **AND** LRU 淘汰为 O(1) 而非 O(n)

### Requirement: Singleflight 零延迟唤醒
系统 SHALL 在 `cache/singleflight.v` 中用 channel 阻塞唤醒 follower，而非 1ms 轮询。

#### Scenario: 缓存击穿去重
- **WHEN** 多个 follower 等待 leader 完成
- **THEN** leader 完成后通过 channel 立即唤醒所有 follower
- **AND** follower 无轮询 CPU 开销

### Requirement: ORM 线程安全
系统 SHALL 为 `OrmManager.connections`、`TransactionManager.active`/`savepoint_count` 添加同步保护。

#### Scenario: 并发数据库访问
- **WHEN** Web 服务器多请求并发访问 OrmManager
- **THEN** connections map 读写有 RwMutex 保护
- **AND** TransactionManager 状态变更有序列化

### Requirement: 定时器线程安全
系统 SHALL 修复 `ticker` 模块的全局调度器初始化竞态、counter 递增竞态、Scheduler 无锁问题。

#### Scenario: 并发创建定时器
- **WHEN** 多个 goroutine 同时创建 timer/ticker
- **THEN** 全局调度器仅初始化一次（sync.Once 或 mutex 保护）
- **AND** counter 递增为原子操作
- **AND** Scheduler.tasks 访问有锁保护

### Requirement: JWT 使用标准加密库
系统 SHALL 迁移 `security/jwt.v` 的自实现 SHA-256/HMAC-SHA256 到 `crypto.sha256` 与 `crypto.hmac` 模块。

#### Scenario: JWT 签名与验证
- **WHEN** 生成或验证 JWT token
- **THEN** 使用 `crypto.sha256` 与 `crypto.hmac` 标准实现
- **AND** 删除自实现的 64 个 K 常量与哈希循环

### Requirement: 日志零拷贝上下文
系统 SHALL 在 `logger/logger.v` 中用 COW 引用替代每条日志的 `context.clone()`。

#### Scenario: 高频日志输出
- **WHEN** 每秒输出数千条日志
- **THEN** LogEntry.fields 持有不可变 map 引用
- **AND** 仅在 MDC 写入时 COW 复制

### Requirement: 拓扑排序 O(n)
系统 SHALL 修复 `core/application_context.v` 的 `topological_sort`，用索引游标替代 `queue.delete(0)`。

#### Scenario: 大量 Bean 启动排序
- **WHEN** 应用包含数百个 Bean
- **THEN** 启动排序为 O(n) 而非 O(n²)

### Requirement: 限流零拷贝哈希
系统 SHALL 在 `web/ratelimit.v` 与 `core/sharded_lock.v` 中实现零拷贝 `fnv1a_str(s string) u64`。

#### Scenario: 高并发限流检查
- **WHEN** 每个受保护请求执行限流检查
- **THEN** key 哈希不分配 `[]u8`
- **AND** 分片锁定位零分配

## MODIFIED Requirements

### Requirement: Container 并发模型
Container SHALL 启用已声明的 `ShardedRwMutex`，按 key 分片保护 bean 定义与实例访问，仅全量操作（destroy_all、bean_names）保留全局锁。

### Requirement: LocalMutex 实现
LocalMutex SHALL 使用 V `sync.Mutex` 原生实现，删除因 `try_lock` bug 而引入的自旋+backoff 模拟。

### Requirement: 锁范围收窄
系统 SHALL 将 I/O 操作（文件读写、网络连接、factory 调用）移出锁保护范围，仅在访问共享数据时持锁。

### Requirement: unsafe nil 消除
关键字段（Container.factory_registry/parent/type_index/event_bus、BaseRepository.exec_*、TransactionManager 回调、Logger.encoder）SHALL 使用 Option 类型 `?&T` 替代 `unsafe { nil }`。

### Requirement: 空壳抽象清理
系统 SHALL 删除或实现空壳 BeanPostProcessor（AutowiredAnnotationPostProcessor 等）与空操作中间件（recover_middleware、session_middleware），避免误导。

### Requirement: 构造器可用性
`new_repository` 与 `new_derived_repository` SHALL 接受 `RepositoryConfig[T]` 结构体而非 9-12 个位置参数。`QueueDispatcher.driver` SHALL 为 `&QueueDriver` 接口类型。

## REMOVED Requirements

### Requirement: 自实现加密算法
**Reason**: `security/jwt.v` 自实现 SHA-256 与 HMAC-SHA256 是未审计的安全风险，V 的 `crypto` 模块已提供标准实现。
**Migration**: 迁移到 `crypto.sha256` 与 `crypto.hmac`，删除自实现代码（jwt.v:213-365）。

### Requirement: LocalMutex 自旋锁
**Reason**: 因 V 0.5.1 `try_lock` bug 而引入的自旋+backoff 模拟互斥锁，性能差且 `locked` 字段无内存屏障。
**Migration**: 改用 `sync.Mutex` 原生 `@lock`/`unlock`，删除自旋逻辑。
