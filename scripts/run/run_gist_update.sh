#!/bin/bash
#
# Gist 数据集：四种策略（direct 段错误会跳过），GTI_UPDATE_RATIO=0.001，删除 1000 条（与插入同量）
# 日志: results/gist/update/logs/run_gist_YYYYMMDD_HHMMSS.log
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"
cd "$ROOT"

LOGDIR="$ROOT/results/gist/update/logs"
mkdir -p "$LOGDIR"
TS=$(date +%Y%m%d_%H%M%S)
LOG="$LOGDIR/run_gist_${TS}.log"

echo "========== Gist wolverine+hybrid (ratio=0.001, delete=1000) =========="
echo "[$(date -Iseconds)] START" | tee "$LOG"
# gist 删除 1000 时 direct/lazy(n2) 会段错误，仅运行 wolverine hybrid
GTI_UPDATE_RATIO=0.001 GTI_UPDATE_DELETE_N=1000 GTI_STRATEGIES="wolverine hybrid" "$SCRIPT_DIR/run_compare_all_delete_strategies.sh" gist run 2>&1 | tee -a "$LOG"
echo "[$(date -Iseconds)] END" >> "$LOG"
echo "日志: $LOG"
