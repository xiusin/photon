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
