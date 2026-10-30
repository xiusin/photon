module storage

// local_adapter.v - Local Filesystem Adapter
//
// Implements the Storage interface for the local filesystem.
// Supports root directory scoping, visibility via file permissions,
// directory traversal, and all common file operations.
import os
import sync

// max_permissions bounds the permissions cache to prevent unbounded
// memory growth from unique file paths. When exceeded, oldest entries
// are evicted (FIFO approximation of LRU).
const max_permissions = 10000

// LocalAdapter provides filesystem access scoped to a root directory
pub struct LocalAdapter {
pub:
	root string // root directory path
pub mut:
	permissions       map[string]string // path → visibility override
	perm_access_order []string          // tracks insertion order for eviction
mut:
	mu sync.RwMutex
}

// new_local_adapter creates a LocalAdapter with the given root directory
pub fn new_local_adapter(root string) &LocalAdapter {
	return &LocalAdapter{
		root:              root
		permissions:       map[string]string{}
		perm_access_order: []string{}
	}
}

// adapter_name returns the adapter type
pub fn (la &LocalAdapter) adapter_name() string {
	return 'local'
}

// resolve_path joins the root with the given path, resolves .. and . segments,
// and verifies the result stays within the configured root directory.
fn (la &LocalAdapter) resolve_path(path string) !string {
	clean := path.trim_left('/')

	// Join root and clean path
	full := if la.root.ends_with('/') {
		la.root + clean
	} else {
		'${la.root}/${clean}'
	}

	// Resolve . and .. segments manually
	resolved := normalize_path(full)

	// Normalize root for comparison
	root_resolved := normalize_path(la.root)

	// Verify path containment: resolved must equal root or be a subdirectory
	if resolved != root_resolved && !resolved.starts_with(root_resolved + '/') {
		return error('path traversal denied: "${path}" escapes root directory')
	}

	// 纯字符串前缀校验挡不住符号链接：root 下的一个 `link -> /etc`，
	// 字面路径永远在 root 里，实际读写却落在 root 之外。
	// 所以再问一次文件系统：最深的那个**已存在**的路径分量，它解析后的
	// 真实位置也必须落在真实 root 之内。
	//
	// 只检查已存在的分量是有意的：write('a/b/c.txt') 时 c.txt 往往还不存在，
	// real_path 对不存在的路径会原样返回，那种情况下检查它自己的前缀就够了。
	// root 本身可能还不存在（首次写入时），那就先建出来 —— 只有建出来
	// real_path 才能给出一个能用来比对的规范路径。
	if !os.exists(root_resolved) {
		os.mkdir_all(root_resolved) or {
			return error('failed to create root directory "${root_resolved}": ${err}')
		}
	}
	real_root := os.real_path(root_resolved)
	if !is_within_real_root(resolved, real_root) {
		return error('path traversal denied: "${path}" resolves outside root directory')
	}

	return resolved
}

// is_within_real_root 沿路径向上找到最深的已存在的祖先，用 real_path 解掉
// 符号链接后再与真实 root 比较。
fn is_within_real_root(resolved string, real_root string) bool {
	mut probe := resolved
	for {
		if os.exists(probe) {
			real_probe := os.real_path(probe)
			return real_probe == real_root || real_probe.starts_with(real_root + '/')
		}
		parent := os.dir(probe)
		if parent == probe || parent.len == 0 {
			// 一路到根都不存在：没有可解析的链接，按字面路径判断
			return true
		}
		probe = parent
	}
	return true
}

// normalize_path resolves . and .. path segments to produce a canonical path
fn normalize_path(path string) string {
	mut segments := []string{}
	for seg in path.split('/') {
		if seg == '' || seg == '.' {
			continue
		}
		if seg == '..' {
			if segments.len > 0 {
				segments.delete(segments.len - 1)
			}
			continue
		}
		segments << seg
	}

	mut result := '/'
	for i, seg in segments {
		if i > 0 {
			result += '/'
		}
		result += seg
	}

	return result
}

// ============================================================
// Basic CRUD
// ============================================================

// read reads a file's contents
pub fn (la &LocalAdapter) read(path string) !string {
	full := la.resolve_path(path)!
	return os.read_file(full)
}

// write creates or overwrites a file
pub fn (mut la LocalAdapter) write(path string, contents string, options StorageWriteOptions) ! {
	full := la.resolve_path(path)!

	// Ensure parent directory exists — non-fatal if it already exists
	parent := dirname(full)
	if !os.exists(parent) {
		os.mkdir_all(parent) or {
			return error('failed to create parent directory "${parent}": ${err}')
		}
	}

	// Write the file
	os.write_file(full, contents)!

	// Set visibility
	la.set_visibility(path, options.visibility)!
}

// delete removes a file
//
// 权限覆盖缓存必须同步摘掉。缓存按「相对路径」索引，而删除后重新创建的
// 同名文件会复用同一个 key —— 残留的 `public` 记录会让下一个本该 private
// 的新文件直接拿到 644 权限，并且 `visibility()` 也报 public。对一个上传
// 目录来说，这就是「删了旧文件，新文件裸奔」。
pub fn (la &LocalAdapter) delete(path string) ! {
	full := la.resolve_path(path)!
	os.rm(full)!
	la.forget_permissions(path)!
}

// forget_permissions drops the cached visibility override for a path
//
// 与 visibility() 同理：`&LocalAdapter` 接收者满足 Storage 的只读段，
// 互斥量本身不因清理一条记录而变化，故走 unsafe 访问。
pub fn (la &LocalAdapter) forget_permissions(path string) ! {
	unsafe {
		la.mu.@lock()
		la.permissions.delete(path)
		la.mu.unlock()
	}
}

// exists checks if a file exists
pub fn (la &LocalAdapter) exists(path string) bool {
	full := la.resolve_path(path) or { return false }
	return os.exists(full)
}

// ============================================================
// File Operations
// ============================================================

// copy duplicates a file
pub fn (la &LocalAdapter) copy(source string, dest string) ! {
	src := la.resolve_path(source)!
	dst := la.resolve_path(dest)!

	// Ensure destination directory exists
	parent := dirname(dst)
	if !os.exists(parent) {
		os.mkdir_all(parent) or {
			return error('failed to create parent directory "${parent}": ${err}')
		}
	}

	// Read source and write to destination
	data := os.read_file(src)!
	os.write_file(dst, data)!
}

// move renames or moves a file
pub fn (la &LocalAdapter) move(source string, dest string) ! {
	src := la.resolve_path(source)!
	dst := la.resolve_path(dest)!

	// Ensure destination directory exists
	parent := dirname(dst)
	if !os.exists(parent) {
		os.mkdir_all(parent) or {
			return error('failed to create parent directory "${parent}": ${err}')
		}
	}

	os.mv(src, dst)!

	// 权限覆盖缓存以「调用方给的相对路径」为键，搬完必须跟着走，
	// 否则源路径残留一条失效记录（同名文件重建即继承旧可见性），
	// 目标路径则退回默认 private —— 一次 move 就悄悄降级了可见性。
	carried := unsafe { la.permissions[source] or { '' } }
	if carried.len > 0 {
		la.forget_permissions(source)!
		mut target_vis := Visibility.private_
		if carried == 'public' {
			target_vis = .public_
		}
		mut self_mut := unsafe { &LocalAdapter(la) }
		self_mut.set_visibility(dest, target_vis)!
	}
}

// size returns the file size in bytes
pub fn (la &LocalAdapter) size(path string) !i64 {
	full := la.resolve_path(path)!
	return os.file_size(full)
}

// mime_type detects MIME type from file extension
pub fn (la &LocalAdapter) mime_type(path string) !string {
	if !la.exists(path) {
		return error('file not found: ${path}')
	}
	return detect_mime_type(path)
}

// last_modified returns the file's last modification time
pub fn (la &LocalAdapter) last_modified(path string) !i64 {
	full := la.resolve_path(path)!
	return os.file_last_mod_unix(full)
}

// metadata returns comprehensive file metadata.
//
// Read-only, so the receiver is `&LocalAdapter` — storage.Storage declares
// metadata() in its immutable section and a `mut` receiver breaks the
// interface implementation (and the cheap `&adapter` registrations).
pub fn (la &LocalAdapter) metadata(path string) !&FileMetadata {
	full := la.resolve_path(path)!
	if !os.exists(full) {
		return error('file not found: ${path}')
	}

	sz := os.file_size(full)
	mime := detect_mime_type(path)
	vis := la.visibility(path) or { Visibility.private_ }

	mut meta := new_file_metadata(path, sz, mime)
	meta.last_modified = os.file_last_mod_unix(full)
	meta.visibility = vis
	return meta
}

// set_visibility changes file visibility.
// On Unix: sets file permissions for public (644) or private (600).
// This is best-effort — full permission control requires platform-specific code.
// The permissions cache is bounded to max_permissions entries (FIFO eviction).
pub fn (mut la LocalAdapter) set_visibility(path string, visibility Visibility) ! {
	full := la.resolve_path(path)!
	if !os.exists(full) {
		return error('file not found: ${path}')
	}

	la.mu.@lock()
	// Only add to access order if it's a new key
	if path !in la.permissions {
		la.perm_access_order << path
	}
	la.permissions[path] = visibility.str()
	// Bound the map: evict the oldest entries once the ceiling is exceeded.
	//
	// 这里必须用括号把 `max_permissions / 2` 分组。原来的
	// `la.permissions.len - max_permissions / 2` 按优先级等价于
	// `(len - max_permissions) / 2`，结果是 0 或负数：evict_count 恒为 0，
	// 一个 key 都删不掉，permissions 无限增长 —— 正是这段代码要防的问题。
	if la.permissions.len > max_permissions {
		target := max_permissions / 2
		evict_count := la.permissions.len - target
		mut evicted := 0
		mut new_order := []string{cap: la.perm_access_order.len}
		for p in la.perm_access_order {
			if evicted < evict_count && p in la.permissions && p != path {
				la.permissions.delete(p)
				evicted++
			} else {
				new_order << p
			}
		}
		la.perm_access_order = new_order
	}
	la.mu.unlock()

	// chmod is best-effort on Unix — errors are logged but not fatal
	if visibility == .public_ {
		os.chmod(full, 0o644) or {
			eprintln('[LocalAdapter] chmod 644 failed for "${full}": ${err}')
		}
	} else {
		os.chmod(full, 0o600) or {
			eprintln('[LocalAdapter] chmod 600 failed for "${full}": ${err}')
		}
	}
}

// visibility returns a file's visibility.
//
// Read-only: the RWMutex is shared state, so a `&LocalAdapter` receiver is
// enough and keeps storage.Storage's immutable section satisfied.
pub fn (la &LocalAdapter) visibility(path string) !Visibility {
	// `&LocalAdapter` keeps Storage's read-only section satisfied, so the
	// RwMutex is reached through unsafe — the lock itself is not mutated.
	unsafe { la.mu.rlock() }
	defer { unsafe { la.mu.runlock() } }
	if vis_str := la.permissions[path] {
		if vis_str == 'public' {
			return Visibility.public_
		}
	}
	return Visibility.private_
}

// ============================================================
// Directory Operations
// ============================================================

// list_contents returns metadata for all files in a directory
pub fn (la &LocalAdapter) list_contents(directory string) ![]&FileMetadata {
	full := la.resolve_path(directory)!
	if !os.exists(full) {
		return error('directory not found: ${directory}')
	}

	entries := os.ls(full)!
	mut result := []&FileMetadata{}

	for entry in entries {
		entry_path := if directory.ends_with('/') {
			'${directory}${entry}'
		} else {
			'${directory}/${entry}'
		}
		full_entry := la.resolve_path(entry_path)!

		if os.is_dir(full_entry) {
			// Directories are listed as files with size 0
			result << &FileMetadata{
				path:          entry_path
				size:          0
				mime_type:     'inode/directory'
				last_modified: os.file_last_mod_unix(full_entry)
				visibility:    .private_
				extra:         {
					'type': 'directory'
				}
			}
		} else {
			sz := os.file_size(full_entry)
			mime := detect_mime_type(entry_path)
			lm := os.file_last_mod_unix(full_entry)
			mut meta := new_file_metadata(entry_path, sz, mime)
			meta.last_modified = lm
			result << meta
		}
	}

	return result
}

// create_directory makes a new directory
pub fn (la &LocalAdapter) create_directory(path string) ! {
	full := la.resolve_path(path)!
	os.mkdir_all(full)!
}

// delete_directory removes a directory and all contents
pub fn (la &LocalAdapter) delete_directory(path string) ! {
	full := la.resolve_path(path)!
	os.rmdir_all(full)!
}

// ============================================================
// URL Generation
// ============================================================

// url returns a relative URL for the file (e.g., '/storage/path/to/file.txt')
pub fn (la &LocalAdapter) url(path string) string {
	clean := path.trim_left('/')
	return '/storage/${clean}'
}

// temporary_url returns a signed URL (stub — local adapter returns url)
pub fn (la &LocalAdapter) temporary_url(path string, expiration_sec i64) !string {
	// Local files don't support signed URLs — return regular URL
	return la.url(path)
}

// ============================================================
// Convenience Methods
// ============================================================

// read_stream reads file as a string (same as read for V compat)
pub fn (la &LocalAdapter) read_stream(path string) !string {
	return la.read(path)
}

// write_stream writes a string to a file (same as write for V compat)
pub fn (mut la LocalAdapter) write_stream(path string, contents string, options StorageWriteOptions) ! {
	la.write(path, contents, options)!
}

// put is a convenience wrapper for write with default options
pub fn (mut la LocalAdapter) put(path string, options StorageWriteOptions) ! {
	la.write(path, '', options)!
}

// put_file uploads a local file to the storage
pub fn (mut la LocalAdapter) put_file(source_path string, dest_path string, options StorageWriteOptions) ! {
	contents := os.read_file(source_path)!
	la.write(dest_path, contents, options)!
}

// ============================================================
// Local-specific helpers
// ============================================================

// full_path returns the absolute filesystem path (for debugging)
pub fn (la &LocalAdapter) full_path(path string) !string {
	return la.resolve_path(path)!
}

// dirname extracts the directory portion of a path
fn dirname(path string) string {
	if !path.contains('/') {
		return '.'
	}
	last_slash := path.last_index('/') or { return '.' }
	return path[..last_slash]
}

// available_space returns available disk space in bytes (stub)
pub fn (la &LocalAdapter) available_space() i64 {
	// Returns a large default — actual implementation depends on OS
	return 10 * 1024 * 1024 * 1024 // 10 GB default
}
