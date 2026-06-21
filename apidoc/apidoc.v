module apidoc

// apidoc.v — Module Entry Point
//
// init(), encode_response(), api_error() for the example application.
import os

// init initializes the API documentation module.
pub fn init(storage_path string) !(&ApiDocStore, &Collector) {
	store := get_store()

	if storage_path.len > 0 && !os.exists(storage_path) {
		os.mkdir_all(storage_path) or { return error('failed to create apidoc storage: ${err}') }
	}

	coll := new_collector(store)
	return store, coll
}

// init_without_collector returns just the store
pub fn init_store(storage_path string) !&ApiDocStore {
	store := get_store()
	if storage_path.len > 0 && !os.exists(storage_path) {
		os.mkdir_all(storage_path) or { return error('failed to create apidoc storage: ${err}') }
	}
	return store
}

// encode_response formats a standard JSON API response.
pub fn encode_response(code int, msg string, data string) string {
	return '{"code":${code},"msg":"${msg}","data":${data}}'
}

// api_error formats a standard JSON API error response.
pub fn api_error(code int, msg string) string {
	return '{"code":${code},"msg":"${msg}"}'
}
