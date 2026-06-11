#!/bin/bash
#
# SHG 优化方案 A+B+C 验证脚本
# 跑两组参数：baseline (ef160, L60) 与 优化组 (ef200, L120)
# 使用 sift 数据集
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

if [ ! -x "./GTI/bin/GTI_shg" ]; then
  echo "错误: GTI_shg 不存在，请先构建 SHG 版本"
  exit 1
fi

echo "========== SHG 优化验证 (A+B+C) =========="
echo ""

# Group 1: baseline (ef 160, L 60)
echo "========== Group 1: baseline (ef=160, L=60) =========="
unset GTI_SHG_EF_BUILD GTI_SEARCH_L GTI_RESULT_SUFFIX
"$SCRIPT_DIR/run_update.sh" sift shg
echo ""

# Group 2: ef200, L120 (A 参数调优 + C L 对比)
echo "========== Group 2: GTI_SHG_EF_BUILD=200, GTI_SEARCH_L=120 =========="
export GTI_SHG_EF_BUILD=200
export GTI_SEARCH_L=120
export GTI_RESULT_SUFFIX=_ef200_l120
"$SCRIPT_DIR/run_update.sh" sift shg
echo ""

echo "========== 完成 =========="
echo "结果:"
echo "  Group 1: results/sift/update/shg/"
echo "  Group 2: results/sift/update/shg_ef200_l120/"
echo ""
echo "对比 recall 与 search 延迟可评估优化效果"
