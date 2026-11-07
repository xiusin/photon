module strutil

// downstream_import_test.v — 「仓库内」与「下游」两套模块解析都必须成立
//
// 这一轮修掉的东西
// ----------------
// 上一轮（130e35b）在这里钉了三条「已知编不过」的断言，结论是「这版修不动」：
//
//     裸名 `import pool`      → 仓库内绿，下游红
//     `import photon.pool`    → 下游绿，仓库内红
//
// 那张表的第二行是**错的**，错在把「仓库内」当成一个不可改变的物理视角。
// 实际上「仓库内红」只是因为 `run-tests.sh` 不带 `-path`：V 按
// `<查找根>/<module_path>` 拼 `import photon.pool`，而工作区叫 `/workspace`
// 不叫 `photon`，于是找不到。给编译命令一个把仓库挂成 `photon` 的查找根，
// `import photon.pool` 在仓库内也能解析 —— 同一个仓库里的
// `cli/make_stub_compiles_test.v:stub_photon_module_root()` 早就这么做了。
//
// 另一半真缺陷是裸 `import pool` / `import orm` / `import cli` 与 vlib 自带
// 模块重名：下游写 `import photon.web` 时它们落到 vlib，报出一堆用户没碰过的
// 文件里的 unknown type。现在框架源码统一用全限定名 `photon.x`，
// `pool/` 也不再 import orm（DbPool 只需要一个 driver 标签）。
//
// 所以这三条断言从「记录差异」升级成「要求通过」。
//
// 为什么必须用拷贝
// ----------------
// 下游视角要模拟真实安装布局。用符号链接时，`<lookup>/photon/web/x.v` 的
// real path 仍是 `/workspace/web/x.v`，V 顺着 `/workspace` 往上找，会看见
// 本仓库的 `pool/`、`orm/` —— 缺陷被链接本身掩盖。同一份代码，链接进来绿、
// 拷进去红。真实安装一定是拷贝，所以这里必须 `cp -a`。
import os

fn downstream_v() string {
	return os.find_abs_path_of_executable('v') or { '' }
}

// build_downstream_tree 在仓库外侧建一份真实安装布局，返回查找根。
// 一次拷贝、多处复用：五个入口各编一次已经不便宜，每次再 cp 整仓库会把
// 用例推过 30s 预算（那会被误报成「用例挂死」，其实只是编译慢）。
fn build_downstream_tree(base string) (string, string) {
	lookup := os.join_path(base, 'lookup')
	app := os.join_path(base, 'app')
	os.mkdir_all(lookup) or {}
	os.mkdir_all(app) or {}
	src_root := os.dir(@DIR)
	link := os.join_path(lookup, 'photon')
	res := os.execute('cp -a "${src_root}/." "${link}/"')
	if res.exit_code != 0 {
		return '', 'cannot copy repo: ${res.output}'
	}
	// `locking/redis_lock_client.v` 用 `import xiusin.vredis`，它是 vendor 进
	// 仓库的第三方模块。真实安装里它应该在模块查找根上，这里补上，否则
	// `import photon.web` 会因为缺 vendor 而假红，掩盖掉真正要验的东西。
	vendor_src := os.join_path(src_root, 'vendor', 'modules', 'xiusin', 'vredis')
	if os.is_dir(vendor_src) {
		vendor_dst := os.join_path(lookup, 'xiusin', 'vredis')
		os.mkdir_all(os.dir(vendor_dst)) or {}
		os.execute('cp -a "${vendor_src}/." "${vendor_dst}/"')
	}
	return lookup, ''
}

// compile_downstream_import 编一个只含这些 import 的最小 main。
//
// 「能不能解析模块」用一次编译就能验，不必为每个入口各编一遍整棵依赖树。
// 把 photon.web 与 photon 合在同一组：两者都要编 web 依赖树，分开编等于
// 把同一份工作付两次，会把这条用例推过 30s 运行预算（那会被误报成挂死）。
fn compile_downstream_import(v_exe string, lookup string, app string, mods []string, tag string) (bool, string) {
	mut src := 'module main\n\n'
	for m in mods {
		src += 'import ${m}\n'
	}
	src += '\nfn main() {\n\tprintln("ok")\n}\n'
	main_file := os.join_path(app, 'main-${tag}.v')
	os.write_file(main_file, src) or { return false, 'cannot write ${main_file}' }
	out := os.join_path(app, 'app-${tag}.bin')
	res := os.execute('${v_exe} -enable-globals -no-rsp -path "@vlib|@vmodules|${lookup}" -o "${out}" "${main_file}"')
	produced := os.exists(out)
	os.rm(out) or {}
	return res.exit_code == 0 && produced, res.output
}

// test_downstream_public_entrypoints_compile 把「公开入口必须能编」写成一条
// 正向要求。任何一条退回裸 import、或 pool/ 重新 import orm、或 photon.v
// 重新加回泛型 re-export，这里都会红。
//
// 五个入口共用一份拷贝，web 与 photon 合编一次压住运行时间。找不到编译器
// 就跳过并打印原因，不在没有编译器的环境里假装通过。
fn test_downstream_public_entrypoints_compile() {
	v_exe := downstream_v()
	if v_exe == '' {
		eprintln('skip: v not found')
		return
	}
	base := os.join_path(os.temp_dir(), 'photon-downstream-${os.getpid()}')
	os.rmdir_all(base) or {}
	defer {
		os.rmdir_all(base) or {}
	}
	lookup, err := build_downstream_tree(base)
	assert err == '', err
	app := os.join_path(base, 'app')

	groups := [
		['photon.pool'],
		['photon.orm'],
		['photon.cli'],
		['photon.web', 'photon'],
	]
	mut gi := 0
	for mods in groups {
		ok, out := compile_downstream_import(v_exe, lookup, app, mods, 'g${gi}')
		assert ok, '下游 `import ${mods.join(" / ")}` 编不过：\n${out}'
		gi++
	}
}

// test_repo_side_import_still_works 反面：仓库内那套解析也必须保持可用。
//
// 关键不同：这里**带 -path**（指向把本仓库挂成 `photon` 的查找根），
// 正是 `run-tests.sh` 现在默认注入的那一个。上一轮这条不带 -path，
// 于是只能守「别把 import pool 改成 photon.pool」—— 那是在守一个
// 自我设限，不是守正确性。
fn test_repo_side_import_still_works() {
	v_exe := downstream_v()
	if v_exe == '' {
		eprintln('skip: v not found')
		return
	}
	root := os.dir(@DIR)
	// 和 cli/make_stub_compiles_test.v:stub_photon_module_root() 同一套做法：
	// 目录名恰为 photon 用父目录，否则在临时目录放一个叫 photon 的链接。
	// 这里用链接是安全的 —— 只验证「仓库内能解析 photon.x」，不需要模拟
	// 下游安装布局。
	lookup := os.join_path(os.temp_dir(), 'photon-repo-lookup-${os.getpid()}')
	os.mkdir_all(lookup) or {}
	link := os.join_path(lookup, 'photon')
	if !os.exists(link) {
		os.symlink(root, link) or { panic(err) }
	}
	defer {
		os.rm(link) or {}
		os.rmdir_all(lookup) or {}
	}
	out := os.join_path(os.temp_dir(), 'photon-repo-side-${os.getpid()}.so')
	res := os.execute('${v_exe} -enable-globals -no-rsp -path "@vlib|@vmodules|${lookup}" -shared -o "${out}" "${os.join_path(root, "web")}"')
	produced := os.exists(out)
	os.rm(out) or {}
	assert res.exit_code == 0 && produced, 'web/ 在仓库内编不过了：\n${res.output}'
}
