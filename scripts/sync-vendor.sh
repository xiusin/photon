#!/bin/sh
# sync-vendor.sh — 把 vendor/modules/<owner>/<mod> 链接进 V 的模块搜索路径
#
# 为什么需要这一步
# ----------------
# V 的 builder 只在这两处按「目录名」找模块：
#   <project>/        （编译目标所在目录）
#   <project>/modules/
# 而且只认一层目录名，所以 `vendor/modules/xiusin/vredis` 这种带 owner 的
# 路径不在搜索范围内 —— 直接用 `v test cache/` 会报
# `cannot import module "xiusin.vredis"`。
#
# 这里把 ~/.vmodules/xiusin/vredis 做成指向仓库内 vendor 目录的符号链接，
# 于是：
#   * 本地与 CI 用完全相同的一份 vredis（vendor/modules/xiusin/vredis）
#   * 上游 vredis 的改动在我们仓库里评审，不再依赖 vpm 拉到的版本
#   * 不再需要 patch 上游源码的补丁脚本
#
# 用法：sh scripts/sync-vendor.sh [more/owners...]
set -e

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VMODULES="${VMODULES:-$HOME/.vmodules}"
VENDOR="$ROOT/vendor/modules"

if [ ! -d "$VENDOR" ]; then
    echo "sync-vendor: $VENDOR not found" >&2
    exit 1
fi

for mod_dir in "$VENDOR"/*/*; do
    [ -d "$mod_dir" ] || continue
    owner=$(basename "$(dirname "$mod_dir")")
    name=$(basename "$mod_dir")
    dest="$VMODULES/$owner"
    mkdir -p "$dest"
    ln -sfn "$mod_dir" "$dest/$name"
    echo "sync-vendor: $owner.$name -> $mod_dir"
done

echo "sync-vendor: done"
