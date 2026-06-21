module seeders

// post_seeder.v — PostSeeder 文章种子数据
//
// 创建 3 个分类 + 10 篇文章（使用随机作者）。
// 幂等性：若文章数 >= 10 则跳过。

import bootstrap
import models
import photon.cli
import util
import database.factories

// PostSeeder 文章种子
pub struct PostSeeder {
pub:
	bootstrap &bootstrap.Bootstrap
}

// new_post_seeder 创建文章种子实例
pub fn new_post_seeder(boot &bootstrap.Bootstrap) &PostSeeder {
	return &PostSeeder{
		bootstrap: boot
	}
}

// run 执行文章种子数据填充
pub fn (s &PostSeeder) run(output &cli.CommandOutput) ! {
	output.section('  Seeding posts')

	// ── 1. 确保分类存在 ──
	mut category_svc := unsafe { s.bootstrap.category_svc }
	categories := ['技术', '生活', '随笔']
	for cat_name in categories {
		dto := models.CreateCategoryDto{
			name:        cat_name
			slug:        util.generate_slug(cat_name)
			description: '${cat_name}相关文章'
		}
		_, _ = category_svc.create(dto) or {
			// 分类可能已存在，忽略错误
			continue
		}
	}
	output.success('    Categories ensured (技术/生活/随笔)')

	// ── 2. 检查是否已有足够文章 ──
	mut post_repo_check := unsafe { s.bootstrap.post_repo }
	existing_posts := post_repo_check.find_all() or { []models.Post{} }
	if existing_posts.len >= 10 {
		output.writeln('    Posts already seeded (${existing_posts.len} found), skipping')
		return
	}

	// ── 3. 获取作者列表 ──
	mut user_repo := unsafe { s.bootstrap.user_repo }
	users := user_repo.find_all() or { []models.User{} }
	if users.len == 0 {
		output.warning('    No users found, skipping post seeding')
		return
	}

	// ── 4. 创建 10 篇文章 ──
	mut created_count := 0
	for i in 1 .. 11 {
		// 轮转使用作者（admin 优先）
		author := users[i % users.len]
		category_id := ((i - 1) % 3) + 1
		status := if i <= 7 { 'published' } else { 'draft' }

		_ := factories.new_post_factory(s.bootstrap).
			with_title('文章标题 ${i} - PhotonBlog 示例').
			with_content('这是第 ${i} 篇示例文章的内容。PhotonBlog 是一个基于 Photon Framework 的完整博客系统示例，展示了 V 语言企业级框架的全部功能，包括依赖注入、ORM、缓存、队列、事件驱动等核心特性。').
			with_summary('示例文章 ${i} 的摘要').
			with_author(author.id).
			with_category(category_id).
			with_status(status).
			create() or {
			output.warning('    Failed to create post ${i}: ${err}')
			continue
		}
		created_count++
	}
	output.success('    Created ${created_count} sample posts')
}
