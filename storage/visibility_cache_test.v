module storage

// visibility_cache_test.v - 权限覆盖缓存的生命周期
//
// 权限覆盖（`permissions` map）按「调用方给的相对路径」索引，跟实际文件
// 之间只靠一次显式的 set_visibility 建立关系。文件被删掉、被搬走之后，
// 这条记录如果留在原地，就会套到下一个同名文件上 —— 而它看起来完全正常。
import os

fn test_delete_drops_visibility_override() {
	root := '/tmp/photon-storage-vis-del'
	os.rmdir_all(root) or {}
	defer { os.rmdir_all(root) or {} }
	os.mkdir_all(root, os.MkdirParams{}) or {}

	mut a := new_local_adapter(root)
	a.write('k.txt', 'one', public_options()) or { assert false }
	assert (a.visibility('k.txt') or { Visibility.private_ }) == .public_

	a.delete('k.txt') or { assert false }

	// 同名文件重建：不该继承上一个文件的 public
	a.write('k.txt', 'two', default_options()) or { assert false }
	assert (a.visibility('k.txt') or { Visibility.public_ }) == .private_
}

fn test_forget_permissions_is_idempotent() {
	root := '/tmp/photon-storage-vis-del2'
	os.rmdir_all(root) or {}
	defer { os.rmdir_all(root) or {} }
	os.mkdir_all(root, os.MkdirParams{}) or {}

	mut a := new_local_adapter(root)
	a.write('k.txt', 'x', public_options()) or { assert false }
	// 绕过 adapter 直接删文件，缓存记录仍在 —— forget 必须能清掉它
	os.rm(os.join_path(root, 'k.txt')) or {}
	a.forget_permissions('k.txt') or { assert false }
	a.forget_permissions('k.txt') or { assert false }
	a.write('k.txt', 'y', default_options()) or { assert false }
	assert (a.visibility('k.txt') or { Visibility.public_ }) == .private_
}

fn test_move_carries_visibility_override() {
	root := '/tmp/photon-storage-vis-mv'
	os.rmdir_all(root) or {}
	defer { os.rmdir_all(root) or {} }
	os.mkdir_all(root, os.MkdirParams{}) or {}

	mut a := new_local_adapter(root)
	a.write('src.txt', 'payload', public_options()) or { assert false }
	a.move('src.txt', 'dst.txt') or { assert false }

	// 新路径继承旧可见性；旧路径不能留后门
	assert (a.visibility('dst.txt') or { Visibility.private_ }) == .public_
	assert (a.visibility('src.txt') or { Visibility.public_ }) == .private_
}

fn test_write_sets_file_mode_by_visibility() {
	root := '/tmp/photon-storage-vis-mode'
	os.rmdir_all(root) or {}
	defer { os.rmdir_all(root) or {} }
	os.mkdir_all(root, os.MkdirParams{}) or {}

	mut a := new_local_adapter(root)
	a.write('pub.txt', 'x', public_options()) or { assert false }
	a.write('priv.txt', 'x', default_options()) or { assert false }

	pub_path := os.join_path(root, 'pub.txt')
	priv_path := os.join_path(root, 'priv.txt')
	assert os.exists(pub_path)
	assert os.exists(priv_path)
	// 0644 / 0600 —— 只比权限位，忽略文件类型位
	assert int(os.stat(pub_path)!.mode) & 0o777 == 0o644
	assert int(os.stat(priv_path)!.mode) & 0o777 == 0o600
}
