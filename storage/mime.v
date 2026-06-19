module storage

// mime.v - MIME Type Detection
//
// Provides MIME type detection based on file extensions.
// Covers all common web file types.

// mime_types maps file extensions to MIME types
const mime_types = {
	// Text
	'txt':   'text/plain'
	'html':  'text/html'
	'htm':   'text/html'
	'css':   'text/css'
	'csv':   'text/csv'
	'xml':   'application/xml'
	'json':  'application/json'
	'yaml':  'application/x-yaml'
	'yml':   'application/x-yaml'
	'md':    'text/markdown'
	'log':   'text/plain'
	// JavaScript/TypeScript
	'js':    'application/javascript'
	'ts':    'application/typescript'
	'jsx':   'text/jsx'
	'tsx':   'text/tsx'
	'mjs':   'application/javascript'
	// Images
	'jpg':   'image/jpeg'
	'jpeg':  'image/jpeg'
	'png':   'image/png'
	'gif':   'image/gif'
	'svg':   'image/svg+xml'
	'webp':  'image/webp'
	'bmp':   'image/bmp'
	'ico':   'image/x-icon'
	'tiff':  'image/tiff'
	'tif':   'image/tiff'
	'avif':  'image/avif'
	'heic':  'image/heic'
	'heif':  'image/heif'
	// Audio
	'mp3':   'audio/mpeg'
	'wav':   'audio/wav'
	'ogg':   'audio/ogg'
	'flac':  'audio/flac'
	'aac':   'audio/aac'
	'm4a':   'audio/mp4'
	'wma':   'audio/x-ms-wma'
	'weba':  'audio/webm'
	// Video
	'mp4':   'video/mp4'
	'webm':  'video/webm'
	'avi':   'video/x-msvideo'
	'mov':   'video/quicktime'
	'wmv':   'video/x-ms-wmv'
	'mkv':   'video/x-matroska'
	'flv':   'video/x-flv'
	// Documents
	'pdf':   'application/pdf'
	'doc':   'application/msword'
	'docx':  'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
	'xls':   'application/vnd.ms-excel'
	'xlsx':  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
	'ppt':   'application/vnd.ms-powerpoint'
	'pptx':  'application/vnd.openxmlformats-officedocument.presentationml.presentation'
	'odt':   'application/vnd.oasis.opendocument.text'
	'ods':   'application/vnd.oasis.opendocument.spreadsheet'
	// Archives
	'zip':   'application/zip'
	'gz':    'application/gzip'
	'tar':   'application/x-tar'
	'rar':   'application/vnd.rar'
	'7z':    'application/x-7z-compressed'
	'bz2':   'application/x-bzip2'
	// Fonts
	'ttf':   'font/ttf'
	'otf':   'font/otf'
	'woff':  'font/woff'
	'woff2': 'font/woff2'
	'eot':   'application/vnd.ms-fontobject'
	// Binary
	'bin':   'application/octet-stream'
	'exe':   'application/x-msdownload'
	'dmg':   'application/x-apple-diskimage'
	'iso':   'application/x-iso9660-image'
	'apk':   'application/vnd.android.package-archive'
	// Web
	'wasm':  'application/wasm'
	'map':   'application/json'
	'v':     'text/x-v'
	'go':    'text/x-go'
	'rs':    'text/x-rust'
	'py':    'text/x-python'
	'rb':    'text/x-ruby'
	'php':   'text/x-php'
	'java':  'text/x-java'
	'c':     'text/x-c'
	'h':     'text/x-c'
	'cpp':   'text/x-c++'
	'sh':    'text/x-sh'
	'sql':   'text/x-sql'
	'toml':  'application/toml'
	'ini':   'text/plain'
	'cfg':   'text/plain'
	'env':   'text/plain'
}

// detect_mime_type detects MIME type from a file path
pub fn detect_mime_type(path string) string {
	ext := extract_extension(path)
	if ext.len > 0 {
		if mime := mime_types[ext] {
			return mime
		}
	}
	return 'application/octet-stream'
}

// detect_mime_type_from_filename is an alias for detect_mime_type
pub fn detect_mime_type_from_filename(filename string) string {
	return detect_mime_type(filename)
}

// extract_extension returns the lowercase file extension without the dot
pub fn extract_extension(path string) string {
	// Get the last segment (filename) from the path
	mut filename := path
	if filename.contains('/') {
		parts := filename.split('/')
		filename = parts[parts.len - 1]
	}

	// Extract extension after the last dot
	if filename.contains('.') {
		parts := filename.split('.')
		return parts[parts.len - 1].to_lower()
	}
	return ''
}

// is_image checks if the MIME type is an image
pub fn is_image(mime_type string) bool {
	return mime_type.starts_with('image/')
}

// is_video checks if the MIME type is a video
pub fn is_video(mime_type string) bool {
	return mime_type.starts_with('video/')
}

// is_audio checks if the MIME type is audio
pub fn is_audio(mime_type string) bool {
	return mime_type.starts_with('audio/')
}

// is_text checks if the MIME type is text-based
pub fn is_text(mime_type string) bool {
	return mime_type.starts_with('text/')
}

// extension_from_mime returns a file extension for a MIME type (reverse lookup)
pub fn extension_from_mime(mime_type string) string {
	for ext, mime in mime_types {
		if mime == mime_type {
			return ext
		}
	}
	return 'bin'
}
