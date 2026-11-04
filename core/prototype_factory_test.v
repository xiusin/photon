module core

// prototype_factory_test.v — FactoryBean 的 prototype 作用域
//
// 只断言「两次 resolve 都拿到了东西」是测不出问题的：一个把实例缓存在别处的
// 实现也会让这条通过。必须断言**两次是不同对象**，才说明作用域真的被尊重。
struct PfSample {
mut:
	serial int
}

struct PfPrototypeFactory {}

fn (f &PfPrototypeFactory) create() !voidptr {
	return voidptr(&PfSample{ serial: 2 })
}

fn (f &PfPrototypeFactory) bean_type() string {
	return 'PfPrototypeProduct'
}

fn (f &PfPrototypeFactory) is_singleton() bool {
	return false
}

struct PfSingletonFactory {}

fn (f &PfSingletonFactory) create() !voidptr {
	return voidptr(&PfSample{ serial: 1 })
}

fn (f &PfSingletonFactory) bean_type() string {
	return 'PfSingletonProduct'
}

fn (f &PfSingletonFactory) is_singleton() bool {
	return true
}

fn test_prototype_factory_returns_new_instance_each_time() {
	mut ctx := new_application_context()
	ctx.register_factory('PfPrototypeProduct', &PfPrototypeFactory{}) or {
		assert false, 'register_factory failed'
		return
	}
	ctx.refresh() or {}
	a := ctx.resolve('PfPrototypeProduct') or { unsafe { nil } }
	b := ctx.resolve('PfPrototypeProduct') or { unsafe { nil } }
	assert !isnil(a)
	assert !isnil(b)
	assert voidptr(a) != voidptr(b), 'prototype 工厂两次 resolve 返回了同一实例'
	ctx.shutdown()
}

fn test_singleton_factory_returns_same_instance() {
	mut ctx := new_application_context()
	ctx.register_factory('PfSingletonProduct', &PfSingletonFactory{}) or {
		assert false, 'register_factory failed'
		return
	}
	ctx.refresh() or {}
	a := ctx.resolve('PfSingletonProduct') or { unsafe { nil } }
	b := ctx.resolve('PfSingletonProduct') or { unsafe { nil } }
	assert !isnil(a)
	assert voidptr(a) == voidptr(b), 'singleton 工厂两次 resolve 返回了不同实例'
	ctx.shutdown()
}
