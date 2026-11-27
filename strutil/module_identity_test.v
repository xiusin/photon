module strutil

// module_identity_test.v — 模块名的两条规矩
//
// 一、`support/` 不许复活
// ----------------------
// `photon.v` 声明 `module photon`，仓库根目录就是 photon 模块的目录。过去
// `support/` 同时被注册成 `support` 与 `photon.support` 两个名字，在**不带
// -path 的仓库内视角**下会解析到后者那份空的函数表，报一串离真因很远的
// `unknown function: support.snake`。改名 `strutil/` / `pageable/` 后消失。
//
// 二、与 vlib 重名的模块必须用全限定名
// ----------------------------------
// `cli/`、`orm/`、`pool/` 与 vlib 自带模块重名。源码里写裸 `import pool`
// 时，仓库内解析到本仓库的 pool/，下游写 `import photon.web` 却解析到
// vlib/pool（没有 Pool / PoolStats）—— 用户什么都没改，却在自己的构建里
// 收到一堆没碰过的文件里的 unknown type。
//
// 所以这些模块的**所有源码引用**（含 example/verify）一律写
// `import photon.<dir>`。混用裸名与全限定名会让同一目录注册两张模块表，
// 正是双重身份的触发条件：verify 里 `import pool` + 框架里
// `import photon.pool` 曾让 `photon.pool.Pool` 整个查不到。上一轮这里
// 有一条相反的禁令（禁止任何 `import photon.<dir>`），理由是「双重身份」。
// 复核后发现那个结论只在「不带 -path」时成立：`run-tests.sh` 现在默认注入
// 一个把仓库挂成 `photon` 的查找根，全仓库统一全限定名后两张模块表不再
// 打架，双重身份不再触发。详见 strutil/downstream_import_test.v。
//
// 这条用例负责：撞 vlib 名的模块不许出现裸 import；`support/` 不许复活；
// 公开模块名单不许被误改名；解析根机制不许被悄悄删掉。
import os
import strings

const root = os.dir(@DIR)

// module_dirs 列出仓库根下的顶层模块目录（含 v.mod 的目录就是模块根）
fn module_dirs() []string {
	mut dirs := []string{}
	for entry in os.ls(root) or { []string{} } {
		if entry.starts_with('.') {
			continue
		}
		full := os.join_path(root, entry)
		if !os.is_dir(full) {
			continue
		}
		// 只认真正装着 `<module>.v` 或任意 `module <dir>` 文件的目录
		if entry in ['vendor', 'scripts', 'docs', 'wiki', '.arts', '.codegraph', '.trae',
			'.workbuddy', '.github', '.photon-test-bin', 'systemd', 'apidoc'] {
			// apidoc 是真模块，下面单独判断
			if entry != 'apidoc' {
				continue
			}
		}
		dirs << entry
	}
	return dirs
}

// declares_module reports whether dir contains a .v file declaring `module <name>`.
fn declares_module(dir string, name string) bool {
	want := 'module ' + name
	for f in os.ls(os.join_path(root, dir)) or { []string{} } {
		if !f.ends_with('.v') {
			continue
		}
		content := os.read_file(os.join_path(root, dir, f)) or { continue }
		for line in content.split_into_lines() {
			trimmed := line.trim_space()
			if trimmed == want {
				return true
			}
			// 只看文件头几行的有效声明，遇到非空非注释的行就停
			if trimmed != '' && !trimmed.starts_with('//') {
				break
			}
		}
	}
	return false
}

// v_file_acc holds the walk results.
// 为什么用指针而不是 `fn [mut acc]`：V 0.5.2 里 `[mut x]` 捕获的是副本 ——
// 闭包内部的修改在外部看不见（最小复现：`mut c := 0; f := fn [mut c] () { c++ }`
// 执行两次后外部仍是 0）。第一版就是这么写的，用例恒过，因为收集到的永远
// 是空表。用指针绕开。
struct VFileAcc {
mut:
	paths []string
}

fn collect_v_file(path string, acc &VFileAcc) {
	if path.contains('/vendor/') || path.contains('/.git/') || path.contains('/.photon-test-bin/')
		|| path.contains('/.vmodules/') {
		return
	}
	if path.ends_with('.v') {
		unsafe {
			mut a := acc
			a.paths << path
		}
	}
}

// all_v_files 递归收集仓库内的 .v 源码（跳过 vendor 与测试用临时目录）
fn all_v_files() []string {
	acc := &VFileAcc{}
	os.walk(root, fn [acc] (path string) {
		collect_v_file(path, acc)
	})
	return acc.paths
}

// strip_string_literals 把源码里的字符串字面量内容抹成空，只留下代码骨架。
//
// 为什么必须抹：`cli/make_commands.v` 里的生成器把 `import photon.cli` 写在
// **字符串**里（那是它产出的代码），而字符串里的这一行也是顶格的。不抹掉就会
// 把「生成器的产物」当成「本仓库的依赖」，报出一个不存在的违规。
fn strip_string_literals(src string) string {
	mut out := strings.Builder{}
	mut quote := u8(0)
	mut i := 0
	for i < src.len {
		c := src[i]
		if quote != 0 {
			if c == `\\` {
				i += 2
				continue
			}
			if c == quote {
				quote = 0
				out.write_u8(c)
			} else {
				// 保留换行，行号/行边界不变
				if c == `\n` {
					out.write_u8(c)
				}
			}
			i++
			continue
		}
		if c == `'` || c == `"` || c == u8(96) {
			quote = c
		}
		out.write_u8(c)
		i++
	}
	return out.str()
}

// vlib_colliding_modules 是与 vlib 自带模块重名的顶层目录。V 的模块查找在
// 下游视角下会优先命中 vlib，所以对它们的引用必须写全限定名。
const vlib_colliding_modules = ['cli', 'orm', 'pool']

fn test_vlib_colliding_modules_use_qualified_imports() {
	mut offenders := []string{}
	for dir in vlib_colliding_modules {
		needle := 'import ' + dir
		for file in all_v_files() {
			raw := os.read_file(file) or { continue }
			content := strip_string_literals(raw)
			for line in content.split_into_lines() {
				trimmed := line.trim_space()
				if trimmed != needle {
					continue
				}
				offenders << '${file}: ${trimmed}  (模块 `${dir}` 与 vlib 重名，请写 `import photon.${dir}`)'
			}
		}
	}
	assert offenders.len == 0, 'found ${offenders.len} bare import(s) of a vlib-colliding module:\n' +
		offenders.join('\n')
}

// test_run_tests_provides_photon_lookup 顶住「解析根被悄悄删掉」。
// 没有它，`import photon.pool` 在仓库内又会变回 cannot import，于是有人
// 会顺手把全限定名退回裸名 —— 下游随即再坏一次。
fn test_run_tests_provides_photon_lookup() {
	script := os.read_file(os.join_path(root, 'scripts', 'run-tests.sh')) or {
		assert false, 'cannot read scripts/run-tests.sh'
		return
	}
	assert script.contains('-path @vlib|@vmodules|') && script.contains('photon-lookup.sh'), 'run-tests.sh 不再注入 photon 查找根。' +
		'请恢复对 scripts/photon-lookup.sh 的调用，否则 `import photon.x` 在仓库内无法解析。'
	assert os.exists(os.join_path(root, 'scripts', 'photon-lookup.sh')), 'scripts/photon-lookup.sh 不见了'
}

// test_known_modules_exist 顶住「模块被误改名/误删」这类静默回归：
// 这几条是公开 API 的一部分，目录一改用户就编不过。
fn test_known_modules_exist() {
	for name in ['strutil', 'pageable', 'core', 'config', 'orm', 'web', 'cache', 'logger',
		'security', 'cli', 'pool', 'locking', 'queue', 'ticker', 'storage', 'mailer',
		'apidoc', 'health', 'metrics', 'retry', 'async', 'http', 'tracing'] {
		assert declares_module(name, name), 'module `${name}` is missing or renamed — ' +
			'it is part of the public API (import ${name})'
	}
}

// test_support_is_not_a_module 名字 `support` 不许复活：它同时是
// `photon.support`，正是双重身份的入口。
fn test_support_directory_is_gone() {
	assert !os.exists(os.join_path(root, 'support')), 'support/ is back — it collides with ' +
		'`import photon.support` and breaks every downstream `import photon.web`'
}
