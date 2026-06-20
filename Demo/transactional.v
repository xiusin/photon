module main

// transactional.v — 事务支持
//
// 提供 SQLite 原生事务封装，与方法上的 @[transactional] 注解配合使用：
//   - @[transactional] 注解：声明事务意图（文档元数据 + 未来 comptime 自动织入入口）
//   - TransactionGuard：RAII 守卫，实际执行 BEGIN / COMMIT / ROLLBACK
//   - transactional()：函数式 API，适合简单场景
//
// 设计说明：
//   Photon 框架的 orm.TransactionManager 仅维护事务状态标志（active/savepoint_count），
//   不直接驱动底层 DB 的 BEGIN/COMMIT/ROLLBACK。框架的 @[transactional] 注解扫描器
//   尚未通过 comptime 织入。因此本文件提供显式的事务封装，确保多步 DB 操作的原子性。
//
// 用法（RAII 守卫，推荐）：
//   @[transactional]
//   pub fn (mut s PostService) create(dto CreatePostDto) !Post {
//       mut tx := begin_transaction(s.repo.db)!
//       defer { tx.auto_rollback() }
//
//       mut repo := s.repo
//       post = repo.save(mut post)!
//
//       tx.commit()!
//
//       // 事务后的副作用（事件分发、缓存失效）放在 commit 之后
//       s.dispatch_published_event(post)
//       return post
//   }
//
// 用法（函数式，适合无返回值的简单场景）：
//   transactional(db, fn [mut repo] () ! {
//       repo.save(mut entity)!
//   })!

import db.sqlite

// ═══════════════════════════════════════════════════════════
// TransactionGuard — RAII 事务守卫
// ═══════════════════════════════════════════════════════════

// TransactionGuard 封装一个数据库事务的生命周期。
// 通过 begin_transaction() 创建，commit() 提交，rollback() 回滚。
// 配合 defer { tx.auto_rollback() } 确保异常路径自动回滚。
pub struct TransactionGuard {
	db &sqlite.DB
mut:
	committed bool // 是否已提交或回滚（避免重复操作）
}

// begin_transaction 开始一个数据库事务（执行 BEGIN）
// 返回 TransactionGuard 守卫，用于后续 commit/rollback
pub fn begin_transaction(db &sqlite.DB) !&TransactionGuard {
	mut d := unsafe { mut db }
	d.exec('BEGIN')!
	return &TransactionGuard{
		db:        db
		committed: false
	}
}

// commit 提交事务（执行 COMMIT）
// 提交后守卫标记为已完成，后续 auto_rollback 不会再执行 ROLLBACK
pub fn (mut g TransactionGuard) commit() ! {
	if g.committed {
		return // 幂等：已提交/回滚，不再操作
	}
	mut d := unsafe { mut g.db }
	d.exec('COMMIT')!
	g.committed = true
}

// rollback 回滚事务（执行 ROLLBACK）
// 幂等：多次调用安全，已提交的事务不会被回滚
pub fn (mut g TransactionGuard) rollback() {
	if g.committed {
		return // 幂等：已提交/回滚，不再操作
	}
	mut d := unsafe { mut g.db }
	d.exec('ROLLBACK') or {} // 忽略回滚错误（事务可能已自动结束）
	g.committed = true
}

// auto_rollback 自动回滚守卫（专用于 defer 块）
// 若事务已 commit 则不操作；否则执行 ROLLBACK
// 典型用法：defer { tx.auto_rollback() }
pub fn (mut g TransactionGuard) auto_rollback() {
	if g.committed {
		return
	}
	mut d := unsafe { mut g.db }
	d.exec('ROLLBACK') or {}
	g.committed = true
}

// is_committed 返回事务是否已提交或回滚
pub fn (g &TransactionGuard) is_committed() bool {
	return g.committed
}

// ═══════════════════════════════════════════════════════════
// transactional — 函数式事务 API
// ═══════════════════════════════════════════════════════════

// transactional 在数据库事务中执行函数 f
//   - f 成功 → COMMIT
//   - f 失败 → ROLLBACK 并向上传播错误
//   - COMMIT 失败 → ROLLBACK 并向上传播错误
pub fn transactional(db &sqlite.DB, f fn () !) ! {
	mut d := unsafe { mut db }
	d.exec('BEGIN')!

	f() or {
		d.exec('ROLLBACK') or {}
		return err
	}

	d.exec('COMMIT') or {
		d.exec('ROLLBACK') or {}
		return err
	}
}
