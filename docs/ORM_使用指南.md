# photon ORM 与 QueryBuilder 使用指南

> 基于 `photon/orm/` 源码深度分析生成，涵盖连接管理、实体映射、四种仓储层级、链式查询构建器、派生查询、Specification 模式、关系加载、事务管理、数据库迁移等全部核心能力。

---

## 目录

1. [架构总览](#1-架构总览)
2. [连接管理 — OrmManager](#2-连接管理--ormmanager)
3. [实体定义与注解系统](#3-实体定义与注解系统)
4. [OrmAdapter — 生命周期钩子层](#4-ormadapter--生命周期钩子层)
5. [BaseRepository — 完整 CRUD 仓储](#5-baserepository--完整-crud-仓储)
6. [Repository — 编译时推导仓储（推荐）](#6-repository--编译时推导仓储推荐)
7. [DerivedRepository — Spring Data 派生查询](#7-derivedrepository--spring-data-派生查询)
8. [QueryBuilder — 链式查询构建器](#8-querybuilder--链式查询构建器)
9. [派生查询方法名解析](#9-派生查询方法名解析)
10. [原生 SQL 查询与命名参数](#10-原生-sql-查询与命名参数)
11. [Specification 模式 — 动态组合查询](#11-specification-模式--动态组合查询)
12. [关系加载 — RelationLoader 与 EagerLoader](#12-关系加载--relationloader-与-eagerloader)
13. [事务管理 — TransactionManager](#13-事务管理--transactionmanager)
14. [数据库迁移 — MigrationManager 与 Schema 构建器](#14-数据库迁移--migrationmanager-与-schema-构建器)
15. [乐观锁](#15-乐观锁)
16. [分页查询](#16-分页查询)
17. [DTO 校验系统](#17-dto-校验系统)
18. [实际项目集成示例](#18-实际项目集成示例)
19. [API 速查表](#19-api-速查表)

---

## 1. 架构总览

photon 的 ORM 体系采用**双层架构**，包装在 V 官方 ORM 之上：

```
┌─────────────────────────────────────────────────────┐
│                   你的业务模块                        │
│  import orm            // V 官方 ORM (QueryBuilder)  │
│  import photon.orm     // photon 生命周期 + 路由层   │
│                                                       │
│  ┌──────────────┐    ┌──────────────────────────┐    │
│  │ orm.QueryBuilder│   │ photon BaseRepository     │    │
│  │ (类型安全 SQL)  │◄──│ (钩子 + 路由 + CRUD)      │    │
│  └──────────────┘    └──────────────────────────┘    │
│         │                        │                   │
│         ▼            ┌─────────────────────────┐     │
│  ┌──────────────┐    │ photon OrmAdapter       │     │
│  │ sqlite/pg    │    │ (生命周期钩子, 自动时间戳)│     │
│  │ /mysql conn  │◄───│ (多数据库路由)           │     │
│  └──────────────┘    └─────────────────────────┘     │
└─────────────────────────────────────────────────────┘
```

**职责划分：**

| 层级 | 提供者 | 职责 |
|------|--------|------|
| 编译时字段校验 | V 官方 `orm` | 结构体字段类型安全 |
| 类型安全查询执行 | V 官方 `orm` | SQL 生成与执行 |
| 自动时间戳管理 | photon `Touchable` | `created_at` / `updated_at` 自动填充 |
| 生命周期钩子 | photon `OrmAdapter` | `before_insert` / `after_find` 等 |
| 多数据库路由 | photon `OrmManager` | 按名称注册与获取连接 |
| Spring Data 派生查询 | photon `derive.v` | 方法名解析为 SQL |
| Repository 模式 | photon `BaseRepository` / `Repository[T]` | 泛型 CRUD |
| 链式查询构建 | photon `QueryBuilder` | WHERE/ORDER/LIMIT/JOIN |
| 事务管理 | photon `TransactionManager` | 传播行为 + 隔离级别 |
| 数据库迁移 | photon `MigrationManager` | 版本化 Schema 迁移 |

**为何分两层？** V 0.5.1 禁止导入同名模块。photon/orm/ 声明为 `module orm`，因此无法 `import orm`（V 官方 ORM）。用户在自己的模块中同时导入两者即可。

```v
import orm            // V 官方 ORM
import photon.orm     // photon ORM 层
```

---

## 2. 连接管理 — OrmManager

`OrmManager` 是多数据库连接注册表，线程安全（内部使用 `sync.RwMutex`）。

### 2.1 创建与注册连接

```v
import db.sqlite
import photon.orm as phorm

// 创建管理器
mut om := phorm.new_orm_manager()

// 注册 SQLite 连接
db := sqlite.connect(':memory:')!
om.register_connection('default', .sqlite, voidptr(db))!

// 注册带自动关闭回调的连接（推荐）
om.register_connection_with_close('default', .sqlite, voidptr(db), fn (c voidptr) ! {
    unsafe { (&sqlite.DB(c)).close()! }
})!
```

**支持的驱动类型：**

```v
pub enum DriverType {
    sqlite
    pg
    mysql
    unknown
}
```

### 2.2 多数据库路由

```v
// 注册多个连接
om.register_connection('default', .pg, voidptr(pg_db))!
om.register_connection('replica', .pg, voidptr(replica_db))!
om.register_connection('analytics', .sqlite, voidptr(analytics_db))!

// 第一个注册的连接自动成为默认
om.set_default('default')!  // 可手动切换默认

// 按名称获取连接
conn := om.get_conn('replica')!

// 驱动类型查询
driver := om.driver('analytics')!  // .sqlite
om.is_sqlite('analytics')  // true
om.is_pg('default')        // true
```

### 2.3 连接生命周期

```v
// 查看所有连接名
names := om.connection_names()  // ['default', 'replica', 'analytics']

// 移除单个连接（若注册了 close_fn 会自动调用）
om.remove_connection('analytics')!

// 关闭所有连接（容器关闭时调用）
om.close_all()!

// destroy 实现 core.DisposableBean 接口（结构化匹配）
om.destroy()!
```

### 2.4 核心 API

| 方法 | 签名 | 说明 |
|------|------|------|
| `new_orm_manager()` | `→ &OrmManager` | 创建空管理器 |
| `register_connection` | `(name, driver, db) !` | 注册连接（无关闭回调） |
| `register_connection_with_close` | `(name, driver, db, close_fn) !` | 注册连接（带关闭回调） |
| `set_default` | `(name) !` | 设置默认连接 |
| `get_conn` | `(name) → voidptr !` | 获取原始连接指针 |
| `default_conn` | `→ voidptr !` | 获取默认连接 |
| `driver` | `(name) → DriverType !` | 获取驱动类型 |
| `has_connection` | `(name) → bool` | 连接是否存在 |
| `connection_names` | `→ []string` | 所有连接名 |
| `remove_connection` | `(name) !` | 移除连接 |
| `close_all` | `!` | 关闭全部 |
| `destroy` | `!` | 同 close_all（DisposableBean） |

---

## 3. 实体定义与注解系统

### 3.1 基础实体 — BaseEntity

```v
import photon.orm as phorm

pub struct BaseEntity {
pub mut:
    id         int @[primary_key; sql: 'id'; sql_type: 'INTEGER']
    created_at i64 @[sql: 'created_at'; sql_type: 'INTEGER']
    updated_at i64 @[sql: 'updated_at'; sql_type: 'INTEGER']
    version    int @[sql: 'version'; sql_type: 'INTEGER']
}
```

嵌入 `BaseEntity` 即可获得：

- `id()` — 返回主键
- `is_new()` — `id == 0` 时为 true（用于 save 路由 INSERT/UPDATE）
- `touch()` — 自动更新时间戳：
  - INSERT 时：`created_at = now`（首次）、`updated_at = now`、`version++`
  - UPDATE 时：`updated_at = now`、`version++`

```v
struct User {
    phorm.BaseEntity       // 带来 id, created_at, updated_at, version
pub mut:
    username string
    email    string
}
```

### 3.2 软删除实体 — SoftDeletableEntity

```v
pub struct SoftDeletableEntity {
    BaseEntity
pub mut:
    deleted_at i64
}

// 方法
// is_deleted() → bool          // deleted_at > 0
// soft_delete()                // deleted_at = now
// restore()                    // deleted_at = 0
```

### 3.3 JPA 注解系统（编译时读取）

photon 通过 V 的 comptime 机制在**编译时**读取结构体注解，零运行时反射开销。

**结构体级注解：**

| 注解 | 说明 | 示例 |
|------|------|------|
| `@[entity]` | 标记为 JPA 实体（标记性） | `@[entity] pub struct User` |
| `@[table('name')]` | 自定义表名 | `@[table('t_user')]` |

默认表名规则：`snake_case(类型名) + 's'`（如 `User` → `users`）。

**字段级注解：**

| 注解 | 说明 | JPA 对应 |
|------|------|----------|
| `@[id]` | 主键字段 | `@Id` |
| `@[primary_key]` | 主键别名（兼容） | `@Id` |
| `@[column('name')]` | 自定义列名 | `@Column` |
| `@[generated_value]` | 自增主键 | `@GeneratedValue` |
| `@[version]` | 乐观锁版本号 | `@Version` |
| `@[created_at]` | 自动填充创建时间 | — |
| `@[updated_at]` | 自动填充更新时间 | — |
| `@[soft_delete]` | 软删除标记字段 | — |
| `@[size(255)]` | 字段长度约束 | `@Size` |
| `@[nullable]` | 允许 NULL | `@Nullable` |
| `@[unique]` | 唯一约束 | — |

默认列名规则：`snake_case(字段名)`。

**完整注解示例：**

```v
@[entity]
@[table('t_user')]
pub struct User {
    @[id]
    @[generated_value]
    id int

    @[column('user_name')]
    @[size(255)]
    username string

    @[required]
    @[email]
    @[unique]
    email string

    @[min(0)]
    @[max(150)]
    age int

    @[version]
    version int

    @[created_at]
    created_at i64

    @[updated_at]
    updated_at i64

    @[soft_delete]
    @[nullable]
    deleted_at i64
}
```

### 3.4 编译时元数据提取

```v
// 提取实体元数据（纯编译时，零运行时成本）
meta := phorm.extract_entity_metadata[User]()
println(meta.table_name)              // 't_user'
println(meta.has_table_annotation)    // true
println(meta.primary_key.column_name) // 'id'
println(meta.columns.len)             // 字段数
println(meta.has_version)             // true
println(meta.has_created_at)          // true
println(meta.has_soft_delete)         // true

// 校验实体是否合法
meta := phorm.scan_entity[User]()!  // 未标注 @[entity] 或 @[table] 时返回错误

// 判断类型是否为实体
is_ent := phorm.is_entity[User]()  // true
```

`EntityMetadata` 结构：

```v
pub struct EntityMetadata {
    table_name           string
    has_table_annotation bool
    columns              []ColumnMetadata
    primary_key          ColumnMetadata
    has_primary_key      bool
    has_version          bool
    has_created_at       bool
    has_updated_at       bool
    has_soft_delete      bool
}
```

### 3.5 生命周期钩子接口

实体可通过实现以下接口获得生命周期回调（全部可选，编译时通过 `$if T is Interface` 检测）：

| 接口 | 方法 | 触发时机 |
|------|------|----------|
| `BeforeCreateHook` | `before_create()` | INSERT 前 |
| `AfterCreateHook` | `after_create()` | INSERT 后 |
| `BeforeUpdateHook` | `before_update()` | UPDATE 前 |
| `AfterUpdateHook` | `after_update()` | UPDATE 后 |
| `BeforeDeleteHook` | `before_delete()` | DELETE 前 |
| `AfterDeleteHook` | `after_delete()` | DELETE 后 |
| `AfterFindHook` | `after_find()` | SELECT 后（每条记录） |

**钩子调用顺序：**

```
INSERT:  BeforeCreate → Touchable.touch → ◄ ORM INSERT ► → AfterCreate
UPDATE:  BeforeUpdate → Touchable.touch → ◄ ORM UPDATE ► → AfterUpdate
DELETE:  BeforeDelete → ◄ ORM DELETE ► → AfterDelete
FIND:    ◄ ORM SELECT ► → AfterFind (每条记录)
```

**实现示例：**

```v
struct Order {
    phorm.BaseEntity
pub mut:
    status string
    total  f64
}

// 实现 BeforeCreateHook
pub fn (mut o Order) before_create() {
    if o.status == '' {
        o.status = 'pending'
    }
}

// 实现 AfterFindHook
pub fn (mut o Order) after_find() {
    // 加载后做格式化或关联数据填充
    o.total = o.total * 1.0  // 示例
}
```

---

## 4. OrmAdapter — 生命周期钩子层

`OrmAdapter[T]` 是最底层的适配器，提供连接路由和生命周期钩子，但不执行 SQL（SQL 由你用 V 官方 ORM 执行）。

### 4.1 创建适配器

```v
import orm            // V 官方 ORM
import photon.orm as phorm

mut om := phorm.new_orm_manager()
db := sqlite.connect(':memory:')!
om.register_connection('default', .sqlite, voidptr(db))!

mut adapter := phorm.new_orm_adapter[User](om, 'default')!
```

### 4.2 手动钩子调用

```v
mut user := User{username: 'Alice'}

// INSERT 前后
adapter.before_insert(mut user)!   // 触发 BeforeCreate + touch()
conn := unsafe { &orm.Connection(adapter.get_conn()!) }
sql db { insert user into User }!  // 你的 V ORM 查询
adapter.after_insert(mut user)!    // 触发 AfterCreate

// UPDATE 前后
adapter.before_update(mut user)!   // 触发 BeforeUpdate + touch()
sql db { update user in User }!
adapter.after_update(mut user)!    // 触发 AfterUpdate

// 查询后
users := sql db { select from User }!
adapter.after_find_all(mut users)!  // 对每条记录触发 AfterFind
```

### 4.3 回调包装器

```v
// wrap_insert: before_insert → 你的回调 → after_insert
adapter.wrap_insert(mut user, fn [mut qb] (mut u User) ! {
    qb.insert(u)!
})!

// wrap_update: before_update → 你的回调 → after_update
adapter.wrap_update(mut user, fn [mut qb] (mut u User) ! {
    qb.update(u)!
})!

// wrap_save: 自动判断 INSERT 还是 UPDATE（基于 is_new()）
adapter.wrap_save(mut user, fn [mut qb] (mut u User) ! {
    qb.insert(u)!
})!

// wrap_delete: before_delete → 你的回调 → after_delete
adapter.wrap_delete(user, fn () ! {
    sql db { delete from User where id == user.id }
})!
```

### 4.4 连接访问

```v
// 获取原始连接指针
conn_ptr := adapter.get_conn()!

// 推荐方式：在回调中安全使用
adapter.with_connection(fn [user] (conn_ptr voidptr) ! {
    conn := unsafe { &orm.Connection(conn_ptr) }
    mut qb := orm.new_query[User](conn)
    qb.insert(user)!
})!
```

---

## 5. BaseRepository — 完整 CRUD 仓储

`BaseRepository[T]` 包装 `OrmAdapter[T]`，通过用户提供的 7 个回调实现完整 CRUD + 生命周期钩子。

### 5.1 创建仓储（推荐 config 方式）

```v
import orm            // V 官方 ORM
import photon.orm as phorm

// 定义回调配置
cfg := phorm.RepositoryConfig[User]{
    exec_find: fn [om] (conn voidptr, id int) !User {
        c := unsafe { &orm.Connection(conn) }
        return sql c {
            select from User where id == id
        }
    },
    exec_find_all: fn [om] (conn voidptr) ![]User {
        c := unsafe { &orm.Connection(conn) }
        return sql c {
            select from User
        }
    },
    exec_insert: fn [om] (conn voidptr, u User) ! {
        c := unsafe { &orm.Connection(conn) }
        sql c { insert u into User }!
    },
    exec_update: fn [om] (conn voidptr, u User) ! {
        c := unsafe { &orm.Connection(conn) }
        sql c { update u in User }!
    },
    exec_delete: fn [om] (conn voidptr, id int) ! {
        c := unsafe { &orm.Connection(conn) }
        sql c { delete from User where id == id }!
    },
    exec_count: fn [om] (conn voidptr) !int {
        c := unsafe { &orm.Connection(conn) }
        return sql c {
            select count from User
        }
    },
    exec_exists: fn [om] (conn voidptr, id int) bool {
        c := unsafe { &orm.Connection(conn) }
        _ := sql c {
            select from User where id == id limit 1
        } or { return false }
        return true
    },
}

// 创建仓储
mut repo := phorm.new_repository_with_config[User](om, 'default', cfg)!
```

### 5.2 CRUD 操作

```v
// save — 自动判断 INSERT/UPDATE（基于 is_new()）
mut user := User{username: 'Alice'}
repo.save(mut user)!           // → INSERT（id==0 → 触发 INSERT 链）
user.email = 'alice@new.com'
repo.save(mut user)!           // → UPDATE（id!=0 → 触发 UPDATE 链）

// update — 强制 UPDATE（拒绝 id==0 的实体）
repo.update(mut user)!

// find_by_id — 查找并触发 AfterFind
user := repo.find_by_id(1)!

// find_all — 查找全部并触发 AfterFind
users := repo.find_all()!

// delete
repo.delete(user)!       // 带钩子
repo.delete_by_id(1)!    // 仅删除

// count / exists
n := repo.count()!
exists := repo.exists_by_id(1)
```

### 5.3 Repository[T] 接口

接口名保留为 `RepositoryInterface[T]`，实现结构体是 `BaseRepository[T]`：

```v
pub interface RepositoryInterface[T] {
    find_by_id(id int) !T
    find_all() ![]T
    save(mut entity T) !T
    update(mut entity T) !T
    delete_by_id(id int) !
    delete(entity T) !
    count() !int
    exists_by_id(id int) bool
}
```

---

## 6. Repository — 编译时推导仓储（推荐）

`Repository[T]` 是**最高级**的仓储，利用 V 的 comptime 在编译时从实体结构体推导 SQL，将 7 个回调简化为 **2 个通用回调**。

### 6.1 创建 Repository

```v
import db.sqlite
import photon.orm as phorm

// 1. 定义执行回调（INSERT/UPDATE/DELETE/DDL）
exec_fn := fn (db voidptr, query string, args []string) ! {
    real := unsafe { &sqlite.DB(db) }
    if args.len == 0 {
        real.exec(query)!
    } else {
        real.exec_param_many(query, args)!
    }
}

// 2. 定义查询回调（SELECT → [][]string）
query_fn := fn (db voidptr, query string, args []string) ![][]string {
    real := unsafe { &sqlite.DB(db) }
    rows := if args.len == 0 {
        real.exec(query)!
    } else {
        real.exec_param_many(query, args)!
    }
    return rows.map(it.vals)
}

// 3. 创建仓储（comptime 推导字段/列名/主键/版本）
mut repo := phorm.new_entity_repository[User](om, 'default', 'users', exec_fn, query_fn)!
```

**主键检测优先级：**
1. 带 `@[id]` 或 `@[primary_key]` 属性的字段
2. 名为 `id` 的字段
3. 都没有则返回错误

**表名解析：**
- 有 `@[table('name')]` 注解 → 使用注解值
- 否则使用传入的 `table_name` 参数

### 6.2 CRUD 操作

```v
// 创建表（comptime 推导列定义）
repo.create_table()!

// save — INSERT（主键为 0 时自动跳过，支持自增）
repo.save(&User{name: 'Alice', email: 'alice@b.com'})!

// save 带显式 ID
repo.save(&User{id: 42, name: 'Bob'})!

// find_by_id
user := repo.find_by_id(1)!

// find_all
users := repo.find_all()!

// delete
repo.delete(1)!

// count
n := repo.count()!  // i64
```

### 6.3 类型安全执行（exec_typed_fn）

默认的 `exec_fn` 接收 `[]string` 参数（丢失原始类型）。配置 `exec_typed_fn` 可保留 `int`/`bool`/`f64` 原始类型：

```v
// ParamValue 是联合类型：bool | f64 | i64 | int | string
typed_fn := fn (db voidptr, query string, args []phorm.ParamValue) ! {
    real := unsafe { &sqlite.DB(db) }
    // 将 ParamValue 转为 string 执行（或按类型分发）
    str_args := args.map(it.str())
    real.exec_param_many(query, str_args)!
}

repo.set_typed_exec_fn(typed_fn)
```

### 6.4 按字段查询

```v
// find_by_field — 按字段值查找（字段名或列名均可）
users := repo.find_by_field('email', 'alice@b.com')!
users := repo.find_by_field('status', 'active')!

// exists_by_field
has := repo.exists_by_field('email', 'alice@b.com')

// count_by_field
n := repo.count_by_field('status', 'active')!
```

### 6.5 原生 SQL 执行

```v
// 位置参数 ? 占位符
users := repo.execute_query(
    'SELECT * FROM users WHERE age > ? ORDER BY age DESC',
    ['18']
)!

// 命名参数 :name 占位符
users := repo.execute_named_query(
    'SELECT * FROM users WHERE age > :age AND name LIKE :name',
    {'age': '18', 'name': 'J%'}
)!
```

### 6.6 DI 集成模式

`Repository` 是泛型，不能直接作为 Photon Bean。通过 `@[component]` 工厂注入 `&OrmManager`：

```v
@[component]
pub struct UserService {
    @[autowired]
    om &phorm.OrmManager
}

fn (s &UserService) repo() !phorm.Repository[User] {
    return phorm.new_entity_repository[User](s.om, 'default', 'users', my_exec_fn, my_query_fn)!
}
```

### 6.7 回调类型定义

```v
// 非查询 SQL 执行（INSERT/UPDATE/DELETE/DDL）
pub type SqlExecFn = fn (db voidptr, query string, args []string) !

// 类型安全的非查询执行
pub type TypedSqlExecFn = fn (db voidptr, query string, args []ParamValue) !

// 查询 SQL 执行（SELECT → [][]string）
pub type SqlQueryFn = fn (db voidptr, query string, args []string) ![][]string

// 影响行数回调（乐观锁必需）
pub type SqlAffectedRowsFn = fn (db voidptr) !int

// 参数值联合类型
pub type ParamValue = bool | f64 | i64 | int | string
```

---

## 7. DerivedRepository — Spring Data 派生查询

`DerivedRepository[T]` 在 `BaseRepository` 基础上增加 Spring Data 风格的方法名解析查询。

### 7.1 创建

```v
import orm
import photon.orm as phorm

// 派生查询回调（接收 QueryParts 和参数列表）
exec_df := fn (conn voidptr, parts phorm.QueryParts, params []voidptr) ![]User {
    c := unsafe { &orm.Connection(conn) }
    mut qb := orm.new_query[User](c)
    if parts.to_where_cond().len > 0 {
        qb.where(parts.to_where_cond(), ...params.map(orm.Primitive(it)))!
    }
    if parts.to_limit() > 0 { qb.limit(parts.to_limit()) }
    if parts.to_order_field().len > 0 {
        qb.order(parts.to_order_field(), parts.to_order_direction())!
    }
    return qb.query()!
}

exec_dc := fn (conn voidptr, parts phorm.QueryParts, params []voidptr) !int {
    c := unsafe { &orm.Connection(conn) }
    mut qb := orm.new_query[User](c)
    qb.where(parts.to_where_cond(), ...params.map(orm.Primitive(it)))!
    return qb.count()!
}

exec_de := fn (conn voidptr, parts phorm.QueryParts, params []voidptr) bool {
    c := unsafe { &orm.Connection(conn) }
    mut qb := orm.new_query[User](c)
    qb.where(parts.to_where_cond(), ...params.map(orm.Primitive(it)))!
    return qb.exists()!
}

exec_dd := fn (conn voidptr, parts phorm.QueryParts, params []voidptr) ! {
    c := unsafe { &orm.Connection(conn) }
    mut qb := orm.new_query[User](c)
    qb.where(parts.to_where_cond(), ...params.map(orm.Primitive(it)))!
    qb.delete()!
}

cfg := phorm.DerivedRepositoryConfig[User]{
    base: phorm.RepositoryConfig[User]{
        // ... 7 个基础回调（同 BaseRepository）
    },
    exec_derived_find:   exec_df,
    exec_derived_count:  exec_dc,
    exec_derived_exists: exec_de,
    exec_derived_delete: exec_dd,
}

mut dr := phorm.new_derived_repository_with_config[User](om, 'default', cfg)!
```

### 7.2 派生查询调用

```v
// find* 方法
users := dr.find('findByNameAndAge',
    orm.Primitive('Alice'), orm.Primitive(30))!

// count* 方法
n := dr.count('countByStatus', orm.Primitive('active'))!

// exists* 方法
has := dr.exists('existsByEmail', orm.Primitive('a@b.com'))!

// delete* 方法
dr.delete_by('deleteByStatus', orm.Primitive('expired'))!

// BaseRepository CRUD 仍然可用
mut u := User{name: 'Bob'}
dr.repo.save(mut u)!
```

---

## 8. QueryBuilder — 链式查询构建器

`QueryBuilder` 是 Laravel Eloquent / Spring JdbcTemplate 风格的链式 SQL 构建器，生成参数化 SELECT 语句。

### 8.1 创建

```v
import photon.orm as phorm

// 需要 OrmManager 和 SQL 执行回调
qb := phorm.new_query_builder(om, 'default', 'users')
qb.set_query_fn(fn (db voidptr, query string, args []string) ![][]string {
    real := unsafe { &sqlite.DB(db) }
    rows := real.exec_param_many(query, args)!
    return rows.map(it.vals)
})
```

### 8.2 链式构建

```v
// WHERE 条件
rows := qb.where_('age > ? and age <= ?', '18', '65')
           .where_('status = ?', 'active')
           .where_in('role', ['admin', 'moderator'])
           .where_not_null('email')
           .where_null('deleted_at')
           .where_between('score', '60', '100')
           .order_by('created_at', .desc)
           .limit(10)
           .offset(20)
           .get()!
```

### 8.3 所有链式方法

| 方法 | 说明 | 示例 |
|------|------|------|
| `select_(cols)` | 设置查询列 | `.select_(['id', 'name'])` |
| `where_(cond, ...args)` | WHERE 条件 | `.where_('age > ?', '18')` |
| `where_in(col, values)` | WHERE IN | `.where_in('status', ['active', 'pending'])` |
| `where_not_null(col)` | IS NOT NULL | `.where_not_null('email')` |
| `where_null(col)` | IS NULL | `.where_null('deleted_at')` |
| `where_between(col, low, high)` | BETWEEN | `.where_between('age', '18', '65')` |
| `order_by(col, dir)` | ORDER BY | `.order_by('name', .asc)` |
| `latest(col)` | ORDER BY DESC | `.latest('created_at')` |
| `oldest(col)` | ORDER BY ASC | `.oldest()` |
| `group_by(...cols)` | GROUP BY | `.group_by('status', 'role')` |
| `having(cond, ...args)` | HAVING | `.having('count > ?', '5')` |
| `join(table, on)` | INNER JOIN | `.join('posts', 'posts.user_id = users.id')` |
| `left_join(table, on)` | LEFT JOIN | `.left_join('profiles', '...')` |
| `right_join(table, on)` | RIGHT JOIN | `.right_join('orders', '...')` |
| `limit(n)` | LIMIT | `.limit(10)` |
| `offset(n)` | OFFSET | `.offset(20)` |
| `page(num, size)` | 分页（1-based） | `.page(2, 10)` → LIMIT 10 OFFSET 10 |
| `when(cond, callback)` | 条件构建 | `.when(active_only, fn (mut q) { q.where_('active', 'true') })` |

### 8.4 终端方法（执行查询）

| 方法 | 返回 | 说明 |
|------|------|------|
| `get()` | `![][]string` | 执行 SELECT，返回所有行 |
| `first()` | `![]string` | LIMIT 1，返回首行（无行报错） |
| `count()` | `!i64` | SELECT COUNT(*) |
| `exists()` | `!bool` | 是否有匹配行 |
| `pluck(col)` | `![]string` | 取单列值列表 |
| `to_sql()` | `(string, []string)` | 调试用：返回 SQL 和参数 |

```v
// 调试 SQL
sql_str, args := qb.where_('id > ?', '10').limit(5).to_sql()
println('SQL: ${sql_str}  ARGS: ${args}')

// first
first_row := qb.where_('status = ?', 'active').first()!

// count
n := qb.where_('status = ?', 'active').count()!

// pluck
names := qb.where_('active', 'true').pluck('name')!
```

### 8.5 生成的 SQL 结构

```sql
SELECT <columns>
FROM <table>
[INNER/LEFT/RIGHT JOIN <table> ON <condition>]
[WHERE <conditions joined by AND>]
[GROUP BY <columns>]
[HAVING <conditions joined by AND>]
[ORDER BY <columns>]
[LIMIT <n>]
[OFFSET <n>]
```

---

## 9. 派生查询方法名解析

`parse_method_name()` 将 Spring Data 风格的方法名解析为 `QueryParts`，可映射到 V 官方 QueryBuilder。

### 9.1 支持的方法名模式

| 方法名 | SQL 等价 |
|--------|----------|
| `findByName` | `WHERE name = ?` |
| `findByNameAndAge` | `WHERE name = ? AND age = ?` |
| `findByNameOrEmail` | `WHERE name = ? OR email = ?` |
| `countByStatus` | `SELECT COUNT(*) WHERE status = ?` |
| `existsByEmail` | `SELECT EXISTS(...) WHERE email = ?` |
| `deleteByStatus` | `DELETE WHERE status = ?` |
| `findTop10ByOrderByCreatedAtDesc` | `ORDER BY created_at DESC LIMIT 10` |
| `findDistinctByName` | `SELECT DISTINCT ... WHERE name = ?` |
| `findByAgeGreaterThan` | `WHERE age > ?` |
| `findByAgeGreaterThanOrEqual` | `WHERE age >= ?` |
| `findByAgeLessThan` | `WHERE age < ?` |
| `findByAgeLessThanOrEqual` | `WHERE age <= ?` |
| `findByNameContaining` | `WHERE name LIKE '%' || ? || '%'` |
| `findByNameStartingWith` | `WHERE name LIKE ? || '%'` |
| `findByNameEndingWith` | `WHERE name LIKE '%' || ?` |
| `findByIdIn` | `WHERE id IN (?)` |
| `findByIdNotIn` | `WHERE id NOT IN (?)` |
| `findByEmailIsNull` | `WHERE email IS NULL` |
| `findByEmailIsNotNull` | `WHERE email IS NOT NULL` |

### 9.2 QueryParts 输出映射

```v
parts := phorm.parse_method_name('findByNameAndAgeOrderByCreatedAtDesc')!

// 映射到 V 官方 QueryBuilder
conn := unsafe { &orm.Connection(om.get_conn('default')!) }
mut qb := orm.new_query[User](conn)

if parts.is_count() {
    return qb.count()
}
if parts.to_limit() > 0 {
    qb.limit(parts.to_limit())
}
qb.where(parts.to_where_cond(), name_param, age_param)!
if parts.to_order_field().len > 0 {
    qb.order(parts.to_order_field(), parts.to_order_direction())!
}

results := qb.query()!
```

### 9.3 QueryParts API

| 方法 | 返回 | 说明 |
|------|------|------|
| `to_where_cond()` | `string` | WHERE 条件字符串 |
| `to_where_cond_with_arrays(map)` | `string` | IN 子句展开占位符 |
| `to_where_param_count()` | `int` | `?` 占位符数量 |
| `to_order_field()` | `string` | 排序字段 |
| `to_order_direction()` | `string` | 'asc' / 'desc' |
| `to_limit()` | `int` | LIMIT 值（0=无限制） |
| `is_count()` | `bool` | 是否为 count 查询 |
| `is_delete()` | `bool` | 是否为 delete 查询 |

### 9.4 支持的关键字

| 关键字 | SQL 操作符 |
|--------|-----------|
| `GreaterThan` | `>` |
| `LessThan` | `<` |
| `GreaterThanOrEqual` | `>=` |
| `LessThanOrEqual` | `<=` |
| `Containing` | `LIKE '%' || ? || '%'` |
| `StartingWith` | `LIKE ? || '%'` |
| `EndingWith` | `LIKE '%' || ?` |
| `In` | `IN (?)` |
| `NotIn` | `NOT IN (?)` |
| `IsNull` | `IS NULL` |
| `IsNotNull` | `IS NOT NULL` |
| `And` | 逻辑 AND |
| `Or` | 逻辑 OR |
| `Top<N>` | LIMIT N |
| `Distinct` | SELECT DISTINCT |
| `OrderBy...Desc/Asc` | ORDER BY |

---

## 10. 原生 SQL 查询与命名参数

### 10.1 @[query] 注解

photon 支持 Spring Data `@Query` 风格的方法注解，在编译时提取 SQL 和命名参数：

```v
struct UserRepo {
    repo phorm.Repository[User]
}

// 方法上的 @[query] 注解
@[query('SELECT * FROM users WHERE age > :age AND name LIKE :name')]
pub fn (r &UserRepo) find_complex(age int, name string) ![]User {
    annotation := phorm.extract_query_annotation[UserRepo]('find_complex') or {
        return error('no @[query] annotation')
    }
    return r.repo.execute_named_query(annotation.sql_text, {
        'age': age.str(),
        'name': name
    })!
}
```

### 10.2 命名参数转换

```v
// :name 参数自动转为 ? 占位符
sql_text, param_names := phorm.convert_named_to_positional(
    'SELECT * FROM users WHERE age > :age AND name = :name'
)
// sql_text == 'SELECT * FROM users WHERE age > ? AND name = ?'
// param_names == ['age', 'name']

// 提取命名参数名
params := phorm.extract_named_params('SELECT * FROM users WHERE age > :age')
// params == ['age']
```

### 10.3 Repository 原生查询

```v
// 位置参数（? 占位符）
users := repo.execute_query(
    'SELECT * FROM users WHERE age > ? ORDER BY age DESC',
    ['18']
)!

// 命名参数（:name 占位符）
users := repo.execute_named_query(
    'SELECT * FROM users WHERE age > :age AND name LIKE :name',
    {'age': '18', 'name': 'J%'}
)!
```

**安全保证：** 所有用户值通过 `?` 位置参数绑定，绝不字符串拼接，防止 SQL 注入。

---

## 11. Specification 模式 — 动态组合查询

Specification 模式（DDD + Spring Data JPA Specification）提供可组合的类型安全查询谓词。

### 11.1 内置 Specification

```v
import photon.orm as phorm

// 比较
phorm.where_eq('status', 'active')         // status = ?
phorm.where_neq('status', 'deleted')       // status != ?
phorm.where_gt('age', '18')                // age > ?
phorm.where_gte('age', '18')               // age >= ?
phorm.where_lt('age', '65')                // age < ?
phorm.where_lte('age', '65')               // age <= ?

// 模糊匹配
phorm.where_like('name', 'Ali%')           // name LIKE ?

// 集合
phorm.where_in('status', ['active', 'pending'])  // status IN (?, ?)

// NULL 检查
phorm.where_null('deleted_at')             // deleted_at IS NULL
phorm.where_not_null('email')              // email IS NOT NULL

// 范围
phorm.where_between('age', '18', '65')     // age BETWEEN ? AND ?
```

### 11.2 组合 Specification

```v
// AND 组合
spec := phorm.spec_and(
    phorm.where_eq('status', 'active'),
    phorm.spec_and(
        phorm.where_gte('age', '18'),
        phorm.where_lte('age', '65')
    )
)

// OR 组合
spec := phorm.spec_or(
    phorm.where_eq('role', 'admin'),
    phorm.where_eq('role', 'moderator')
)

// NOT 取反
spec := phorm.spec_not(phorm.where_eq('status', 'deleted'))
```

### 11.3 执行查询

```v
// 创建执行器（用户提供回调）
executor := phorm.new_specification_executor[User](
    find_fn: fn (criteria phorm.Criteria) ![]User {
        // 将 Criteria 转为 SQL 执行
        where_clause := criteria.to_where_clause()
        params := criteria.params()
        // ... 执行 SQL 并返回实体列表
    },
    count_fn: fn (criteria phorm.Criteria) !int {
        // ... 执行 COUNT 并返回数量
    }
)

// 使用
users := executor.find(spec)!
n := executor.count(spec)!
exists := executor.exists(spec)!
```

### 11.4 Criteria 输出

```v
spec := phorm.spec_and(
    phorm.where_eq('status', 'active'),
    phorm.where_gte('age', '18')
)
criteria := spec.to_criteria()

// 生成 WHERE 子句
where_sql := criteria.to_where_clause()
// → "WHERE status = ? AND age >= ?"

// 提取参数
params := criteria.params()
// → ['active', '18']
```

### 11.5 自定义 Specification

```v
// 实现 Specification 接口
struct ActiveAdultsSpec {}

pub fn (s &ActiveAdultsSpec) to_criteria() phorm.Criteria {
    return phorm.spec_and(
        phorm.where_eq('status', 'active'),
        phorm.spec_and(
            phorm.where_gte('age', '18'),
            phorm.where_lte('age', '65')
        )
    ).to_criteria()
}

// 使用
spec := &ActiveAdultsSpec{}
users := executor.find(spec)!
```

---

## 12. 关系加载 — RelationLoader 与 EagerLoader

### 12.1 关系类型

| 类型 | 结构 | 说明 |
|------|------|------|
| HasMany | `HasMany[T]` | 一对多（User → Posts） |
| BelongsTo | `BelongsTo[T]` | 多对一（Post → User） |
| ManyToMany | `ManyToMany[T]` | 多对多（User ↔ Roles） |
| HasOne | `HasOne[T]` | 一对一 |

```v
// 创建关系占位符
mut posts := phorm.new_has_many[Post]()
mut author := phorm.new_belongs_to[User]()
mut roles := phorm.new_many_to_many[Role]()
mut profile := phorm.new_has_one[Profile]()
```

### 12.2 RelationLoader — 懒加载

```v
import db.sqlite
import photon.orm as phorm

// 创建 RelationLoader（需配置 SQL 回调）
rl := phorm.new_relation_loader_with_fns(om, 'default', exec_fn, query_fn)

// 加载 HasMany（一对多）
mut user := User{id: 1, name: 'Alice'}
mut posts := phorm.new_has_many[Post]()
rl.load_has_many[User, Post](user, mut posts, 'user_id')!
// → SELECT * FROM posts WHERE user_id = ?
// posts.items 现在包含该用户的所有文章

// 加载 BelongsTo（多对一）
mut post := Post{id: 1, user_id: 5, title: 'Hello'}
mut author := phorm.new_belongs_to[User]()
rl.load_belongs_to[Post, User](post, mut author, 'user_id')!
// → SELECT * FROM users WHERE id = ?
// author.item 现在包含文章的作者

// 加载 ManyToMany（多对多）
mut user := User{id: 1}
mut roles := phorm.new_many_to_many[Role]()
rl.load_many_to_many[User, Role](user, mut roles, 'user_roles', 'user_id', 'role_id')!
// → SELECT t.* FROM roles t
//   INNER JOIN user_roles p ON t.id = p.role_id
//   WHERE p.user_id = ?
```

### 12.3 EagerLoader — 批量加载（N+1 预防）

```v
// 批量加载 HasMany（一次查询加载多个父实体的子关系）
el := phorm.new_eager_loader_with_fns[User](om, 'users', 'default', exec_fn, query_fn)

parents := [user1, user2, user3]  // []User
mut relations := map[int]phorm.HasMany[Post]{}

phorm.eager_load_has_many[User, Post](el, parents, mut relations, 'user_id')!
// → SELECT * FROM posts WHERE user_id IN (?, ?, ?)
// 一次查询加载所有用户的文章，按 FK 分组

// 批量加载 BelongsTo
mut belongs := map[int]phorm.BelongsTo[User]{}
phorm.eager_load_belongs_to[Post, User](el, posts, mut belongs, 'user_id')!
// → SELECT * FROM users WHERE id IN (?, ?, ...)
```

### 12.4 安全保证

所有表名和列名在拼入 SQL 前经过 `is_valid_identifier()` 校验（仅允许字母、数字、下划线，首字符为字母或下划线），防止 SQL 注入。外键值通过 `?` 参数绑定。

---

## 13. 事务管理 — TransactionManager

### 13.1 创建事务管理器

```v
import photon.orm as phorm

// 基础创建（无真实连接）
mut tm := phorm.new_transaction_manager()

// 绑定真实数据库连接
tm := phorm.new_transaction_manager_with_conn(
    voidptr(db),     // 连接指针
    begin_fn,        // fn (voidptr) !
    commit_fn,       // fn (voidptr) !
    rollback_fn      // fn (voidptr) !
)
```

### 13.2 基本事务操作

```v
// 手动事务
tm.begin()!
// ... 执行 SQL ...
tm.commit()!
// 或出错时
tm.rollback()!

// 检查事务状态
if tm.is_active() { ... }
```

### 13.3 传播行为

```v
// execute() 方法根据传播行为自动管理事务
tm.execute(.required, fn () ! {
    // 事务体
})!

// .required     — 有事务则加入，无则创建（默认）
// .requires_new — 总是创建新事务（挂起现有）
// .nested       — 在现有事务内使用 savepoint
// .supports     — 有事务则加入，无则非事务运行
// .not_supported — 挂起现有事务，非事务运行
// .mandatory    — 必须有现有事务，否则报错
// .never        — 必须无事务，否则报错
```

**传播行为对照表：**

| 传播行为 | 有现有事务 | 无现有事务 |
|----------|-----------|-----------|
| `.required` | 加入 | 创建 |
| `.requires_new` | 挂起，创建新 | 创建 |
| `.nested` | savepoint | 报错 |
| `.supports` | 加入 | 非事务运行 |
| `.not_supported` | 挂起，非事务运行 | 非事务运行 |
| `.mandatory` | 加入 | 报错 |
| `.never` | 报错 | 非事务运行 |

### 13.4 事务选项

```v
opts := phorm.TransactionOptions{
    isolation:   .read_committed
    readonly:    true
    timeout_ms:  5000
    rollback_for: ['NetworkError']
    no_rollback_for: ['ValidationError']
}
tm.begin_with_options(opts)!

// 隔离级别
pub enum Isolation {
    default_
    read_uncommitted
    read_committed
    repeatable_read
    serializable
}
```

**隔离级别 SQL 生成：**
- SQLite：`PRAGMA read_uncommitted = 1/0`
- PostgreSQL/MySQL：`SET TRANSACTION ISOLATION LEVEL READ COMMITTED` 等

### 13.5 在事务中执行 SQL

```v
// exec_within 检查 readonly 和 timeout
tm.exec_within('INSERT INTO users ...', [])!
// readonly 事务执行写操作会报错
// 超时后自动回滚

// 手动检查超时
tm.check_timeout()!
```

### 13.6 便捷函数

```v
// transactional — REQUIRED 传播的便捷函数
phorm.transactional(fn () ! {
    // 事务体
})!
```

### 13.7 @[transactional] 注解

```v
// @[transactional] 属性在编译时解析
// 支持格式：
//   @[transactional]                           — 默认（REQUIRED）
//   @[transactional: 'readonly']               — 只读
//   @[transactional: 'requires_new']           — REQUIRES_NEW
//   @[transactional: 'nested']                 — NESTED
//   @[transactional: 'propagation:requires_new;isolation:read_committed']
//   @[transactional: 'timeout:5000']
//   @[transactional: 'rollback:NetworkError']

// 解析注解
attr := 'propagation:requires_new;isolation:read_committed'
ta := phorm.parse_transactional_attr(attr)
// ta.propagation == .requires_new
// ta.isolation == .read_committed

// 从方法属性数组解析（comptime 使用）
ta := phorm.parse_transactional_attrs(method.attrs)
```

### 13.8 TransactionalInterceptor

```v
// 创建拦截器
mut ti := phorm.new_transactional_interceptor(tm)

// 手动使用拦截器
started := ti.begin_if_needed(attr)!
// ... 执行业务逻辑 ...
ti.commit_if_needed(started)!
// 或出错时
ti.rollback_if_needed_with_attr(started, err, attr)
```

### 13.9 与生命周期钩子结合

```v
// Pattern A: OrmAdapter 钩子 + V 官方事务
mut conn := unsafe { &orm.Connection(om.get_conn('default')!) }

orm.transaction[void](mut conn, fn [mut adapter] (mut tx orm.Tx) ! {
    mut order := Order{status: 'pending', total: 99.99}

    adapter.before_insert(mut order)!        // auto-touch + hooks
    sql tx { insert order into Order }!
    adapter.after_insert(mut order)!         // post-insert hooks
})!

// Pattern B: TransactionManager.execute + 传播行为
tm.execute(.required, fn [mut conn, mut adapter] () ! {
    mut order := Order{status: 'pending', total: 99.99}
    adapter.before_insert(mut order)!
    sql conn { insert order into Order }!
    adapter.after_insert(mut order)!
})!
```

---

## 14. 数据库迁移 — MigrationManager 与 Schema 构建器

### 14.1 Schema 构建器

```v
import photon.orm as phorm

mut schema := phorm.new_schema(.sqlite)

// 创建表
schema.create_table('users', fn (mut t phorm.TableDef) {
    t.id()                          // id INTEGER PRIMARY KEY AUTOINCREMENT
    t.string_('username', 255)      // VARCHAR(255)
    t.not_null()                    // NOT NULL
    t.string_('email', 255)
    t.string_('password', 255)
    t.integer('age')
    t.boolean_('active')            // BOOLEAN
    t.float_('score')
    t.decimal_('price', 10, 2)      // DECIMAL(10,2)
    t.timestamp_('created_at')
    t.timestamp_('updated_at')
    t.unique_(['email'], 'idx_users_email')
    t.index_(['username'], 'idx_users_username')
})

// 获取生成的 SQL
ddl := schema.to_sql()
// CREATE TABLE IF NOT EXISTS users (
//   id INTEGER PRIMARY KEY AUTOINCREMENT,
//   username VARCHAR(255) NOT NULL,
//   ...
// );
// CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email ON users (email);

// 执行
for stmt in schema.statements {
    db.exec(stmt)!
}
```

### 14.2 TableDef 列构建方法

| 方法 | SQL 类型 | 说明 |
|------|----------|------|
| `id()` | INTEGER PRIMARY KEY | 自增主键 |
| `big_id()` | BIGINT PRIMARY KEY | 大整数自增主键 |
| `string_(name, len)` | VARCHAR(len) | 字符串 |
| `text(name)` | TEXT | 长文本 |
| `integer(name)` | INTEGER | 整数 |
| `bigint(name)` | BIGINT | 大整数 |
| `boolean_(name)` | BOOLEAN | 布尔 |
| `float_(name)` | REAL | 浮点 |
| `double_(name)` | DOUBLE PRECISION | 双精度 |
| `decimal_(name, p, s)` | DECIMAL(p,s) | 定点数 |
| `date_(name)` | DATE | 日期 |
| `time_(name)` | TIME | 时间 |
| `timestamp_(name)` | TIMESTAMP | 时间戳 |
| `datetime_(name)` | DATETIME | 日期时间 |
| `binary_(name)` | BLOB | 二进制 |
| `json_(name)` | JSON/JSONB | JSON |
| `uuid_(name)` | UUID/TEXT | UUID |
| `enum_(name, values)` | TEXT | 枚举 |
| `references(name, ref_table)` | INTEGER REFERENCES | 外键 |

**列修饰方法：**

| 方法 | 说明 |
|------|------|
| `not_null()` | 最后一列设为 NOT NULL |
| `unique_(cols, idx_name)` | 唯一约束/索引 |
| `default_(value)` | 默认值 |
| `timestamps()` | 添加 created_at + updated_at |
| `soft_deletes()` | 添加 deleted_at（nullable） |
| `index_(cols, idx_name)` | 普通索引 |

### 14.3 Schema DDL 操作

```v
// 修改表
schema.alter_table('users', fn (mut t phorm.TableDef) {
    t.add_column(phorm.ColumnDef{name: 'phone', type_: .vstring, length: 20})
    t.drop_column('old_column')
    t.rename_column('name', 'full_name')
})

// 其他 DDL
schema.drop_table('old_table')
schema.drop_table_if_exists('temp')
schema.rename_table('old', 'new')
schema.create_index('users', 'idx_age', ['age'], false)
schema.drop_index('idx_old')
```

### 14.4 Migration 接口

```v
// 实现 Migration 接口
struct CreateUsersTable {
    ver int
}

fn (m CreateUsersTable) version() int { return m.ver }
fn (m CreateUsersTable) name() string { return 'create_users_table' }

fn (m CreateUsersTable) up(mut manager phorm.OrmManager) ! {
    // 使用 Schema 构建器或原生 SQL
    mut schema := phorm.new_schema(.sqlite)
    schema.create_table('users', fn (mut t phorm.TableDef) {
        t.id()
        t.string_('username', 255)
        t.string_('email', 255)
        t.timestamps()
    })
    // 执行 schema.statements...
}

fn (m CreateUsersTable) down(mut manager phorm.OrmManager) ! {
    // 回滚逻辑
    mut schema := phorm.new_schema(.sqlite)
    schema.drop_table('users')
}
```

### 14.5 MigrationManager — 内存模式

```v
om := phorm.new_orm_manager()
mut mm := phorm.new_migration_manager(om)
mm.set_in_memory_mode()  // 测试用

mm.add(&CreateUsersTable{ver: 1})
mm.add(&CreatePostsTable{ver: 2})

mm.initialize()!   // 创建跟踪表
result := mm.migrate()!
// result.applied == 2, result.skipped == 0

mm.status()!       // 打印迁移状态
mm.rollback()!     // 回滚最后一批
mm.reset()!        // 回滚所有
mm.fresh()!        // 重置 + 重新迁移

mm.pending_count()  // 待迁移数
mm.applied_count()  // 已迁移数
```

### 14.6 MigrationManager — SQL 模式（真实数据库）

```v
// 配置 SQL 执行回调
mm := phorm.new_migration_manager_with_fns(om, 'default', exec_fn, query_fn)

// 添加原生 SQL 迁移
mm.add_sql_migration('001', '创建用户表', 
    'CREATE TABLE users (id SERIAL PRIMARY KEY, username VARCHAR(255));',
    'DROP TABLE users;'
)
mm.add_sql_migration('002', '添加邮箱列',
    'ALTER TABLE users ADD COLUMN email VARCHAR(255);',
    'ALTER TABLE users DROP COLUMN email;'
)

mm.initialize()!  // CREATE TABLE IF NOT EXISTS schema_migrations ...
result := mm.migrate()!
// 每个迁移在独立事务中执行：BEGIN → up_sql → INSERT version → COMMIT
```

**SQL 迁移特性：**
- 每个迁移在独立事务中执行
- 失败时自动回滚（ROLLBACK）
- 版本记录在 `_photon_migrations` 表
- 支持跳过已应用的迁移
- 参数化版本记录（防 SQL 注入）

### 14.7 驱动感知的列类型映射

```v
// ColumnType.sql_type(driver) 根据驱动返回不同 SQL 类型
phorm.ColumnType.vstring.sql_type(.pg)     // 'VARCHAR'
phorm.ColumnType.vstring.sql_type(.sqlite) // 'TEXT'
phorm.ColumnType.vbool.sql_type(.sqlite)   // 'INTEGER'
phorm.ColumnType.vbool.sql_type(.pg)       // 'BOOLEAN'
phorm.ColumnType.vjson.sql_type(.pg)       // 'JSONB'
phorm.ColumnType.vjson.sql_type(.sqlite)   // 'TEXT'
phorm.ColumnType.vuuid.sql_type(.pg)       // 'UUID'
phorm.ColumnType.vuuid.sql_type(.sqlite)   // 'TEXT'
```

---

## 15. 乐观锁

实体标记 `@[version]` 字段后，`Repository.update()` 自动启用乐观锁。

### 15.1 定义版本字段

```v
@[entity]
@[table('products')]
pub struct Product {
    @[id]
    id int

    name string

    @[version]
    version int
}
```

### 15.2 配置影响行数回调

```v
mut repo := phorm.new_entity_repository[Product](om, 'default', 'products', exec_fn, query_fn)!

// 乐观锁必需：配置影响行数回调
repo.set_affected_rows_fn(fn (db voidptr) !int {
    return unsafe { &sqlite.DB(db) }.changes()
})
```

### 15.3 自动版本检查

```v
// UPDATE 自动带版本检查
// 生成 SQL: UPDATE products SET name = ?, version = version + 1
//          WHERE id = ? AND version = ?
mut product := repo.find_by_id(1)!
product.name = 'Updated'

result := repo.update(product)!
// 如果影响行数为 0（版本不匹配），抛出 OptimisticLockException

// save() 也自动路由：version != 0 时走 update 路径
repo.save(&product)!  // version != 0 → 调用 update()
```

### 15.4 OptimisticLockException

```v
pub struct OptimisticLockException {
    entity_type string
    id          string
    code        int = 409  // HTTP 409 Conflict
}

// 捕获
match repo.update(product) {
    Product { /* 成功 */ }
    IError(e) {
        if e is phorm.OptimisticLockException {
            println('乐观锁冲突: ${e.entity_type} id=${e.id}')
        }
    }
}
```

---

## 16. 分页查询

### 16.1 Offset 分页（PageResult）

```v
// paginate — 返回 PageResult[T]
result := repo.paginate(1, 10)!  // 第 1 页，每页 10 条
// 执行: SELECT COUNT(*) FROM users
//       SELECT * FROM users LIMIT ? OFFSET ?

for user in result.items {
    println(user.name)
}
println('总数: ${result.total}')         // i64
println('总页数: ${result.total_pages}')  // int
println('有下一页: ${result.has_next()}')
println('有上一页: ${result.has_previous()}')
println('为空: ${result.is_empty()}')
```

### 16.2 带 Sort 的分页（support.Page）

```v
import support

// 构建分页请求（带排序）
pr := support.page_request(2, 10)  // 第 2 页，每页 10 条
pr.sort.orders << support.Order{property: 'created_at', direction: .desc}

page := repo.find_all_paged(pr)!
// page.items      — []T
// page.total      — i64
// page.total_pages — int
// page.page       — int
// page.size       — int
```

### 16.3 Keyset 游标分页（高性能）

```v
// 游标分页 — 避免 COUNT(*) 全表扫描，O(log n) with index
req := phorm.KeysetPageRequest{
    after_value: ''        // 空表示第一页
    sort_field:  'id'      // 排序字段
    sort_dir:    'asc'     // 'asc' 或 'desc'
    limit:       20        // 每页条数
}

items, next_cursor := repo.find_keyset(req)!
// 执行: SELECT * FROM users WHERE id > ? ORDER BY id ASC LIMIT 21
// (取 limit+1 行判断是否有更多)

for user in items {
    println(user.name)
}

if next_cursor != '' {
    // 还有下一页
    req.after_value = next_cursor
    items2, next_cursor2 := repo.find_keyset(req)!
}
```

**Keyset 分页优势：**
- 不需要 `SELECT COUNT(*)`（避免 O(n) 全表扫描）
- 使用 `WHERE id > ? ORDER BY id LIMIT ?`（O(log n) with index）
- 数据插入/删除时分页稳定
- 适合无限滚动 / "加载更多" 模式
- 只能前后导航，不能跳转到任意页

---

## 17. DTO 校验系统

photon 提供编译时 DTO 校验，灵感来自 Jakarta Bean Validation (JSR 380)。

### 17.1 校验注解

| 注解 | 适用类型 | 说明 |
|------|----------|------|
| `@[required]` | string/int/i64/f64 | 非零值 |
| `@[email]` | string | 邮箱格式 |
| `@[min(N)]` | int/i64/f64 | 最小值 |
| `@[max(N)]` | int/i64/f64 | 最大值 |
| `@[pattern('regex')]` | string | 模式匹配（glob 风格） |
| `@[length(M, N)]` | string | 长度范围 |

### 17.2 使用

```v
@[entity]
@[table('users')]
pub struct User {
    @[id]
    id int

    @[required]
    @[length(1, 255)]
    name string

    @[required]
    @[email]
    @[unique]
    email string

    @[min(0)]
    @[max(150)]
    age int
}

// 校验
user := User{name: '', email: 'invalid', age: -1}
result := phorm.validate[User](user)!

if !result.is_valid {
    for err in result.errors {
        println('${err.field}: ${err.message} (rule: ${err.rule})')
    }
}
```

### 17.3 ValidationResult

```v
pub struct ValidationResult {
    is_valid bool
    errors   []ValidationError
}

pub struct ValidationError {
    field   string  // 字段名
    message string  // 错误描述（双语）
    rule    string  // 失败的规则名
}
```

---

## 18. 实际项目集成示例

以 `photon-skeleton` 项目（PostgreSQL）为例，展示完整的集成模式。

### 18.1 数据库初始化

```v
// database/database.v
import db.pg
import photon.orm as phorm

__global (
    g_db          &pg.DB
    g_orm_manager &phorm.OrmManager
)

pub fn init_database(db_path string) !&phorm.OrmManager {
    cfg := parse_pg_conn_string(db_path)
    db := pg.connect(cfg)!

    mut om := phorm.new_orm_manager()
    om.register_connection('default', .pg, voidptr(db))!
    g_orm_manager = om
    return om
}
```

### 18.2 驱动适配层（pg_helper）

```v
// database/pg_helper.v
import db.pg
import strings

// ? 占位符 → PostgreSQL $N 占位符
pub fn convert_placeholders(sql_str string) string {
    mut sb := strings.new_builder(sql_str.len + 16)
    mut n := 1
    mut in_quote := false
    for i, ch in sql_str {
        if ch == `\'` && (i == 0 || sql_str[i-1] != `\\`) {
            in_quote = !in_quote
        } else if ch == `?` && !in_quote {
            sb.write_string('$' + n.str())
            n++
            continue
        }
        sb.write_byte(ch)
    }
    return sb.str()
}

// SqlExecFn 实现
pub fn pg_exec_fn(db voidptr, query string, args []string) ! {
    real := unsafe { &pg.DB(db) }
    converted := convert_placeholders(query)
    if args.len == 0 {
        real.exec(converted)!
    } else {
        real.exec_param_many_result(converted, args)!
    }
}

// SqlQueryFn 实现
pub fn pg_query_fn(db voidptr, query string, args []string) ![][]string {
    real := unsafe { &pg.DB(db) }
    converted := convert_placeholders(query)
    rows := if args.len == 0 {
        real.exec(converted)!
    } else {
        real.exec_param_many(converted, args)!
    }
    return rows.map(it.vals)
}

// 便捷包装
pub fn pg_exec(query string, args []string) ! {
    pg_exec_fn(voidptr(g_db), query, args)!
}

pub fn pg_query(query string, args []string) ![][]string {
    return pg_query_fn(voidptr(g_db), query, args)
}
```

### 18.3 仓储层

```v
// app/repositories/user_repo.v
import database
import app.models
import photon.orm as phorm

pub struct UserRepository {
pub mut:
    om &phorm.OrmManager
}

pub fn new_user_repository(om &phorm.OrmManager) &UserRepository {
    return &UserRepository{om: om}
}

pub fn (repo &UserRepository) find_by_id(id int) !models.User {
    rows := database.pg_query('SELECT * FROM users WHERE id = ?', [id.str()])!
    if rows.len == 0 {
        return error('用户不存在')
    }
    // 映射行到结构体
    return models.User{
        id: rows[0][0].int()
        name: rows[0][1]
        // ...
    }
}

pub fn (repo &UserRepository) save(user models.User) ! {
    database.pg_exec(
        'INSERT INTO users (name, email) VALUES (?, ?)',
        [user.name, user.email]
    )!
}
```

### 18.4 使用 Repository

```v
// 定义实体（int 主键，适合 Repository）
@[entity]
@[table('articles')]
pub struct Article {
    @[id]
    @[generated_value]
    id int

    title string
    body  string

    @[version]
    version int

    @[created_at]
    created_at i64

    @[updated_at]
    updated_at i64
}

// 在服务中使用
pub struct ArticleService {
    om &phorm.OrmManager
}

fn (s &ArticleService) repo() !phorm.Repository[Article] {
    return phorm.new_entity_repository[Article](
        s.om, 'default', 'articles',
        database.pg_exec_fn, database.pg_query_fn
    )!
}

fn (s &ArticleService) create_article(title string, body string) !Article {
    mut repo := s.repo()!
    repo.create_table()!

    repo.save(&Article{title: title, body: body})!
    articles := repo.find_all()!
    return articles[articles.len - 1]
}
```

---

## 19. API 速查表

### OrmManager

| API | 签名 |
|-----|------|
| `new_orm_manager()` | `→ &OrmManager` |
| `register_connection(name, driver, db)` | `!` |
| `register_connection_with_close(name, driver, db, close_fn)` | `!` |
| `set_default(name)` | `!` |
| `get_conn(name)` | `→ voidptr !` |
| `driver(name)` | `→ DriverType !` |
| `has_connection(name)` | `→ bool` |
| `remove_connection(name)` | `!` |
| `close_all()` | `!` |
| `destroy()` | `!` |

### OrmAdapter[T]

| API | 签名 |
|-----|------|
| `new_orm_adapter[T](manager, db_name)` | `→ &OrmAdapter[T] !` |
| `before_insert(mut entity)` | `!` |
| `after_insert(mut entity)` | `!` |
| `before_update(mut entity)` | `!` |
| `after_update(mut entity)` | `!` |
| `before_delete(entity)` | `!` |
| `after_delete(entity)` | `!` |
| `after_find(mut entity)` | `!` |
| `after_find_all(mut entities)` | `!` |
| `wrap_insert(mut entity, callback)` | `!` |
| `wrap_update(mut entity, callback)` | `!` |
| `wrap_save(mut entity, callback)` | `!` |
| `wrap_delete(entity, callback)` | `!` |
| `get_conn()` | `→ voidptr !` |

### BaseRepository[T]

| API | 签名 |
|-----|------|
| `new_repository_with_config[T](manager, db_name, config)` | `→ &BaseRepository[T] !` |
| `find_by_id(id)` | `→ T !` |
| `find_all()` | `→ []T !` |
| `save(mut entity)` | `→ T !` |
| `update(mut entity)` | `→ T !` |
| `delete(entity)` | `!` |
| `delete_by_id(id)` | `!` |
| `count()` | `→ int !` |
| `exists_by_id(id)` | `→ bool` |

### Repository[T]

| API | 签名 |
|-----|------|
| `new_entity_repository[T](manager, db_name, table, exec_fn, query_fn)` | `→ Repository[T] !` |
| `create_table()` | `!` |
| `save(entity)` | `!` |
| `update(entity)` | `→ T !` |
| `find_by_id(id)` | `→ T !` |
| `find_all()` | `→ []T !` |
| `delete(id)` | `!` |
| `count()` | `→ i64 !` |
| `find_by_field(field, value)` | `→ []T !` |
| `exists_by_field(field, value)` | `→ bool` |
| `count_by_field(field, value)` | `→ int !` |
| `paginate(page, size)` | `→ PageResult[T] !` |
| `find_all_paged(page_request)` | `→ support.Page[T] !` |
| `find_keyset(req)` | `→ ([]T, string) !` |
| `execute_query(sql, params)` | `→ []T !` |
| `execute_named_query(sql, named_params)` | `→ []T !` |
| `set_typed_exec_fn(callback)` | — |
| `set_affected_rows_fn(callback)` | — |

### QueryBuilder

| API | 签名 |
|-----|------|
| `new_query_builder(manager, db_name, table)` | `→ &QueryBuilder` |
| `set_query_fn(fn)` | `→ &QueryBuilder` |
| `select_(cols)` | `→ &QueryBuilder` |
| `where_(cond, ...args)` | `→ &QueryBuilder` |
| `where_in(col, values)` | `→ &QueryBuilder` |
| `where_not_null(col)` | `→ &QueryBuilder` |
| `where_null(col)` | `→ &QueryBuilder` |
| `where_between(col, low, high)` | `→ &QueryBuilder` |
| `order_by(col, dir)` | `→ &QueryBuilder` |
| `latest(col)` | `→ &QueryBuilder` |
| `oldest(col)` | `→ &QueryBuilder` |
| `group_by(...cols)` | `→ &QueryBuilder` |
| `having(cond, ...args)` | `→ &QueryBuilder` |
| `join(table, on)` | `→ &QueryBuilder` |
| `left_join(table, on)` | `→ &QueryBuilder` |
| `right_join(table, on)` | `→ &QueryBuilder` |
| `limit(n)` | `→ &QueryBuilder` |
| `offset(n)` | `→ &QueryBuilder` |
| `page(num, size)` | `→ &QueryBuilder` |
| `when(cond, callback)` | `→ &QueryBuilder` |
| `get()` | `→ [][]string !` |
| `first()` | `→ []string !` |
| `count()` | `→ i64 !` |
| `exists()` | `→ bool !` |
| `pluck(col)` | `→ []string !` |
| `to_sql()` | `→ (string, []string)` |

### TransactionManager

| API | 签名 |
|-----|------|
| `new_transaction_manager()` | `→ &TransactionManager` |
| `new_transaction_manager_with_conn(conn, begin, commit, rollback)` | `→ &TransactionManager` |
| `begin()` | `!` |
| `begin_with_options(opts)` | `!` |
| `commit()` | `!` |
| `rollback()` | `!` |
| `is_active()` | `→ bool` |
| `execute(propagation, f)` | `!` |
| `exec_within(sql, params)` | `!` |
| `check_timeout()` | `!` |
| `rollback_if_needed(err, attr)` | `!` |
| `transactional(f)` | `!`（全局函数） |

### MigrationManager

| API | 签名 |
|-----|------|
| `new_migration_manager(manager)` | `→ &MigrationManager` |
| `new_migration_manager_with_fns(manager, db_name, exec_fn, query_fn)` | `→ &MigrationManager` |
| `add(migration)` | — |
| `add_sql_migration(version, desc, up_sql, down_sql)` | — |
| `initialize()` | `!` |
| `migrate()` | `→ MigrationResult !` |
| `rollback()` | `!` |
| `reset()` | `!` |
| `fresh()` | `!` |
| `status()` | `!` |
| `pending_count()` | `→ int` |
| `applied_count()` | `→ int` |
| `get_applied_versions()` | `→ []string !` |

---

## 仓储层级选择指南

| 场景 | 推荐方案 |
|------|----------|
| 单库，无钩子 | V 官方 `orm.new_query[T](db)` |
| 单库，需自动时间戳 | `OrmAdapter` + 手动 QueryBuilder |
| 单库，需完整 CRUD + 钩子 | `Repository[T]`（2 个回调，编译时推导） |
| 多库路由 | `OrmManager` + `Repository[T]` |
| 仅自定义钩子逻辑 | `OrmAdapter` 直接使用 |
| Spring Data 派生查询 | `derive.v` + `DerivedRepository` |
| 动态组合查询 | `Specification` 模式 |
| 关系加载 | `RelationLoader`（懒加载）/ `EagerLoader`（批量） |
| 需要乐观锁 | `Repository[T]` + `@[version]` 字段 |
| 高性能分页 | `Repository[T].find_keyset()`（游标分页） |

---

> **文档版本：** 基于 photon `photon/orm/` 源码生成
> **源码位置：** `/Users/sss/products/webos/photon/orm/`
