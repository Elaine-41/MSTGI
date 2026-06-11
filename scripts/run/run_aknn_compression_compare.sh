#!/bin/bash
#
# A-kNN 向量压缩开启/关闭对比
# - Sift: 向量压缩关闭（GTI_SHG_FULL_DIM_LEVEL_SKIP=1）
# - Deep: 向量压缩开启（默认）与 向量压缩关闭（GTI_SHG_FULL_DIM_LEVEL_SKIP=1）
# SHG 统一采用：插入后 rebuild + 65% 采样（GTI_SHG_REBUILD_AFTER_INSERT=1, GTI_SHG_SHORTCUT_SAMPLE_RATIO=0.65）
# 输出: n2, wolverine, shg 的 aknn_build_s, aknn_search_s, aknn_recall
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

L=60
K=10

# 与 MST 实验一致
export GTI_SPLIT_STRATEGY=lb
export GTI_LSH_ENABLED=0
export OMP_NUM_THREADS=1

# 数据集配置: 名称|base|query|gt
SIFT_BASE="./Datasets/sift/sift/sift_base.fvecs"
SIFT_QUERY="./Datasets/sift/sift/sift_query.fvecs"
SIFT_GT="./Datasets/sift/sift/sift_groundtruth.ivecs"

DEEP_BASE="./Datasets/deep/deep1M/deep1M_base.fvecs"
DEEP_QUERY="./Datasets/deep/deep1M/deep1M_query.fvecs"
DEEP_GT="./Datasets/deep/deep1M/deep1M_groundtruth.ivecs"

run_aknn() {
  local bin="$1"
  local backend="$2"
  local base="$3"
  local query="$4"
  local gt="$5"
  local out_dir="$6"

  mkdir -p "$out_dir"

  if [ ! -x "$bin" ]; then
    echo "跳过 ${backend}: 可执行文件不存在 $bin"
    return 1
  fi

  echo "========== ${backend} A-kNN =========="
  "$bin" "$base" "$query" 0 "$gt" "$L" "$K" "$out_dir/" 2>&1 | tee "$out_dir/run.log"

  local cost_file="$out_dir/cost_${K}_${L}.txt"
  if [ ! -f "$cost_file" ]; then
    echo "错误: 未生成 $cost_file"
    return 1
  fi

  local aknn_build aknn_search aknn_recall
  aknn_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); gsub(/s$/,"",$2); print $2}' "$cost_file" | tail -1)"
  aknn_search="$(awk -F: '/Search time/ {gsub(/^[ \t]+/,"",$2); gsub(/s$/,"",$2); print $2}' "$cost_file" | tail -1)"
  aknn_recall="$(awk -F: '/Search recall/ {gsub(/^[ \t]+/,"",$2); print $2}' "$cost_file" | tail -1)"

  echo "${aknn_build}|${aknn_search}|${aknn_recall}"
}

run_dataset() {
  local dataset="$1"
  local base query gt
  local results_root csv_name

  case "$dataset" in
    sift)
      base="$SIFT_BASE"
      query="$SIFT_QUERY"
      gt="$SIFT_GT"
      results_root="./results/sift/aknn_compare"
      ;;
    deep)
      base="$DEEP_BASE"
      query="$DEEP_QUERY"
      gt="$DEEP_GT"
      results_root="./results/deep/aknn_compare"
      ;;
    *)
      echo "未知数据集: $dataset"
      return 1
      ;;
  esac

  local compression="$2"  # on 或 off
  local suffix="comp_${compression}"
  mkdir -p "$results_root"

  local csv="${results_root}/aknn_compare_${suffix}.csv"
  echo "dataset,compression,backend,aknn_build_s,aknn_search_s,aknn_recall" > "$csv"

  if [ "$compression" = "off" ]; then
    export GTI_SHG_FULL_DIM_LEVEL_SKIP=1
  else
    unset GTI_SHG_FULL_DIM_LEVEL_SKIP
  fi

  # n2
  local out_n2="${results_root}/n2_${suffix}"
  local res
  res=$(run_aknn "./GTI/bin/GTI_n2" "n2" "$base" "$query" "$gt" "$out_n2" | tail -1)
  [ -n "$res" ] && echo "${dataset},${compression},n2,${res//|/,}" >> "$csv"
  echo ""

  # wolverine
  local out_wol="${results_root}/wolverine_${suffix}"
  res=$(run_aknn "./GTI/bin/GTI" "wolverine" "$base" "$query" "$gt" "$out_wol" | tail -1)
  [ -n "$res" ] && echo "${dataset},${compression},wolverine,${res//|/,}" >> "$csv"
  echo ""

  # shg
  local out_shg="${results_root}/shg_${suffix}"
  res=$(run_aknn "./GTI/bin/GTI_shg" "shg" "$base" "$query" "$gt" "$out_shg" | tail -1)
  [ -n "$res" ] && echo "${dataset},${compression},shg,${res//|/,}" >> "$csv"
  echo ""

  unset GTI_SHG_FULL_DIM_LEVEL_SKIP

  echo "结果已保存: $csv"
  [ -f "$csv" ] && column -t -s, "$csv" 2>/dev/null || cat "$csv"
  echo ""
}

echo "=========================================="
echo "A-kNN 向量压缩对比实验"
echo "=========================================="
echo ""

# 1. Sift 向量压缩关闭
echo ">>> [1/3] Sift 向量压缩关闭 (GTI_SHG_FULL_DIM_LEVEL_SKIP=1)"
run_dataset "sift" "off"

# 2. Deep 向量压缩开启（默认）
echo ">>> [2/3] Deep 向量压缩开启 (默认)"
run_dataset "deep" "on"

# 3. Deep 向量压缩关闭
echo ">>> [3/3] Deep 向量压缩关闭 (GTI_SHG_FULL_DIM_LEVEL_SKIP=1)"
run_dataset "deep" "off"

echo "=========================================="
echo "完成"
echo "=========================================="
echo ""
echo "结果文件:"
echo "  Sift 压缩关闭: results/sift/aknn_compare/aknn_compare_comp_off.csv"
echo "  Deep 压缩开启: results/deep/aknn_compare/aknn_compare_comp_on.csv"
echo "  Deep 压缩关闭: results/deep/aknn_compare/aknn_compare_comp_off.csv"
echo ""
echo "现有 Sift 压缩开启: results/sift/aknn_compare/aknn_compare.csv (已有)"
echo ""
