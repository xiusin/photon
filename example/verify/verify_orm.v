module main

// verify_orm.v — 事务、Schema DDL、迁移、实体、仓储 验证

import orm

// VUser 验证用实体，内嵌 BaseEntity（提供 id/touch/is_new 及 @[primary_key] 元数据）
struct VUser {
	orm.BaseEntity
mut:
	name string
}

// 仓储回调使用的内存假存储（-enable-globals）
__global (
	g_repo_users []VUser
)

// VMigration 实现 orm.Migration 接口（version/name/up/down）
struct VMigration {
	ver int
}

fn (m VMigration) version() int {
	return m.ver
}

fn (m VMigration) name() string {
	return 'create_users_v${m.ver}'
}

fn (m VMigration) up(mut manager orm.OrmManager) ! {
	// in-memory 模式下仅记录版本，无需真实 DDL
}

fn (m VMigration) down(mut manager orm.OrmManager) ! {
}

fn verify_orm(mut v Verifier) {
	v.section('ORM — 事务 / Schema / 迁移 / 仓储')

	// ── 1) TransactionManager.execute 事务执行 ──
	mut tm := orm.new_transaction_manager()
	mut tflag := &EventTracker{}
	tm.execute(.required, fn [mut tflag] () ! {
		tflag.record('ran')
	}) or {
		v.check('tx.execute 成功路径', false)
		return
	}
	v.check('tx.execute 执行了事务体', 'ran' in tflag.events)
	v.check('tx 初始非活动', !tm.is_active())

	// 失败路径：错误向上传播
	mut errored := false
	tm.execute(.required, fn () ! {
		return error('rollback please')
	}) or {
		errored = true
	}
	v.check('tx.execute 失败时传播错误', errored)

	// 全局 transactional 助手
	mut gflag := &EventTracker{}
	orm.transactional(fn [mut gflag] () ! {
		gflag.record('ran')
	}) or {}
	v.check('orm.transactional 助手执行', 'ran' in gflag.events)

	// ── 2) Schema 构建器生成 DDL ──
	mut schema := orm.new_schema(.sqlite)
	schema.create_table('users', fn (mut t orm.TableDef) {
		t.id()
		t.string_('username', 255)
		t.not_null()
		t.string_('email', 255)
		t.timestamp_('created_at')
		t.unique_(['email'], 'idx_users_email')
	})
	ddl := schema.to_sql()
	v.check('Schema.to_sql 含 CREATE TABLE', ddl.contains('CREATE TABLE'))
	v.check('Schema.to_sql 含表名 users', ddl.contains('users'))
	v.check('Schema.statements_count > 0', schema.statements_count() > 0)

	// ── 3) MigrationManager 内存模式迁移 ──
	om := orm.new_orm_manager()
	mut mm := orm.new_migration_manager(om)
	mm.set_in_memory_mode()
	mm.add(&VMigration{ver: 1})
	mm.add(&VMigration{ver: 2})
	mm.migrate() or {
		v.check('migration migrate()', false)
		return
	}
	v.check('迁移后 applied_count == 2', mm.applied_count() == 2)
	mm.rollback() or {}
	v.check('rollback 后 applied_count 减少', mm.applied_count() < 2)

	// ── 4) OrmManager 连接注册 ──
	mut om2 := orm.new_orm_manager()
	om2.register_connection('default', .sqlite, voidptr(99)) or {
		v.check('register_connection', false)
		return
	}
	v.check('has_connection(default)', om2.has_connection('default'))
	v.check('driver(default) == sqlite', om2.driver('default') or { orm.DriverType.unknown } == .sqlite)

	// ── 5) BaseRepository[T] 仓储模式（内存假存储验证 find/save/count/delete）──
	g_repo_users = [
		VUser{
			BaseEntity: orm.BaseEntity{
				id: 1
			}
			name:       'alice'
		},
		VUser{
			BaseEntity: orm.BaseEntity{
				id: 2
			}
			name:       'bob'
		},
	]
	cfg := orm.RepositoryConfig[VUser]{
		exec_find:     fn (conn voidptr, id int) !VUser {
			for u in g_repo_users {
				if u.id == id {
					return u
				}
			}
			return error('VUser not found: ${id}')
		}
		exec_find_all: fn (conn voidptr) ![]VUser {
			return g_repo_users
		}
		exec_insert:   fn (conn voidptr, e VUser) ! {
			mut u := e
			u.id = g_repo_users.len + 1
			g_repo_users << u
		}
		exec_update:   fn (conn voidptr, e VUser) ! {
			for i, u in g_repo_users {
				if u.id == e.id {
					g_repo_users[i] = e
				}
			}
		}
		exec_delete:   fn (conn voidptr, id int) ! {
			g_repo_users = g_repo_users.filter(it.id != id)
		}
		exec_count:    fn (conn voidptr) !int {
			return g_repo_users.len
		}
		exec_exists:   fn (conn voidptr, id int) bool {
			for u in g_repo_users {
				if u.id == id {
					return true
				}
			}
			return false
		}
	}
	mut repo := orm.new_repository_with_config[VUser](om2, 'default', cfg) or {
		v.check('new_repository_with_config', false)
		return
	}
	found := repo.find_by_id(1) or { VUser{} }
	v.check('repo.find_by_id', found.name == 'alice')
	all := repo.find_all() or { []VUser{} }
	v.check('repo.find_all 返回全部', all.len == 2)
	v.check('repo.count', (repo.count() or { -1 }) == 2)
	v.check('repo.exists_by_id(1)', repo.exists_by_id(1))
	v.check('repo.exists_by_id(99)=false', !repo.exists_by_id(99))

	mut newu := VUser{
		name: 'carol'
	}
	repo.save(mut newu) or {
		v.check('repo.save(insert)', false)
		return
	}
	v.check('save 后 count == 3', (repo.count() or { -1 }) == 3)

	repo.delete_by_id(1) or {}
	v.check('delete_by_id 后 count == 2', (repo.count() or { -1 }) == 2)
}
