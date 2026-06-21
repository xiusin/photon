module core

// service_provider.v - Service Provider (Laravel Service Provider + Spring @Configuration inspired)
//
// Provides a modular, structured way to register and bootstrap services.
// This is the Photon equivalent of Laravel's Service Provider pattern,
// which offers a clean separation between registration and bootstrapping.
//
// Spring equivalent: @Configuration class with @Bean methods
// Laravel equivalent: Illuminate\Support\ServiceProvider
//
// Key concepts:
//   - ServiceProvider trait: register() + boot() lifecycle
//   - register(): bind services into the container (no dependencies on other services)
//   - boot(): perform actions after ALL services are registered (can use dependencies)
//   - DeferredProvider: services that are only registered when needed (Laravel deferred providers)
//   - ProviderRegistry: manages discovery and loading of providers
//
// Usage:
//   struct CacheServiceProvider {
//       @[autowired]
//       config &CacheConfig
//   }
//
//   pub fn (sp &CacheServiceProvider) register(mut ctx ApplicationContext) ! {
//       // Register bindings — no other services available yet
//       ctx.register_bean('RedisCache', BeanRegistrationOptions{
//           scope: .singleton
//           tags: ['cache']
//       })!
//   }
//
//   pub fn (sp &CacheServiceProvider) boot(mut ctx ApplicationContext) ! {
//       // All services are now available — can use dependencies
//       cache := ctx.resolve('RedisCache')!
//       // ... warm up cache, etc.
//   }
//
//   // Register the provider
//   mut app := new_application_context()
//   app.register_provider(&CacheServiceProvider{})
//   app.refresh()!  // calls register() on all providers, then boot()
import sync

// ── ServiceProvider ──

// ServiceProvider is the interface for modular service registration.
// It separates the "register" phase (add bindings) from the "boot" phase
// (use bindings), ensuring a clean initialization order.
//
// Spring equivalent: @Configuration class (register ≡ @Bean methods, boot ≡ @PostConstruct)
// Laravel equivalent: ServiceProvider::register() + ServiceProvider::boot()
pub interface ServiceProvider {
	// register adds bindings to the container.
	// Called during refresh() BEFORE any beans are instantiated.
	// This is the "registration" phase — no other services are available yet.
	// MUST NOT resolve any beans from the container.
	register(mut ctx ApplicationContext) !

	// boot performs post-registration initialization.
	// Called during refresh() AFTER all providers have registered and
	// all beans have been instantiated. Other services ARE available.
	// Laravel equivalent: ServiceProvider::boot()
	boot(mut ctx ApplicationContext) !
}

// ── DeferredServiceProvider ──

// DeferredServiceProvider is a provider that is only loaded when one of
// its provided services is actually needed. This improves startup performance
// by deferring unnecessary registrations.
//
// Spring equivalent: @ConditionalOnBean / auto-configuration conditions
// Laravel equivalent: Illuminate\Support\ServiceProvider::$defer = true
pub interface DeferredServiceProvider {
	// register adds bindings (same as ServiceProvider).
	register(mut ctx ApplicationContext) !

	// boot performs post-registration initialization.
	boot(mut ctx ApplicationContext) !

	// provides returns the list of service type names this provider offers.
	// The provider is only loaded when one of these services is resolved.
	provides() []string
}

// ── ProviderRegistry ──

// ProviderEntry wraps a ServiceProvider with its registration state.
pub struct ProviderEntry {
pub mut:
	provider  &ServiceProvider = unsafe { nil }
	type_name string
	is_booted bool
}

// ProviderRegistry manages the discovery, registration, and lifecycle
// of ServiceProviders. It ensures proper ordering of register() and boot() calls.
//
// Spring equivalent: ConfigurationClassPostProcessor
// Laravel equivalent: Application::register() + ProviderRepository
@[heap]
pub struct ProviderRegistry {
pub mut:
	providers []ProviderEntry
mut:
	mu sync.RwMutex
}

// new_provider_registry creates an empty ProviderRegistry.
pub fn new_provider_registry() &ProviderRegistry {
	return &ProviderRegistry{
		providers: []ProviderEntry{}
	}
}

// add registers a ServiceProvider.
// The provider's register() method will be called during the next refresh().
pub fn (mut r ProviderRegistry) add(type_name string, provider &ServiceProvider) {
	r.mu.@lock()
	defer { r.mu.unlock() }
	r.providers << ProviderEntry{
		provider:  unsafe { provider }
		type_name: type_name
		is_booted: false
	}
}

// register_all calls register() on all providers in registration order.
// This is called during refresh() before beans are instantiated.
pub fn (mut r ProviderRegistry) register_all(mut ctx ApplicationContext) ! {
	r.mu.rlock()
	providers := r.providers.clone()
	r.mu.runlock()

	for entry in providers {
		if !isnil(entry.provider) {
			entry.provider.register(mut ctx) or {
				eprintln('[ProviderRegistry] register failed for "${entry.type_name}": ${err}')
			}
		}
	}
}

// boot_all calls boot() on all providers in registration order.
// This is called during refresh() after all beans are instantiated.
pub fn (mut r ProviderRegistry) boot_all(mut ctx ApplicationContext) ! {
	r.mu.@lock()
	defer { r.mu.unlock() }

	for mut entry in r.providers {
		if !isnil(entry.provider) && !entry.is_booted {
			entry.provider.boot(mut ctx) or {
				eprintln('[ProviderRegistry] boot failed for "${entry.type_name}": ${err}')
			}
			entry.is_booted = true
		}
	}
}

// provider_count returns the number of registered providers.
pub fn (mut r ProviderRegistry) provider_count() int {
	r.mu.rlock()
	defer { r.mu.runlock() }
	return r.providers.len
}

// is_booted checks if a specific provider has been booted.
pub fn (mut r ProviderRegistry) is_booted(type_name string) bool {
	r.mu.rlock()
	defer { r.mu.runlock() }
	for entry in r.providers {
		if entry.type_name == type_name {
			return entry.is_booted
		}
	}
	return false
}
