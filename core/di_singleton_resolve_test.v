module core

// di_singleton_resolve_test.v — 深度验证 DI 单例解析 + 缓存预热 + 别名映射 + 字段名自动装配
//
// 验证路径：
//   1. snapshot_singletons() 完整捕获所有实例+别名
//   2. freeze_bean_definitions() 预热后 resolve_cache 完整
//   3. 冻结后 resolve() 无锁快速路径命中（canonical + alias）
//   4. autowire_bean 字段名解析正确匹配注册名
//   5. 多别名场景（register_instance_with_aliases）缓存完整性
//   6. 冻结后 cache_misses 不增长（证明无锁路径命中）

// ── 测试用 Mock 结构体 ──

struct MockRepo {
	id int
}

struct MockLogger {
	level string
}

struct MockService {
pub mut:
	repo  &MockRepo   = unsafe { nil } @[autowired]
	log   &MockLogger = unsafe { nil } @[autowired]
}

// ── 1. snapshot_singletons 完整性 ──

fn test_snapshot_singletons_captures_all_instances() {
	mut c := new_container()
	repo := &MockRepo{id: 1}
	log := &MockLogger{level: 'info'}

	c.register_instance('mock_repo', unsafe { voidptr(repo) }) or { assert false }
	c.register_instance('log', unsafe { voidptr(log) }) or { assert false }

	snapshot := c.snapshot_singletons()
	assert snapshot.len == 2
	assert !isnil(snapshot['mock_repo'])
	assert !isnil(snapshot['log'])
}

fn test_snapshot_singletons_captures_aliases() {
	mut c := new_container()
	repo := &MockRepo{id: 42}

	c.register_instance('mock_repo', unsafe { voidptr(repo) }) or { assert false }
	c.register_alias('MockRepo', 'mock_repo') or { assert false }
	c.register_alias('Repo', 'mock_repo') or { assert false }

	snapshot := c.snapshot_singletons()
	// 1 instance + 2 aliases = 3 entries
	assert snapshot.len == 3
	assert snapshot['mock_repo'] == unsafe { voidptr(repo) }
	assert snapshot['MockRepo'] == unsafe { voidptr(repo) }
	assert snapshot['Repo'] == unsafe { voidptr(repo) }
	// 所有别名应指向同一实例
	assert snapshot['mock_repo'] == snapshot['MockRepo']
	assert snapshot['MockRepo'] == snapshot['Repo']
}

fn test_snapshot_singletons_empty_container() {
	mut c := new_container()
	snapshot := c.snapshot_singletons()
	assert snapshot.len == 0
}

fn test_snapshot_singletons_alias_without_instance_skipped() {
	mut c := new_container()
	// 注册 definition 但不注册 instance
	c.register(new_bean_definition('SomeBean')) or { assert false }
	c.register_alias('SomeAlias', 'SomeBean') or { assert false }

	snapshot := c.snapshot_singletons()
	// 没有 instance，别名不应出现
	assert snapshot.len == 0
}

// ── 2. freeze_bean_definitions 预热 resolve_cache ──

fn test_freeze_prewarms_cache_with_singletons() {
	mut ctx := new_application_context()
	repo := &MockRepo{id: 1}
	log := &MockLogger{level: 'debug'}

	ctx.register_instance('mock_repo', unsafe { voidptr(repo) }) or { assert false }
	ctx.register_instance_with_aliases('log', unsafe { voidptr(log) }, ['Logger']) or { assert false }

	// 冻结前 cache 可能为空或部分填充
	ctx.freeze_bean_definitions()

	// 冻结后 cache 必须包含所有 singleton + alias
	assert ctx.is_frozen_bean_definitions() == true
	cache_size := ctx.cache_size()
	// 至少 3 个条目: mock_repo, log, Logger
	assert cache_size >= 3
}

fn test_freeze_idempotent() {
	mut ctx := new_application_context()
	ctx.register_instance('bean_a', unsafe { voidptr(&MockRepo{id: 1}) }) or { assert false }

	ctx.freeze_bean_definitions()
	size_after_first_freeze := ctx.cache_size()

	ctx.freeze_bean_definitions() // 幂等
	size_after_second_freeze := ctx.cache_size()

	assert size_after_first_freeze == size_after_second_freeze
}

// ── 3. 冻结后 resolve() 无锁快速路径命中 ──

fn test_resolve_after_freeze_hits_cache_canonical() {
	mut ctx := new_application_context()
	repo := &MockRepo{id: 99}

	ctx.register_instance('mock_repo', unsafe { voidptr(repo) }) or { assert false }
	ctx.freeze_bean_definitions()

	misses_before := ctx.cache_miss_count()

	instance := ctx.resolve('mock_repo') or {
		assert false
		return
	}

	misses_after := ctx.cache_miss_count()

	// 冻结后必须命中缓存（miss 不增长）
	assert misses_after == misses_before
	assert instance == unsafe { voidptr(repo) }
}

fn test_resolve_after_freeze_hits_cache_alias() {
	mut ctx := new_application_context()
	repo := &MockRepo{id: 77}

	ctx.register_instance_with_aliases('mock_repo', unsafe { voidptr(repo) }, ['MockRepo', 'Repo']) or { assert false }
	ctx.freeze_bean_definitions()

	misses_before := ctx.cache_miss_count()

	// 通过别名解析
	inst1 := ctx.resolve('MockRepo') or { assert false; return }
	inst2 := ctx.resolve('Repo') or { assert false; return }

	misses_after := ctx.cache_miss_count()

	// 别名也必须命中缓存
	assert misses_after == misses_before
	assert inst1 == unsafe { voidptr(repo) }
	assert inst2 == unsafe { voidptr(repo) }
	assert inst1 == inst2
}

fn test_resolve_after_freeze_cache_miss_grows_for_unknown() {
	mut ctx := new_application_context()
	ctx.register_instance('known', unsafe { voidptr(&MockRepo{id: 1}) }) or { assert false }
	ctx.freeze_bean_definitions()

	misses_before := ctx.cache_miss_count()

	// 解析不存在的 bean — 应走慢速路径（cache miss 增长）
	ctx.resolve('unknown_bean') or {
		misses_after := ctx.cache_miss_count()
		assert misses_after > misses_before
		return
	}
	assert false
}

// ── 4. autowire_bean 字段名解析 ──

fn test_autowire_bean_resolves_by_field_name() {
	mut ctx := new_application_context()
	repo := &MockRepo{id: 10}
	log := &MockLogger{level: 'warn'}

	// 注册名必须与字段名一致
	ctx.register_instance('repo', unsafe { voidptr(repo) }) or { assert false }
	ctx.register_instance('log', unsafe { voidptr(log) }) or { assert false }

	mut svc := MockService{}
	ctx.autowire_bean[MockService](mut svc) or { assert false }

	assert !isnil(svc.repo)
	assert svc.repo.id == 10
	assert !isnil(svc.log)
	assert svc.log.level == 'warn'
}

fn test_autowire_bean_resolves_by_capitalized_field_name() {
	mut ctx := new_application_context()
	repo := &MockRepo{id: 20}

	// 注册名为首字母大写形式
	ctx.register_instance('Repo', unsafe { voidptr(repo) }) or { assert false }

	mut svc := MockService{}
	ctx.autowire_bean[MockService](mut svc) or { assert false }

	// capitalize_first('repo') = 'Repo' — 应命中
	assert !isnil(svc.repo)
	assert svc.repo.id == 20
}

fn test_autowire_bean_field_name_mismatch_leaves_nil() {
	mut ctx := new_application_context()
	repo := &MockRepo{id: 30}

	// 注册名与字段名不匹配
	ctx.register_instance('different_repo', unsafe { voidptr(repo) }) or { assert false }

	mut svc := MockService{}
	ctx.autowire_bean[MockService](mut svc) or {}

	// 字段名 'repo' 不匹配 'different_repo' → 注入 nil
	assert isnil(svc.repo)
}

// ── 5. register_instance_with_aliases 多别名场景 ──

fn test_register_instance_with_aliases_full_resolve() {
	mut ctx := new_application_context()
	repo := &MockRepo{id: 55}

	ctx.register_instance_with_aliases('primary_repo', unsafe { voidptr(repo) }, ['Alias1', 'Alias2', 'Alias3']) or { assert false }
	ctx.freeze_bean_definitions()

	// 所有名称都应解析到同一实例
	inst_primary := ctx.resolve('primary_repo') or { assert false; return }
	inst_a1 := ctx.resolve('Alias1') or { assert false; return }
	inst_a2 := ctx.resolve('Alias2') or { assert false; return }
	inst_a3 := ctx.resolve('Alias3') or { assert false; return }

	assert inst_primary == unsafe { voidptr(repo) }
	assert inst_a1 == inst_primary
	assert inst_a2 == inst_primary
	assert inst_a3 == inst_primary
}

// ── 6. 冻结后多次 resolve 全部命中缓存 ──

fn test_repeated_resolve_after_freeze_all_cache_hits() {
	mut ctx := new_application_context()
	repo := &MockRepo{id: 66}
	ctx.register_instance('mock_repo', unsafe { voidptr(repo) }) or { assert false }
	ctx.freeze_bean_definitions()

	misses_before := ctx.cache_miss_count()

	// 连续解析 100 次
	for i in 0 .. 100 {
		inst := ctx.resolve('mock_repo') or { assert false; return }
		assert inst == unsafe { voidptr(repo) }
	}

	misses_after := ctx.cache_miss_count()
	// 100 次 resolve 不应产生任何 cache miss
	assert misses_after == misses_before
}

// ── 7. freeze + unfreeze + re-freeze 生命周期 ──

fn test_freeze_unfreeze_refreeze_cycle() {
	mut ctx := new_application_context()
	ctx.register_instance('bean_a', unsafe { voidptr(&MockRepo{id: 1}) }) or { assert false }
	ctx.freeze_bean_definitions()
	assert ctx.is_frozen_bean_definitions() == true

	ctx.unfreeze_bean_definitions()
	assert ctx.is_frozen_bean_definitions() == false
	assert ctx.cache_size() == 0 // unfreeze 清空缓存

	// 重新注册并冻结
	ctx.register_instance('bean_b', unsafe { voidptr(&MockRepo{id: 2}) }) or { assert false }
	ctx.freeze_bean_definitions()
	assert ctx.is_frozen_bean_definitions() == true
	assert ctx.cache_size() >= 1
}

// ── 8. 模拟 WebOS 场景：前缀命名冲突验证 ──

struct WebosMockRepo {
	code string
}

struct BlogMockRepo {
	code string
}

struct WebosMockService {
pub mut:
	webos_repo &WebosMockRepo = unsafe { nil } @[autowired]
}

struct BlogMockService {
pub mut:
	repo &BlogMockRepo = unsafe { nil } @[autowired]
}

fn test_field_name_prefix_prevents_cross_injection() {
	mut ctx := new_application_context()
	webos_repo := &WebosMockRepo{code: 'webos'}
	blog_repo := &BlogMockRepo{code: 'blog'}

	// 模拟 bootstrap 注册：两个不同前缀的 repo
	ctx.register_instance('webos_repo', unsafe { voidptr(webos_repo) }) or { assert false }
	ctx.register_instance('repo', unsafe { voidptr(blog_repo) }) or { assert false }

	// WebosMockService 字段名 webos_repo → 应注入 WebosMockRepo
	mut webos_svc := WebosMockService{}
	ctx.autowire_bean[WebosMockService](mut webos_svc) or { assert false }
	assert !isnil(webos_svc.webos_repo)
	assert webos_svc.webos_repo.code == 'webos'

	// BlogMockService 字段名 repo → 应注入 BlogMockRepo
	mut blog_svc := BlogMockService{}
	ctx.autowire_bean[BlogMockService](mut blog_svc) or { assert false }
	assert !isnil(blog_svc.repo)
	assert blog_svc.repo.code == 'blog'
}

// ── 9. freeze 后 resolve 通过 ApplicationContext 层（非直接 Container）──

fn test_resolve_via_application_context_after_freeze() {
	mut ctx := new_application_context()
	repo := &MockRepo{id: 88}
	log := &MockLogger{level: 'error'}

	ctx.register_instance_with_aliases('mock_repo', unsafe { voidptr(repo) }, ['MockRepo']) or { assert false }
	ctx.register_instance_with_aliases('log', unsafe { voidptr(log) }, ['Logger']) or { assert false }

	ctx.freeze_bean_definitions()

	// 通过 ApplicationContext.resolve() 解析（走 cache_mu 路径）
	inst1 := ctx.resolve('mock_repo') or { assert false; return }
	inst2 := ctx.resolve('MockRepo') or { assert false; return }
	inst3 := ctx.resolve('log') or { assert false; return }
	inst4 := ctx.resolve('Logger') or { assert false; return }

	assert inst1 == unsafe { voidptr(repo) }
	assert inst2 == unsafe { voidptr(repo) }
	assert inst3 == unsafe { voidptr(log) }
	assert inst4 == unsafe { voidptr(log) }
	assert inst1 == inst2
	assert inst3 == inst4
}

// ── 10. create_and_register 后 freeze 缓存预热 ──

struct SimpleComponent {
pub mut:
	val int
}

fn test_create_and_register_then_freeze_cache_complete() {
	mut ctx := new_application_context()

	// 注册一个基础设施 bean
	repo := &MockRepo{id: 100}
	ctx.register_instance_with_aliases('repo', unsafe { voidptr(repo) }, ['MockRepo']) or { assert false }

	// create_and_register 会调用 autowire + register_instance_with_aliases
	// SimpleComponent 没有 @[autowired] 字段，所以注入步骤无操作
	ctx.create_and_register[SimpleComponent]('simple_component', 'SimpleComponent') or { assert false }

	// 冻结
	ctx.freeze_bean_definitions()

	// cache 必须包含所有注册的 bean 及其别名
	cache_sz := ctx.cache_size()
	// 至少: repo, MockRepo, simple_component, SimpleComponent = 4
	assert cache_sz >= 4

	// 所有名称都能命中缓存
	misses_before := ctx.cache_miss_count()
	_ = ctx.resolve('repo') or { assert false; return }
	_ = ctx.resolve('MockRepo') or { assert false; return }
	_ = ctx.resolve('simple_component') or { assert false; return }
	_ = ctx.resolve('SimpleComponent') or { assert false; return }
	misses_after := ctx.cache_miss_count()
	assert misses_after == misses_before
}
