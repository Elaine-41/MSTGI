#!/bin/bash
#
# SHG 三种策略 A-kNN 纯搜索对比（sift）
# shg_d_rebuild / shg_e_full / shg_e_sample65
# 探究跳层优势为何未展现，不同 shortcut 策略对 aknn 搜索的影响
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

BASE="./Datasets/sift/sift/sift_base.fvecs"
QUERY="./Datasets/sift/sift/sift_query.fvecs"
GT="./Datasets/sift/sift/sift_groundtruth.ivecs"
L=60
K=10
RESULTS_ROOT="./results/sift/aknn_compare"
CSV="${RESULTS_ROOT}/aknn_compare_strategies.csv"

mkdir -p "$RESULTS_ROOT"
echo "backend,aknn_build_s,aknn_search_s,aknn_recall" > "$CSV"

export GTI_SPLIT_STRATEGY=lb
export GTI_LSH_ENABLED=0
export OMP_NUM_THREADS=1

run_aknn() {
  local backend="$1"
  local out_dir="$RESULTS_ROOT/${backend}"
  mkdir -p "$out_dir"

  if [ ! -x "./GTI/bin/GTI_shg" ]; then
    echo "跳过 ${backend}: GTI_shg 不存在"
    return 1
  fi

  echo "========== ${backend} A-kNN =========="
  ./GTI/bin/GTI_shg "$BASE" "$QUERY" 0 "$GT" "$L" "$K" "$out_dir/" 2>&1 | tee "$out_dir/run.log"

  local cost_file="$out_dir/cost_${K}_${L}.txt"
  if [ ! -f "$cost_file" ]; then
    echo "错误: 未生成 $cost_file"
    return 1
  fi

  local aknn_build aknn_search aknn_recall
  aknn_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$cost_file" | tail -1)"
  aknn_search="$(awk -F: '/Search time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$cost_file" | tail -1)"
  aknn_recall="$(awk -F: '/Search recall/ {gsub(/^[ \t]+/,"",$2); print $2}' "$cost_file" | tail -1)"

  echo "${backend},${aknn_build},${aknn_search},${aknn_recall}" >> "$CSV"
  echo ""
}

# shg_d_rebuild: 插入后 rebuild（aknn 无 insert，主要看建库+搜索基线）
echo ">>> 策略: shg_d_rebuild (GTI_SHG_REBUILD_AFTER_INSERT=1)"
unset GTI_SHG_SHORTCUT_SAMPLE_RATIO GTI_RESULT_SUFFIX
export GTI_SHG_REBUILD_AFTER_INSERT=1
run_aknn "shg_d_rebuild" || true
unset GTI_SHG_REBUILD_AFTER_INSERT

# shg_e_full: buildShortcuts 全量
echo ">>> 策略: shg_e_full (GTI_SHG_SHORTCUT_SAMPLE_RATIO=1)"
unset GTI_SHG_REBUILD_AFTER_INSERT GTI_RESULT_SUFFIX
export GTI_SHG_SHORTCUT_SAMPLE_RATIO=1
run_aknn "shg_e_full" || true
unset GTI_SHG_SHORTCUT_SAMPLE_RATIO

# shg_e_sample65: buildShortcuts 65% 采样
echo ">>> 策略: shg_e_sample65 (GTI_SHG_SHORTCUT_SAMPLE_RATIO=0.65)"
unset GTI_SHG_REBUILD_AFTER_INSERT GTI_RESULT_SUFFIX
export GTI_SHG_SHORTCUT_SAMPLE_RATIO=0.65
run_aknn "shg_e_sample65" || true
unset GTI_SHG_SHORTCUT_SAMPLE_RATIO

echo "========== 完成 =========="
echo "结果: $CSV"
echo ""
if [ -f "$CSV" ]; then
  echo "SHG 策略 A-kNN 对比:"
  column -t -s, "$CSV" 2>/dev/null || cat "$CSV"
fi
