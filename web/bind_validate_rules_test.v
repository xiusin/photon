module web

// bind_validate_rules_test.v — `@[validate: 'min:..; max:..; len:..']` 的覆盖面
//
// 这一组盯的是 validate_struct() 里那几个 `$if field.typ is ...` 分支。
//
// 缺陷的形状：`bind` / `bind_json` / `bind_request_body` / `bind_and_validate`
// 这四个入口，以及 `validate_struct()` 本身，**在全仓库里一条用例都没有**
// （`grep -rn bind_request_body --include=*_test.v` 是空集）。所以分支漏一个
// 也不会有人知道。
//
// 漏掉的分支是 `min` / `max` 只覆盖 `int`：其余七种数值类型（i8 / i16 / i64 /
// u8 / u16 / u64 / f32 / f64）的数值规则写上去，编译通过、运行时静默跳过。
// 表格显示 `@[validate: 'min:18']`，请求带 `age=-5` 照样进业务层。
//
// 一条容易被忽略的边界：`int` 分支在字段**缺席**时也会报错。字段值是 0、
// 规则是 `min:1`，于是「没传这个字段」和「传了 0」得到同一个结论 ——
// 这是另一个方向的错（把可选字段变成必填），但不在这组用例的取舍范围内：
// `@[required]` 才是「必须传」的表达方式。这里把现状钉成事实，免得
// 下次改数值分支时顺手把它改了却没人发现。
import os
import veb

// ── 每个数值类型一个结构体 ──
//
// 必须分开写：同一个结构体里放一个 `int` 字段，`int` 分支就会先报错，
// 后面字段的结论全被盖住 —— 我第一次写探针时就撞上了这个，拿到的
// 七条「未拦下」全是 `i_field` 那一条的重复。

struct MinMaxInt {
	v int @[validate: 'min:18; max:120']
}

struct MinMaxI8 {
	v i8 @[validate: 'min:18; max:120']
}

struct MinMaxI16 {
	v i16 @[validate: 'min:18; max:120']
}

struct MinMaxI64 {
	v i64 @[validate: 'min:18; max:120']
}

struct MinMaxU8 {
	v u8 @[validate: 'min:1; max:10']
}

struct MinMaxU16 {
	v u16 @[validate: 'min:1; max:10']
}

struct MinMaxU64 {
	v u64 @[validate: 'min:1; max:10']
}

struct MinMaxF32 {
	v f32 @[validate: 'min:1; max:10']
}

struct MinMaxF64 {
	v f64 @[validate: 'min:1; max:10']
}

// ── required 的类型覆盖面 ──
//
// 和上面同一组形状：`@[required]` 原来只写了 string / int / i64 / f64 四个分支，
// 其余七个数值类型（i8 / i16 / u8 / u16 / u32 / u64 / f32）编译通过、运行时
// 一个字都不检查。字段缺席时值是零值，结构体照常构造成功。
//
// 每类型一个结构体，理由同上：同结构体里放一个 `int` 字段会盖住后面的结论。
struct ReqString {
	v string @[required]
}

struct ReqInt {
	v int @[required]
}

struct ReqI8 {
	v i8 @[required]
}

struct ReqI16 {
	v i16 @[required]
}

struct ReqI64 {
	v i64 @[required]
}

struct ReqU8 {
	v u8 @[required]
}

struct ReqU16 {
	v u16 @[required]
}

struct ReqU32 {
	v u32 @[required]
}

struct ReqU64 {
	v u64 @[required]
}

struct ReqF32 {
	v f32 @[required]
}

struct ReqF64 {
	v f64 @[required]
}

struct RequiredAndRules {
	name string @[required; validate: 'len:2..5']
	age  int    @[validate: 'min:1']
}

// rule_ctx 造一个带查询参数的上下文。
//
// 只走 `ctx.query`：extract_params() 还会解析 `ctx.req.url` 的查询串当兜底，
// 两条路都填上会让「参数到底从哪来」变成一个和本组用例无关的变量。
fn rule_ctx(params map[string]string) &veb.Context {
	return &veb.Context{
		query: params
	}
}

// rejected 跑一次 bind_and_validate，返回「是否被拦下」。
//
// 只看布尔值，不比对报错文案：文案是给人读的，锁死它会让改一个措辞就红一整片。
fn rejected[T](params map[string]string) bool {
	mut ok := true
	bind_and_validate[T](rule_ctx(params)) or { ok = false }
	return !ok
}

// ── 一、每种数值类型的 min / max 都要生效 ──

fn test_int_min_max() {
	assert rejected[MinMaxInt]({'v': '17'}), 'int: 17 应小于 min:18'
	assert !rejected[MinMaxInt]({'v': '18'})
	assert rejected[MinMaxInt]({'v': '121'}), 'int: 121 应大于 max:120'
	assert !rejected[MinMaxInt]({'v': '120'})
}

fn test_i8_min_max() {
	assert rejected[MinMaxI8]({'v': '17'}), 'i8: 17 应小于 min:18'
	assert !rejected[MinMaxI8]({'v': '18'})
	assert rejected[MinMaxI8]({'v': '121'}), 'i8: 121 应大于 max:120'
}

fn test_i16_min_max() {
	assert rejected[MinMaxI16]({'v': '17'}), 'i16: 17 应小于 min:18'
	assert !rejected[MinMaxI16]({'v': '18'})
	assert rejected[MinMaxI16]({'v': '121'}), 'i16: 121 应大于 max:120'
}

fn test_i64_min_max() {
	assert rejected[MinMaxI64]({'v': '17'}), 'i64: 17 应小于 min:18'
	assert !rejected[MinMaxI64]({'v': '18'})
	assert rejected[MinMaxI64]({'v': '121'}), 'i64: 121 应大于 max:120'
}

fn test_u8_min_max() {
	assert rejected[MinMaxU8]({'v': '0'}), 'u8: 0 应小于 min:1'
	assert !rejected[MinMaxU8]({'v': '1'})
	assert rejected[MinMaxU8]({'v': '11'}), 'u8: 11 应大于 max:10'
}

fn test_u16_min_max() {
	assert rejected[MinMaxU16]({'v': '0'}), 'u16: 0 应小于 min:1'
	assert !rejected[MinMaxU16]({'v': '1'})
	assert rejected[MinMaxU16]({'v': '11'}), 'u16: 11 应大于 max:10'
}

fn test_u64_min_max() {
	assert rejected[MinMaxU64]({'v': '0'}), 'u64: 0 应小于 min:1'
	assert !rejected[MinMaxU64]({'v': '1'})
	assert rejected[MinMaxU64]({'v': '11'}), 'u64: 11 应大于 max:10'
}

fn test_f32_min_max() {
	assert rejected[MinMaxF32]({'v': '0'}), 'f32: 0 应小于 min:1'
	assert !rejected[MinMaxF32]({'v': '1'})
	assert rejected[MinMaxF32]({'v': '11'}), 'f32: 11 应大于 max:10'
}

fn test_f64_min_max() {
	assert rejected[MinMaxF64]({'v': '0'}), 'f64: 0 应小于 min:1'
	assert !rejected[MinMaxF64]({'v': '1'})
	assert rejected[MinMaxF64]({'v': '11'}), 'f64: 11 应大于 max:10'
}

// ── 二、边界是「含」，不是「越过」 ──

fn test_min_max_are_inclusive() {
	// 规则写 18..120 时，18 和 120 本身都必须通过。
	// 写成 `val <= min` / `val >= max` 的那种差一错，正好被这两条卡住。
	// f64 的规则是 1..10，和 int / i64 的 18..120 不是同一个区间，单独一张表。
	for v in ['18', '19', '119', '120'] {
		assert !rejected[MinMaxInt]({'v': v}), 'int: ${v} 在 18..120 之间，不该被拦下'
		assert !rejected[MinMaxI64]({'v': v}), 'i64: ${v} 在 18..120 之间，不该被拦下'
	}
	for v in ['1', '2', '9', '10'] {
		assert !rejected[MinMaxF64]({'v': v}), 'f64: ${v} 在 1..10 之间，不该被拦下'
	}
}

// ── 三、小数与负数：非 int 类型以前根本走不到这里 ──

fn test_f64_accepts_fractional_values() {
	mut dto := MinMaxF64{}
	mut ok := true
	bind_and_validate[MinMaxF64](rule_ctx({
		'v': '2.5'
	})) or { ok = false }
	if ok {
		dto = bind_and_validate[MinMaxF64](rule_ctx({
			'v': '2.5'
		})) or { MinMaxF64{} }
	}
	// 2.5 落在 1..10 里，不该被拦
	assert ok, 'f64: 2.5 在 1..10 之间，不该被拦下'
	assert dto.v == f64(2.5)
	// 0.5 小于 min:1（写成 `.int()` 会把 0.5 截成 0，结论一样是拦下 —— 但
	// 用 `int()` 实现时 10.9 > max:10 也会被截成 10 从而漏过去，所以补一条）
	assert rejected[MinMaxF64]({'v': '0.5'})
	assert rejected[MinMaxF64]({'v': '10.9'}),
		'f64: 10.9 大于 max:10，不该因为截断成 10 而被放过'
}

fn test_negative_values_are_rejected() {
	assert rejected[MinMaxInt]({'v': '-1'})
	assert rejected[MinMaxI64]({'v': '-1'})
	assert rejected[MinMaxF64]({'v': '-1.5'})
}

// ── 四、规则与 `required` 同时存在时互不干扰 ──

fn test_required_and_len_together() {
	assert rejected[RequiredAndRules]({
		'name': ''
		'age':  '1'
	}), '空 name 应被 @[required] 拦下'
	assert rejected[RequiredAndRules]({
		'name': 'a'
		'age':  '1'
	}), 'name 长度 1 应被 len:2..5 拦下'
	assert rejected[RequiredAndRules]({
		'name': 'abcdef'
		'age':  '1'
	}), 'name 长度 6 应被 len:2..5 拦下'
	assert !rejected[RequiredAndRules]({
		'name': 'abc'
		'age':  '1'
	})
}

// ── 五、没有规则、没有标注的字段一律放行 ──

struct PlainDto {
	name  string
	count int
	ratio f64
}

fn test_plain_fields_are_never_rejected() {
	assert !rejected[PlainDto]({
		'name':  ''
		'count': '0'
		'ratio': '0'
	})
	assert !rejected[PlainDto](map[string]string{})
}

// ── 六、`@[required]` 要在每个数值类型上都生效 ──
//
// 这一节的存在理由：`@[required]` 的 `$if field.typ is ...` 分支原来只有
// string / int / i64 / f64 四个。漏掉的七个类型不会报错 —— 字段缺席时
// 值是零值，结构体照常构造成功，业务层拿到一份「字段都在、值全是零」的数据。
//
// 「缺席」和「显式传零」在这里得到同一个结论，这是零值语义的必然结果，
// 不是本节的取舍：`@[required]` 在数值字段上的含义就是「必须是非零值」。

fn test_required_string() {
	assert rejected[ReqString](map[string]string{})
	assert rejected[ReqString]({'v': ''})
	assert !rejected[ReqString]({'v': 'x'})
}

fn test_required_int() {
	assert rejected[ReqInt](map[string]string{})
	assert !rejected[ReqInt]({'v': '1'})
}

fn test_required_i8() {
	assert rejected[ReqI8](map[string]string{}), 'i8: 字段缺席时必须被拦下'
	assert !rejected[ReqI8]({'v': '1'})
}

fn test_required_i16() {
	assert rejected[ReqI16](map[string]string{}), 'i16: 字段缺席时必须被拦下'
	assert !rejected[ReqI16]({'v': '1'})
}

fn test_required_i64() {
	assert rejected[ReqI64](map[string]string{})
	assert !rejected[ReqI64]({'v': '1'})
}

fn test_required_u8() {
	assert rejected[ReqU8](map[string]string{}), 'u8: 字段缺席时必须被拦下'
	assert !rejected[ReqU8]({'v': '1'})
}

fn test_required_u16() {
	assert rejected[ReqU16](map[string]string{}), 'u16: 字段缺席时必须被拦下'
	assert !rejected[ReqU16]({'v': '1'})
}

fn test_required_u32() {
	assert rejected[ReqU32](map[string]string{}), 'u32: 字段缺席时必须被拦下'
	assert !rejected[ReqU32]({'v': '1'})
}

fn test_required_u64() {
	assert rejected[ReqU64](map[string]string{}), 'u64: 字段缺席时必须被拦下'
	assert !rejected[ReqU64]({'v': '1'})
}

fn test_required_f32() {
	assert rejected[ReqF32](map[string]string{}), 'f32: 字段缺席时必须被拦下'
	assert !rejected[ReqF32]({'v': '1.5'})
}

fn test_required_f64() {
	assert rejected[ReqF64](map[string]string{})
	assert !rejected[ReqF64]({'v': '1.5'})
}

// required 走的是 bind_and_validate 这条路径，而 bind_request_body 走的是
// 另一条（json2 解码 + validate_struct）。两条路径共用 validate_struct，
// 但只有 bind 那条有「字段缺席 → 零值」的形状。所以 required 的
// 覆盖面必须在 validate_struct 上直接验一次，不能只靠 bind 那条路径。
fn test_required_covers_every_numeric_type_in_validate_struct() {
	mut r8 := ReqU8{
		v: 0
	}
	mut r8_ok := true
	validate_struct(mut r8) or { r8_ok = false }
	assert !r8_ok, 'u8: validate_struct 必须拦住零值'

	mut r32 := ReqU32{
		v: 0
	}
	mut r32_ok := true
	validate_struct(mut r32) or { r32_ok = false }
	assert !r32_ok, 'u32: validate_struct 必须拦住零值'

	mut rf32 := ReqF32{
		v: 0.0
	}
	mut rf32_ok := true
	validate_struct(mut rf32) or { rf32_ok = false }
	assert !rf32_ok, 'f32: validate_struct 必须拦住零值'

	mut ok := ReqI16{
		v: 7
	}
	mut ok_flag := true
	validate_struct(mut ok) or { ok_flag = false }
	assert ok_flag, 'i16: 非零值不该被拦下'
}

// ── 七、结构断言：required 的分支集合必须和 min/max 一致 ──
//
// 行为用例挡不住「将来又给 min/max 加一个类型，required 没跟上」——
// 两份分支在今天是碰巧一致的，明天就分叉。而这类分叉没有任何返回值
// 在表达：漏掉的类型，编译通过、运行静默。
//
// 读源码找 `$if field.typ is X` 是唯一的办法：comptime 的分支集合
// 在运行时不可枚举。
fn test_required_and_min_max_cover_the_same_numeric_types() {
	src := os.read_file(os.join_path(@VMODROOT, 'web', 'bind.v')) or {
		assert false, '读不到 web/bind.v'
		return
	}
	required_body := extract_fn_body(src, 'if is_required {')
	assert required_body.len > 0, '找不到 validate_struct 里的 is_required 段'
	covered := numeric_types_in(required_body)
	// bool 不在 required 的覆盖面里（零值 false 无法区分「没传」和「传了 false」），
	// 所以只比对数值族。
	expected := ['int', 'i8', 'i16', 'i64', 'u8', 'u16', 'u32', 'u64', 'f32', 'f64']
	for t in expected {
		assert covered.contains(t), '@[required] 没有覆盖 ${t} —— 它会编译通过、运行时静默跳过'
	}
	// string 也会出现在这一段里（`$if field.typ is string`），它不是数值族，
	// 单独放行；除此之外多出任何类型都说明「加了一个分支却没被这里记录」。
	mut unexpected := []string{}
	for t in covered {
		if t !in expected && t != 'string' {
			unexpected << t
		}
	}
	assert unexpected.len == 0, 'required 分支里有预期之外的类型: ${unexpected}'
}

// extract_fn_body 从 marker 那一行起，取到下一个顶格的 `}` 之前。
// 只用于源码结构断言，不需要通用的解析器。
fn extract_fn_body(src string, marker string) string {
	lines := src.split_into_lines()
	mut start := -1
	for i, line in lines {
		if line.contains(marker) {
			start = i
			break
		}
	}
	if start < 0 {
		return ''
	}
	mut out := []string{}
	mut depth := 0
	for i := start; i < lines.len; i++ {
		line := lines[i]
		out << line
		depth += line.count('{') - line.count('}')
		if i > start && depth <= 0 {
			break
		}
	}
	return out.join('\n')
}

// numeric_types_in 抽出 `$if field.typ is X` / `$else $if field.typ is X`
// 里出现的类型名。
fn numeric_types_in(body string) []string {
	mut types := []string{}
	needle := 'field.typ is '
	mut rest := body
	for {
		idx := rest.index(needle) or { break }
		tail := rest[idx + needle.len..].trim_space()
		mut end := 0
		for end < tail.len {
			c := tail[end]
			if !(c.is_alnum() || c == `_`) {
				break
			}
			end++
		}
		if end > 0 {
			t := tail[..end]
			if t !in types {
				types << t
			}
		}
		rest = tail[end..]
	}
	return types
}
