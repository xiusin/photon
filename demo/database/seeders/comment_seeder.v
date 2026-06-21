module seeders

// comment_seeder.v — CommentSeeder 评论种子数据
//
// 创建 20 条评论，分布在前 10 篇文章上。
// 幂等性：若 post_id=1 已有评论则跳过。

import bootstrap
import models
import photon.cli
import database.factories

// CommentSeeder 评论种子
pub struct CommentSeeder {
pub:
	bootstrap &bootstrap.Bootstrap
}

// new_comment_seeder 创建评论种子实例
pub fn new_comment_seeder(boot &bootstrap.Bootstrap) &CommentSeeder {
	return &CommentSeeder{
		bootstrap: boot
	}
}

// run 执行评论种子数据填充
pub fn (s &CommentSeeder) run(output &cli.CommandOutput) ! {
	output.section('  Seeding comments')

	// ── 1. 检查是否已有评论 ──
	existing_count := s.bootstrap.comment_svc.count_by_post(1) or { 0 }
	if existing_count > 0 {
		output.writeln('    Comments already seeded, skipping')
		return
	}

	// ── 2. 获取用户与文章列表 ──
	mut user_repo := unsafe { s.bootstrap.user_repo }
	users := user_repo.find_all() or { []models.User{} }
	mut post_repo := unsafe { s.bootstrap.post_repo }
	posts := post_repo.find_all() or { []models.Post{} }
	if users.len == 0 || posts.len == 0 {
		output.warning('    No users or posts found, skipping comment seeding')
		return
	}

	// ── 3. 创建 20 条评论 ──
	mut created_count := 0
	comment_templates := [
		'很好的文章，受益匪浅！',
		'感谢分享，学到了很多。',
		'这个框架的设计理念很棒。',
		'V 语言的编译期特性确实强大。',
		'期待更多关于 Photon Framework 的教程。',
		'文章中的示例代码很清晰。',
		'请问有性能基准测试数据吗？',
		'对比 Laravel 的设计很直观。',
		'事务处理的 RAII 模式很优雅。',
		'缓存标签失效机制设计得很好。',
	]

	for i in 1 .. 21 {
		post := posts[((i - 1) % posts.len)]
		user := users[((i - 1) % users.len)]
		content := comment_templates[(i - 1) % comment_templates.len]

		_ := factories.new_comment_factory(s.bootstrap).
			with_post(post.id).
			with_user(user.id).
			with_content('第 ${i} 条评论: ${content}').
			create() or {
			output.warning('    Failed to create comment ${i}: ${err}')
			continue
		}
		created_count++
	}
	output.success('    Created ${created_count} sample comments')
}
