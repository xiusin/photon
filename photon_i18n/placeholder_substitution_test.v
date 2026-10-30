module photon_i18n

// placeholder_substitution_test.v — 占位符替换的语义边界
//
// 老实现是逐个 `msg.replace('{i}', arg)`，带来两个静默错误：
//   1. 参数值里含 "{n}" 会被下一轮当成占位符再替换一次（顺序污染）
//   2. 参数不足时占位符原样留在文案里，用户看到裸花括号
import os

fn write_bundle(name string, content string) !string {
	dir := os.join_path(os.temp_dir(), 'photon_i18n_${name}_${os.getpid()}')
	os.mkdir_all(dir)!
	os.write_file(os.join_path(dir, 'messages_en.toml'), content)!
	return dir
}

fn test_arg_value_is_not_reinterpreted() {
	// "{0} and {1}" 传 ("{1}", "x")：第一个参数里的 {1} 不能被二次展开
	dir := write_bundle('reinterp', 'm = "{0} and {1}"\n')!
	defer {
		os.rmdir_all(dir) or {}
	}
	mut ms := new_resource_bundle_message_source('messages', dir)
	ms.load_locale(.en)!
	got := ms.resolve('m', .en, '{1}', 'x')
	assert got == '{1} and x', 'got: ${got}'
}

fn test_missing_args_drop_placeholder_instead_of_leaking_braces() {
	dir := write_bundle('missing', 'items = "You have {0} of {1} items"\n')!
	defer {
		os.rmdir_all(dir) or {}
	}
	mut ms := new_resource_bundle_message_source('messages', dir)
	ms.load_locale(.en)!
	got := ms.resolve('items', .en, '3')
	assert !got.contains('{'), 'unfilled placeholders must not leak to users, got: ${got}'
	assert got.contains('3')
	assert got.contains('items')
}

fn test_double_digit_indices_are_not_swapped() {
	// 11 个参数：{1} 不能被 {10} 的替换串到
	dir := write_bundle('digits', 'm = "{0}|{1}|{10}"\n')!
	defer {
		os.rmdir_all(dir) or {}
	}
	mut ms := new_resource_bundle_message_source('messages', dir)
	ms.load_locale(.en)!
	got := ms.resolve('m', .en, 'a0', 'a1', 'a2', 'a3', 'a4', 'a5', 'a6', 'a7', 'a8', 'a9', 'a10')
	assert got == 'a0|a1|a10', 'got: ${got}'
}

fn test_braces_that_are_not_placeholders_are_kept() {
	dir := write_bundle('literal', 'm = "json: {\\"k\\": 1} and {0} and {x}"\n')!
	defer {
		os.rmdir_all(dir) or {}
	}
	mut ms := new_resource_bundle_message_source('messages', dir)
	ms.load_locale(.en)!
	got := ms.resolve('m', .en, 'V')
	assert got.contains('V')
	assert got.contains('{x}'), 'non-numeric placeholders must be left alone, got: ${got}'
	assert !got.contains('{0}')
}

fn test_no_args_leaves_template_untouched() {
	dir := write_bundle('noargs', 'm = "Hello {0}"\n')!
	defer {
		os.rmdir_all(dir) or {}
	}
	mut ms := new_resource_bundle_message_source('messages', dir)
	ms.load_locale(.en)!
	assert ms.resolve('m', .en) == 'Hello {0}'
}

fn test_empty_template_and_empty_args() {
	assert substitute_placeholders('', []) == ''
	assert substitute_placeholders('plain', ['x']) == 'plain'
	assert substitute_placeholders('{0}', []) == '{0}'
	assert substitute_placeholders('{0}', ['a']) == 'a'
	assert substitute_placeholders('{0}{0}', ['a']) == 'aa'
}
