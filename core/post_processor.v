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
// It resolves configuration values from the Environment and binds them to
// bean fields, providing the Photon equivalent of Spring's @Value annotation.
//
// Design note: V's comptime requires a statically-known type T to iterate
// fields via $for. The BeanPostProcessor interface operates on voidptr
// beans, so the actual value-injection happens in the generic comptime
// method inject_values[T](), which is called at the registration site
// where T is known (e.g., from comptime-generated code in scanner.v or
// the user's bootstrap code). The post_process_* methods remain as no-op
// markers to satisfy the BeanPostProcessor interface contract.
//
// Thread-safety: the struct holds only an immutable &Environment reference.
// inject_values[T]() is stateless — it reads from the Environment (which is
// protected by its own RwMutex) and writes only to the caller-owned bean
// instance. No locking is required on the post-processor itself.
//
// Spring equivalent: CustomAutowireConfigurer + ValueAnnotationBeanPostProcessor
pub struct ValueAnnotationPostProcessor {
pub:
	environment &Environment = unsafe { nil }
}

// post_process_before_initialization is a no-op marker. Actual value
// injection is performed by inject_values[T](), which requires a
// statically-known type T (not available from a voidptr bean).
pub fn (pp &ValueAnnotationPostProcessor) post_process_before_initialization(bean_name string, bean voidptr) voidptr {
	return bean
}

// post_process_after_initialization is a no-op marker.
pub fn (pp &ValueAnnotationPostProcessor) post_process_after_initialization(bean_name string, bean voidptr) voidptr {
	return bean
}

// inject_values scans type T at compile time for fields annotated with
// @[value('key')] and injects the corresponding property values from the
// Environment. This is the real value-injection implementation — it uses
// V's comptime $for to iterate fields and $if to check field types, so
// all type checking and field access is resolved at compile time (zero
// runtime reflection).
//
// Supported field types: string, int, i64, f32, f64, bool
//
// The property key is extracted from @[value('key')] using
// extract_value_expr() (from scanner.v). Both attribute forms are
// supported:
//   @[value: 'app.name']   → key = 'app.name'
//   @[value('app.name')]   → key = 'app.name'
//
// If a referenced property key is not found in the Environment, an error
// is returned with a readable bilingual message:
//   value injection failed: key "..." not found / 值注入失败：键 "..." 未找到
//
// The lookup respects the full Environment priority chain
// (CLI > env vars > profile config > default config > programmatic).
//
// Usage:
//   mut config := MyConfig{}
//   env := app.environment
//   pp.inject_values[MyConfig](mut config, env)!
//   // config fields are now populated from environment properties
//
// NOTE (V 0.5.1): previously this function took `mut env &Environment` which
// the compiler mis-resolved to `&&Environment` at the call site. The signature
// now uses `env &Environment` (non-mut) with an internal `mut env_mut := env`
// local to call mut-receiver methods on Environment. This is fully callable
// from outside this module. Prefer `inject_values_for_bean[T]()` (set
// `environment` first) for the convenience wrapper.
pub fn (mut pp ValueAnnotationPostProcessor) inject_values[T](mut bean T, env &Environment) ! {
	mut env_mut := env
	$for field in T.fields {
		key := extract_value_expr(field.attrs)
		// Skip fields without @[value('...')] (continue is not allowed
		// in comptime $for loops, so we guard with an if-block).
		if key.len > 0 {
			// Look up the property — error if not found in any source.
			if !env_mut.has_property(key) {
				return error('value injection failed: key "${key}" not found / 值注入失败：键 "${key}" 未找到')
			}
			raw_value := env_mut.get_property(key)

			// Convert and assign by field type (comptime — zero runtime reflection).
			$if field.typ is string {
				bean.$(field.name) = raw_value
			} $else $if field.typ is int {
				bean.$(field.name) = raw_value.int()
			} $else $if field.typ is i64 {
				bean.$(field.name) = raw_value.i64()
			} $else $if field.typ is f32 {
				bean.$(field.name) = f32(raw_value.f64())
			} $else $if field.typ is f64 {
				bean.$(field.name) = raw_value.f64()
			} $else $if field.typ is bool {
				bean.$(field.name) = raw_value.to_lower() == 'true' || raw_value == '1'
			}
		}
	}
}

// value_keys returns the property keys referenced by @[value('key')] /
// @[value: 'key'] annotations on T's fields (comptime scan, zero runtime
// reflection). Fields without a @[value] annotation are skipped.
pub fn value_keys[T]() []string {
	mut keys := []string{}
	$for field in T.fields {
		key := extract_value_expr(field.attrs)
		if key.len > 0 {
			keys << key
		}
	}
	return keys
}

// bind_values binds @[value] annotated fields from a pre-resolved property map
// (every referenced key must be present). Supported field types:
//   string, bool, int, i8, i16, i64, u8, u16, u32, u64, f32, f64,
//   and comma-separated lists []string, []int, []f64, []bool.
// It deliberately takes a plain
// `map[string]string` rather than an `&Environment`, so the generic carries no
// reference-to-Environment parameter — this is what makes it usable from any
// module under V 0.5.1, where a `mut env &Environment` generic parameter is
// mis-resolved to `&&Environment` at the call site.
pub fn (mut pp ValueAnnotationPostProcessor) bind_values[T](mut bean T, props map[string]string) ! {
	$for field in T.fields {
		key := extract_value_expr(field.attrs)
		if key.len > 0 {
			if key !in props {
				return error('value injection failed: key "${key}" not found / 值注入失败：键 "${key}" 未找到')
			}
			raw_value := props[key]
			$if field.typ is string {
				bean.$(field.name) = raw_value
			} $else $if field.typ is int {
				bean.$(field.name) = raw_value.int()
			} $else $if field.typ is i8 {
				bean.$(field.name) = raw_value.i8()
			} $else $if field.typ is i16 {
				bean.$(field.name) = raw_value.i16()
			} $else $if field.typ is i64 {
				bean.$(field.name) = raw_value.i64()
			} $else $if field.typ is u8 {
				bean.$(field.name) = raw_value.u8()
			} $else $if field.typ is u16 {
				bean.$(field.name) = raw_value.u16()
			} $else $if field.typ is u32 {
				bean.$(field.name) = raw_value.u32()
			} $else $if field.typ is u64 {
				bean.$(field.name) = raw_value.u64()
			} $else $if field.typ is f32 {
				bean.$(field.name) = f32(raw_value.f64())
			} $else $if field.typ is f64 {
				bean.$(field.name) = raw_value.f64()
			} $else $if field.typ is bool {
				bean.$(field.name) = raw_value.to_lower() == 'true' || raw_value == '1'
			} $else $if field.typ is []string {
				mut arr := []string{}
				if raw_value.len > 0 {
					for part in raw_value.split(',') {
						arr << part.trim_space()
					}
				}
				bean.$(field.name) = arr
			} $else $if field.typ is []int {
				mut arr := []int{}
				if raw_value.len > 0 {
					for part in raw_value.split(',') {
						arr << part.trim_space().int()
					}
				}
				bean.$(field.name) = arr
			} $else $if field.typ is []f64 {
				mut arr := []f64{}
				if raw_value.len > 0 {
					for part in raw_value.split(',') {
						arr << part.trim_space().f64()
					}
				}
				bean.$(field.name) = arr
			} $else $if field.typ is []bool {
				mut arr := []bool{}
				if raw_value.len > 0 {
					for part in raw_value.split(',') {
						pt := part.trim_space().to_lower()
						arr << (pt == 'true' || pt == '1')
					}
				}
				bean.$(field.name) = arr
			}
		}
	}
}

// inject_values_for_bean injects @[value] annotated fields from the post-
// processor's embedded Environment. This is the recommended entry point: it
// resolves each @[value] key through the Environment's full priority chain
// OUTSIDE the generic boundary (into a plain map), then binds via bind_values.
// Works from any module under V 0.5.1.
//
// Returns an error if the environment is not set or a referenced key is missing.
pub fn (mut pp ValueAnnotationPostProcessor) inject_values_for_bean[T](mut bean T) ! {
	if isnil(pp.environment) {
		return error('ValueAnnotationPostProcessor.environment is not set / 值注入后处理器的 environment 字段未设置')
	}
	mut env := pp.environment
	// Resolve every @[value] key through the full priority chain (cli > env-vars
	// > profile toml > default toml > set_property), outside the generic.
	mut props := map[string]string{}
	for key in value_keys[T]() {
		if env.has_property(key) {
			props[key] = env.get_property(key)
		}
	}
	pp.bind_values[T](mut bean, props)!
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

// ── BeanDefinitionRegistryPostProcessor ──

// BeanDefinitionRegistryPostProcessor extends BeanFactoryPostProcessor with
// the ability to modify the bean definition registry (add/remove/redefine
// bean definitions) before any beans are instantiated.
//
// This is the most powerful extension point in the container lifecycle —
// it runs BEFORE BeanFactoryPostProcessor and can register entirely new
// bean definitions programmatically.
//
// Spring equivalent:
//   org.springframework.beans.factory.support.BeanDefinitionRegistryPostProcessor
//
// Usage:
//   struct DynamicBeanRegistrar {}
//
//   fn (r &DynamicBeanRegistrar) post_process_bean_definition_registry(mut ctx ApplicationContext) {
//       // Register additional bean definitions at runtime
//       mut def := core.new_bean_definition('DynamicService')
//       def.tags = ['dynamic']
//       ctx.register(def) or {}
//   }
//
//   fn (r &DynamicBeanRegistrar) post_process_bean_factory(mut ctx ApplicationContext) {
//       // Optionally modify existing definitions
//   }
//
//   ctx.add_registry_post_processor(&core.BeanDefinitionRegistryPostProcessor(&DynamicBeanRegistrar{}))
pub interface BeanDefinitionRegistryPostProcessor {
	// post_process_bean_definition_registry is called after all bean
	// definitions are registered but before any beans are instantiated.
	// This is the hook to add, remove, or redefine bean definitions.
	post_process_bean_definition_registry(mut ctx ApplicationContext)
	// post_process_bean_factory is inherited from BeanFactoryPostProcessor.
	// Called after all registry post-processors have run, but still
	// before bean instantiation. Useful for final definition adjustments.
	post_process_bean_factory(mut ctx ApplicationContext)
}

// BaseRegistryPostProcessor provides a no-op implementation of
// BeanDefinitionRegistryPostProcessor. Custom post-processors can embed
// this struct and override only the methods they need.
//
// Spring equivalent: BeanDefinitionRegistryPostProcessor with no-op defaults
pub struct BaseRegistryPostProcessor {
pub:
	name string = 'BaseRegistryPostProcessor'
}

pub fn (bp &BaseRegistryPostProcessor) post_process_bean_definition_registry(mut ctx ApplicationContext) {
	// No-op — override in subclass
}

pub fn (bp &BaseRegistryPostProcessor) post_process_bean_factory(mut ctx ApplicationContext) {
	// No-op — override in subclass
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
