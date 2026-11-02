module web

// resource_handler_containment_test.v — 静态资源 location 的边界。
//
// `add_mapping(pattern, location)` 的承诺是「只从 location 里取文件」。
// 这句承诺原先没有任何代码在兑现：`os.join_path` 只是字符串拼接，
// 不解释 `..`，也不管符号链接。于是：
//
//   GET /static/../secret.txt   =>  /srv/public/../secret.txt  =  /srv/secret.txt
//   public/link -> /etc/passwd  =>  字面路径在 public 内，实际读到的是 /etc/passwd
//
// 对静态目录（用户上传、构建产物、可写挂载点）来说，这是最常见的逃逸路径。

import os

fn rh_traversal_fixture() string {
	base := os.join_path(os.temp_dir(), 'photon_rh_containment')
	os.rmdir_all(base) or {}
	os.mkdir_all(os.join_path(base, 'public', 'sub')) or {}
	os.write_file(os.join_path(base, 'secret.txt'), 'TOP-SECRET') or {}
	os.write_file(os.join_path(base, 'public', 'sub', 'ok.css'), 'ok') or {}
	return base
}

fn test_dotdot_cannot_escape_location() {
	base := rh_traversal_fixture()
	defer {
		os.rmdir_all(base) or {}
	}
	mut r := new_resource_handler_registry()
	r.add_mapping('/static/**', os.join_path(base, 'public'))

	for p in ['/static/../secret.txt', '/static/sub/../../secret.txt', '/static/./../secret.txt',
		'/static/%2e%2e/secret.txt'] {
		assert r.resolve(p) == none, '${p} must not resolve outside the location'
	}
}

fn test_symlink_inside_location_cannot_escape() {
	base := rh_traversal_fixture()
	defer {
		os.rmdir_all(base) or {}
	}
	link := os.join_path(base, 'public', 'link.txt')
	os.symlink(os.join_path(base, 'secret.txt'), link) or { return }
	mut r := new_resource_handler_registry()
	r.add_mapping('/static/**', os.join_path(base, 'public'))
	assert r.resolve('/static/link.txt') == none, 'symlink must not be served'
}

fn test_dotdot_location_config_is_normalized() {
	base := rh_traversal_fixture()
	defer {
		os.rmdir_all(base) or {}
	}
	// location 来自配置，常常是拼出来的，带 `..` 很正常
	mut r := new_resource_handler_registry()
	r.add_mapping('/assets/**', '${base}/public/../public')
	found := r.resolve('/assets/sub/ok.css') or { '' }
	assert found != '', 'normalized location should still serve files inside itself'
	assert !found.contains('/../'), 'returned path must be normalized: ${found}'
}

fn test_normal_url_forms_still_resolve() {
	base := rh_traversal_fixture()
	defer {
		os.rmdir_all(base) or {}
	}
	mut r := new_resource_handler_registry()
	r.add_mapping('/static/**', os.join_path(base, 'public'))
	for p in ['/static/sub/ok.css', '/static/./sub/ok.css', '/static//sub/ok.css',
		'/static/sub/../sub/ok.css'] {
		assert r.resolve(p) or { '' } != '', '${p} is a legitimate path and must resolve'
	}
}

fn test_markdown_negotiation_also_stays_inside() {
	base := os.join_path(os.temp_dir(), 'photon_rh_neg')
	os.rmdir_all(base) or {}
	os.mkdir_all(os.join_path(base, 'public')) or {}
	os.write_file(os.join_path(base, 'outside.md'), 'ESCAPED') or {}
	defer {
		os.rmdir_all(base) or {}
	}
	mut r := new_resource_handler_registry()
	r.add_mapping('/docs/**', os.join_path(base, 'public'))
	r.set_compression(enable_markdown_negotiation: true)
	assert r.resolve_with_negotiation('/docs/../outside', 'text/markdown') == none, 'negotiation must not escape the location'
}
