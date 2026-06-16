module apidoc

// storage.v — Thread-safe API Documentation Store
//
// Stores entries by reference (map[string]&ApiDocEntry) to support
// mutable access patterns required by the example controllers.

import sync

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
	mut paths := ''
	mut tag_set := map[string]bool{}

	for _, ep in s.entries {
		path_key := ep.path
		if path_key.len == 0 { continue }

		// Collect tags from group
		group := ep.group
		if group.len > 0 {
			tag_set[group] = true
		}

		mut op := '"${ep.method.to_lower()}":{"summary":"${json_escape(ep.summary)}","operationId":"${json_escape(ep.id)}"'
		if group.len > 0 {
			op += ',"tags":["${json_escape(group)}"]'
		}
		if ep.parameters.len > 0 {
			mut plist := []string{}
			for p in ep.parameters {
				mut schema_type := p.type_
				// Map inferred types to OpenAPI types
				if schema_type == 'int' { schema_type = 'integer' }
				else if schema_type == 'float' { schema_type = 'number' }
				else if schema_type == 'bool' { schema_type = 'boolean' }
				else { schema_type = 'string' }
				plist << '{"name":"${json_escape(p.name)}","in":"${json_escape(p.location)}","required":${p.required},"schema":{"type":"${schema_type}"}}'
			}
			op += ',"parameters":[${plist.join(',')}]'
		}
		if ep.headers.len > 0 {
			mut hlist := []string{}
			for h in ep.headers {
				hlist << '{"name":"${json_escape(h.name)}","in":"header","required":false,"description":"${json_escape(h.description)}","schema":{"type":"string"}}'
			}
			op += ',"parameters":[${hlist.join(',')}]'
		}

		// Build response schema
		mut resp_schema := ''
		if ep.response.properties.len > 0 {
			mut props := []string{}
			for rp in ep.response.properties {
				mut rp_type := rp.type_
				if rp_type == 'int' { rp_type = 'integer' }
				else if rp_type == 'float' { rp_type = 'number' }
				else if rp_type == 'bool' { rp_type = 'boolean' }
				else { rp_type = 'string' }
				props << '"${json_escape(rp.path)}":{"type":"${rp_type}","description":"${json_escape(rp.description)}"}'
			}
			resp_schema = '{"type":"object","properties":{${props.join(',')}}}'
		} else {
			resp_schema = '{"type":"object"}'
		}

		op += ',"responses":{"${ep.response.status_code}":{"description":"OK","content":{"${json_escape(ep.response.content_type)}":{"schema":${resp_schema}}}}}'
		op += '}'
		paths += '"${json_escape(path_key)}":{${op}},'
	}
	paths = paths.trim_right(',')

	// Build tags array
	mut tags_arr := []string{}
	for tag_name, _ in tag_set {
		tags_arr << '{"name":"${json_escape(tag_name)}"}'
	}
	tags_str := tags_arr.join(',')

	s.mu.unlock()
	return '{"openapi":"3.0.0","info":{"title":"API Documentation","version":"1.0.0","description":"Auto-generated API documentation from Photon Framework"},"servers":[{"url":"http://localhost:8080","description":"Development server"}],"tags":[${tags_str}],"paths":{${paths}}}'
}
