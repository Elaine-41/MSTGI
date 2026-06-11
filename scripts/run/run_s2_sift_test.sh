#!/bin/bash
#
# S2 轻量级 query 在 sift 上的对比测试
# 1. 无 S2 (baseline): shg_m24_efb80_efs80 已有结果可复用
# 2. 有 S2: 运行并输出到 shg_prune0_opt_s2
# 3. 对比与 wolverine_d2
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

BASE="./Datasets/sift/sift/sift_base.fvecs"
QUERY="./Datasets/sift/sift/sift_query.fvecs"
GT="./Datasets/sift/sift/sift_groundtruth.ivecs"
L=60
K=10

export GTI_SHG_M=24
export GTI_SHG_EF_BUILD=80
export GTI_SHG_EF_SEARCH=80
export GTI_SHG_REBUILD_AFTER_INSERT=1
export GTI_SHG_SHORTCUT_SAMPLE_RATIO=0.65
export GTI_SHG_PRUNE=0
export GTI_LSH_ENABLED=0
export GTI_SPLIT_STRATEGY=lb
export GTI_PATCH_DELETE_ONLY=1
export GTI_DELETE_CHUNK_SIZE=2000
export OMP_NUM_THREADS=1

if [ ! -x "./GTI/bin/GTI_shg" ]; then
  echo "错误: GTI_shg 不存在"
  exit 1
fi

if [ ! -f "$BASE" ] || [ ! -f "$QUERY" ] || [ ! -f "$GT" ]; then
  echo "错误: sift 数据集缺失"
  exit 1
fi

OUT_S2="./results/sift/update/shg_prune0_opt_s2"
mkdir -p "$OUT_S2"

echo "########################################"
echo "# S2 测试: SHG_prune0 + GTI_SHG_LIGHTWEIGHT_QUERY=1"
echo "########################################"

export GTI_SHG_LIGHTWEIGHT_QUERY=1
echo "========== Update (含多次搜索) =========="
./GTI/bin/GTI_shg "$BASE" "$QUERY" 3 "$GT" "$OUT_S2/" 2>&1 | tee "$OUT_S2/run.log"

echo ""
echo "完成. 结果: $OUT_S2/"
echo "对比: baseline=results/sift/update/shg_m24_efb80_efs80/, wolverine_d2=results/sift/update/wolverine_Wolverine_d2/"
