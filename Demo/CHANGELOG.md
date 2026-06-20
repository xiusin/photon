# Changelog

All notable changes to PhotonBlog are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Planned

- Test base class (`TestCase`, `RefreshDatabase`) integration
- Additional integration tests for soft delete and eager loading

---

## [0.2.0] - 2026-06-20

### Summary

Major upgrade transforming PhotonBlog from a flat demo into a **skeleton-grade reference project** with Laravel-level code quality and encapsulation. This release restructures the entire codebase into a layered architecture with ServiceProvider-based DI, annotation-driven configuration, and a complete CLI toolkit.

### Added — Architecture

- **ServiceProvider pattern**: 9 service providers (`AppServiceProvider`, `DatabaseServiceProvider`, `CacheServiceProvider`, `WebServiceProvider`, `AuthServiceProvider`, `QueueServiceProvider`, `EventServiceProvider`, `RepositoryServiceProvider`, `ServiceServiceProvider`) with `register()` + `boot()` lifecycle.
- **AppKernel**: Application kernel orchestrating provider registration and `refresh()` lifecycle in [bootstrap/app.v](bootstrap/app.v).
- **BootContext**: Type-safe shared mutable state container passed between providers, eliminating `unsafe { voidptr(x) }` type erasure.
- **Layered directory structure**: `app/Http/{Middleware,Resources}`, `bootstrap/`, `config/`, `database/{migrations,seeders,factories}`, `providers/`, `routes/`, `docs/`.

### Added — Configuration

- Per-concern config files in `config/`: `app.v`, `database.v`, `jwt.v`, `cache.v`, `mail.v`, `storage.v`, `logging.v`, `web.v`, `auth.v`.
- `load_config(profile)` scans `config/*.v`, loads `.env`, and resolves `${PLACEHOLDER}` variables via `Environment.resolve_placeholders`.
- Production environment validation: `APP_PROFILE=prod` with empty/default `JWT_SECRET` fails fast at startup.
- Role hierarchy loaded from `config/auth.v` (removed hardcoded `rh.add_role('ADMIN', ['EDITOR'])`).
- Environment files: `.env.example`, `.env.prod.example`, `.env.testing`.

### Added — Web Layer

- **Unified response format**: `web.Result` envelope with `success`/`code`/`message`/`data`/`timestamp`/`path` via `web.success` / `web.fail` / `web.page` / `web.created` / `web.ok` / `web.bad_request` / `web.not_found` / `web.unauthorized` / `web.forbidden`.
- **Exception handling**: `ExceptionHandlerRegistry` in [app/Http/Kernel.v](app/Http/Kernel.v) mapping `BadRequestException`/`NotFoundException`/`ValidationException`/`UnauthorizedException`/`ForbiddenException`/`ConflictException`/`RateLimitExceededException` to proper HTTP status codes. Default handler catches unknown exceptions and returns 500 (stack trace hidden in production).
- **Form request validation**: DTOs annotated with `@[validate: 'required|email|min_len:6']` rules, validated via `web.validate_body[T](ctx)`. Removed all inline `if dto.x.len == 0` checks.
- **Middleware groups**: `MiddlewareGroupRegistry` in [app/Http/Middleware/registry.v](app/Http/Middleware/registry.v) with named groups `web` (CORS+RequestId+RequestLog+CSRF), `api` (web minus CSRF + RateLimit), `auth` (JwtAuth), `admin` (auth+RoleAuth[ADMIN]), `editor` (auth+RoleAuth[EDITOR,ADMIN]).
- **API Resources**: Laravel-style response transformers in [app/Http/Resources/](app/Http/Resources/) — `UserResource` (hides `password`), `PostResource` (nests author/category/tags), `CommentResource` (nests user/replies), `CategoryResource`, `TagResource`, and `ResourceCollection[T]` for batch + pagination metadata.
- **Pagination**: `support.LengthAwarePaginator[T]` replacing hand-written `start..end` slicing in list endpoints, with `meta`/`links` metadata in responses.

### Added — Data Layer

- **Repository pattern upgrade**: All repositories extend `orm.EagerRepository[T]` with `with(['author','category','tags'])` eager loading to eliminate N+1 queries.
- **Filter structs**: `PostFilter`, `UserFilter`, `CommentFilter` pushing filter/sort/pagination down to SQL via `find_with_filters(...)`.
- **Soft deletes**: Entities use `orm.SoftDeletableEntity` with `deleted_at` field. Added `restore(id)`, `force_delete(id)`, `with_trashed()` methods. Queries auto-filter soft-deleted rows.
- **ORM adapter**: Replaced manual `row_to_*` mapping and SQLite-specific `last_insert_rowid()` with `orm.OrmAdapter[T]` auto-mapping.
- **Versioned migrations**: 6 timestamped migration files in [database/migrations/](database/migrations/) auto-scanned and sorted by filename timestamp. `MigrationManager` handles up/down.
- **Factories**: Builder-pattern factories (`UserFactory`, `PostFactory`, `CommentFactory`) with `new()`/`with_role(role)`/`create() !T`/`make() T`.
- **Seeders**: Idempotent seeders (`DatabaseSeeder`, `UserSeeder`, `PostSeeder`, `CommentSeeder`) — 1 ADMIN + 2 EDITOR + 5 USER + 10 posts + 20 comments.

### Added — Caching & Locking

- **Singleflight**: Cache stampede prevention via `cache.get_or_load()` + Singleflight in `PostService.get_post`/`get_posts`.
- **Tagged cache**: Tag-based bulk invalidation — `tagged_cache.flush('posts')` on post update, `flush('users')` on user update, `flush('stats')` on stats update.
- **`cache_remember` helper**: Generic `cache_remember[T](cm, key, ttl, loader)` in [helpers.v](helpers.v).
- **Cache corruption fix**: `json.decode` failure now deletes the stale cache key and reloads, instead of silently returning an empty entity.
- **LockGuard RAII**: `locking.new_lock_guard(mut lm, key)` replacing manual `lock`/`unlock` in `PostService.publish_post`/`update_post` and `StatsService.aggregate_stats`.

### Added — Security

- **CSRF protection**: `CsrfMiddleware` wrapping `security.CsrfManager` (Double-Submit Cookie pattern) for Web routes. API routes exempt (JWT-immune).
- **JWT production validation**: Empty/default `JWT_SECRET` in `prod` profile fails fast.
- **Bcrypt hashing**: `User.password` field privatized; verification only via `BcryptHasher.verify`.
- **`fetch_github_avatar` hardening**: 5s connect timeout + 3 retries with exponential backoff; failure does not block registration.

### Added — Transactions

- `@[transactional]` annotation on `PostService.create_post`/`update_post`/`delete_post`, `CommentService.create_comment`, `UserService.register` for atomic multi-step operations.

### Added — CLI

- **Code generators** (`make:*`): `make:controller`, `make:model`, `make:migration`, `make:middleware`, `make:provider`, `make:command`, `make:resource`, `make:seeder`, `make:factory`, `make:entity` — all with stub generation.
- **Migration lifecycle commands**: `migrate:fresh` (drop all + re-migrate), `migrate:refresh` (rollback + re-migrate), `migrate:reset` (rollback all), all with `--seed` flag support.
- **`DocsCommand`**: Static API doc generation (`--format=markdown|html`) from route annotations.
- **`ServeCommand`**: Actually starts the veb server (removed empty stub); `--port`/`--host` flags honored.
- **`QueueWorkCommand`**: Fixed control flow — `worker.run()` blocks; removed redundant `for worker.is_running() { worker.tick() }` loop.
- **`SchedulerRunCommand`**: Graceful shutdown on SIGINT/SIGTERM.
- All commands now declare `sig` signatures for `--help` output.

### Added — API Documentation

- **`apidoc` integration**: Runtime API doc collector with interactive dashboard at `/__docs`, static assets at `/__docs/static/:file`, JSON entries at `/__docs/api/entries`, and OpenAPI 3.0 export at `/__docs/api/export`.
- Production safety: `apidoc` handler disabled in `prod` profile.

### Added — Make Toolkit

- Full lifecycle Makefile with categorized targets:
  - **Environment**: `setup`, `install`, `uninstall`
  - **Development**: `dev` (watch), `run`, `serve`, `watch`
  - **Build**: `build`, `build-release`, `release`, `release-package`
  - **Testing**: `test`, `test-unit`, `test-integration`, `test-coverage`
  - **Database**: `migrate`, `migrate-rollback`, `migrate-refresh`, `migrate-fresh`, `migrate-reset`, `migrate-status`, `seed`, `seed-fresh`, `db-shell`
  - **Runtime**: `queue-work`, `queue-restart`, `scheduler-run`, `routes`, `stats`
  - **Quality**: `lint`, `fmt`, `check`
  - **Container**: `docker`, `docker-up`, `docker-down`, `docker-logs`
  - **Cleanup**: `clean`, `clean-all`, `distclean`
  - **Helpers**: `logs`, `shell`, `benchmark`, `docs`
  - **Code generation**: 10 `make-*` aliases for `make:*` commands
  - `help` target auto-generated from `##` comments.

### Added — Containerization

- `docker-compose.yml` with `app`, `db`, `redis`, `queue`, `scheduler` services, healthchecks, and volume mounts.
- `docker-compose.prod.yml` production override with resource limits, restart policies, and log drivers.
- Multi-stage `Dockerfile` with non-root user and healthcheck.

### Added — Documentation

- Rewritten [README.md](README.md) with features, quick start, configuration, API reference, architecture diagram (Mermaid), CLI commands, Make targets, deployment, and testing.
- [docs/architecture.md](docs/architecture.md) — 1200+ line architecture document covering request lifecycle, DI container, service provider lifecycle, data flow, middleware chain, caching/locking strategy, event-driven architecture, security architecture, database layer, API Resource pattern, design decisions, and module dependency graph (9 Mermaid diagrams).
- [CONTRIBUTING.md](CONTRIBUTING.md) — development setup, code standards, commit conventions, PR process, testing requirements.
- [CHANGELOG.md](CHANGELOG.md) — this file.
- [LICENSE](LICENSE) — MIT.
- [.editorconfig](.editorconfig) — V language editor configuration.

### Changed

- `main.v` rewritten as thin entry point: load `.env` → `load_config(profile)` → `new_app_kernel(cfg)` → `kernel.bootstrap()` → register middleware groups → register routes → CLI/Web dispatch.
- `bootstrap.v` rewritten as thin wrapper delegating to `bootstrap/app.v` AppKernel.
- `controllers.v` — all `ok_resp`/`err_resp` replaced with `web.success`/`web.fail`/`web.page`; all `json.encode(entity)` replaced with `XxxResource(entity).to_json()`; all inline validation replaced with `web.validate_body[T]`.
- `repositories.v` — all repositories extend `orm.EagerRepository[T]`; manual row mapping removed.
- `services.v` — manual `if cm.has(key)` cache logic replaced with `cache.get_or_load()` + Singleflight; manual `lock`/`unlock` replaced with `LockGuard`.
- `App.req_count` race condition fixed via `sync.atomic`.
- `MiddlewareManager` removed; middleware orchestration moved to `MiddlewareGroupRegistry`.

### Removed

- `ApiResponseDto`, `success_response`, `error_response` dead code from `models.v`.
- 7 `build_*_dto` form fallback functions (framework validator handles JSON/form uniformly).
- `parse_body_or_form` dual-path parsing.
- All hand-crafted JSON string concatenation (`'{"success":...}'`) in controllers.
- All inline validation (`if dto.x.len == 0`) in controllers.
- `unsafe { voidptr(x) }` type erasure in DI.
- Hardcoded role hierarchy in `bootstrap.v`.

### Fixed

- Cache corruption silently returning empty entities on `json.decode` failure.
- `App.req_count` data race under concurrent requests.
- `QueueWorkCommand` hanging due to redundant polling loop after blocking `worker.run()`.
- `fetch_github_avatar` blocking registration on network failure (now non-blocking with timeout + retry).
- CSRF blocking first POST request before any GET issued a cookie (now skips validation when expected token is empty).

---

## [0.1.0] - 2026-01-01

### Added

- Initial PhotonBlog demo: flat structure with basic CRUD for users, posts, comments, categories, tags.
- JWT authentication, in-memory caching, SQLite database, veb server.
- Basic CLI with `serve`, `migrate`, `seed` commands.

---

[Unreleased]: https://github.com/photon/demo/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/photon/demo/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/photon/demo/releases/tag/v0.1.0
