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

# Detect if we're inside photon/ directory (no photon/ prefix needed)
ROOT_PREFIX := $(if $(wildcard photon.v),,photon/)

# ── Module directories ──
MODULES := $(ROOT_PREFIX)config/ $(ROOT_PREFIX)logger/ $(ROOT_PREFIX)security/ $(ROOT_PREFIX)cli/ $(ROOT_PREFIX)web/ $(ROOT_PREFIX)orm/ $(ROOT_PREFIX)http/ $(ROOT_PREFIX)queue/ $(ROOT_PREFIX)support/ $(ROOT_PREFIX)ticker/ $(ROOT_PREFIX)cache/ $(ROOT_PREFIX)pool/ $(ROOT_PREFIX)locking/
EXAMPLE := $(ROOT_PREFIX)example/

# ── ORM test files ──
ORM_TESTS := $(ROOT_PREFIX)orm/orm_test.v \
             $(ROOT_PREFIX)orm/entity_test.v \
             $(ROOT_PREFIX)orm/query_test.v \
             $(ROOT_PREFIX)orm/derive_test.v \
             $(ROOT_PREFIX)orm/transaction_test.v

# ── Targets ──

.PHONY: build run test test-all check clean help

help:
	@echo "Photon Framework Build & Test"
	@echo ""
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

build:
	@mkdir -p $(ROOT_PREFIX)bin
	v $(VFLAGS) -o $(ROOT_PREFIX)bin/photon-example $(EXAMPLE)
	@echo "Binary: $(ROOT_PREFIX)bin/photon-example"

run:
	v $(VFLAGS) run $(EXAMPLE)

test:
	v $(VFLAGS) test $(ORM_TESTS)

test-all:
	@echo "Running all module tests..."
	@total=0; pass=0; fail=0; \
	for dir in $(MODULES); do \
		if [ -d "$$dir" ]; then \
			if v $(VFLAGS) test "$$dir" >/dev/null 2>&1; then \
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
		v $(VFLAGS) -shared -o /dev/null "$$dir" >/dev/null 2>&1 && echo "OK" || echo "FAIL"; \
	done
	@printf "Check %-25s ... " "$(EXAMPLE)"
	@v $(VFLAGS) -o $(ROOT_PREFIX)bin/_check_tmp $(EXAMPLE) >/dev/null 2>&1 && echo "OK ($(ROOT_PREFIX)bin/_check_tmp)" || echo "FAIL"
	@rm -f $(ROOT_PREFIX)bin/_check_tmp

clean:
	rm -rf $(ROOT_PREFIX)bin/
	@echo "Cleaned build artifacts."

# ── Linux Service Deployment ──

SERVICE_NAME := photon
SERVICE_FILE := $(ROOT_PREFIX)systemd/$(SERVICE_NAME).service
INSTALL_DIR  := /opt/photon
SYSTEMD_DIR  := /etc/systemd/system

# Build a production binary suitable for systemd deployment
service:
	@echo "Building production binary..."
	v $(VFLAGS) -prod -o $(ROOT_PREFIX)bin/$(SERVICE_NAME) $(EXAMPLE)
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