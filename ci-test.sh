#!/bin/sh
# ci-test.sh — Local CI pipeline validation
# Run:   cd photon && sh ci-test.sh
#         or   make ci-test
#
# This mirrors what GitHub Actions does in .github/workflows/ci.yml

set -e

VFLAGS="-enable-globals"
MODULES="core config logger security cli web orm http queue support ticker cache pool locking async photon_i18n health metrics mailer retry storage tracing apidoc"

echo ""
echo "=============================================="
echo "  Photon Framework — CI Pipeline (Local)"
echo "=============================================="
echo ""

# Step 1: Verify V installation + module deps
echo "→ Step 1: V version"
v --version
echo ""

echo "→ Step 1b: Module dependencies"
# v.mod 声明 xiusin.vredis；上游版本在 V 0.5.2 下编不过，装完打补丁。
if [ ! -d "$HOME/.vmodules/xiusin/vredis" ]; then
    v install xiusin.vredis
fi
sh scripts/patch-vredis.sh
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

# Step 4: Build example
echo "→ Step 4: Build Example"
mkdir -p bin
v $VFLAGS -prod -o bin/photon-app example/
echo "  Binary: bin/photon-app ($(ls -lh bin/photon-app | awk '{print $5}'))"
echo ""

echo "=============================================="
echo "  ✅ CI Pipeline Complete — All Checks Passed"
echo "=============================================="
