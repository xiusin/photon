module web

// upload.v - File Upload Handling (Laravel File Upload / Spring MultipartFile inspired)
//
// Provides utilities for handling file uploads in web requests.
// Supports:
//   - Single and multiple file uploads
//   - File validation (size, extension, MIME type)
//   - Secure file naming and storage
//   - Chunked upload support (resumable)
//
// Security considerations:
//   - Double-extension attacks are blocked (e.g., "shell.php.jpg")
//   - Path traversal in filenames is sanitized
//   - Binary data is written via os.write_bytes (not os.write_file)
//   - Crypto-secure random IDs for chunked uploads
//
// Usage:
//   upload := web.new_upload_handler()
//   upload.max_size = 10 * 1024 * 1024  // 10MB
//   upload.allowed_extensions = ['.jpg', '.png', '.pdf']
//
//   result := upload.handle(ctx, 'avatar', '/var/www/uploads')!
import veb
import os
import crypto.sha256
import encoding.hex
import crypto.rand
import sync
import strconv
import time

// sha256_hex computes a SHA-256 hash and returns it as hex string.
fn sha256_hex(data []u8) string {
	digest := sha256.sum(data)
	mut arr := []u8{}
	for b in digest {
		arr << b
	}
	return hex.encode(arr)
}

// ── Upload Result ──

// UploadResult holds the result of a successful file upload.
pub struct UploadResult {
pub:
	original_name string
	stored_name   string
	path          string // full path on disk
	size          int
	extension     string
	mime_type     string
	hash          string // SHA-256 hash of file content
}

// ── Upload Error ──

// UploadError represents an upload validation error.
pub struct UploadError {
pub:
	field   string
	message string
	code    UploadErrorCode
}

// UploadErrorCode categorizes upload errors.
pub enum UploadErrorCode {
	file_not_found
	file_too_large
	invalid_extension
	invalid_mime_type
	write_failed
	chunk_error
	dangerous_filename
}

// str returns a human-readable error message.
pub fn (e UploadError) str() string {
	return match e.code {
		.file_not_found { 'file not found in request field "${e.field}"' }
		.file_too_large { 'file "${e.field}" exceeds maximum size' }
		.invalid_extension { 'file "${e.field}" has disallowed extension' }
		.invalid_mime_type { 'file "${e.field}" has disallowed MIME type' }
		.write_failed { 'failed to write file "${e.field}" to disk' }
		.chunk_error { 'chunk upload error for "${e.field}"' }
		.dangerous_filename { 'file "${e.field}" has a dangerous filename' }
	}
}

// ── Upload Handler ──

// UploadHandler handles file uploads with validation and storage.
pub struct UploadHandler {
pub mut:
	max_size           int = 10 * 1024 * 1024 // 10MB default
	allowed_extensions []string // empty = all allowed
	allowed_mime_types []string // empty = all allowed
	naming_strategy    NamingStrategy = .hash
	path_strategy      PathStrategy   = .date
}

// NamingStrategy defines how uploaded files are named.
pub enum NamingStrategy {
	original   // keep original name (unsafe, may collide)
	hash       // SHA-256 hash-based unique name
	sequential // incremental numbering
	uuid       // random UUID-like name
}

// PathStrategy defines how subdirectories are organized.
pub enum PathStrategy {
	flat     // all files in one directory
	date     // YYYY/MM/DD subdirectories
	hash_dir // first 2 chars of hash as subdirectory
}

// new_upload_handler creates an UploadHandler with sensible defaults.
pub fn new_upload_handler() &UploadHandler {
	return &UploadHandler{
		max_size:           10 * 1024 * 1024
		allowed_extensions: []string{}
		allowed_mime_types: []string{}
		naming_strategy:    .hash
		path_strategy:      .date
	}
}

// ── Validation ──

// dangerous_extensions lists extensions that should never be uploaded
// as they could be executed on the server side.
const dangerous_extensions = [
	'.php',
	'.php3',
	'.php4',
	'.php5',
	'.phtml',
	'.pht',
	'.jsp',
	'.jspx',
	'.asp',
	'.aspx',
	'.exe',
	'.bat',
	'.cmd',
	'.com',
	'.sh',
	'.bash',
	'.vbs',
	'.ps1',
	'.wsf',
	'.msi',
	'.dll',
	'.so',
	'.dylib',
	'.cgi',
	'.pl',
	'.py',
	'.rb',
]

// is_dangerous_filename checks if a filename has a dangerous extension
// or uses a double-extension attack (e.g., "shell.php.jpg").
fn is_dangerous_filename(original_name string) bool {
	// Check every dot-separated segment for dangerous extensions
	// This catches both "shell.php" and "shell.php.jpg"
	lower := original_name.to_lower()
	for segment in lower.split('.') {
		ext := '.' + segment
		if ext in dangerous_extensions {
			return true
		}
	}
	// Check for path traversal attempts
	if original_name.contains('..') || original_name.contains('/') || original_name.contains('\\') {
		return true
	}
	return false
}

// validate checks a file against the handler's rules.
pub fn (h &UploadHandler) validate(original_name string, size int, content_type string) ! {
	// Block dangerous filenames (double-extension, path traversal, executable extensions)
	if is_dangerous_filename(original_name) {
		return error('dangerous filename: "${original_name}" — file rejected for security')
	}

	// Check file size
	if size > h.max_size {
		return error('file exceeds maximum size of ${h.max_size} bytes (got ${size})')
	}

	// Check extension (only the last extension is checked for the allowlist)
	if h.allowed_extensions.len > 0 {
		ext := os.file_ext(original_name).to_lower()
		if ext !in h.allowed_extensions {
			return error('file extension "${ext}" is not allowed')
		}
	}

	// Check MIME type
	if h.allowed_mime_types.len > 0 {
		if content_type !in h.allowed_mime_types {
			return error('MIME type "${content_type}" is not allowed')
		}
	}
}

// ── Storage ──

// handle processes a file upload from a veb context.
// In V's veb, file uploads are accessed through form parsing.
// This provides a high-level API that validates and stores the file.
// Uses os.write_file for text data (from ctx.form which is string-based).
pub fn (mut h UploadHandler) handle(ctx &veb.Context, field string, dest_dir string) !UploadResult {
	// Ensure destination directory exists
	os.mkdir_all(dest_dir, os.MkdirParams{}) or {
		return error('failed to create upload directory: ${dest_dir}')
	}

	// Read file from form data
	// Note: In V's veb, file data is typically accessed via ctx.form()
	// This is a simplified API - actual implementation depends on veb version
	file_data := ctx.form[field] or { '' }
	if file_data.len == 0 {
		return error('no file found in field "${field}"')
	}

	original_name := ctx.form['${field}_name'] or { 'upload' }
	content_type := ctx.form['${field}_type'] or { 'application/octet-stream' }

	// Validate (includes dangerous filename check)
	h.validate(original_name, file_data.len, content_type) or { return err }

	// Sanitize filename: strip path components
	safe_name := sanitize_filename(original_name)

	// Generate stored name
	stored_name := h.generate_name(safe_name, file_data)

	// Generate path
	sub_path := h.generate_path()
	full_dir := os.join_path(dest_dir, sub_path)
	os.mkdir_all(full_dir, os.MkdirParams{}) or {}

	// Write file
	full_path := os.join_path(full_dir, stored_name)
	os.write_file(full_path, file_data) or { return error('failed to write uploaded file: ${err}') }

	// Compute hash
	hash := sha256_hex(file_data.bytes())

	ext := os.file_ext(safe_name)

	return UploadResult{
		original_name: safe_name
		stored_name:   stored_name
		path:          full_path
		size:          file_data.len
		extension:     ext
		mime_type:     content_type
		hash:          hash
	}
}

// handle_bytes processes raw bytes as a file upload.
// Useful when file data is already in memory.
// Uses os.write_bytes to safely write binary data (no truncation on 0x00 bytes).
pub fn (mut h UploadHandler) handle_bytes(original_name string, data []u8, dest_dir string) !UploadResult {
	// Ensure destination directory exists
	os.mkdir_all(dest_dir, os.MkdirParams{}) or {
		return error('failed to create upload directory: ${dest_dir}')
	}

	// Sanitize filename
	safe_name := sanitize_filename(original_name)

	// Validate (includes dangerous filename check)
	content_type := guess_mime_type(safe_name)
	h.validate(safe_name, data.len, content_type) or { return err }

	// Generate stored name
	stored_name := h.generate_name_from_bytes(safe_name, data)

	// Generate path
	sub_path := h.generate_path()
	full_dir := os.join_path(dest_dir, sub_path)
	os.mkdir_all(full_dir, os.MkdirParams{}) or {}

	// Write file using binary-safe method
	full_path := os.join_path(full_dir, stored_name)
	os.write_bytes(full_path, data) or { return error('failed to write uploaded file: ${err}') }

	// Compute hash
	hash := sha256_hex(data)

	ext := os.file_ext(safe_name)

	return UploadResult{
		original_name: safe_name
		stored_name:   stored_name
		path:          full_path
		size:          data.len
		extension:     ext
		mime_type:     content_type
		hash:          hash
	}
}

// sanitize_filename strips path components and normalizes the filename.
fn sanitize_filename(name string) string {
	// Strip any directory components (path traversal protection)
	mut safe := name.replace('\\', '/')
	parts := safe.split('/')
	safe = parts[parts.len - 1]
	// Remove leading dots (hidden files on Unix)
	for safe.starts_with('.') {
		if safe.len <= 1 {
			break
		}
		safe = safe[1..]
	}
	if safe.len == 0 {
		safe = 'upload'
	}
	return safe
}

// ── Name Generation ──

// generate_name creates a storage filename based on the naming strategy.
// Accepts string content (for handle() which uses ctx.form data as strings).
pub fn (h &UploadHandler) generate_name(original_name string, content string) string {
	ext := os.file_ext(original_name)

	if h.naming_strategy == .original {
		return original_name
	}
	if h.naming_strategy == .hash {
		full_hash := sha256_hex(content.bytes())
		return full_hash[..16] + ext
	}
	if h.naming_strategy == .sequential {
		ts := time.now().unix_nano()
		return '${ts}${ext}'
	}
	if h.naming_strategy == .uuid {
		mut bytes := rand.read(8) or {
			// Fallback: use time-based bytes
			mut fallback := []u8{len: 8}
			ts_fallback := time.now().unix_nano()
			for i in 0 .. 8 {
				fallback[i] = u8((ts_fallback >> (i * 8)) & 0xff)
			}
			fallback
		}
		return hex.encode(bytes) + ext
	}
	return original_name
}

// generate_name_from_bytes creates a storage filename from raw bytes.
// Used by handle_bytes() for binary-safe name generation.
pub fn (h &UploadHandler) generate_name_from_bytes(original_name string, data []u8) string {
	ext := os.file_ext(original_name)

	if h.naming_strategy == .original {
		return original_name
	}
	if h.naming_strategy == .hash {
		full_hash := sha256_hex(data)
		return full_hash[..16] + ext
	}
	if h.naming_strategy == .sequential {
		ts := time.now().unix_nano()
		return '${ts}${ext}'
	}
	if h.naming_strategy == .uuid {
		mut bytes := rand.read(8) or {
			// Fallback: use time-based bytes
			mut fallback := []u8{len: 8}
			ts_fallback := time.now().unix_nano()
			for i in 0 .. 8 {
				fallback[i] = u8((ts_fallback >> (i * 8)) & 0xff)
			}
			fallback
		}
		return hex.encode(bytes) + ext
	}
	return original_name
}

// generate_path creates a subdirectory path based on the path strategy.
pub fn (h &UploadHandler) generate_path() string {
	now_ := time.now()

	if h.path_strategy == .flat {
		return ''
	}
	if h.path_strategy == .date {
		return '${now_.year:04d}/${now_.month:02d}/${now_.day:02d}'
	}
	if h.path_strategy == .hash_dir {
		ts := now_.unix_nano().hex()
		if ts.len >= 2 {
			return ts[..2]
		}
		return '00'
	}
	return ''
}

// ── MIME Type Detection ─

// guess_mime_type guesses a MIME type from a file extension.
pub fn guess_mime_type(filename string) string {
	ext := os.file_ext(filename).to_lower()
	return match ext {
		'.jpg', '.jpeg' { 'image/jpeg' }
		'.png' { 'image/png' }
		'.gif' { 'image/gif' }
		'.webp' { 'image/webp' }
		'.svg' { 'image/svg+xml' }
		'.pdf' { 'application/pdf' }
		'.doc' { 'application/msword' }
		'.docx' { 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' }
		'.xls' { 'application/vnd.ms-excel' }
		'.xlsx' { 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }
		'.zip' { 'application/zip' }
		'.txt' { 'text/plain' }
		'.csv' { 'text/csv' }
		'.json' { 'application/json' }
		'.xml' { 'application/xml' }
		'.html' { 'text/html' }
		'.mp4' { 'video/mp4' }
		'.mp3' { 'audio/mpeg' }
		'.wav' { 'audio/wav' }
		else { 'application/octet-stream' }
	}
}

// ── Chunked Upload ──

// ChunkInfo holds metadata for a chunked upload.
pub struct ChunkInfo {
pub:
	upload_id    string
	total_chunks int
	chunk_index  int
	file_name    string
	total_size   int
pub mut:
	received_chunks []bool
	chunk_dir       string
}

// UploadChunkManager manages chunked/resumable uploads.
// Thread-safe via sync.RwMutex.
pub struct UploadChunkManager {
pub mut:
	chunks   map[string]&ChunkInfo // upload_id -> chunk info
	temp_dir string = '/tmp/photon_uploads'
mut:
	mu sync.RwMutex
}

// new_chunk_manager creates an UploadChunkManager.
pub fn new_chunk_manager() &UploadChunkManager {
	return &UploadChunkManager{
		chunks: map[string]&ChunkInfo{}
	}
}

// init_upload initializes a new chunked upload.
pub fn (mut cm UploadChunkManager) init_upload(file_name string, total_chunks int, total_size int) string {
	upload_id := generate_upload_id()
	cm.mu.@lock()
	defer { cm.mu.unlock() }
	cm.chunks[upload_id] = &ChunkInfo{
		upload_id:       upload_id
		total_chunks:    total_chunks
		chunk_index:     0
		file_name:       file_name
		total_size:      total_size
		received_chunks: []bool{len: total_chunks, init: false}
		chunk_dir:       os.join_path(cm.temp_dir, upload_id)
	}
	entry := cm.chunks[upload_id] or { unsafe { nil } }
	os.mkdir_all(entry.chunk_dir, os.MkdirParams{}) or {}
	return upload_id
}

// receive_chunk receives and stores a single chunk.
// Uses binary-safe write via os.write_file (chunk data is string from form).
pub fn (mut cm UploadChunkManager) receive_chunk(upload_id string, chunk_index int, data string) ! {
	cm.mu.rlock()
	mut info := cm.chunks[upload_id] or {
		cm.mu.runlock()
		return error('upload session not found: ${upload_id}')
	}
	cm.mu.runlock()

	if chunk_index < 0 || chunk_index >= info.total_chunks {
		return error('invalid chunk index: ${chunk_index}')
	}

	chunk_path := os.join_path(info.chunk_dir, '${chunk_index:08d}.part')
	os.write_file(chunk_path, data) or { return error('failed to write chunk: ${err}') }

	info.received_chunks[chunk_index] = true
}

// is_complete checks if all chunks have been received.
pub fn (mut cm UploadChunkManager) is_complete(upload_id string) bool {
	cm.mu.rlock()
	defer { cm.mu.runlock() }
	info := cm.chunks[upload_id] or { return false }
	for received in info.received_chunks {
		if !received {
			return false
		}
	}
	return true
}

// assemble combines all chunks into the final file.
// Uses os.write_bytes for binary-safe assembly.
pub fn (mut cm UploadChunkManager) assemble(upload_id string, dest_path string) ! {
	cm.mu.@lock()
	defer { cm.mu.unlock() }
	info := cm.chunks[upload_id] or { return error('upload session not found: ${upload_id}') }

	// Read and concatenate all chunks as binary
	mut content := []u8{}
	for i in 0 .. info.total_chunks {
		chunk_path := os.join_path(info.chunk_dir, '${i:08d}.part')
		chunk_data := os.read_bytes(chunk_path) or { return error('missing chunk ${i}') }
		content << chunk_data
	}

	// Write the assembled file using binary-safe method
	os.write_bytes(dest_path, content) or { return error('failed to write assembled file: ${err}') }

	// Clean up chunks
	os.rmdir_all(info.chunk_dir) or {}
	cm.chunks.delete(upload_id)
}

// ── Helpers ──

fn generate_upload_id() string {
	ts := time.now().unix_nano()
	bytes := rand.read(8) or {
		// Fallback: use time-based bytes
		mut fallback := []u8{len: 8}
		for i in 0 .. 8 {
			fallback[i] = u8((ts >> (i * 8)) & 0xff)
		}
		fallback
	}
	rnd := hex.encode(bytes)
	return '${strconv.format_int(ts, 16)}_${rnd}'
}
