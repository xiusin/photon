module i18n

// message_source.v - Photon i18n Module
//
// Provides internationalization (i18n) support via the MessageSource abstraction,
// mirroring Spring's org.springframework.context.MessageSource pattern.
//
// ResourceBundleMessageSource loads message bundles from TOML files named
// `{basename}_{lang}.toml` (e.g., `messages_en.toml`, `messages_zh.toml`).
// Messages support `{0}`, `{1}`, ... placeholder substitution.
//
// Usage:
//   mut ms := i18n.new_resource_bundle_message_source('messages', 'config/i18n')
//   ms.load_locale(.en)!
//   ms.load_locale(.zh)!
//   msg := ms.resolve('greeting', .zh, '张三')  // → "你好,张三"
//
// Thread-safety: all read/write operations are guarded by an RwMutex.
// Lazy loading: resolve() auto-loads the bundle on first access if not preloaded.
import os
import sync
import toml

// Locale represents a supported language/region identifier.
pub enum Locale {
	en // English
	zh // Chinese
	ja // Japanese
}

// code returns the canonical string code for the locale (e.g., 'en', 'zh', 'ja').
pub fn (l Locale) code() string {
	return match l {
		.en { 'en' }
		.zh { 'zh' }
		.ja { 'ja' }
	}
}

// locale_from_str parses a locale string into a Locale.
// Accepts common variants: 'en', 'en_US', 'en-us', 'zh_CN', 'zh-tw', 'ja_JP', etc.
// Returns none for unrecognized strings.
pub fn locale_from_str(s string) ?Locale {
	return match s.to_lower() {
		'en', 'en_us', 'en-us' { .en }
		'zh', 'zh_cn', 'zh-cn', 'zh_tw', 'zh-tw' { .zh }
		'ja', 'ja_jp', 'ja-jp' { .ja }
		else { none }
	}
}

// MessageSource is the interface for resolving internationalized messages.
// Implementations include ResourceBundleMessageSource (TOML-backed).
pub interface MessageSource {
mut:
	resolve(code string, locale Locale, args ...string) string
	resolve_or(code string, locale Locale, fallback string, args ...string) string
}

// ResourceBundleMessageSource loads messages from TOML resource bundles.
// Files are named `{basename}_{lang}.toml` (e.g., `messages_en.toml`).
// When a message is missing for the requested locale, it falls back to
// `fallback_locale` (default: English) before returning the fallback string.
pub struct ResourceBundleMessageSource {
pub:
	basename string // e.g., 'messages' → loads messages_{lang}.toml
	base_dir string // directory containing message files
pub mut:
	fallback_locale Locale = .en // locale used when the requested locale has no bundle
mut:
	mu      sync.RwMutex
	bundles map[string]map[string]string // locale_code → (code → message)
}

// new_resource_bundle_message_source creates a new ResourceBundleMessageSource.
// `basename` is the file prefix (e.g., 'messages'), `base_dir` is the directory
// containing the bundle files.
pub fn new_resource_bundle_message_source(basename string, base_dir string) &ResourceBundleMessageSource {
	return &ResourceBundleMessageSource{
		basename: basename
		base_dir: base_dir
		bundles:  map[string]map[string]string{}
	}
}

// load_locale loads the message bundle for the given locale from disk.
// If the file is not found and the locale is not the fallback locale, it
// attempts to load the fallback locale's bundle instead.
// Returns an error if neither the requested nor fallback bundle can be loaded,
// or if the TOML is invalid.
pub fn (mut rb ResourceBundleMessageSource) load_locale(locale Locale) ! {
	lang := locale.code()
	file_path := os.join_path(rb.base_dir, '${rb.basename}_${lang}.toml')

	content := os.read_file(file_path) or {
		if locale == rb.fallback_locale {
			return error('message bundle not found: ${file_path}')
		}
		// Try fallback locale
		rb.load_locale(rb.fallback_locale) or {
			return error('neither ${lang} nor fallback bundle found')
		}
		return
	}

	doc := toml.parse_text(content) or { return error('invalid TOML in ${file_path}: ${err}') }

	mut bundle := map[string]string{}
	any := doc.to_any()
	for k, v in any.as_map() {
		bundle[k] = v.string()
	}

	rb.mu.@lock()
	defer { rb.mu.unlock() }
	rb.bundles[lang] = bundle.move()
}

// ensure_loaded loads the bundle for the given locale if not already loaded.
// Errors during lazy loading are silently ignored (resolve will then fall back
// to the fallback locale or the fallback string).
fn (mut rb ResourceBundleMessageSource) ensure_loaded(locale Locale) {
	lang := locale.code()

	// Fast path: check if already loaded (read lock)
	rb.mu.rlock()
	loaded := lang in rb.bundles
	rb.mu.runlock()

	if !loaded {
		// Slow path: load the bundle (write lock acquired inside load_locale)
		rb.load_locale(locale) or {}
	}
}

// resolve looks up a message by code and locale, replacing `{0}`, `{1}`, ...
// placeholders with the provided args. Returns the code itself if the message
// is not found in any bundle.
pub fn (mut rb ResourceBundleMessageSource) resolve(code string, locale Locale, args ...string) string {
	return rb.resolve_or(code, locale, code, ...args)
}

// resolve_or looks up a message by code and locale, replacing `{0}`, `{1}`, ...
// placeholders with the provided args. Returns `fallback` if the message is
// not found in the requested locale's bundle nor the fallback locale's bundle.
pub fn (mut rb ResourceBundleMessageSource) resolve_or(code string, locale Locale, fallback string, args ...string) string {
	rb.ensure_loaded(locale)

	rb.mu.rlock()
	defer { rb.mu.runlock() }

	mut msg := rb.lookup(code, locale, fallback)

	// Replace {0}, {1}, ... placeholders with provided args
	for i, arg in args {
		msg = msg.replace('{${i}}', arg)
	}
	return msg
}

// lookup finds a message by code, falling back to the fallback locale, then
// to the fallback string. Caller must hold the read lock.
fn (rb &ResourceBundleMessageSource) lookup(code string, locale Locale, fallback string) string {
	locale_bundle := (rb.bundles[locale.code()] or {
		map[string]string{}
	}).clone()
	if msg := locale_bundle[code] {
		return msg
	}
	if locale != rb.fallback_locale {
		fb_bundle := (rb.bundles[rb.fallback_locale.code()] or {
			map[string]string{}
		}).clone()
		if msg := fb_bundle[code] {
			return msg
		}
	}
	return fallback
}
