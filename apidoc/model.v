module apidoc

// model.v — API Documentation Data Model
//
// Types: ApiDocEntry, ApiDocParam, ApiDocHeader, ApiDocResponseProp

import json

// ApiDocParam represents a request parameter
pub struct ApiDocParam {
pub mut:
	name        string
	location    string // "query", "path", "header", "body"
	required    bool
	description string
	locked      bool
	type_       string @[json:'type']
	examples    []string
}

// ApiDocHeader represents a captured request header
pub struct ApiDocHeader {
pub mut:
	name         string
	description  string
	locked       bool
	value_sample string
}

// ApiDocResponseProp represents a property in the response schema
pub struct ApiDocResponseProp {
pub mut:
	path        string // e.g., "data.users[].name"
	description string
	locked      bool
	type_       string @[json:'type']
}

// ApiDocResponse wraps response metadata
pub struct ApiDocResponse {
pub mut:
	properties   []ApiDocResponseProp
	body_sample  string
	content_type string
	status_code  int
}

// ApiDocRequest wraps request body schema
pub struct ApiDocRequest {
pub mut:
	properties []ApiDocParam
}

// ApiDocEntry represents a fully documented API endpoint
pub struct ApiDocEntry {
pub:
	id string // "GET::/api/users"
pub mut:
	method    string
	path      string
	summary   string
	group     string
	locked    bool
	is_hidden bool
	parameters []ApiDocParam
	headers    []ApiDocHeader
	response   ApiDocResponse
	request    ApiDocRequest
	hit_count  int
}

// to_json serializes the entry as a JSON string using the built-in json module
pub fn (e &ApiDocEntry) to_json() string {
	return json.encode(e)
}
