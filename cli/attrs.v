module cli

// attrs.v — 编译期属性的统一解析
//
// 为什么单独一个文件
// ------------------
// V 的 `$for field in T.fields` 给出的 `field.attrs` 是 `[]string`，元素形如
// `option: 'env'` / `argument` / `required`。而 `T.attributes`（struct 级）给的
// 是 `[]VAttribute`，带 `.name` / `.has_arg` / `.arg`。两种形态不一致，且
// 0.5.2 把 `@[option('env')]` 规范成 `option: 'env'`，解析必须容忍两种写法。
//
// 之前 `scan_command` / `bind_input` 两处各写一份解析，而且都写成 `attr.name`
// / `attr.args` —— 那是对 `[]VAttribute` 的假设，套在 `[]string` 上整块编不过。
// 这里只留一个出口，两边共用。

// attr_name_of 取属性名：`option: 'env'` → `option`，`argument` → `argument`
fn attr_name_of(raw string) string {
	mut end := raw.len
	if idx := raw.index(':') {
		end = idx
	} else if idx := raw.index('(') {
		end = idx
	}
	return raw[..end].trim_space()
}

// attr_arg_of 取属性参数：`option: 'env'` → `env`，`argument` → ''
//
// 同时容忍 `: 'x'`、`: "x"`、`('x')` 三种写法；0.5.2 的 comptime 会给出去掉
// 外层括号但保留引号的形式，引号由这里剥。
fn attr_arg_of(raw string) string {
	mut rest := ''
	if idx := raw.index(':') {
		rest = raw[idx + 1..]
	} else if idx := raw.index('(') {
		rest = raw[idx + 1..]
		if rest.ends_with(')') {
			rest = rest[..rest.len - 1]
		}
	} else {
		return ''
	}
	return rest.trim_space().trim("'\"")
}

// has_attr 判断属性列表里是否存在名为 `name` 的属性
fn has_attr(attrs []string, name string) bool {
	mut found := false
	for raw in attrs {
		if attr_name_of(raw) == name {
			found = true
		}
	}
	return found
}

// attr_value 取属性列表里第一个名为 `name` 的属性的参数值，没有则返回 ''
fn attr_value(attrs []string, name string) string {
	mut val := ''
	for raw in attrs {
		if attr_name_of(raw) == name && val.len == 0 {
			val = attr_arg_of(raw)
		}
	}
	return val
}

// arg_index_of 求 `field_name` 在「带 @[argument] 的字段序列」中的序号。
//
// 编译期循环里不允许 `break` / `continue`，所以整段扫完再判断，不提前退出。
// 返回 -1 表示该字段不是位置参数。
fn arg_index_of[T](field_name string) int {
	mut counter := 0
	mut found := -1
	$for f in T.fields {
		if has_attr(f.attrs, attr_argument) {
			if f.name == field_name {
				found = counter
			}
			counter++
		}
	}
	return found
}
