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
//   make:resource     - generate an API resource transformer
//   make:seeder       - generate a database seeder
//   make:factory      - generate a model factory

import os
import time

// MakeCommandCommand generates a new CLI command file
pub struct MakeCommandCommand {
	BaseCommand
}

pub fn new_make_command_command() &MakeCommandCommand {
	return &MakeCommandCommand{
		BaseCommand: BaseCommand{
			name: 'make:command'
			description: 'Generate a new CLI command class'
			sig: '<name>'
		}
	}
}

pub fn (c &MakeCommandCommand) execute(input &CommandInput, output &CommandOutput) ! {
	name := input.get_arg(0)
	if name.len == 0 {
		return error('command name is required. Usage: make:command <Name>')
	}

	stub := generate_command_stub(name)
	write_stub(name, 'commands', stub, output)!
	return
}

// MakeControllerCommand generates a new web controller
pub struct MakeControllerCommand {
	BaseCommand
}

pub fn new_make_controller_command() &MakeControllerCommand {
	return &MakeControllerCommand{
		BaseCommand: BaseCommand{
			name: 'make:controller'
			description: 'Generate a new web controller class'
			sig: '<name> [--resource]'
		}
	}
}

pub fn (c &MakeControllerCommand) execute(input &CommandInput, output &CommandOutput) ! {
	name := input.get_arg(0)
	if name.len == 0 {
		return error('controller name is required. Usage: make:controller <Name>')
	}

	is_resource := input.has_flag('resource')
	stub := generate_controller_stub(name, is_resource)
	write_stub(name, 'controllers', stub, output)!
	return
}

// MakeMiddlewareCommand generates a new middleware
pub struct MakeMiddlewareCommand {
	BaseCommand
}

pub fn new_make_middleware_command() &MakeMiddlewareCommand {
	return &MakeMiddlewareCommand{
		BaseCommand: BaseCommand{
			name: 'make:middleware'
			description: 'Generate a new middleware class'
			sig: '<name>'
		}
	}
}

pub fn (c &MakeMiddlewareCommand) execute(input &CommandInput, output &CommandOutput) ! {
	name := input.get_arg(0)
	if name.len == 0 {
		return error('middleware name is required. Usage: make:middleware <Name>')
	}

	stub := generate_middleware_stub(name)
	write_stub(name, 'middleware', stub, output)!
	return
}

// MakeProviderCommand generates a new service provider
pub struct MakeProviderCommand {
	BaseCommand
}

pub fn new_make_provider_command() &MakeProviderCommand {
	return &MakeProviderCommand{
		BaseCommand: BaseCommand{
			name: 'make:provider'
			description: 'Generate a new service provider class'
			sig: '<name>'
		}
	}
}

pub fn (c &MakeProviderCommand) execute(input &CommandInput, output &CommandOutput) ! {
	name := input.get_arg(0)
	if name.len == 0 {
		return error('provider name is required. Usage: make:provider <Name>')
	}

	stub := generate_provider_stub(name)
	write_stub(name, 'providers', stub, output)!
	return
}

// MakeEntityCommand generates a new ORM entity
pub struct MakeEntityCommand {
	BaseCommand
}

pub fn new_make_entity_command() &MakeEntityCommand {
	return &MakeEntityCommand{
		BaseCommand: BaseCommand{
			name: 'make:entity'
			description: 'Generate a new entity class'
			sig: '<name>'
		}
	}
}

pub fn (c &MakeEntityCommand) execute(input &CommandInput, output &CommandOutput) ! {
	name := input.get_arg(0)
	if name.len == 0 {
		return error('entity name is required. Usage: make:entity <Name>')
	}

	stub := generate_entity_stub(name)
	write_stub(name, 'entities', stub, output)!
	return
}

// MakeModelCommand generates a new model (entity + repository stub)
pub struct MakeModelCommand {
	BaseCommand
}

pub fn new_make_model_command() &MakeModelCommand {
	return &MakeModelCommand{
		BaseCommand: BaseCommand{
			name: 'make:model'
			description: 'Generate a new model (entity + repository stub)'
			sig: '<name>'
		}
	}
}

pub fn (c &MakeModelCommand) execute(input &CommandInput, output &CommandOutput) ! {
	name := input.get_arg(0)
	if name.len == 0 {
		return error('model name is required. Usage: make:model <Name>')
	}

	// 生成实体 + 仓储两个文件
	entity_stub := generate_entity_stub(name)
	repo_stub := generate_repository_stub(name)
	write_stub(name, 'entities', entity_stub, output)!
	write_stub(name, 'repositories', repo_stub, output)!
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
			name: 'make:migration'
			description: 'Generate a new database migration'
			sig: '<name>'
		}
	}
}

pub fn (c &MakeMigrationCommand) execute(input &CommandInput, output &CommandOutput) ! {
	name := input.get_arg(0)
	if name.len == 0 {
		return error('migration name is required. Usage: make:migration <Name>')
	}

	stub := generate_migration_stub(name)
	now := time.now()
	timestamp := '${now.year}${now.month:02}${now.day:02}${now.hour:02}${now.minute:02}${now.second:02}'
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
			name: 'make:resource'
			description: 'Generate a new API resource transformer'
			sig: '<name>'
		}
	}
}

pub fn (c &MakeResourceCommand) execute(input &CommandInput, output &CommandOutput) ! {
	name := input.get_arg(0)
	if name.len == 0 {
		return error('resource name is required. Usage: make:resource <Name>')
	}

	stub := generate_resource_stub(name)
	write_stub(name, 'resources', stub, output)!
	return
}

// MakeSeederCommand generates a new database seeder
pub struct MakeSeederCommand {
	BaseCommand
}

pub fn new_make_seeder_command() &MakeSeederCommand {
	return &MakeSeederCommand{
		BaseCommand: BaseCommand{
			name: 'make:seeder'
			description: 'Generate a new database seeder'
			sig: '<name>'
		}
	}
}

pub fn (c &MakeSeederCommand) execute(input &CommandInput, output &CommandOutput) ! {
	name := input.get_arg(0)
	if name.len == 0 {
		return error('seeder name is required. Usage: make:seeder <Name>')
	}

	stub := generate_seeder_stub(name)
	write_stub(name, 'database/seeders', stub, output)!
	return
}

// MakeFactoryCommand generates a new model factory
pub struct MakeFactoryCommand {
	BaseCommand
}

pub fn new_make_factory_command() &MakeFactoryCommand {
	return &MakeFactoryCommand{
		BaseCommand: BaseCommand{
			name: 'make:factory'
			description: 'Generate a new model factory'
			sig: '<name>'
		}
	}
}

pub fn (c &MakeFactoryCommand) execute(input &CommandInput, output &CommandOutput) ! {
	name := input.get_arg(0)
	if name.len == 0 {
		return error('factory name is required. Usage: make:factory <Name>')
	}

	stub := generate_factory_stub(name)
	write_stub(name, 'database/factories', stub, output)!
	return
}

// ============================================================
// Stub generators
// ============================================================

fn generate_command_stub(name string) string {
	pascal := to_pascal_case(name)
	snake := to_snake_case(name)
	return 'module commands

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

pub fn (c &${pascal}Command) execute(input &cli.CommandInput, output &cli.CommandOutput) ! {
	output.success(\"${pascal} command executed!\")
	return
}
'
}

fn generate_controller_stub(name string, is_resource bool) string {
	pascal := to_pascal_case(name)
	mut resource_methods := ''
	if is_resource {
		resource_methods = '
// index lists all ${pascal} resources
@[get; \"/${to_snake_case(name)}\"]
pub fn (mut c ${pascal}Controller) index() veb.Result {
	c.set_content_type(\"application/json\")
	return c.text(\"[{\\\"id\\\":1,\\\"name\\\":\\\"${to_snake_case(name)}\\\"}]")
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
}'
	}
	return 'module controllers

import veb

// ${pascal}Controller — generated by Photon CLI
pub struct ${pascal}Controller {
	veb.Context
}
' + resource_methods
}

fn generate_middleware_stub(name string) string {
	pascal := to_pascal_case(name)
	return 'module middleware

import photon.web

// ${pascal}Middleware — generated by Photon CLI
pub fn ${to_snake_case(name)}_middleware(mut ctx &web.MiddlewareContext) !bool {
	// Add middleware logic here
	return true
}
'
}

fn generate_provider_stub(name string) string {
	pascal := to_pascal_case(name)
	snake := to_snake_case(name)
	return 'module providers

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
'
}

fn generate_entity_stub(name string) string {
	pascal := to_pascal_case(name)
	snake := to_snake_case(name)
	table := snake + 's'
	return 'module entities

// ${pascal} — generated by Photon CLI
@[table: \"${table}\"]
pub struct ${pascal} {
pub mut:
	id         int    @[primary_key; sql: \"id\"; sql_type: \"INTEGER\"]
	created_at i64    @[sql: \"created_at\"; sql_type: \"INTEGER\"]
	updated_at i64    @[sql: \"updated_at\"; sql_type: \"INTEGER\"]
}
'
}

// generate_repository_stub 生成仓储层 stub（供 make:model 使用）
fn generate_repository_stub(name string) string {
	pascal := to_pascal_case(name)
	snake := to_snake_case(name)
	return 'module repositories

import photon.orm as phorm

// ${pascal}Repository — generated by Photon CLI
pub struct ${pascal}Repository {
pub:
	om &phorm.OrmManager = unsafe { nil }
}

pub fn new_${snake}_repository(om &phorm.OrmManager) &${pascal}Repository {
	return &${pascal}Repository{
		om: om
	}
}

// find_by_id 根据 ID 查询单个 ${pascal}
pub fn (r &${pascal}Repository) find_by_id(id int) !${pascal} {
	return phorm.find_by_id[${pascal}](r.om, id)!
}

// find_all 查询全部 ${pascal}（按 id 升序）
pub fn (mut r ${pascal}Repository) find_all() ![]${pascal} {
	return phorm.find_all[${pascal}](r.om)!
}

// save 插入或更新 ${pascal}
pub fn (r &${pascal}Repository) save(mut entity ${pascal}) !${pascal} {
	return phorm.save(r.om, mut entity)!
}

// delete 按 ID 删除 ${pascal}
pub fn (r &${pascal}Repository) delete(id int) ! {
	phorm.delete_by_id[${pascal}](r.om, id)!
}
'
}

// generate_migration_stub 生成迁移文件 stub
fn generate_migration_stub(name string) string {
	pascal := to_pascal_case(name)
	snake := to_snake_case(name)
	table := snake + 's'
	return 'module main

// Create${pascal}Table — generated by Photon CLI
// 创建 ${table} 表

import photon.orm as phorm

pub struct Create${pascal}Table {}

// version 迁移版本号（递增）
pub fn (m Create${pascal}Table) version() int {
	return 100 // TODO: 调整为实际版本号，避免与现有迁移冲突
}

// name 迁移名称
pub fn (m Create${pascal}Table) name() string {
	return \"create_${table}_table\"
}

// up 正向迁移：创建表
pub fn (m Create${pascal}Table) up(om &phorm.OrmManager) ! {
	schema := phorm.new_schema()
	schema.create_table(\"${table}\", fn (t phorm.TableBuilder) {
		t.id()
		t.string(\"name\", 255)
		t.timestamps()
	})
	phorm.execute_schema(om, schema)!
}

// down 回滚迁移：删除表
pub fn (m Create${pascal}Table) down(om &phorm.OrmManager) ! {
	schema := phorm.new_schema()
	schema.drop_table(\"${table}\")
	phorm.execute_schema(om, schema)!
}
'
}

// generate_resource_stub 生成 API Resource 转换器 stub
fn generate_resource_stub(name string) string {
	pascal := to_pascal_case(name)
	snake := to_snake_case(name)
	return 'module resources

import json

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
	return json.encode(r)
}
'
}

// generate_seeder_stub 生成 Seeder stub
fn generate_seeder_stub(name string) string {
	pascal := to_pascal_case(name)
	snake := to_snake_case(name)
	return 'module seeders

import photon.cli

// ${pascal}Seeder — generated by Photon CLI
// 数据库种子数据填充器
pub struct ${pascal}Seeder {}

pub fn new_${snake}_seeder() &${pascal}Seeder {
	return &${pascal}Seeder{}
}

// run 执行种子数据填充
pub fn (s &${pascal}Seeder) run(output &cli.CommandOutput) ! {
	output.writeln(\"  Seeding ${snake}...\")

	// TODO: 在此插入种子数据逻辑
	// 推荐使用 Factory 生成测试数据：
	//   factory := new_${snake}_factory(boot)
	//   factory.with_name(\"sample\").create()!

	output.success(\"  ${pascal} seeded successfully\")
}
'
}

// generate_factory_stub 生成 Model Factory stub
fn generate_factory_stub(name string) string {
	pascal := to_pascal_case(name)
	snake := to_snake_case(name)
	return 'module factories

// ${pascal}Factory — generated by Photon CLI
// 模型工厂，用于生成测试与种子数据（Builder 模式）
pub struct ${pascal}Factory {
mut:
	name string
}

pub fn new_${snake}_factory() ${pascal}Factory {
	return ${pascal}Factory{
		name: \"sample-${snake}\"
	}
}

// with_name 设置 name 字段（Builder 链式调用）
pub fn (mut f ${pascal}Factory) with_name(name string) &${pascal}Factory {
	f.name = name
	return &f
}

// make 构造实体（不持久化）
pub fn (f &${pascal}Factory) make() ${pascal}Resource {
	// TODO: 返回实际实体类型
	return ${pascal}Resource{
		id: 0
		name: f.name
		created_at: 0
		updated_at: 0
	}
}

// create 构造并持久化实体
pub fn (f &${pascal}Factory) create() !${pascal}Resource {
	entity := f.make()
	// TODO: 调用 Repository.save() 持久化
	return entity
}
'
}

// ============================================================
// Helpers
// ============================================================

fn write_stub(name string, dir string, content string, output &CommandOutput) ! {
	path := '${dir}/${to_snake_case(name)}.v'

	// Ensure directory exists
	os.mkdir_all(dir) or {}

	// Write file
	os.write_file(path, content)!

	output.success('Created: ${path}')
}

// to_snake_case converts PascalCase or camelCase to snake_case
fn to_snake_case(s string) string {
	mut result := ''
	for i, ch in s {
		if ch.is_capital() && i > 0 {
			result += '_'
		}
		result += ch.ascii_str().to_lower()
	}
	return result
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
