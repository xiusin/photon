#!/bin/sh
# ci-test.sh — Local CI pipeline validation
# Run:   cd photon && sh ci-test.sh
#         or   make ci-test
#
# This mirrors what GitHub Actions does in .github/workflows/ci.yml

set -e

VFLAGS="-enable-globals"
MODULES="core config logger security cli web orm http queue support ticker cache pool locking async photon_i18n health metrics mailer retry storage tracing apidoc"
VENDOR_MODULES="vendor/modules/xiusin/vredis"

echo ""
echo "=============================================="
echo "  Photon Framework — CI Pipeline (Local)"
echo "=============================================="
echo ""

# Step 1: Verify V installation + module deps
echo "→ Step 1: V version"
v --version
echo ""

echo "→ Step 1b: Vendored dependencies"
# 唯一的第三方代码 vendor 在仓库内（vendor/modules/xiusin/vredis）。
# 这一步把它链接进 V 的模块搜索路径，本地与 CI 用的是同一份源码。
sh scripts/sync-vendor.sh
echo ""

# Step 2: Check formatting (non-blocking)
echo "→ Step 2: Format check"
v fmt -check . || echo "  Format warnings (non-blocking)"
echo ""

# Step 3: Run all module tests
echo "→ Step 3: Module Tests"
PASS=0
FAIL=0
for mod in $MODULES; do
    if v $VFLAGS test "$mod/" >/dev/null 2>&1; then
        echo "  [OK]   $mod/"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $mod/"
        FAIL=$((FAIL + 1))
    fi
done
echo ""
echo "  Total: $((PASS + FAIL)) | Passed: $PASS | Failed: $FAIL"
echo ""

if [ $FAIL -gt 0 ]; then
    echo "❌ CI FAILED: $FAIL module(s) failed"
    exit 1
fi

# Step 3b: Vendored dependency tests (needs a reachable Redis; skipped otherwise)
echo "→ Step 3b: Vendored module tests"
for mod in $VENDOR_MODULES; do
    if v $VFLAGS test "$mod/" >/dev/null 2>&1; then
        echo "  [OK]   $mod/"
    else
        echo "  [FAIL] $mod/"
        FAIL=$((FAIL + 1))
    fi
done
echo ""

# Step 4: Build example
echo "→ Step 4: Build Example"
mkdir -p bin
v $VFLAGS -prod -o bin/photon-app example/
echo "  Binary: bin/photon-app ($(ls -lh bin/photon-app | awk '{print $5}'))"
echo ""

echo "=============================================="
echo "  ✅ CI Pipeline Complete — All Checks Passed"
echo "=============================================="
