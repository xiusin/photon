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
MODULES := $(ROOT_PREFIX)core/ $(ROOT_PREFIX)config/ $(ROOT_PREFIX)log/ $(ROOT_PREFIX)security/ $(ROOT_PREFIX)cli/ $(ROOT_PREFIX)web/ $(ROOT_PREFIX)orm/ $(ROOT_PREFIX)http/ $(ROOT_PREFIX)queue/ $(ROOT_PREFIX)support/ $(ROOT_PREFIX)ticker/ $(ROOT_PREFIX)cache/ $(ROOT_PREFIX)pool/ $(ROOT_PREFIX)locking/
EXAMPLE := $(ROOT_PREFIX)example/main.v

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
	@echo "  make clean     - Remove build artifacts"

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