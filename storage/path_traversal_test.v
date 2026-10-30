module storage

// path_traversal_test.v — root 沙箱的边界
//
// `resolve_path` 只做了字面路径的前缀校验。root 下放一个符号链接就能绕过去：
// 字面路径永远在 root 里，实际读写落在 root 之外。沙箱存在的全部意义就是
// 挡住这种情况。
import os

fn probe_root(name string) string {
	return os.join_path(os.temp_dir(), 'photon_storage_${name}_${os.getpid()}')
}

fn test_dotdot_escape_is_rejected() {
	root := probe_root('dotdot')
	defer {
		os.rmdir_all(root) or {}
	}
	la := new_local_adapter(root)
	mut refused := false
	la.read('../../etc/passwd') or { refused = true }
	assert refused, '`..` must not escape the root'
}

fn test_absolute_path_is_scoped_under_root() {
	root := probe_root('abs')
	defer {
		os.rmdir_all(root) or {}
	}
	mut la := new_local_adapter(root)
	la.write('/nested/file.txt', 'x', StorageWriteOptions{})!
	// 前导 / 被剥掉，落在 root 之内
	assert la.read('nested/file.txt')! == 'x'
	assert os.exists(os.join_path(root, 'nested', 'file.txt'))
}

fn test_symlink_to_outside_file_is_rejected() {
	root := probe_root('symfile')
	outside := os.join_path(os.temp_dir(), 'photon_storage_secret_${os.getpid()}.txt')
	os.mkdir_all(root)!
	os.write_file(outside, 'TOP-SECRET')!
	link := os.join_path(root, 'link')
	if os.exists(link) {
		os.rm('${link}') or {}
	}
	os.symlink(outside, link)!
	defer {
		os.rm(link) or {}
		os.rm(outside) or {}
		os.rmdir_all(root) or {}
	}

	la := new_local_adapter(root)
	mut blocked := false
	data := la.read('link') or {
		blocked = true
		''
	}
	assert blocked, 'a symlink pointing outside the root must be rejected'
	assert !data.contains('TOP-SECRET')
}

fn test_symlink_to_outside_directory_is_rejected() {
	root := probe_root('symdir')
	outdir := os.join_path(os.temp_dir(), 'photon_storage_outdir_${os.getpid()}')
	os.mkdir_all(root)!
	os.mkdir_all(outdir)!
	os.write_file(os.join_path(outdir, 'leak.txt'), 'LEAK')!
	link := os.join_path(root, 'out')
	if os.exists(link) {
		os.rm(link) or {}
	}
	os.symlink(outdir, link)!
	defer {
		os.rm(link) or {}
		os.rmdir_all(outdir) or {}
		os.rmdir_all(root) or {}
	}

	la := new_local_adapter(root)
	mut blocked := false
	la.read('out/leak.txt') or { blocked = true }
	assert blocked, 'a symlinked directory must not become a read path'
}

fn test_symlink_inside_root_still_works() {
	root := probe_root('symok')
	defer {
		os.rmdir_all(root) or {}
	}
	mut la := new_local_adapter(root)
	la.write('real.txt', 'inside', StorageWriteOptions{})!
	os.symlink(os.join_path(root, 'real.txt'), os.join_path(root, 'alias'))!
	assert la.read('alias')! == 'inside', 'symlinks that stay inside the root must keep working'
}

fn test_write_creates_missing_root() {
	root := probe_root('mkdir')
	defer {
		os.rmdir_all(root) or {}
	}
	assert !os.exists(root)
	mut la := new_local_adapter(root)
	la.write('a.txt', 'ok', StorageWriteOptions{})!
	assert la.read('a.txt')! == 'ok'
}
