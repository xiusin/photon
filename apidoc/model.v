module apidoc

// model.v — API Documentation Data Model
//
// Types: ApiDocEntry, ApiDocParam, ApiDocHeader, ApiDocResponseProp
import x.json2

// ApiDocParam represents a request parameter
pub struct ApiDocParam {
pub mut:
	name        string
	location    string // "query", "path", "header", "body"
	required    bool
	description string
	locked      bool
	type_       string @[json: 'type']
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
	type_       string @[json: 'type']
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
	method     string
	path       string
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

// ApiDocEntryView is the JSON projection of ApiDocEntry.
//
// json2 dispatches any struct with a to_json() method to that method instead of
// encoding its fields (the JsonEncoder interface). Encoding ApiDocEntry from
// inside its own to_json() therefore calls itself until the stack overflows.
// This view type has no methods, so json2 encodes it field by field.
struct ApiDocEntryView {
	id         string
	method     string
	path       string
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

// to_json serializes the entry as a JSON string.
//
// ⚠️ 不能写成 `json2.encode(e)`：ApiDocEntry 实现了 to_json()，json2 会把它当作
// JsonEncoder 回头调用本方法，首次请求 /__docs/api/entries 就会栈溢出崩溃。
pub fn (e &ApiDocEntry) to_json() string {
	view := ApiDocEntryView{
		id:         e.id
		method:     e.method
		path:       e.path
		summary:    e.summary
		group:      e.group
		locked:     e.locked
		is_hidden:  e.is_hidden
		parameters: e.parameters
		headers:    e.headers
		response:   e.response
		request:    e.request
		hit_count:  e.hit_count
	}
	return json2.encode(view)
}
