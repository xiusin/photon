module config

// environment.v - Environment Abstraction (Spring Environment inspired)
//
// Provides unified property access across multiple property sources,
// active profile management, and placeholder resolution.

// PropertySource is a source of configuration properties.
// Methods use mut receiver to support lazy loading of property data.
pub interface PropertySource {
	name() string
mut:
	get_property(key string) ?string
	contains_property(key string) bool
	get_all_with_prefix(prefix string) map[string]string
}

// Environment provides unified property access over a list of PropertySource.
//
// 这是 config 包自己的实现，与 core.Environment 是两个类型：
//   - core.Environment：应用运行时环境（profile / TOML / CLI 参数），并发安全
//   - config.Environment：轻量属性解析器，只依赖 PropertySource 接口
//
// 两者职责不同，所以这里**不是**废弃别名。之前挂的 @[deprecated] 会让任何
// 使用它的代码在 -prod 下直接编译失败（废弃告警被升级成 error），已移除。
pub struct Environment {
pub mut:
	property_sources []&PropertySource
	active_profiles  []string
mut:
	source_cache    map[string]string
	cache_valid     bool
	profile_sources map[string]&PropertySource
}

// new_environment creates an Environment
pub fn new_environment() &Environment {
	return &Environment{
		profile_sources: map[string]&PropertySource{}
	}
}

// add_source registers a property source
pub fn (mut e Environment) add_source(source &PropertySource) {
	e.property_sources << source
	e.cache_valid = false
}

// sources 返回已注册的属性源（按注册顺序）。
//
// 用 `&PropertySource` 直接遍历调用方的容器时，V 会按接口对象取方法，
// 容易踩到「拿到的是副本/悬垂槽位」那类问题（orm 的 Specification 已经
// 中过一次）。统一走这个 accessor，容器只有一份。
pub fn (e &Environment) sources() []&PropertySource {
	return e.property_sources
}

// overlay_sources 返回按优先级从低到高的属性源：注册顺序在前，
// environment.profiles 展开出的 profile 源在后。
//
// 这是「profile 覆盖基础配置」的**唯一**落地点。以前注册顺序就是
// 优先级顺序，而 set_profiles 只往 active_profiles 里写、从没参与过
// 覆盖顺序 —— 先注册 application-dev.yml 再注册 application.yml 时，
// dev 的配置会被基础配置原样盖回去，而两边都"加载成功"。
pub fn (e &Environment) overlay_sources() []&PropertySource {
	mut ordered := e.property_sources.clone()
	for profile in e.active_profiles {
		profile_source := e.profile_sources[profile] or { continue }
		ordered << profile_source
	}
	return ordered
}

// register_profile_source 把一个 profile 专属的属性源绑到 profile 名上。
// 同名重复注册时后注册的覆盖先注册的（同一 profile 只应有一份配置）。
pub fn (mut e Environment) register_profile_source(profile string, source &PropertySource) {
	unsafe {
		e.profile_sources[profile] = source
	}
	e.cache_valid = false
}

// build_cache builds the full merge cache by calling get_all_with_prefix('') on
// all sources. Sources are iterated in forward order so that later sources
// (higher priority) override earlier ones. This matches get_property's reverse
// traversal semantics: the last source with a key wins.
fn (mut e Environment) build_cache() {
	e.source_cache = map[string]string{}
	// Iterate forward: later sources override earlier (highest priority wins)
	for mut source in e.overlay_sources() {
		for key, value in source.get_all_with_prefix('') {
			e.source_cache[key] = value
		}
	}
	e.cache_valid = true
}

// add_profile activates a profile
pub fn (mut e Environment) add_profile(profile string) {
	e.active_profiles << profile
}

// set_profiles replaces all active profiles
pub fn (mut e Environment) set_profiles(profiles []string) {
	e.active_profiles = profiles.clone()
}

// get_active_profiles returns active profiles
pub fn (e &Environment) get_active_profiles() []string {
	return e.active_profiles.clone()
}

// accepts_profile checks if a profile is active
pub fn (e &Environment) accepts_profile(profile string) bool {
	return profile in e.active_profiles
}

// get_property retrieves a property from any source
pub fn (mut e Environment) get_property(key string) ?string {
	// Fast path: O(1) cache lookup
	if e.cache_valid {
		if val := e.source_cache[key] {
			return val
		}
		return none
	}

	// Build the full merge cache on first access (lazy)
	e.build_cache()

	// O(1) lookup from the now-built cache
	if val := e.source_cache[key] {
		return val
	}
	return none
}

// get_property_or retrieves a property with default
pub fn (mut e Environment) get_property_or(key string, default_val string) string {
	val := e.get_property(key) or { return default_val }
	return val
}

// contains_property checks if any source has the property
pub fn (mut e Environment) contains_property(key string) bool {
	for mut source in e.property_sources {
		if source.contains_property(key) {
			return true
		}
	}
	return false
}

// resolve_placeholders replaces ${key} and ${key:default} placeholders with
// property values. Supports nested placeholders like ${app.${env}.host}.
//
// Placeholder syntax (Spring-style):
//   ${key}           — resolved to the property value; empty string if not found
//   ${key:default}   — resolved to the property value; 'default' if not found
//   ${app.${env}.host} — inner placeholder resolved first, then outer
//
// Circular references are detected and replaced with an error marker
// (e.g., "${a→b→a}" when a references b which references a).
//
// Example:
//   env.add_source(...)
//   env.resolve_placeholders('jdbc://${db.host:localhost}:${db.port:5432}/${db.name}')
//   // → 'jdbc://localhost:5432/mydb' (when db.name=mydb)
//
// Spring equivalent: PropertySourcesPlaceholderConfigurer
pub fn (mut e Environment) resolve_placeholders(value string) string {
	return e.resolve_placeholders_with_visited(value, []string{})
}

// resolve_placeholders_with_visited carries a visited set to detect
// circular placeholder references (e.g., ${a} → ${b} → ${a}).
fn (mut e Environment) resolve_placeholders_with_visited(text string, visited []string) string {
	mut result := text
	mut start := 0
	dollar := '$'
	open_pattern := dollar + '{'
	for {
		open_pos := result.index_after(open_pattern, start) or { break }

		// Find the matching closing '}', handling nested ${...}
		close_pos := find_matching_brace(result, open_pos)
		if close_pos < 0 {
			break
		}

		placeholder := result[open_pos + 2..close_pos]

		// Recursively resolve nested placeholders inside the key first
		// e.g., ${app.${env}.host} → resolve ${env} first → ${app.dev.host}
		mut resolved_key_part := placeholder
		if placeholder.contains(open_pattern) {
			resolved_key_part = e.resolve_placeholders_with_visited(placeholder, visited)
		}

		// Support default values: ${key:default}
		// Split on the FIRST ':' only (default value may contain ':')
		parts := resolved_key_part.split_nth(':', 2)
		key := parts[0]
		default_val := if parts.len > 1 { parts[1] } else { '' }

		// Check for circular reference
		if key in visited {
			cycle_path := visited.join('→') + '→' + key
			result = result[..open_pos] + '\${' + cycle_path + '}' + result[close_pos + 1..]
			break
		}

		resolved_raw := e.get_property_or(key, default_val)
		// Recursively resolve if the value itself contains placeholders.
		mut resolved := resolved_raw
		if resolved_raw.contains(open_pattern) {
			mut new_visited := visited.clone()
			new_visited << key
			resolved = e.resolve_placeholders_with_visited(resolved_raw, new_visited)
		}

		// Scan position is a property of the *text being scanned*, not of the
		// rebuilt string. The previous version advanced `start` by the length
		// of the resolved value, which only stayed correct when the placeholder
		// sat at offset 0 — otherwise the next placeholder could be skipped (or
		// the same one re-resolved) as soon as a substitution changed the length
		// of the text in front of it.
		//
		// Typed as i64 so V's smartcast machinery keeps rejecting a possibly
		// negative value instead of converting it to an array index.
		next_start := i64(open_pos) + i64(resolved.len)
		result = result[..open_pos] + resolved + result[close_pos + 1..]
		if next_start >= i64(result.len) {
			break
		}
		start = int(next_start)
	}
	return result
}

// find_matching_brace finds the index of the matching '}' for a '${' at open_pos.
// Handles nested ${...} by tracking brace depth.
// Returns -1 if no matching brace is found.
fn find_matching_brace(text string, open_pos int) int {
	mut depth := 1
	mut i := open_pos + 2 // skip past '${'
	for i < text.len {
		if text[i] == `}` {
			depth--
			if depth == 0 {
				return i
			}
		} else if i + 1 < text.len && text[i] == `$` && text[i + 1] == `{` {
			depth++
			i++ // skip the '{' as well
		}
		i++
	}
	return -1
}

// has_property checks if a property exists in any source
// Alias for contains_property for API consistency with core.Environment
pub fn (mut e Environment) has_property(key string) bool {
	return e.contains_property(key)
}

// get_by_prefix returns all properties from all sources that start with the given prefix.
// Later-added sources override earlier ones for the same key.
//
// Spring equivalent: Environment.getProperty("prefix.*")
// Useful for binding all "app.database.*" properties into a config struct.
//
// Example:
//   env.get_by_prefix('app.database.')
//   // Returns: { 'app.database.host': 'localhost', 'app.database.port': '5432' }
pub fn (mut e Environment) get_by_prefix(prefix string) map[string]string {
	mut result := map[string]string{}
	// Check sources in forward order so later sources override；
	// profile 源排最后，于是 profile 值覆盖基础配置。
	for mut source in e.overlay_sources() {
		for key, value in source.get_all_with_prefix(prefix) {
			result[key] = value
		}
	}
	return result
}

// get_subtree returns all properties under a prefix, with the prefix stripped.
// This is useful for binding nested configuration into structs.
//
// Example:
//   // Properties: { 'app.db.host': 'localhost', 'app.db.port': '5432' }
//   env.get_subtree('app.db.')
//   // Returns: { 'host': 'localhost', 'port': '5432' }
pub fn (mut e Environment) get_subtree(prefix string) map[string]string {
	all := e.get_by_prefix(prefix)
	mut result := map[string]string{}
	for key, value in all {
		stripped := key[prefix.len..]
		if stripped.len > 0 {
			result[stripped] = value
		}
	}
	return result
}

// has_any_profile checks if any profile is active
pub fn (e &Environment) has_any_profile() bool {
	return e.active_profiles.len > 0
}

// is_production checks if 'prod' or 'production' profile is active
pub fn (e &Environment) is_production() bool {
	return e.accepts_profile('prod') || e.accepts_profile('production')
}
