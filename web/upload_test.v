module web

import os

// ── UploadHandler Tests ──

fn test_new_upload_handler() {
	h := new_upload_handler()
	assert h.max_size == 10 * 1024 * 1024
	assert h.allowed_extensions.len == 0
	assert h.allowed_mime_types.len == 0
	assert h.naming_strategy == .hash
	assert h.path_strategy == .date
}

// ── Validation Tests ──

fn test_upload_validate_size_ok() {
	h := new_upload_handler()
	h.validate('test.jpg', 1000, 'image/jpeg') or {
		assert false
		return
	}
}

fn test_upload_validate_size_too_large() {
	mut h := new_upload_handler()
	h.max_size = 100
	h.validate('test.jpg', 200, 'image/jpeg') or { return }
	assert false
}

fn test_upload_validate_extension_ok() {
	mut h := new_upload_handler()
	h.allowed_extensions = ['.jpg', '.png']
	h.validate('test.jpg', 1000, 'image/jpeg') or {
		assert false
		return
	}
}

fn test_upload_validate_extension_blocked() {
	mut h := new_upload_handler()
	h.allowed_extensions = ['.jpg', '.png']
	h.validate('test.exe', 1000, 'application/octet-stream') or { return }
	assert false
}

fn test_upload_validate_mime_ok() {
	mut h := new_upload_handler()
	h.allowed_mime_types = ['image/jpeg', 'image/png']
	h.validate('test.jpg', 1000, 'image/jpeg') or {
		assert false
		return
	}
}

fn test_upload_validate_mime_blocked() {
	mut h := new_upload_handler()
	h.allowed_mime_types = ['image/jpeg']
	h.validate('test.png', 1000, 'image/png') or { return }
	assert false
}

// ── Name Generation Tests ──

fn test_upload_generate_name_hash() {
	h := new_upload_handler()
	name := h.generate_name('photo.jpg', 'some content')
	assert name.ends_with('.jpg')
	assert name.len > 4 // hash + extension
}

fn test_upload_generate_name_original() {
	mut h := new_upload_handler()
	h.naming_strategy = .original
	name := h.generate_name('photo.jpg', 'content')
	assert name == 'photo.jpg'
}

fn test_upload_generate_name_sequential() {
	mut h := new_upload_handler()
	h.naming_strategy = .sequential
	name := h.generate_name('photo.jpg', 'content')
	assert name.ends_with('.jpg')
}

fn test_upload_generate_name_uuid() {
	mut h := new_upload_handler()
	h.naming_strategy = .uuid
	name := h.generate_name('photo.jpg', 'content')
	assert name.ends_with('.jpg')
}

// ── Path Generation Tests ──

fn test_upload_generate_path_flat() {
	mut h := new_upload_handler()
	h.path_strategy = .flat
	path := h.generate_path()
	assert path == ''
}

fn test_upload_generate_path_date() {
	h := new_upload_handler()
	path := h.generate_path()
	// Should be YYYY/MM/DD format
	assert path.contains('/')
	parts := path.split('/')
	assert parts.len == 3
}

fn test_upload_generate_path_hash_dir() {
	mut h := new_upload_handler()
	h.path_strategy = .hash_dir
	path := h.generate_path()
	assert path.len == 2
}

// ── MIME Type Detection Tests ──

fn test_guess_mime_type_jpeg() {
	assert guess_mime_type('photo.jpg') == 'image/jpeg'
	assert guess_mime_type('photo.jpeg') == 'image/jpeg'
}

fn test_guess_mime_type_png() {
	assert guess_mime_type('photo.png') == 'image/png'
}

fn test_guess_mime_type_pdf() {
	assert guess_mime_type('doc.pdf') == 'application/pdf'
}

fn test_guess_mime_type_json() {
	assert guess_mime_type('data.json') == 'application/json'
}

fn test_guess_mime_type_unknown() {
	assert guess_mime_type('file.xyz') == 'application/octet-stream'
}

// ── handle_bytes Tests ──

fn test_upload_handle_bytes() {
	mut h := new_upload_handler()
	h.naming_strategy = .sequential
	h.path_strategy = .flat

	tmp_dir := os.join_path(os.temp_dir(), 'photon_upload_test_${os.getpid()}')
	defer {
		os.rmdir_all(tmp_dir) or {}
	}

	data := [u8(`H`), `e`, `l`, `l`, `o`]
	result := h.handle_bytes('test.txt', data, tmp_dir)!

	assert result.original_name == 'test.txt'
	assert result.extension == '.txt'
	assert result.size == 5
	assert result.mime_type == 'text/plain'
	assert result.path.starts_with(tmp_dir)

	// Verify file was written
	exists := os.exists(result.path)
	assert exists
}

// ── UploadError Tests ──

fn test_upload_error_str() {
	e := UploadError{
		field: 'avatar'
		message: 'too large'
		code: .file_too_large
	}
	s := e.str()
	assert s.contains('avatar')
	assert s.contains('maximum size')
}

// ── Chunked Upload Tests ──

fn test_new_chunk_manager() {
	cm := new_chunk_manager()
	assert cm.chunks.len == 0
}

fn test_chunk_manager_init_upload() {
	mut cm := new_chunk_manager()
	cm.temp_dir = os.join_path(os.temp_dir(), 'photon_chunk_test_${os.getpid()}')
	defer {
		os.rmdir_all(cm.temp_dir) or {}
	}

	upload_id := cm.init_upload('large_file.zip', 3, 1024000)
	assert upload_id.len > 0
	assert cm.chunks.len == 1
	assert cm.chunks[upload_id].total_chunks == 3
}

fn test_chunk_manager_receive_and_complete() {
	mut cm := new_chunk_manager()
	cm.temp_dir = os.join_path(os.temp_dir(), 'photon_chunk_test_${os.getpid()}')
	defer {
		os.rmdir_all(cm.temp_dir) or {}
	}

	upload_id := cm.init_upload('test.txt', 2, 10)

	// Receive chunk 0
	cm.receive_chunk(upload_id, 0, 'Hello')!
	assert !cm.is_complete(upload_id)

	// Receive chunk 1
	cm.receive_chunk(upload_id, 1, ' World')!
	assert cm.is_complete(upload_id)
}

fn test_chunk_manager_assemble() {
	mut cm := new_chunk_manager()
	cm.temp_dir = os.join_path(os.temp_dir(), 'photon_chunk_test_${os.getpid()}')
	defer {
		os.rmdir_all(cm.temp_dir) or {}
	}

	upload_id := cm.init_upload('test.txt', 2, 11)
	cm.receive_chunk(upload_id, 0, 'Hello')!
	cm.receive_chunk(upload_id, 1, ' World')!

	dest_path := os.join_path(cm.temp_dir, 'assembled.txt')
	cm.assemble(upload_id, dest_path)!

	content := os.read_file(dest_path)!
	assert content == 'Hello World'

	// Upload session should be cleaned up
	assert upload_id !in cm.chunks
}

fn test_chunk_manager_invalid_upload_id() {
	mut cm := new_chunk_manager()
	cm.receive_chunk('nonexistent', 0, 'data') or { return }
	assert false
}

fn test_chunk_manager_invalid_chunk_index() {
	mut cm := new_chunk_manager()
	cm.temp_dir = os.join_path(os.temp_dir(), 'photon_chunk_test_${os.getpid()}')
	defer {
		os.rmdir_all(cm.temp_dir) or {}
	}

	upload_id := cm.init_upload('test.txt', 2, 10)
	cm.receive_chunk(upload_id, 5, 'data') or { return }
	// Invalid index should error
}
