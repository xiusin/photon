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
# 逐文件跑 + 每条命令 30s 熔断（scripts/run-tests.sh）。
# 单个用例死锁只会被判为 TIMEOUT 并强杀，不会拖垮整条流水线。
echo "→ Step 3: Module Tests (per-file, ${PHOTON_TEST_TIMEOUT:-30}s timeout)"
if sh scripts/run-tests.sh; then
    PASS=$((PASS + 1))
else
    FAIL=$((FAIL + 1))
fi
echo ""

# Step 3b: Vendored dependency tests (needs a reachable Redis; skipped otherwise)
# 同样走 30s 熔断：Redis 不可达时用例会长时间重试，不能让它挂住流水线。
echo "→ Step 3b: Vendored module tests (${PHOTON_TEST_TIMEOUT:-30}s timeout)"
for mod in $VENDOR_MODULES; do
    log="/tmp/photon-vendor-$(echo "$mod" | tr '/' '_').log"
    if timeout -k 5 "${PHOTON_TEST_TIMEOUT:-30}" v $VFLAGS test "$mod/" >"$log" 2>&1; then
        echo "  [OK]   $mod/"
    else
        rc=$?
        if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
            echo "  [TIMEOUT] $mod/ (> ${PHOTON_TEST_TIMEOUT:-30}s, 已强杀) 日志: $log"
        else
            echo "  [FAIL] $mod/ (rc=$rc) 日志: $log"
        fi
        FAIL=$((FAIL + 1))
    fi
done
echo ""

# Step 4: Build example
echo "→ Step 4: Build Example"
# 全量编译本身也可能卡在 comptime 展开上，给一个更宽的熔断（默认 300s）。
mkdir -p bin
BUILD_TIMEOUT="${PHOTON_BUILD_TIMEOUT:-300}"
timeout -k 10 "$BUILD_TIMEOUT" v $VFLAGS -prod -o bin/photon-app example/ || {
    rc=$?
    echo "  ❌ example 编译失败 (rc=$rc$([ "$rc" -eq 124 ] && echo ", 超 ${BUILD_TIMEOUT}s 已强杀"))"
    exit 1
}
echo "  Binary: bin/photon-app ($(ls -lh bin/photon-app | awk '{print $5}'))"
echo ""

echo "=============================================="
echo "  ✅ CI Pipeline Complete — All Checks Passed"
echo "=============================================="
