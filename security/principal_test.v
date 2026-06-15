module security

// principal_test.v - Tests for UserDetails and InMemoryUserDetailsService

fn test_new_user() {
	u := new_user('admin', 'secret', ['ADMIN', 'USER'])
	assert u.username() == 'admin'
	assert u.password() == 'secret'
	assert u.authorities().len == 2
	assert u.authorities()[0] == 'ADMIN'
}

fn test_user_details_interface() {
	u := new_user('john', 'pass123', ['USER'])

	assert u.username() == 'john'
	assert u.password() == 'pass123'
	assert u.authorities().len == 1
	assert u.is_enabled() == true
	assert u.is_account_non_expired() == true
	assert u.is_account_non_locked() == true
	assert u.is_credentials_non_expired() == true
}

fn test_user_disabled() {
	mut u := new_user('disabled_user', 'pass', [])
	u.enabled = false
	assert u.is_enabled() == false
}

fn test_new_in_memory_service() {
	svc := new_in_memory_service()
	assert svc != unsafe { nil }
}

fn test_add_and_load_user() {
	mut svc := new_in_memory_service()
	u := new_user('admin', 'pass', ['ADMIN'])
	svc.add_user(u)
	loaded := svc.load_user_by_username('admin') or {
		assert false
		return
	}
	assert loaded.username() == 'admin'
}

fn test_load_multiple_users() {
	mut svc := new_in_memory_service()
	svc.add_user(new_user('alice', 'p1', ['USER']))
	svc.add_user(new_user('bob', 'p2', ['MODERATOR']))

	alice := svc.load_user_by_username('alice') or {
		assert false
		return
	}
	assert alice.username() == 'alice'
	assert alice.authorities().len == 1

	bob := svc.load_user_by_username('bob') or {
		assert false
		return
	}
	assert bob.username() == 'bob'
	assert bob.authorities()[0] == 'MODERATOR'
}

fn test_load_three_users() {
	mut svc := new_in_memory_service()
	svc.add_user(new_user('u1', 'p1', ['USER']))
	svc.add_user(new_user('u2', 'p2', ['USER']))
	svc.add_user(new_user('u3', 'p3', ['ADMIN']))

	u1 := svc.load_user_by_username('u1') or {
		assert false
		return
	}
	u2 := svc.load_user_by_username('u2') or {
		assert false
		return
	}
	u3 := svc.load_user_by_username('u3') or {
		assert false
		return
	}

	assert u1.username() == 'u1'
	assert u2.username() == 'u2'
	assert u3.authorities()[0] == 'ADMIN'
}
