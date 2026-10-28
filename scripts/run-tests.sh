#!/bin/sh
# run-tests.sh — 按文件跑测试，每条命令 30s 熔断
#
# 为什么按文件
# ------------
# `v test mod/` 把整个模块的用例编进一个二进制。只要里面有 1 个用例死锁，
# 整个模块就挂住，CI 只能等到全局限时才失败 —— 拿不到「是谁卡的」，
# 而且会把后面的模块一起拖死。按文件跑才能定位到具体文件、并在 30s 内掐断。
#
# 编译与运行分开计时
# ------------------
# `v test file_test.v` 是「编译 + 运行」两段，编译要 10~15s（web/module 尤其慢）。
# 合成一个超时的话，慢机器上编译就可能吃掉全部预算，于是把「编译慢」误报成
# 「用例挂死」—— 这类误报比漏报更坏：会让人去查一个并不存在的死锁。
#
# 所以：编译单独给 BUILD_TIMEOUT（默认 180s），只有运行进程才吃 TEST_TIMEOUT
# （默认 30s）。超时后能明确区分是 BUILD_TIMEOUT 还是 RUN_TIMEOUT。
#
# 用法:
#   sh scripts/run-tests.sh                 # 全部模块
#   sh scripts/run-tests.sh web orm         # 指定模块
#   PHOTON_TEST_TIMEOUT=20 sh scripts/run-tests.sh web   # 自定义运行超时（默认 30s）
#   PHOTON_BUILD_TIMEOUT=300 sh scripts/run-tests.sh web # 自定义编译超时（默认 180s）
#
# 退出码: 0 全绿 / 1 有失败或超时
set -u

ROOT="${PHOTON_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || exit 1

VFLAGS="${VFLAGS:--enable-globals}"
TIMEOUT="${PHOTON_TEST_TIMEOUT:-30}"
BUILD_TIMEOUT="${PHOTON_BUILD_TIMEOUT:-180}"
V="${V:-v}"
LOG_DIR="${PHOTON_TEST_LOG_DIR:-/tmp/photon-test-logs}"
# 编译产物放仓库内临时目录，不放 /tmp。
# 原因：把产物放 /tmp/photon-test-logs/.bin 时，产物会被立刻清掉
# （v 返回 0 但目标文件不存在），于是每个文件都误报「编译失败」。
# 放仓库内既稳定，也能被 .gitignore 一次覆盖。
BIN_DIR="${PHOTON_TEST_BIN_DIR:-$ROOT/.photon-test-bin}"

ALL_MODULES="core config logger security cli web orm http queue support ticker cache pool locking async photon_i18n health metrics mailer retry storage tracing apidoc"

if [ $# -gt 0 ]; then
	MODULES="$*"
else
	MODULES="$ALL_MODULES"
fi

mkdir -p "$LOG_DIR" "$BIN_DIR"

# run_with_timeout SECS CMD...  —— 超时则连同整个进程组一起杀
#
# 为什么不能只 timeout 顶层进程
# ----------------------------
# `v -o bin file_test.v` 编译完会立刻执行测试二进制并 wait 它。
# GNU timeout 默认只给直接子进程发信号，产物就成了孤儿继续跑：
# CPU 被逐渐吃满、后续用例莫名变慢，日志还只写一个 "Killed"，
# 排查时完全看不出是谁在烧 CPU。
# 所以统一用 setsid 建进程组，超时对整组 kill -9。
run_with_timeout() {
	_secs=$1
	shift
	setsid "$@" &
	_pid=$!

	(
		i=0
		while [ "$i" -lt "$_secs" ]; do
			sleep 1
			kill -0 "$_pid" 2>/dev/null || exit 0
			i=$((i + 1))
		done
		kill -9 -"$_pid" 2>/dev/null
		kill -9 "$_pid" 2>/dev/null
	) &
	_wd=$!

	wait "$_pid"
	_rc=$?

	kill -9 "$_wd" 2>/dev/null
	kill -9 -"$_pid" 2>/dev/null
	wait "$_wd" 2>/dev/null
	if [ "$_rc" -eq 137 ]; then
		return 124
	fi
	return $_rc
}

# run_one_file FILE LOG BIN  —— 跑一个测试文件，通过全局 PROBE 回传结论
#
# 三个超时预算各管一段，别混在一起：
#   BUILD_TIMEOUT  只给编译（`v -o bin` 编完即退出，产物留着先不跑）
#   TIMEOUT        只给运行（单独执行编译产物）
# 分开的理由：合成一个预算时，慢机器上的冷编译会吃光预算并被报成「用例挂死」，
# 于是有人去查一个并不存在的死锁。分开后 [BUILD-TIMEOUT] 和 [RUN-TIMEOUT]
# 是两件不同的事，看到的标签就是结论。
run_one_file() {
	_file=$1
	_log=$2
	_bin=$3

	: >"$_log"

	run_with_timeout "$BUILD_TIMEOUT" "$V" $VFLAGS -keepc -o "$_bin" "$_file" >>"$_log" 2>&1
	_brc=$?
	if [ "$_brc" -eq 124 ]; then
		PROBE=build_timeout
		return
	fi
	if [ "$_brc" -ne 0 ] || [ ! -f "$_bin" ]; then
		PROBE=compile_fail
		PROBE_RC=$_brc
		return
	fi

	run_with_timeout "$TIMEOUT" "$_bin" >>"$_log" 2>&1
	_rrc=$?
	rm -f "$_bin"
	if [ "$_rrc" -eq 124 ]; then
		PROBE=run_timeout
		return
	fi
	if [ "$_rrc" -ne 0 ]; then
		PROBE=fail
		PROBE_RC=$_rrc
		return
	fi
	PROBE=ok
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
printf '  Photon Test Runner — 编译 %ss / 运行 %ss 各自计时\n' "$BUILD_TIMEOUT" "$TIMEOUT"
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
		bin="$BIN_DIR/${mod}__${name%.v}"

		PROBE=
		PROBE_RC=0
		run_one_file "$f" "$log" "$bin"

		case $PROBE in
		ok)
			printf '    [OK]      %s\n' "$name"
			PASS=$((PASS + 1))
			;;
		run_timeout)
			printf '    [RUN-TIMEOUT] %s  (> %ss, 用例挂死)\n' "$name" "$TIMEOUT"
			printf '              日志: %s\n' "$log"
			report_timeout "$f"
			;;
		build_timeout)
			printf '    [BUILD-TIMEOUT] %s  (> %ss, 编译未完成)\n' "$name" "$BUILD_TIMEOUT"
			printf '              日志: %s\n' "$log"
			report_timeout "$f"
			;;
		compile_fail)
			printf '    [FAIL]    %s  (编译失败 rc=%s)\n' "$name" "$PROBE_RC"
			printf '              日志: %s\n' "$log"
			report_fail "$f"
			;;
		*)
			printf '    [FAIL]    %s  (rc=%s)\n' "$name" "$PROBE_RC"
			printf '              日志: %s\n' "$log"
			report_fail "$f"
			;;
		esac
	done
done

printf '\n----------------------------------------------\n'
printf '  Passed: %s | Failed: %s | Timeout: %s | Skipped: %s\n' "$PASS" "$FAIL" "$TIMEOUTS" "$SKIP"
if [ -n "$TIMEOUT_LIST" ]; then
	printf '\n  ⏱ 超时（编译 > %ss，或运行 > %ss 未结束）:\n' "$BUILD_TIMEOUT" "$TIMEOUT"
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
