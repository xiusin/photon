module core

// di_controller.v — 控制器依赖注入（Spring @Autowired for Controllers）
//
// 提供编译期扫描控制器字段 @[autowired] 注解，并从 ApplicationContext
// 自动注入依赖的能力。这是 Photon 实现 Spring 风格"控制器任意拆分"的
// 关键 DI 基础设施。
//
// 核心函数：
//   autowire_controller[T] — 扫描 T 的 @[autowired] 字段并注入
//   wire_controller[T]    — 创建新实例 + 注入依赖（一步到位）
//
// 用法：
//   @[controller]
//   @[prefix: '/api/v1']
//   pub struct UserController {
//       user_service &UserService @[autowired]
//       auth_service &AuthService @[autowired]
//   }
//
//   // 从 DI 容器创建并注入依赖
//   ctrl := core.wire_controller[UserController](mut ctx)!
//   app.WebModule.mount_controller[UserController](ctrl, '/api/v1')

// resolve_autowired_dependency 按 Spring 的字段注入约定，依次尝试三种名字。
//
// 顺序不能换：
//   1. @[qualifier('name')] —— 显式指定优先，它就是为"名字对不上"存在的
//   2. 字段名原样        —— 约定优于配置，用户按 bean 名写字段时间最多
//   3. 字段名转 PascalCase —— 字段只能 snake_case，而 bean 名习惯用类型名
//
// 第 3 步是关键。原来这里是 capitalize_first()：它只把首字母大写，
// proto_bean → Proto_bean，永远不可能等于 ProtoBean。于是"字段名与
// bean 名不同"的注入全部静默失败 —— 字段保持注册时的默认值（通常是
// nil），调用时才在很远的地方炸成段错误。
//
// 这里返回 voidptr 而不是 !voidptr：注入是"尽力而为"的语义，
// 缺一个可选依赖不应该让整个控制器创建失败。
fn (mut ctx ApplicationContext) resolve_autowired_dependency(field_name string, qualifier string, type_name string) voidptr {
	if qualifier.len > 0 {
		// 两张表都要查，顺序有意义：
		//
		//   a. qualifiers 表 —— @[qualifier('x')] 注册时写进去的映射。
		//      原来这里只有 ctx.resolve(qualifier)（按名字查），
		//      完全没查这张表，所以真正用了 qualifier 的注入从来没生效过。
		//
		//   b. bean 名 —— 直接拿 qualifier 的字面值当 bean 名。
		//      这是仓库里既有的用法（测试与文档里 <bean>.qualifier 与
		//      register_instance('<qualifier>') 混着写），保留它，
		//      避免把已经能跑的场景改坏。
		//
		// 两者都命中时以 qualifiers 表为准：那才是 qualifier 的语义，
		// 按名字查只是它的宽松退化形式。
		if inst := ctx.container.resolve_by_qualifier(qualifier) {
			return inst
		}
		if inst := ctx.resolve(qualifier) {
			return inst
		}
	}
	if inst := ctx.resolve(field_name) {
		return inst
	}
	// 3a. 字段名 → PascalCase（proto_bean → ProtoBean）
	camel := snake_to_pascal_case(field_name)
	if camel != field_name {
		if inst := ctx.resolve(camel) {
			return inst
		}
	}
	// 3b. 字段的类型名（proto_bean &ProtoBean → ProtoBean）
	//
	// 为什么还需要这一步：用户完全可以写 `svc &UserService`，
	// 此时 3a 推出的 'Svc' 并不存在，但类型名 'UserService' 才是
	// 容器里真正的键。Spring 也是按类型优先于按名字解析的。
	if type_name.len > 0 && type_name != camel && type_name != field_name {
		if inst := ctx.resolve(type_name) {
			return inst
		}
	}
	return voidptr(unsafe { nil })
}

// autowire_controller 扫描控制器 T 的字段，将标注 @[autowired] 的字段
// 从 ApplicationContext 中解析并注入。
//
// 解析顺序见 resolve_autowired_dependency。
//
// V comptime 注意：
//   由于 V 0.5.1 无法在 comptime 中获取引用类型字段的完整类型名，
//   这里额外尝试一次"字段名本身"作为类型提示（见下面的 field.name
//   与 T.name 组合），其余情况下只能依赖名字约定。
//
// Spring 等价：AbstractAutowireCapableBeanFactory.populateBean()
//
// 用法：
//   mut ctrl := &UserController{}
//   ctx.autowire_controller[UserController](ctrl)!
//   // ctrl.user_service 现在已注入
pub fn (mut ctx ApplicationContext) autowire_controller[T](controller &T) ! {
	$for field in T.fields {
		mut has_autowired := false
		for attr in field.attrs {
			if attr == attr_autowired {
				has_autowired = true
			}
		}

		if has_autowired {
			field_qualifier := extract_qualifier(field.attrs)
			instance_resolved := ctx.resolve_autowired_dependency(field.name, field_qualifier, '')
			if !isnil(instance_resolved) {
				inject_voidptr_field[T](controller, field.name, instance_resolved)
			}
		}
	}
}

// inject_voidptr_field 把实例指针写进 controller 的指定字段。
//
// 为什么绕这么一圈：V comptime 不允许直接把运行时字符串当字段名取地址。
// 所以这里用一个 $for 把每个字段名硬编码进生成的代码里，再按名字匹配。
// 这是"运行期字段名 → 编译期字段地址"的唯一可行桥接方式。
fn inject_voidptr_field[T](controller &T, field_name string, instance voidptr) {
	$for field in T.fields {
		if field.name == field_name {
			mut ctrl := unsafe { &T(controller) }
			unsafe {
				// ⚠️ V 0.5.2 下 `&voidptr(&ctrl.$(field.name))` 一律报
				//   cannot cast string to `&voidptr`, use `addr.str` instead.
				// —— 编译器把 comptime 字段的取址当成「取字符串字段的值」。
				// 必须先经 voidptr 转一次：`voidptr(addr)` 再取址，
				// 生成的 C 就是 `*(voidptr_t*)&ctrl->field = instance`，
				// 与手写等价。
				//
				// 这个缺陷的症状是「整个 core 编不过」，而且只在
				// 泛型函数体内的 comptime 字段上出现 ——
				// `v -check core/` 因为要求 main 模块而看不出，
				// 直到编 example/verify 才炸出来。
				addr := &ctrl.$(field.name)
				slot := &voidptr(voidptr(addr))
				*slot = instance
			}
		}
	}
}

// wire_controller 创建控制器 T 的新实例，自动注入 @[autowired] 依赖，
// 并返回完全初始化的控制器指针。
//
// 这是 autowire_controller 的便捷封装——一步到位创建+注入。
//
// Spring 等价：AbstractAutowireCapableBeanFactory.createBean()
//
// 用法：
//   ctrl := ctx.wire_controller[UserController]()!
//   app.WebModule.mount_controller[UserController](ctrl, '/api/v1')
pub fn (mut ctx ApplicationContext) wire_controller[T]() !&T {
	mut controller := &T{}
	ctx.autowire_controller[T](controller)!
	return controller
}

// register_controller 注册控制器到 DI 容器，并返回注入依赖后的实例。
// 控制器以单例方式注册，可在后续通过 resolve() 获取。
//
// Spring 等价：@Controller + @Autowired 自动注册
//
// 用法：
//   ctrl := ctx.register_controller[UserController]()!
//   // ctrl 已注册为单例，可通过 ctx.resolve('UserController') 再次获取
pub fn (mut ctx ApplicationContext) register_controller[T]() !&T {
	controller := ctx.wire_controller[T]()!
	ctx.register_instance(T.name, voidptr(controller))!
	return controller
}

// ── 辅助函数 ──

// snake_to_pascal_case 把 snake_case 字段名转成类型名习惯的 PascalCase。
//
//   proto_bean   → ProtoBean
//   user_service → UserService
//   repo         → Repo
//
// 与 capitalize_first 的区别：后者只动首字母，proto_bean → Proto_bean，
// 对 `&ProtoBean` 这种字段永远匹配不上。
fn snake_to_pascal_case(s string) string {
	if s.len == 0 {
		return s
	}
	mut out := []string{cap: s.len}
	for part in s.split('_') {
		if part.len == 0 {
			continue
		}
		out << part[0..1].to_upper() + part[1..]
	}
	return out.join('')
}

// capitalize_first 将字符串首字母大写。
//
// 注意：这不是命名风格转换。`capitalize_first('proto_bean')` 是
// `'Proto_bean'`，不是 `'ProtoBean'`。需要后者请用 snake_to_pascal_case。
fn capitalize_first(s string) string {
	if s.len == 0 {
		return s
	}
	return s[0..1].to_upper() + s[1..]
}
