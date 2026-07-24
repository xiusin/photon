module web

// mime_types maps file extensions (including leading dot, lowercase) to MIME types.
// This is the single source of truth — used by veb_mime_type(), download_mime_types, and guess_mime_type().
pub const mime_types = {
	// Text
	'.css':  'text/css'
	'.js':   'text/javascript'
	'.json': 'application/json'
	'.html': 'text/html'
	'.htm':  'text/html'
	'.xml':  'application/xml'
	'.txt':  'text/plain'
	'.md':   'text/markdown'
	'.csv':  'text/csv'

	// Images
	'.png':  'image/png'
	'.jpg':  'image/jpeg'
	'.jpeg': 'image/jpeg'
	'.gif':  'image/gif'
	'.svg':  'image/svg+xml'
	'.ico':  'image/vnd.microsoft.icon'
	'.webp': 'image/webp'

	// Fonts
	'.woff':  'font/woff'
	'.woff2': 'font/woff2'
	'.ttf':   'font/ttf'
	'.otf':   'font/otf'

	// Documents
	'.pdf':  'application/pdf'
	'.doc':  'application/msword'
	'.docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
	'.xls':  'application/vnd.ms-excel'
	'.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'

	// Archives
	'.zip': 'application/zip'
	'.gz':  'application/gzip'
	'.zst': 'application/zstd'
	'.tar': 'application/x-tar'

	// Audio / Video
	'.mp4':  'video/mp4'
	'.webm': 'video/webm'
	'.avi':  'video/x-msvideo'
	'.mp3':  'audio/mpeg'
	'.wav':  'audio/wav'

	// WebAssembly
	'.wasm': 'application/wasm'
}
