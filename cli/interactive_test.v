module cli

// interactive_test.v — ask / confirm / secret / choice / anticipate 的纯逻辑
//
// 这一组函数原先直接读写 stdin/stdout：没人能在用例里给它们答案，也就没人
// 发现 ask_required 与 choice 都有走不出去的循环。下面的用例全部作用在
// `*_from` / `parse_*` 上，输入是字符串、输出是字符串，可断言。

// ---------- ask ----------

fn test_ask_from_echoes_prompt_with_default() {
	r := ask_from('端口', '8080', '')
	assert r.prompt_out == '端口 [8080]: '
	assert r.result.valid
	// 空输入回落默认值
	assert r.result.answer == '8080'
}

fn test_ask_from_prompt_without_default() {
	r := ask_from('姓名', '', '')
	assert r.prompt_out == '姓名: '
	// 空输入且无默认值 —— 无效，而不是「答案是空串」
	assert !r.result.valid
	assert r.result.answer == ''
}

fn test_ask_from_trims_input() {
	r := ask_from('姓名', '', '  张三  ')
	assert r.result.valid
	assert r.result.answer == '张三'
}

fn test_ask_from_input_wins_over_default() {
	r := ask_from('端口', '8080', '9090')
	assert r.result.answer == '9090'
}

fn test_ask_from_whitespace_input_falls_back_to_default() {
	// 全空白等价于没答
	r := ask_from('端口', '8080', '    ')
	assert r.result.valid
	assert r.result.answer == '8080'
}

// ---------- confirm ----------

fn test_confirm_from_defaults() {
	assert confirm_from('继续', true, '').result
	assert !confirm_from('继续', false, '').result
	assert confirm_from('继续', true, '').prompt_out == '继续 [Y/n]: '
	assert confirm_from('继续', false, '').prompt_out == '继续 [y/N]: '
}

fn test_confirm_from_reads_both_forms() {
	assert confirm_from('q', false, 'y').result
	assert confirm_from('q', false, 'Y').result
	assert confirm_from('q', false, 'YES').result
	assert confirm_from('q', false, ' yes ').result
	assert !confirm_from('q', true, 'n').result
	assert !confirm_from('q', true, 'no').result
	assert !confirm_from('q', true, 'N').result
}

fn test_parse_yes_no_only_accepts_leading_y() {
	// 旧实现是 `input == 'y' || input == 'yes'`：'yeah' / 'yep' 一律 false，
	// 而 `[Y/n]` 里用户看到的是「回车即 yes」，答 yeah 显然也是 yes。
	assert parse_yes_no('yeah', false)
	assert parse_yes_no('yep', false)
	assert !parse_yes_no('nope', true)
	// 任何非 y 开头的都是 no
	assert !parse_yes_no('谁知道', true)
}

// ---------- secret ----------

fn test_secret_from_strips_newline_only() {
	assert secret_from('密码', 'hunter2\n') == 'hunter2'
	assert secret_from('密码', 'hunter2\r\n') == 'hunter2'
	// 前后空格是密码的一部分，不能 trim
	assert secret_from('密码', '  spaced  ') == '  spaced  '
}

// ---------- choice ----------

fn test_choice_prompt_lists_options() {
	p := choice_prompt('选择颜色', ['红', '蓝', '绿'])
	assert p.contains('选择颜色')
	assert p.contains('[0] 红')
	assert p.contains('[1] 蓝')
	assert p.contains('[2] 绿')
	assert p.contains('Enter choice [0-2]: ')
}

fn test_choice_prompt_empty_options_has_no_negative_range() {
	// 旧提示语会是 `Enter choice [0--1]`
	p := choice_prompt('没有选项', [])
	assert !p.contains('-1]')
}

fn test_parse_choice_valid() {
	assert parse_choice('0', 3).index == 0
	assert parse_choice('2', 3).index == 2
	assert parse_choice(' 1 ', 3).index == 1
	assert parse_choice('1', 3).err == ''
}

fn test_parse_choice_rejects_non_digits() {
	// 关键回归：`'abc'.int()` 在 V 里返回 0，旧实现会把字母当成第 0 项
	r := parse_choice('abc', 3)
	assert r.index == -1
	assert r.err != ''
	assert r.err.contains('0 and 2')
}

fn test_parse_choice_rejects_out_of_range() {
	r := parse_choice('7', 3)
	assert r.index == -1
	assert r.err.contains('out of range')

	r2 := parse_choice('3', 3)
	assert r2.index == -1
}

fn test_parse_choice_rejects_leading_zero_form() {
	// '07' 不是一个选项；旧实现的 `.int()` 会读成 7，落在越界里，
	// 但 '00' 会被读成 0 而「莫名选中第一项」。这里统一拒绝掉。
	assert parse_choice('00', 3).index == -1
	assert parse_choice('03', 3).index == -1
	assert parse_choice('0', 3).index == 0
}

fn test_parse_choice_rejects_empty_input() {
	r := parse_choice('', 3)
	assert r.index == -1
	assert r.err.contains('required')
}

fn test_parse_choice_empty_options() {
	r := parse_choice('0', 0)
	assert r.index == -1
	assert r.err.contains('No options')
}

fn test_choice_with_attempts_exits_on_eof() {
	// 用例环境里 stdin 是 EOF。旧实现是 `for {}`，这里会挂死到超时；
	// 现在必须有限次之后返回 -1。
	assert choice_with_attempts('选择', ['a', 'b'], 2) == -1
}

// ---------- anticipate ----------

fn test_anticipate_from_single_match() {
	got, unique := anticipate_from('pho', ['Photon', 'Spring'])
	assert got == 'Photon'
	assert unique
}

fn test_anticipate_from_case_insensitive_fallback() {
	got, _ := anticipate_from('ph', ['Photon', 'PHP'])
	assert got == 'Photon'
}

fn test_anticipate_from_prefers_exact_case() {
	got, _ := anticipate_from('PH', ['Photon', 'PHP'])
	assert got == 'PHP'
}

fn test_anticipate_from_no_match_keeps_input() {
	got, unique := anticipate_from('zzz', ['Photon'])
	assert got == 'zzz'
	assert !unique
}

fn test_anticipate_from_empty_input() {
	got, unique := anticipate_from('', ['Photon'])
	assert got == ''
	assert !unique
}

// ---------- ask_required ----------

fn test_ask_required_exits_on_eof() {
	// 同上：旧实现里 EOF 让 os.input 返回字面量 '<EOF>'，循环能出去，
	// 但会把 '<EOF>' 当答案返回给调用方。
	answer := ask_required('姓名')
	assert answer == ''
}
