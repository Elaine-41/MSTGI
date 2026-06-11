#!/bin/bash
#
# 比较两种删除策略：混合 (Lazy + 累积后 patchDelete) vs 纯 Wolverine patchDelete
# 指标：Recall、删除总时间、删除平均每条耗时
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

DATASET="${1:-sift}"
RUN_BOTH="${2:-}"

# 结果目录
DIR_MIXED="./results/${DATASET}/update"
DIR_PATCH="./results/${DATASET}/update_patch_only"
SUM_FILE="update_summary_k10_l60_ratio0.01.txt"
CSV_FILE="update_curve_k10_l60_ratio0.01.csv"

usage() {
  echo "用法: $0 <dataset> [run]"
  echo "  dataset: sift | deep | gist (默认 sift)"
  echo "  run: 可选，若为 run 则先执行两种策略再比较；否则只比较已有结果"
  echo ""
  echo "示例:"
  echo "  $0 sift          # 仅比较已有结果"
  echo "  $0 sift run      # 先跑混合+纯 patch，再比较"
  exit 1
}

[[ -z "${DATASET}" ]] && usage

if [[ "$RUN_BOTH" = "run" ]]; then
  echo "========== 1. 混合策略 (Lazy + patchDelete) =========="
  "$SCRIPT_DIR/run_update.sh" "$DATASET" || true
  echo ""
  echo "========== 2. 纯 Wolverine patchDelete =========="
  "$SCRIPT_DIR/run_update.sh" "$DATASET" patch_only || true
  echo ""
fi

# 解析 summary 文件
parse_summary() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    echo ""
    return
  fi
  awk '
    /^Time of index construction:/ { idx_time = $NF }
    /^Delete n:/ { delete_n = $NF }
    /^Delete avg time \(s\/item\):/ { delete_avg = $NF }
    /^Delete strategy:/ { strategy = $0; sub(/^[^:]+: /,"",strategy) }
    END {
      if (delete_avg != "") printf "%.6f", delete_avg
    }
  ' "$f"
}

# 计算删除总时间 = delete_avg * delete_n（若 summary 未直接给出，从 CSV 推断）
get_delete_total_and_recall() {
  local dir="$1"
  local sum="$dir/$SUM_FILE"
  local csv="$dir/$CSV_FILE"
  if [[ ! -f "$sum" ]]; then
    echo "0|0"
    return
  fi
  local delete_n delete_avg total recall
  delete_n=$(awk '/^Delete n:/ {print $NF}' "$sum")
  delete_avg=$(awk '/^Delete avg time \(s\/item\):/ {print $NF}' "$sum")
  total="0"
  if [[ -n "$delete_n" && -n "$delete_avg" && "$delete_n" -gt 0 ]]; then
    total=$(awk "BEGIN { printf \"%.2f\", $delete_avg * $delete_n }" 2>/dev/null || echo "0")
  fi
  recall="-"
  if [[ -f "$csv" ]]; then
    # 取最后一条 delete 相关记录的 recall（避免中断导致最后一行是 insert）
    recall=$(grep -E "delete_|delete_rebuild|delete_patch" "$csv" | tail -1 | awk -F, '{print $NF}')
    [[ -z "$recall" ]] && recall=$(tail -1 "$csv" | awk -F, '{print $NF}')
  fi
  echo "${total}|${recall}"
}

echo "=========================================="
echo "  删除策略对比: $DATASET"
echo "=========================================="

for label in "混合 (Lazy+patch)" "纯 patchDelete"; do
  if [[ "$label" = "混合 (Lazy+patch)" ]]; then
    dir="$DIR_MIXED"
  else
    dir="$DIR_PATCH"
  fi
  sum="$dir/$SUM_FILE"
  if [[ ! -f "$sum" ]]; then
    echo ""
    echo "[$label] 结果不存在: $sum"
    echo "  请先运行: $0 $DATASET run"
    continue
  fi
  IFS='|' read -r total recall <<< "$(get_delete_total_and_recall "$dir")"
  delete_n=$(awk '/^Delete n:/ {print $NF}' "$sum")
  delete_avg=$(awk '/^Delete avg time \(s\/item\):/ {print $NF}' "$sum")
  echo ""
  echo "[$label]"
  echo "  删除总数:     $delete_n"
  echo "  删除总时间:   ${total}s"
  echo "  删除平均:     ${delete_avg} s/item"
  echo "  最终 Recall:  $recall"
done

echo ""
echo "--- 汇总对比 ---"
if [[ -f "$DIR_MIXED/$SUM_FILE" && -f "$DIR_PATCH/$SUM_FILE" ]]; then
  IFS='|' read -r t1 r1 <<< "$(get_delete_total_and_recall "$DIR_MIXED")"
  IFS='|' read -r t2 r2 <<< "$(get_delete_total_and_recall "$DIR_PATCH")"
  a1=$(awk '/^Delete avg time \(s\/item\):/ {print $NF}' "$DIR_MIXED/$SUM_FILE")
  a2=$(awk '/^Delete avg time \(s\/item\):/ {print $NF}' "$DIR_PATCH/$SUM_FILE")
  printf "%-25s %12s %14s %10s\n" "策略" "删除总时间(s)" "平均(s/item)" "Recall"
  printf "%-25s %12s %14s %10s\n" "混合 (Lazy+patch)" "$t1" "$a1" "$r1"
  printf "%-25s %12s %14s %10s\n" "纯 patchDelete" "$t2" "$a2" "$r2"
else
  echo "缺少任一策略结果，无法对比。运行: $0 $DATASET run"
fi
echo ""
