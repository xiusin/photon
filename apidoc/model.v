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

// json_escape escapes a string for safe JSON output
fn json_escape(s string) string {
	mut out := ''
	for ch in s {
		match ch {
			`"` { out += '\\"' }
			`\\` { out += '\\\\' }
			`\n` { out += '\\n' }
			`\r` { out += '\\r' }
			`\t` { out += '\\t' }
			else { out += ch.ascii_str() }
		}
	}
	return out
}

// to_json serializes the entry as a JSON string
pub fn (e &ApiDocEntry) to_json() string {
	mut parts := []string{}
	parts << '"id":"${json_escape(e.id)}"'
	parts << '"method":"${json_escape(e.method)}"'
	parts << '"path":"${json_escape(e.path)}"'
	parts << '"summary":"${json_escape(e.summary)}"'
	parts << '"group":"${json_escape(e.group)}"'
	parts << '"locked":${e.locked}'
	parts << '"is_hidden":${e.is_hidden}'
	parts << '"hit_count":${e.hit_count}'

	// Parameters
	mut pstrs := []string{}
	for p in e.parameters {
		mut pp := []string{}
		pp << '"name":"${json_escape(p.name)}"'
		pp << '"location":"${json_escape(p.location)}"'
		pp << '"required":${p.required}'
		pp << '"description":"${json_escape(p.description)}"'
		pp << '"locked":${p.locked}'
		pp << '"type":"${json_escape(p.type_)}"'
		mut ex := []string{}
		for ex_val in p.examples {
			ex << '"${json_escape(ex_val)}"'
		}
		pp << '"examples":[${ex.join(',')}]'
		pstrs << '{${pp.join(',')}}'
	}
	parts << '"parameters":[${pstrs.join(',')}]'

	// Headers
	mut hstrs := []string{}
	for h in e.headers {
		mut hp := []string{}
		hp << '"name":"${json_escape(h.name)}"'
		hp << '"description":"${json_escape(h.description)}"'
		hp << '"locked":${h.locked}'
		hp << '"value_sample":"${json_escape(h.value_sample)}"'
		hstrs << '{${hp.join(',')}}'
	}
	parts << '"headers":[${hstrs.join(',')}]'

	// Response properties
	mut rpstrs := []string{}
	for rp in e.response.properties {
		mut rpj := []string{}
		rpj << '"path":"${json_escape(rp.path)}"'
		rpj << '"description":"${json_escape(rp.description)}"'
		rpj << '"locked":${rp.locked}'
		rpj << '"type":"${json_escape(rp.type_)}"'
		rpstrs << '{${rpj.join(',')}}'
	}
	parts << '"response":{"properties":[${rpstrs.join(',')}]'

// Response body sample and content type
	if e.response.body_sample.len > 0 {
		parts << ',"body_sample":"${json_escape(e.response.body_sample)}"'
	}
	parts << ',"content_type":"${json_escape(e.response.content_type)}"'
	parts << ',"status_code":${e.response.status_code}}'

	return '{${parts.join(',')}}'
}
