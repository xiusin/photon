module security

// auth.v - Authentication Manager
//
// Provides the AuthenticationManager, authentication providers,
// and authentication tokens.
// PasswordEncoder interface and implementations live in password_encoder.v.

// PlainTextPasswordEncoder is a simple encoder for development only.
// It implements the PasswordEncoder interface defined in password_encoder.v.
pub struct PlainTextPasswordEncoder {}

pub fn (pe &PlainTextPasswordEncoder) encode(raw_password string) !string {
	return raw_password
}

pub fn (pe &PlainTextPasswordEncoder) matches(raw_password string, encoded_password string) !bool {
	return raw_password == encoded_password
}

pub fn (pe &PlainTextPasswordEncoder) upgrade_encoding(encoded string) bool {
	return false
}

// Authentication represents an authentication request or result
pub struct Authentication {
pub mut:
	principal     string
	credentials   string
	authorities   []string
	authenticated bool
	details       map[string]string
}

// new_authentication creates a new unauthenticated Authentication
pub fn new_authentication(principal string, credentials string) &Authentication {
	return &Authentication{
		principal:   principal
		credentials: credentials
	}
}

// is_authenticated returns whether the auth is authenticated
pub fn (a &Authentication) is_authenticated() bool {
	return a.authenticated
}

// mark_authenticated marks the authentication as successful
pub fn (mut a Authentication) mark_authenticated(authorities []string) {
	a.authenticated = true
	a.authorities = authorities
}

// AuthenticationProvider is a trait for authentication providers
pub interface AuthenticationProvider {
	supports(auth &Authentication) bool
	authenticate(auth &Authentication) !&Authentication
}

// AuthenticationManager orchestrates authentication through providers
pub struct AuthenticationManager {
pub mut:
	providers []&AuthenticationProvider
}

// new_auth_manager creates a new AuthenticationManager
pub fn new_auth_manager() &AuthenticationManager {
	return &AuthenticationManager{}
}

// add_provider adds an authentication provider
pub fn (mut am AuthenticationManager) add_provider(provider &AuthenticationProvider) {
	am.providers << provider
}

// authenticate runs the authentication through all providers
pub fn (am &AuthenticationManager) authenticate(mut auth Authentication) ! {
	for provider in am.providers {
		if provider.supports(auth) {
			result := provider.authenticate(auth)!
			auth.principal = result.principal
			auth.authorities = result.authorities
			auth.authenticated = true
			auth.details = result.details.clone()
			return
		}
	}
	return error('no authentication provider supports this authentication')
}

// JwtAuthenticationProvider authenticates using JWT tokens
pub struct JwtAuthenticationProvider {
pub:
	jwt_manager &JwtManager
}

// supports checks if the auth has a Bearer token or a JWT-like token.
// Bearer-prefixed tokens are always accepted; raw tokens are accepted
// if they have the JWT three-segment pattern or sufficient length.
pub fn (jp &JwtAuthenticationProvider) supports(auth &Authentication) bool {
	if auth.credentials.starts_with('Bearer ') {
		return true
	}
	// JWT-like check: three base64 segments separated by dots, or
	// long enough to be a raw JWT (min header+payload+sig)
	return auth.credentials.count('.') == 2 || auth.credentials.len > 20
}

// authenticate validates the JWT token
pub fn (jp &JwtAuthenticationProvider) authenticate(auth &Authentication) !&Authentication {
	token := auth.credentials
	mut jwt_token := token
	if token.starts_with('Bearer ') {
		jwt_token = token['Bearer '.len..]
	}

	claims := jp.jwt_manager.parse_token(jwt_token)!

	mut result := new_authentication(claims.sub, jwt_token)
	result.mark_authenticated(claims.roles)
	result.details['jti'] = claims.jti
	result.details['exp'] = claims.exp.str()
	result.details['iss'] = claims.iss

	return result
}

// UsernamePasswordAuthenticationProvider authenticates via username/password
pub struct UsernamePasswordAuthenticationProvider {
pub:
	user_service     &UserDetailsService
	password_encoder &PasswordEncoder
}

// supports checks if the auth has a username and password
pub fn (up &UsernamePasswordAuthenticationProvider) supports(auth &Authentication) bool {
	return auth.principal.len > 0 && auth.credentials.len > 0
		&& !auth.credentials.starts_with('Bearer ')
}

// authenticate validates username and password against UserDetailsService
pub fn (up &UsernamePasswordAuthenticationProvider) authenticate(auth &Authentication) !&Authentication {
	user := up.user_service.load_user_by_username(auth.principal)!

	// Validate password using the configured encoder
	if !up.password_encoder.matches(auth.credentials, user.password())! {
		return error('invalid credentials for user: ${auth.principal}')
	}

	// Check account status
	if !user.is_enabled() {
		return error('account is disabled: ${auth.principal}')
	}
	if !user.is_account_non_locked() {
		return error('account is locked: ${auth.principal}')
	}
	if !user.is_account_non_expired() {
		return error('account is expired: ${auth.principal}')
	}

	mut result := new_authentication(user.username(), '')
	result.mark_authenticated(user.authorities())

	return result
}
