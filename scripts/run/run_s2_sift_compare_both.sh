#!/bin/bash
#
# S2 公平对比：同一会话内依次运行 baseline（无 S2）与 S2，确保建库/Insert/Delete 可比
# 输出：shg_prune0_nos2, shg_prune0_opt_s2
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
export GTI_LSH_ENABLED=0
export GTI_SPLIT_STRATEGY=lb
export GTI_PATCH_DELETE_ONLY=1
export GTI_DELETE_CHUNK_SIZE=2000
export OMP_NUM_THREADS=1

[ ! -x "./GTI/bin/GTI_shg" ] && { echo "错误: GTI_shg 不存在"; exit 1; }
[ ! -f "$BASE" ] || [ ! -f "$QUERY" ] || [ ! -f "$GT" ] && { echo "错误: sift 数据集缺失"; exit 1; }

run_one() {
  local out="$1"
  local use_s2="$2"
  mkdir -p "$out"
  if [ "$use_s2" = "1" ]; then
    export GTI_SHG_LIGHTWEIGHT_QUERY=1
    echo "========== [S2] Update -> $out =========="
  else
    unset GTI_SHG_LIGHTWEIGHT_QUERY
    echo "========== [baseline] Update -> $out =========="
  fi
  ./GTI/bin/GTI_shg "$BASE" "$QUERY" 3 "$GT" "$out/" 2>&1 | tee "$out/run.log"
}

OUT_NOS2="./results/sift/update/shg_prune0_nos2"
OUT_S2="./results/sift/update/shg_prune0_opt_s2"

echo "########################################"
echo "# S2 公平对比：baseline -> S2（同会话）"
echo "########################################"
run_one "$OUT_NOS2" 0
run_one "$OUT_S2" 1

echo ""
echo "完成. 对比: $OUT_NOS2 vs $OUT_S2"
