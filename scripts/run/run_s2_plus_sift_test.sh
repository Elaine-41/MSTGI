#!/bin/bash
#
# S2+ 测试：S2 + GTI_SHG_FULL_DIM_LEVEL_SKIP=1（方向 1 快速路径）
# 预期：overwriteQuerySlotData 仅 memcpy，搜索延迟再降约 5–15%
# 输出：results/sift/update/shg_prune0_opt_s2_plus/
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

BASE="./Datasets/sift/sift/sift_base.fvecs"
QUERY="./Datasets/sift/sift/sift_query.fvecs"
GT="./Datasets/sift/sift/sift_groundtruth.ivecs"

export GTI_SHG_M=24
export GTI_SHG_EF_BUILD=80
export GTI_SHG_EF_SEARCH=80
export GTI_SHG_REBUILD_AFTER_INSERT=1
export GTI_SHG_SHORTCUT_SAMPLE_RATIO=0.65
export GTI_SHG_PRUNE=0
export GTI_SHG_FULL_DIM_LEVEL_SKIP=1
export GTI_SHG_LIGHTWEIGHT_QUERY=1
export GTI_LSH_ENABLED=0
export GTI_SPLIT_STRATEGY=lb
export GTI_PATCH_DELETE_ONLY=1
export GTI_DELETE_CHUNK_SIZE=2000
export OMP_NUM_THREADS=1

[ ! -x "./GTI/bin/GTI_shg" ] && { echo "错误: GTI_shg 不存在"; exit 1; }
[ ! -f "$BASE" ] || [ ! -f "$QUERY" ] || [ ! -f "$GT" ] && { echo "错误: sift 数据集缺失"; exit 1; }

OUT="./results/sift/update/shg_prune0_opt_s2_plus"
mkdir -p "$OUT"

echo "########################################"
echo "# S2+ 测试: S2 + FULL_DIM_LEVEL_SKIP=1"
echo "########################################"
./GTI/bin/GTI_shg "$BASE" "$QUERY" 3 "$GT" "$OUT/" 2>&1 | tee "$OUT/run.log"

echo ""
echo "完成. 结果: $OUT/"
