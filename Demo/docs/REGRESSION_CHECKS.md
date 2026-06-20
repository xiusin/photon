# Regression Test Checklist — PhotonBlog 0.2.0

This document provides manual verification steps for the PhotonBlog skeleton upgrade.
Each section corresponds to a Task 25 subtask in the spec. Run these checks in order
before declaring a release candidate.

> Note: The V compiler is required for the automated `v test` and `make check` commands.
> If V is not installed, verify the file structure and code patterns manually.

---

## Pre-flight: Environment

```bash
# V compiler ≥ 0.4.x required
v version

# Working directory
cd /workspace/Demo

# Verify .env exists
ls -la .env

# Verify framework dependency
ls /workspace/v.mod
```

---

## SubTask 25.1 — `make setup` (Build + Migrate + Seed)

```bash
cd /workspace/Demo
make setup
```

**Expected**:
- Build succeeds (binary at `bin/demo`)
- All 6 migrations run
- Seeders populate 1 ADMIN + 2 EDITOR + 5 USER + 10 posts + 20 comments
- Exit code 0

**Failure modes**:
- Missing `.env` → copy from `.env.example`
- SQLite lock → delete `*.db` and retry
- V version too old → upgrade to 0.5.x

---

## SubTask 25.2 — `make dev` (Hot Reload)

```bash
cd /workspace/Demo
make dev
```

**Expected**:
- veb server starts on port 8080
- Hot reload active (`v -enable-globals watch`)
- No syntax errors on startup

**Smoke test**:
```bash
curl http://localhost:8080/health
# Expected: 200 OK
```

---

## SubTask 25.3 — `make build` and `make release`

```bash
make build           # Debug build
make release         # Optimized release build
file bin/demo        # Verify ELF/Mach-O
ls -la bin/demo      # Check size (debug > release)
```

**Expected**:
- Both builds succeed
- Release binary is 30-50% smaller than debug
- Release binary runs in production mode (no debug logs)

---

## SubTask 25.4 — `make test`

```bash
make test-unit
```

**Expected**:
- All unit tests pass
- Test count: ~250+ (depends on new test files)

**New test files added in 0.2.0**:
- `tests/test_case.v` (TestCase base)
- `tests/refresh_database.v` (RefreshDatabase trait)
- `tests/validation_test.v` (~30 tests)
- `tests/exception_test.v` (~25 tests)
- `tests/soft_delete_test.v` (~15 tests)
- `tests/eager_loading_test.v` (~12 tests)
- `tests/factory_test.v` (~20 tests)
- `auth_test.v` (5 new TestCase demos)

**Integration tests**:
```bash
make test-integration
```

---

## SubTask 25.5 — `make migrate-fresh && make seed`

```bash
make migrate-fresh
make seed
```

**Expected**:
- All tables dropped and recreated
- Seed data inserted (idempotent)
- Database has expected counts

**Verification**:
```bash
sqlite3 storage/database/demo.db "SELECT COUNT(*) FROM users;"
# Expected: 8 (1 ADMIN + 2 EDITOR + 5 USER)
sqlite3 storage/database/demo.db "SELECT COUNT(*) FROM posts;"
# Expected: 10
sqlite3 storage/database/demo.db "SELECT COUNT(*) FROM comments;"
# Expected: 20
```

---

## SubTask 25.6 — `make docker-up`

```bash
make docker
make docker-up
# Wait ~10 seconds for healthcheck
make docker-logs service=app
```

**Expected**:
- `app` service healthcheck returns 200 within 30s
- `queue` and `scheduler` services start after `app` is healthy
- Volume mounts work (logs visible in `storage/logs/`)

**Smoke test**:
```bash
curl http://localhost:8080/health
# Expected: 200 OK
```

---

## SubTask 25.7 — `make docs`

```bash
make docs
ls docs/api/
```

**Expected**:
- `docs/api/index.html` exists
- `docs/api/openapi.json` exists
- Dashboard at `/__docs` returns 200 (when not in prod)

---

## SubTask 25.8 — `make help`

```bash
make help
```

**Expected**:
- Categorized help list (Environment / Development / Build / Testing / Database / Runtime / Quality / Container / Cleanup / Helpers)
- All targets documented with `##` comments

---

## SubTask 25.9 — API Endpoint Regression

All 29 API endpoints (curl tests):

```bash
BASE=http://localhost:8080

# Auth
curl $BASE/api/v1/auth/register -X POST -H 'Content-Type: application/json' -d '{"username":"test","email":"test@x.com","password":"secret123"}'
# → 201

# Login → get token
TOKEN=$(curl -s $BASE/api/v1/auth/login -X POST -H 'Content-Type: application/json' -d '{"username":"test","password":"secret123"}' | jq -r .data.access_token)

# Users
curl $BASE/api/v1/users -H "Authorization: Bearer $TOKEN"   # → 200
curl $BASE/api/v1/users/1 -H "Authorization: Bearer $TOKEN" # → 200
curl $BASE/api/v1/users/1 -X PUT -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"nickname":"Updated"}' # → 200
curl $BASE/api/v1/users/2 -X DELETE -H "Authorization: Bearer $TOKEN" # → 200

# Posts
curl $BASE/api/v1/posts                                  # → 200
curl $BASE/api/v1/posts/1                                # → 200
curl $BASE/api/v1/posts -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"title":"Test","content":"Body","author_id":1}' # → 201
curl $BASE/api/v1/posts/1 -X PUT -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"title":"Updated"}' # → 200
curl $BASE/api/v1/posts/1 -X DELETE -H "Authorization: Bearer $TOKEN" # → 200
curl $BASE/api/v1/posts/1/publish -X POST -H "Authorization: Bearer $TOKEN" # → 200

# Comments
curl $BASE/api/v1/comments -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"post_id":1,"user_id":1,"content":"Nice"}' # → 201
curl $BASE/api/v1/comments/1 -X PUT -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"content":"Updated"}' # → 200
curl $BASE/api/v1/comments/1 -X DELETE -H "Authorization: Bearer $TOKEN" # → 200

# Categories
curl $BASE/api/v1/categories
curl $BASE/api/v1/categories -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"name":"Tech","slug":"tech"}'
curl $BASE/api/v1/categories/1 -X PUT -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"name":"Tech Updated"}'
curl $BASE/api/v1/categories/2 -X DELETE -H "Authorization: Bearer $TOKEN"

# Tags
curl $BASE/api/v1/tags
curl $BASE/api/v1/tags -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"name":"vlang","slug":"vlang"}'
curl $BASE/api/v1/tags/1 -X DELETE -H "Authorization: Bearer $TOKEN"

# Uploads
curl $BASE/api/v1/uploads/avatar -X POST -H "Authorization: Bearer $TOKEN" -F "file=@/path/to/image.png" # → 200
curl $BASE/api/v1/uploads/image -X POST -H "Authorization: Bearer $TOKEN" -F "file=@/path/to/image.png" # → 200
```

**Web routes**:
```bash
curl $BASE/            # → 200 (HTML or redirect)
curl $BASE/health      # → 200 OK
curl $BASE/ping        # → 200 "pong"
curl $BASE/stats       # → 200 (JSON)
```

**API Docs**:
```bash
curl $BASE/__docs                              # → 200 (dev only)
curl $BASE/__docs/api/entries                  # → 200 JSON
curl $BASE/__docs/api/export                   # → 200 OpenAPI 3.0 JSON
```

---

## SubTask 25.10 — CLI Command Regression

```bash
./bin/demo --help                          # → Help output
./bin/demo serve --port=8080               # → Start server (in background)
./bin/demo migrate                         # → Run pending migrations
./bin/demo migrate:status                  # → Migration status
./bin/demo migrate:rollback                # → Rollback last
./bin/demo migrate:fresh                   # → Drop all + re-migrate
./bin/demo migrate:refresh                 # → Rollback all + re-migrate
./bin/demo migrate:fresh --seed            # → Fresh + seed
./bin/demo seed                            # → Run all seeders
./bin/demo queue:work                      # → Start worker (in background)
./bin/demo scheduler:run                   # → Run scheduler (Ctrl+C to stop)
./bin/demo stats                           # → Print stats
./bin/demo routes                          # → Print all routes
./bin/demo docs --format=markdown          # → Generate API docs
./bin/demo docs --format=html              # → Generate HTML docs
./bin/demo make:controller PostController  # → Generate controller
./bin/demo make:model Post --table=posts   # → Generate model
./bin/demo make:migration create_likes    # → Generate migration
./bin/demo make:middleware Auth            # → Generate middleware
./bin/demo make:provider Custom            # → Generate provider
./bin/demo make:command CustomCommand      # → Generate command
./bin/demo make:resource PostResource      # → Generate resource
./bin/demo make:seeder PostSeeder          # → Generate seeder
./bin/demo make:factory PostFactory        # → Generate factory
./bin/demo make:entity Post                # → Generate entity
```

**Expected**: All commands execute successfully and produce expected output.

---

## SubTask 25.11 — Production JWT Secret Validation

```bash
APP_PROFILE=prod JWT_SECRET= ./bin/demo serve
```

**Expected**: Process exits with error: `"JWT_SECRET is required in production profile / 生产环境必须配置 JWT_SECRET"`

**Pass criteria**: Server does NOT start.

```bash
# Test default secret
APP_PROFILE=prod JWT_SECRET=changeme ./bin/demo serve
# Expected: Same error (default secret rejected)
```

---

## SubTask 25.12 — Password Field Not Leaked

```bash
TOKEN=$(curl -s $BASE/api/v1/auth/login -X POST -H 'Content-Type: application/json' -d '{"username":"admin","password":"admin123"}' | jq -r .data.access_token)
RESPONSE=$(curl -s $BASE/api/v1/users -H "Authorization: Bearer $TOKEN")
echo "$RESPONSE" | jq .data[0]
```

**Expected**: User object contains `id`, `username`, `email`, `nickname`, `role`, but **NOT** `password` or `version`.

```bash
# Negative assertion
echo "$RESPONSE" | grep -q '"password"'
# Expected: exit code 1 (not found)
```

---

## SubTask 25.13 — No `unsafe { voidptr(x) }` Type Erasure in DI

```bash
grep -rn "voidptr" /workspace/Demo/*.v
```

**Expected**: No matches in DI-related files (bootstrap, providers, services).

**Acceptable matches** (compile-time FFI / interface conversion):
- `unsafe { ... }` in HttpKernel for `http.Status(code)` cast
- `unsafe { ... }` in veb for Context conversion
- `unsafe { nil }` for optional struct field defaults

---

## SubTask 25.14 — No Hand-crafted JSON Strings

```bash
grep -rn "'{\"success" /workspace/Demo/*.v
grep -rn "'{\"code" /workspace/Demo/*.v
grep -rn "json.encode.*\"success" /workspace/Demo/*.v
```

**Expected**: No matches in `controllers.v`. All responses use `web.success` / `web.fail` / `web.page` / `send_result` helpers.

---

## SubTask 25.15 — No Inline Validation Residue

```bash
grep -rn "if dto.*\.len == 0" /workspace/Demo/controllers.v
grep -rn "if.*dto.*empty" /workspace/Demo/controllers.v
```

**Expected**: No matches. All validation uses `web.validate_body[T]` / `ctx.validate_json_or_422[T]()`.

---

## SubTask 25.16 — Documentation Files Exist

```bash
ls /workspace/Demo/README.md
ls /workspace/Demo/CONTRIBUTING.md
ls /workspace/Demo/CHANGELOG.md
ls /workspace/Demo/LICENSE
ls /workspace/Demo/.editorconfig
ls /workspace/Demo/docs/architecture.md
```

**Expected**: All files exist with non-zero size.

---

## SubTask 25.17 — Test Files Exist

```bash
ls /workspace/Demo/tests/
```

**Expected**:
- `test_case.v` (TestCase base class)
- `refresh_database.v` (RefreshDatabase trait)
- `validation_test.v`
- `exception_test.v`
- `soft_delete_test.v`
- `eager_loading_test.v`
- `factory_test.v`

---

## SubTask 25.18 — Service Provider Coverage

```bash
ls /workspace/Demo/providers/
```

**Expected**: 9 ServiceProviders + 1 BootContext:
- `app_service_provider.v`
- `database_service_provider.v`
- `cache_service_provider.v`
- `web_service_provider.v`
- `auth_service_provider.v`
- `queue_service_provider.v`
- `event_service_provider.v`
- `repository_service_provider.v`
- `service_service_provider.v`
- `boot_context.v`

---

## SubTask 25.19 — Config File Coverage

```bash
ls /workspace/Demo/config/
```

**Expected**: 9 config files:
- `app.v`, `auth.v`, `cache.v`, `database.v`, `jwt.v`, `logging.v`, `mail.v`, `storage.v`, `web.v`

---

## SubTask 25.20 — Make Target Coverage

```bash
cd /workspace/Demo
grep -E "^[a-z-]+:" Makefile | head -40
make help
```

**Expected**: All categories populated (Environment / Development / Build / Testing / Database / Runtime / Quality / Container / Cleanup / Helpers / Code Generation).

---

## Sign-off

When all 20 sections pass:

```
[ ] All sections pass
[ ] No compiler errors
[ ] No test failures
[ ] Production JWT validation works
[ ] Password field not leaked
[ ] Documentation complete
[ ] Sign-off: ____________________  Date: __________
```

---

## Appendix: Quick One-Liner Regression

```bash
cd /workspace/Demo && \
  make build && \
  make test-unit 2>&1 | tail -5 && \
  APP_PROFILE=prod JWT_SECRET= ./bin/demo serve 2>&1 | grep -q "JWT_SECRET" && \
  echo "REGRESSION PASS"
```
