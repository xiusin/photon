# photon/Makefile — Photon Framework Build & Test Automation
#
# Run from project root:     make -f photon/Makefile test
# Run from photon/ dir:       cd photon && make test
#
# Targets:
#   make build     - Compile the full server example
#   make run       - Compile and run the full server example
#   make test      - Run specific ORM test files
#   make test-all  - Run all Photon module tests
#   make check     - Typecheck all modules (no test execution)
#   make clean     - Remove build artifacts

# ── V Compiler flags ──
VFLAGS := -enable-globals

# Locate a usable `v` binary. We prefer PATH, then a few well-known install
# locations, then fall back to whatever V points at. CI sandboxes and Mac/Linux
# dev boxes both end up with a working V via this search.
V       ?= $(shell command -v v 2>/dev/null)
V       ?= $(shell test -x /usr/local/bin/v && echo /usr/local/bin/v)
V       ?= $(shell test -x /opt/homebrew/bin/v && echo /opt/homebrew/bin/v)
V       ?= $(shell test -x $$HOME/v/v && echo $$HOME/v/v)
V       ?= $(shell test -x $$V && echo $$V)
V       ?= $(error "Could not find 'v' compiler. Install V or set $$V in your environment.")

# Detect if we're inside photon/ directory (no photon/ prefix needed)
ROOT_PREFIX := $(if $(wildcard photon.v),,photon/)

# ── Module directories ──
MODULES := $(ROOT_PREFIX)config/ $(ROOT_PREFIX)logger/ $(ROOT_PREFIX)security/ $(ROOT_PREFIX)cli/ $(ROOT_PREFIX)web/ $(ROOT_PREFIX)orm/ $(ROOT_PREFIX)http/ $(ROOT_PREFIX)queue/ $(ROOT_PREFIX)support/ $(ROOT_PREFIX)ticker/ $(ROOT_PREFIX)cache/ $(ROOT_PREFIX)pool/ $(ROOT_PREFIX)locking/ $(ROOT_PREFIX)async/
EXAMPLE := $(ROOT_PREFIX)example/

# ── ORM test files ──
# v test only accepts folders or *_test.v files; non-test helpers (like
# orm/query_test.v) are listed under TEST_HELPERS for typecheck only.
ORM_TESTS := $(ROOT_PREFIX)orm/orm_test.v \
             $(ROOT_PREFIX)orm/entity_test.v \
             $(ROOT_PREFIX)orm/derive_test.v \
             $(ROOT_PREFIX)orm/transaction_test.v \
             $(ROOT_PREFIX)orm/relation_test.v \
             $(ROOT_PREFIX)orm/migration_test.v \
             $(ROOT_PREFIX)orm/adapter_test.v \
             $(ROOT_PREFIX)orm/transaction_annotation_test.v \
             $(ROOT_PREFIX)orm/repository_test.v

# ── Targets ──

.PHONY: build run test test-all check clean help docs-serve doctor link-vmodules unlink-vmodules

help:
	@echo "Photon Framework Build & Test"
	@echo ""
	@echo "  make doctor         - Self-check: env + link + compile every module"
	@echo "  make link-vmodules  - Create ~/.vmodules/photon -> \$$PWD"
	@echo "  make unlink-vmodules - Remove the global vmodule symlink"
	@echo "  make dev            - link-vmodules + run the example server"
	@echo "  make build     - Compile the full server example"
	@echo "  make run       - Compile and run the full server example"
	@echo "  make test      - Run ORM test files (fast smoke test)"
	@echo "  make test-all  - Run all module tests"
	@echo "  make check     - Typecheck all modules + example"
	@echo "  make service       - Build production binary for systemd deployment"
	@echo "  make install-service - Build and install as systemd service (sudo)"
	@echo "  make uninstall-service - Remove from systemd"
	@echo "  make docker       - Build Docker image"
	@echo "  make docker-run   - Build and run Docker container"
	@echo "  make docker-push  - Push to container registry"
	@echo "  make clean         - Remove build artifacts"
	@echo "  make docs-serve    - Start documentation server (port 8765)"

build:
	@mkdir -p $(ROOT_PREFIX)bin
	$(V) $(VFLAGS) -o $(ROOT_PREFIX)bin/photon-example $(EXAMPLE)
	@echo "Binary: $(ROOT_PREFIX)bin/photon-example"

run:
	$(V) $(VFLAGS) run $(EXAMPLE)

test:
	$(V) $(VFLAGS) test $(ORM_TESTS)

test-all:
	@echo "Running all module tests..."
	@total=0; pass=0; fail=0; \
	for dir in $(MODULES); do \
		if [ -d "$$dir" ]; then \
			if $(V) $(VFLAGS) test "$$dir" >/dev/null 2>&1; then \
				echo "  [OK]   $$dir"; \
				pass=$$((pass+1)); \
			else \
				echo "  [FAIL] $$dir"; \
				fail=$$((fail+1)); \
			fi; \
			total=$$((total+1)); \
		fi; \
	done; \
	echo "-----------------------------------"; \
	echo "Total: $$total modules | Passed: $$pass | Failed: $$fail"

check:
	@for dir in $(MODULES); do \
		printf "Check %-25s ... " "$$dir"; \
		$(V) $(VFLAGS) -shared -o /dev/null "$$dir" >/dev/null 2>&1 && echo "OK" || echo "FAIL"; \
	done
	@printf "Check %-25s ... " "$(EXAMPLE)"
	@$(V) $(VFLAGS) -o $(ROOT_PREFIX)bin/_check_tmp $(EXAMPLE) >/dev/null 2>&1 && echo "OK ($(ROOT_PREFIX)bin/_check_tmp)" || echo "FAIL"
	@rm -f $(ROOT_PREFIX)bin/_check_tmp

clean:
	rm -rf $(ROOT_PREFIX)bin/
	@echo "Cleaned build artifacts."

# ── Developer environment ──
#
# V resolves imports by walking: project/.vmodules → ~/.vmodules → $VAPATH/vlib.
# `v .` in a downstream project therefore needs the photon module to be visible
# either via that project's .vmodules/photon symlink, or via ~/.vmodules/photon.
# `make link-vmodules` creates the global one (Mac & Linux) so `make doctor`
# and `make dev` Just Work on a fresh checkout.

VMODULES_DIR := $(HOME)/.vmodules
PHOTON_LINK  := $(VMODULES_DIR)/photon

link-vmodules:
	@mkdir -p $(VMODULES_DIR)
	@if [ -L $(PHOTON_LINK) ] && [ "$$(readlink -f $(PHOTON_LINK) 2>/dev/null || readlink $(PHOTON_LINK))" = "$(CURDIR)" ]; then \
		echo "  [OK]  $(PHOTON_LINK) -> $(CURDIR)"; \
	else \
		ln -sfn $(CURDIR) $(PHOTON_LINK); \
		echo "  [NEW] $(PHOTON_LINK) -> $(CURDIR)"; \
	fi

unlink-vmodules:
	@rm -f $(PHOTON_LINK)
	@echo "  [RM]  $(PHOTON_LINK)"

# `make doctor` is a one-shot self-check: prints environment, ensures the vmodule
# link is in place, and compiles every module + the bundled example. Exits 0 only
# when every step passes — safe to wire into CI.
doctor: link-vmodules
	@echo "─── Photon doctor ───"
	@printf "V compiler:    "; $(V) -V 2>/dev/null | head -1
	@printf "OS:            "; uname -s
	@printf "C compiler:    "; $${CC:-cc} --version 2>/dev/null | head -1
	@printf "photon path:   "; pwd
	@echo
	@echo "Per-module typecheck:"
	@rm -f /tmp/photon-doctor.fail
	@for dir in $(MODULES); do \
		if [ -d "$$dir" ]; then \
			printf "  %-22s ... " "$$dir"; \
			if $(V) $(VFLAGS) -shared -o /dev/null "$$dir" >/dev/null 2>&1; then \
				echo "OK"; \
			else \
				echo "FAIL"; touch /tmp/photon-doctor.fail; \
			fi; \
		fi; \
	done
	@printf "  %-22s ... " "$(EXAMPLE)"
	@if $(V) $(VFLAGS) -o /dev/null $(EXAMPLE) >/dev/null 2>&1; then echo "OK"; else echo "FAIL"; touch /tmp/photon-doctor.fail; fi
	@echo
	@if [ ! -f /tmp/photon-doctor.fail ]; then \
		echo "doctor: PASS ✓"; \
		rm -f /tmp/photon-doctor.fail; \
	else \
		echo "doctor: FAIL ✗"; \
		rm -f /tmp/photon-doctor.fail; \
		exit 1; \
	fi

# Push the global vmodule link into the current project as well — useful when
# you want to test a downstream consumer without modifying its .vmodules/.
dev: link-vmodules
	$(V) $(VFLAGS) run $(EXAMPLE)

# ── Documentation Server ──

docs-serve:
	$(V) run $(ROOT_PREFIX)docs/serve.v

# ── Linux Service Deployment ──

SERVICE_NAME := photon
SERVICE_FILE := $(ROOT_PREFIX)systemd/$(SERVICE_NAME).service
INSTALL_DIR  := /opt/photon
SYSTEMD_DIR  := /etc/systemd/system

# Build a production binary suitable for systemd deployment
service:
	@echo "Building production binary..."
	$(V) $(VFLAGS) -prod -o $(ROOT_PREFIX)bin/$(SERVICE_NAME) $(EXAMPLE)
	@echo "Binary: $(ROOT_PREFIX)bin/$(SERVICE_NAME)"

# Install as a systemd service (requires root)
install-service: service
	@echo "Installing Photon service..."
	@mkdir -p $(INSTALL_DIR)/data $(INSTALL_DIR)/logs
	cp $(ROOT_PREFIX)bin/$(SERVICE_NAME) $(INSTALL_DIR)/app
	cp $(SERVICE_FILE) $(SYSTEMD_DIR)/$(SERVICE_NAME).service
	chmod +x $(INSTALL_DIR)/app
	systemctl daemon-reload
	@echo ""
	@echo "Service installed. Commands:"
	@echo "  sudo systemctl enable $(SERVICE_NAME)   # auto-start on boot"
	@echo "  sudo systemctl start $(SERVICE_NAME)    # start now"
	@echo "  sudo systemctl status $(SERVICE_NAME)   # check status"
	@echo "  sudo journalctl -u $(SERVICE_NAME) -f   # tail logs"

# Uninstall the service (requires root)
uninstall-service:
	-systemctl stop $(SERVICE_NAME)
	-systemctl disable $(SERVICE_NAME)
	rm -f $(SYSTEMD_DIR)/$(SERVICE_NAME).service
	systemctl daemon-reload
	@echo "Service uninstalled."

# ── Docker / Container ──

DOCKER_IMAGE := photon-app
DOCKER_REGISTRY ?= ghcr.io/xiusin

# Build the Docker image locally
docker:
	@echo "Building Docker image..."
	docker build -t $(DOCKER_IMAGE):latest -f $(ROOT_PREFIX)Dockerfile $(ROOT_PREFIX)..

# Run the Docker image locally on port 8080
docker-run: docker
	@echo "Running Docker container on http://localhost:8080"
	docker run --rm -p 8080:8080 $(DOCKER_IMAGE):latest

# Push the Docker image to a registry
docker-push: docker
	@echo "Tagging and pushing Docker image..."
	docker tag $(DOCKER_IMAGE):latest $(DOCKER_REGISTRY)/$(DOCKER_IMAGE):latest
	docker push $(DOCKER_REGISTRY)/$(DOCKER_IMAGE):latest