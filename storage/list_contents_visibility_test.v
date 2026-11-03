module storage

// list_contents_visibility_test.v - 目录列表与单文件查询必须给出同一个可见性
//
// `permissions` 是可见性的唯一事实来源（除了缓存，没有任何地方记录它）。
// `metadata()` / `visibility()` 都会查这张表，但 `list_contents()` 给每个
// 条目硬写了 `.private_` —— 同一份文件，走单文件接口报 public、走目录
// 列表报 private。上传目录里 public 的资源会被前端当成私有资源处理，
// 而且两条路径都不报错，看起来都「正常返回了元数据」。
import os

fn test_list_contents_reports_cached_visibility() {
	root := '/tmp/photon-storage-list-vis'
	os.rmdir_all(root) or {}
	defer { os.rmdir_all(root) or {} }
	os.mkdir_all(root, os.MkdirParams{}) or {}

	mut a := new_local_adapter(root)
	a.write('pub.txt', 'public one', public_options()) or { assert false }
	a.write('priv.txt', 'private one', default_options()) or { assert false }

	// 单文件接口：public 就是 public
	assert (a.metadata('pub.txt') or { panic('missing') }).visibility == .public_
	assert (a.metadata('priv.txt') or { panic('missing') }).visibility == .private_

	listed := a.list_contents('') or { panic('list failed') }
	mut found := map[string]Visibility{}
	for m in listed {
		found[m.path] = m.visibility
	}
	assert 'pub.txt' in found
	assert 'priv.txt' in found
	// 两条路径对同一个文件必须给同一个答案
	assert found['pub.txt'] == .public_
	assert found['priv.txt'] == .private_
}

fn test_list_contents_tracks_visibility_changes() {
	root := '/tmp/photon-storage-list-vis2'
	os.rmdir_all(root) or {}
	defer { os.rmdir_all(root) or {} }
	os.mkdir_all(root, os.MkdirParams{}) or {}

	mut a := new_local_adapter(root)
	a.write('f.txt', 'x', default_options()) or { assert false }
	a.set_visibility('f.txt', .public_) or { assert false }

	for m in a.list_contents('') or { panic('list failed') } {
		if m.path == 'f.txt' {
			assert m.visibility == .public_
		}
	}

	// 降回 private：列表也必须跟着变
	a.set_visibility('f.txt', .private_) or { assert false }
	for m in a.list_contents('') or { panic('list failed') } {
		if m.path == 'f.txt' {
			assert m.visibility == .private_
		}
	}
}

fn test_list_contents_paths_are_root_relative_and_canonical() {
	root := '/tmp/photon-storage-list-vis3'
	os.rmdir_all(root) or {}
	defer { os.rmdir_all(root) or {} }
	os.mkdir_all(root, os.MkdirParams{}) or {}

	mut a := new_local_adapter(root)
	a.write('top.txt', 'x', default_options()) or { assert false }
	a.write('sub/deep.txt', 'y', default_options()) or { assert false }

	// 同一份文件，不同入参形状必须给出同一个 path，而且这个 path
	// 能直接喂回 metadata() / visibility()
	for dir in ['', '/', '.', './'] {
		for m in a.list_contents(dir) or { panic('list failed') } {
			assert !m.path.starts_with('/')
			assert !m.path.starts_with('./')
		}
	}

	sub := a.list_contents('sub') or { panic('list failed') }
	assert sub.len == 1
	assert sub[0].path == 'sub/deep.txt'
	// 返回的 path 必须能被单文件接口认出来
	assert (a.metadata(sub[0].path) or { panic('metadata rejected listed path') }).path == 'sub/deep.txt'
}
