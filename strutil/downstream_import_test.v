module strutil

// downstream_import_test.v — 「仓库内」与「下游」两套模块解析必须一致
//
// 这一轮想修的东西，最后没能修，但查出了它的边界，所以把边界钉成用例。
//
// 现象
// ----
// `web/request_pool.v` 里是裸 `import pool`，`pool/db_pool.v` 里是裸 `import orm`。
// 在仓库内编译（`v test web/`）时，V 先看导入方所在项目，于是解析到本仓库的
// `pool/` 与 `orm/` —— 一切正常。
//
// 但下游用户是在**自己的工程**里写下 `import photon.web` 的。这条路径下，
// `web/request_pool.v` 的裸 `import pool` 落到 vlib 自带的 `pool`
// （里面只有 `ConnectionPool`，没有 `Pool` / `PoolStats`），于是：
//
//     unknown type `pool.PoolStats`
//     unknown type `pool.Pool`
//     …
//
// 报错出现在 `web/request_pool.v` 里，而用户根本没碰过这个文件。
//
// 为什么修不动（这一步是这轮真正的产出）
// --------------------------------------
// 直觉上的修法是改成 `import photon.pool`。但 V 0.5.2 的模块查找里，
// `-path` 给的那些根**优先于**导入方所在项目。仓库内的测试命令
// （`VFLAGS="-enable-globals" sh scripts/run-tests.sh`）不带 `-path`，
// 于是 `import photon.pool` 在仓库内一律报 `cannot import module "photon.pool"`。
//
// 两种写法各让一方编不过：
//
//     裸名 `import pool`      → 仓库内绿，下游红
//     `import photon.pool`    → 下游绿，仓库内红
//
// 而这台机器上连 `~/.vmodules/photon` 都没有，两边都满足不了。
// 所以这轮**没有**动那两行 import —— 改一半比不改更糟：那会让 `run-tests.sh`
// 从「全绿」变成「web 整片红」，而红的理由跟被测代码毫无关系。
//
// 这条用例负责把这个事实钉住，并在条件允许时自动升级
// ---------------------------------------------------------------------
// 一旦构建侧补齐了「仓库内也能解析 `photon.x`」的前置（例如 `run-tests.sh`
// 统一带上 `-path <仓库父目录>`），下面两条断言会从「记录差异」变成
// 「要求通过」，并在那一刻变红提醒把它改成普通的通过断言。
import os

fn downstream_v() string {
	return os.find_abs_path_of_executable('v') or { '' }
}

// downstream_can_compile 在仓库**外侧**建一个最小工程，用真实安装布局编一次。
//
// 关键：cwd 在临时目录，只靠 `-path` 里的 `photon` 符号链接找模块 ——
// 这就是「用户机器上」的解析环境。仓库内那种「本地目录优先」的便利全部消失。
fn downstream_can_compile(import_line string) (bool, string) {
	v_exe := downstream_v()
	if v_exe == '' {
		return true, 'skipped: v not found'
	}
	base := os.join_path(os.temp_dir(), 'photon-downstream-${os.getpid()}')
	os.rmdir_all(base) or {}
	lookup := os.join_path(base, 'lookup')
	app := os.join_path(base, 'app')
	os.mkdir_all(lookup) or {}
	os.mkdir_all(app) or {}
	defer {
		os.rmdir_all(base) or {}
	}
	// 必须**拷贝**一份，不能用符号链接。
	//
	// 用符号链接时，`/tmp/x/lookup/photon/web/request_pool.v` 的 real path
	// 仍然是 `/workspace/web/request_pool.v`，V 于是按 `/workspace` 往上找，
	// 恰好看见 `/workspace/pool` —— 裸 `import pool` 侥幸成功，缺陷被掩盖。
	// 这是我在这一轮里被误导了两次的地方：同一份代码，链接进来是绿的，
	// 拷进去是红的。真实的安装/发布一定是拷贝。
	src_root := os.dir(@DIR)
	link := os.join_path(lookup, 'photon')
	cp := os.execute('cp -a "${src_root}/." "${link}/"')
	if cp.exit_code != 0 {
		return true, 'skipped: cannot copy repo: ${cp.output}'
	}

	src := 'module main\n\n${import_line}\n\nfn main() {\n\tprintln("ok")\n}\n'
	main_file := os.join_path(app, 'main.v')
	os.write_file(main_file, src) or { return false, 'cannot write ${main_file}' }
	out := os.join_path(app, 'app.bin')
	res := os.execute('${v_exe} -enable-globals -no-rsp -path "@vlib|@vmodules|${lookup}" -o "${out}" "${main_file}"')
	produced := os.exists(out)
	os.rm(out) or {}
	return res.exit_code == 0 && produced, res.output
}

// test_downstream_import_photon_web_is_known_to_fail 记录当前差异。
//
// 如果这条用例红了，说明「下游 `import photon.web` 能编了」——
// 那是好消息，请把本函数改成 `assert ok`，并把上面的注释删掉。
fn test_downstream_import_photon_web_is_known_to_fail() {
	ok, out := downstream_can_compile('import photon.web')
	if ok {
		assert false, '下游 `import photon.web` 现在能编了！这是好消息 —— ' +
			'请把本用例改成 assert ok，并删掉 downstream_import_test.v 里「修不动」那段说明。'
	}
	// 失败必须还是那个原因，不能因为别的东西坏了而「恰好红」
	assert out.contains('pool.') || out.contains('unknown type'), '下游失败原因变了，' +
		'不再是 `pool.*` 解析问题，请重新读一遍这个文件：\n${out}'
}

// test_downstream_import_photon_pool_is_known_to_fail 同上，守 `pool/db_pool.v`
// 里裸 `import orm` 那条（vlib 也有 `orm`）。
fn test_downstream_import_photon_pool_is_known_to_fail() {
	ok, out := downstream_can_compile('import photon.pool')
	if ok {
		assert false, '下游 `import photon.pool` 现在能编了！请改成 assert ok。'
	}
	assert out.contains('orm.') || out.contains('unknown type'), '下游失败原因变了，' +
		'不再是 `orm.*` 解析问题：\n${out}'
}

// test_repo_side_import_still_works 反面：仓库内那套解析必须保持可用。
//
// 这条和上面两条是一对。哪天有人「顺手」把 `web/request_pool.v` 的
// `import pool` 改成 `import photon.pool`，这里立刻红 —— 因为 `run-tests.sh`
// 不带 `-path`，仓库内解析不到 `photon.pool`。它挡的是「改一半」。
fn test_repo_side_import_still_works() {
	v_exe := downstream_v()
	if v_exe == '' {
		eprintln('skip: v not found')
		return
	}
	root := os.dir(@DIR)
	out := os.join_path(os.temp_dir(), 'photon-repo-side-${os.getpid()}.so')
	res := os.execute('${v_exe} -enable-globals -no-rsp -shared -o "${out}" "${os.join_path(root, "web")}"')
	produced := os.exists(out)
	os.rm(out) or {}
	assert res.exit_code == 0 && produced, 'web/ 在仓库内编不过了。' +
		'如果是因为把 `import pool` 改成了 `import photon.pool`，请回退那处改动 —— ' +
		'`run-tests.sh` 不带 `-path`，仓库内解析不到 `photon.x`：\n${res.output}'
}
