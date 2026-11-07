#!/bin/sh
# ci-test.sh — Local CI pipeline validation
# Run:   cd photon && sh ci-test.sh
#         or   make ci-test
#
# This mirrors what GitHub Actions does in .github/workflows/ci.yml

set -e

VFLAGS="-enable-globals"
MODULES="core config logger security cli web orm http queue strutil pageable ticker cache pool locking async photon_i18n health metrics mailer retry storage tracing apidoc"
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
# 逐文件跑，编译与运行各自计时（scripts/run-tests.sh）：
#   PHOTON_BUILD_TIMEOUT  编译预算，默认 180s（冷编译 10~15s，慢机器留足余量）
#   PHOTON_TEST_TIMEOUT   运行预算，默认 30s
# 分开的理由：合成一个预算时，慢机器上编译吃光预算会被报成「用例挂死」，
# 于是有人去查一个并不存在的死锁。超时连同进程组一起强杀，不留孤儿进程。
echo "→ Step 3: Module Tests (per-file, build ${PHOTON_BUILD_TIMEOUT:-180}s / run ${PHOTON_TEST_TIMEOUT:-30}s)"
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
# example/ 会经由 web/request_pool.v 引到 `import photon.pool`，同样需要
# photon 查找根（见 scripts/photon-lookup.sh）。不带 -path 会报
# `cannot import module "photon.pool"`。
LOOKUP=$(sh scripts/photon-lookup.sh)
timeout -k 10 "$BUILD_TIMEOUT" v $VFLAGS -path "@vlib|@vmodules|${LOOKUP}" -prod -o bin/photon-app example/ || {
    rc=$?
    echo "  ❌ example 编译失败 (rc=$rc$([ "$rc" -eq 124 ] && echo ", 超 ${BUILD_TIMEOUT}s 已强杀"))"
    exit 1
}
echo "  Binary: bin/photon-app ($(ls -lh bin/photon-app | awk '{print $5}'))"
echo ""

echo "=============================================="
echo "  ✅ CI Pipeline Complete — All Checks Passed"
echo "=============================================="
