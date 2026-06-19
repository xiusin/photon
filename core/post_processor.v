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
