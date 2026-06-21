module storage

// storage.v - Photon Storage Module (Flysystem-inspired)
//
// Provides a unified filesystem abstraction with pluggable adapters.
// Supports local filesystem out of the box, with extension points
// for S3, GCS, Azure Blob, FTP, SFTP, etc.
//
// Architecture:
//   storage.v        - Storage interface, StorageManager, metadata types
//   local_adapter.v  - Local filesystem implementation
//   s3_adapter.v     - S3-compatible cloud storage stub
//   mime.v           - MIME type detection helpers
//
// Usage:
//   import photon.storage
//
//   mut manager := storage.new_manager()
//   manager.register('local', storage.new_local_adapter('/var/uploads'))
//   manager.register('s3', storage.new_s3_adapter('my-bucket', 'us-east-1'))
//
//   // Read
//   content := manager.get('local').read('path/to/file.txt')!
//   // Write
//   manager.get('local').write('path/to/new.txt', 'Hello World', .public)!
//   // Delete
//   manager.get('local').delete('path/to/old.txt')!

// ============================================================
// Visibility
// ============================================================

// Visibility controls who can access a file
pub enum Visibility {
	public_
	private_
}

// str returns the visibility string
pub fn (v Visibility) str() string {
	return match v {
		.public_ { 'public' }
		.private_ { 'private' }
	}
}

// ============================================================
// FileMetadata
// ============================================================

// FileMetadata holds information about a stored file
pub struct FileMetadata {
pub:
	path      string
	size      i64
	mime_type string
	etag      string
pub mut:
	last_modified i64
	visibility    Visibility = .private_
	extra         map[string]string // adapter-specific metadata
}

// new_file_metadata creates FileMetadata (last_modified defaults to 0)
pub fn new_file_metadata(path string, size i64, mime_type string) &FileMetadata {
	return &FileMetadata{
		path:      path
		size:      size
		mime_type: mime_type
		extra:     map[string]string{}
	}
}

// ============================================================
// StorageWriteOptions
// ============================================================

// StorageWriteOptions configures write operations
pub struct StorageWriteOptions {
pub:
	visibility   Visibility = .private_
	content_type string
	metadata     map[string]string
}

// default_options returns default write options
pub fn default_options() StorageWriteOptions {
	return StorageWriteOptions{
		metadata: map[string]string{}
	}
}

// public_options returns write options with public visibility
pub fn public_options() StorageWriteOptions {
	return StorageWriteOptions{
		visibility: .public_
		metadata:   map[string]string{}
	}
}

// ============================================================
// Storage — the core filesystem interface
// ============================================================

// Storage is the unified filesystem trait.
// All storage adapters (local, S3, GCS, etc.) implement this interface.
// Methods are split: read operations (immutable) and write operations (mut).
pub interface Storage {
	// — Read operations (immutable) —
	read(path string) !string
	exists(path string) bool
	size(path string) !i64
	mime_type(path string) !string
	last_modified(path string) !i64
	metadata(path string) !&FileMetadata
	visibility(path string) !Visibility
	list_contents(directory string) ![]&FileMetadata
	url(path string) string
	temporary_url(path string, expiration_sec i64) !string
	read_stream(path string) !string
	adapter_name() string
mut:
	// — Write operations (mutable) —
	write(path string, contents string, options StorageWriteOptions) !
	delete(path string) !
	copy(source string, dest string) !
	move(source string, dest string) !
	set_visibility(path string, visibility Visibility) !
	create_directory(path string) !
	delete_directory(path string) !
	write_stream(path string, contents string, options StorageWriteOptions) !
	put(path string, options StorageWriteOptions) !
	put_file(source_path string, dest_path string, options StorageWriteOptions) !
}

// ============================================================
// StorageManager — multi-disk management
// ============================================================

// StorageManager manages multiple storage disks (Laravel Storage inspired).
// Think of it as the Storage facade: you register disks by name, then
// retrieve and use them throughout your application.
@[heap]
pub struct StorageManager {
pub mut:
	disks        map[string]&Storage
	default_disk string = 'local'
}

// new_manager creates a new StorageManager
pub fn new_manager() &StorageManager {
	return unsafe {
		&StorageManager{
			disks: map[string]&Storage{}
		}
	}
}

// register adds a named storage disk
@[unsafe]
pub fn (mut sm StorageManager) register(name string, adapter &Storage) {
	sm.disks[name] = adapter
	if sm.default_disk.len == 0 {
		sm.default_disk = name
	}
}

// disk returns a named disk or the default.
// Returns an error if no disk is registered.
pub fn (sm &StorageManager) disk(name string) !&Storage {
	return sm.disks[name] or {
		return sm.disks[sm.default_disk] or { return error('no storage disk registered') }
	}
}

// get is an alias for disk()
pub fn (sm &StorageManager) get(name string) !&Storage {
	return sm.disk(name)
}

// must_get is like get() but returns a non-optional reference (for convenience)
pub fn (sm &StorageManager) must_get(name string) &Storage {
	return sm.get(name) or { panic('storage disk not found: ${name}') }
}

// has_disk checks if a disk is registered
pub fn (sm &StorageManager) has_disk(name string) bool {
	return name in sm.disks
}

// disk_names returns all registered disk names
pub fn (sm &StorageManager) disk_names() []string {
	return sm.disks.keys()
}
