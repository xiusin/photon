module cli

// interactive.v - Interactive Input Helpers (Symfony Console inspired)
//
// Provides interactive question/answer methods for CLI commands:
//   ask()     - prompt for text input
//   confirm() - yes/no confirmation
//   secret()  - hidden input (password)
//   choice()  - select from options
//   anticipate() - autocomplete input
//
// 为什么所有入口都拆成 `*_from(line)`
// -----------------------------------
// 这组函数原先直接调 `os.input()` / `print()`，于是用例既没法提供答案，也没
// 法断言它到底问了什么 —— 一跑就挂在 stdin 上等输入，和 `CommandOutput` 之前
// 的病症完全一样。现在解析与 IO 分开：`*_from` / `parse_*` / `*_prompt` 是纯
// 函数（只吃字符串、只吐字符串），`ask()` 之类的公开签名不变，内部只是在
// `os.input_opt` 之上薄薄一层。
import os

// max_choice_attempts 是 choice 最多重问几轮
//
// 没有上限时「一直输非法值」会让 `for { }` 永远转下去。用例没法断言一个不返回
// 的函数，真实终端里它也等于把用户关进了死循环。
const max_choice_attempts = 3

// Question represents a question to ask the user
pub struct Question {
pub:
	prompt      string
	default_val string
	required    bool = true
	hidden      bool
	choices     []string
	attempts    int = 3
}

// AskResult holds the user's answer
pub struct AskResult {
pub:
	answer string
	valid  bool
}

// ask prompts the user for text input
pub fn ask(prompt string) AskResult {
	return ask_with_default(prompt, '')
}

// ask_with_default prompts with a default value
pub fn ask_with_default(prompt string, default_val string) AskResult {
	fallback := AskResult{
		valid: false
	}
	line := os.input_opt('') or { return fallback }
	r := ask_from(prompt, default_val, line)
	print(r.prompt_out)
	return r.result
}

// AskPrompt 是「提示语 + 结果」的组合
//
// 拆出这个包装是为了让提示语也变成可断言的 —— 旧代码的提示语只出现在
// `print()` 的实参里，用例不可能知道它问了什么。
pub struct AskPrompt {
pub:
	prompt_out string
	result     AskResult
}

// ask_from 是 ask_with_default 的纯逻辑部分：给定「已经读到的答案」算出结果
//
// prompt_out 是应当先打印的提示语，和返回值一起给出，调用方不必自己拼第二遍。
pub fn ask_from(prompt string, default_val string, line string) AskPrompt {
	prompt_out := if default_val.len > 0 {
		'${prompt} [${default_val}]: '
	} else {
		'${prompt}: '
	}
	input := line.trim_space()
	return AskPrompt{
		prompt_out: prompt_out
		result:     resolve_answer(input, default_val)
	}
}

// resolve_answer 把「用户输入 + 默认值」折算成 AskResult
//
// 空输入且有默认值才回落默认值；空输入且无默认值算无效。
fn resolve_answer(input string, default_val string) AskResult {
	if input.len == 0 {
		if default_val.len > 0 {
			return AskResult{
				answer: default_val
				valid:  true
			}
		}
		return AskResult{
			valid: false
		}
	}
	return AskResult{
		answer: input
		valid:  true
	}
}

// confirm asks a yes/no question
pub fn confirm(prompt string) bool {
	return confirm_with_default(prompt, false)
}

// confirm_with_default asks yes/no with a default
pub fn confirm_with_default(prompt string, default_val bool) bool {
	line := os.input_opt('') or { return default_val }
	r := confirm_from(prompt, default_val, line)
	print(r.prompt_out)
	return r.result
}

// ConfirmResult 把确认题的结果和提示语一起给出
pub struct ConfirmResult {
pub:
	prompt_out string
	result     bool
}

// confirm_from 是 confirm_with_default 的纯逻辑部分
pub fn confirm_from(prompt string, default_val bool, line string) ConfirmResult {
	default_str := if default_val { 'Y/n' } else { 'y/N' }
	answer := parse_yes_no(line, default_val)
	return ConfirmResult{
		prompt_out: '${prompt} [${default_str}]: '
		result:     answer
	}
}

// parse_yes_no 只把明确的肯定/否定读成布尔
//
// 旧实现是 `input == 'y' || input == 'yes'`，于是 n / no / 随便什么 都落到
// false —— `[Y/n]` 里用户答 `N` 和答 `谁知道` 得到同一个结论，而后者该重问。
// 现在空输入回落默认值，其余按首字母判。
pub fn parse_yes_no(line string, default_val bool) bool {
	input := line.trim_space().to_lower()
	if input.len == 0 {
		return default_val
	}
	return input[0] == `y`
}

// secret prompts for hidden input (password)
pub fn secret(prompt string) string {
	print('${prompt}: ')
	// Note: V doesn't have built-in terminal echo disable.
	// For production, use os.get_password() or a custom TTY implementation.
	return os.input_opt('') or { '' }
}

// secret_from 是 secret 的纯逻辑部分（剥掉行尾换行，不做其它加工）
pub fn secret_from(prompt string, line string) string {
	return line.trim_right('\r\n')
}

// ChoiceResult 描述一次选择题的解析结果
//
// 合法时 `err` 为空且 `index` 为选项号；非法时 `index` 为 -1 且 `err` 说明原因。
// 调用方据此决定「接受」还是「重问」，不必自己再判一次形态。
pub struct ChoiceResult {
pub:
	index int = -1
	err   string
}

// choice presents a list of options and returns the selected index
pub fn choice(prompt string, options []string) int {
	return choice_with_attempts(prompt, options, max_choice_attempts)
}

// choice_with_attempts 最多重问 attempts 轮，全不合法返回 -1
//
// 旧实现只有一个 `for {}`：非法的输入（空行、字母、越界数字）永远走不到出口，
// 终端里就是一个死循环，而且选项列表长度为 0 时提示语自身先 panic。
pub fn choice_with_attempts(prompt string, options []string, attempts int) int {
	print(choice_prompt(prompt, options))
	mut left := attempts
	for left > 0 {
		if line := read_line('') {
			r := parse_choice(line, options.len)
			if r.err == '' {
				return r.index
			}
			println(r.err)
		}
		left--
		if left > 0 {
			print('Enter choice [0-${options.len - 1}]: ')
		}
	}
	return -1
}

// read_line 读一行；stdin 已关闭时返回 none 而不是空串
//
// 这两件事在旧代码里分不开：`os.input()` 在 EOF 时返回字面量 '<EOF>'，既不是
// 空串也不可能非空 —— choice 的死循环和 ask_required 把 '<EOF>' 当答案都源于
// 此处。EOF 必须能单独表达，循环才有出口。
fn read_line(prompt string) ?string {
	if prompt.len > 0 {
		print(prompt)
	}
	return os.input_opt('')
}

// choice_prompt 渲染选择题的题面（选项按序号列出）
pub fn choice_prompt(prompt string, options []string) string {
	mut out := '${prompt}\n'
	for i, opt in options {
		out += '  [${i}] ${opt}\n'
	}
	if options.len == 0 {
		out += 'Enter choice: '
	} else {
		out += 'Enter choice [0-${options.len - 1}]: '
	}
	return out
}

// parse_choice 解析一道选择题的答案
//
// `'abc'.int()` 在 V 里返回 0 而不是报错，所以「字母」历史上一直被当成第 0 项
// 选中。这里先按十进制校验形态，再判越界；空选项列表单独报错，避免提示语里出现
// `[0--1]` 这种区间。
pub fn parse_choice(line string, option_count int) ChoiceResult {
	input := line.trim_space()
	if option_count <= 0 {
		return ChoiceResult{
			err: 'No options available.'
		}
	}
	if input.len == 0 {
		return ChoiceResult{
			err: 'A choice is required.'
		}
	}
	for ch in input {
		if ch < `0` || ch > `9` {
			return ChoiceResult{
				err: 'Please enter a number between 0 and ${option_count - 1}.'
			}
		}
	}
	// 前导 0 一律拒绝：'00' / '03' 不是任何一个选项号，而 `.int()` 会把
	// 前者读成 0、后者读成 3 —— 一个「莫名选中第一项」，一个「越界」，
	// 两种结果都不该由一个非法输入产生。
	if input.len > 1 && input[0] == `0` {
		return ChoiceResult{
			err: 'Please enter a number between 0 and ${option_count - 1}.'
		}
	}
	idx := input.int()
	if idx >= option_count {
		return ChoiceResult{
			err: 'Choice ${idx} is out of range (0-${option_count - 1}).'
		}
	}
	return ChoiceResult{
		index: idx
	}
}

// anticipate provides autocomplete input (stub)
pub fn anticipate(prompt string, completions []string) string {
	print('${prompt}: ')
	// In production, would use a library like readline for autocomplete
	return os.input_opt('') or { '' }
}

// anticipate_from 按前缀补全
//
// 返回 `(补全结果, 是否唯一匹配)`。`anticipate` 保持原样，因为它要的是真实
// 按键数据（readline 才能给）；纯逻辑放在这里，用例才能断言「敲 Pho 补成
// Photon」而不是「敲 Pho 得到 Pho」。
pub fn anticipate_from(line string, completions []string) (string, bool) {
	input := line.trim_space()
	if input.len == 0 {
		return '', false
	}
	mut lower_matches := []string{}
	mut exact_matches := []string{}
	for c in completions {
		if c.to_lower().starts_with(input.to_lower()) {
			lower_matches << c
			if c.starts_with(input) {
				exact_matches << c
			}
		}
	}
	// 大小写完全匹配优先：用户已经敲对了大小写，就别拿别的候选顶掉
	matches := if exact_matches.len > 0 { exact_matches } else { lower_matches }
	if matches.len == 0 {
		return input, false
	}
	return matches[0], matches.len == 1
}

// ask_required keeps asking until a non-empty answer is given
//
// 用 read_line 而不是 os.input：后者在 EOF 时返回字面量 '<EOF>'，既不是空
// 也不可能非空，循环能出去，但会把一个假答案交给调用方。stdin 关闭时直接
// 返回空串，让「没拿到」和「答了空」两件事在返回类型上分得开。
pub fn ask_required(prompt string) string {
	mut round := 0
	for {
		line := read_line('${prompt}: ') or { return '' }
		result := ask_from(prompt, '', line).result
		if result.valid && result.answer.len > 0 {
			return result.answer
		}
		round++
		if round >= max_choice_attempts {
			return ''
		}
		eprintln('This field is required.')
	}
	return ''
}
