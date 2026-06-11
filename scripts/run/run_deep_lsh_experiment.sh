#!/bin/bash
#
# Deep数据集LSH实验脚本
# 对比baseline（不使用LSH）和+LSH版本的性能
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

GTI_BIN="./GTI/bin/GTI"
L=60
K=10

# Deep数据集路径
DATASET_NAME="deep"
BASE_FILE="./Datasets/deep/deep1M/deep1M_base.fvecs"
QUERY_FILE="./Datasets/deep/deep1M/deep1M_query.fvecs"
GT_FILE="./Datasets/deep/deep1M/deep1M_groundtruth.ivecs"

if [ ! -x "$GTI_BIN" ]; then
  echo "错误: GTI 可执行文件不存在或不可执行: $GTI_BIN"
  exit 1
fi

# 检查数据集文件
if [ ! -f "$BASE_FILE" ] || [ ! -f "$QUERY_FILE" ] || [ ! -f "$GT_FILE" ]; then
  echo "错误: 数据集文件不完整"
  echo "BASE: $BASE_FILE"
  echo "QUERY: $QUERY_FILE"
  echo "GT: $GT_FILE"
  exit 1
fi

# 创建结果目录
RESULTS_ROOT="./results/lsh_experiment"
mkdir -p "$RESULTS_ROOT"
# CSV文件放在summary目录
mkdir -p "${RESULTS_ROOT}/summary"
CSV_FILE="${RESULTS_ROOT}/summary/${DATASET_NAME}_lsh_comparison.csv"
echo "dataset,variant,run_id,split_strategy,use_sampling,full_threshold,sample_size,balance_min_frac,lsh_enabled,lsh_tables,lsh_k,lsh_seed_count,ef_seed,aknn_build_s,aknn_search_s,aknn_recall,update_build_s,update_insert_avg_s_per_item,update_final_recall" > "$CSV_FILE"

run_one () {
  local variant="$1"
  local lsh_enabled="$2"
  local run_id="$3"
  
  # 新路径结构: {dataset}/lsh_comparison/run{run_id}
  local out_dir="${RESULTS_ROOT}/${DATASET_NAME}/lsh_comparison/run${run_id}"
  rm -rf "$out_dir"
  mkdir -p "$out_dir/aknn" "$out_dir/update"

  # 设置环境变量
  export GTI_SPLIT_STRATEGY="lb"
  export GTI_MST_USE_SAMPLING="0"
  export GTI_MST_FULL_THRESHOLD="200"
  export GTI_MST_SAMPLE_SIZE="300"
  export GTI_MST_BALANCE_MIN_FRAC="0.1"
  export GTI_MST_SEED=42
  
  # LSH配置（轻量化: L=2,K=4,seed=2）
  export GTI_LSH_ENABLED="$lsh_enabled"
  export GTI_LSH_TABLES="2"
  export GTI_LSH_K="4"
  export GTI_LSH_SEED_COUNT="2"
  export GTI_LSH_EF_SEED="32"
  
  export OMP_NUM_THREADS=4

  echo "========== [${variant}][run${run_id}] A-kNN =========="
  echo "LSH enabled: $lsh_enabled"
  "$GTI_BIN" "$BASE_FILE" "$QUERY_FILE" 0 "$GT_FILE" "$L" "$K" "$out_dir/aknn/" 2>&1 | tee "$out_dir/aknn/run.log"
  local aknn_file="$out_dir/aknn/cost_${K}_${L}.txt"
  
  local aknn_build aknn_search aknn_recall
  aknn_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_search="$(awk -F: '/Search time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_recall="$(awk -F: '/Search recall/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"

  echo "========== [${variant}][run${run_id}] Update =========="
  "$GTI_BIN" "$BASE_FILE" "$QUERY_FILE" 3 "$GT_FILE" "$out_dir/update/" 2>&1 | tee "$out_dir/update/run.log"
  local upd_sum="$out_dir/update/update_summary_k10_l60_ratio0.005.txt"
  local upd_csv="$out_dir/update/update_curve_k10_l60_ratio0.005.csv"
  local upd_build upd_insert_avg upd_final_recall
  upd_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_insert_avg="$(awk -F: '/Insert avg time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_final_recall="$(tail -1 "$upd_csv" | awk -F, '{print $5}')"

  echo "${DATASET_NAME},${variant},${run_id},lb,0,200,300,0.1,${lsh_enabled},2,4,2,32,${aknn_build},${aknn_search},${aknn_recall},${upd_build},${upd_insert_avg},${upd_final_recall}" >> "$CSV_FILE"
}

echo ""
echo "=========================================="
echo "Deep数据集LSH对比实验"
echo "=========================================="
echo ""

# 仅运行LSH验证（跳过baseline）
echo "运行LSH实验（LSH启用，轻量化参数 L=2,K=4,seed=2）..."
for run_id in 1 2 3; do
  echo "  Run ${run_id}/3..."
  run_one "lsh" "1" "$run_id"
done

echo ""
echo "=========================================="
echo "实验完成！"
echo "结果文件: $CSV_FILE"
echo "=========================================="
echo ""

# 显示结果摘要
echo "结果摘要:"
echo "=========================================="
cat "$CSV_FILE" | column -t -s','

echo ""
echo "LSH (轻量化 L=2,K=4,seed=2):"
awk -F',' 'NR>1 && $2=="lsh" {build+=$14; search+=$15; recall+=$16; count++} END {if(count>0) printf "  Build: %.3f s\n  Search: %.6f s\n  Recall: %.6f\n", build/count, search/count, recall/count}' "$CSV_FILE"
