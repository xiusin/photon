module i18n

// message_source_test.v - Unit tests for Photon i18n Module
// Tests: locale parsing, message resolution, placeholder substitution,
//        fallback locale behavior, lazy loading, error handling.
import os

// setup_test_bundles creates a temporary directory with English and Chinese
// message bundle files for testing. Returns the directory path.
// Caller is responsible for cleanup via cleanup_test_bundles.
fn setup_test_bundles() !string {
	tmp_dir := os.join_path(os.temp_dir(), 'photon_i18n_test_${os.getpid()}')
	if !os.exists(tmp_dir) {
		os.mkdir(tmp_dir)!
	}

	// English bundle: greeting with placeholder, farewell without, items, multi-arg
	os.write_file(os.join_path(tmp_dir, 'messages_en.toml'),
		'greeting = "Hello, {0}"\nfarewell = "Goodbye"\nitems = "You have {0} items"\nmulti = "{0} has {1} items"\n')!

	// Chinese bundle: only greeting and farewell (items missing → tests fallback)
	os.write_file(os.join_path(tmp_dir, 'messages_zh.toml'),
		'greeting = "你好,{0}"\nfarewell = "再见"\n')!

	return tmp_dir
}

fn cleanup_test_bundles(tmp_dir string) {
	os.rmdir_all(tmp_dir) or {}
}

// ============================================================
// Locale Code Tests
// ============================================================

fn test_locale_code() {
	assert Locale.en.code() == 'en'
	assert Locale.zh.code() == 'zh'
	assert Locale.ja.code() == 'ja'
}

// ============================================================
// locale_from_str Tests
// ============================================================

fn test_locale_from_str_english() ! {
	val := locale_from_str('en') or { return error('expected locale_from_str("en") to succeed') }
	assert val == Locale.en

	val2 := locale_from_str('EN') or { return error('expected locale_from_str("EN") to succeed') }
	assert val2 == Locale.en

	val3 := locale_from_str('en_US') or {
		return error('expected locale_from_str("en_US") to succeed')
	}
	assert val3 == Locale.en

	val4 := locale_from_str('en-us') or {
		return error('expected locale_from_str("en-us") to succeed')
	}
	assert val4 == Locale.en
}

fn test_locale_from_str_chinese() ! {
	val := locale_from_str('zh') or { return error('expected locale_from_str("zh") to succeed') }
	assert val == Locale.zh

	val2 := locale_from_str('ZH') or { return error('expected locale_from_str("ZH") to succeed') }
	assert val2 == Locale.zh

	val3 := locale_from_str('zh_CN') or {
		return error('expected locale_from_str("zh_CN") to succeed')
	}
	assert val3 == Locale.zh

	val4 := locale_from_str('zh-cn') or {
		return error('expected locale_from_str("zh-cn") to succeed')
	}
	assert val4 == Locale.zh

	val5 := locale_from_str('zh_tw') or {
		return error('expected locale_from_str("zh_tw") to succeed')
	}
	assert val5 == Locale.zh

	val6 := locale_from_str('zh-tw') or {
		return error('expected locale_from_str("zh-tw") to succeed')
	}
	assert val6 == Locale.zh
}

fn test_locale_from_str_japanese() ! {
	val := locale_from_str('ja') or { return error('expected locale_from_str("ja") to succeed') }
	assert val == Locale.ja

	val2 := locale_from_str('JA') or { return error('expected locale_from_str("JA") to succeed') }
	assert val2 == Locale.ja

	val3 := locale_from_str('ja_JP') or {
		return error('expected locale_from_str("ja_JP") to succeed')
	}
	assert val3 == Locale.ja

	val4 := locale_from_str('ja-jp') or {
		return error('expected locale_from_str("ja-jp") to succeed')
	}
	assert val4 == Locale.ja
}

fn test_locale_from_str_unknown_returns_none() {
	if _ := locale_from_str('fr') {
		assert false, 'expected none for unknown locale fr'
	} else {
		assert true
	}
	if _ := locale_from_str('') {
		assert false, 'expected none for empty string'
	} else {
		assert true
	}
}

// ============================================================
// ResourceBundleMessageSource Construction Tests
// ============================================================

fn test_new_resource_bundle_message_source() {
	ms := new_resource_bundle_message_source('messages', '/tmp/i18n')
	assert ms.basename == 'messages'
	assert ms.base_dir == '/tmp/i18n'
	assert ms.fallback_locale == Locale.en
}

// ============================================================
// Message Resolution Tests (explicit load)
// ============================================================

fn test_resolve_english_with_placeholder() ! {
	tmp_dir := setup_test_bundles()!
	defer { cleanup_test_bundles(tmp_dir) }

	mut ms := new_resource_bundle_message_source('messages', tmp_dir)
	ms.load_locale(Locale.en)!

	result := ms.resolve('greeting', Locale.en, 'John')
	assert result == 'Hello, John'
}

fn test_resolve_chinese_with_placeholder() ! {
	tmp_dir := setup_test_bundles()!
	defer { cleanup_test_bundles(tmp_dir) }

	mut ms := new_resource_bundle_message_source('messages', tmp_dir)
	ms.load_locale(Locale.zh)!

	result := ms.resolve('greeting', Locale.zh, '张三')
	assert result == '你好,张三'
}

fn test_resolve_without_args() ! {
	tmp_dir := setup_test_bundles()!
	defer { cleanup_test_bundles(tmp_dir) }

	mut ms := new_resource_bundle_message_source('messages', tmp_dir)
	ms.load_locale(Locale.en)!

	result := ms.resolve('farewell', Locale.en)
	assert result == 'Goodbye'
}

fn test_resolve_multiple_placeholders() ! {
	tmp_dir := setup_test_bundles()!
	defer { cleanup_test_bundles(tmp_dir) }

	mut ms := new_resource_bundle_message_source('messages', tmp_dir)
	ms.load_locale(Locale.en)!

	result := ms.resolve('multi', Locale.en, 'Alice', '5')
	assert result == 'Alice has 5 items'
}

// ============================================================
// Fallback Locale Tests
// ============================================================

fn test_fallback_to_english_when_chinese_missing() ! {
	tmp_dir := setup_test_bundles()!
	defer { cleanup_test_bundles(tmp_dir) }

	mut ms := new_resource_bundle_message_source('messages', tmp_dir)
	ms.load_locale(Locale.zh)!
	ms.load_locale(Locale.en)!

	// 'items' exists in English but not Chinese → should fall back to English
	result := ms.resolve('items', Locale.zh)
	assert result == 'You have {0} items'
}

fn test_fallback_with_placeholder() ! {
	tmp_dir := setup_test_bundles()!
	defer { cleanup_test_bundles(tmp_dir) }

	mut ms := new_resource_bundle_message_source('messages', tmp_dir)
	ms.load_locale(Locale.zh)!
	ms.load_locale(Locale.en)!

	// 'items' falls back to English, then placeholder is replaced
	result := ms.resolve('items', Locale.zh, '3')
	assert result == 'You have 3 items'
}

// ============================================================
// Missing Code Tests
// ============================================================

fn test_missing_code_returns_code_itself() ! {
	tmp_dir := setup_test_bundles()!
	defer { cleanup_test_bundles(tmp_dir) }

	mut ms := new_resource_bundle_message_source('messages', tmp_dir)
	ms.load_locale(Locale.en)!

	// resolve uses code as default fallback
	result := ms.resolve('nonexistent', Locale.en)
	assert result == 'nonexistent'
}

fn test_missing_code_with_explicit_fallback() ! {
	tmp_dir := setup_test_bundles()!
	defer { cleanup_test_bundles(tmp_dir) }

	mut ms := new_resource_bundle_message_source('messages', tmp_dir)
	ms.load_locale(Locale.en)!

	result := ms.resolve_or('nonexistent', Locale.en, 'default value')
	assert result == 'default value'
}

fn test_missing_code_with_fallback_and_placeholder() ! {
	tmp_dir := setup_test_bundles()!
	defer { cleanup_test_bundles(tmp_dir) }

	mut ms := new_resource_bundle_message_source('messages', tmp_dir)
	ms.load_locale(Locale.en)!

	result := ms.resolve_or('nonexistent', Locale.en, 'default {0}', 'value')
	assert result == 'default value'
}

// ============================================================
// Lazy Loading Tests
// ============================================================

fn test_lazy_loading_on_resolve() ! {
	tmp_dir := setup_test_bundles()!
	defer { cleanup_test_bundles(tmp_dir) }

	mut ms := new_resource_bundle_message_source('messages', tmp_dir)
	// Do NOT call load_locale — resolve should lazy-load automatically
	result := ms.resolve('farewell', Locale.en)
	assert result == 'Goodbye'
}

fn test_lazy_loading_chinese() ! {
	tmp_dir := setup_test_bundles()!
	defer { cleanup_test_bundles(tmp_dir) }

	mut ms := new_resource_bundle_message_source('messages', tmp_dir)
	// Lazy load Chinese on first resolve
	result := ms.resolve('greeting', Locale.zh, '李四')
	assert result == '你好,李四'
}

// ============================================================
// Error Handling Tests
// ============================================================

fn test_load_nonexistent_bundle_returns_error() {
	mut ms := new_resource_bundle_message_source('messages', '/nonexistent/path/i18n')
	if _ := ms.load_locale(Locale.en) {
		assert false, 'expected error for nonexistent bundle'
	} else {
		assert true
	}
}

fn test_load_nonexistent_locale_falls_back_then_errors() {
	mut ms := new_resource_bundle_message_source('messages', '/nonexistent/path/i18n')
	// Loading a non-fallback locale should try fallback, then error
	if _ := ms.load_locale(Locale.zh) {
		assert false, 'expected error when neither locale nor fallback bundle exists'
	} else {
		assert true
	}
}

fn test_resolve_with_missing_bundle_uses_fallback_string() ! {
	// When no bundle can be loaded, resolve should still return the fallback
	mut ms := new_resource_bundle_message_source('messages', '/nonexistent/path/i18n')
	result := ms.resolve_or('greeting', Locale.en, 'Hi there')
	assert result == 'Hi there'
}

// ============================================================
// Interface Conformance Test
// ============================================================

fn test_message_source_interface_conformance() ! {
	tmp_dir := setup_test_bundles()!
	defer { cleanup_test_bundles(tmp_dir) }

	mut ms := new_resource_bundle_message_source('messages', tmp_dir)
	ms.load_locale(Locale.en)!

	// Verify ResourceBundleMessageSource satisfies the MessageSource interface
	_ = MessageSource(ms)

	result := ms.resolve('greeting', Locale.en, 'World')
	assert result == 'Hello, World'
}
