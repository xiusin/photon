module strutil

// module_identity_test.v — 仓库里不许再出现「一个目录两个模块名」
//
// 为什么这条用例存在
// ------------------
// `photon.v` 声明 `module photon`，仓库根目录就是 photon 模块的目录。于是任何
// 顶层目录 `X/` 会同时被注册成两个名字：
//
//     import X          → <root>/X
//     import photon.X   → <root>/X     （同一个目录，两张模块表）
//
// 两条路径同时被加载时，V 会解析到 `photon.X` 那份空的函数表，报出来的不是
// 「找不到模块」，而是一串 `unknown function: X.foo` —— 离真因很远。
// `support/` 曾经就是这个形状，任何 `import photon.web` 的下游用户都编不过。
//
// 现在的规矩很简单：顶层目录名不许是 `photon.<dir>` 能拼出来的名字，
// 也就是不许叫 `photon` 以外任何会与 `photon.X` 撞车的名字 —— 而
// `photon.X` 对**任何**顶层目录都成立。所以真正的约束是：
// **任何被 `import photon.<x>` 引用的模块，都不能同时作为顶层目录存在。**
//
// 这条用例直接扫仓库：只要某个顶层目录里有一份 `module <dir名>` 的 .v 文件，
// 且这个目录不是 `photon` 自己，就检查没有任何源码 `import photon.<dir名>`。
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

fn test_no_top_level_module_is_reachable_as_photon_dot_x() {
	mut offenders := []string{}
	for dir in module_dirs() {
		if dir == 'photon' {
			continue
		}
		// 目录本身得真的是一个模块（有 `module <dir>` 的 .v）
		if !declares_module(dir, dir) {
			continue
		}
		needle := 'import photon.' + dir
		for file in all_v_files() {
			raw := os.read_file(file) or { continue }
			content := strip_string_literals(raw)
			for line in content.split_into_lines() {
				trimmed := line.trim_space()
				if !trimmed.starts_with(needle) {
					continue
				}
				if trimmed.len > needle.len && is_ident_byte(trimmed[needle.len]) {
					continue
				}
				offenders << '${file}: ${trimmed}  (目录 ${dir}/ 已占用模块名 `photon.${dir}`)'
			}
		}
	}
	assert offenders.len == 0, 'found ${offenders.len} dual-identity import(s):\n' +
		offenders.join('\n')
}

fn is_ident_byte(b u8) bool {
	return (b >= `a` && b <= `z`) || (b >= `A` && b <= `Z`) || (b >= `0` && b <= `9`) || b == `_`
}

// test_known_modules_exist 顶住「模块被误改名/误删」这类静默回归：
// 这几条是公开 API 的一部分，目录一改用户就编不过。
fn test_known_modules_exist() {
	for name in ['strutil', 'pageable', 'core', 'config', 'orm', 'web', 'cache', 'logger',
		'security', 'cli', 'pool', 'locking', 'queue', 'ticker', 'storage', 'mailer',
		'apidoc', 'health', 'metrics', 'retry', 'async', 'http', 'tracing', 'photon_i18n'] {
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
