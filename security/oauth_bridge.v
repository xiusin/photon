module security

// oauth_bridge.v — OAuth 令牌交换桥接层
//
// 桥接 veb.oauth 的 OAuth 授权码交换能力：
//   - 支持 form 和 json 两种 token 交换方式
//   - get_token(code) 获取 access token
//
// Spring 等价：Spring Security OAuth2 Client 的 token endpoint
//
// 用法：
//   oauth := security.new_oauth_context(
//       token_url: 'https://github.com/login/oauth/access_token'
//       client_id: 'your-client-id'
//       client_secret: 'your-client-secret'
//       redirect_uri: 'http://localhost:8080/callback'
//   )
//   token_resp := oauth.exchange_token('authorization_code_from_github') or {
//       // 处理错误
//       ''
//   }
import json
import net.http

// TokenPostType token 交换的请求格式
pub enum TokenPostType {
	form
	json
}

// OAuthContext OAuth 令牌交换上下文。
// 桥接 veb.oauth.Context。
//
// 字段说明：
//   token_url:       OAuth 提供方的 token endpoint URL
//   client_id:       注册的 client_id
//   client_secret:   注册的 client_secret
//   token_post_type: token 交换请求格式（form 或 json）
//   redirect_uri:    回调 URL
pub struct OAuthContext {
pub:
	token_url       string
	client_id       string
	client_secret   string
	token_post_type TokenPostType = .form
	redirect_uri    string
}

// new_oauth_context 创建 OAuth 上下文。
// 桥接 veb.oauth.Context 构造。
//
// 用法：
//   ctx := security.new_oauth_context(
//       token_url: 'https://github.com/login/oauth/access_token'
//       client_id: 'your-client-id'
//       client_secret: 'your-client-secret'
//       redirect_uri: 'http://localhost:8080/callback'
//   )
pub fn new_oauth_context(config OAuthContext) OAuthContext {
	return config
}

// exchange_token 用授权码交换 access token。
// 桥接 veb.oauth.Context.get_token()。
//
// 参数：
//   code: OAuth 提供方返回的授权码
//
// 返回：
//   token endpoint 的响应体（通常为 JSON，包含 access_token）
//
// 用法：
//   resp := oauth.exchange_token('auth_code_from_provider') or {
//       println('OAuth error: ${err}')
//       return
//   }
//   // 解析 JSON 响应
//   token_data := json.decode(json.Any, resp)!
pub fn (ctx &OAuthContext) exchange_token(code string) ?string {
	if ctx.token_post_type == .json {
		body := json.encode({
			'client_id':     ctx.client_id
			'client_secret': ctx.client_secret
			'code':          code
		})
		resp := http.post_json(ctx.token_url, body) or { return none }
		return resp.body
	} else {
		resp := http.post_form(ctx.token_url, {
			'client_id':     ctx.client_id
			'client_secret': ctx.client_secret
			'code':          code
			'grant_type':    'authorization_code'
			'redirect_uri':  ctx.redirect_uri
		}) or { return none }
		return resp.body
	}
}

// OAuthRequest OAuth 请求参数。
// 桥接 veb.oauth.Request。
pub struct OAuthRequest {
pub:
	client_id     string
	client_secret string
	code          string
	state         string
}

// build_authorization_url 构建 OAuth 授权页面 URL。
// 将用户重定向到此 URL 进行授权。
//
// 用法：
//   url := security.build_authorization_url(
//       authorize_url: 'https://github.com/login/oauth/authorize'
//       client_id: 'your-client-id'
//       redirect_uri: 'http://localhost:8080/callback'
//       state: csrf_token
//       scope: 'user:email'
//   )
//   // 重定向用户到 url
pub fn build_authorization_url(authorize_url string, client_id string, redirect_uri string, state string, scope string) string {
	mut url := '${authorize_url}?'
	url += 'client_id=${client_id}'
	url += '&redirect_uri=${redirect_uri}'
	url += '&state=${state}'
	if scope.len > 0 {
		url += '&scope=${scope}'
	}
	return url
}
