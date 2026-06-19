module web

// bind_test.v — Tests for Spring-style DTO Binding
import veb

struct SimpleDto {
	name  string
	email string
}

struct LoginDto {
	username string @[required]
	password string @[required]
	remember bool
}

struct NamedDto {
	user_name string @[form: 'username']
	user_age  int    @[form: 'age']
}

fn ctx_with_params(params string) &veb.Context {
	mut ctx := &veb.Context{}
	ctx.req.url = '/test' + params
	if params.starts_with('?') {
		qs := params[1..]
		for kv in qs.split('&') {
			pair := kv.split('=')
			if pair.len == 2 {
				ctx.query[pair[0]] = pair[1]
			}
		}
	}
	return ctx
}

fn test_bind_simple() {
	ctx := ctx_with_params('?name=alice&email=alice@test.com')
	dto := bind[SimpleDto](ctx) or {
		assert false
		return
	}
	assert dto.name == 'alice'
	assert dto.email == 'alice@test.com'
}

fn test_bind_with_type_conversion() {
	ctx := ctx_with_params('?username=admin&password=secret&remember=1')
	dto := bind[LoginDto](ctx) or {
		assert false
		return
	}
	assert dto.username == 'admin'
	assert dto.password == 'secret'
	assert dto.remember == true
}

fn test_bind_missing_optional() {
	ctx := ctx_with_params('?name=only')
	dto := bind[SimpleDto](ctx) or {
		assert false
		return
	}
	assert dto.name == 'only'
	assert dto.email == '' // missing optional
}

fn test_bind_required_missing() {
	// username is required but missing
	ctx := ctx_with_params('?password=secret')
	_ = bind[LoginDto](ctx) or {
		// Expected error
		return
	}
	assert false // should not reach here
}

fn test_bind_with_form_alias() {
	ctx := ctx_with_params('?username=bob&age=25')
	dto := bind[NamedDto](ctx) or {
		assert false
		return
	}
	assert dto.user_name == 'bob'
	assert dto.user_age == 25
}

fn test_bind_json() {
	mut ctx := ctx_with_params('')
	ctx.req.data = '{"name":"alice","email":"alice@test.com"}'
	dto := bind_json[SimpleDto](ctx) or {
		assert false
		return
	}
	assert dto.name == 'alice'
	assert dto.email == 'alice@test.com'
}

fn test_bind_json_empty_body() {
	ctx := ctx_with_params('')
	_ = bind_json[SimpleDto](ctx) or { return }
	assert false
}

fn test_extract_attr_arg_simple() {
	result := extract_attr_arg("form: 'username'")
	assert result == 'username'
}

fn test_extract_attr_arg_no_arg() {
	result := extract_attr_arg('required')
	assert result == 'required'
}

fn test_bind_empty_input() {
	ctx := ctx_with_params('')
	dto := bind[SimpleDto](ctx) or {
		assert false
		return
	}
	assert dto.name == ''
	assert dto.email == ''
}
