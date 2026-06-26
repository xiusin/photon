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

// autowire_controller 扫描控制器 T 的字段，将标注 @[autowired] 的字段
// 从 ApplicationContext 中解析并注入。
//
// 解析顺序：
//   1. 如果字段有 @[qualifier('name')]，按 qualifier 名称解析
//   2. 否则按字段名解析（约定：字段名 = Bean 名称）
//   3. 如果字段名首字母大写形式匹配，尝试解析（如 field → Field）
//
// V comptime 注意：
//   由于 V 0.5.1 无法在 comptime 中获取引用类型字段的完整类型名，
//   我们使用 unsafe 指针写入方式设置字段值。这仅对指针类型字段安全。
//   通过 field.is_shared、field.is_mut 等属性可以做一些过滤，
//   但最可靠的方式是：仅对标注了 @[autowired] 的字段执行注入。
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
			// 提取 qualifier（如果有）
			field_qualifier := extract_qualifier(field.attrs)

			// 确定解析名称
			bean_name := if field_qualifier.len > 0 {
				field_qualifier
			} else {
				field.name
			}

			// 尝试解析依赖
			// 注意：V comptime $for 循环不允许 continue，
			// 所以用 if 嵌套 + or 块代替
			instance_resolved := ctx.resolve(bean_name) or {
				// 尝试首字母大写形式
				ctx.resolve(capitalize_first(field.name)) or {
					voidptr(unsafe { nil })
				}
			}

			// 仅在成功解析时注入
			if !isnil(instance_resolved) {
				// 通过 unsafe 指针写入设置字段值
				// 这种方式对指针类型字段是安全的
				mut ctrl := unsafe { &T(controller) }
				unsafe {
					// ⚠️ 重要提示：必须分两步操作，不能内联为
					//   *(&voidptr(&ctrl.$(field.name))) = instance_resolved
					// 因为 V 0.5.x 编译器在解析内联形式时，会将
					// &ctrl.$(field.name) 误解为"取字段字符串值"而非"取字段地址"，
					// 导致 "cannot cast string to &voidptr" 编译错误。
					// 先将字段地址存入中间变量 addr，再通过 &voidptr(addr)
					// 解引用写入，既避免了编译器误解析，又消除了
					// 原先 "unused variable: field_ptr" 的编译器警告。
					addr := &ctrl.$(field.name)
					*(&voidptr(addr)) = instance_resolved
				}
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

// capitalize_first 将字符串首字母大写
fn capitalize_first(s string) string {
	if s.len == 0 {
		return s
	}
	return s[0..1].to_upper() + s[1..]
}

// ── ServiceLocator 集成 ──

// locate_controller 通过全局 ServiceLocator 创建并注入控制器。
// 无需直接传递 ApplicationContext，适合在非启动代码中使用。
//
// 前提：全局 ServiceLocator 已通过 set_global_service_locator() 初始化。
//
// Spring 等价：ApplicationContext.getBean(MyController.class)
// Laravel 等价：app(MyController::class)
//
// 用法：
//   ctrl := core.locate_controller[UserController]()!
pub fn locate_controller[T]() !&T {
	if isnil(g_service_locator) {
		return error('locate_controller: global ServiceLocator not initialized / 全局服务定位器未初始化')
	}
	mut sl := g_service_locator
	if isnil(sl.context) {
		return error('locate_controller: ServiceLocator has no ApplicationContext / 服务定位器未关联 ApplicationContext')
	}
	mut ctx := unsafe { sl.context }
	return ctx.wire_controller[T]()
}
