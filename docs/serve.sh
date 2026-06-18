#!/bin/bash
# Photon Docs — 本地预览服务器
#
# 用法: ./serve.sh [port]
# 优先使用 V 语言服务器，如不可用则降级到 Python
PORT="${1:-8765}"
DIR="$(cd "$(dirname "$0")/.." && pwd)"

if command -v v &>/dev/null; then
  echo "🚀 Using V language server..."
  cd "$DIR" && v run docs/serve.v --port "$PORT"
else
  echo "⚠️  V compiler not found, falling back to Python HTTP server"
  echo "   Install V for better experience: https://vlang.io"
  echo ""
  echo "🚀 Photon Docs starting at http://localhost:$PORT"
  echo "   Press Ctrl+C to stop"
  cd "$(dirname "$0")"
  python3 -m http.server "$PORT"
fi
