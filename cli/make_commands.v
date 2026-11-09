module cli

// make_commands.v - Code Generation Commands (Laravel artisan make: inspired)
//
// Provides stub generators for quickly scaffolding Photon components:
//   make:command      - generate a CLI command
//   make:controller   - generate a web controller
//   make:middleware   - generate a middleware
//   make:provider     - generate a service provider
//   make:entity       - generate an ORM entity
//   make:model        - generate a model (entity + repository stub)
//   make:migration    - generate a database migration
//
// 每个 stub 都必须能真的编译通过 —— 「生成了一个文件」不等于「生成了一份
// 能用的代码」。早先有 6 类 stub 一共 48 个文件编不过（mut output 缺失、
// TableBuilder 不存在、跨包类型写错、返回栈上引用……），而它们全都排在
// 一个从未被用例驱动过、也从没对生成结果做编译验证的路径上。
import os
import photon.strutil
import time

// MakeCommandCommand generates a new CLI command file
pub struct MakeCommandCommand {
	BaseCommand
}

pub fn new_make_command_command() &MakeCommandCommand {
	return &MakeCommandCommand{
		BaseCommand: BaseCommand{
			name:        'make:command'
			description: 'Generate a new CLI command class'
			sig:         '<name>'
		}
	}
}

pub fn (c &MakeCommandCommand) execute(input &CommandInput, mut output &CommandOutput) ! {
	name := input.get_arg(0)
	if name.len == 0 {
		return error('command name is required. Usage: make:command <Name>')
	}

	stub := generate_command_stub(name)
	write_stub(name, 'commands', stub, mut output)!
	return
}

// MakeControllerCommand generates a new web controller
pub struct MakeControllerCommand {
	BaseCommand
}

pub fn new_make_controller_command() &MakeControllerCommand {
	return &MakeControllerCommand{
		BaseCommand: BaseCommand{
			name:        'make:controller'
			description: 'Generate a new web controller class'
			sig:         '<name> [--resource]'
		}
	}
}

pub fn (c &MakeControllerCommand) execute(input &CommandInput, mut output &CommandOutput) ! {
	name := input.get_arg(0)
	if name.len == 0 {
		return error('controller name is required. Usage: make:controller <Name>')
	}

	is_resource := input.has_flag('resource')
	stub := generate_controller_stub(name, is_resource)
	write_stub(name, 'controllers', stub, mut output)!
	return
}

// MakeMiddlewareCommand generates a new middleware
pub struct MakeMiddlewareCommand {
	BaseCommand
}

pub fn new_make_middleware_command() &MakeMiddlewareCommand {
	return &MakeMiddlewareCommand{
		BaseCommand: BaseCommand{
			name:        'make:middleware'
			description: 'Generate a new middleware class'
			sig:         '<name>'
		}
	}
}

pub fn (c &MakeMiddlewareCommand) execute(input &CommandInput, mut output &CommandOutput) ! {
	name := input.get_arg(0)
	if name.len == 0 {
		return error('middleware name is required. Usage: make:middleware <Name>')
	}

	stub := generate_middleware_stub(name)
	write_stub(name, 'middleware', stub, mut output)!
	return
}

// MakeProviderCommand generates a new service provider
pub struct MakeProviderCommand {
	BaseCommand
}

pub fn new_make_provider_command() &MakeProviderCommand {
	return &MakeProviderCommand{
		BaseCommand: BaseCommand{
			name:        'make:provider'
			description: 'Generate a new service provider class'
			sig:         '<name>'
		}
	}
}

pub fn (c &MakeProviderCommand) execute(input &CommandInput, mut output &CommandOutput) ! {
	name := input.get_arg(0)
	if name.len == 0 {
		return error('provider name is required. Usage: make:provider <Name>')
	}

	stub := generate_provider_stub(name)
	write_stub(name, 'providers', stub, mut output)!
	return
}

// MakeEntityCommand generates a new ORM entity
pub struct MakeEntityCommand {
	BaseCommand
}

pub fn new_make_entity_command() &MakeEntityCommand {
	return &MakeEntityCommand{
		BaseCommand: BaseCommand{
			name:        'make:entity'
			description: 'Generate a new entity class'
			sig:         '<name>'
		}
	}
}

pub fn (c &MakeEntityCommand) execute(input &CommandInput, mut output &CommandOutput) ! {
	name := input.get_arg(0)
	if name.len == 0 {
		return error('entity name is required. Usage: make:entity <Name>')
	}

	stub := generate_entity_stub(name)
	write_stub(name, 'entities', stub, mut output)!
	return
}

// MakeModelCommand generates a new model (entity + repository stub)
pub struct MakeModelCommand {
	BaseCommand
}

pub fn new_make_model_command() &MakeModelCommand {
	return &MakeModelCommand{
		BaseCommand: BaseCommand{
			name:        'make:model'
			description: 'Generate a new model (entity + repository stub)'
			sig:         '<name>'
		}
	}
}

pub fn (c &MakeModelCommand) execute(input &CommandInput, mut output &CommandOutput) ! {
	name := input.get_arg(0)
	if name.len == 0 {
		return error('model name is required. Usage: make:model <Name>')
	}

	// 生成实体 + 仓储两个文件
	entity_stub := generate_entity_stub(name)
	repo_stub := generate_repository_stub(name)
	write_stub(name, 'entities', entity_stub, mut output)!
	write_stub(name, 'repositories', repo_stub, mut output)!
	return
}

// MakeMigrationCommand generates a new database migration file
// 文件名格式：YYYYMMDDHHMMSS_create_<name>_table.v
pub struct MakeMigrationCommand {
	BaseCommand
}

pub fn new_make_migration_command() &MakeMigrationCommand {
	return &MakeMigrationCommand{
		BaseCommand: BaseCommand{
			name:        'make:migration'
			description: 'Generate a new database migration'
			sig:         '<name>'
		}
	}
}

pub fn (c &MakeMigrationCommand) execute(input &CommandInput, mut output &CommandOutput) ! {
	name := input.get_arg(0)
	if name.len == 0 {
		return error('migration name is required. Usage: make:migration <Name>')
	}

	stub := generate_migration_stub(name)
	// 时间戳必须能直接当文件名：`format_ss()` 给的是 `2026-11-06 14:57:47`，
	// 中间那个空格会把路径切成两段，落盘的是一堆以日期命名的碎片。
	timestamp := migration_timestamp(time.now())
	snake := to_snake_case(name)
	path := 'database/migrations/${timestamp}_create_${snake}_table.v'

	os.mkdir_all('database/migrations') or {}
	os.write_file(path, stub)!

	output.success('Created: ${path}')
	return
}

// MakeResourceCommand generates a new API resource transformer
pub struct MakeResourceCommand {
	BaseCommand
}

pub fn new_make_resource_command() &MakeResourceCommand {
	return &MakeResourceCommand{
		BaseCommand: BaseCommand{
			name:        'make:resource'
			description: 'Generate a new API resource transformer'
			sig:         '<name>'
		}
	}
}

pub fn (c &MakeResourceCommand) execute(input &CommandInput, mut output &CommandOutput) ! {
	name := input.get_arg(0)
	if name.len == 0 {
		return error('resource name is required. Usage: make:resource <Name>')
	}

	stub := generate_resource_stub(name)
	write_stub(name, 'resources', stub, mut output)!
	return
}

// MakeSeederCommand generates a new database seeder
pub struct MakeSeederCommand {
	BaseCommand
}

pub fn new_make_seeder_command() &MakeSeederCommand {
	return &MakeSeederCommand{
		BaseCommand: BaseCommand{
			name:        'make:seeder'
			description: 'Generate a new database seeder'
			sig:         '<name>'
		}
	}
}

pub fn (c &MakeSeederCommand) execute(input &CommandInput, mut output &CommandOutput) ! {
	name := input.get_arg(0)
	if name.len == 0 {
		return error('seeder name is required. Usage: make:seeder <Name>')
	}

	stub := generate_seeder_stub(name)
	write_stub(name, 'database/seeders', stub, mut output)!
	return
}

// MakeFactoryCommand generates a new model factory
pub struct MakeFactoryCommand {
	BaseCommand
}

pub fn new_make_factory_command() &MakeFactoryCommand {
	return &MakeFactoryCommand{
		BaseCommand: BaseCommand{
			name:        'make:factory'
			description: 'Generate a new model factory'
			sig:         '<name>'
		}
	}
}

pub fn (c &MakeFactoryCommand) execute(input &CommandInput, mut output &CommandOutput) ! {
	name := input.get_arg(0)
	if name.len == 0 {
		return error('factory name is required. Usage: make:factory <Name>')
	}

	stub := generate_factory_stub(name)
	write_stub(name, 'database/factories', stub, mut output)!
	return
}

// ============================================================
// Stub generators
// ============================================================

// generate_command_stub 生成 CLI 命令 stub。
//
// 这里的 `mut output` 不是风格选择：`Command.execute` 的签名是
// `execute(input &CommandInput, mut output &CommandOutput) !`。少了 `mut`
// 连 `output.success(...)` 都过不了编译器（"`output` is immutable"）。
fn generate_command_stub(name string) string {
	pascal := to_pascal_case(name)
	snake := to_snake_case(name)
	return "module commands

import photon.cli

// ${pascal}Command — generated by Photon CLI
pub struct ${pascal}Command {
	cli.BaseCommand
}

pub fn new_${snake}_command() &${pascal}Command {
	return &${pascal}Command{
		BaseCommand: cli.BaseCommand{
			name: \"${snake}\"
			description: \"${pascal} command description\"
			sig: \"[--option=value]\"
		}
	}
}

pub fn (c &${pascal}Command) execute(input &cli.CommandInput, mut output &cli.CommandOutput) ! {
	output.success(\"${pascal} command executed!\")
}
"
}

fn generate_controller_stub(name string, is_resource bool) string {
	pascal := to_pascal_case(name)
	mut resource_methods := ''
	if is_resource {
		resource_methods = "
// index lists all ${pascal} resources
@[get; \"/${to_snake_case(name)}\"]
pub fn (mut c ${pascal}Controller) index() veb.Result {
	c.set_content_type(\"application/json\")
	return c.text(\"[{\\\"id\\\":1,\\\"name\\\":\\\"${to_snake_case(name)}\\\"}]\")
}

// show returns a single ${pascal} resource
@[get; \"/${to_snake_case(name)}/:id\"]
pub fn (mut c ${pascal}Controller) show(id string) veb.Result {
	c.set_content_type(\"application/json\")
	return c.text(\"{\\\"id\\\":\" + id + \",\\\"name\\\":\\\"${to_snake_case(name)}\\\"}\")
}

// store creates a new ${pascal} resource
@[post; \"/${to_snake_case(name)}\"]
pub fn (mut c ${pascal}Controller) store() veb.Result {
	c.set_content_type(\"application/json\")
	return c.text(\"{\\\"status\\\":\\\"created\\\"}\")
}

// update modifies an existing ${pascal} resource
@[put; \"/${to_snake_case(name)}/:id\"]
pub fn (mut c ${pascal}Controller) update(id string) veb.Result {
	c.set_content_type(\"application/json\")
	return c.text(\"{\\\"id\\\":\" + id + \",\\\"status\\\":\\\"updated\\\"}\")
}

// destroy deletes a ${pascal} resource
@[delete; \"/${to_snake_case(name)}/:id\"]
pub fn (mut c ${pascal}Controller) destroy(id string) veb.Result {
	c.set_content_type(\"application/json\")
	return c.text(\"{\\\"id\\\":\" + id + \",\\\"status\\\":\\\"deleted\\\"}\")
}"
	}
	return
		'module controllers

import veb

// ${pascal}Controller — generated by Photon CLI
pub struct ${pascal}Controller {
	veb.Context
}
' +
		resource_methods
}

// generate_middleware_stub 生成中间件 stub。
//
// 签名必须和 `web.MiddlewareFunc = fn (ctx &MiddlewareContext) !bool` 一致：
// 早先生成的是 `mut ctx &web.MiddlewareContext`，既不是那个函数类型的实例，
// 也无法直接传给 `chain.use(...)` —— 中间件生成了却挂不上去。
fn generate_middleware_stub(name string) string {
	pascal := to_pascal_case(name)
	snake := to_snake_case(name)
	return "module middleware

import photon.web

// ${pascal}Middleware — generated by Photon CLI
//
// 用法：chain.use(${snake}_middleware)
pub fn ${snake}_middleware(ctx &web.MiddlewareContext) !bool {
	// Add middleware logic here. ctx.data 可用于在中间件之间传值。
	_ = ctx
	return true
}
"
}

fn generate_provider_stub(name string) string {
	pascal := to_pascal_case(name)
	snake := to_snake_case(name)
	return "module providers

import photon.core

// ${pascal}ServiceProvider — generated by Photon CLI
pub struct ${pascal}ServiceProvider {}

pub fn (p &${pascal}ServiceProvider) name() string {
	return \"${snake}\"
}

pub fn (p &${pascal}ServiceProvider) register(app &core.ApplicationContext) ! {
	// Register beans in the container here
}

pub fn (p &${pascal}ServiceProvider) boot(app &core.ApplicationContext) ! {
	// Post-registration boot logic here
}
"
}

fn generate_entity_stub(name string) string {
	pascal := to_pascal_case(name)
	table := table_name_of(name)
	return "module entities

// ${pascal} — generated by Photon CLI
@[table: \"${table}\"]
pub struct ${pascal} {
pub mut:
	id         int    @[primary_key; sql: \"id\"; sql_type: \"INTEGER\"]
	name       string @[sql: \"name\"; sql_type: \"VARCHAR(255)\"]
	created_at i64    @[sql: \"created_at\"; sql_type: \"INTEGER\"]
	updated_at i64    @[sql: \"updated_at\"; sql_type: \"INTEGER\"]
}
"
}

// generate_repository_stub 生成仓储层 stub（供 make:model 使用）
//
// 实体在 `entities` 包里，仓储在 `repositories` 包里 —— 必须跨包引用
// `entities.${pascal}`。早先版本直接写 `${pascal}`，等于在 repositories 包里
// 找一个不存在的类型（`unknown type repositories.Address`）。
//
// 查询走 phorm.new_query_builder()：框架里没有 `find_by_id` / `find_all` /
// `save` / `delete_by_id` 这些包级函数，那些名字都是凭空写出来的。
fn generate_repository_stub(name string) string {
	pascal := to_pascal_case(name)
	snake := to_snake_case(name)
	table := table_name_of(name)
	return "module repositories

import photon.orm as phorm

// ${pascal}Repository — generated by Photon CLI
// 数据访问层，封装 entities.${pascal} 的 CRUD 操作
pub struct ${pascal}Repository {
pub:
	om &phorm.OrmManager = unsafe { nil }
}

pub fn new_${snake}_repository(om &phorm.OrmManager) &${pascal}Repository {
	return &${pascal}Repository{
		om: om
	}
}

// query 返回针对 ${table} 表的查询构造器
pub fn (r &${pascal}Repository) query() &phorm.QueryBuilder {
	return phorm.new_query_builder(r.om, 'default', '${table}')
}

// entity_table 返回实体对应的表名，便于调用方自建查询
pub fn (r &${pascal}Repository) entity_table() string {
	return '${table}'
}
"
}

// generate_migration_stub 生成迁移文件 stub。
//
// 早先版本引用了 `phorm.TableBuilder` / `phorm.execute_schema` / 无参
// `new_schema()` —— 这三个都不存在。真实 API 是
// `new_schema(.sqlite)` → `schema.create_table(name, fn (mut t TableDef) {...})`
// → `schema.to_sql()`。
//
// 迁移的执行不由迁移自己发起：`Migration` 接口在 `MigrationManager.migrate()`
// 里被调用，那里才持有 exec_fn / 事务。所以 up() 只负责「产出 DDL 并交给
// manager 提供的入口」，而不是自己去连库。
fn generate_migration_stub(name string) string {
	pascal := to_pascal_case(name)
	snake := to_snake_case(name)
	table := table_name_of(name)
	return "module migrations

import photon.orm as phorm

// Create${pascal}Table — generated by Photon CLI
// 创建 ${table} 表
pub struct Create${pascal}Table {}

// version 迁移版本号，需全局唯一且递增
pub fn (m &Create${pascal}Table) version() int {
	return ${migration_version_of(name)}
}

// name 迁移名称
pub fn (m &Create${pascal}Table) name() string {
	return 'create_${table}_table'
}

// up 正向迁移：创建表
//
// 这里只产出 DDL —— 真正的执行发生在 MigrationManager.migrate()，那里才
// 持有 exec_fn 和事务。迁移自己不该去连库。
pub fn (m &Create${pascal}Table) up(mut manager phorm.OrmManager) ! {
	_ = manager
	_ = create_${snake}_table_sql()
}

// down 回滚迁移：删除表
pub fn (m &Create${pascal}Table) down(mut manager phorm.OrmManager) ! {
	_ = manager
	_ = drop_${snake}_table_sql()
}

// create_${snake}_table_sql 生成建表 DDL。
// 单独抽出来，用例可以直接断言这条 SQL 的内容，不必起数据库。
pub fn create_${snake}_table_sql() string {
	mut schema := phorm.new_schema(.sqlite)
	schema.create_table('${table}', fn (mut t phorm.TableDef) {
		t.id()
		t.string_('name', 255)
		t.timestamps()
	})
	return schema.to_sql()
}

// drop_${snake}_table_sql 生成删表 DDL
pub fn drop_${snake}_table_sql() string {
	mut schema := phorm.new_schema(.sqlite)
	schema.drop_table('${table}')
	return schema.to_sql()
}
"
}

// generate_resource_stub 生成 API Resource 转换器 stub
fn generate_resource_stub(name string) string {
	pascal := to_pascal_case(name)
	snake := to_snake_case(name)
	return 'module resources

import x.json2

// ${pascal}Resource — generated by Photon CLI
// API 资源转换器，将 ${pascal} 实体转换为 API 响应格式
pub struct ${pascal}Resource {
pub:
	id         int
	name       string
	created_at i64
	updated_at i64
}

// new_${snake}_resource 从实体构造 Resource
pub fn new_${snake}_resource(id int, name string, created_at i64, updated_at i64) ${pascal}Resource {
	return ${pascal}Resource{
		id: id
		name: name
		created_at: created_at
		updated_at: updated_at
	}
}

// to_json 序列化为 JSON 字符串
pub fn (r ${pascal}Resource) to_json() string {
	return json2.encode(r)
}
'
}

// generate_seeder_stub 生成 Seeder stub
fn generate_seeder_stub(name string) string {
	pascal := to_pascal_case(name)
	snake := to_snake_case(name)
	return "module seeders

import photon.cli

// ${pascal}Seeder — generated by Photon CLI
// 数据库种子数据填充器
pub struct ${pascal}Seeder {}

pub fn new_${snake}_seeder() &${pascal}Seeder {
	return &${pascal}Seeder{}
}

// run 执行种子数据填充
//
// 和 CommandOutput 的所有写方法一样，这个参数必须是 `mut`：
// 少了它，`output.writeln(...)` 直接过不了编译。
pub fn (s &${pascal}Seeder) run(mut output cli.CommandOutput) ! {
	output.writeln(\"  Seeding ${snake}...\")

	// TODO: 在此插入种子数据逻辑
	output.success(\"  ${pascal} seeded successfully\")
}
"
}

// generate_factory_stub 生成 Model Factory stub。
//
// 早先版本有三处编译不过：
//   1. `fn (mut f X) with_name() &X { ... return &f }` —— 返回指向栈上
//      接收者的引用，V 直接拒绝（"`f` cannot be referenced outside
//      `unsafe` blocks as it might be stored on stack"）。
//   2. `make()` 返回 `${pascal}Resource`，那个类型在 factories 包里不存在。
//   3. 工厂造出来的应该是实体，不是 API Resource。
//
// 改成 `@[heap]` 结构体 + 返回值接收者（`f &X`）承载链式调用，
// 并把返回值换成 `entities.${pascal}`。
fn generate_factory_stub(name string) string {
	pascal := to_pascal_case(name)
	snake := to_snake_case(name)
	return "module factories

import entities

// ${pascal}Factory — generated by Photon CLI
// 模型工厂，用于生成测试与种子数据（Builder 模式）
@[heap]
pub struct ${pascal}Factory {
mut:
	name_ string
}

pub fn new_${snake}_factory() &${pascal}Factory {
	return &${pascal}Factory{
		name_: 'sample-${snake}'
	}
}

// with_name 设置 name 字段（Builder 链式调用）
pub fn (mut f ${pascal}Factory) with_name(value string) &${pascal}Factory {
	f.name_ = value
	return f
}

// make 构造实体（不持久化）
pub fn (f &${pascal}Factory) make() entities.${pascal} {
	return entities.${pascal}{
		name: f.name_
	}
}
"
}

// ============================================================
// Helpers
// ============================================================

fn write_stub(name string, dir string, content string, mut output &CommandOutput) ! {
	path := '${dir}/${to_snake_case(name)}.v'

	// Ensure directory exists
	os.mkdir_all(dir) or {}

	// Write file
	os.write_file(path, content)!

	output.success('Created: ${path}')
}

// to_snake_case converts PascalCase or camelCase to snake_case.
//
// 委托给 strutil.snake：这里原来是一份手写的劣化实现，每个大写字母前都插
// 下划线，于是 `HTMLParser` → `h_t_m_l_parser`、`UserDOB` → `user_d_o_b`。
// 生成出来的文件叫 controllers/user_d_o_b.v，表叫 user_d_o_bs。
// strutil.snake 处理了缩写连读（`HTTPServer` → `http_server`），这里没理由
// 再维护第二套规则 —— 而 cli_test 里那条断言当时把这个 bug 锁成了「正确」。
fn to_snake_case(s string) string {
	return strutil.snake(s)
}

// to_pascal_case converts snake_case to PascalCase
fn to_pascal_case(s string) string {
	mut result := ''
	mut capitalize_next := true
	for ch in s {
		if ch == `_` || ch == `-` {
			capitalize_next = true
			continue
		}
		if capitalize_next {
			result += ch.ascii_str().to_upper()
			capitalize_next = false
		} else {
			result += ch.ascii_str()
		}
	}
	return result
}

// migration_version_of 从迁移名推出一个稳定、可复现的版本号。
//
// 早先写死 `return 100` 并留了句 TODO —— 而版本号是 MigrationManager 排序与
// 去重的唯一依据，每个新迁移都是 100 就意味着「第二个迁移永远不执行」。
// 这里用名字的 FNV-1a 取正数：同一个名字永远得到同一个版本，不同名字极难撞。
fn migration_version_of(name string) int {
	mut hash := u64(14695981039346656037)
	for ch in to_snake_case(name) {
		hash = hash ^ u64(ch)
		hash = hash * u64(1099511628211)
	}
	// 截到 32 位并加 1，避开 0（0 常被当作「未设置」）
	return int(hash & u64(0x7FFFFFFF)) + 1
}

// migration_timestamp 把时间格式化成可安全用作文件名的 `YYYYMMDDHHMMSS`。
//
// 为什么不用 `format_ss()`：它返回 `2026-11-06 14:57:47`，含空格。写文件时
// 路径被切成两段，结果是在 database/migrations/ 下生成一堆以日期命名的
// 碎片文件，而「看起来」命令还成功了。
fn migration_timestamp(t time.Time) string {
	return '${t.year:04d}${t.month:02d}${t.day:02d}${t.hour:02d}${t.minute:02d}${t.second:02d}'
}

// table_name_of 由实体名推出表名。
//
// 直接 `snake + 's'` 会得到 `posts` ← `Post`（对），但 `create_postss`
// ← `CreatePosts`（错）：迁移命令的入参常写成 `CreatePosts`，已经带复数。
// 这里只在末尾不是 s 时补一个。
fn table_name_of(name string) string {
	snake := to_snake_case(name)
	if snake.ends_with('s') {
		return snake
	}
	return snake + 's'
}
