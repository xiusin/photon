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
pub:
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
	mappings  []ResourceHandlerMapping
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
pub fn (r &ResourceHandlerRegistry) resolve(path string) ?string {
	for mapping in r.mappings {
		if pattern_matches(mapping.pattern, path) {
			// Extract the part of path after the pattern prefix
			relative := extract_relative_path(mapping.pattern, path)
			for location in mapping.locations {
				file_path := os.join_path(location, relative)
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
					base := os.join_path(location, relative)
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
