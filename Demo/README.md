# PhotonBlog

> A complete blog/CMS API service built with [Photon Framework](../) — the enterprise-grade V language framework inspired by Spring Boot.

PhotonBlog demonstrates the full capabilities of Photon Framework across all 16 modules: core DI, web routing, ORM, security/JWT, caching, locking, queue, mailer, storage, scheduler, and more. It is designed as a reference implementation for building production-grade V language applications.

---

## Features

- **Authentication & Authorization** — JWT-based auth with role hierarchy (ADMIN > EDITOR > USER)
- **Blog Content Management** — Posts, categories, tags, and nested comments with full CRUD
- **File Uploads** — Avatar and image uploads with size/type validation
- **Caching** — Memory cache with tag-based invalidation for hot data
- **Database Migrations** — Versioned schema migrations with rollback support
- **Event-Driven Architecture** — Domain events (user.registered, post.published, comment.posted) with async listeners
- **Background Jobs** — Queue-based email delivery and statistics aggregation
- **Scheduled Tasks** — Cron-style periodic jobs (stats aggregation, cache warmup, cleanup)
- **Rate Limiting** — IP-based sliding window rate limiting (60 req/min)
- **Structured Logging** — Level-based logging with request ID tracing
- **API Documentation** — Auto-generated API docs via apidoc module
- **CLI Commands** — serve, migrate, seed, queue:work, scheduler:run, stats, routes

---

## Quick Start

### Prerequisites

- [V language](https://vlang.io/) compiler (>= 0.4.x, recommended 0.5.x)
- Photon Framework (located at `../` relative to this directory)

### Build & Run

```bash
# 1. Build the binary
make build

# 2. Run database migrations
./demo migrate

# 3. (Optional) Seed sample data
./demo seed

# 4. Start the server
make serve
# or: ./demo serve
```

The server starts on `http://0.0.0.0:8080` (dev profile by default).

### Verify

```bash
curl http://localhost:8080/health
curl http://localhost:8080/ping
```

---

## Configuration

PhotonBlog supports three profiles: **dev** (default), **prod**, and **test**.

| Profile | Debug | Log Level | Database       | Port |
|---------|-------|-----------|----------------|------|
| dev     | true  | debug     | SQLite :memory:| 8080 |
| prod    | false | info      | SQLite file    | 80   |
| test    | true  | error     | SQLite :memory:| 0    |

### Environment Variable Overrides

All `APP_*` prefixed environment variables override config values:

| Env Var                        | Config Key                  |
|--------------------------------|-----------------------------|
| `APP_PROFILE`                  | profile                     |
| `APP_DEBUG`                    | app.debug                   |
| `APP_LOG_LEVEL`                | log.level                   |
| `APP_SERVER_HOST`              | server.host                 |
| `APP_SERVER_PORT`              | server.port                 |
| `APP_DATABASE_PATH`            | database.path               |
| `APP_JWT_SECRET`               | jwt.secret                  |
| `APP_CACHE_TTL`                | cache.ttl                   |
| `APP_MAIL_DRIVER`              | mail.driver                 |
| `APP_STORAGE_BASE_PATH`        | storage.base_path           |

Example:

```bash
APP_PROFILE=prod APP_SERVER_PORT=3000 APP_JWT_SECRET=my-secret ./demo serve
```

---

## API Endpoints

### System

| Method | Path             | Auth | Description         |
|--------|------------------|------|---------------------|
| GET    | `/`              | -    | API info            |
| GET    | `/health`        | -    | Health check        |
| GET    | `/ping`          | -    | Connectivity test   |
| GET    | `/stats`         | -    | Server statistics   |

### Auth

| Method | Path                          | Auth | Description          |
|--------|-------------------------------|------|----------------------|
| POST   | `/api/v1/auth/register`       | -    | User registration    |
| POST   | `/api/v1/auth/login`          | -    | Login (returns JWT)  |
| POST   | `/api/v1/auth/refresh`        | JWT  | Refresh token        |
| GET    | `/api/v1/auth/profile`        | JWT  | Current user profile |
| POST   | `/api/v1/auth/logout`         | JWT  | Logout               |

### Users (ADMIN)

| Method | Path                   | Auth  | Description       |
|--------|------------------------|-------|-------------------|
| GET    | `/api/v1/users`        | ADMIN | List users (paged)|
| GET    | `/api/v1/users/:id`    | ADMIN | User detail       |
| POST   | `/api/v1/users`        | ADMIN | Create user       |
| PUT    | `/api/v1/users/:id`    | ADMIN | Update user       |
| DELETE | `/api/v1/users/:id`    | ADMIN | Delete user       |

### Posts

| Method | Path                          | Auth     | Description           |
|--------|-------------------------------|----------|-----------------------|
| GET    | `/api/v1/posts`               | -        | List posts (paged)    |
| GET    | `/api/v1/posts/:id`           | -        | Post detail           |
| POST   | `/api/v1/posts`               | EDITOR+  | Create post           |
| PUT    | `/api/v1/posts/:id`           | EDITOR+  | Update post           |
| DELETE | `/api/v1/posts/:id`           | ADMIN    | Delete post           |

### Comments

| Method | Path                                  | Auth    | Description           |
|--------|---------------------------------------|---------|-----------------------|
| GET    | `/api/v1/posts/:id/comments`          | -       | List comments         |
| POST   | `/api/v1/posts/:id/comments`          | USER+   | Create comment        |
| DELETE | `/api/v1/comments/:id`                | ADMIN/Owner | Delete comment    |

### Categories & Tags

| Method | Path                        | Auth     | Description       |
|--------|-----------------------------|----------|-------------------|
| GET    | `/api/v1/categories`        | -        | List categories   |
| POST   | `/api/v1/categories`        | ADMIN    | Create category   |
| GET    | `/api/v1/tags`              | -        | List tags         |
| POST   | `/api/v1/tags`              | EDITOR+  | Create tag        |

### File Uploads

| Method | Path                        | Auth     | Description          |
|--------|-----------------------------|----------|----------------------|
| POST   | `/api/v1/uploads/avatar`    | USER+    | Upload avatar (2MB)  |
| POST   | `/api/v1/uploads/image`     | EDITOR+  | Upload image (5MB)   |
| GET    | `/api/v1/uploads/:file`     | -        | Access uploaded file |

---

## Architecture

```
PhotonBlog/
├── v.mod              # Module definition (module main)
├── config.v           # Configuration system (AppConfig + load_config)
├── bootstrap.v        # Application bootstrap (DI container assembly)
├── app.v              # veb App struct + Context + main()
├── models.v           # Entity definitions (User, Post, Comment, Category, Tag)
├── database.v         # Database connection + migrations
├── repositories.v     # Repository layer (BaseRepository + OrmAdapter)
├── services.v         # Business logic services
├── events.v           # Domain events + listeners
├── jobs.v             # Queue jobs (email, stats, cleanup)
├── middleware.v       # Middleware chain (CORS, Auth, RateLimit, etc.)
├── controllers.v      # HTTP controllers (all endpoints)
├── commands.v         # CLI commands (serve, migrate, seed, etc.)
├── scheduler.v        # Scheduled task registration
├── Makefile           # Build automation
├── Dockerfile         # Multi-stage container build
└── README.md          # This file
```

### Module Coverage

PhotonBlog integrates all 16 Photon Framework modules:

| Module    | Usage in PhotonBlog                                    |
|-----------|--------------------------------------------------------|
| core      | ApplicationContext, Bean registration, EventBus        |
| config    | Multi-source config (Map + Env), profile-based loading |
| log       | Structured logging with levels and request ID tracing  |
| cache     | Memory cache for posts, stats, hot data                |
| orm       | Entity mapping, repositories, migrations, transactions|
| pool      | Database connection pooling                            |
| lock      | Distributed locks for concurrent post updates         |
| web       | veb routing, middleware chain, validation, uploads     |
| security  | JWT auth, Bcrypt hashing, role hierarchy, CSRF         |
| http      | HTTP client (GitHub avatar fetch integration)          |
| mailer    | Welcome emails, comment notifications (SMTP/Log)       |
| storage   | Local file storage for uploads                         |
| queue     | Background jobs (email, stats aggregation)             |
| ticker    | Scheduled tasks (cron-style periodic jobs)             |
| cli       | CLI command system (serve, migrate, seed, etc.)        |
| support   | Pagination, collections, sorting utilities             |

---

## Deployment

### Docker

```bash
# Build image (from photon root directory)
docker build -t photonblog -f Demo/Dockerfile .

# Run container
docker run -d --name photonblog \
  -p 8080:8080 \
  -e APP_PROFILE=prod \
  -e APP_JWT_SECRET=your-production-secret \
  photonblog
```

### CLI Commands

```bash
./demo serve           # Start HTTP server
./demo migrate         # Run database migrations
./demo migrate:rollback # Rollback last migration
./demo migrate:status  # Show migration status
./demo seed            # Seed sample data
./demo queue:work      # Start queue worker
./demo scheduler:run   # Start scheduler
./demo stats           # Print statistics
./demo routes          # Print route table
```

---

## Development

### Running Tests

```bash
make test
# or: v -enable-globals test .
```

### Project Conventions

- **V Style**: `snake_case` for files/variables, `PascalCase` for structs/traits
- **Compile Flag**: All builds use `-enable-globals`
- **No Hardcoding**: All configurable values read from config system
- **Error Handling**: V's `!` error propagation with `or` blocks

---

## License

MIT — Part of the Photon Framework project.
