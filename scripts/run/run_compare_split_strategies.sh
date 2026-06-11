#!/bin/bash
#
# Compare split strategies across multiple datasets:
#   - baseline (promoteLb)
#   - MST-full (promote_mst, no sampling)
#   - MST-sampling (forced by low threshold + sample)
#
# Datasets: deep, gist, sift
# Output: CSV with AkNN and Update metrics for each dataset.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

GTI_BIN="./GTI/bin/GTI"
L=60
K=10

# 数据集配置: name,base_path,query_path,gt_path
declare -a DATASETS=(
  "deep:./Datasets/deep/deep1M/deep1M_base.fvecs:./Datasets/deep/deep1M/deep1M_query.fvecs:./Datasets/deep/deep1M/deep1M_groundtruth.ivecs"
  "gist:./Datasets/gist/gist_base.fvecs:./Datasets/gist/gist_query.fvecs:./Datasets/gist/gist_groundtruth.ivecs"
  "sift:./Datasets/sift/sift/sift_base.fvecs:./Datasets/sift/sift/sift_query.fvecs:./Datasets/sift/sift/sift_groundtruth.ivecs"
)

if [ ! -x "$GTI_BIN" ]; then
  echo "错误: GTI 可执行文件不存在或不可执行: $GTI_BIN"
  exit 1
fi

# 创建总结果目录
RESULTS_ROOT="./results/split_compare"
mkdir -p "$RESULTS_ROOT"

# 合并的 CSV（包含所有数据集）
CSV_ALL="${RESULTS_ROOT}/compare_split_strategies_all.csv"
echo "dataset,variant,split_strategy,use_sampling,full_threshold,sample_size,balance_min_frac,aknn_build_s,aknn_search_s,aknn_recall,update_build_s,update_insert_avg_s_per_item,update_final_recall" > "$CSV_ALL"

run_one () {
  local dataset_name="$1"
  local base_file="$2"
  local query_file="$3"
  local gt_file="$4"
  local variant="$5"
  local split_strategy="$6"
  local use_sampling="$7"
  local full_threshold="$8"
  local sample_size="$9"
  local balance_min_frac="${10}"

  local out_dir="${RESULTS_ROOT}/${dataset_name}"
  local dir="${out_dir}/${variant}"
  rm -rf "$dir"
  mkdir -p "$dir/aknn" "$dir/update"

  # 检查数据集文件是否存在
  if [ ! -f "$base_file" ] || [ ! -f "$query_file" ] || [ ! -f "$gt_file" ]; then
    echo "警告: 数据集 ${dataset_name} 文件不完整，跳过"
    return 1
  fi

  # env config for GTI
  export GTI_SPLIT_STRATEGY="$split_strategy"
  export GTI_MST_USE_SAMPLING="$use_sampling"
  export GTI_MST_FULL_THRESHOLD="$full_threshold"
  export GTI_MST_SAMPLE_SIZE="$sample_size"
  export GTI_MST_BALANCE_MIN_FRAC="$balance_min_frac"
  export GTI_MST_SEED=42
  export OMP_NUM_THREADS=1

  echo "========== [${dataset_name}][${variant}] A-kNN =========="
  "$GTI_BIN" "$base_file" "$query_file" 0 "$gt_file" "$L" "$K" "$dir/aknn/"
  local aknn_file="$dir/aknn/cost_${K}_${L}.txt"
  local aknn_build aknn_search aknn_recall
  aknn_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_search="$(awk -F: '/Search time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_recall="$(awk -F: '/Search recall/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"

  echo "========== [${dataset_name}][${variant}] Update =========="
  "$GTI_BIN" "$base_file" "$query_file" 3 "$gt_file" "$dir/update/"
  local upd_sum="$dir/update/update_summary_k10_l60_ratio0.005.txt"
  local upd_csv="$dir/update/update_curve_k10_l60_ratio0.005.csv"
  local upd_build upd_insert_avg upd_final_recall
  upd_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_insert_avg="$(awk -F: '/Insert avg time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_final_recall="$(tail -1 "$upd_csv" | awk -F, '{print $5}')"

  echo "${dataset_name},${variant},${split_strategy},${use_sampling},${full_threshold},${sample_size},${balance_min_frac},${aknn_build},${aknn_search},${aknn_recall},${upd_build},${upd_insert_avg},${upd_final_recall}" >> "$CSV_ALL"
}

# 遍历所有数据集
for dataset_config in "${DATASETS[@]}"; do
  IFS=':' read -r dataset_name base_file query_file gt_file <<< "$dataset_config"
  
  echo ""
  echo "=========================================="
  echo "处理数据集: ${dataset_name}"
  echo "=========================================="
  
  # 为每个数据集创建单独的 CSV
  CSV_DATASET="${RESULTS_ROOT}/${dataset_name}/compare_split_strategies.csv"
  mkdir -p "$(dirname "$CSV_DATASET")"
  echo "variant,split_strategy,use_sampling,full_threshold,sample_size,balance_min_frac,aknn_build_s,aknn_search_s,aknn_recall,update_build_s,update_insert_avg_s_per_item,update_final_recall" > "$CSV_DATASET"
  
  # Baseline
  echo "运行 baseline_lb..."
  if run_one "$dataset_name" "$base_file" "$query_file" "$gt_file" "baseline_lb" "lb" 0 200 300 0.1; then
    tail -1 "$CSV_ALL" >> "$CSV_DATASET"
  fi

  # MST-full
  echo "运行 mst_full..."
  if run_one "$dataset_name" "$base_file" "$query_file" "$gt_file" "mst_full" "mst" 0 200 300 0.1; then
    tail -1 "$CSV_ALL" >> "$CSV_DATASET"
  fi

  # MST-sampling
  echo "运行 mst_sampling..."
  if run_one "$dataset_name" "$base_file" "$query_file" "$gt_file" "mst_sampling" "mst" 1 32 32 0.1; then
    tail -1 "$CSV_ALL" >> "$CSV_DATASET"
  fi
  
  echo "数据集 ${dataset_name} 完成，结果已写入: $CSV_DATASET"
done

echo ""
echo "=========================================="
echo "所有数据集对比完成！"
echo "合并结果: $CSV_ALL"
echo "各数据集结果: ${RESULTS_ROOT}/*/compare_split_strategies.csv"
echo "=========================================="
