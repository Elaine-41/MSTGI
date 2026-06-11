#!/bin/bash
#
# LSH 参数探索脚本（仅跑 LSH，不跑 baseline）
# 1. 探索 ef: 4L, 5L
# 2. 探索 LSH 参数: L, K, seed_count, dim_low
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

GTI_BIN="./GTI/bin/GTI"
L=60
K=10

declare -a DATASETS=(
  "deep|./Datasets/deep/deep1M/deep1M_base.fvecs|./Datasets/deep/deep1M/deep1M_query.fvecs|./Datasets/deep/deep1M/deep1M_groundtruth.ivecs"
  "gist|./Datasets/gist/gist_base.fvecs|./Datasets/gist/gist_query.fvecs|./Datasets/gist/gist_groundtruth.ivecs"
  "sift|./Datasets/sift/sift/sift_base.fvecs|./Datasets/sift/sift/sift_query.fvecs|./Datasets/sift/sift/sift_groundtruth.ivecs"
)

# 配置格式: ef_mult | L_tables | K | seed_count | dim_low | config_id
# ef_mult: 4=4L, 5=5L (5L=baseline)
declare -a CONFIGS=(
  "5|2|4|2|16|ef5L_L2K4s2d16"
  "5|2|4|4|16|ef5L_L2K4s4d16"
  "5|4|4|4|16|ef5L_L4K4s4d16"
  "5|4|4|6|24|ef5L_L4K4s6d24"
  "4|4|4|4|16|ef4L_L4K4s4d16"
  "4|2|4|4|16|ef4L_L2K4s4d16"
)

if [ ! -x "$GTI_BIN" ]; then
  echo "错误: GTI 可执行文件不存在: $GTI_BIN"
  exit 1
fi

RESULTS_ROOT="./results/lsh_experiment"
mkdir -p "$RESULTS_ROOT"
# CSV文件放在summary目录
mkdir -p "${RESULTS_ROOT}/summary"
CSV_FILE="${RESULTS_ROOT}/summary/lsh_param_sweep.csv"
echo "dataset,config_id,ef_mult,lsh_L,lsh_K,lsh_seed,dim_low,run_id,aknn_build_s,aknn_search_s,aknn_recall,update_build_s,update_insert_avg_s_per_item,update_final_recall" > "$CSV_FILE"

run_one () {
  local dataset_name="$1"
  local base_file="$2"
  local query_file="$3"
  local gt_file="$4"
  local ef_mult="$5"
  local lsh_L="$6"
  local lsh_K="$7"
  local lsh_seed="$8"
  local dim_low="$9"
  local config_id="${10}"
  local run_id="${11}"

  # 新路径结构: {dataset}/param_sweep/{config_id}/run{run_id}
  local out_dir="${RESULTS_ROOT}/${dataset_name}/param_sweep/${config_id}/run${run_id}"
  rm -rf "$out_dir"
  mkdir -p "$out_dir/aknn" "$out_dir/update"

  export GTI_SPLIT_STRATEGY="lb"
  export GTI_MST_USE_SAMPLING="0"
  export GTI_MST_FULL_THRESHOLD="200"
  export GTI_MST_SAMPLE_SIZE="300"
  export GTI_MST_BALANCE_MIN_FRAC="0.1"
  export GTI_MST_SEED=42
  export GTI_LSH_ENABLED="1"
  export GTI_LSH_TABLES="$lsh_L"
  export GTI_LSH_K="$lsh_K"
  export GTI_LSH_SEED_COUNT="$lsh_seed"
  export GTI_LSH_DIM_LOW="$dim_low"
  export GTI_LSH_EF_MULTIPLIER="$ef_mult"
  export OMP_NUM_THREADS=4

  echo "========== [${dataset_name}][${config_id}][run${run_id}] A-kNN =========="
  "$GTI_BIN" "$base_file" "$query_file" 0 "$gt_file" "$L" "$K" "$out_dir/aknn/" 2>&1 | tee "$out_dir/aknn/run.log"
  local aknn_file="$out_dir/aknn/cost_${K}_${L}.txt"

  local aknn_build aknn_search aknn_recall
  aknn_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_search="$(awk -F: '/Search time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_recall="$(awk -F: '/Search recall/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"

  echo "========== [${dataset_name}][${config_id}][run${run_id}] Update =========="
  "$GTI_BIN" "$base_file" "$query_file" 3 "$gt_file" "$out_dir/update/" 2>&1 | tee "$out_dir/update/run.log"
  local upd_sum="$out_dir/update/update_summary_k10_l60_ratio0.005.txt"
  local upd_csv="$out_dir/update/update_curve_k10_l60_ratio0.005.csv"
  local upd_build upd_insert_avg upd_final_recall
  upd_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_insert_avg="$(awk -F: '/Insert avg time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_final_recall="$(tail -1 "$upd_csv" | awk -F, '{print $5}')"

  echo "${dataset_name},${config_id},${ef_mult},${lsh_L},${lsh_K},${lsh_seed},${dim_low},${run_id},${aknn_build},${aknn_search},${aknn_recall},${upd_build},${upd_insert_avg},${upd_final_recall}" >> "$CSV_FILE"
}

echo ""
echo "=========================================="
echo "LSH 参数探索 (仅 LSH，不跑 baseline)"
echo "=========================================="
echo ""

for ds_line in "${DATASETS[@]}"; do
  IFS='|' read -r ds_name base_file query_file gt_file <<< "$ds_line"

  if [ ! -f "$base_file" ] || [ ! -f "$query_file" ] || [ ! -f "$gt_file" ]; then
    echo "跳过 $ds_name: 数据集文件不完整"
    continue
  fi

  echo "=========================================="
  echo "数据集: $ds_name"
  echo "=========================================="

  for cfg_idx in "${!CONFIGS[@]}"; do
    IFS='|' read -r ef_mult lsh_L lsh_K lsh_seed dim_low config_id <<< "${CONFIGS[$cfg_idx]}"
    echo "  [${config_id}] run 1/2..."
    run_one "$ds_name" "$base_file" "$query_file" "$gt_file" "$ef_mult" "$lsh_L" "$lsh_K" "$lsh_seed" "$dim_low" "$config_id" "1"
    echo "  [${config_id}] run 2/2..."
    run_one "$ds_name" "$base_file" "$query_file" "$gt_file" "$ef_mult" "$lsh_L" "$lsh_K" "$lsh_seed" "$dim_low" "$config_id" "2"
  done
  echo ""
done

echo ""
echo "=========================================="
echo "实验完成！结果: $CSV_FILE"
echo "=========================================="
echo ""

echo "按数据集和配置汇总 (2次平均):"
echo "=========================================="
for ds in deep gist sift; do
  echo ""
  echo "--- $ds ---"
  for cfg in "${CONFIGS[@]}"; do
    config_id=$(echo "$cfg" | cut -d'|' -f6)
    awk -F',' -v ds="$ds" -v cfg="$config_id" 'NR>1 && $1==ds && $2==cfg {build+=$9; search+=$10; recall+=$11; count++} END {if(count>0) printf "  %s: Build %.1fs  Search %.4fs  Recall %.3f\n", cfg, build/count, search/count, recall/count}' "$CSV_FILE"
  done
done
