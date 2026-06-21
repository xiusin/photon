module web

// input_test.v — Tests for Laravel-style Input service
import veb

fn ctx_with_query(query_string string) &veb.Context {
	mut ctx := &veb.Context{}
	ctx.req.url = '/test' + query_string
	if query_string.starts_with('?') {
		qs := query_string[1..]
		for kv in qs.split('&') {
			pair := kv.split('=')
			if pair.len == 2 {
				ctx.query[pair[0]] = pair[1]
			}
		}
	}
	return ctx
}

fn test_input_all() {
	ctx := ctx_with_query('?name=alice&email=alice@test.com')
	i := input(ctx)
	all := i.all()
	assert all['name'] == 'alice'
	assert all['email'] == 'alice@test.com'
}

fn test_input_get() {
	ctx := ctx_with_query('?name=alice')
	i := input(ctx)
	assert i.get('name', '') == 'alice'
	assert i.get('missing', 'default') == 'default'
}

fn test_input_only() {
	ctx := ctx_with_query('?name=alice&email=test@test.com&secret=xyz')
	i := input(ctx)
	result := i.only(['name', 'email'])
	assert result.len == 2
	assert result['name'] == 'alice'
	assert result['email'] == 'test@test.com'
	assert 'secret' !in result
}

fn test_input_except() {
	ctx := ctx_with_query('?name=alice&email=test@test.com&password=secret')
	i := input(ctx)
	result := i.except(['password'])
	assert result.len == 2
	assert 'password' !in result
}

fn test_input_has() {
	ctx := ctx_with_query('?name=alice')
	i := input(ctx)
	assert i.has('name') == true
	assert i.has('email') == false
}

fn test_input_filled() {
	ctx := ctx_with_query('?name=alice&empty=')
	i := input(ctx)
	assert i.filled('name') == true
	assert i.filled('empty') == false
	assert i.filled('missing') == false
}

fn test_input_missing() {
	ctx := ctx_with_query('?name=alice')
	i := input(ctx)
	assert i.missing('email') == true
	assert i.missing('name') == false
}

fn test_input_method() {
	mut ctx := ctx_with_query('')
	ctx.req.method = .post
	i := input(ctx)
	assert i.method() == 'POST'
}

fn test_input_path() {
	ctx := ctx_with_query('?name=test')
	i := input(ctx)
	assert i.path() == '/test'
	assert i.url() == '/test?name=test'
}

fn test_input_is_method() {
	mut ctx := ctx_with_query('')
	ctx.req.method = .delete
	i := input(ctx)
	assert i.is_method('DELETE') == true
	assert i.is_method('POST') == false
}

fn test_input_is_json() {
	mut ctx := ctx_with_query('')
	ctx.req.header.add_custom('Content-Type', 'application/json') or {}
	i := input(ctx)
	assert i.is_json() == true
}

fn test_input_json_body() {
	mut ctx := ctx_with_query('')
	ctx.req.data = '{"status":"ok"}'
	i := input(ctx)
	assert i.json_body() == '{"status":"ok"}'
}

fn test_input_integer() {
	ctx := ctx_with_query('?age=30')
	i := input(ctx)
	assert i.integer('age', 0) == 30
	assert i.integer('missing', 18) == 18
}

fn test_input_boolean() {
	ctx := ctx_with_query('?active=1&flag=true&on=yes')
	i := input(ctx)
	assert i.boolean('active', false) == true
	assert i.boolean('flag', false) == true
	assert i.boolean('on', false) == true
	assert i.boolean('missing', true) == true
}

fn test_input_has_file() {
	ctx := ctx_with_query('')
	i := input(ctx)
	assert i.has_file('avatar') == false
}
