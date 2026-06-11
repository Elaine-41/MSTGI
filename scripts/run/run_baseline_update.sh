#!/bin/bash
#
# Baseline Index Update 测试（README 示例：bigann_example 数据集）
# 禁用 LSH、使用 LB 分裂，验证插入+删除流程
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

GTI_BIN="./GTI/bin/GTI"
BASE="./Datasets/bigann_example_base.fvecs"
QUERY="./Datasets/bigann_example_query.fvecs"
GT="./Datasets/bigann_example_groundtruth.ivecs"
RESULT_DIR="./Datasets"

if [ ! -x "$GTI_BIN" ]; then
  echo "错误: GTI可执行文件不存在: $GTI_BIN"
  exit 1
fi
if [ ! -f "$BASE" ] || [ ! -f "$QUERY" ] || [ ! -f "$GT" ]; then
  echo "错误: 缺少 bigann_example 数据集"
  exit 1
fi

echo "========== Baseline Index Update (README 示例) =========="
echo "  GTI_LSH_ENABLED=0, GTI_SPLIT_STRATEGY=lb"
echo ""

export GTI_LSH_ENABLED=0
export GTI_SPLIT_STRATEGY=lb
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"

"$GTI_BIN" "$BASE" "$QUERY" 3 "$GT" "$RESULT_DIR/"

echo ""
echo "输出: ${RESULT_DIR}/update_curve_k10_l60_ratio0.01.csv"
echo "     ${RESULT_DIR}/update_summary_k10_l60_ratio0.01.txt"
