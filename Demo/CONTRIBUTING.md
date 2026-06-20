# Contributing to PhotonBlog

First off, thank you for taking the time to contribute! PhotonBlog is a skeleton project for the [Photon Framework](../), and contributions that improve its quality as a reference implementation are warmly welcome.

This document describes the development workflow, code standards, commit conventions, and pull request process. By participating, you agree to abide by the [Code of Conduct](#code-of-conduct).

---

## Table of Contents

- [Development Environment Setup](#development-environment-setup)
- [Project Structure](#project-structure)
- [Code Standards](#code-standards)
- [Commit Convention](#commit-convention)
- [Pull Request Process](#pull-request-process)
- [Testing Requirements](#testing-requirements)
- [Issue Reporting](#issue-reporting)
- [Code of Conduct](#code-of-conduct)

---

## Development Environment Setup

### Prerequisites

- **V language** compiler >= 0.4.x (recommended 0.5.x). Install from [vlang.io](https://vlang.io/).
- **Make** (GNU Make or compatible)
- **Git** >= 2.20
- **Docker** and **Docker Compose** (optional, for containerized development)
- **sqlite3** CLI (optional, for `make db-shell`)

### Setup Steps

```bash
# 1. Clone the repository (Photon Framework + Demo)
git clone <your-fork-url>
cd photon/Demo

# 2. Copy environment file
cp .env.example .env

# 3. One-command setup: build + migrate + seed
make setup

# 4. Start development server with hot reload
make dev
```

### Verify Your Setup

```bash
make check      # lint + fmt + test
curl http://localhost:8080/health
```

If `make check` passes and the health endpoint returns `200 OK`, your environment is ready.

---

## Project Structure

```
Demo/
├── app/                          # Application layer
│   └── Http/
│       ├── Kernel.v              # HTTP kernel: exception handler registry
│       ├── Middleware/           # Middleware group registry
│       └── Resources/            # API Resource transformers (Laravel-style)
├── bootstrap/                    # Bootstrap layer
│   ├── app.v                     # AppKernel: provider registration + lifecycle
│   └── console.v                 # Console banners and route table printing
├── config/                       # Per-concern configuration files
│   ├── app.v                     # AppConfig
│   ├── database.v                # DatabaseConfig
│   ├── jwt.v                     # JwtConfig
│   ├── cache.v                   # CacheConfig
│   ├── mail.v                    # MailConfig
│   ├── storage.v                 # StorageConfig
│   ├── logging.v                 # LoggingConfig
│   ├── web.v                     # WebConfig (CORS, rate limit, middleware groups)
│   └── auth.v                    # AuthConfig (role hierarchy)
├── database/
│   ├── migrations/               # Timestamped migration files
│   ├── seeders/                  # Database seeders
│   └── factories/                # Model factories
├── providers/                    # ServiceProviders (Laravel-style)
│   ├── app_service_provider.v
│   ├── database_service_provider.v
│   ├── cache_service_provider.v
│   ├── web_service_provider.v
│   ├── auth_service_provider.v
│   ├── queue_service_provider.v
│   ├── event_service_provider.v
│   ├── repository_service_provider.v
│   ├── service_service_provider.v
│   └── boot_context.v            # Type-safe shared mutable state container
├── routes/
│   ├── api.v                     # API routes (/api/v1/*)
│   └── web.v                     # Web routes (/, /health, /ping, /stats)
├── docs/
│   └── architecture.md           # Architecture document
├── Makefile                      # Full lifecycle Make targets
├── Dockerfile                    # Multi-stage container build
├── docker-compose.yml            # Multi-service orchestration
├── main.v                        # Application entry point
├── app.v                         # App struct (veb server)
├── controllers.v                 # HTTP controllers
├── services.v                    # Business services
├── repositories.v                # Data access layer
├── models.v                      # Entities and DTOs
├── middleware.v                  # Middleware implementations
├── commands.v                    # CLI command definitions
├── helpers.v                     # Utility functions
└── *_test.v                      # Test files (co-located)
```

---

## Code Standards

### V Language Style

PhotonBlog follows the [V language official style guide](https://github.com/vlang/v/blob/master/doc/docs.md#style-guide). Key rules:

1. **Indentation**: Use **tabs**, not spaces. Configure your editor via [`.editorconfig`](.editorconfig).
2. **Naming**:
   - Files and variables: `snake_case` (e.g., `user_service.v`, `user_repo`)
   - Structs and traits: `PascalCase` (e.g., `UserService`, `UserRepository`)
   - Constants: `snake_case` (e.g., `default_page_size`)
3. **Public symbols** must be marked with `pub`. Internal helpers should omit `pub`.
4. **Error handling**: Use V's `!` error propagation and `or` blocks. Do not swallow errors silently.
5. **No runtime reflection**: All annotations are processed at compile time via `comptime $for`.

### Formatting

Always run the formatter before committing:

```bash
make fmt        # Runs `v fmt -w .`
```

### Linting

```bash
make lint       # Runs `v vet`
```

Fix all lint warnings before opening a PR.

### Architecture Conventions

- **Layered architecture**: Controllers → Services → Repositories → ORM. Do not skip layers (e.g., controllers must not call repositories directly).
- **Dependency Injection**: Use `@[autowired]` field injection. Do not instantiate dependencies with `&Foo{}` inside services.
- **ServiceProvider pattern**: All framework integrations go through a ServiceProvider's `register()` + `boot()` lifecycle. Do not bootstrap framework components ad-hoc in `main.v`.
- **API Resources**: All HTTP responses must go through a Resource transformer. Never `json.encode(entity)` directly in a controller.
- **Unified response**: Use `web.success` / `web.fail` / `web.page` / `web.created`. Never hand-craft JSON strings.
- **Configuration**: Read config from `config/*.v` files via `BootContext`. Do not hardcode values.

### Comments

- Use `//` for single-line comments explaining non-obvious logic.
- Use `/* ... */` for multi-line documentation blocks.
- Comment in **Chinese + English** for user-facing error messages (per framework convention).
- Do not add redundant comments that restate what the code already says.

---

## Commit Convention

PhotonBlog follows [Conventional Commits](https://www.conventionalcommits.org/) 1.0.0.

### Format

```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types

| Type       | Description                                                  |
|------------|--------------------------------------------------------------|
| `feat`     | A new feature                                                |
| `fix`      | A bug fix                                                    |
| `docs`     | Documentation only changes                                   |
| `style`    | Changes that do not affect the meaning of the code (formatting, etc.) |
| `refactor` | A code change that neither fixes a bug nor adds a feature   |
| `perf`     | A code change that improves performance                      |
| `test`     | Adding missing tests or correcting existing tests            |
| `build`    | Changes that affect the build system or dependencies         |
| `ci`       | Changes to CI configuration files and scripts                |
| `chore`    | Other changes that don't modify src or test files            |
| `revert`   | Reverts a previous commit                                    |

### Scopes

Common scopes for this project: `controller`, `service`, `repository`, `middleware`, `provider`, `config`, `migration`, `seeder`, `factory`, `resource`, `cli`, `make`, `docker`, `docs`, `test`.

### Examples

```
feat(controller): add POST /api/v1/posts/{id}/publish endpoint

fix(cache): flush 'posts' tag on post update to prevent stale reads

docs(architecture): add middleware chain sequence diagram

test(repository): add soft delete restore and force_delete tests

refactor(service): replace manual lock/unlock with LockGuard RAII

chore(make): add make-factory target alias
```

### Subject Rules

- Use the imperative, present tense: "add" not "added" / "adds".
- Do not capitalize the first letter.
- No period at the end.
- Maximum 72 characters.

### Body

- Explain **why** the change is made, not **what** (the diff shows what).
- Wrap at 72 characters.
- Reference issues: `Closes #123`, `Refs #456`.

---

## Pull Request Process

1. **Fork** the repository and create your branch from `main`:
   ```bash
   git checkout -b feat/your-feature
   ```

2. **Write code** following the [Code Standards](#code-standards).

3. **Add tests** for new features or bug fixes. See [Testing Requirements](#testing-requirements).

4. **Run checks locally**:
   ```bash
   make check      # lint + fmt + test
   ```
   All checks must pass.

5. **Commit** using [Conventional Commits](#commit-convention).

6. **Push** and open a Pull Request against `main`.

7. **PR description** must include:
   - **Summary**: What does this PR do and why?
   - **Breaking changes**: If any, list them and migration steps.
   - **Testing**: How did you verify the change? Which tests were added/updated?
   - **Checklist**:
     - [ ] `make check` passes
     - [ ] Tests added/updated for new behavior
     - [ ] Documentation updated (README, architecture.md, CHANGELOG if applicable)
     - [ ] No new lint warnings
     - [ ] No `unsafe { voidptr(x) }` type erasure introduced
     - [ ] No hand-crafted JSON strings in controllers
     - [ ] No hardcoded config values (use `config/*.v`)

8. **Code review**: At least one maintainer approval is required. Address review feedback by pushing new commits (do not force-push during review unless asked).

9. **Squash merge**: PRs are squash-merged. Ensure your commit history is clean before merge.

---

## Testing Requirements

### Test File Location

Test files are **co-located** with source files and named `<feature>_test.v`:

```
services.v          # source
services_test.v     # tests (or service_test.v)
```

### Test Style

- Use V's built-in `assert` statement.
- Each test function name starts with `test_`.
- One test function per behavior; group related assertions.
- Use factories for test data: `UserFactory.new().with_role('admin').create()`.
- Use `RefreshDatabase` trait to ensure a clean database per test (see [tests/test_case.v](tests/test_case.v)).

### Test Coverage

- New features must include tests.
- Bug fixes must include a regression test.
- Aim for meaningful coverage of business logic, not 100% line coverage of getters/setters.

### Running Tests

```bash
make test                # All tests
make test-unit           # Unit tests only (*_test.v except integration_test.v)
make test-integration    # Integration tests only
make test-coverage       # Coverage report
```

---

## Issue Reporting

Before opening a new issue, please:

1. **Search** existing issues to avoid duplicates.
2. **Verify** the issue reproduces on the latest `main` branch.
3. **Provide**:
   - V compiler version (`v version`)
   - Operating system
   - Minimal reproduction steps
   - Expected vs. actual behavior
   - Relevant logs (use `LOG_LEVEL=debug` if helpful)

Use issue templates if available. Label the issue appropriately (`bug`, `feature`, `question`, `documentation`).

---

## Code of Conduct

Be respectful and constructive. Personal attacks, harassment, and discrimination are not tolerated. Focus on the code and the problem, not the person. Disagreements are natural — discuss them calmly and back up opinions with evidence.

---

Thank you for contributing to PhotonBlog!
