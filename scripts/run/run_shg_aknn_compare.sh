#!/bin/bash
#
# SHG A-kNN 搜索性能对比（sift）
# 与 n2、Wolverine 对比，测试 SHG 跳层优势
# 模式 0：建库 + 近似 k-NN 搜索（无 update）
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
CSV="${RESULTS_ROOT}/aknn_compare.csv"

mkdir -p "$RESULTS_ROOT"
echo "backend,aknn_build_s,aknn_search_s,aknn_recall" > "$CSV"

# 与 MST 实验一致：LB 分裂，单线程
export GTI_SPLIT_STRATEGY=lb
export GTI_LSH_ENABLED=0
export OMP_NUM_THREADS=1

run_aknn() {
  local bin="$1"
  local backend="$2"
  local out_dir="$RESULTS_ROOT/${backend}"
  mkdir -p "$out_dir"

  if [ ! -x "$bin" ]; then
    echo "跳过 ${backend}: 可执行文件不存在 $bin"
    return 1
  fi

  echo "========== ${backend} A-kNN =========="
  "$bin" "$BASE" "$QUERY" 0 "$GT" "$L" "$K" "$out_dir/" 2>&1 | tee "$out_dir/run.log"

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

# n2 基线（GTI_n2）
run_aknn "./GTI/bin/GTI_n2" "n2" || true

# Wolverine（GTI with Wolverine backend）
run_aknn "./GTI/bin/GTI" "wolverine" || true

# SHG
run_aknn "./GTI/bin/GTI_shg" "shg" || true

echo "========== 完成 =========="
echo "结果: $CSV"
echo ""
if [ -f "$CSV" ]; then
  echo "A-kNN 对比:"
  column -t -s, "$CSV" 2>/dev/null || cat "$CSV"
fi
