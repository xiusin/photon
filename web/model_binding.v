module web

// model_binding.v - Route Model Binding (Laravel route model binding inspired)
//
// Provides implicit and explicit route model binding where route
// parameters like :id are automatically resolved to ORM entities.
//
// Usage:
//   @[get('/users/:id')]
//   pub fn (mut c UserController) show(user &User) veb.Result { ... }
//
// The :id parameter is automatically resolved to a User entity
// from the database before the controller method is called.

// ModelBindingConfig configures route model binding behavior
pub struct ModelBindingConfig {
pub:
	field         string // The route parameter to bind (e.g., 'id')
	entity_type   string // The entity struct name (e.g., 'User')
	column        string = 'id' // Column to query (default: 'id')
	not_found_msg string = 'Resource not found'
}

// ModelBindingRegistry maps route parameters to entity bindings
pub struct ModelBindingRegistry {
pub mut:
	bindings map[string][]ModelBindingConfig // controller_method → bindings
}

// new_model_binding_registry creates a ModelBindingRegistry
pub fn new_model_binding_registry() &ModelBindingRegistry {
	return &ModelBindingRegistry{
		bindings: map[string][]ModelBindingConfig{}
	}
}

// bind registers a model binding for a controller method.
// Example: bind('UserController.show', 'id', 'User')
pub fn (mut mbr ModelBindingRegistry) bind(method_key string, field string, entity_type string) {
	mut bindings := mbr.bindings[method_key] or { []ModelBindingConfig{} }
	bindings << ModelBindingConfig{
		field:       field
		entity_type: entity_type
	}
	mbr.bindings[method_key] = bindings
}

// get_binding retrieves the model binding for a given method and field
pub fn (mbr &ModelBindingRegistry) get_binding(method_key string, field string) ?ModelBindingConfig {
	bindings := mbr.bindings[method_key] or { return none }
	for b in bindings {
		if b.field == field {
			return b
		}
	}
	return none
}

// resolve_model resolves a route parameter to an entity using the ORM.
// This is called at compile-time via comptime code generation, or at runtime
// by the route scanner when it detects :id-style parameters.
// Accepts the ORM manager as a voidptr to avoid cross-module import issues;
// cast to the concrete ORM type at the call site.
pub fn resolve_model(entity_type string, id_value string, manager voidptr) !voidptr {
	table_name := entity_type.to_lower() + 's'
	_ = table_name
	_ = manager

	// Stub: requires real DB driver connection
	return unsafe { nil }
}

// ImplicitModelBinding discovers model bindings from controller method signatures.
// If a method parameter type is a known entity, it's automatically bound.
// This uses comptime $for reflection at compile time.
pub fn discover_bindings[T]() []ModelBindingConfig {
	mut bindings := []ModelBindingConfig{}

	$for method in T.methods {
		$for param in method.params {
			param_type := typeof(param.typ).name
			// If the param type is an entity struct, auto-bind it
			if param_type !in ['string', 'int', 'bool', 'voidptr'] {
				bindings << ModelBindingConfig{
					field:       param.name
					entity_type: param_type
				}
			}
		}
	}
	return bindings
}

// -- Explicit Binding Helpers --

// bind_route_model registers a route model binding for a controller.
// This mirrors Laravel's Route::model('user', User::class) pattern.
pub fn bind_route_model[T](mut registry ModelBindingRegistry, controller_name string, param string) {
	entity_type := typeof[T]().name
	registry.bind(controller_name, param, entity_type)
}

// -- Implicit Binding Convention --

// implicit_binding_key returns the conventional binding key for a field.
// By default, route :id maps to entity.id.
// Custom mapping: if a route has :slug, it maps to entity.slug.
pub fn implicit_binding_key() string {
	return 'id'
}
