#!/bin/bash
#
# Deep 数据集：四种删除策略，GTI_UPDATE_RATIO=0.001（0.1%）
# 日志: results/deep/update/logs/run_deep_YYYYMMDD_HHMMSS.log
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"
cd "$ROOT"

LOGDIR="$ROOT/results/deep/update/logs"
mkdir -p "$LOGDIR"
TS=$(date +%Y%m%d_%H%M%S)
LOG="$LOGDIR/run_deep_${TS}.log"

echo "========== Deep 四种策略 (ratio=0.001, 0.1%) =========="
echo "[$(date -Iseconds)] START" | tee "$LOG"
GTI_UPDATE_RATIO=0.001 "$SCRIPT_DIR/run_compare_all_delete_strategies.sh" deep run 2>&1 | tee -a "$LOG"
echo "[$(date -Iseconds)] END" >> "$LOG"
echo "日志: $LOG"
