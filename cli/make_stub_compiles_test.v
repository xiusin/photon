module cli

// make_stub_compiles_test.v — 生成出来的代码必须能编译
//
// 为什么这个文件存在
// ------------------
// `make:*` 系列是脚手架：用户敲一条命令，拿到一份可以直接开工的代码。
// 但这 10 个生成器在 0.5.2 下产出的 80 个文件里有 48 个编不过：
//
//   commands/*      `output` 参数少了 `mut`（"output is immutable"）
//   database/seeders/*  同上
//   middleware/*    签名与 web.MiddlewareFunc 不匹配
//   factories/*     返回栈上接收者的引用；返回类型 factories.XxxResource 不存在
//   repositories/*  实体类型写成了本包内的名字，而实体在 entities 包
//   database/migrations/*  `phorm.TableBuilder` / `phorm.execute_schema` 都不存在
//
// 它们全都没被调用过：用例只断言过「命令名对」，从没断言过「生成的文件能编」。
// 于是「生成成功」被当成「生成正确」，而这两件事差了 48 个编译错误。
//
// 下面这组用例做的唯一一件事：真调一次生成器，真让 V 编译一次产物。
import os

// stub_workdir 造一个干净的目录，用来承接生成结果
fn stub_workdir(tag string) string {
	dir := os.join_path(os.temp_dir(), 'photon-stub-${tag}-${os.getpid()}')
	os.rmdir_all(dir) or {}
	os.mkdir_all(dir) or {}
	return dir
}

// run_make 执行某个 make 命令，返回它创建的相对路径
fn run_make(cmd_name string, args []string) ![]string {
	mut out := new_capturing_output()
	mut raw := [cmd_name]
	raw << args
	// 走和 CliApplication 一样的解析路径：schema 从命令签名读出来。
	// 直接用 new_input 会得到一张空表，解析器退回贪心规则，
	// `--resource BlogPost` 里的 BlogPost 就被吃成 resource 的值。
	schema := schema_from_signature(make_signature(cmd_name))
	input := new_input_with_schema(raw, schema)
	match cmd_name {
		'make:command' { new_make_command_command().execute(input, mut out)! }
		'make:controller' { new_make_controller_command().execute(input, mut out)! }
		'make:middleware' { new_make_middleware_command().execute(input, mut out)! }
		'make:provider' { new_make_provider_command().execute(input, mut out)! }
		'make:entity' { new_make_entity_command().execute(input, mut out)! }
		'make:model' { new_make_model_command().execute(input, mut out)! }
		'make:migration' { new_make_migration_command().execute(input, mut out)! }
		'make:resource' { new_make_resource_command().execute(input, mut out)! }
		'make:seeder' { new_make_seeder_command().execute(input, mut out)! }
		'make:factory' { new_make_factory_command().execute(input, mut out)! }
		else { return error('unknown make command: ${cmd_name}') }
	}
	// success() 会带上 ANSI 颜色码，所以按标记定位而不是按前缀匹配
	mut created := []string{}
	for line in out.collected().split_into_lines() {
		if idx := line.index('Created: ') {
			created << line[idx + 'Created: '.len..].trim_space()
		}
	}
	return created
}

// make_signature 返回 make 命令自己的 usage 串，与 new_xxx_command() 里的 sig 一致
fn make_signature(cmd_name string) string {
	return match cmd_name {
		'make:controller' { '<name> [--resource]' }
		else { '<name>' }
	}
}

// ── 生成结果的名字 ──

fn test_stub_names_keep_acronyms_together() {
	dir := stub_workdir('names')
	os.chdir(dir) or { panic(err) }
	defer {
		os.chdir(os.dir(os.executable())) or {}
		os.rmdir_all(dir) or {}
	}

	created := run_make('make:controller', ['HTMLParser'])!
	assert created.len == 1
	assert created[0] == 'controllers/html_parser.v'
}

fn test_entity_table_name_keeps_acronyms_together() {
	dir := stub_workdir('entity')
	os.chdir(dir) or { panic(err) }
	defer {
		os.chdir(os.dir(os.executable())) or {}
		os.rmdir_all(dir) or {}
	}

	run_make('make:entity', ['UserDOB'])!
	content := os.read_file('entities/user_dob.v')!
	// 表名不该是 user_d_o_bs
	assert content.contains("@[table: \"user_dobs\"]")
	assert !content.contains('user_d_o_b')
}

// ── 生成结果能被 V 编译 ──

fn test_generated_command_stub_compiles() {
	dir := stub_workdir('cmd')
	os.chdir(dir) or { panic(err) }
	defer {
		os.chdir(os.dir(os.executable())) or {}
		os.rmdir_all(dir) or {}
	}

	run_make('make:command', ['SyncUsers'])!
	assert os.exists('commands/sync_users.v')
	// `output` 缺 `mut` 时这里是 "output is immutable"，正是本用例要拦的
	assert_stub_compiles('commands/sync_users.v')
}

fn test_generated_middleware_stub_compiles() {
	dir := stub_workdir('mw')
	os.chdir(dir) or { panic(err) }
	defer {
		os.chdir(os.dir(os.executable())) or {}
		os.rmdir_all(dir) or {}
	}

	run_make('make:middleware', ['Audit'])!
	assert_stub_compiles('middleware/audit.v')
}

fn test_generated_entity_and_repository_compile() {
	dir := stub_workdir('model')
	os.chdir(dir) or { panic(err) }
	defer {
		os.chdir(os.dir(os.executable())) or {}
		os.rmdir_all(dir) or {}
	}

	run_make('make:model', ['Article'])!
	assert os.exists('entities/article.v')
	assert os.exists('repositories/article.v')
	assert_stub_compiles('entities/article.v')
	assert_stub_compiles('repositories/article.v')
}

fn test_generated_factory_and_seeder_compile() {
	dir := stub_workdir('fac')
	os.chdir(dir) or { panic(err) }
	defer {
		os.chdir(os.dir(os.executable())) or {}
		os.rmdir_all(dir) or {}
	}

	run_make('make:entity', ['Article'])!
	run_make('make:factory', ['Article'])!
	run_make('make:seeder', ['Article'])!
	assert_stub_compiles('database/factories/article.v')
	assert_stub_compiles('database/seeders/article.v')
}

fn test_generated_migration_stub_compiles() {
	dir := stub_workdir('mig')
	os.chdir(dir) or { panic(err) }
	defer {
		os.chdir(os.dir(os.executable())) or {}
		os.rmdir_all(dir) or {}
	}

	created := run_make('make:migration', ['CreatePosts'])!
	assert created.len == 1
	path := created[0]
	// 文件名必须是完整路径：`format_ss()` 带空格时会被 argv 切成两段
	assert !path.contains(' ')
	assert path.starts_with('database/migrations/')
	assert path.ends_with('_create_posts_table.v')
	assert_stub_compiles(path)
}

// ── 迁移版本号 ──

fn test_migration_versions_are_distinct_per_name() {
	// 早先写死 `return 100`。版本号是 MigrationManager 排序与去重的唯一依据，
	// 每个迁移都是 100 就等于「只有第一个会执行」。
	a := migration_version_of('CreatePosts')
	b := migration_version_of('CreateUsers')
	c := migration_version_of('CreatePosts')
	assert a > 0
	assert b > 0
	assert a != b
	assert a == c, '同一名字必须得到同一版本号，否则每次重建都算新迁移'
}

// ── 生成 DDL 的内容 ──

fn test_migration_stub_ddl_is_real_sql() {
	dir := stub_workdir('ddl')
	os.chdir(dir) or { panic(err) }
	defer {
		os.chdir(os.dir(os.executable())) or {}
		os.rmdir_all(dir) or {}
	}

	run_make('make:migration', ['CreatePosts'])!
	files := os.ls('database/migrations') or { [] }
	assert files.len == 1
	content := os.read_file(os.join_path('database/migrations', files[0]))!
	// 迁移里引用过 phorm.TableBuilder / phorm.execute_schema，两者都不存在
	assert !content.contains('TableBuilder')
	assert !content.contains('execute_schema')
	// 真实 API
	assert content.contains('new_schema(.sqlite)')
	assert content.contains('create_table(')
	assert content.contains('t.id()')
}

// ── 参数解析：`--resource` 不能吃掉位置参数 ──

fn test_controller_resource_flag_does_not_eat_name() {
	// `make:controller --resource BlogPost`：非注解命令的 option schema 早先是
	// 空的，解析器退回贪心规则，把 BlogPost 当成 --resource 的值，位置参数
	// 消失，命令自己报 "controller name is required" —— 也就是说
	// `make:controller --resource Post` 这条命令从来没能用成功过。
	//
	// 有 schema 时（CliApplication 走的就是这条），`--resource` 是裸布尔，
	// 不会吞掉后面的 token。
	schema := schema_from_signature('<name> [--resource]')
	parsed := new_input_with_schema(['make:controller', '--resource', 'BlogPost'], schema)
	assert parsed.get_arg(0) == 'BlogPost'
	assert parsed.has_flag('resource')

	// 反过来把位置参数写在前、flag 写在后也必须成立 —— 用户两种顺序都会用
	parsed2 := new_input_with_schema(['make:controller', 'BlogPost', '--resource'], schema)
	assert parsed2.get_arg(0) == 'BlogPost'
	assert parsed2.has_flag('resource')
}

fn test_signature_schema_distinguishes_flag_and_value() {
	flags := schema_from_signature('<name> [--resource]')
	assert flags.known['resource']
	assert !flags.should_take_value('resource')

	values := schema_from_signature('[--port=8080] [--host=localhost]')
	assert values.known['port']
	assert values.should_take_value('port')
	assert values.should_take_value('host')
}

// 三种 usage 写法都得认：裸 flag、带等号取值、空格分隔取值。
fn test_signature_schema_reads_all_three_forms() {
	s := schema_from_signature('[--env <name>] [--verbose] [args...]')
	assert s.known['env']
	assert s.should_take_value('env')
	assert s.known['verbose']
	// `args...` 是位置参数说明，不是 --verbose 的值
	assert !s.should_take_value('verbose')
}

fn test_controller_stub_is_generated_with_resource_flag() {
	dir := stub_workdir('res')
	os.chdir(dir) or { panic(err) }
	defer {
		os.chdir(os.dir(os.executable())) or {}
		os.rmdir_all(dir) or {}
	}

	created := run_make('make:controller', ['--resource', 'Post'])!
	assert created.len == 1
	content := os.read_file(created[0])!
	assert content.contains('pub fn (mut c PostController) index()')
}

// ── helper ──

// assert_stub_compiles 用真实的 V 编译器编一次生成的产物。
//
// `-shared -o` 让它产出一个 .so 而不是可执行文件：模块包（module commands
// 之类）本来就没有 main，直接编可执行会以「没有 main」失败，那是假阴性。
// 找不到 v 可执行文件时跳过 —— 用例不该在一个没有编译器的环境里假装通过。
//
// 为什么必须显式给 `-path`
// ------------------------
// 产物落在 /tmp 里，V 的模块查找路径就是从 `/tmp/...` 往上算的：
//   /tmp/photon-stub-cmd-1234/、/tmp/、/            ← 全都没有 photon
// 再往后才是 `@vmodules`。所以在**干净机器**上，这里的每一条都会报
// `cannot import module "photon.cli" (not found)`。
//
// 它们以前是绿的，靠的是环境里恰好存在的两个巧合之一：
//   * cwd 在仓库内，于是 V 用 cwd 当 lookup_root 找到了 ../photon；
//   * 或者 ~/.vmodules/photon 恰好存在（旧版 SDK 的布局）。
// 两个都不属于「测试环境应该有」的东西 —— 换台机器就变成一片红，
// 而红的原因跟生成器毫无关系，正好是这组用例本来要防的那种「假信号」。
//
// 显式注入一条 `-path` 之后，用例对布局不再有任何要求：它只要求
// 「仓库根就是 photon 模块的根」这一件事，而那正是被测对象的前提。
fn assert_stub_compiles(path string) {
	v_exe := os.find_abs_path_of_executable('v') or {
		eprintln('skip: v executable not found, cannot verify ${path}')
		return
	}
	lookup := '@vlib|@vmodules|${stub_photon_module_root()}'
	out := os.join_path(os.temp_dir(), 'photon-stub-check-${os.getpid()}.so')
	res := os.execute('${v_exe} -enable-globals -no-rsp -show-c-output -path "${lookup}" -shared -o "${out}" "${path}"')
	if res.exit_code != 0 || !os.exists(out) {
		assert false, 'generated stub does not compile: ${path}\ncmd: ${v_exe} -enable-globals -no-rsp -show-c-output -path "${lookup}" -shared -o "${out}" "${path}"\nrc: ${res.exit_code} exists: ${os.exists(out)}\n${res.output}'
	}
}

// stub_photon_module_root 返回「让 `import photon.x` 能解析到本仓库」的查找根。
//
// 仓库根目录里放着 `photon.v`（module photon）与 `v.mod`（name: photon），
// 所以 `import photon.cli` 需要的查找根是仓库根的**父目录** —— V 会拼成
// `<查找根>/photon/cli`。按目录名传进来（而不是硬编码 `/workspace`）是为了
// 让 fork、CI 检出目录、本地多份 checkout 都能用。
fn stub_photon_module_root() string {
	here := os.dir(@DIR)
	name := os.base(here)
	parent := os.dir(here)
	// V 是按 `<root>/<module_path>` 拼的，目录名必须真的等于 `photon`。
	// 改过名的检出目录（比如 photon-2/）没法直接当查找根，这时在临时目录里
	// 放一个叫 `photon` 的符号链接。
	//
	// 这里用链接是安全的，和 downstream_import_test.v 里必须用拷贝不同：
	// 那一条要验证的是「下游能不能解析 photon.x」，而 V 会按 real path 往上
	// 找模块，链接会把 `<root>/pool` 这类本地目录暴露出来，从而掩盖缺陷。
	// 这一条只验证「生成出来的 stub 本身能不能编」，stub 里的 import 全都写成
	// 了 `photon.x`，不依赖本地同名目录，链接不影响结论。
	if name == 'photon' {
		return parent
	}
	link := os.join_path(os.temp_dir(), 'photon-lookup', 'photon')
	os.mkdir_all(os.dir(link)) or {}
	if !os.exists(link) {
		os.symlink(here, link) or { panic(err) }
	}
	return os.dir(link)
}

// ── 表名 ──

fn test_table_name_does_not_double_pluralize() {
	// `make:migration CreatePosts` 早先得到 `create_postss`：命令的入参常写成
	// 复数形式，再无条件补一个 `s` 就成了 `postss`，表名与实体对不上。
	assert table_name_of('Post') == 'posts'
	assert table_name_of('CreatePosts') == 'create_posts'
	assert table_name_of('UserDOB') == 'user_dobs'
	assert table_name_of('Status') == 'status'
}
