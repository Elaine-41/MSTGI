#!/bin/bash
#
# 同时后台运行 Deep 和 Gist（分开执行可并行）
# 用法: "$SCRIPT_DIR/run_deep_gist_update.sh"
# 或分别执行: "$SCRIPT_DIR/run_deep_update.sh" &  "$SCRIPT_DIR/run_gist_update.sh" &
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"
cd "$ROOT"

echo "后台启动 Deep 和 Gist（并行运行）..."
"$SCRIPT_DIR/run_deep_update.sh" &
"$SCRIPT_DIR/run_gist_update.sh" &
wait
echo "全部完成"
