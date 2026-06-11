#!/bin/bash
#
# Sift 消融实验（单数据集，旧版）
# 建议优先使用 run_ablation.sh（先 deep 再 sift，二者最佳配置）
# 本脚本仅跑 sift，MST 用 mst_full(200/300/0.1)，wolverine_d2 用 Wolverine+方向2
# 结果: results/ablation/sift/
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

GTI_BIN="./GTI/bin/GTI"
GTI_SHG_BIN="./GTI/bin/GTI_shg"
BASE="./Datasets/sift/sift/sift_base.fvecs"
QUERY="./Datasets/sift/sift/sift_query.fvecs"
GT="./Datasets/sift/sift/sift_groundtruth.ivecs"
L=60
K=10
UPDATE_RATIO=0.01

RESULTS_ROOT="./results/ablation/sift"
CSV="${RESULTS_ROOT}/ablation_compare.csv"

if [ ! -f "$BASE" ] || [ ! -f "$QUERY" ] || [ ! -f "$GT" ]; then
  echo "错误: sift 数据集文件不完整"
  exit 1
fi

mkdir -p "$RESULTS_ROOT"
echo "variant,aknn_build_s,aknn_search_s,aknn_recall,update_build_s,update_insert_avg_s,update_delete_avg_s,update_final_recall" > "$CSV"

export GTI_LSH_ENABLED=0
export GTI_UPDATE_RATIO="$UPDATE_RATIO"
export OMP_NUM_THREADS=1

# ========== 1. Baseline (GTI 原始: lb + hybrid) ==========
run_baseline() {
  local dir="${RESULTS_ROOT}/baseline_lb"
  rm -rf "$dir"
  mkdir -p "$dir/aknn" "$dir/update"

  export GTI_SPLIT_STRATEGY=lb
  unset GTI_PATCH_DELETE_ONLY GTI_TREE_PRIORITY_SAME_LEAF GTI_WOLVERINE_DELETE_MODEL

  echo "========== [baseline_lb] A-kNN =========="
  "$GTI_BIN" "$BASE" "$QUERY" 0 "$GT" "$L" "$K" "$dir/aknn/" 2>&1 | tee "$dir/aknn/run.log"

  echo "========== [baseline_lb] Update =========="
  "$GTI_BIN" "$BASE" "$QUERY" 3 "$GT" "$dir/update/" 2>&1 | tee "$dir/update/run.log"

  local aknn_file="$dir/aknn/cost_${K}_${L}.txt"
  local upd_sum="$dir/update/update_summary_k10_l60_ratio0.010.txt"
  local upd_csv="$dir/update/update_curve_k10_l60_ratio0.010.csv"

  local aknn_build aknn_search aknn_recall upd_build upd_insert upd_delete upd_recall
  aknn_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_search="$(awk -F: '/Search time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_recall="$(awk -F: '/Search recall/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  upd_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_insert="$(awk -F: '/Insert avg time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_delete="$(awk -F: '/Delete avg time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_recall="$(tail -1 "$upd_csv" | awk -F, '{print $5}')"

  echo "baseline_lb,${aknn_build},${aknn_search},${aknn_recall},${upd_build},${upd_insert},${upd_delete},${upd_recall}" >> "$CSV"
}

# ========== 2. MST (mst_full) ==========
run_mst() {
  local dir="${RESULTS_ROOT}/mst_full"
  rm -rf "$dir"
  mkdir -p "$dir/aknn" "$dir/update"

  export GTI_SPLIT_STRATEGY=mst
  export GTI_MST_USE_SAMPLING=0
  export GTI_MST_FULL_THRESHOLD=200
  export GTI_MST_SAMPLE_SIZE=300
  export GTI_MST_BALANCE_MIN_FRAC=0.1
  export GTI_MST_SEED=42
  unset GTI_PATCH_DELETE_ONLY GTI_TREE_PRIORITY_SAME_LEAF

  echo "========== [mst_full] A-kNN =========="
  "$GTI_BIN" "$BASE" "$QUERY" 0 "$GT" "$L" "$K" "$dir/aknn/" 2>&1 | tee "$dir/aknn/run.log"

  echo "========== [mst_full] Update =========="
  "$GTI_BIN" "$BASE" "$QUERY" 3 "$GT" "$dir/update/" 2>&1 | tee "$dir/update/run.log"

  local aknn_file="$dir/aknn/cost_${K}_${L}.txt"
  local upd_sum="$dir/update/update_summary_k10_l60_ratio0.010.txt"
  local upd_csv="$dir/update/update_curve_k10_l60_ratio0.010.csv"

  local aknn_build aknn_search aknn_recall upd_build upd_insert upd_delete upd_recall
  aknn_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_search="$(awk -F: '/Search time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_recall="$(awk -F: '/Search recall/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  upd_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_insert="$(awk -F: '/Insert avg time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_delete="$(awk -F: '/Delete avg time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_recall="$(tail -1 "$upd_csv" | awk -F, '{print $5}')"

  echo "mst_full,${aknn_build},${aknn_search},${aknn_recall},${upd_build},${upd_insert},${upd_delete},${upd_recall}" >> "$CSV"
}

# ========== 3. Wolverine + 方向2 ==========
run_wolverine_d2() {
  local dir="${RESULTS_ROOT}/wolverine_d2"
  rm -rf "$dir"
  mkdir -p "$dir/aknn" "$dir/update"

  export GTI_SPLIT_STRATEGY=lb
  export GTI_PATCH_DELETE_ONLY=1
  export GTI_TREE_PRIORITY_SAME_LEAF=1
  export GTI_WOLVERINE_DELETE_MODEL=Wolverine

  echo "========== [wolverine_d2] A-kNN =========="
  "$GTI_BIN" "$BASE" "$QUERY" 0 "$GT" "$L" "$K" "$dir/aknn/" 2>&1 | tee "$dir/aknn/run.log"

  echo "========== [wolverine_d2] Update =========="
  "$GTI_BIN" "$BASE" "$QUERY" 3 "$GT" "$dir/update/" 2>&1 | tee "$dir/update/run.log"

  local aknn_file="$dir/aknn/cost_${K}_${L}.txt"
  local upd_sum="$dir/update/update_summary_k10_l60_ratio0.010.txt"
  local upd_csv="$dir/update/update_curve_k10_l60_ratio0.010.csv"

  local aknn_build aknn_search aknn_recall upd_build upd_insert upd_delete upd_recall
  aknn_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_search="$(awk -F: '/Search time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_recall="$(awk -F: '/Search recall/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  upd_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_insert="$(awk -F: '/Insert avg time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_delete="$(awk -F: '/Delete avg time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_recall="$(tail -1 "$upd_csv" | awk -F, '{print $5}')"

  echo "wolverine_d2,${aknn_build},${aknn_search},${aknn_recall},${upd_build},${upd_insert},${upd_delete},${upd_recall}" >> "$CSV"
}

# ========== 4. MST + Wolverine_d2 组合（两者同时开启）==========
run_mst_wolverine_d2() {
  local dir="${RESULTS_ROOT}/mst_wolverine_d2"
  rm -rf "$dir"
  mkdir -p "$dir/aknn" "$dir/update"

  # MST 最优配置 + Wolverine_d2 最优配置
  export GTI_SPLIT_STRATEGY=mst
  export GTI_MST_USE_SAMPLING=0
  export GTI_MST_FULL_THRESHOLD=200
  export GTI_MST_SAMPLE_SIZE=300
  export GTI_MST_BALANCE_MIN_FRAC=0.1
  export GTI_MST_SEED=42
  export GTI_PATCH_DELETE_ONLY=1
  export GTI_TREE_PRIORITY_SAME_LEAF=1
  export GTI_WOLVERINE_DELETE_MODEL=Wolverine

  echo "========== [mst_wolverine_d2] A-kNN =========="
  "$GTI_BIN" "$BASE" "$QUERY" 0 "$GT" "$L" "$K" "$dir/aknn/" 2>&1 | tee "$dir/aknn/run.log"

  echo "========== [mst_wolverine_d2] Update =========="
  "$GTI_BIN" "$BASE" "$QUERY" 3 "$GT" "$dir/update/" 2>&1 | tee "$dir/update/run.log"

  local aknn_file="$dir/aknn/cost_${K}_${L}.txt"
  local upd_sum="$dir/update/update_summary_k10_l60_ratio0.010.txt"
  local upd_csv="$dir/update/update_curve_k10_l60_ratio0.010.csv"

  local aknn_build aknn_search aknn_recall upd_build upd_insert upd_delete upd_recall
  aknn_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_search="$(awk -F: '/Search time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_recall="$(awk -F: '/Search recall/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  upd_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_insert="$(awk -F: '/Insert avg time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_delete="$(awk -F: '/Delete avg time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_recall="$(tail -1 "$upd_csv" | awk -F, '{print $5}')"

  echo "mst_wolverine_d2,${aknn_build},${aknn_search},${aknn_recall},${upd_build},${upd_insert},${upd_delete},${upd_recall}" >> "$CSV"
}

# ========== 5. SHG prune0 ==========
run_shg() {
  local dir="${RESULTS_ROOT}/shg_prune0"
  rm -rf "$dir"
  mkdir -p "$dir/aknn" "$dir/update"

  if [ ! -x "$GTI_SHG_BIN" ]; then
    echo "跳过 shg_prune0: GTI_shg 不存在，请先编译 SHG 版本"
    return 1
  fi

  export GTI_SPLIT_STRATEGY=lb
  export GTI_PATCH_DELETE_ONLY=1
  export GTI_DELETE_CHUNK_SIZE=2000
  export GTI_SHG_PRUNE=0
  export GTI_SHG_M=24
  export GTI_SHG_EF_BUILD=80
  export GTI_SHG_EF_SEARCH=80
  # m24_efb80_efs80 为 SHG_prune0 推荐优化参数（SHG_PLAN_PROGRESS_ANALYSIS 第八节）

  echo "========== [shg_prune0] A-kNN =========="
  "$GTI_SHG_BIN" "$BASE" "$QUERY" 0 "$GT" "$L" "$K" "$dir/aknn/" 2>&1 | tee "$dir/aknn/run.log"

  echo "========== [shg_prune0] Update =========="
  "$GTI_SHG_BIN" "$BASE" "$QUERY" 3 "$GT" "$dir/update/" 2>&1 | tee "$dir/update/run.log"

  local aknn_file="$dir/aknn/cost_${K}_${L}.txt"
  local upd_sum="$dir/update/update_summary_k10_l60_ratio0.010.txt"
  local upd_csv="$dir/update/update_curve_k10_l60_ratio0.010.csv"

  local aknn_build aknn_search aknn_recall upd_build upd_insert upd_delete upd_recall
  aknn_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_search="$(awk -F: '/Search time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_recall="$(awk -F: '/Search recall/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  upd_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_insert="$(awk -F: '/Insert avg time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_delete="$(awk -F: '/Delete avg time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_recall="$(tail -1 "$upd_csv" | awk -F, '{print $5}')"

  echo "shg_prune0,${aknn_build},${aknn_search},${aknn_recall},${upd_build},${upd_insert},${upd_delete},${upd_recall}" >> "$CSV"
}

# ========== 执行：baseline + MST + wolverine_d2 + MST+wolverine_d2 组合 ==========
echo "=========================================="
echo "Sift 消融实验: GTI原始 | MST | Wolverine_d2 | MST+Wolverine_d2"
echo "统一 ratio=0.01，使用各板块最优配置"
echo "结果目录: $RESULTS_ROOT"
echo "=========================================="

run_baseline || true
run_mst || true
run_wolverine_d2 || true
run_mst_wolverine_d2 || true

echo ""
echo "=========================================="
echo "消融实验完成！"
echo "对比结果: $CSV"
echo "=========================================="
if [ -f "$CSV" ]; then
  echo ""
  column -t -s, "$CSV" 2>/dev/null || cat "$CSV"
fi
