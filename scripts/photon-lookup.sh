#!/bin/sh
# photon-lookup.sh — 输出一个能解析 `import photon.<x>` 的 V 查找根
#
# V 按 `<查找根>/<module_path>` 拼全限定 import，所以查找根下必须有一个
# 真的叫 `photon` 的目录指向本仓库。检出目录往往叫 /workspace、photon-2
# 之类，不带 -path 时 `import photon.pool` 一律 cannot import module。
#
# 用法（在所有需要编框架源码的地方）：
#   LOOKUP=$(sh scripts/photon-lookup.sh)
#   v -path "@vlib|@vmodules|${LOOKUP}" ...
#
# 目录名恰为 photon 时直接用父目录；否则在仓库内的 .photon-test-bin/lookup/
# 放一个叫 photon 的符号链接。用链接是安全的：这里只要求「仓库内解析到
# 本仓库」，不需要模拟下游安装布局（那是 strutil/downstream_import_test.v
# 的事，那条必须用拷贝）。
#
# 所有调用方共用这一份，避免「改了 run-tests.sh 却忘了 Makefile」这种
# 半套修复 —— 上一轮下游 import 编不过，就是这么来的。
set -u

ROOT="${PHOTON_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
mkdir -p "$ROOT/.photon-test-bin"

name=$(basename "$ROOT")
if [ "$name" = "photon" ]; then
	printf '%s' "$(dirname "$ROOT")"
	exit 0
fi

dir="$ROOT/.photon-test-bin/lookup"
mkdir -p "$dir"
[ -e "$dir/photon" ] || ln -s "$ROOT" "$dir/photon"
printf '%s' "$dir"
