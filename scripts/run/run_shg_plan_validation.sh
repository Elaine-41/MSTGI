#!/bin/bash
#
# SHG Plan 未完成项验证：sift + deep 数据集
# 基线配置：插入后 rebuild + 65% 采样（先前验证效果不错）
# 验证 S4 (GTI_SHG_PRUNE=0)，若效果变差则回滚
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

# SHG 基线配置（插入后 rebuild + 65% 采样）
# prune0 使用优化参数 m24_efb80_efs80（见 SHG_PLAN_PROGRESS_ANALYSIS 第八节、SHG_prune0.md 第九章）
SHG_BASELINE_ENV=(
  "GTI_SHG_REBUILD_AFTER_INSERT=1"
  "GTI_SHG_SHORTCUT_SAMPLE_RATIO=0.65"
  "GTI_SHG_M=24"
  "GTI_SHG_EF_BUILD=80"
  "GTI_SHG_EF_SEARCH=80"
)

export GTI_LSH_ENABLED=0
export GTI_SPLIT_STRATEGY=lb
export OMP_NUM_THREADS=1

run_update() {
  local dataset="$1"
  local suffix="$2"
  shift 2
  local base_query_gt result_dir
  case "$dataset" in
    sift)
      base_query_gt="./Datasets/sift/sift/sift_base.fvecs|./Datasets/sift/sift/sift_query.fvecs|./Datasets/sift/sift/sift_groundtruth.ivecs"
      result_dir="./results/sift/update/shg${suffix}"
      unset GTI_UPDATE_RATIO
      ;;
    deep)
      base_query_gt="./Datasets/deep/deep1M/deep1M_base.fvecs|./Datasets/deep/deep1M/deep1M_query.fvecs|./Datasets/deep/deep1M/deep1M_groundtruth.ivecs"
      result_dir="./results/deep/update/shg${suffix}"
      export GTI_UPDATE_RATIO=0.005
      ;;
    *) echo "未知数据集 $dataset"; return 1 ;;
  esac

  IFS='|' read -r BASE QUERY GT <<< "$base_query_gt"
  mkdir -p "$result_dir"
  if [ ! -x "./GTI/bin/GTI_shg" ]; then
    echo "错误: GTI_shg 不存在，请先编译"
    return 1
  fi
  if [ ! -f "$BASE" ] || [ ! -f "$QUERY" ] || [ ! -f "$GT" ]; then
    echo "错误: 数据集文件缺失"
    return 1
  fi

  export GTI_PATCH_DELETE_ONLY=1
  export GTI_DELETE_CHUNK_SIZE=2000
  for e in "${SHG_BASELINE_ENV[@]}"; do export "$e"; done
  while [[ $# -gt 0 ]]; do export "$1"; shift; done

  echo "========== Update: $dataset | $suffix =========="
  "./GTI/bin/GTI_shg" "$BASE" "$QUERY" 3 "$GT" "$result_dir/" 2>&1 | tee "$result_dir/run.log"
  echo ""
}

run_aknn() {
  local dataset="$1"
  local suffix="$2"
  shift 2
  local base query gt l k out_dir
  case "$dataset" in
    sift)
      base="./Datasets/sift/sift/sift_base.fvecs"
      query="./Datasets/sift/sift/sift_query.fvecs"
      gt="./Datasets/sift/sift/sift_groundtruth.ivecs"
      ;;
    deep)
      base="./Datasets/deep/deep1M/deep1M_base.fvecs"
      query="./Datasets/deep/deep1M/deep1M_query.fvecs"
      gt="./Datasets/deep/deep1M/deep1M_groundtruth.ivecs"
      ;;
    *) echo "未知数据集 $dataset"; return 1 ;;
  esac
  l=60
  k=10
  out_dir="./results/${dataset}/aknn_compare/shg${suffix}"
  mkdir -p "$out_dir"

  for e in "${SHG_BASELINE_ENV[@]}"; do export "$e"; done
  while [[ $# -gt 0 ]]; do export "$1"; shift; done

  echo "========== A-kNN: $dataset | $suffix =========="
  "./GTI/bin/GTI_shg" "$base" "$query" 0 "$gt" "$l" "$k" "$out_dir/" 2>&1 | tee "$out_dir/run.log"
  echo ""
}

# --- 1. 基线：REBUILD + 65% 采样 ---
echo "########################################"
echo "# 1. 基线 (REBUILD_AFTER_INSERT=1, SAMPLE_RATIO=0.65)"
echo "########################################"
run_update "sift" "_baseline" || true
run_update "deep" "_baseline" || true
run_aknn "sift" "_baseline" || true
run_aknn "deep" "_baseline" || true

# --- 2. S4: PRUNE=0 ---
echo "########################################"
echo "# 2. S4 (GTI_SHG_PRUNE=0)"
echo "########################################"
run_update "sift" "_prune0" "GTI_SHG_PRUNE=0" || true
run_update "deep" "_prune0" "GTI_SHG_PRUNE=0" || true
run_aknn "sift" "_prune0" "GTI_SHG_PRUNE=0" || true
run_aknn "deep" "_prune0" "GTI_SHG_PRUNE=0" || true

echo "########################################"
echo "# 完成：请对比 shg_baseline vs shg_prune0"
echo "# 若 prune0 recall 明显下降或 search 未提速，则回滚 S4"
echo "########################################"
