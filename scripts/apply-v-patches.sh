#!/bin/sh
# apply-v-patches.sh — 把 scripts/v-patches/ 下的编译器补丁打进本地 V 并重新自举
#
# 为什么需要这一步
# ----------------
# Photon 的控制器约定是 `(mut ctx veb.Context, params map[string]string)`，
# 而 V 0.5.2 的 checker 把「任何返回 veb.Result 的方法」都当成 veb app 方法，
# 只放行 string/整数/bool。于是 `example/verify`（247 项功能断言）和
# `web/mount_test.v` 在**未打补丁的官方编译器**上整包编不过。
#
# 这条约束没法在框架里绕：改成 string 参数就等于放弃路径参数。
# 所以框架代码保持原样，把「需要编译器配合」这件事显式做成一个脚本，
# 而不是让每次验证都变成一次手工试错。
#
# 用法：
#   sh scripts/apply-v-patches.sh                  # 自动定位 V（$VEXE、v、$VROOT）
#   VROOT=/path/to/v sh scripts/apply-v-patches.sh # 指定 V 源码目录
#   VFLAGS="-gc none" sh scripts/apply-v-patches.sh # 自举时加参数（默认就是 -gc none）
#
# 幂等：已经打过的补丁会被跳过（`git apply --reverse --check` 探测）。
# 非 git 目录的 V 源码树无法用 git apply，会直接报错退出，不做猜测性改动。
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PATCH_DIR="$ROOT/scripts/v-patches"
# 0.5.2 在较新 glibc 上自举必须绕开预编译 libgc（缺 sigsetjmp）
VFLAGS="${VFLAGS:--gc none}"

if [ -z "${VROOT:-}" ]; then
	if [ -n "${VEXE:-}" ]; then
		VROOT=$(dirname "$(dirname "$(readlink -f "$VEXE")")")
	elif command -v v >/dev/null 2>&1; then
		VROOT=$(dirname "$(dirname "$(readlink -f "$(command -v v)")")")
	fi
fi

if [ -z "${VROOT:-}" ] || [ ! -d "$VROOT/vlib/v" ]; then
	echo "apply-v-patches: 找不到 V 源码目录；用 VROOT=/path/to/v 指定" >&2
	exit 1
fi
if [ ! -d "$VROOT/.git" ]; then
	echo "apply-v-patches: $VROOT 不是 git 仓库，无法安全地打补丁" >&2
	exit 1
fi

echo "→ V 源码: $VROOT"
for p in "$PATCH_DIR"/*.patch; do
	[ -f "$p" ] || continue
	name=$(basename "$p")
	if (cd "$VROOT" && git apply --reverse --check "$p" 2>/dev/null); then
		echo "  [SKIP] $name（已应用）"
		continue
	fi
	if (cd "$VROOT" && git apply "$p"); then
		echo "  [OK]   $name"
	else
		echo "  [FAIL] $name —— 补丁与当前 V 源码不匹配（版本不同批？）" >&2
		exit 1
	fi
done

echo "→ 重新自举（make local=1 VFLAGS=\"$VFLAGS\"）"
# 注意 VFLAGS 要作为 make 变量传：`make local=1 VFLAGS="-gc none"`。
# 直接 `make local=1 -gc none` 会被 make 当成选项解析并报错。
(cd "$VROOT" && make local=1 VFLAGS="$VFLAGS" >/tmp/photon-v-rebuild.log 2>&1) || {
	echo "apply-v-patches: 自举失败，日志 /tmp/photon-v-rebuild.log" >&2
	echo "  提示：0.5.2 首次自举需要 -gc none（预编译 libgc 在较新 glibc 上缺 sigsetjmp）" >&2
	exit 1
}
"$VROOT/v" version
echo "✅ 编译器补丁已应用"
