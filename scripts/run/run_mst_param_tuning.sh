#!/bin/bash
#
# MST参数调优实验脚本
# 运行8组实验，每组3次（固定seed），取均值
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

# 创建结果目录
RESULTS_ROOT="./results/split_compare/mst_param_tuning"
mkdir -p "$RESULTS_ROOT"

# 合并的 CSV（包含所有数据集）
CSV_ALL="${RESULTS_ROOT}/mst_param_tuning_all.csv"
echo "dataset,variant,run_id,split_strategy,use_sampling,full_threshold,sample_size,balance_min_frac,aknn_build_s,aknn_search_s,aknn_recall,update_build_s,update_insert_avg_s_per_item,update_final_recall" > "$CSV_ALL"

# 实验配置: variant_name,split_strategy,use_sampling,full_threshold,sample_size,balance_min_frac
declare -a EXPERIMENTS=(
  "baseline:lb:0:200:300:0.1"
  "exp2:mst:1:32:64:0.05"
  "exp3:mst:1:32:128:0.05"
  "exp4:mst:1:64:64:0.05"
  "exp5:mst:1:64:128:0.05"
  "exp6:mst:1:128:128:0.05"
  "exp7:mst:1:32:64:0.01"
  "exp8:mst:1:32:64:0.10"
)

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
  local run_id="${11}"

  local out_dir="${RESULTS_ROOT}/${dataset_name}"
  local dir="${out_dir}/${variant}_run${run_id}"
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

  echo "========== [${dataset_name}][${variant}][run${run_id}] A-kNN =========="
  "$GTI_BIN" "$base_file" "$query_file" 0 "$gt_file" "$L" "$K" "$dir/aknn/" 2>&1 | tee "$dir/aknn/run.log"
  local aknn_file="$dir/aknn/cost_${K}_${L}.txt"
  
  # 从日志中提取实际配置（如果存在）
  local actual_config=""
  if [ -f "$dir/aknn/run.log" ]; then
    actual_config="$(grep -m1 "^MST_CONFIG:" "$dir/aknn/run.log" || echo "")"
    if [ -n "$actual_config" ]; then
      echo "实际配置: $actual_config"
    fi
  fi
  
  local aknn_build aknn_search aknn_recall
  aknn_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_search="$(awk -F: '/Search time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_recall="$(awk -F: '/Search recall/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"

  echo "========== [${dataset_name}][${variant}][run${run_id}] Update =========="
  "$GTI_BIN" "$base_file" "$query_file" 3 "$gt_file" "$dir/update/" 2>&1 | tee "$dir/update/run.log"
  local upd_sum="$dir/update/update_summary_k10_l60_ratio0.005.txt"
  local upd_csv="$dir/update/update_curve_k10_l60_ratio0.005.csv"
  local upd_build upd_insert_avg upd_final_recall
  upd_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_insert_avg="$(awk -F: '/Insert avg time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_final_recall="$(tail -1 "$upd_csv" | awk -F, '{print $5}')"

  echo "${dataset_name},${variant},${run_id},${split_strategy},${use_sampling},${full_threshold},${sample_size},${balance_min_frac},${aknn_build},${aknn_search},${aknn_recall},${upd_build},${upd_insert_avg},${upd_final_recall}" >> "$CSV_ALL"
}

# 遍历所有数据集
for dataset_config in "${DATASETS[@]}"; do
  IFS=':' read -r dataset_name base_file query_file gt_file <<< "$dataset_config"
  
  echo ""
  echo "=========================================="
  echo "处理数据集: ${dataset_name}"
  echo "=========================================="
  
  # 为每个数据集创建单独的 CSV
  CSV_DATASET="${RESULTS_ROOT}/${dataset_name}/mst_param_tuning.csv"
  mkdir -p "$(dirname "$CSV_DATASET")"
  echo "variant,run_id,split_strategy,use_sampling,full_threshold,sample_size,balance_min_frac,aknn_build_s,aknn_search_s,aknn_recall,update_build_s,update_insert_avg_s_per_item,update_final_recall" > "$CSV_DATASET"
  
  # 遍历所有实验配置
  for exp_config in "${EXPERIMENTS[@]}"; do
    IFS=':' read -r variant split_strategy use_sampling full_threshold sample_size balance_min_frac <<< "$exp_config"
    
    echo ""
    echo "运行实验: ${variant} (${split_strategy}, use_sampling=${use_sampling}, full_threshold=${full_threshold}, sample_size=${sample_size}, balance_min_frac=${balance_min_frac})"
    
    # 每组跑3次
    for run_id in 1 2 3; do
      echo "  Run ${run_id}/3..."
      if run_one "$dataset_name" "$base_file" "$query_file" "$gt_file" "$variant" "$split_strategy" "$use_sampling" "$full_threshold" "$sample_size" "$balance_min_frac" "$run_id"; then
        tail -1 "$CSV_ALL" >> "$CSV_DATASET"
      fi
    done
  done
  
  echo ""
  echo "数据集 ${dataset_name} 完成，结果已写入: $CSV_DATASET"
done

echo ""
echo "=========================================="
echo "所有实验完成！"
echo "合并结果: $CSV_ALL"
echo "各数据集结果: ${RESULTS_ROOT}/*/mst_param_tuning.csv"
echo "=========================================="
