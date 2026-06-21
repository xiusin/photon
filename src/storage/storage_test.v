module storage

// storage_test.v - Tests for Photon Storage Module
import os

// ============================================================
// MIME Detection Tests
// ============================================================

fn test_mime_detection() {
	assert detect_mime_type('photo.jpg') == 'image/jpeg'
	assert detect_mime_type('image.png') == 'image/png'
	assert detect_mime_type('doc.pdf') == 'application/pdf'
	assert detect_mime_type('script.js') == 'application/javascript'
	assert detect_mime_type('style.css') == 'text/css'
	assert detect_mime_type('index.html') == 'text/html'
	assert detect_mime_type('data.json') == 'application/json'
	assert detect_mime_type('video.mp4') == 'video/mp4'
}

fn test_mime_default() {
	assert detect_mime_type('unknown.xyz') == 'application/octet-stream'
	assert detect_mime_type('no_extension') == 'application/octet-stream'
}

fn test_extract_extension() {
	assert extract_extension('file.txt') == 'txt'
	assert extract_extension('/path/to/file.pdf') == 'pdf'
	assert extract_extension('no_ext') == ''
	assert extract_extension('archive.tar.gz') == 'gz'
	assert extract_extension('Image.JPG') == 'jpg'
}

fn test_is_image_audio_video() {
	assert is_image('image/jpeg') == true
	assert is_image('image/png') == true
	assert is_image('text/plain') == false
	assert is_video('video/mp4') == true
	assert is_video('image/jpeg') == false
	assert is_audio('audio/mpeg') == true
	assert is_audio('audio/ogg') == true
	assert is_audio('video/mp4') == false
}

fn test_extension_from_mime() {
	assert extension_from_mime('image/jpeg') == 'jpg'
	assert extension_from_mime('application/json') == 'json'
	assert extension_from_mime('text/html') == 'html'
}

// ============================================================
// LocalAdapter Tests
// ============================================================

fn test_local_adapter_new() {
	adapter := new_local_adapter('/tmp/test-storage')
	assert adapter.adapter_name() == 'local'
	assert adapter.root == '/tmp/test-storage'
}

fn test_local_adapter_resolve_path() {
	adapter := new_local_adapter('/var/uploads')
	assert adapter.resolve_path('file.txt') == '/var/uploads/file.txt'
	assert adapter.resolve_path('/file.txt') == '/var/uploads/file.txt'
	assert adapter.resolve_path('dir/file.txt') == '/var/uploads/dir/file.txt'
}

fn test_local_adapter_write_and_read() {
	root := '/tmp/photon-storage-test'
	os.rmdir_all(root) or {}
	defer { os.rmdir_all(root) or {} }

	mut adapter := new_local_adapter(root)
	adapter.write('test.txt', 'Hello, Photon!', default_options())!

	content := adapter.read('test.txt')!
	assert content == 'Hello, Photon!'
	assert adapter.exists('test.txt') == true
	assert adapter.exists('nonexistent.txt') == false
}

fn test_local_adapter_delete() {
	root := '/tmp/photon-storage-del'
	os.rmdir_all(root) or {}
	defer { os.rmdir_all(root) or {} }

	mut adapter := new_local_adapter(root)
	adapter.write('to_delete.txt', 'delete me', default_options())!
	assert adapter.exists('to_delete.txt') == true

	adapter.delete('to_delete.txt')!
	assert adapter.exists('to_delete.txt') == false
}

fn test_local_adapter_size() {
	root := '/tmp/photon-storage-size'
	os.rmdir_all(root) or {}
	defer { os.rmdir_all(root) or {} }

	mut adapter := new_local_adapter(root)
	adapter.write('sized.txt', '1234567890', default_options())!

	sz := adapter.size('sized.txt')!
	assert sz == 10
}

fn test_local_adapter_mime_type() {
	root := '/tmp/photon-storage-mime'
	os.rmdir_all(root) or {}
	defer { os.rmdir_all(root) or {} }

	mut adapter := new_local_adapter(root)
	adapter.write('image.png', 'fake-png', default_options())!

	mime := adapter.mime_type('image.png')!
	assert mime == 'image/png'
}

fn test_local_adapter_copy_move() {
	root := '/tmp/photon-storage-cp'
	os.rmdir_all(root) or {}
	defer { os.rmdir_all(root) or {} }

	mut adapter := new_local_adapter(root)
	adapter.write('original.txt', 'copy me', default_options())!

	adapter.copy('original.txt', 'copied.txt')!
	assert adapter.exists('copied.txt') == true

	adapter.move('original.txt', 'moved.txt')!
	assert adapter.exists('original.txt') == false
	assert adapter.exists('moved.txt') == true
}

fn test_local_adapter_directories() {
	root := '/tmp/photon-storage-dir'
	os.rmdir_all(root) or {}
	defer { os.rmdir_all(root) or {} }

	mut adapter := new_local_adapter(root)
	adapter.create_directory('subdir')!
	assert adapter.exists('subdir') == true

	adapter.write('subdir/nested.txt', 'nested', default_options())!
	contents := adapter.list_contents('subdir')!
	assert contents.len >= 1
}

fn test_local_adapter_public_write() {
	root := '/tmp/photon-storage-pub'
	os.rmdir_all(root) or {}
	defer { os.rmdir_all(root) or {} }

	mut adapter := new_local_adapter(root)
	adapter.write('public.txt', 'hello world', public_options())!
	assert adapter.exists('public.txt') == true
}

fn test_local_adapter_url() {
	adapter := new_local_adapter('/var/uploads')
	assert adapter.url('images/photo.jpg') == '/storage/images/photo.jpg'
	assert adapter.url('/images/photo.jpg') == '/storage/images/photo.jpg'
}

// ============================================================
// StorageManager Tests
// ============================================================

fn test_storage_manager_new() {
	manager := new_manager()
	assert manager.disks.len == 0
}

fn test_storage_manager_register() {
	root := '/tmp/photon-storage-mgr'
	os.mkdir_all(root) or {}
	defer { os.rmdir_all(root) or {} }

	mut manager := new_manager()
	manager.register('uploads', new_local_adapter(root))
	assert manager.has_disk('uploads') == true
	assert manager.disk_names().len == 1
}

// ============================================================
// S3Adapter Tests
// ============================================================

fn test_s3_adapter_new() {
	adapter := new_s3_adapter('my-bucket', 'us-east-1')
	assert adapter.adapter_name() == 's3'
	assert adapter.bucket == 'my-bucket'
	assert adapter.region == 'us-east-1'
}

fn test_s3_adapter_url() {
	adapter := new_s3_adapter('my-bucket', 'us-east-1')
	url := adapter.url('path/to/file.txt')
	assert url.contains('my-bucket')
	assert url.contains('path/to/file.txt')
}

fn test_s3_adapter_compatible() {
	adapter := new_s3_compatible_adapter('my-bucket', 'us-east-1', 'https://minio.example.com',
		'AKIAIOSFODNN7EXAMPLE', 'secret-key')
	assert adapter.endpoint == 'https://minio.example.com'
	assert adapter.use_path_style == true
}

fn test_s3_adapter_temporary_url() {
	adapter := new_s3_adapter('my-bucket', 'us-east-1')
	url := adapter.temporary_url('secret.txt', 3600)!
	assert url.contains('secret.txt')
	assert url.contains('Expires')
	assert url.contains('Signature')
}

fn test_s3_operations_stubs() {
	mut adapter := new_s3_adapter('test-bucket', 'us-east-1')

	// Write succeeds (stub no-op)
	adapter.write('file.txt', 'test', default_options())!

	// Read returns stub placeholder
	content := adapter.read('file.txt')!
	assert content.contains('stub')

	// Exists returns true for all paths (stub)
	assert adapter.exists('file.txt') == true

	// Create directory is no-op
	adapter.create_directory('prefix/')!
	assert true
}

// ============================================================
// Visibility Tests
// ============================================================

fn test_visibility_enum() {
	assert Visibility.public_.str() == 'public'
	assert Visibility.private_.str() == 'private'
}

fn test_default_options() {
	opts := default_options()
	assert opts.visibility == .private_
}

fn test_public_options() {
	opts := public_options()
	assert opts.visibility == .public_
}

// ============================================================
// FileMetadata Tests
// ============================================================

fn test_file_metadata_new() {
	meta := new_file_metadata('path/to/file.txt', 1024, 'text/plain')
	assert meta.path == 'path/to/file.txt'
	assert meta.size == 1024
	assert meta.mime_type == 'text/plain'
	assert meta.visibility == .private_
}
