#!/bin/bash
# Photon Docs — 本地预览服务器
# 用法: ./serve.sh [port]
PORT="${1:-8765}"
echo "🚀 Photon Docs starting at http://localhost:$PORT"
echo "   Press Ctrl+C to stop"
cd "$(dirname "$0")"
python3 -m http.server "$PORT"
