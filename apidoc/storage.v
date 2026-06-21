module apidoc

// storage.v — Thread-safe API Documentation Store
//
// Entries are stored by reference (map[string]&ApiDocEntry). Mutable access is
// only exposed through the with_entry / with_or_create_entry callbacks, which
// invoke the caller's logic while the store lock is held. This guarantees that
// every field modification is atomic with respect to other store methods
// (lock_endpoint, unlock_endpoint, delete_entry, ...) and eliminates the data
// race that existed when mutable references were returned after unlock.
// Read-only access is provided by get_entry, which returns a value copy.
import sync
import json

// OpenAPI 3.0 output structures

struct OpenApiInfo {
	title   string
	version string
}

struct OpenApiSchema {
	type_ string @[json: 'type']
}

struct OpenApiParam {
	name     string
	in_      string @[json: 'in']
	required bool
	schema   OpenApiSchema
}

struct OpenApiResponse {
	description string
}

struct OpenApiOperation {
	summary      string
	operation_id string @[json: 'operationId']
	parameters   []OpenApiParam
	responses    map[string]OpenApiResponse
}

struct OpenApiDoc {
	openapi string
	info    OpenApiInfo
	paths   map[string]map[string]OpenApiOperation
}

@[heap]
pub struct ApiDocStore {
pub mut:
	entries map[string]&ApiDocEntry
mut:
	mu sync.Mutex
}

pub fn new_store() &ApiDocStore {
	return &ApiDocStore{
		entries: map[string]&ApiDocEntry{}
	}
}

// thread-safe singleton holder
struct DocStoreSingleton {
mut:
	mu    sync.Mutex
	store &ApiDocStore = unsafe { nil }
}

__global (
	g_singleton DocStoreSingleton
)

pub fn get_store() &ApiDocStore {
	g_singleton.mu.@lock()
	defer { g_singleton.mu.unlock() }
	if isnil(g_singleton.store) {
		g_singleton.store = new_store()
	}
	return g_singleton.store
}

// get_entries returns all entries as copies
pub fn (mut s ApiDocStore) get_entries() []apidoc.ApiDocEntry {
	s.mu.@lock()
	mut result := []ApiDocEntry{cap: s.entries.len}
	for _, ep in s.entries {
		result << *ep
	}
	s.mu.unlock()
	return result
}

// get_entry returns a value copy of an entry by ID (read-only, thread-safe).
// Callers that need to mutate an entry must use with_entry / with_or_create_entry
// so that all modifications happen while the store lock is held.
pub fn (mut s ApiDocStore) get_entry(id string) !ApiDocEntry {
	s.mu.@lock()
	defer { s.mu.unlock() }
	ep := s.entries[id] or { return error('entry not found: ${id}') }
	return *ep
}

// with_entry looks up an entry by ID and invokes f with a mutable reference
// to it while holding the store lock. All modifications performed inside f
// are atomic with respect to other store methods (e.g. lock_endpoint).
pub fn (mut s ApiDocStore) with_entry(id string, f fn (mut entry ApiDocEntry) !) ! {
	s.mu.@lock()
	defer { s.mu.unlock() }
	mut entry := s.entries[id] or { return error('entry not found: ${id}') }
	f(mut entry)!
}

// with_or_create_entry returns an existing entry (or creates a new one) and
// invokes f with a mutable reference to it while holding the store lock.
pub fn (mut s ApiDocStore) with_or_create_entry(method string, path string, f fn (mut entry ApiDocEntry) !) ! {
	s.mu.@lock()
	defer { s.mu.unlock() }
	id := method.to_upper() + '::' + path
	mut entry := s.entries[id] or {
		e := &ApiDocEntry{
			id:     id
			method: method.to_upper()
			path:   path
		}
		s.entries[id] = e
		e
	}
	f(mut entry)!
}

// delete_entry removes an entry
pub fn (mut s ApiDocStore) delete_entry(id string) ! {
	s.mu.@lock()
	if id !in s.entries {
		s.mu.unlock()
		return error('entry not found')
	}
	s.entries.delete(id)
	s.mu.unlock()
}

// lock_endpoint locks an endpoint
pub fn (mut s ApiDocStore) lock_endpoint(id string) {
	s.mu.@lock()
	if mut ep := s.entries[id] {
		ep.locked = true
	}
	s.mu.unlock()
}

// unlock_endpoint unlocks an endpoint
pub fn (mut s ApiDocStore) unlock_endpoint(id string) {
	s.mu.@lock()
	if mut ep := s.entries[id] {
		ep.locked = false
	}
	s.mu.unlock()
}

// reset clears all entries
pub fn (mut s ApiDocStore) reset() {
	s.mu.@lock()
	s.entries.clear()
	s.mu.unlock()
}

// export_openapi generates a more complete OpenAPI 3.0 JSON
pub fn (mut s ApiDocStore) export_openapi() string {
	s.mu.@lock()

	mut path_map := map[string]map[string]OpenApiOperation{}
	for _, ep in s.entries {
		path_key := ep.path
		if path_key.len == 0 {
			continue
		}
		mut params := []OpenApiParam{}
		for p in ep.parameters {
			params << OpenApiParam{
				name:     p.name
				in_:      p.location
				required: p.required
				schema:   OpenApiSchema{
					type_: p.type_
				}
			}
		}
		op := OpenApiOperation{
			summary:      ep.summary
			operation_id: ep.id
			parameters:   params
			responses:    {
				'200': OpenApiResponse{
					description: 'OK'
				}
			}
		}
		method_key := ep.method.to_lower()
		mut ops := (path_map[path_key] or {
			map[string]OpenApiOperation{}
		}).clone()
		ops[method_key] = op
		path_map[path_key] = ops.move()
	}

	s.mu.unlock()

	doc := OpenApiDoc{
		openapi: '3.0.0'
		info:    OpenApiInfo{
			title:   'API Documentation'
			version: '1.0.0'
		}
		paths:   path_map
	}
	return json.encode(doc)
}
