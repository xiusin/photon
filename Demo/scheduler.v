module main

// scheduler.v — PhotonBlog 定时调度任务
//
// 使用 photon.ticker.Scheduler 实现定时任务调度，注册 3 个周期性任务：
//   1. 每分钟：统计聚合（分发 StatsAggregationJob 到队列异步执行）
//   2. 每小时：缓存预热（失效旧统计缓存，触发下次访问重新聚合）
//   3. 每天 03:00（cron `0 3 * * *`）：清理过期数据（分发 CleanupExpiredTokensJob）
//
// 调度器通过 start_scheduler() 在独立 goroutine 中启动，由 SchedulerRunCommand
// 调用并阻塞主线程保持运行。

import photon.ticker
import photon.cache
import photon.logger
import photon.queue
import json
import time

// new_scheduler 创建并配置调度器，注册 3 个定时任务
// 参数：
//   - stats_svc: 统计服务（用于直接聚合，作为 Job 分发的备选方案）
//   - cache_mgr: 缓存管理器（用于缓存预热与失效）
//   - log: 日志记录器
pub fn new_scheduler(stats_svc &StatsService, cache_mgr &cache.CacheManager, log &logger.Logger) !&ticker.Scheduler {
	mut sched := ticker.new_task_scheduler()

	// ── 1. 每分钟：统计聚合 ──
	// 分发 StatsAggregationJob 到队列，由 Worker 异步消费执行聚合
	mut stats_builder := sched.every(1 * time.minute)
	stats_builder.task(fn [log] () ! {
		log.info('[Scheduler] 触发统计聚合任务 / Running stats aggregation')
		queue.dispatch(StatsAggregationJob{}) or {
			log.error('[Scheduler] 分发 StatsAggregationJob 失败 / Failed to dispatch: ${err}')
		}
	})
	stats_builder.name('stats_aggregation')
	sched.register(stats_builder)

	// ── 2. 每小时：缓存预热 ──
	// 失效旧的统计缓存，下次访问时触发重新聚合；同时预聚合统计数据写入缓存
	mut warmup_builder := sched.every(1 * time.hour)
	warmup_builder.task(fn [stats_svc, cache_mgr, log] () ! {
		log.info('[Scheduler] 触发缓存预热任务 / Running cache warmup')

		// 失效旧统计缓存
		unsafe {
			mut cm := cache_mgr
			cm.delete('stats:blog') or {}
			cm.delete('stats:user_count') or {}
			cm.delete('stats:post_count') or {}
			cm.delete('stats:published_count') or {}
			cm.delete('stats:comment_count') or {}

			// 预聚合统计数据并写入缓存（1 小时 TTL）
			stats := stats_svc.aggregate_stats() or {
				log.error('[Scheduler] 缓存预热聚合失败 / Warmup aggregation failed: ${err}')
				return
			}
			stats_json := json.encode(stats)
			cm.set('stats:blog', stats_json, 3600) or {}

			log.info('[Scheduler] 缓存预热完成 / Cache warmed up — users=${stats.user_count} posts=${stats.post_count} comments=${stats.comment_count}')
		}
	})
	warmup_builder.name('cache_warmup')
	sched.register(warmup_builder)

	// ── 3. 每天 03:00：清理过期数据 ──
	// 分发 CleanupExpiredTokensJob 清理过期的 JWT 黑名单条目
	mut cleanup_builder := sched.cron('0 3 * * *')
	cleanup_builder.task(fn [log] () ! {
		log.info('[Scheduler] 触发每日清理任务 / Running daily cleanup')
		queue.dispatch(CleanupExpiredTokensJob{}) or {
			log.error('[Scheduler] 分发 CleanupExpiredTokensJob 失败 / Failed to dispatch: ${err}')
		}
	})
	cleanup_builder.name('daily_cleanup')
	sched.register(cleanup_builder)

	log.info('[Scheduler] 调度器已配置 / Scheduler configured — ${sched.task_count()} tasks registered')
	return sched
}

// start_scheduler 在独立 goroutine 中启动调度器
// 调度器启动后会每秒检查一次到期任务并执行
pub fn start_scheduler(sched &ticker.Scheduler) {
	unsafe {
		sched.start()
	}
}
