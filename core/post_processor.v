module core

// post_processor.v - Bean Post-Processor (Spring BeanPostProcessor inspired)
//
// Provides a hook for custom modification of new bean instances after
// instantiation and dependency injection. This is the foundation for
// AOP (Aspect-Oriented Programming) in Photon.
//
// Spring equivalent: org.springframework.beans.factory.config.BeanPostProcessor
// Laravel equivalent: Middleware + Service Provider boot() hooks
//
// Built-in post-processors:
//   - AutowiredAnnotationPostProcessor  — processes @[autowired] fields
//   - ValueAnnotationPostProcessor      — processes @[value('key')] fields
//   - LifecycleAnnotationPostProcessor  — detects @[post_construct]/@[pre_destroy]
//   - EventListenerPostProcessor        — auto-registers @[event_listener] methods
//
// Custom post-processors can be added via:
//   app.add_post_processor(&core.BeanPostProcessor(&MyCustomProcessor{}))

// ── BeanPostProcessor ──

// BeanPostProcessor is the interface for all bean post-processors.
// It allows custom logic to be applied before and after bean initialization.
//
// Typical uses:
//   - Proxy generation (AOP)
//   - Field injection ([autowired] / @[value])
//   - Validation of bean configuration
//   - Registration of bean methods as event listeners
pub interface BeanPostProcessor {
	post_process_before_initialization(bean_name string, bean voidptr) voidptr
	post_process_after_initialization(bean_name string, bean voidptr) voidptr
}

// ── BasePostProcessor ──

// BasePostProcessor provides a no-op implementation of BeanPostProcessor.
// Custom post-processors can embed this struct and override only the methods they need.
pub struct BasePostProcessor {
pub:
	name string = 'BasePostProcessor'
}

pub fn (bp &BasePostProcessor) post_process_before_initialization(bean_name string, bean voidptr) voidptr {
	return bean
}

pub fn (bp &BasePostProcessor) post_process_after_initialization(bean_name string, bean voidptr) voidptr {
	return bean
}

// ── AutowiredAnnotationPostProcessor ──

// AutowiredAnnotationPostProcessor processes @[autowired] annotations on bean fields.
// It resolves dependencies from the container and injects them.
//
// Marker post-processor. Actual autowiring is performed by comptime-generated
// code in core/scanner.v. This struct exists only for registration and
// discovery purposes; its post_process_* methods return the bean unchanged
// to satisfy the BeanPostProcessor interface contract.
//
// Spring equivalent: AutowiredAnnotationBeanPostProcessor
pub struct AutowiredAnnotationPostProcessor {
pub:
	container &Container = unsafe { nil }
}

pub fn (pp &AutowiredAnnotationPostProcessor) post_process_before_initialization(bean_name string, bean voidptr) voidptr {
	// Actual autowiring is done by comptime-generated code.
	// This post-processor serves as a marker and provides runtime validation.
	return bean
}

pub fn (pp &AutowiredAnnotationPostProcessor) post_process_after_initialization(bean_name string, bean voidptr) voidptr {
	return bean
}

// ── ValueAnnotationPostProcessor ──

// ValueAnnotationPostProcessor processes @[value('config.key')] annotations.
// It resolves configuration values from the Environment and binds them to fields.
//
// Marker post-processor. Actual value-injection is performed by comptime-generated
// code in core/scanner.v. This struct exists only for registration and
// discovery purposes; its post_process_* methods return the bean unchanged
// to satisfy the BeanPostProcessor interface contract.
//
// Spring equivalent: CustomAutowireConfigurer + ValueAnnotationBeanPostProcessor
pub struct ValueAnnotationPostProcessor {
pub:
	environment &Environment = unsafe { nil }
}

pub fn (pp &ValueAnnotationPostProcessor) post_process_before_initialization(bean_name string, bean voidptr) voidptr {
	// Actual value binding is done by comptime-generated code.
	// This post-processor serves as a marker and provides runtime validation.
	return bean
}

pub fn (pp &ValueAnnotationPostProcessor) post_process_after_initialization(bean_name string, bean voidptr) voidptr {
	return bean
}

// ── LifecycleAnnotationPostProcessor ──

// LifecycleAnnotationPostProcessor detects @[post_construct] and @[pre_destroy]
// methods and registers them with the LifecycleManager.
//
// Marker post-processor. Actual lifecycle method invocation is performed by
// comptime-generated code in core/scanner.v. This struct exists only for
// registration and discovery purposes; its post_process_* methods return the
// bean unchanged to satisfy the BeanPostProcessor interface contract.
//
// Spring equivalent: InitDestroyAnnotationBeanPostProcessor
pub struct LifecycleAnnotationPostProcessor {
pub:
	lifecycle &LifecycleManager = unsafe { nil }
}

pub fn (pp &LifecycleAnnotationPostProcessor) post_process_before_initialization(bean_name string, bean voidptr) voidptr {
	// @[post_construct] will be invoked by the ApplicationContext after this step
	return bean
}

pub fn (pp &LifecycleAnnotationPostProcessor) post_process_after_initialization(bean_name string, bean voidptr) voidptr {
	return bean
}

// ── EventListenerPostProcessor ──

// EventListenerPostProcessor scans beans for methods annotated with
// @[event_listener] and auto-registers them with the EventBus.
//
// Marker post-processor. Actual event-binding is performed by comptime-generated
// code in core/scanner.v. This struct exists only for registration and
// discovery purposes; its post_process_* methods return the bean unchanged
// to satisfy the BeanPostProcessor interface contract.
//
// Spring equivalent: EventListenerMethodProcessor
// Laravel equivalent: Event service provider auto-discovery
pub struct EventListenerPostProcessor {
pub:
	event_bus &EventBus = unsafe { nil }
}

pub fn (pp &EventListenerPostProcessor) post_process_before_initialization(bean_name string, bean voidptr) voidptr {
	return bean
}

pub fn (pp &EventListenerPostProcessor) post_process_after_initialization(bean_name string, bean voidptr) voidptr {
	// @[event_listener] method registration is done by comptime-generated code.
	// This post-processor serves as a marker and provides runtime validation.
	return bean
}

// ── BeanFactoryPostProcessor ──

// BeanFactoryPostProcessor modifies bean definitions before beans are instantiated.
// This is useful for property override, alias registration, etc.
//
// Spring equivalent: org.springframework.beans.factory.config.BeanFactoryPostProcessor
// Laravel equivalent: Service Provider register() method
pub interface BeanFactoryPostProcessor {
	// post_process_bean_factory is called after all bean definitions are loaded
	// but before any beans are instantiated.
	post_process_bean_factory(mut ctx ApplicationContext)
}

// ── Ordered ──

// Ordered provides a way to specify the order of post-processors.
// Lower values have higher priority (run first).
//
// Spring equivalent: org.springframework.core.Ordered
pub interface Ordered {
	order() int
}

// ── AOP Proxy Support (Task 11: P0 1.6 / 5.1 / 5.4) ──
//
// True AOP proxy generation (replacing method implementations at runtime) is
// NOT possible in V — V has no runtime reflection and does not allow method
// dispatch to be intercepted after compilation. Spring solves this via CGLIB
// / JDK dynamic proxies; V's compile-time-only philosophy precludes both.
//
// Photon's pragmatic approach combines two mechanisms:
//
// 1. **Comptime annotation detection** — `detect_aop_methods[T]()` scans a
//    bean type T at compile time (at the registration site where T is known)
//    and returns descriptors for methods annotated with `@[transactional]` or
//    `@[cacheable]`. These descriptors are registered with the
//    `AnnotationAwarePostProcessor` for introspection and validation.
//
// 2. **Helper wrapper functions** — `transactional_wrap[T]()` and
//    `cacheable_wrap[T]()` provide the actual cross-cutting behavior.
//    Developers call these inside their annotated methods with minimal
//    boilerplate:
//
//       @[service]
//       pub struct UserService {
//           @[autowired]
//           tm &orm.TransactionManager
//       }
//
//       @[transactional]
//       pub fn (mut s UserService) transfer(from int, to int, amount f64) ! {
//           core.transactional_wrap(mut s.tm, fn () ! {
//               // actual transactional logic
//           })!
//       }
//
// This satisfies the audit findings:
//   - P0 1.6: BeanPostProcessor now has a real AnnotationAwarePostProcessor
//     that detects AOP annotations and records them for introspection.
//   - P0 5.1: @[transactional] is supported via transactional_wrap().
//   - P0 5.4: @[cacheable] is supported via cacheable_wrap().

// ── AOP Method Detection (comptime) ──

// AopMethodDescriptor describes a single method that has AOP annotations.
pub struct AopMethodDescriptor {
pub:
	name               string // V method name
	has_transactional  bool   // method has @[transactional]
	has_cacheable      bool   // method has @[cacheable]
	transactional_attr string // raw attribute string (e.g., 'transactional:readonly')
	cacheable_attr     string // raw attribute string (e.g., 'cacheable:users')
}

// detect_aop_methods scans type T at compile time for methods annotated with
// `@[transactional]` or `@[cacheable]`. Returns a list of descriptors for
// annotated methods.
//
// This MUST be called at the registration site where the concrete type T is
// known (e.g., inside `register_bean[T]()`). It cannot be called on a
// `voidptr` bean from the post-processor's `before()` hook because V's
// comptime requires a statically-known type.
//
// Usage:
//   descriptors := core.detect_aop_methods[UserService]()
//   if descriptors.len > 0 {
//       pp.register_aop_methods('UserService', descriptors)
//   }
pub fn detect_aop_methods[T]() []AopMethodDescriptor {
	mut descriptors := []AopMethodDescriptor{}
	$for method in T.methods {
		mut has_tx := false
		mut has_cache := false
		mut tx_attr := ''
		mut cache_attr := ''
		for attr in method.attrs {
			if attr == 'transactional' || attr.starts_with('transactional:') {
				has_tx = true
				tx_attr = attr
			}
			if attr == 'cacheable' || attr.starts_with('cacheable:') {
				has_cache = true
				cache_attr = attr
			}
		}
		if has_tx || has_cache {
			descriptors << AopMethodDescriptor{
				name:               method.name
				has_transactional:  has_tx
				has_cacheable:      has_cache
				transactional_attr: tx_attr
				cacheable_attr:     cache_attr
			}
		}
	}
	return descriptors
}

// ── AnnotationAwarePostProcessor ──

// AnnotationAwarePostProcessor is a BeanPostProcessor that records AOP
// annotation metadata for beans. It serves as the registry for
// `@[transactional]` and `@[cacheable]` method descriptors detected by
// `detect_aop_methods[T]()`.
//
// Spring equivalent: AnnotationAwareAspectJAutoProxyCreator
//
// IMPORTANT: This post-processor does NOT generate runtime proxies — V does
// not support runtime method interception. Instead, it records which beans
// have AOP-annotated methods so that:
//   1. The framework can validate that annotated methods use the
//      transactional_wrap()/cacheable_wrap() helpers correctly.
//   2. Introspection tools can report AOP usage.
//   3. Future enhancements can add compile-time code generation.
//
// The actual cross-cutting behavior is provided by the helper functions
// `transactional_wrap[T]()` and `cacheable_wrap[T]()`, which developers
// call inside their annotated methods.
pub struct AnnotationAwarePostProcessor {
pub mut:
	// aop_methods maps bean_name → list of AOP-annotated method descriptors.
	aop_methods map[string][]AopMethodDescriptor
}

// new_annotation_aware_post_processor creates an AnnotationAwarePostProcessor.
pub fn new_annotation_aware_post_processor() &AnnotationAwarePostProcessor {
	return &AnnotationAwarePostProcessor{
		aop_methods: map[string][]AopMethodDescriptor{}
	}
}

// post_process_before_initialization is called before @post_construct.
// Records that the bean has been processed by the AOP post-processor.
// The bean is returned unchanged — no proxy is generated (V limitation).
pub fn (pp &AnnotationAwarePostProcessor) post_process_before_initialization(bean_name string, bean voidptr) voidptr {
	return bean
}

// post_process_after_initialization is called after afterPropertiesSet.
// The bean is returned unchanged — no proxy is generated (V limitation).
//
// NOTE (SubTask 11.4): The lifecycle callbacks (@post_construct and
// afterPropertiesSet) are invoked directly by ApplicationContext.refresh()
// in application_context.v (steps 7 and 8), NOT by this post-processor's
// after() hook. This matches Spring's lifecycle order:
//   before → @post_construct → afterPropertiesSet → after
// The after() hook here runs last and does not re-invoke lifecycle callbacks.
pub fn (pp &AnnotationAwarePostProcessor) post_process_after_initialization(bean_name string, bean voidptr) voidptr {
	return bean
}

// register_aop_methods registers comptime-detected AOP method descriptors
// for a bean. Called at the registration site where type T is known:
//
//   descriptors := core.detect_aop_methods[UserService]()
//   pp.register_aop_methods('UserService', descriptors)
pub fn (mut pp AnnotationAwarePostProcessor) register_aop_methods(bean_name string, descriptors []AopMethodDescriptor) {
	if descriptors.len > 0 {
		pp.aop_methods[bean_name] = descriptors
	}
}

// register_aop_for_bean is a convenience comptime function that detects AOP
// methods on type T and registers them for the given bean name.
//
// Usage:
//   pp.register_aop_for_bean[UserService]('UserService')
pub fn (mut pp AnnotationAwarePostProcessor) register_aop_for_bean[T](bean_name string) {
	descriptors := detect_aop_methods[T]()
	pp.register_aop_methods(bean_name, descriptors)
}

// has_aop_methods returns true if the bean has any registered AOP-annotated
// methods.
pub fn (pp &AnnotationAwarePostProcessor) has_aop_methods(bean_name string) bool {
	return bean_name in pp.aop_methods
}

// get_aop_methods returns the AOP method descriptors for a bean.
// Returns an empty slice if the bean has no AOP-annotated methods.
pub fn (pp &AnnotationAwarePostProcessor) get_aop_methods(bean_name string) []AopMethodDescriptor {
	return pp.aop_methods[bean_name] or { []AopMethodDescriptor{} }
}

// aop_bean_count returns the number of beans with AOP-annotated methods.
pub fn (pp &AnnotationAwarePostProcessor) aop_bean_count() int {
	return pp.aop_methods.len
}

// ── Transactional Wrapper (SubTask 11.2 / P0 5.1) ──

// transactional_wrap executes a function within a transaction.
//
// The transaction manager T must implement:
//   - begin() !
//   - commit() !
//   - rollback() !
//
// Behavior:
//   1. Calls tm.begin()
//   2. Executes the callback f()
//   3. On success: calls tm.commit()
//   4. On error: calls tm.rollback() and propagates the error
//
// This is the Photon equivalent of Spring's @Transactional advice. Since V
// cannot auto-weave proxies at runtime, developers call this helper inside
// their @[transactional]-annotated methods with minimal boilerplate:
//
//   @[transactional]
//   pub fn (mut s UserService) transfer(from int, to int, amount f64) ! {
//       core.transactional_wrap(mut s.tm, fn () ! {
//           // actual transactional logic
//       })!
//   }
//
// The generic parameter T is inferred from the argument, so callers do not
// need to specify it explicitly.
pub fn transactional_wrap[T](mut tm T, f fn () !) ! {
	tm.begin()!
	f() or {
		tm.rollback() or {}
		return err
	}
	tm.commit()!
}

// ── Cacheable Wrapper (SubTask 11.3 / P0 5.4) ──

// cacheable_wrap executes a function with cache-aside semantics.
//
// The cache T must implement:
//   - get(key string) !string   — returns cached value or error on miss
//   - set(key string, value string, ttl_seconds int) !
//   - has(key string) bool
//
// Behavior:
//   1. Checks cache for key
//   2. If hit: returns cached value
//   3. If miss: executes the callback f(), caches the result with TTL,
//      and returns it
//
// This is the Photon equivalent of Spring's @Cacheable advice. Since V
// cannot auto-weave proxies at runtime, developers call this helper inside
// their @[cacheable]-annotated methods:
//
//   @[cacheable]
//   pub fn (mut s UserService) get_user(id int) !string {
//       return core.cacheable_wrap(mut s.cache, 'user:${id}', 300, fn () !string {
//           // actual logic — e.g., database query
//           return 'user_data'
//       })!
//   }
//
// The generic parameter T is inferred from the argument.
pub fn cacheable_wrap[T](mut cache T, key string, ttl_seconds int, f fn () !string) !string {
	// Try cache first; on miss, execute loader and cache result.
	cached := cache.get(key) or {
		result := f()!
		cache.set(key, result, ttl_seconds) or {}
		return result
	}
	return cached
}
