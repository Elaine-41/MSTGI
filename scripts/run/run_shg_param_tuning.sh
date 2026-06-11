#!/bin/bash
#
# SHG 参数调优：M、EF_BUILD、EF_SEARCH 多组合验证
# 固定：GTI_SHG_REBUILD_AFTER_INSERT=1, GTI_SHG_SHORTCUT_SAMPLE_RATIO=0.65, GTI_SHG_PRUNE=0
# 可变：GTI_SHG_M, GTI_SHG_EF_BUILD, GTI_SHG_EF_SEARCH
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

# 固定配置
export GTI_SHG_REBUILD_AFTER_INSERT=1
export GTI_SHG_SHORTCUT_SAMPLE_RATIO=0.65
export GTI_SHG_PRUNE=0

export GTI_LSH_ENABLED=0
export GTI_SPLIT_STRATEGY=lb
export OMP_NUM_THREADS=1

# 参数组合: "M:EF_BUILD:EF_SEARCH:suffix"
# 基线 M=24,efb=80,efs=50 已有 shg_prune0 数据，可跳过
PARAM_SETS=(
  "24:80:50:_m24_efb80_efs50"     # 基线（与 prune0 等价）
  "24:80:80:_m24_efb80_efs80"
  "24:120:50:_m24_efb120_efs50"
  "24:120:80:_m24_efb120_efs80"
  "32:80:50:_m32_efb80_efs50"
  "32:120:80:_m32_efb120_efs80"
)

run_one() {
  local m="$1"
  local efb="$2"
  local efs="$3"
  local suffix="$4"
  local dataset="$5"

  local base query gt result_dir
  if [ "$dataset" = "sift" ]; then
    base="./Datasets/sift/sift/sift_base.fvecs"
    query="./Datasets/sift/sift/sift_query.fvecs"
    gt="./Datasets/sift/sift/sift_groundtruth.ivecs"
    result_dir="./results/sift/update/shg${suffix}"
    unset GTI_UPDATE_RATIO
  else
    base="./Datasets/deep/deep1M/deep1M_base.fvecs"
    query="./Datasets/deep/deep1M/deep1M_query.fvecs"
    gt="./Datasets/deep/deep1M/deep1M_groundtruth.ivecs"
    result_dir="./results/deep/update/shg${suffix}"
    export GTI_UPDATE_RATIO=0.005
  fi

  mkdir -p "$result_dir"
  export GTI_SHG_M="$m"
  export GTI_SHG_EF_BUILD="$efb"
  export GTI_SHG_EF_SEARCH="$efs"
  export GTI_PATCH_DELETE_ONLY=1
  export GTI_DELETE_CHUNK_SIZE=2000

  echo "========== $dataset | M=$m EF_BUILD=$efb EF_SEARCH=$efs =========="
  "./GTI/bin/GTI_shg" "$base" "$query" 3 "$gt" "$result_dir/" 2>&1 | tee "$result_dir/run.log"
  echo ""
}

# 跳过已有基线（M=24,efb=80,efs=50 等价于 shg_prune0）
SKIP_BASELINE="${SKIP_BASELINE:-1}"

echo "########################################"
echo "# SHG 参数调优 (REBUILD=1, SAMPLE=0.65, PRUNE=0)"
echo "########################################"

for ps in "${PARAM_SETS[@]}"; do
  IFS=':' read -r m efb efs suffix <<< "$ps"
  if [ "$SKIP_BASELINE" = "1" ] && [ "$suffix" = "_m24_efb80_efs50" ]; then
    echo "跳过基线 $suffix (已有 shg_prune0 数据)"
    continue
  fi
  run_one "$m" "$efb" "$efs" "$suffix" "sift" || true
done

echo "########################################"
echo "# 完成。汇总请查看 results/sift/update/shg_*/update_summary_*.txt"
echo "# 对比: recall、delete_avg、建库时间、search/query"
echo "########################################"
