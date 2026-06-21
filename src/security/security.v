module security

// security.v - Photon Security Module
//
// Provides authentication, authorization, JWT, RBAC, and CSRF protection.
// Integrates with the Photon web module via middleware and annotations.
//
// Architecture:
//   principal.v  - UserDetails trait, user identity abstraction
//   jwt.v        - JWT token creation, parsing, validation (HMAC-SHA256)
//   auth.v       - AuthenticationManager, providers, tokens
//   role.v       - RBAC: roles, permissions, granted authorities, hierarchy
//   csrf.v       - CSRF token generation, double-submit cookie pattern
//   annotations.v - @[secured], @[roles_allowed], @[permit_all], @[deny_all]
//   filter.v     - SecurityFilterChain for veb web integration
//   context.v    - SecurityContext (request-scoped auth state holder)
