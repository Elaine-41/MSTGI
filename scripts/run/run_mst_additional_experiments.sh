#!/bin/bash
#
# 运行额外的MST参数调优实验
# 1. mst_full策略（use_sampling=0）的新参数组合
# 2. mst_sample策略的新参数组合（针对不同数据集）
# 每组参数运行3次重复
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

# 输出CSV文件
CSV_ALL="${RESULTS_ROOT}/mst_param_tuning_all1.csv"
CSV_TEMP="${RESULTS_ROOT}/mst_param_tuning_all1_temp.csv"

# 读取已有的实验结果
EXISTING_CSV="${RESULTS_ROOT}/mst_param_tuning_all.csv"
if [ -f "$EXISTING_CSV" ]; then
  echo "读取已有实验结果..."
  # 复制已有数据（包含标题行）
  cp "$EXISTING_CSV" "$CSV_ALL"
else
  # 如果没有已有文件，创建新的标题行
  echo "dataset,variant,run_id,split_strategy,use_sampling,full_threshold,sample_size,balance_min_frac,aknn_build_s,aknn_search_s,aknn_recall,update_build_s,update_insert_avg_s_per_item,update_final_recall" > "$CSV_ALL"
fi

# 临时文件用于追加新结果（先清空）
> "$CSV_TEMP"

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

  echo "${dataset_name},${variant},${run_id},${split_strategy},${use_sampling},${full_threshold},${sample_size},${balance_min_frac},${aknn_build},${aknn_search},${aknn_recall},${upd_build},${upd_insert_avg},${upd_final_recall}" >> "$CSV_TEMP"
}

# 遍历所有数据集
for dataset_config in "${DATASETS[@]}"; do
  IFS=':' read -r dataset_name base_file query_file gt_file <<< "$dataset_config"
  
  echo ""
  echo "=========================================="
  echo "处理数据集: ${dataset_name}"
  echo "=========================================="
  
  # mst_full策略的实验配置（use_sampling=0）
  # 格式: variant_name:full_threshold:sample_size:balance_min_frac
  declare -a MST_FULL_EXPERIMENTS=(
    "mst_full_orig:200:300:0.1"
    "mst_full_1:200:300:0.2"
    "mst_full_2:200:300:0.05"
    "mst_full_3:300:300:0.1"
    "mst_full_4:200:200:0.1"
  )
  
  # mst_sample策略的实验配置（use_sampling=1），根据数据集不同
  declare -a MST_SAMPLE_EXPERIMENTS
  case "$dataset_name" in
    "deep")
      MST_SAMPLE_EXPERIMENTS=(
        "mst_sample_deep_1:64:96:0.05"
        "mst_sample_deep_2:64:64:0.1"
      )
      ;;
    "gist")
      MST_SAMPLE_EXPERIMENTS=(
        "mst_sample_gist_1:32:48:0.05"
        "mst_sample_gist_2:32:64:0.03"
        "mst_sample_gist_3:48:64:0.05"
        "mst_sample_gist_4:64:64:0.1"
      )
      ;;
    "sift")
      MST_SAMPLE_EXPERIMENTS=(
        "mst_sample_sift_1:32:32:0.05"
        "mst_sample_sift_2:16:32:0.05"
      )
      ;;
  esac
  
  # 运行 mst_full 实验
  echo ""
  echo "运行 mst_full 策略实验..."
  for exp_config in "${MST_FULL_EXPERIMENTS[@]}"; do
    IFS=':' read -r variant full_threshold sample_size balance_min_frac <<< "$exp_config"
    
    echo ""
    echo "运行实验: ${variant} (mst_full, use_sampling=0, full_threshold=${full_threshold}, sample_size=${sample_size}, balance_min_frac=${balance_min_frac})"
    
    # 每组跑3次
    for run_id in 1 2 3; do
      echo "  Run ${run_id}/3..."
      if run_one "$dataset_name" "$base_file" "$query_file" "$gt_file" "$variant" "mst" "0" "$full_threshold" "$sample_size" "$balance_min_frac" "$run_id"; then
        echo "    完成"
      fi
    done
  done
  
  # 运行 mst_sample 实验
  echo ""
  echo "运行 mst_sample 策略实验..."
  for exp_config in "${MST_SAMPLE_EXPERIMENTS[@]}"; do
    IFS=':' read -r variant full_threshold sample_size balance_min_frac <<< "$exp_config"
    
    echo ""
    echo "运行实验: ${variant} (mst_sample, use_sampling=1, full_threshold=${full_threshold}, sample_size=${sample_size}, balance_min_frac=${balance_min_frac})"
    
    # 每组跑3次
    for run_id in 1 2 3; do
      echo "  Run ${run_id}/3..."
      if run_one "$dataset_name" "$base_file" "$query_file" "$gt_file" "$variant" "mst" "1" "$full_threshold" "$sample_size" "$balance_min_frac" "$run_id"; then
        echo "    完成"
      fi
    done
  done
  
  echo ""
  echo "数据集 ${dataset_name} 完成"
done

# 合并新结果到最终文件
if [ -s "$CSV_TEMP" ]; then
  echo ""
  echo "合并新实验结果..."
  cat "$CSV_TEMP" >> "$CSV_ALL"
  rm -f "$CSV_TEMP"
fi

echo ""
echo "=========================================="
echo "所有额外实验完成！"
echo "结果已保存到: $CSV_ALL"
echo "（包含已有实验结果 + 新增实验结果）"
echo "=========================================="
