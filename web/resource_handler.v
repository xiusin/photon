module web

// resource_handler.v - Spring ResourceHandlerRegistry equivalent
//
// Registers URL pattern → filesystem location mappings for serving static resources.
// Spring equivalent: org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry
//
// 深度集成 veb 原生静态文件能力：
//   - 预压缩文件自动检测（.gz / .zst）
//   - 即时压缩 + 磁盘缓存（小文件自动压缩并缓存）
//   - Markdown 内容协商（Accept: text/markdown）
//   - 零拷贝 sendfile 传输
import os
import compress.gzip
import compress.zstd

// ResourceHandlerMapping maps a URL pattern to one or more filesystem locations.
pub struct ResourceHandlerMapping {
pub:
	pattern   string
	locations []string
}

// StaticCompressionConfig 配置静态文件压缩行为。
// 桥接 veb.StaticHandler 的压缩配置能力。
//
// 用法：
//   resources.set_compression(StaticCompressionConfig{
//       enable: true
//       max_size: 2_000_000  // 2MB 以下自动压缩
//   })
@[params]
pub struct StaticCompressionConfig {
pub mut:
	// 是否启用自动压缩（zstd 优先，gzip 回退）
	enable bool
	// 仅 gzip 压缩（不含 zstd）
	enable_gzip_only bool
	// 仅 zstd 压缩（不含 gzip）
	enable_zstd_only bool
	// 自动压缩的最大文件大小（字节），超过此大小不压缩
	// 默认 1MB
	max_size int = 1_048_576
	// 是否启用 Markdown 内容协商
	enable_markdown_negotiation bool
}

// ResourceHandlerRegistry holds all static resource mappings.
pub struct ResourceHandlerRegistry {
pub mut:
	mappings    []ResourceHandlerMapping
	compression StaticCompressionConfig
}

pub fn new_resource_handler_registry() ResourceHandlerRegistry {
	return ResourceHandlerRegistry{
		mappings: []ResourceHandlerMapping{}
	}
}

// add_mapping registers a URL pattern → locations mapping.
pub fn (mut r ResourceHandlerRegistry) add_mapping(pattern string, locations ...string) {
	r.mappings << ResourceHandlerMapping{
		pattern:   pattern
		locations: locations
	}
}

// set_compression 配置静态文件压缩策略。
// 桥接 veb.StaticHandler 的 enable_static_compression / enable_static_gzip / enable_static_zstd。
//
// 用法：
//   resources.set_compression(enable: true, max_size: 2_000_000)
pub fn (mut r ResourceHandlerRegistry) set_compression(config StaticCompressionConfig) {
	r.compression = config
}

// resolve matches a request path against registered patterns and returns
// the first existing file path, or none.
//
// 注册一个 location 的语义是「只从这个目录取文件」，但 `os.join_path` 只是
// 字符串拼接，它不解释 `..`：
//
//   r.add_mapping('/static/**', '/srv/public')
//   GET /static/../secret.txt   =>  /srv/public/../secret.txt  =  /srv/secret.txt
//
// 越界的那一份候选现在**直接不参与匹配**，而不是「本 location 没有就去试
// 下一个」—— 后者会把同一次请求悄悄换到另一个 location 上，仍然是一次逃逸。
pub fn (r &ResourceHandlerRegistry) resolve(path string) ?string {
	// 请求路径先归一化：`/static//a.css`、`/static/./a.css`、
	// `/static/sub/../a.css` 指向同一个文件，规范化之后才能做前缀判断。
	request_path := if p := normalize_url_path(path) { p } else { return none }
	for mapping in r.mappings {
		if pattern_matches(mapping.pattern, request_path) {
			// Extract the part of path after the pattern prefix
			relative := extract_relative_path(mapping.pattern, request_path)
			// 归一化后仍以 ../ 开头，意味着这一份请求已经跳出 pattern 前缀本身。
			if escapes_pattern_prefix(relative) {
				continue
			}
			for location in mapping.locations {
				real_location := normalize_fs_path(location)
				file_path := os.join_path(real_location, relative)
				if !path_within_root(file_path, real_location) {
					continue
				}
				if os.exists(file_path) && os.is_file(file_path) {
					return file_path
				}
			}
		}
	}
	return none
}

// resolve_with_negotiation 匹配请求路径并支持内容协商。
// 如果启用 Markdown 协商且客户端发送 Accept: text/markdown，
// 优先返回 .md / .html.md / /index.html.md 变体。
//
// 桥接 veb 的 enable_markdown_negotiation 能力。
pub fn (r &ResourceHandlerRegistry) resolve_with_negotiation(path string, accept_header string) ?string {
	// Markdown 内容协商
	if r.compression.enable_markdown_negotiation && accept_header.contains('text/markdown') {
		for mapping in r.mappings {
			if pattern_matches(mapping.pattern, path) {
				relative := extract_relative_path(mapping.pattern, path)
				for location in mapping.locations {
					real_location := normalize_fs_path(location)
					base := os.join_path(real_location, relative)
					// 与 resolve() 同一道闸口：内容协商变体同样只能落在 location 内
					if escapes_pattern_prefix(relative) || !path_within_root(base, real_location) {
						continue
					}
					// 按优先级查找 Markdown 变体
					variants := [
						base + '.md',
						base + '.html.md',
						os.join_path(os.dir(base), 'index.html.md'),
					]
					for variant in variants {
						if os.exists(variant) && os.is_file(variant) {
							return variant
						}
					}
				}
			}
		}
	}

	// 常规文件解析
	return r.resolve(path)
}

// resolve_precompressed 查找预压缩文件（.gz / .zst）。
// 返回 (压缩文件路径, 编码名称) 或 none。
//
// 桥接 veb.Context.serve_precompressed_file() 逻辑。
// 仅当预压缩文件存在且修改时间 >= 原始文件时才返回。
//
// 用法：
//   if file_path, encoding := reg.resolve_precompressed(path, accept_encoding) {
//       // 直接 serve 预压缩文件，零拷贝
//   }
pub fn (r &ResourceHandlerRegistry) resolve_precompressed(path string, accept_encoding string) ?(string, string) {
	orig := r.resolve(path) or { return none }

	orig_mtime := os.file_last_mod_unix(orig)

	// zstd 优先（更好的压缩比）
	if accept_encoding.contains('zstd') {
		zst_path := orig + '.zst'
		if os.exists(zst_path) && os.is_file(zst_path) {
			zst_mtime := os.file_last_mod_unix(zst_path)
			if zst_mtime >= orig_mtime {
				return zst_path, 'zstd'
			}
		}
	}

	// gzip 回退
	if accept_encoding.contains('gzip') {
		gz_path := orig + '.gz'
		if os.exists(gz_path) && os.is_file(gz_path) {
			gz_mtime := os.file_last_mod_unix(gz_path)
			if gz_mtime >= orig_mtime {
				return gz_path, 'gzip'
			}
		}
	}

	return none
}

// compress_and_cache 即时压缩文件并缓存到磁盘。
// 返回 (压缩文件路径, 编码名称) 或 none（压缩失败或文件过大）。
//
// 桥接 veb.Context.serve_compressed_static() 逻辑。
// 压缩结果写入 .gz / .zst 文件，后续请求直接走 resolve_precompressed()。
pub fn (r &ResourceHandlerRegistry) compress_and_cache(file_path string, accept_encoding string) ?(string, string) {
	// 检查文件大小是否在阈值内
	file_size := os.file_size(file_path)
	if file_size > r.compression.max_size {
		return none
	}

	data := os.read_bytes(file_path) or { return none }

	// zstd 优先
	if accept_encoding.contains('zstd') && !r.compression.enable_gzip_only {
		zst_path := file_path + '.zst'
		compressed := zstd.compress(data) or { return none }
		os.write_file(zst_path, compressed.bytestr()) or { return none }
		return zst_path, 'zstd'
	}

	// gzip 回退
	if accept_encoding.contains('gzip') && !r.compression.enable_zstd_only {
		gz_path := file_path + '.gz'
		compressed := gzip.compress(data) or { return none }
		os.write_file(gz_path, compressed.bytestr()) or { return none }
		return gz_path, 'gzip'
	}

	return none
}

// serve reads and returns the file content for a resolved path.
pub fn (r &ResourceHandlerRegistry) serve(path string) !string {
	file_path := r.resolve(path) or { return error('resource not found: ${path}') }
	return os.read_file(file_path)!
}

// pattern_matches checks if a path matches a URL pattern.
// Supports /static/** style patterns.
fn pattern_matches(pattern string, path string) bool {
	if pattern.ends_with('/**') {
		prefix := pattern[..pattern.len - 3]
		return path.starts_with(prefix)
	}
	return pattern == path
}

// normalize_url_path 把 URL 路径规范化：合并连续斜杠、去掉 `.` 段、
// 消解 `..` 段（不跨越根）。
//
// 返回 none 表示路径本身非法（越过了根，或有 NUL 之类的控制字节）——
// 这类请求只可能是构造出来的，直接不参与资源匹配。
//
// 注意这里**不做** percent-decoding：解码发生在更外层（vercel/veb 交给
// handler 的已经是解码后的 url）。如果调用方传来的是原始编码形态，
// `%2e%2e` 在这里只是一个普通文件名，不会变成 `..`，也就不会被误判成越界。
fn normalize_url_path(path string) ?string {
	if path.contains('\x00') {
		return none
	}
	raw := if path.starts_with('/') { path } else { '/' + path }
	mut segments := []string{}
	for seg in raw.split('/') {
		match seg {
			'', '.' {
				continue
			}
			'..' {
				// 已经在根上再 `..` 就是越界，不是「回到根」
				if segments.len == 0 {
					return none
				}
				segments.delete_last()
			}
			else {
				segments << seg
			}
		}
	}
	return '/' + segments.join('/')
}

// normalize_fs_path 规范化文件系统 location：纯字面量搬运，消解 `.`/`..`，
// 保留开头的 `/`（绝对路径）或原样保留相对路径的形态。
//
// location 是服务端自己配的，通常不会有 `..`，但配置常常来自环境变量或
// `join_path(config_dir, env)`，出现 `/var/data/../public` 并不稀奇。
fn normalize_fs_path(path string) string {
	if path == '' {
		return '.'
	}
	is_abs := path.starts_with('/')
	mut segments := []string{}
	for seg in path.split('/') {
		match seg {
			'', '.' {
				continue
			}
			'..' {
				if segments.len > 0 && segments.last() != '..' {
					segments.delete_last()
				} else if !is_abs {
					segments << '..'
				}
				// 绝对路径在根上再 `..` —— 留在根，等价于「没有变化」
			}
			else {
				segments << seg
			}
		}
	}
	joined := segments.join('/')
	if is_abs {
		return '/' + joined
	}
	return if joined == '' { '.' } else { joined }
}

// escapes_pattern_prefix 判断归一化后的相对路径是否还落在 pattern 前缀之内。
fn escapes_pattern_prefix(relative string) bool {
	if relative.starts_with('/') {
		return true
	}
	return relative == '..' || relative.starts_with('../')
}

// path_within_root 判断候选文件是否仍在 location 之内。
//
// 两层：字面前缀（便宜，目标文件不存在时也能判）+ 对最深的已存在分量做
// real_path 解符号链接（挡住 root 里一个 `link -> /etc` 就绕出去的情况）。
// 与 storage/local_adapter.v 的 resolve_path 是同一套思路。
fn path_within_root(file_path string, real_location string) bool {
	literal := if real_location == '/' { '/' } else { real_location + '/' }
	if file_path != real_location && !file_path.starts_with(literal) {
		return false
	}
	mut probe := file_path
	for {
		if os.exists(probe) {
			real_probe := os.real_path(probe)
			real_root := if os.exists(real_location) { os.real_path(real_location) } else { real_location }
			return real_probe == real_root || real_probe.starts_with(real_root + '/')
		}
		parent := os.dir(probe)
		if parent == probe || parent.len == 0 {
			// 一路到根都不存在：没有可解析的链接，字面判断已经足够
			return true
		}
		probe = parent
	}
	return true
}

// extract_relative_path extracts the path after the pattern prefix.
fn extract_relative_path(pattern string, path string) string {
	if pattern.ends_with('/**') {
		prefix := pattern[..pattern.len - 2] // keep the trailing '/'
		if path.starts_with(prefix) {
			return path[prefix.len..]
		}
	}
	return path
}
