# ═══════════════════════════════════════════════════════════
# PhotonBlog Demo — 全生命周期构建脚本
# ═══════════════════════════════════════════════════════════
#
# 用法：
#   make help        — 查看所有可用目标
#   make setup       — 一键初始化（编译 + 迁移 + 种子）
#   make dev         — 开发模式（热重载）
#   make release     — 生产构建
#
# 环境变量：
#   PROFILE          — 环境配置 (dev|prod|test，默认 dev)
#   PORT             — 服务端口 (默认从 .env 读取)
#   SERVICE          — docker-logs 时过滤的服务名
# ═══════════════════════════════════════════════════════════

# ── 变量定义 ──
V          ?= v
VFLAGS     := -enable-globals
VFLAGS_DEV := -enable-globals
VFLAGS_REL := -enable-globals -d release -cflags "-O2"
BIN        := demo
BIN_DIR    := bin
DB_PATH    ?= photonblog.db
PROFILE    ?= dev
PORT       ?= 8080
HOST       ?= 0.0.0.0
SERVICE    ?=

# V only compiles .v files in the given directory, NOT sub-directories.
# Demo uses a Laravel-style directory layout (app/, config/, bootstrap/, …)
# where every .v file declares `module main`.  We flatten them into a
# single build directory so `v run` sees everything.
BUILD_DIR  := .build

# ── 跨平台检测 (macOS / Linux) ──
# 优先使用 docker compose（Docker v2+），回退到 docker-compose（v1）
DOCKER_COMPOSE := $(shell command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1 && echo "docker compose" || echo "docker-compose")

# 操作系统检测：darwin (macOS) / linux
UNAME_S := $(shell uname -s)

# 文件监听工具选择：
#   macOS:  fswatch (brew install fswatch)
#   Linux:  inotifywait (apt install inotify-tools)
ifeq ($(UNAME_S),Darwin)
    WATCHER       := fswatch
    WATCHER_FLAGS := -r --exclude='\.git' --exclude='\.db' --exclude='storage' --exclude='bin' --exclude='dist' .
    WATCHER_CHECK := command -v fswatch >/dev/null 2>&1 || { echo "✗ macOS 需要 fswatch: brew install fswatch"; exit 1; }
else
    WATCHER       := inotifywait
    WATCHER_FLAGS := -r -e modify,create,delete,move --exclude '\.git|\.db|storage|bin|dist' .
    WATCHER_CHECK := command -v inotifywait >/dev/null 2>&1 || { echo "✗ Linux 需要 inotifywait: apt install inotify-tools"; exit 1; }
endif

# ── 默认目标 ──
.DEFAULT_GOAL := help

# ═══════════════════════════════════════════════════════════
# 环境初始化
# ═══════════════════════════════════════════════════════════

.PHONY: setup install uninstall flatten

# ── Flatten: collect all `module main` .v files into .build/ ──
# V's `v run <dir>` only compiles .v files directly in <dir>, not in
# sub-directories.  Demo uses a Laravel-style layout where every .v
# file is `module main` but lives in app/, config/, bootstrap/, etc.
# The `flatten` target COPIES them all into .build/ so V sees them.
# We use cp (not symlinks) because V's watch mode on macOS does not
# reliably follow symlinks.
flatten:
	@rm -rf $(BUILD_DIR)
	@mkdir -p $(BUILD_DIR)/.vmodules
	@for f in $$(find . -name '*.v' \
		-not -path './.vmodules/*' \
		-not -path './.build/*' \
		-not -path './docs/*' \
		-not -path './.git/*' \
		-not -path './storage/*' \
		-not -path './bin/*' \
		-not -path './dist/*' \
		-not -name '*_test.v'); do \
		base=$$(basename $$f); \
		if [ "$$base" = "v.mod" ]; then continue; fi; \
		dir=$$(dirname $$f); \
		if [ "$$dir" = "." ]; then \
			dest=$(BUILD_DIR)/$$base; \
		else \
			prefix=$$(echo $$dir | sed 's|^\./||;s|/|__|g'); \
			dest=$(BUILD_DIR)/$${prefix}__$$base; \
		fi; \
		cp "$$f" "$$dest"; \
	done
	@cp v.mod $(BUILD_DIR)/v.mod
	@# Make photon vmodule resolvable — copy only module dirs (not examples/tests/docs)
	@PHOTON_ROOT=$$(cd .. && pwd); \
	mkdir -p $(BUILD_DIR)/.vmodules/photon; \
	cp $(BUILD_DIR)/.vmodules/photon 2>/dev/null; \
	for d in photon.v v.mod core config log cache orm pool lock web cli security apidoc logger; do \
		if [ -e "$$PHOTON_ROOT/$$d" ]; then \
			cp -R "$$PHOTON_ROOT/$$d" $(BUILD_DIR)/.vmodules/photon/; \
		fi; \
	done; \
	mkdir -p $(HOME)/.vmodules; \
	ln -sfn "$$PHOTON_ROOT" $(HOME)/.vmodules/photon
	@# Verify
	@test -d $(BUILD_DIR)/.vmodules/photon/apidoc || { echo "ERROR: photon vmodule not resolvable"; exit 1; }

## 环境初始化: 一键搭建开发环境
setup: check-v env build migrate seed
	@echo ""
	@echo "✓ PhotonBlog 开发环境初始化完成！"
	@echo "  执行 'make dev' 启动开发服务器"
	@echo "  执行 'make help' 查看所有命令"

## 检查 V 编译器
check-v:
	@command -v $(V) >/dev/null 2>&1 || { echo "✗ 未找到 V 编译器，请先安装: https://vlang.io"; exit 1; }
	@echo "✓ V 编译器: $$($(V) version)"

## 环境自检 (macOS/Linux)
doctor:
	@echo "=== PhotonBlog 环境自检 ==="
	@echo "操作系统: $(UNAME_S)"
	@command -v $(V) >/dev/null 2>&1 && echo "✓ V 编译器: $$($(V) version)" || echo "✗ V 编译器未安装"
	@command -v sqlite3 >/dev/null 2>&1 && echo "✓ sqlite3: $$(sqlite3 --version)" || echo "⚠ sqlite3 未安装 (可选)"
	@command -v make >/dev/null 2>&1 && echo "✓ make: $$(make --version | head -1)" || echo "✗ make 未安装"
	@command -v $(WATCHER) >/dev/null 2>&1 && echo "✓ 文件监听器: $(WATCHER)" || echo "⚠ 文件监听器 $(WATCHER) 未安装 (make watch 需要)"
	@command -v $(DOCKER_COMPOSE) >/dev/null 2>&1 && echo "✓ 容器编排: $(DOCKER_COMPOSE)" || echo "⚠ Docker Compose 未安装 (可选)"
	@command -v curl >/dev/null 2>&1 && echo "✓ curl: $$(curl --version | head -1)" || echo "⚠ curl 未安装"
	@echo "═══════════════════════════"

## 创建 .env 文件（若不存在）
env:
	@if [ ! -f .env ]; then cp .env.example .env; echo "✓ 已从模板创建 .env 文件"; fi

## 安装二进制到系统路径
install: build-release
	@echo "安装 $(BIN) 到 /usr/local/bin/"
	@cp $(BIN_DIR)/$(BIN) /usr/local/bin/$(BIN)
	@chmod +x /usr/local/bin/$(BIN)
	@echo "✓ 安装完成，可全局执行: $(BIN)"

## 卸载系统二进制
uninstall:
	@rm -f /usr/local/bin/$(BIN)
	@echo "✓ 已卸载 $(BIN)"

# ═══════════════════════════════════════════════════════════
# 开发
# ═══════════════════════════════════════════════════════════

.PHONY: dev run serve watch

## 开发模式: 热重载监听文件变更
# 自动检测 V 编译器版本：
#   - V 0.5.x: 使用原生 watch（`v watch run . -- args`）
#   - 旧版 V / 语法不兼容: 回退到 `make watch`（fswatch/inotifywait 跨平台回退）
dev: flatten
	@echo "启动开发模式（热重载）..."
	@if $(V) watch --help 2>&1 | grep -q "run"; then \
		echo "✓ 使用 V 0.5.x 原生 watch..."; \
		$(V) $(VFLAGS_DEV) watch run $(BUILD_DIR) -- serve --host=$(HOST) --port=$(PORT); \
	else \
		echo "⚠ V 版本不支持 watch run，回退到 $(WATCHER) 监听..."; \
		$(MAKE) watch HOST=$(HOST) PORT=$(PORT); \
	fi

## 编译并运行服务器
run: build
	./$(BIN) serve --host=$(HOST) --port=$(PORT)

## 启动服务器（别名）
serve: run

## 文件监听重启（跨平台：macOS=fswatch, Linux=inotifywait）
# 启动服务器后，源码变更时自动重建并重启。
# 需要先安装对应工具：macOS `brew install fswatch`；Linux `apt install inotify-tools`
watch:
	@echo "监听文件变更并重启 [$(UNAME_S)/$(WATCHER)]..."
	$(WATCHER_CHECK)
	@while true; do \
		$(V) $(VFLAGS_DEV) $(BUILD_DIR) && \
		./$(BIN) serve --host=$(HOST) --port=$(PORT) & \
		SERVER_PID=$$!; \
		$(WATCHER) $(WATCHER_FLAGS) >/dev/null 2>&1; \
		kill $$SERVER_PID 2>/dev/null; \
		wait $$SERVER_PID 2>/dev/null; \
		sleep 1; \
		echo "↻ 检测到文件变更，重新构建..."; \
	done

# ═══════════════════════════════════════════════════════════
# 构建
# ═══════════════════════════════════════════════════════════

.PHONY: build build-release release release-package

## Debug 构建
build: flatten
	@echo "编译 (debug)..."
	$(V) $(VFLAGS) -o $(BIN) $(BUILD_DIR)
	@echo "✓ 编译完成: ./$(BIN)"

## 生产优化构建
build-release: flatten
	@echo "编译 (release)..."
	@mkdir -p $(BIN_DIR)
	$(V) $(VFLAGS_REL) -o $(BIN_DIR)/$(BIN) $(BUILD_DIR)
	@echo "✓ 生产构建完成: $(BIN_DIR)/$(BIN)"

## 生产构建（别名）
release: build-release

## 打包发布 tarball
release-package: build-release
	@echo "打包发布..."
	@mkdir -p dist
	@tar -czf dist/$(BIN)-release-$$(date +%Y%m%d%H%M%S).tar.gz \
		$(BIN_DIR)/$(BIN) \
		config/ \
		.env.example \
		.env.prod.example \
		database/migrations/ \
		database/seeders/ \
		README.md
	@echo "✓ 发布包已生成到 dist/"

# ═══════════════════════════════════════════════════════════
# 测试
# ═══════════════════════════════════════════════════════════

.PHONY: test test-unit test-integration test-coverage

## 运行全部测试
test:
	@echo "运行测试..."
	$(V) $(VFLAGS) test $(SRC_DIR)

## 运行单元测试
test-unit:
	@echo "运行单元测试..."
	$(V) $(VFLAGS) test $(SRC_DIR) -run '.*_test\.v$$' || \
	$(V) $(VFLAGS) test $(SRC_DIR)

## 运行集成测试
test-integration:
	@echo "运行集成测试..."
	$(V) $(VFLAGS) test $(SRC_DIR) || true

## 生成测试覆盖率报告
test-coverage:
	@echo "生成测试覆盖率报告..."
	@$(V) $(VFLAGS) test $(SRC_DIR) 2>&1 | tee coverage.txt
	@echo "✓ 覆盖率报告已保存到 coverage.txt"

# ═══════════════════════════════════════════════════════════
# 数据库
# ═══════════════════════════════════════════════════════════

.PHONY: migrate migrate-rollback migrate-refresh migrate-fresh migrate-fresh-seed migrate-reset migrate-status seed seed-fresh db-shell

## 执行数据库迁移
migrate: build
	./$(BIN) migrate

## 回滚最后一次迁移
migrate-rollback: build
	./$(BIN) migrate:rollback

## 回滚并重新迁移（通过 down 方法回滚，保留迁移历史）
migrate-refresh: build
	./$(BIN) migrate:refresh
	@echo "✓ 迁移已刷新"

## 重置数据库（drop 所有表 + 重新迁移）
migrate-fresh: build
	@echo "重置数据库..."
	./$(BIN) migrate:fresh

## 重置数据库并插入种子数据（一键初始化）
migrate-fresh-seed: build
	@echo "重置数据库并插入种子数据..."
	./$(BIN) migrate:fresh --seed
	@echo "✓ 数据库已重置并插入种子数据"

## 回滚所有迁移
migrate-reset: build
	./$(BIN) migrate:reset

## 查看迁移状态
migrate-status: build
	./$(BIN) migrate:status

## 插入种子数据
seed: build
	./$(BIN) seed

## 重置并插入种子数据
seed-fresh: migrate-fresh seed
	@echo "✓ 数据库已重置并插入种子数据"

## 数据库 CLI
db-shell:
	@echo "打开 SQLite CLI ($(DB_PATH))..."
	@sqlite3 $(DB_PATH) || echo "✗ 需要安装 sqlite3"

# ═══════════════════════════════════════════════════════════
# 运行时
# ═══════════════════════════════════════════════════════════

.PHONY: queue-work queue-restart scheduler-run routes stats

## 启动队列 Worker
queue-work: build
	./$(BIN) queue:work

## 重启队列 Worker
queue-restart: build
	./$(BIN) queue:restart || echo "队列重启信号已发送"

## 启动定时调度器
scheduler-run: build
	./$(BIN) scheduler:run

## 打印路由表
routes: build
	./$(BIN) routes

## 输出服务器统计
stats: build
	./$(BIN) stats

# ═══════════════════════════════════════════════════════════
# 代码质量
# ═══════════════════════════════════════════════════════════

.PHONY: lint fmt check vet

## 代码静态检查
lint:
	@echo "运行静态检查..."
	$(V) vet $(SRC_DIR) 2>&1 || true

## 格式化代码
fmt:
	@echo "格式化代码..."
	$(V) fmt -w $(SRC_DIR)
	@echo "✓ 代码格式化完成"

## 综合检查（lint + fmt + test）
check: lint fmt test
	@echo "✓ 所有检查通过"

## 别名: vet
vet: lint

# ═══════════════════════════════════════════════════════════
# 容器化
# ═══════════════════════════════════════════════════════════

.PHONY: docker docker-up docker-down docker-logs docker-build docker-shell

## 构建 Docker 镜像
docker:
	@echo "构建 Docker 镜像..."
	docker build -t photonblog -f Dockerfile ..

## 构建镜像（别名）
docker-build: docker

## 启动全部服务（docker-compose up -d）
docker-up:
	@echo "启动 Docker Compose 服务..."
	$(DOCKER_COMPOSE) up -d
	@echo "✓ 服务已启动，访问 http://localhost:8080"
	@echo "  查看日志: make docker-logs"
	@echo "  停止服务: make docker-down"

## 停止全部服务
docker-down:
	@echo "停止 Docker Compose 服务..."
	$(DOCKER_COMPOSE) down
	@echo "✓ 服务已停止"

## 查看服务日志（SERVICE=app 过滤特定服务）
docker-logs:
	@if [ -z "$(SERVICE)" ]; then \
		$(DOCKER_COMPOSE) logs -f --tail=100; \
	else \
		$(DOCKER_COMPOSE) logs -f --tail=100 $(SERVICE); \
	fi

## 进入容器 shell
docker-shell:
	@$(DOCKER_COMPOSE) exec app /bin/sh

# ═══════════════════════════════════════════════════════════
# 清理
# ═══════════════════════════════════════════════════════════

.PHONY: clean clean-all distclean

## 清理构建产物
clean:
	@echo "清理构建产物..."
	@rm -f $(BIN)
	@rm -rf $(BIN_DIR)/$(BIN)
	@rm -rf $(BUILD_DIR)
	@rm -f *.db *.db-journal *.db-wal *.db-shm
	@echo "✓ 清理完成"

## 深度清理（含日志、上传、文档生成物）
clean-all: clean
	@echo "深度清理..."
	@rm -rf storage/logs/*.log
	@rm -rf storage/uploads/*
	@rm -rf docs/api/*
	@rm -rf dist/
	@rm -f coverage.txt
	@echo "✓ 深度清理完成"

## 彻底清理（别名）
distclean: clean-all

# ═══════════════════════════════════════════════════════════
# 辅助
# ═══════════════════════════════════════════════════════════

.PHONY: logs shell benchmark bench docs help

## 查看应用日志
logs:
	@tail -f storage/logs/app.log || echo "✗ 日志文件不存在"

## 应用 shell
shell:
	@echo "PhotonBlog Shell (输入 'exit' 退出)"
	@./$(BIN) shell || /bin/sh

## 性能基准测试
benchmark: build
	@echo "运行性能基准..."
	@./$(BIN) benchmark || echo "基准测试完成"

## 别名: bench
bench: benchmark

## 生成 API 文档
docs: build
	@echo "生成 API 文档..."
	./$(BIN) docs
	@echo "✓ API 文档已生成到 docs/api/"

# ═══════════════════════════════════════════════════════════
# 代码生成（make:* 命令的 Make 别名）
# ═══════════════════════════════════════════════════════════

.PHONY: make-controller make-model make-migration make-middleware make-provider make-command make-resource make-seeder make-factory make-entity

## 生成控制器（make:controller）
make-controller: build
	@test -n "$(NAME)" || (echo "用法: make make-controller NAME=PostController" && exit 1)
	./$(BIN) make:controller $(NAME)

## 生成模型（make:model，含实体 + 仓储）
make-model: build
	@test -n "$(NAME)" || (echo "用法: make make-model NAME=Post" && exit 1)
	./$(BIN) make:model $(NAME)

## 生成迁移文件（make:migration）
make-migration: build
	@test -n "$(NAME)" || (echo "用法: make make-migration NAME=create_posts_table" && exit 1)
	./$(BIN) make:migration $(NAME)

## 生成中间件（make:middleware）
make-middleware: build
	@test -n "$(NAME)" || (echo "用法: make make-middleware NAME=AuthMiddleware" && exit 1)
	./$(BIN) make:middleware $(NAME)

## 生成服务提供者（make:provider）
make-provider: build
	@test -n "$(NAME)" || (echo "用法: make make-provider NAME=CacheServiceProvider" && exit 1)
	./$(BIN) make:provider $(NAME)

## 生成 CLI 命令（make:command）
make-command: build
	@test -n "$(NAME)" || (echo "用法: make make-command NAME=SendEmailCommand" && exit 1)
	./$(BIN) make:command $(NAME)

## 生成 API Resource（make:resource）
make-resource: build
	@test -n "$(NAME)" || (echo "用法: make make-resource NAME=PostResource" && exit 1)
	./$(BIN) make:resource $(NAME)

## 生成 Seeder（make:seeder）
make-seeder: build
	@test -n "$(NAME)" || (echo "用法: make make-seeder NAME=PostSeeder" && exit 1)
	./$(BIN) make:seeder $(NAME)

## 生成 Factory（make:factory）
make-factory: build
	@test -n "$(NAME)" || (echo "用法: make make-factory NAME=PostFactory" && exit 1)
	./$(BIN) make:factory $(NAME)

## 生成实体（make:entity）
make-entity: build
	@test -n "$(NAME)" || (echo "用法: make make-entity NAME=Post" && exit 1)
	./$(BIN) make:entity $(NAME)

## 显示帮助信息
help:
	@echo "╔══════════════════════════════════════════════════════════════╗"
	@echo "║              PhotonBlog Demo — 构建命令手册                  ║"
	@echo "╚══════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "环境初始化:"
	@awk '/^## 环境初始化/{f=1;next}/^## /{f=0}f && /^[a-zA-Z_-]+:/{split($$0,a,":");printf "  \033[36m%-20s\033[0m %s\n",a[1],desc} /^[a-zA-Z_-]+:.*##/{split($$0,a,":");split(a[2],b,"##");printf "  \033[36m%-20s\033[0m %s\n",a[1],b[2]}' Makefile 2>/dev/null || true
	@echo ""
	@echo "开发:"
	@awk '/^## 开发:/{f=1;next}/^## /{f=0}f && /^[a-zA-Z_-]+:/{split($$0,a,":");printf "  \033[36m%-20s\033[0m %s\n",a[1],desc} /^[a-zA-Z_-]+:.*##/{split($$0,a,":");split(a[2],b,"##");printf "  \033[36m%-20s\033[0m %s\n",a[1],b[2]}' Makefile 2>/dev/null || true
	@echo ""
	@echo "构建:"
	@awk '/^## 构建:/{f=1;next}/^## /{f=0}f && /^[a-zA-Z_-]+:/{split($$0,a,":");printf "  \033[36m%-20s\033[0m %s\n",a[1],desc} /^[a-zA-Z_-]+:.*##/{split($$0,a,":");split(a[2],b,"##");printf "  \033[36m%-20s\033[0m %s\n",a[1],b[2]}' Makefile 2>/dev/null || true
	@echo ""
	@echo "测试:"
	@awk '/^## 测试:/{f=1;next}/^## /{f=0}f && /^[a-zA-Z_-]+:/{split($$0,a,":");printf "  \033[36m%-20s\033[0m %s\n",a[1],desc} /^[a-zA-Z_-]+:.*##/{split($$0,a,":");split(a[2],b,"##");printf "  \033[36m%-20s\033[0m %s\n",a[1],b[2]}' Makefile 2>/dev/null || true
	@echo ""
	@echo "数据库:"
	@awk '/^## 数据库:/{f=1;next}/^## /{f=0}f && /^[a-zA-Z_-]+:/{split($\0,a,":");printf "  \033[36m%-20s\033[0m %s\n",a[1],desc} /^[a-zA-Z_-]+:.*##/{split($$0,a,":");split(a[2],b,"##");printf "  \033[36m%-20s\033[0m %s\n",a[1],b[2]}' Makefile 2>/dev/null || true
	@echo ""
	@echo "运行时:"
	@awk '/^## 运行时:/{f=1;next}/^## /{f=0}f && /^[a-zA-Z_-]+:/{split($$0,a,":");printf "  \033[36m%-20s\033[0m %s\n",a[1],desc} /^[a-zA-Z_-]+:.*##/{split($$0,a,":");split(a[2],b,"##");printf "  \033[36m%-20s\033[0m %s\n",a[1],b[2]}' Makefile 2>/dev/null || true
	@echo ""
	@echo "代码质量:"
	@awk '/^## 代码质量:/{f=1;next}/^## /{f=0}f && /^[a-zA-Z_-]+:/{split($$0,a,":");printf "  \033[36m%-20s\033[0m %s\n",a[1],desc} /^[a-zA-Z_-]+:.*##/{split($$0,a,":");split(a[2],b,"##");printf "  \033[36m%-20s\033[0m %s\n",a[1],b[2]}' Makefile 2>/dev/null || true
	@echo ""
	@echo "容器化:"
	@awk '/^## 容器化:/{f=1;next}/^## /{f=0}f && /^[a-zA-Z_-]+:/{split($$0,a,":");printf "  \033[36m%-20s\033[0m %s\n",a[1],desc} /^[a-zA-Z_-]+:.*##/{split($$0,a,":");split(a[2],b,"##");printf "  \033[36m%-20s\033[0m %s\n",a[1],b[2]}' Makefile 2>/dev/null || true
	@echo ""
	@echo "清理:"
	@awk '/^## 清理:/{f=1;next}/^## /{f=0}f && /^[a-zA-Z_-]+:/{split($$0,a,":");printf "  \033[36m%-20s\033[0m %s\n",a[1],desc} /^[a-zA-Z_-]+:.*##/{split($$0,a,":");split(a[2],b,"##");printf "  \033[36m%-20s\033[0m %s\n",a[1],b[2]}' Makefile 2>/dev/null || true
	@echo ""
	@echo "代码生成 (需 NAME= 参数):"
	@awk '/^## 生成/{f=1;next}/^## /{f=0}f && /^[a-zA-Z_-]+:/{split($$0,a,":");printf "  \033[36m%-20s\033[0m %s\n",a[1],desc} /^[a-zA-Z_-]+:.*##/{split($$0,a,":");split(a[2],b,"##");printf "  \033[36m%-20s\033[0m %s\n",a[1],b[2]}' Makefile 2>/dev/null || true
	@echo ""
	@echo "辅助:"
	@awk '/^## 辅助:/{f=1;next}/^## /{f=0}f && /^[a-zA-Z_-]+:/{split($$0,a,":");printf "  \033[36m%-20s\033[0m %s\n",a[1],desc} /^[a-zA-Z_-]+:.*##/{split($$0,a,":");split(a[2],b,"##");printf "  \033[36m%-20s\033[0m %s\n",a[1],b[2]}' Makefile 2>/dev/null || true
	@echo ""
	@echo "环境变量:"
	@echo "  PROFILE=prod        设置环境配置 (dev|prod|test)"
	@echo "  PORT=9090           设置服务端口"
	@echo "  HOST=127.0.0.1      设置监听地址"
	@echo "  SERVICE=app         docker-logs 过滤服务名"
	@echo ""
	@echo "快速开始:"
	@echo "  make setup    # 一键初始化"
	@echo "  make dev      # 开发模式"
	@echo "  make test     # 运行测试"
	@echo "  make help     # 查看此帮助"
