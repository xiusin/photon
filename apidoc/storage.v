module apidoc

// storage.v — Thread-safe API Documentation Store
//
// Stores entries by reference (map[string]&ApiDocEntry) to support
// mutable access patterns required by the example controllers.

import sync
import json

// OpenAPI 3.0 output structures

struct OpenApiInfo {
	title   string
	version string
}

struct OpenApiSchema {
	type_ string @[json:'type']
}

struct OpenApiParam {
	name     string
	in_      string @[json:'in']
	required bool
	schema   OpenApiSchema
}

struct OpenApiResponse {
	description string
}

struct OpenApiOperation {
	summary      string
	operation_id string           @[json:'operationId']
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
	mu sync.Mutex
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
pub fn (mut s ApiDocStore) get_entries() []ApiDocEntry {
	s.mu.@lock()
	mut result := []ApiDocEntry{cap: s.entries.len}
	for _, ep in s.entries {
		result << *ep
	}
	s.mu.unlock()
	return result
}

// get_entry returns a mutable reference to an entry by ID
pub fn (mut s ApiDocStore) get_entry(id string) !&ApiDocEntry {
	s.mu.@lock()
	ep := s.entries[id] or {
		s.mu.unlock()
		return error('entry not found: ${id}')
	}
	s.mu.unlock()
	return ep
}

// get_or_create_entry returns existing mutable entry or creates a new one
pub fn (mut s ApiDocStore) get_or_create_entry(method string, path string) !&ApiDocEntry {
	s.mu.@lock()
	id := method.to_upper() + '::' + path
	if ep := s.entries[id] {
		s.mu.unlock()
		return ep
	}
	entry := &ApiDocEntry{
		id: id
		method: method.to_upper()
		path: path
	}
	s.entries[id] = entry
	s.mu.unlock()
	return entry
}

// update_entry updates an existing entry (no-op since entries are stored by reference)
pub fn (mut s ApiDocStore) update_entry(id string, entry &ApiDocEntry) ! {
	s.mu.@lock()
	if id !in s.entries {
		s.mu.unlock()
		return error('entry not found')
	}
	// Entry is already stored by reference — mutation is already reflected
	s.mu.unlock()
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
				name: p.name
				in_: p.location
				required: p.required
				schema: OpenApiSchema{type_: p.type_}
			}
		}
		op := OpenApiOperation{
			summary: ep.summary
			operation_id: ep.id
			parameters: params
			responses: {'200': OpenApiResponse{description: 'OK'}}
		}
		method_key := ep.method.to_lower()
		mut ops := (path_map[path_key] or { map[string]OpenApiOperation{} }).clone()
		ops[method_key] = op
		path_map[path_key] = ops.move()
	}

	// Build tags array
	mut tags_arr := []string{}
	for tag_name, _ in tag_set {
		tags_arr << '{"name":"${json_escape(tag_name)}"}'
	}
	tags_str := tags_arr.join(',')

	s.mu.unlock()

	doc := OpenApiDoc{
		openapi: '3.0.0'
		info: OpenApiInfo{title: 'API Documentation', version: '1.0.0'}
		paths: path_map
	}
	return json.encode(doc)
}
