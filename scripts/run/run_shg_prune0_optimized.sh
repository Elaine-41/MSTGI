#!/bin/bash
#
# SHG_prune0 优化版：采用 m24_efb80_efs80 参数（SHG_prune0.md 第七章推荐）
# 相比基线 prune0 (M=24, EF=80/50)：建库更快、Delete 更快、搜索更快，recall 持平
# 结果: results/{sift,deep}/update/shg_prune0_opt/, aknn_compare/shg_prune0_opt/
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

# 优化参数：m24_efb80_efs80（综合推荐）
export GTI_SHG_M=24
export GTI_SHG_EF_BUILD=80
export GTI_SHG_EF_SEARCH=80

# 固定：PRUNE=0 + REBUILD + 65% 采样
export GTI_SHG_REBUILD_AFTER_INSERT=1
export GTI_SHG_SHORTCUT_SAMPLE_RATIO=0.65
export GTI_SHG_PRUNE=0

export GTI_LSH_ENABLED=0
export GTI_SPLIT_STRATEGY=lb
export GTI_PATCH_DELETE_ONLY=1
export GTI_DELETE_CHUNK_SIZE=2000
export OMP_NUM_THREADS=1

L=60
K=10

if [ ! -x "./GTI/bin/GTI_shg" ]; then
  echo "错误: GTI_shg 不存在，请先编译"
  exit 1
fi

run_dataset() {
  local ds="$1"
  local base query gt ratio
  case "$ds" in
    sift)
      base="./Datasets/sift/sift/sift_base.fvecs"
      query="./Datasets/sift/sift/sift_query.fvecs"
      gt="./Datasets/sift/sift/sift_groundtruth.ivecs"
      ratio="0.010"
      unset GTI_UPDATE_RATIO
      ;;
    deep)
      base="./Datasets/deep/deep1M/deep1M_base.fvecs"
      query="./Datasets/deep/deep1M/deep1M_query.fvecs"
      gt="./Datasets/deep/deep1M/deep1M_groundtruth.ivecs"
      ratio="0.005"
      export GTI_UPDATE_RATIO=0.005
      ;;
    *) echo "未知数据集 $ds"; return 1 ;;
  esac

  if [ ! -f "$base" ] || [ ! -f "$query" ] || [ ! -f "$gt" ]; then
    echo "跳过 $ds: 数据集缺失"
    return 1
  fi

  local out_base="./results/${ds}"
  mkdir -p "${out_base}/update/shg_prune0_opt"
  mkdir -p "${out_base}/aknn_compare/shg_prune0_opt"

  echo "========== [$ds] SHG_prune0 优化版 A-kNN (M=24, EF=80/80) =========="
  ./GTI/bin/GTI_shg "$base" "$query" 0 "$gt" "$L" "$K" "${out_base}/aknn_compare/shg_prune0_opt/" 2>&1 | tee "${out_base}/aknn_compare/shg_prune0_opt/run.log"

  echo "========== [$ds] SHG_prune0 优化版 Update =========="
  ./GTI/bin/GTI_shg "$base" "$query" 3 "$gt" "${out_base}/update/shg_prune0_opt/" 2>&1 | tee "${out_base}/update/shg_prune0_opt/run.log"

  echo "[$ds] 完成: ${out_base}/update/shg_prune0_opt/, ${out_base}/aknn_compare/shg_prune0_opt/"
}

echo "########################################"
echo "# SHG_prune0 优化版 (m24_efb80_efs80)"
echo "# 预期: 建库 289s, Delete 64s, 搜索 1.67ms, recall 0.784"
echo "########################################"

for ds in sift deep; do
  run_dataset "$ds" || true
done

echo "########################################"
echo "# 完成。对比: shg_prune0 (基线) vs shg_prune0_opt (优化)"
echo "########################################"
