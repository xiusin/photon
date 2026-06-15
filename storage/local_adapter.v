module storage

// local_adapter.v - Local Filesystem Adapter
//
// Implements the Storage interface for the local filesystem.
// Supports root directory scoping, visibility via file permissions,
// directory traversal, and all common file operations.

import os

// LocalAdapter provides filesystem access scoped to a root directory
pub struct LocalAdapter {
pub:
	root      string // root directory path
pub mut:
	permissions map[string]string // path → visibility override
}

// new_local_adapter creates a LocalAdapter with the given root directory
pub fn new_local_adapter(root string) &LocalAdapter {
	return &LocalAdapter{
		root: root
		permissions: map[string]string{}
	}
}

// adapter_name returns the adapter type
pub fn (la &LocalAdapter) adapter_name() string {
	return 'local'
}

// resolve_path joins the root with the given path
fn (la &LocalAdapter) resolve_path(path string) string {
	clean := path.trim_left('/')
	if la.root.ends_with('/') {
		return la.root + clean
	}
	return '${la.root}/${clean}'
}

// ============================================================
// Basic CRUD
// ============================================================

// read reads a file's contents
pub fn (la &LocalAdapter) read(path string) !string {
	full := la.resolve_path(path)
	return os.read_file(full)
}

// write creates or overwrites a file
pub fn (mut la LocalAdapter) write(path string, contents string, options StorageWriteOptions) ! {
	full := la.resolve_path(path)

	// Ensure parent directory exists
	parent := dirname(full)
	os.mkdir_all(parent) or {}

	// Write the file
	os.write_file(full, contents)!

	// Set visibility
	la.set_visibility(path, options.visibility)!
}

// delete removes a file
pub fn (la &LocalAdapter) delete(path string) ! {
	full := la.resolve_path(path)
	os.rm(full)!
}

// exists checks if a file exists
pub fn (la &LocalAdapter) exists(path string) bool {
	full := la.resolve_path(path)
	return os.exists(full)
}

// ============================================================
// File Operations
// ============================================================

// copy duplicates a file
pub fn (la &LocalAdapter) copy(source string, dest string) ! {
	src := la.resolve_path(source)
	dst := la.resolve_path(dest)

	// Ensure destination directory exists
	parent := dirname(dst)
	os.mkdir_all(parent) or {}

	// Read source and write to destination
	data := os.read_file(src)!
	os.write_file(dst, data)!
}

// move renames or moves a file
pub fn (la &LocalAdapter) move(source string, dest string) ! {
	src := la.resolve_path(source)
	dst := la.resolve_path(dest)

	// Ensure destination directory exists
	parent := dirname(dst)
	os.mkdir_all(parent) or {}

	os.mv(src, dst)!
}

// size returns the file size in bytes
pub fn (la &LocalAdapter) size(path string) !i64 {
	full := la.resolve_path(path)
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
	full := la.resolve_path(path)
	return os.file_last_mod_unix(full)
}

// metadata returns comprehensive file metadata
pub fn (la &LocalAdapter) metadata(path string) !&FileMetadata {
	full := la.resolve_path(path)
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

// set_visibility changes file visibility
pub fn (mut la LocalAdapter) set_visibility(path string, visibility Visibility) ! {
	full := la.resolve_path(path)
	if !os.exists(full) {
		return error('file not found: ${path}')
	}

	la.permissions[path] = visibility.str()

	// On Unix: set read permissions for public files
	// This is a best-effort; full permission control requires platform-specific code
	if visibility == .public_ {
		os.chmod(full, 0o644) or {}
	} else {
		os.chmod(full, 0o600) or {}
	}
}

// visibility returns a file's visibility
pub fn (la &LocalAdapter) visibility(path string) !Visibility {
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
	full := la.resolve_path(directory)
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
		full_entry := la.resolve_path(entry_path)

		if os.is_dir(full_entry) {
			// Directories are listed as files with size 0
			result << &FileMetadata{
				path: entry_path
				size: 0
				mime_type: 'inode/directory'
				last_modified: os.file_last_mod_unix(full_entry)
				visibility: .private_
				extra: {'type': 'directory'}
			}
		} else {
			sz := os.file_size(full_entry)
			mime := detect_mime_type(entry_path)
		_ = os.file_last_mod_unix(full_entry)
		result << new_file_metadata(entry_path, sz, mime)
		}
	}

	return result
}

// create_directory makes a new directory
pub fn (la &LocalAdapter) create_directory(path string) ! {
	full := la.resolve_path(path)
	os.mkdir_all(full)!
}

// delete_directory removes a directory and all contents
pub fn (la &LocalAdapter) delete_directory(path string) ! {
	full := la.resolve_path(path)
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
pub fn (la &LocalAdapter) full_path(path string) string {
	return la.resolve_path(path)
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
