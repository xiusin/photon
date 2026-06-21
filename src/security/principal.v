module security

// principal.v - User Identity Abstraction
//
// Defines the UserDetails trait (equivalent to Spring Security's UserDetails)
// and provides a simple default implementation. This is the core identity
// model used throughout the security module.

// UserDetails represents an authenticated user's identity
pub interface UserDetails {
	username() string
	password() string
	authorities() []string
	is_enabled() bool
	is_account_non_expired() bool
	is_account_non_locked() bool
	is_credentials_non_expired() bool
}

// SimpleUserDetails is a concrete UserDetails implementation
pub struct SimpleUserDetails {
pub:
	username_str string
	password_str string
	roles        []string
pub mut:
	enabled             bool = true
	account_expired     bool
	account_locked      bool
	credentials_expired bool
}

// new_user creates a new SimpleUserDetails
pub fn new_user(username string, password string, roles []string) &SimpleUserDetails {
	return &SimpleUserDetails{
		username_str: username
		password_str: password
		roles:        roles
		enabled:      true
	}
}

// username returns the username
pub fn (u &SimpleUserDetails) username() string {
	return u.username_str
}

// password returns the password
pub fn (u &SimpleUserDetails) password() string {
	return u.password_str
}

// authorities returns the granted roles as authorities
pub fn (u &SimpleUserDetails) authorities() []string {
	return u.roles
}

// is_enabled returns whether the account is enabled
pub fn (u &SimpleUserDetails) is_enabled() bool {
	return u.enabled
}

// is_account_non_expired returns whether the account is not expired
pub fn (u &SimpleUserDetails) is_account_non_expired() bool {
	return !u.account_expired
}

// is_account_non_locked returns whether the account is not locked
pub fn (u &SimpleUserDetails) is_account_non_locked() bool {
	return !u.account_locked
}

// is_credentials_non_expired returns whether credentials are not expired
pub fn (u &SimpleUserDetails) is_credentials_non_expired() bool {
	return !u.credentials_expired
}

// UserDetailsService is the trait for loading user-specific data
pub interface UserDetailsService {
	load_user_by_username(username string) !&UserDetails
}

// InMemoryUserDetailsService stores users in memory (dev/testing)
pub struct InMemoryUserDetailsService {
pub mut:
	users map[string]&UserDetails
}

// new_in_memory_service creates a new InMemoryUserDetailsService
pub fn new_in_memory_service() &InMemoryUserDetailsService {
	return &InMemoryUserDetailsService{
		users: map[string]&UserDetails{}
	}
}

// add_user adds a user to the in-memory store
pub fn (mut s InMemoryUserDetailsService) add_user(user &UserDetails) {
	unsafe {
		s.users[user.username()] = user
	}
}

// load_user_by_username finds a user by username
pub fn (s &InMemoryUserDetailsService) load_user_by_username(username string) !&UserDetails {
	return s.users[username] or { return error('user not found: ${username}') }
}
