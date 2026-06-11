#!/bin/bash
#
# 消融实验：MST + Wolverine_d2 组合（Sift 和 Gist）
# 与 deep 一样，仅跑组合实验，结果存入各自路径
# 结果: results/ablation/sift/, results/ablation/gist/
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

GTI_BIN="./GTI/bin/GTI"
L=60
K=10

export GTI_LSH_ENABLED=0
export OMP_NUM_THREADS=1
export GTI_PATCH_DELETE_ONLY=1
export GTI_TREE_PRIORITY_SAME_LEAF=1
export GTI_WOLVERINE_DELETE_MODEL=Wolverine

run_one() {
  local ds_name="$1"
  local base_file="$2"
  local query_file="$3"
  local gt_file="$4"
  local update_ratio="$5"
  local ratio_suffix="$6"
  local mst_use_sampling="$7"
  local mst_full_threshold="$8"
  local mst_sample_size="$9"
  local mst_balance="${10}"
  local use_gist_opts="${11:-0}"

  local RESULTS_ROOT="./results/ablation/${ds_name}"
  local CSV="${RESULTS_ROOT}/ablation_compare.csv"

  if [ ! -f "$base_file" ] || [ ! -f "$query_file" ] || [ ! -f "$gt_file" ]; then
    echo "跳过 ${ds_name}: 数据集文件不完整"
    return 1
  fi

  mkdir -p "$RESULTS_ROOT"
  if [ ! -s "$CSV" ]; then
    echo "variant,aknn_build_s,aknn_search_s,aknn_recall,update_build_s,update_insert_avg_s,update_delete_avg_s,update_final_recall" > "$CSV"
  fi

  export GTI_UPDATE_RATIO="$update_ratio"
  export GTI_SPLIT_STRATEGY=mst
  export GTI_MST_USE_SAMPLING="$mst_use_sampling"
  export GTI_MST_FULL_THRESHOLD="$mst_full_threshold"
  export GTI_MST_SAMPLE_SIZE="$mst_sample_size"
  export GTI_MST_BALANCE_MIN_FRAC="$mst_balance"
  export GTI_MST_SEED=42

  if [ "$use_gist_opts" = "1" ]; then
    export GTI_UPDATE_DELETE_N=2000
    export GTI_DELETE_CHUNK_SIZE=200
  else
    unset GTI_UPDATE_DELETE_N GTI_DELETE_CHUNK_SIZE 2>/dev/null || true
  fi

  local dir="${RESULTS_ROOT}/mst_wolverine_d2"
  rm -rf "$dir"
  mkdir -p "$dir/aknn" "$dir/update"

  echo "=========================================="
  echo "消融: ${ds_name} - MST+Wolverine_d2"
  echo "MST: use_sampling=${mst_use_sampling}, ${mst_full_threshold}/${mst_sample_size}/${mst_balance}"
  echo "结果: $RESULTS_ROOT"
  echo "=========================================="

  echo "========== [${ds_name}][mst_wolverine_d2] A-kNN =========="
  "$GTI_BIN" "$base_file" "$query_file" 0 "$gt_file" "$L" "$K" "$dir/aknn/" 2>&1 | tee "$dir/aknn/run.log"

  echo "========== [${ds_name}][mst_wolverine_d2] Update =========="
  "$GTI_BIN" "$base_file" "$query_file" 3 "$gt_file" "$dir/update/" 2>&1 | tee "$dir/update/run.log"

  local aknn_file="$dir/aknn/cost_${K}_${L}.txt"
  local upd_sum="$dir/update/update_summary_k10_l60_ratio${ratio_suffix}.txt"
  local upd_csv="$dir/update/update_curve_k10_l60_ratio${ratio_suffix}.csv"

  local aknn_build aknn_search aknn_recall upd_build upd_insert upd_delete upd_recall
  aknn_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_search="$(awk -F: '/Search time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_recall="$(awk -F: '/Search recall/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  upd_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_insert="$(awk -F: '/Insert avg time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_delete="$(awk -F: '/Delete avg time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_recall="$(tail -1 "$upd_csv" | awk -F, '{print $5}')"

  echo "mst_wolverine_d2,${aknn_build},${aknn_search},${aknn_recall},${upd_build},${upd_insert},${upd_delete},${upd_recall}" >> "$CSV"

  echo ""
  echo "[${ds_name}] 完成: $CSV"
  column -t -s, "$CSV" 2>/dev/null || cat "$CSV"
}

# ========== Sift: mst_opt = exp2（32/64/0.05 采样），与 mst_param_tuning / ablation_sift_compare 一致 ==========
run_one "sift" \
  "./Datasets/sift/sift/sift_base.fvecs" \
  "./Datasets/sift/sift/sift_query.fvecs" \
  "./Datasets/sift/sift/sift_groundtruth.ivecs" \
  "0.01" "0.010" \
  1 32 64 0.05 \
  "0"

# ========== Gist: mst_full_4 (200/200/0.1), ratio=0.005 ==========
# Gist 专用: 2000 条删除，chunk=200
run_one "gist" \
  "./Datasets/gist/gist_base.fvecs" \
  "./Datasets/gist/gist_query.fvecs" \
  "./Datasets/gist/gist_groundtruth.ivecs" \
  "0.005" "0.005" \
  0 200 200 0.1 \
  "1"

echo ""
echo "=========================================="
echo "Sift + Gist 消融实验完成！"
echo "结果: results/ablation/sift/, results/ablation/gist/"
echo "=========================================="
