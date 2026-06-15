# photon/Makefile — Photon Framework Build & Test Automation
#
# Run from project root:  make -f photon/Makefile test
#
# Targets:
#   make build     - Compile the full server example
#   make run       - Compile and run the full server example
#   make test      - Run all ORM test files
#   make test-all  - Run all Photon test files
#   make check     - Typecheck all modules (no test execution)
#   make clean     - Remove build artifacts

# ── V Compiler flags ──
VFLAGS := -enable-globals

# ── Module directories (trailing slashes required for V multi-target) ──
MODULES := photon/core/ photon/config/ photon/log/ photon/security/ photon/cli/ photon/web/ photon/orm/
EXAMPLE := photon/example/main.v

# ── ORM test files ──
ORM_TESTS := photon/orm/orm_test.v \
             photon/orm/entity_test.v \
             photon/orm/adapter_test.v \
             photon/orm/repository_test.v \
             photon/orm/derive_test.v \
             photon/orm/transaction_test.v

# ── Targets ──

.PHONY: build run test test-all check clean help

help:
	@echo "Photon Framework Build & Test"
	@echo ""
	@echo "  make build     - Compile the full server example"
	@echo "  make run       - Compile and run the full server example"
	@echo "  make test      - Run all ORM test files (6)"
	@echo "  make test-all  - Run all Photon tests (photon/...)"
	@echo "  make check     - Typecheck all modules + example"
	@echo "  make clean     - Remove build artifacts"

build:
	@mkdir -p photon/bin
	v $(VFLAGS) -o photon/bin/photon-example $(EXAMPLE) $(MODULES)
	@echo "Binary: photon/bin/photon-example"

run:
	v $(VFLAGS) run $(EXAMPLE) $(MODULES)

test:
	v $(VFLAGS) test $(ORM_TESTS)

test-all:
	v $(VFLAGS) test photon/...

check:
	@for dir in $(MODULES); do \
		printf "Check %-25s ... " "$$dir"; \
		v $(VFLAGS) -shared -o /dev/null "$$dir" >/dev/null 2>&1 && echo "OK" || echo "FAIL"; \
	done
	@printf "Check %-25s ... " "$(EXAMPLE)"
	@v $(VFLAGS) -o /dev/null $(EXAMPLE) $(MODULES) >/dev/null 2>&1 && echo "OK" || echo "FAIL (see 'make run' for details)"

clean:
	rm -rf photon/bin/
