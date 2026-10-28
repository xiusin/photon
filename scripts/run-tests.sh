#!/bin/sh
# run-tests.sh — 按文件跑测试，每条命令 30s 熔断
#
# 为什么按文件
# ------------
# `v test mod/` 把整个模块的用例编进一个二进制。只要里面有 1 个用例死锁，
# 整个模块就挂住，CI 只能等到全局限时才失败 —— 拿不到「是谁卡的」，
# 而且会把后面的模块一起拖死。按文件跑才能定位到具体文件、并在 30s 内掐断。
#
# 用法:
#   sh scripts/run-tests.sh                 # 全部模块
#   sh scripts/run-tests.sh web orm         # 指定模块
#   PHOTON_TEST_TIMEOUT=20 sh scripts/run-tests.sh web   # 自定义超时（默认 30s）
#
# 退出码: 0 全绿 / 1 有失败或超时
set -u

ROOT="${PHOTON_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1

VFLAGS="${VFLAGS:--enable-globals}"
TIMEOUT="${PHOTON_TEST_TIMEOUT:-30}"
V="${V:-v}"
LOG_DIR="${PHOTON_TEST_LOG_DIR:-/tmp/photon-test-logs}"

ALL_MODULES="core config logger security cli web orm http queue support ticker cache pool locking async photon_i18n health metrics mailer retry storage tracing apidoc"

if [ $# -gt 0 ]; then
	MODULES="$*"
else
	MODULES="$ALL_MODULES"
fi

mkdir -p "$LOG_DIR"

# Portable timeout: GNU timeout 优先，macOS 没有就退化成后台跑 + 看门狗
run_with_timeout() {
	_secs=$1
	shift
	if command -v timeout >/dev/null 2>&1; then
		timeout -k 5 "$_secs" "$@"
		return $?
	fi
	"$@" &
	_pid=$!
	( sleep "$_secs"; kill -9 "$_pid" 2>/dev/null ) &
	_wd=$!
	wait "$_pid"
	_rc=$?
	kill -9 "$_wd" 2>/dev/null
	wait "$_wd" 2>/dev/null
	return $_rc
}

PASS=0
FAIL=0
TIMEOUTS=0
SKIP=0
FAILED_LIST=""
TIMEOUT_LIST=""

report_fail() {
	FAIL=$((FAIL + 1))
	FAILED_LIST="$FAILED_LIST $1"
}
report_timeout() {
	TIMEOUTS=$((TIMEOUTS + 1))
	TIMEOUT_LIST="$TIMEOUT_LIST $1"
}

printf '\n==============================================\n'
printf '  Photon Test Runner — %ss/file timeout\n' "$TIMEOUT"
printf '==============================================\n\n'

[ -x "$(command -v "$V" 2>/dev/null)" ] || [ -n "$(command -v "$V" 2>/dev/null)" ] || {
	printf 'run-tests: 找不到 V 编译器 (%s)\n' "$V" >&2
	exit 1
}

for mod in $MODULES; do
	[ -d "$mod" ] || { printf '  [SKIP] %s/ (目录不存在)\n' "$mod"; SKIP=$((SKIP + 1)); continue; }

	# 模块里没有测试文件就跳过（V 对空目录会报错）
	_files=$(ls "$mod"/*_test.v 2>/dev/null || true)
	if [ -z "$_files" ]; then
		printf '  [SKIP] %s/ (无测试文件)\n' "$mod"
		SKIP=$((SKIP + 1))
		continue
	fi

	printf '→ %s/\n' "$mod"
	for f in $_files; do
		name=$(basename "$f")
		log="$LOG_DIR/${mod}__${name}.log"
		run_with_timeout "$TIMEOUT" "$V" $VFLAGS test "$f" >"$log" 2>&1
		rc=$?
		case $rc in
		0)
			printf '    [OK]      %s\n' "$name"
			PASS=$((PASS + 1))
			;;
		124 | 137)
			printf '    [TIMEOUT] %s  (> %ss, 已强杀)\n' "$name" "$TIMEOUT"
			printf '              日志: %s\n' "$log"
			report_timeout "$f"
			;;
		*)
			printf '    [FAIL]    %s  (rc=%s)\n' "$name" "$rc"
			printf '              日志: %s\n' "$log"
			report_fail "$f"
			;;
		esac
	done
done

printf '\n----------------------------------------------\n'
printf '  Passed: %s | Failed: %s | Timeout: %s | Skipped: %s\n' "$PASS" "$FAIL" "$TIMEOUTS" "$SKIP"
if [ -n "$TIMEOUT_LIST" ]; then
	printf '\n  ⏱ 超时（%ss 内未结束，多半是死锁/挂起）:\n' "$TIMEOUT"
	for f in $TIMEOUT_LIST; do printf '      - %s\n' "$f"; done
fi
if [ -n "$FAILED_LIST" ]; then
	printf '\n  ✗ 失败:\n'
	for f in $FAILED_LIST; do printf '      - %s\n' "$f"; done
fi
printf '%s\n\n' '----------------------------------------------'

if [ "$FAIL" -gt 0 ] || [ "$TIMEOUTS" -gt 0 ]; then
	printf '❌ 测试未通过\n'
	exit 1
fi
printf '✅ 全部通过\n'
