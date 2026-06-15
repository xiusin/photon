module web

// web.v - Photon Web Module
//
// Provides annotation-driven web development on top of V's veb framework.
// Features: annotation-based routing, middleware chain, filters,
// unified response wrapper, CORS support, request/response interception.
//
// All web components are in a single `module web`:
//   controller.v - Controller base with veb.Context
//   router.v     - Annotation-driven route scanner
//   middleware.v - Composable middleware chain
//   filter.v     - Request/response filters
//   result.v     - Unified API response wrapper
