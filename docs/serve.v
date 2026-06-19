module main

// serve.v — Photon Documentation Static File Server
//
// A lightweight V-language HTTP server for serving the Photon documentation SPA.
// Supports MIME type detection, path traversal protection, and SPA fallback routing.
//
// Usage:
//   v run docs/serve.v              # default port 8765
//   v run docs/serve.v 3000         # custom port
import os
import veb
import net.http

// ── MIME type map ──
const mime_types = {
	'.html':  'text/html; charset=utf-8'
	'.css':   'text/css; charset=utf-8'
	'.js':    'application/javascript; charset=utf-8'
	'.json':  'application/json; charset=utf-8'
	'.png':   'image/png'
	'.jpg':   'image/jpeg'
	'.jpeg':  'image/jpeg'
	'.gif':   'image/gif'
	'.svg':   'image/svg+xml'
	'.ico':   'image/x-icon'
	'.woff':  'font/woff'
	'.woff2': 'font/woff2'
	'.ttf':   'font/ttf'
	'.eot':   'application/vnd.ms-fontobject'
	'.map':   'application/json'
	'.webp':  'image/webp'
	'.webm':  'video/webm'
	'.mp4':   'video/mp4'
	'.xml':   'application/xml; charset=utf-8'
	'.txt':   'text/plain; charset=utf-8'
	'.md':    'text/markdown; charset=utf-8'
	'.pdf':   'application/pdf'
}

// DocApp — Documentation web application
pub struct DocApp {
pub mut:
	docs_dir string
}

// Context — Request-level context
pub struct Context {
	veb.Context
}

// detect_mime returns the MIME type for a file based on its extension.
fn detect_mime(path string) string {
	ext := os.file_ext(path).to_lower()
	return mime_types[ext] or { 'application/octet-stream' }
}

// is_safe_path prevents path traversal attacks.
fn is_safe_path(path string) bool {
	return !path.contains('..') && !path.contains('\\')
}

// resolve_docs_dir finds the docs directory containing index.html.
fn resolve_docs_dir() !string {
	// 1. Try relative to CWD (most common: running from project root)
	cwd := os.getwd()
	cwd_docs := os.join_path(cwd, 'docs')
	if os.exists(os.join_path(cwd_docs, 'index.html')) {
		return cwd_docs
	}

	// 2. Try relative to the source file location
	src_dir := os.dir(@FILE)
	if os.exists(os.join_path(src_dir, 'index.html')) {
		return src_dir
	}

	// 3. Try parent of source file (in case serve.v is inside docs/)
	parent_docs := os.join_path(src_dir, '..', 'docs')
	if os.exists(os.join_path(parent_docs, 'index.html')) {
		return os.real_path(parent_docs)
	}

	return error('Cannot find docs/ directory with index.html.\n' +
		'  Please run from the photon project root:\n' + '    v run docs/serve.v')
}

// parse_port extracts port number from command line args.
// Supports both `v run docs/serve.v [port]` and compiled `./serve [port]`
fn parse_port() int {
	args := os.args
	// v run puts the actual args after the script path, try last arg first
	for i := args.len - 1; i >= 1; i-- {
		arg := args[i]
		// Skip flags and the v run script path
		if arg.starts_with('-') || arg.ends_with('.v') || arg.contains('/') {
			continue
		}
		port := arg.int()
		if port > 0 && port < 65536 {
			return port
		}
		// Not a valid port, stop looking
		break
	}
	return 8765
}

// ── Route: SPA entry point ──
@['/']
pub fn (mut app DocApp) index(mut ctx Context) veb.Result {
	index_file := os.join_path(app.docs_dir, 'index.html')
	content := os.read_file(index_file) or {
		ctx.res.set_status(unsafe { http.Status(404) })
		ctx.set_content_type('text/plain; charset=utf-8')
		return ctx.text('404 — index.html not found in ${app.docs_dir}')
	}
	ctx.set_content_type('text/html; charset=utf-8')
	return ctx.text(content)
}

// ── Route: Static file serving with SPA fallback ──
@['/:path...']
pub fn (mut app DocApp) serve_static(mut ctx Context, path string) veb.Result {
	// Security: reject path traversal
	if !is_safe_path(path) {
		ctx.res.set_status(unsafe { http.Status(403) })
		ctx.set_content_type('text/plain; charset=utf-8')
		return ctx.text('403 — Forbidden')
	}

	file_path := os.join_path(app.docs_dir, path)

	// If the path is a directory, try index.html inside it
	if os.is_dir(file_path) {
		idx_path := os.join_path(file_path, 'index.html')
		if os.exists(idx_path) {
			content := os.read_file(idx_path) or {
				ctx.res.set_status(unsafe { http.Status(500) })
				return ctx.text('500 — Failed to read file')
			}
			ctx.set_content_type('text/html; charset=utf-8')
			return ctx.text(content)
		}
	}

	// Serve the file if it exists
	if os.exists(file_path) && !os.is_dir(file_path) {
		content := os.read_file(file_path) or {
			ctx.res.set_status(unsafe { http.Status(500) })
			return ctx.text('500 — Failed to read file')
		}
		ctx.set_content_type(detect_mime(file_path))
		return ctx.text(content)
	}

	// SPA fallback: if no static file matches, serve index.html
	// This handles hash-based routing on the client side.
	fallback := os.join_path(app.docs_dir, 'index.html')
	content := os.read_file(fallback) or {
		ctx.res.set_status(unsafe { http.Status(404) })
		ctx.set_content_type('text/plain; charset=utf-8')
		return ctx.text('404 — Not Found')
	}
	ctx.set_content_type('text/html; charset=utf-8')
	return ctx.text(content)
}

fn main() {
	port := parse_port()

	// Resolve docs directory
	docs_dir := resolve_docs_dir() or {
		eprintln('Error: ${err}')
		exit(1)
	}

	mut app := &DocApp{
		docs_dir: docs_dir
	}

	println('  ╔══════════════════════════════════════════════╗')
	println('  ║   ⚛️  Photon Documentation Server            ║')
	println('  ║                                              ║')
	println('  ║   http://localhost:${port.str()}                      ║')
	println('  ║   Docs:  ${docs_dir}           ║')
	println('  ║                                              ║')
	println('  ║   Press Ctrl+C to stop                       ║')
	println('  ╚══════════════════════════════════════════════╝')

	veb.run_at[DocApp, Context](mut app, host: '0.0.0.0', port: port, family: .ip) or {
		eprintln('Failed to start server: ${err}')
		exit(1)
	}
}
