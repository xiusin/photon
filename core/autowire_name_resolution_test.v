module core

// autowire_name_resolution_test.v — 字段名与 bean 名对不上时，注入还成不成立。
//
// 背景：字段名只能是 snake_case，而 bean 名习惯用类型名（PascalCase）。
// 于是 `proto_bean &ProtoBean @[autowired]` 这种写法是最自然的用法，
// 但容器里的键是 'ProtoBean'，字段名是 'proto_bean' —— 两者对不上。
//
// 曾经的兜底是 capitalize_first()：它只把首字母大写，
// proto_bean → Proto_bean，永远不等于 ProtoBean。于是注入静默失败，
// 字段停留在声明时的默认值（通常是 nil），调用点才炸。
//
// 这些用例的断言全部落在「字段是不是真的拿到了东西」上，
// 而不是「autowire 有没有返回成功」—— 后者一直是成功的。

struct ProtoBean {
pub mut:
	id int
}

struct SingBean {
pub mut:
	id int
}

struct AwService {
pub mut:
	proto_bean &ProtoBean @[autowired]
}

struct AwQualifiedService {
pub mut:
	whatever &AwQualifiedBean @[autowired; qualifier: 'the_one']
}

struct AwQualifiedBean {
pub mut:
	tag string
}

// test_snake_case_field_finds_pascal_case_bean 是这一批的主用例。
//
// 注意 bean 用的是 prototype scope：prototype 的实例不经过单例缓存，
// 必须由 comptime 生成的代码 set_instance 之后才存在，因此它天然
// 覆盖了「注入路径本身是否真的跑通」这件事。
fn test_snake_case_field_finds_pascal_case_bean() {
	mut ctx := new_application_context()
	mut def := new_bean_definition('ProtoBean')
	def.scope = .prototype
	ctx.register(def)!
	mut container := ctx.container
	container.set_instance('ProtoBean', voidptr(&ProtoBean{
		id: 42
	}))

	mut svc := &AwService{
		proto_bean: unsafe { nil }
	}
	ctx.autowire_controller[AwService](svc)!
	assert !isnil(svc.proto_bean), 'proto_bean 没被注入：字段名 snake_case 推不出 bean 名 PascalCase'
	assert svc.proto_bean.id == 42
}

// test_singleton_snake_case_field_finds_pascal_case_bean 锁住单例侧的同一条路径。
fn test_singleton_snake_case_field_finds_pascal_case_bean() {
	mut ctx := new_application_context()
	ctx.register_instance('SingBean', voidptr(&SingBean{
		id: 7
	}))!

	mut svc := &AwSingService{
		sing_bean: unsafe { nil }
	}
	ctx.autowire_bean[AwSingService](mut svc)!
	assert !isnil(svc.sing_bean), 'autowire_bean 与 autowire_controller 必须给出同一个结果'
	assert svc.sing_bean.id == 7
}

struct AwSingService {
pub mut:
	sing_bean &SingBean @[autowired]
}

// test_qualifier_wins_over_convention 保证 qualifier 优先级没被这次改动打乱。
fn test_qualifier_wins_over_convention() {
	mut ctx := new_application_context()
	mut def := new_bean_definition('AwQualifiedBean')
	def.qualifier = 'the_one'
	ctx.register(def)!
	mut container := ctx.container
	container.set_instance('AwQualifiedBean', voidptr(&AwQualifiedBean{
		tag: 'from-qualifier'
	}))

	mut svc := &AwQualifiedService{
		whatever: unsafe { nil }
	}
	ctx.autowire_controller[AwQualifiedService](svc)!
	assert !isnil(svc.whatever), 'qualifier 显式指定的名字必须优先命中'
	assert svc.whatever.tag == 'from-qualifier'
}

// test_missing_dependency_stays_nil 反向锁住「找不到就是找不到」。
//
// 注入是尽力而为：不能因为推导出了几个候选名字，就把不存在的依赖
// 硬塞一个野指针进去。
fn test_missing_dependency_stays_nil() {
	mut ctx := new_application_context()

	mut svc := &AwService{
		proto_bean: unsafe { nil }
	}
	ctx.autowire_controller[AwService](svc)!
	assert isnil(svc.proto_bean), '容器里没有 ProtoBean，字段必须是 nil'
}
