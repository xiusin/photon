module web

// assets.v — 前端资源管理与压缩合并
//
// 桥接 veb.assets.AssetManager 的能力：
//   - 递归扫描目录，自动发现 CSS/JS 文件
//   - 文件合并（combine）— 多个文件合成一个请求
//   - 基础 minify（minify_css, minify_js）
//   - 缓存目录管理，自动清理过期缓存
//   - 模板中 include 引用
//
// Spring 等价：Spring Boot 的 ResourceResolver + ResourceChain
//
// 用法：
//   mut am := web.new_asset_manager()
//   am.handle_assets('./public/css')!
//   am.handle_assets('./public/js')!
//   am.minify = true
//   am.cache_dir = './.cache/assets'
//   combined_path := am.combine(.css)!
//   // 在模板中引用
//   html := am.include(.css, 'main.css')
import os
import strings
import veb

// AssetType 资源类型
pub enum AssetType {
	css
	js
	all
}

// Asset 表示一个前端资源文件
pub struct Asset {
pub:
	kind          AssetType
	file_path     string
	last_modified i64
	include_name  string
}

// AssetManager 管理前端资源（CSS/JS）。
// 桥接 veb.assets.AssetManager。
//
// 功能：
//   - 递归扫描目录，自动发现 CSS/JS 文件
//   - 可选 minify（压缩空白和换行）
//   - combine() 将多个文件合并为一个
//   - include() 生成 HTML 标签引用
//   - 缓存管理，自动清理过期文件
pub struct AssetManager {
mut:
	css               []Asset
	js                []Asset
	cached_file_names []string
pub mut:
	// 是否启用 minify
	minify bool
	// 缓存目录（用于存储 minified/combined 文件）
	cache_dir string
	// 合并文件的名称前缀
	combined_file_name string = 'combined'
}

// new_asset_manager 创建资源管理器。
// 桥接 veb.assets.AssetManager 默认构造。
//
// 用法：
//   mut am := web.new_asset_manager()
//   am.minify = true
//   am.cache_dir = './.cache/assets'
pub fn new_asset_manager() AssetManager {
	return AssetManager{}
}

// handle_assets 递归扫描目录并添加所有 CSS/JS 文件。
// 桥接 veb.assets.AssetManager.handle_assets()。
//
// 用法：
//   am.handle_assets('./public/css')!
//   am.handle_assets('./public/js')!
pub fn (mut am AssetManager) handle_assets(directory_path string) ! {
	am.add_asset_directory(directory_path, '')!
}

// handle_assets_at 递归扫描目录，并给所有资源添加前缀。
// 桥接 veb.assets.AssetManager.handle_assets_at()。
//
// 用法：
//   am.handle_assets_at('./public/css', '/css')!
//   // main.css → /css/main.css
pub fn (mut am AssetManager) handle_assets_at(directory_path string, prepend string) ! {
	am.add_asset_directory(directory_path, prepend.trim_right('/'))!
}

// add_asset_directory 递归扫描目录的内部实现。
fn (mut am AssetManager) add_asset_directory(directory_path string, traversed_path string) ! {
	files := os.ls(directory_path) or {
		return error('cannot read directory: ${directory_path}')
	}

	for file in files {
		full_path := os.join_path(directory_path, file)
		relative_path := os.join_path(traversed_path, file)

		if os.is_dir(full_path) {
			am.add_asset_directory(full_path, relative_path)!
		} else {
			ext := os.file_ext(full_path)
			match ext {
				'.css' { am.add(.css, full_path, relative_path)! }
				'.js' { am.add(.js, full_path, relative_path)! }
				else {}
			}
		}
	}
}

// get_assets 获取指定类型的所有资源。
// 桥接 veb.assets.AssetManager.get_assets()。
pub fn (am &AssetManager) get_assets(asset_type AssetType) []Asset {
	return match asset_type {
		.css {
			am.css
		}
		.js {
			am.js
		}
		.all {
			mut assets := []Asset{}
			assets << am.css
			assets << am.js
			assets
		}
	}
}

// add 添加一个资源文件。
// 桥接 veb.assets.AssetManager.add()。
//
// 如果启用了 minify 且 cache_dir 已设置，
// 会自动 minify 并缓存文件。
pub fn (mut am AssetManager) add(asset_type AssetType, file_path string, include_name string) ! {
	if asset_type == .all {
		return error('cannot add asset of type "all"')
	}
	if !os.exists(file_path) {
		return error('file "${file_path}" does not exist')
	}

	last_modified := os.file_last_mod_unix(file_path)

	mut real_path := file_path

	if am.minify {
		if am.cache_dir != '' && os.exists(am.cache_dir) == false {
			os.mkdir_all(am.cache_dir)!
		}

		if am.cache_dir != '' {
			output_path, is_cached := am.minify_and_cache(asset_type, file_path, last_modified,
				include_name)!
			if is_cached == false && am.exists(asset_type, include_name) {
				return
			}
			real_path = output_path
		}
	}

	asset := Asset{
		kind:          asset_type
		file_path:     real_path
		last_modified: last_modified
		include_name:  include_name
	}

	match asset_type {
		.css { am.css << asset }
		.js { am.js << asset }
		else {}
	}
}

// exists 检查指定资源是否已添加。
// 桥接 veb.assets.AssetManager.exists()。
pub fn (am &AssetManager) exists(asset_type AssetType, include_name string) bool {
	assets := am.get_assets(asset_type)
	return assets.any(it.include_name == include_name)
}

// include 生成 HTML 引用标签。
// 桥接 veb.assets.AssetManager.include()。
//
// 用法：
//   // 在模板中
//   @{am.include(.css, 'main.css')}
//   // 输出: <link rel="stylesheet" href="/main.css">
//
//   @{am.include(.js, 'app.js')}
//   // 输出: <script src="/app.js"></script>
pub fn (am &AssetManager) include(asset_type AssetType, include_name string) veb.RawHtml {
	assets := am.get_assets(asset_type)
	for asset in assets {
		if asset.include_name == include_name {
			mut real_path := asset.file_path
			if real_path.len > 0 && real_path[0] != `/` && !os.is_abs_path(real_path) {
				real_path = '/${asset.file_path}'
			}

			return match asset_type {
				.css {
					'<link rel="stylesheet" href="${real_path}">'
				}
				.js {
					'<script src="${real_path}"></script>'
				}
				else {
					eprintln('[assets] can only include css or js assets')
					''
				}
			}
		}
	}
	eprintln('[assets] no asset with include name "${include_name}" exists!')
	return ''
}

// combine 将指定类型的所有资源合并为一个文件。
// 桥接 veb.assets.AssetManager.combine()。
//
// 用法：
//   combined_css := am.combine(.css)!
//   // 返回合并后的文件路径
pub fn (mut am AssetManager) combine(asset_type AssetType) !string {
	if asset_type == .all {
		am.combine(.css)!
		am.combine(.js)!
		return ''
	}
	if am.cache_dir == '' {
		return error('cannot combine assets: cache directory is not set')
	}
	if !os.exists(am.cache_dir) {
		os.mkdir_all(am.cache_dir)!
	}

	assets := am.get_assets(asset_type)
	combined_file_path := os.join_path(am.cache_dir, '${am.combined_file_name}.${asset_type}')
	mut f := os.create(combined_file_path)!

	for asset in assets {
		bytes := os.read_bytes(asset.file_path)!
		f.write(bytes)!
		f.write_string('\n')!
	}

	f.close()
	return combined_file_path
}

// cleanup_cache 清理缓存目录中不再使用的文件。
// 桥接 veb.assets.AssetManager.cleanup_cache()。
pub fn (mut am AssetManager) cleanup_cache() ! {
	if am.cache_dir == '' {
		return error('cache directory is not set')
	}
	cached_files := os.ls(am.cache_dir)!

	for file in cached_files {
		ext := os.file_ext(file)
		if ext !in ['.css', '.js'] || file in am.cached_file_names {
			continue
		} else if !file.starts_with(am.combined_file_name) {
			os.rm(os.join_path(am.cache_dir, file))!
		}
	}
}

// minify_and_cache 压缩并缓存文件。
// 桥接 veb.assets.AssetManager.minify_and_cache()。
fn (mut am AssetManager) minify_and_cache(asset_type AssetType, file_path string, last_modified i64, include_name string) !(string, bool) {
	if asset_type == .all {
		return error('cannot minify asset of type "all"')
	}
	if am.cache_dir == '' {
		return error('cache directory is not set')
	}

	cache_key := am.get_cache_key(file_path, last_modified)
	output_file := '${cache_key}.${asset_type}'
	output_path := os.join_path(am.cache_dir, output_file)

	if os.exists(output_path) {
		am.cached_file_names << output_file
		return output_path, false
	}

	// 清理旧的缓存文件
	cached_files := os.ls(am.cache_dir)!
	hash := cache_key.all_before('-')
	for file in cached_files {
		if file.starts_with(hash) {
			os.rm(os.join_path(am.cache_dir, file))!
		}
	}

	txt := os.read_file(file_path)!
	minified := match asset_type {
		.css { minify_css(txt) }
		.js { minify_js(txt) }
		else { '' }
	}
	os.write_file(output_path, minified)!

	am.cached_file_names << output_file
	return output_path, true
}

// get_cache_key 生成缓存键。
// 桥接 veb.assets.AssetManager.get_cache_key()。
fn (mut am AssetManager) get_cache_key(file_path string, last_modified i64) string {
	abs_path := if os.is_abs_path(file_path) { file_path } else { os.resource_abs_path(file_path) }
	return '${abs_path.hash()}-${last_modified}'
}

// minify_css 压缩 CSS（基础实现）。
// 桥接 veb.assets.minify_css()。
pub fn minify_css(css string) string {
	mut lines := css.split('\n')
	mut sb := strings.new_builder(lines.len * 20)
	defer {
		unsafe { sb.free() }
	}
	for line in lines {
		trimmed := line.trim_space()
		if trimmed != '' {
			sb.write_string(trimmed)
		}
	}
	return sb.str()
}

// minify_js 压缩 JavaScript（基础实现）。
// 桥接 veb.assets.minify_js()。
pub fn minify_js(js string) string {
	mut lines := js.split('\n')
	mut sb := strings.new_builder(lines.len * 40)
	defer {
		unsafe { sb.free() }
	}
	for line in lines {
		trimmed := line.trim_space()
		if trimmed != '' {
			sb.write_string(trimmed)
			sb.write_u8(` `)
		}
	}
	return sb.str()
}
