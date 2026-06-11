#!/bin/bash
#
# SHG 验证脚本：使用 sift 数据集，结果输出到 results/SHG/
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"
cd "$ROOT"

GTI_SHG_BIN="./GTI/bin/GTI_shg"
BASE="./Datasets/sift/sift/sift_base.fvecs"
QUERY="./Datasets/sift/sift/sift_query.fvecs"
GT="./Datasets/sift/sift/sift_groundtruth.ivecs"
RESULT_DIR="./results/SHG"

mkdir -p "$RESULT_DIR"

# 若 GTI_shg 不存在则构建
if [ ! -x "$GTI_SHG_BIN" ]; then
  echo "========== 构建 GTI_shg (SHG 后端) =========="
  cd GTI
  mkdir -p build_shg
  cd build_shg
  cmake -DGTI_USE_SHG=ON -DGTI_USE_WOLVERINE=OFF ..
  make -j
  cd ../..
  if [ ! -x "$GTI_SHG_BIN" ]; then
    echo "错误: 构建失败，未找到 $GTI_SHG_BIN"
    exit 1
  fi
  echo ""
fi

if [ ! -f "$BASE" ] || [ ! -f "$QUERY" ] || [ ! -f "$GT" ]; then
  echo "错误: 缺少 sift 数据集文件"
  echo "  BASE:  $BASE"
  echo "  QUERY: $QUERY"
  echo "  GT:    $GT"
  exit 1
fi

echo "========== SHG 验证: sift 数据集 =========="
echo "  BASE: $BASE"
echo "  结果: $RESULT_DIR/"
echo ""

# process 0: build + approx k-NN, 参数: gt, L, k, res_file
# res_file 为目录，会生成 cost_K_L.txt
export GTI_LSH_ENABLED="${GTI_LSH_ENABLED:-0}"
export GTI_SPLIT_STRATEGY="${GTI_SPLIT_STRATEGY:-lb}"
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"

L=60
K=10
RES_FILE="${RESULT_DIR}/"

LOG="${RESULT_DIR}/run.log"
"$GTI_SHG_BIN" "$BASE" "$QUERY" 0 "$GT" "$L" "$K" "$RES_FILE" | tee "$LOG"

echo ""
echo "输出: ${RESULT_DIR}/cost_${K}_${L}.txt"
