module apidoc

// model.v — API Documentation Data Model
//
// Types: ApiDocEntry, ApiDocParam, ApiDocHeader, ApiDocResponseProp

// ApiDocParam represents a request parameter
pub struct ApiDocParam {
pub mut:
	name        string
	location    string // "query", "path", "header", "body"
	required    bool
	description string
	locked      bool
	type_       string
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
	type_       string
}

// ApiDocResponse wraps response metadata
pub struct ApiDocResponse {
pub mut:
	properties []ApiDocResponseProp
	body_sample string
	content_type string
	status_code int
}

// ApiDocRequest wraps request body schema
pub struct ApiDocRequest {
pub mut:
	properties []ApiDocParam
}

// ApiDocEntry represents a fully documented API endpoint
pub struct ApiDocEntry {
pub:
	id        string // "GET::/api/users"
pub mut:
	method    string
	path      string
	summary    string
	group      string
	locked     bool
	is_hidden  bool
	parameters []ApiDocParam
	headers    []ApiDocHeader
	response   ApiDocResponse
	request    ApiDocRequest
	hit_count  int
}

// to_json serializes the entry as a JSON string
pub fn (e &ApiDocEntry) to_json() string {
	mut parts := []string{}
	parts << '"id":"${e.id}"'
	parts << '"method":"${e.method}"'
	parts << '"path":"${e.path}"'
	parts << '"summary":"${e.summary}"'
	parts << '"group":"${e.group}"'
	parts << '"locked":${e.locked}'
	parts << '"is_hidden":${e.is_hidden}'
	parts << '"hit_count":${e.hit_count}'

	// Parameters
	mut pstrs := []string{}
	for p in e.parameters {
		mut pp := []string{}
		pp << '"name":"${p.name}"'
		pp << '"location":"${p.location}"'
		pp << '"required":${p.required}'
		pp << '"description":"${p.description}"'
		pp << '"locked":${p.locked}'
		pp << '"type":"${p.type_}"'
		mut ex := []string{}
		for ex_val in p.examples {
			ex << '"${ex_val}"'
		}
		pp << '"examples":[${ex.join(',')}]'
		pstrs << '{${pp.join(',')}}'
	}
	parts << '"parameters":[${pstrs.join(',')}]'

	// Headers
	mut hstrs := []string{}
	for h in e.headers {
		mut hp := []string{}
		hp << '"name":"${h.name}"'
		hp << '"description":"${h.description}"'
		hp << '"locked":${h.locked}'
		hp << '"value_sample":"${h.value_sample}"'
		hstrs << '{${hp.join(',')}}'
	}
	parts << '"headers":[${hstrs.join(',')}]'

	// Response properties
	mut rpstrs := []string{}
	for rp in e.response.properties {
		mut rpj := []string{}
		rpj << '"path":"${rp.path}"'
		rpj << '"description":"${rp.description}"'
		rpj << '"locked":${rp.locked}'
		rpj << '"type":"${rp.type_}"'
		rpstrs << '{${rpj.join(',')}}'
	}
	parts << '"response":{"properties":[${rpstrs.join(',')}]'

// Response body sample and content type
	if e.response.body_sample.len > 0 {
		parts << ',"body_sample":"${e.response.body_sample}"'
	}
	parts << ',"content_type":"${e.response.content_type}"'
	parts << ',"status_code":${e.response.status_code}}'

	return '{${parts.join(',')}}'
}
