#!/bin/bash
#
# 三数据集 LSH 对比实验
# 比较 deep, gist, sift 在 baseline（无LSH）与 +LSH 下的性能
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

GTI_BIN="./GTI/bin/GTI"
L=60
K=10

# 数据集配置: 名称 base query groundtruth
declare -a DATASETS=(
  "deep|./Datasets/deep/deep1M/deep1M_base.fvecs|./Datasets/deep/deep1M/deep1M_query.fvecs|./Datasets/deep/deep1M/deep1M_groundtruth.ivecs"
  "gist|./Datasets/gist/gist_base.fvecs|./Datasets/gist/gist_query.fvecs|./Datasets/gist/gist_groundtruth.ivecs"
  "sift|./Datasets/sift/sift/sift_base.fvecs|./Datasets/sift/sift/sift_query.fvecs|./Datasets/sift/sift/sift_groundtruth.ivecs"
)

if [ ! -x "$GTI_BIN" ]; then
  echo "错误: GTI 可执行文件不存在或不可执行: $GTI_BIN"
  exit 1
fi

# 创建结果目录
RESULTS_ROOT="./results/lsh_experiment"
mkdir -p "$RESULTS_ROOT"

# 结果CSV文件
CSV_FILE="${RESULTS_ROOT}/lsh_multi_dataset_comparison.csv"
echo "dataset,variant,run_id,split_strategy,use_sampling,full_threshold,sample_size,balance_min_frac,lsh_enabled,lsh_tables,lsh_k,lsh_seed_count,ef_seed,aknn_build_s,aknn_search_s,aknn_recall,update_build_s,update_insert_avg_s_per_item,update_final_recall" > "$CSV_FILE"

run_one () {
  local dataset_name="$1"
  local base_file="$2"
  local query_file="$3"
  local gt_file="$4"
  local variant="$5"
  local lsh_enabled="$6"
  local run_id="$7"
  
  local out_dir="${RESULTS_ROOT}/${dataset_name}_${variant}_run${run_id}"
  rm -rf "$out_dir"
  mkdir -p "$out_dir/aknn" "$out_dir/update"

  export GTI_SPLIT_STRATEGY="lb"
  export GTI_MST_USE_SAMPLING="0"
  export GTI_MST_FULL_THRESHOLD="200"
  export GTI_MST_SAMPLE_SIZE="300"
  export GTI_MST_BALANCE_MIN_FRAC="0.1"
  export GTI_MST_SEED=42
  export GTI_LSH_ENABLED="$lsh_enabled"
  export GTI_LSH_TABLES="2"
  export GTI_LSH_K="4"
  export GTI_LSH_SEED_COUNT="2"
  export GTI_LSH_DIM_LOW="16"
  export GTI_LSH_EF_SEED="32"
  export GTI_LSH_EF_MULTIPLIER="5"
  export OMP_NUM_THREADS=4

  echo "========== [${dataset_name}][${variant}][run${run_id}] A-kNN =========="
  echo "LSH enabled: $lsh_enabled"
  "$GTI_BIN" "$base_file" "$query_file" 0 "$gt_file" "$L" "$K" "$out_dir/aknn/" 2>&1 | tee "$out_dir/aknn/run.log"
  local aknn_file="$out_dir/aknn/cost_${K}_${L}.txt"
  
  local aknn_build aknn_search aknn_recall
  aknn_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_search="$(awk -F: '/Search time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_recall="$(awk -F: '/Search recall/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"

  echo "========== [${dataset_name}][${variant}][run${run_id}] Update =========="
  "$GTI_BIN" "$base_file" "$query_file" 3 "$gt_file" "$out_dir/update/" 2>&1 | tee "$out_dir/update/run.log"
  local upd_sum="$out_dir/update/update_summary_k10_l60_ratio0.005.txt"
  local upd_csv="$out_dir/update/update_curve_k10_l60_ratio0.005.csv"
  local upd_build upd_insert_avg upd_final_recall
  upd_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_insert_avg="$(awk -F: '/Insert avg time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_final_recall="$(tail -1 "$upd_csv" | awk -F, '{print $5}')"

  echo "${dataset_name},${variant},${run_id},lb,0,200,300,0.1,${lsh_enabled},2,4,2,32,${aknn_build},${aknn_search},${aknn_recall},${upd_build},${upd_insert_avg},${upd_final_recall}" >> "$CSV_FILE"
}

echo ""
echo "=========================================="
echo "三数据集 LSH 对比实验 (deep, gist, sift)"
echo "=========================================="
echo ""

for ds_line in "${DATASETS[@]}"; do
  IFS='|' read -r ds_name base_file query_file gt_file <<< "$ds_line"
  
  if [ ! -f "$base_file" ] || [ ! -f "$query_file" ] || [ ! -f "$gt_file" ]; then
    echo "跳过 $ds_name: 数据集文件不完整"
    echo "  BASE: $base_file"
    echo "  QUERY: $query_file"
    echo "  GT: $gt_file"
    continue
  fi
  
  echo "=========================================="
  echo "数据集: $ds_name"
  echo "=========================================="
  
  echo "  [lsh] LSH 启用 (run 1/2)..."
  run_one "$ds_name" "$base_file" "$query_file" "$gt_file" "lsh" "1" "1"
  echo "  [lsh] LSH 启用 (run 2/2)..."
  run_one "$ds_name" "$base_file" "$query_file" "$gt_file" "lsh" "1" "2"
  
  echo ""
done

echo ""
echo "=========================================="
echo "实验完成！"
echo "结果文件: $CSV_FILE"
echo "=========================================="
echo ""

echo "结果摘要:"
echo "=========================================="
cat "$CSV_FILE" | column -t -s','

echo ""
echo "按数据集汇总 (2次取平均):"
echo "=========================================="
for ds in deep gist sift; do
  echo ""
  echo "--- $ds ---"
  echo "LSH (ef=5L, L=2,K=4,seed=2,dim_low=16):"
  awk -F',' -v ds="$ds" 'NR>1 && $1==ds && $2=="lsh" {build+=$14; search+=$15; recall+=$16; count++} END {if(count>0) printf "  Build: %.3f s  Search: %.6f s  Recall: %.6f\n", build/count, search/count, recall/count}' "$CSV_FILE"
done
