module orm

// ═══════════════════════════════════════════════════════════════════
// photon/orm — The Lifecycle & Routing Layer on Top of V's ORM
// ═══════════════════════════════════════════════════════════════════
//
// ── Two Layers, One Goal ──
//
//   V's official `orm`       Photon's `photon.orm`
//   ─────────────────        ──────────────────────
//   Compile-time field        Lifecycle hooks (before/after
//   validation                  insert, update, delete, find)
//   Type-safe QueryBuilder    Multi-driver connection routing
//   SQL generation & exec     Auto-touch (created_at/updated_at)
//   Migration support         Repository pattern (Spring-style)
//   Relation loading          Derived query method parsing
//                             BaseRepository[T] with pluggable
//                               ORM callbacks
//
// Photon does NOT replace V's ORM — it wraps it.  Together they
// give you:
//
//   • Compile-time field validation        (V's orm)
//   • Type-safe query execution             (V's orm)
//   • Automatic created_at / updated_at     (Photon Touchable)
//   • before_insert / after_find hooks      (Photon OrmAdapter)
//   • Multi-database routing                (Photon OrmManager)
//   • Spring Data-style derived queries     (Photon derive.v)
//   • Repository[T] interface + impl        (Photon BaseRepository)
//
// ── Why the Separation? ──
//
// V 0.5.1 forbids importing a module with the same name.  photon/orm/
// declares `module orm`, so it CANNOT `import orm` (V's standard ORM).
//
// Instead, the user imports BOTH in their own module:
//
//   import orm             // V's standard ORM (QueryBuilder, etc.)
//   import photon.orm      // Photon's lifecycle + routing layer
//
// This cleanly separates responsibilities:
//   — photon/orm provides hooks, routing, and the repository pattern
//   — The user's module wires V's QueryBuilder into photon's callbacks
//
// ── Architecture ──
//
//   ┌─────────────────────────────────────────────────┐
//   │                   Your Module                    │
//   │  import orm                                      │
//   │  import photon.orm                               │
//   │                                                   │
//   │  ┌──────────────┐    ┌────────────────────────┐  │
//   │  │ orm.QueryBuilder  │    │ photon BaseRepository  │  │
//   │  │ (type-safe SQL)   │◄───│ (hooks + routing)      │  │
//   │  └──────────────┘    │    └────────────────────────┘  │
//   │         │            │              │                 │
//   │         ▼            │    ┌─────────────────────┐    │
//   │  ┌──────────────┐    │    │ photon OrmAdapter   │    │
//   │  │ sqlite / pg  │    │    │ (lifecycle hooks,    │    │
//   │  │ / mysql conn │◄───┼────│  auto-touch, routing)│    │
//   │  └──────────────┘    │    └─────────────────────┘    │
//   │                      │              │                 │
//   └──────────────────────┼──────────────┼─────────────────┘
//                          │              │
//   ┌──────────────────────┼──────────────┼─────────────────┐
//   │   photon/orm         │              ▼                  │
//   │   (module orm)       │    ┌─────────────────────┐    │
//   │                      │    │ OrmManager          │    │
//   │                      │    │ ┌─────────────────┐ │    │
//   │                      │    │ │ "default" → conn │ │    │
//   │                      │    │ │ "replica" → conn │ │    │
//   │                      │    │ │ "analytics"→conn │ │    │
//   │                      │    │ └─────────────────┘ │    │
//   │                      │    └─────────────────────┘    │
//   │                      │                               │
//   │  Does NOT import     │  derive.v — parse_method_name()│
//   │  V's `orm`           │  entity.v — Touchable,         │
//   │  (module collision)  │             Identifiable       │
//   └──────────────────────┴───────────────────────────────┘
//
// ── Quick Start ──
//
//   1. Low-level: OrmAdapter (hooks only, you manage QueryBuilder)
//
//      import orm
//      import photon.orm
//
//      mut om := orm.new_orm_manager()
//      om.register_connection('default', .sqlite, db)!
//
//      mut a := orm.new_orm_adapter[User](om, 'default')!
//      a.before_insert(mut user)!   // auto-touch + lifecycle
//      conn := unsafe { &orm.Connection(a.get_conn()!) }
//      sql db { ... }               // your V ORM query
//      a.after_insert(mut user)!
//
//   2. High-level: BaseRepository (full CRUD with hooks)
//
//      import orm
//      import photon.orm
//
//      mut repo := orm.new_repository[User](om, 'default',
//          exec_find: fn (conn voidptr, id int) !User {
//              c := unsafe { &orm.Connection(conn) }
//              return sql c {
//                  select from User where id == id  // col = param
//              }
//          },
//          exec_insert: fn (conn voidptr, u User) ! {
//              c := unsafe { &orm.Connection(conn) }
//              sql c { insert u into User }
//          },
//          // ... exec_find_all, exec_update, exec_delete,
//          //     exec_count, exec_exists
//      )!
//
//      mut u := User{name: 'Alice'}
//      repo.save(mut u)!           // auto-touch + hooks + insert
//      existing := repo.find_by_id(1)!  // hooks + AfterFind
//
//   3. Callback-style: OrmAdapter wrappers (you bring the ORM call)
//
//      a.wrap_save(mut user, fn [db] (mut u User) ! {
//          mut qb := orm.new_query[User](db)
//          qb.insert(mut u)!
//      })!    // auto-detects new vs existing via Identifiable
//
// ── Transactions with Lifecycle Hooks ──
//
// Photon's hooks and V's transaction API work together seamlessly.
// Because BaseRepository and OrmAdapter access connections by name
// from the OrmManager, you control which connection (raw or tx)
// gets used.  Call adapter hooks directly inside the transaction
// block so auto-touch and lifecycle callbacks fire atomically.
//
//   Pattern A: OrmAdapter hooks inside V's orm.transaction()
//   ─────────────────────────────────────────────────────────
//   Use when you need full control and V's native tx API.
//
//      import orm
//      import photon.orm
//
//      mut om := orm.new_orm_manager()
//      om.register_connection('default', .sqlite, db)!
//      mut a := orm.new_orm_adapter[Order](om, 'default')!
//
//      // Get a transactional connection
//      mut conn := unsafe { &orm.Connection(om.get_conn('default')!) }
//
//      orm.transaction[void](mut conn, fn [mut a] (mut tx orm.Tx) ! {
//          mut order := Order{status: 'pending', total: 99.99}
//
//          a.before_insert(mut order)!        // auto-touch + hooks
//          sql tx { insert order into Order }!
//          a.after_insert(mut order)!         // post-insert hooks
//
//          // If any step fails, the SQL INSERT rolls back.
//          // Note: hook side effects (field mutations, external
//          // calls) are NOT transactional — only the DB is atomic.
//      })!
//
//   Pattern B: Photon's TransactionManager.execute()
//   ─────────────────────────────────────────────────
//   Use when you want Spring-style propagation (REQUIRED,
//   REQUIRES_NEW, NESTED, etc.) on top of V's ORM transactions.
//
//      mut tm := orm.new_transaction_manager()
//
//      // conn, a from Pattern A above.
//      // .required creates a new tx, commits on success,
//      // rolls back on error.  The outermost caller owns
//      // the tx — nested .required calls join silently.
//      tm.execute(.required, fn [mut conn, a] () ! {
//          mut order := Order{status: 'pending', total: 99.99}
//
//          a.before_insert(mut order)!
//          sql conn { insert order into Order }!
//          a.after_insert(mut order)!
//      })!
//
//      // Nested .required joins the existing tx (conn, a from above):
//      tm.execute(.required, fn [mut conn, a] () ! {
//          // Outer tx is already active — this just runs f()
//          // without begin/commit/rollback.
//      })!
//
//      // .requires_new suspends the outer tx, creates a new one (conn, a from above):
//      tm.execute(.requires_new, fn [mut conn, a] () ! {
//          // Runs in its own independent tx.
//      })!
//
//      // .nested uses a savepoint within the active tx:
//      tm.execute(.nested, fn () ! {
//          // If this fails, only the savepoint rolls back.
//      })!
//
//   ── Propagation Behavior ──
//
//     Propagation   Existing TX?  Behavior
//     ───────────   ────────────  ────────────────────────────
//     .required     yes           join (skip begin/commit)
//     .required     no            create tx → commit or rollback
//     .requires_new yes           suspend, create new tx
//     .requires_new no            create tx
//     .nested       yes           savepoint (rollback on error)
//     .nested       no            error
//     .supports     yes           join
//     .supports     no            run without tx
//     .not_supported yes          suspend, run without tx
//     .not_supported no           run without tx
//     .mandatory    yes           join
//     .mandatory    no            error
//     .never        yes           error
//     .never        no            run without tx
//
//   Pattern C: transactional() convenience (single-shot)
//   ──────────────────────────────────────────────────────
//
//      mut conn := unsafe { &orm.Connection(om.get_conn('default')!) }
//
//      orm.transactional(fn [mut conn, mut a] () ! {
//          mut order := Order{status: 'pending', total: 99.99}
//          a.before_insert(mut order)!
//          sql conn { insert order into Order }!
//          a.after_insert(mut order)!
//      })!
//
//   Pattern D: Multi-entity transactional save with BaseRepository
//   ──────────────────────────────────────────────────────────────
//   Creates an order + debits inventory atomically using hooks
//   inside a transaction.  Each repo's callbacks use the active
//   transaction connection.
//
//      // Build tx-aware repos by injecting the tx connection
//      mut tx_conn := unsafe { &orm.Connection(om.get_conn('default')!) }
//
//      mut order_repo := orm.new_repository[Order](om, 'default',
//          // ── Callbacks capture tx_conn (the transaction connection)
//          // ── and ignore the conn voidptr so all SQL runs inside the tx.
//          exec_insert: fn [tx_conn] (conn voidptr, o Order) ! {
//              sql tx_conn { insert o into Order }!
//          },
//          exec_update: fn [tx_conn] (conn voidptr, o Order) ! {
//              sql tx_conn { update o in Order }!
//          },
//          // ...
//      )!
//
//      orm.transaction[void](mut tx_conn, fn [mut order_repo, mut inv_repo] (
//          mut tx orm.Tx
//      ) ! {
//          mut order := Order{status: 'placed', total: 49.97}
//          order_repo.save(mut order)!   // auto-touch + hooks + insert
//
//          // Debit inventory inside the same tx
//          mut item := inv_repo.find_by_id(order.item_id)!
//          item.quantity -= 1
//          inv_repo.update(mut item)!    // hooks + update
//      })!
//
// ── Lifecycle Hook Call Order ──
//
// Every CRUD operation follows a strict before→ORM→after sequence.
// The OrmAdapter and BaseRepository use identical ordering.  The
// difference is only who runs the ORM step: you (OrmAdapter) or
// the callbacks (BaseRepository).
//
//   ╔══════════════════════════════════════════════════════════╗
//   ║  INSERT (new entity — save() or wrap_insert)            ║
//   ╠══════════════════════════════════════════════════════════╣
//   ║  1. BeforeCreateHook.before_create()    (if implemented) ║
//   ║  2. Touchable.touch()                   (if implemented) ║
//   ║     └─ created_at = now  (first time only)               ║
//   ║     └─ updated_at = now                                 ║
//   ║     └─ version++                                        ║
//   ║  3. ◄ ORM INSERT (your callback) ►                      ║
//   ║  4. AfterCreateHook.after_create()     (if implemented) ║
//   ╚══════════════════════════════════════════════════════════╝
//
//   ╔══════════════════════════════════════════════════════════╗
//   ║  UPDATE (existing entity — save() or wrap_update)       ║
//   ╠══════════════════════════════════════════════════════════╣
//   ║  0. Identifiable check: rejects new (id==0) entities    ║
//   ║     (BaseRepository.update() only — returns error)      ║
//   ║  1. BeforeUpdateHook.before_update()    (if implemented) ║
//   ║  2. Touchable.touch()                   (if implemented) ║
//   ║     └─ updated_at = now                                 ║
//   ║     └─ version++                                        ║
//   ║  3. ◄ ORM UPDATE (your callback) ►                      ║
//   ║  4. AfterUpdateHook.after_update()     (if implemented) ║
//   ╚══════════════════════════════════════════════════════════╝
//
//   ╔══════════════════════════════════════════════════════════╗
//   ║  DELETE — delete() or wrap_delete                       ║
//   ╠══════════════════════════════════════════════════════════╣
//   ║  0. Identifiable check: entity must have id()           ║
//   ║     (BaseRepository.delete() only — error if missing)   ║
//   ║  1. BeforeDeleteHook.before_delete()    (if implemented) ║
//   ║  2. ◄ ORM DELETE (your callback) ►                      ║
//   ║  3. AfterDeleteHook.after_delete()     (if implemented) ║
//   ╚══════════════════════════════════════════════════════════╝
//
//   ╔══════════════════════════════════════════════════════════╗
//   ║  FIND — find_by_id() / find_all() / after_find_all()    ║
//   ╠══════════════════════════════════════════════════════════╣
//   ║  1. ◄ ORM SELECT (your callback) ►                      ║
//   ║  2. AfterFindHook.after_find()         (if implemented) ║
//   ║     Called on every entity in the result set.            ║
//   ╚══════════════════════════════════════════════════════════╝
//
// ── Auto-Touch (Touchable interface) ──
//
// BaseEntity implements Touchable.  Structs embedding BaseEntity
// get automatic timestamp management without any extra code:
//
//   struct User {
//       orm.BaseEntity           // ← brings id, created_at,
//       name string                  //   updated_at, version,
//   }                                //   touch(), id(), is_new()
//
//   touch() is called automatically by before_insert and
//   before_update.  What it sets:
//
//     Field        On INSERT           On UPDATE
//     ─────        ──────────          ──────────
//     created_at   set to now          (unchanged)
//     updated_at   set to now          set to now
//     version      ++ (starts at 1)    ++
//
// ── New vs Existing Detection (Identifiable interface) ──
//
// BaseEntity also implements Identifiable (id() + is_new()).
// wrap_save() and BaseRepository.save() use this to choose the
// correct hook chain automatically:
//
//   entity.id == 0  →  wrap_save routes to INSERT chain
//   entity.id != 0  →  wrap_save routes to UPDATE chain
//
// Both wrap_save() and BaseRepository.save() use the same logic.
// wrap_update() and BaseRepository.update() skip this check —
// they always run the UPDATE chain and reject new entities.
//
// ── Notes ──
//
//   • delete does NOT call touch() — version is not bumped.
//   • before_delete/after_delete receive the entity by value
//     (immutable snapshot).  Use BeforeDeleteHook to read entity
//     state before deletion; modifications won't persist.
//   • All hooks are optional — $if T is Interface means they
//     compile to no-ops when the interface isn't implemented.
//
// ── Derived Query Integration (parse_method_name + BaseRepository) ──
//
//   parse_method_name() parses Spring Data-style method names into
//   QueryParts that map directly to V's QueryBuilder.  Pair it with
//   BaseRepository callbacks for zero-boilerplate finders.
//
//   ── Supported Method Name Patterns ──
//
//     Method Name                         → SQL Equivalent
//     ───────────                         → ──────────────
//     findByName                          → WHERE name = ?
//     findByNameAndAge                    → WHERE name = ? AND age = ?
//     findByNameOrEmail                   → WHERE name = ? OR email = ?
//     countByStatus                       → SELECT COUNT(*) WHERE status = ?
//     existsByEmail                       → SELECT EXISTS(...) WHERE email = ?
//     deleteByStatus                      → DELETE WHERE status = ?
//     findTop10ByOrderByCreatedAtDesc     → ORDER BY created_at DESC LIMIT 10
//     findDistinctByName                  → SELECT DISTINCT ... WHERE name = ?
//
//   ── Pattern 1: Manual Integration ──
//
//     Parse the method name, build a QueryBuilder, and map each
//     QueryParts output to the corresponding ORM call:
//
//       parts := orm.parse_method_name('findByNameAndAge')!
//
//       conn := unsafe { &orm.Connection(om.get_conn('default')!) }
//       mut qb := orm.new_query[User](conn)   // V's official ORM
//
//       if parts.is_count() {
//           return qb.count()                      // countBy* methods
//       }
//       if parts.to_limit() > 0 { qb.limit(parts.to_limit()) }
//       qb.where(parts.to_where_cond(), name_param, age_param)!
//       if parts.to_order_field().len > 0 {
//           qb.order(parts.to_order_field(),
//               parts.to_order_direction())!   // (field, direction)
//       }
//
//       mut results := qb.query()!
//       // Apply AfterFind hooks if you have an adapter:
//       // a.after_find_all(mut results)!
//       return results
//
//     Note: qb.order() in V's ORM takes (field, direction) — keep
//     QueryParts output in that order to avoid swapped arguments.
//
//   ── Pattern 2: BaseRepository Wrapper ──
//
//     Wrap the parse_map_exec pattern in a helper on BaseRepository
//     for reusable Spring-style finders:
//
//       // User-land helper (your module, not photon/orm):
//       fn find_by[T](mut repo BaseRepository[T], method string, params ...orm.Primitive) ![]T {
//           // Only handles find* methods.  For count*/delete*,
//           // use count_by/delete_by helpers (same pattern, different return types).
//           parts := orm.parse_method_name(method)!
//           assert parts.to_where_param_count() == params.len
//
//           conn := unsafe { &orm.Connection(repo.adapter.get_conn()!) }
//           mut qb := orm.new_query[T](conn)
//
//           if parts.to_limit() > 0 { qb.limit(parts.to_limit()) }
//           if parts.to_where_cond().len > 0 {
//               qb.where(parts.to_where_cond(), ...params)!
//           }
//           if parts.to_order_field().len > 0 {
//               qb.order(parts.to_order_field(),         // (field, dir)
//                   parts.to_order_direction())!
//           }
//
//           mut results := qb.query()!
//           repo.adapter.after_find_all(mut results)!
//           return results
//       }
//
//       // Usage:
//       users := find_by[User](mut repo, 'findByNameAndAge',
//           orm.Primitive('Alice'), orm.Primitive(30))!
//
//   ── Pattern 3: DerivedRepository (built into photon/orm) ──
//
//     DerivedRepository wraps BaseRepository + parse_method_name()
//     with user-provided OrmExecDerived* callbacks.  Each callback
//     receives (conn, QueryParts, params []voidptr) — cast params
//     to orm.Primitive inside your callback.
//
//       import orm
//       import photon.orm
//
//       // Implement the four derived-query callbacks:
//       exec_df := fn (conn voidptr, parts QueryParts, params []voidptr) ![]User {
//           c := unsafe { &orm.Connection(conn) }
//           mut qb := orm.new_query[User](c)
//           if parts.to_where_cond().len > 0 {
//               qb.where(parts.to_where_cond(),
//                   ...params.map(orm.Primitive(it)))!
//           }
//           if parts.to_limit() > 0 { qb.limit(parts.to_limit()) }
//           if parts.to_order_field().len > 0 {
//               qb.order(parts.to_order_field(),
//                   parts.to_order_direction())!
//           }
//           return qb.query()!
//       }
//
//       exec_dc := fn (conn voidptr, parts QueryParts, params []voidptr) !int {
//           c := unsafe { &orm.Connection(conn) }
//           mut qb := orm.new_query[User](c)
//           qb.where(parts.to_where_cond(),
//               ...params.map(orm.Primitive(it)))!
//           return qb.count()!
//       }
//
//       exec_de := fn (conn voidptr, parts QueryParts, params []voidptr) bool {
//           c := unsafe { &orm.Connection(conn) }
//           mut qb := orm.new_query[User](c)
//           qb.where(parts.to_where_cond(),
//               ...params.map(orm.Primitive(it)))!
//           return qb.exists()!
//       }
//
//       exec_dd := fn (conn voidptr, parts QueryParts, params []voidptr) ! {
//           c := unsafe { &orm.Connection(conn) }
//           mut qb := orm.new_query[User](c)
//           qb.where(parts.to_where_cond(),
//               ...params.map(orm.Primitive(it)))!
//           qb.delete()!
//       }
//
//       mut dr := orm.new_derived_repository[User](om, 'default',
//           exec_find, exec_find_all, exec_insert, exec_update,
//           exec_delete, exec_count, exec_exists,
//           exec_df, exec_dc, exec_de, exec_dd)!
//
//       // Spring Data-style queries with automatic lifecycle hooks:
//       users := dr.find('findByNameAndAge',
//           orm.Primitive('Alice'), orm.Primitive(30))!
//       n     := dr.count('countByStatus', orm.Primitive('active'))!
//       has   := dr.exists('existsByEmail', orm.Primitive('a@b.com'))!
//       dr.delete_by('deleteByStatus', orm.Primitive('expired'))!
//
//       // BaseRepository CRUD still accessible via dr.repo:
//       mut u := User{name: 'Bob'}
//       dr.repo.save(mut u)!  // hooks + insert
//
//   ── QueryParts Output Reference ──
//
//     After parse_method_name(), map QueryParts to QueryBuilder:
//
//       QueryParts field           → QueryBuilder call
//       ─────────────────          → ─────────────────
//       .to_where_cond()           → qb.where(cond, ...params)
//       .to_where_param_count()    → validate params.len == ? count
//       .to_order_field()          → qb.order(field, direction)
//       .to_order_direction()      → qb.order(field, direction)
//       .to_limit()                → qb.limit(n)
//       .is_count()                → call qb.count() instead of query()
//       .is_delete()               → call qb.delete() instead of query()
//       .operation                 → .find→query, .count→count,
//                                   .exists→exists, .delete_all→delete
//
// ── When to Use What ──
//
//   Single database, no hooks       → V's orm.new_query[User](db)
//   Single db, want auto-touch      → OrmAdapter + manual QueryBuilder
//   Single db, want full repository → BaseRepository with callbacks
//   Multiple databases              → OrmManager + BaseRepository
//     per connection
//   Custom hook logic only          → OrmAdapter directly
//   Spring-style derived queries    → derive.v + BaseRepository

// ── Driver metadata ──

// DriverType identifies the database backend.
pub enum DriverType {
	sqlite
	pg
	mysql
	unknown
}

// driver_name returns a human-readable driver name.
pub fn (d DriverType) str() string {
	return match d {
		.sqlite { 'sqlite' }
		.pg { 'postgresql' }
		.mysql { 'mysql' }
		.unknown { 'unknown' }
	}
}

// ── OrmConnection ──

// OrmConnection wraps a database connection with driver metadata.
// The `db` field holds the actual driver connection (sqlite.DB,
// pg.DB, mysql.DB, etc.) — it is typed as voidptr because
// photon/orm cannot import V's `orm.Connection` interface (module
// name collision).  The adapter sub-module retrieves and casts it.
pub struct OrmConnection {
pub:
	db     voidptr
	driver DriverType
}

// ── OrmManager ──

// OrmManager manages multiple database connections across drivers.
//
// Think of it as a connection registry — it stores database
// connections and routes queries to the right one.  It does NOT
// build SQL or execute queries directly; that's delegated to
// the OrmAdapter and V's official orm.QueryBuilder[T].
@[heap]
pub struct OrmManager {
pub mut:
	connections map[string]OrmConnection
	default     string
}

// new_orm_manager creates an empty OrmManager.
//
// Use register_connection() to add database connections, then
// use the adapter sub-module for type-safe queries.
pub fn new_orm_manager() &OrmManager {
	return &OrmManager{
		connections: map[string]OrmConnection{}
	}
}

// register_connection registers a database connection under a name.
//
// Example:
//   db := sqlite.connect(':memory:')!
//   om.register_connection('default', .sqlite, db)!
//
// If no default is set yet, the first registered connection
// becomes the default.
pub fn (mut om OrmManager) register_connection(name string, driver DriverType, db voidptr) ! {
	if name in om.connections {
		return error('connection "${name}" already registered')
	}
	om.connections[name] = OrmConnection{
		db:     db
		driver: driver
	}
	if om.default.len == 0 {
		om.default = name
	}
}

// set_default changes the default connection name.
pub fn (mut om OrmManager) set_default(name string) ! {
	if name !in om.connections {
		return error('connection "${name}" not registered')
	}
	om.default = name
}

// connection returns the OrmConnection by name (or default).
pub fn (om &OrmManager) connection(name string) !OrmConnection {
	db_name := if name.len > 0 { name } else { om.default }
	if db_name.len == 0 {
		return error('no default connection set')
	}
	return om.connections[db_name] or { return error('connection "${db_name}" not registered') }
}

// get_conn returns the raw connection pointer by name (or default).
pub fn (om &OrmManager) get_conn(name string) !voidptr {
	conn := om.connection(name)!
	return conn.db
}

// default_conn returns the default connection pointer.
pub fn (om &OrmManager) default_conn() !voidptr {
	return om.get_conn('')
}

// driver returns the DriverType for a connection.
pub fn (om &OrmManager) driver(name string) !DriverType {
	conn := om.connection(name)!
	return conn.driver
}

// has_connection checks if a named connection exists.
pub fn (om &OrmManager) has_connection(name string) bool {
	return name in om.connections
}

// connection_names returns all registered connection names.
pub fn (om &OrmManager) connection_names() []string {
	return om.connections.keys()
}

// remove_connection removes a connection by name.
pub fn (mut om OrmManager) remove_connection(name string) ! {
	if name !in om.connections {
		return error('connection "${name}" not registered')
	}
	om.connections.delete(name)
	if om.default == name {
		om.default = ''
		// Pick first remaining as default
		for key, _ in om.connections {
			om.default = key
			break
		}
	}
}

// ── Convenience: multi-driver connection helpers ──

// is_sqlite returns true if the named connection is SQLite.
pub fn (om &OrmManager) is_sqlite(name string) bool {
	d := om.driver(name) or { return false }
	return d == .sqlite
}

// is_pg returns true if the named connection is PostgreSQL.
pub fn (om &OrmManager) is_pg(name string) bool {
	d := om.driver(name) or { return false }
	return d == .pg
}

// is_mysql returns true if the named connection is MySQL.
pub fn (om &OrmManager) is_mysql(name string) bool {
	d := om.driver(name) or { return false }
	return d == .mysql
}
