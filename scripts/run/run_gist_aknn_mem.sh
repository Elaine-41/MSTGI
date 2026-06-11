#!/bin/bash
#
# 近似搜索 + 采集峰值内存（RSS）与索引构建时间
# 数据集目录：./Datasets/gist
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

DATASET_DIR="./Datasets/gist"
GTI_BIN="./GTI/bin/GTI"
RESULT_DIR="./results/gist/approximate"

L=60
K=10

BASE="${DATASET_DIR}/gist_base.fvecs"
QUERY="${DATASET_DIR}/gist_query.fvecs"
GT="${DATASET_DIR}/gist_groundtruth.ivecs"

mkdir -p "$RESULT_DIR"

if [ ! -x "$GTI_BIN" ]; then
  echo "错误: GTI可执行文件不存在或不可执行: $GTI_BIN"
  exit 1
fi
if [ ! -f "$BASE" ] || [ ! -f "$QUERY" ] || [ ! -f "$GT" ]; then
  echo "错误: 缺少数据集文件（base/query/groundtruth）于 $DATASET_DIR"
  exit 1
fi

echo "========== 运行近似搜索并采集内存 =========="
echo "命令: $GTI_BIN $BASE $QUERY 0 $GT $L $K $RESULT_DIR/"

TIME_LOG="${RESULT_DIR}/time_mem_k${K}_l${L}.txt"
rm -f "$TIME_LOG"

set +e
/usr/bin/time -v "$GTI_BIN" "$BASE" "$QUERY" 0 "$GT" "$L" "$K" "$RESULT_DIR/" 2> "$TIME_LOG"
rc=$?
set -e
if [ $rc -ne 0 ]; then
  echo "错误: GTI 运行失败，退出码=$rc；请查看 $TIME_LOG"
  exit $rc
fi

# 解析峰值RSS（KB），换算GB/TB
RSS_KB="$(awk -F: '/Maximum resident set size/ {gsub(/^[ \t]+/,"",$2); print $2}' "$TIME_LOG" | tail -1)"
if [ -n "$RSS_KB" ]; then
  RSS_GB="$(awk -v kb="$RSS_KB" 'BEGIN{printf "%.6f", kb/1024/1024}')"
  RSS_TB="$(awk -v gb="$RSS_GB" 'BEGIN{printf "%.6f", gb/1024}')"
  echo "Peak RSS: ${RSS_KB} KB (${RSS_GB} GB, ${RSS_TB} TB)"
  echo "Peak RSS: ${RSS_KB} KB (${RSS_GB} GB, ${RSS_TB} TB)" >> "${RESULT_DIR}/cost_${K}_${L}.txt"
else
  echo "警告: 未能从 /usr/bin/time -v 解析峰值RSS；请查看 $TIME_LOG"
fi

echo "结果文件: ${RESULT_DIR}/cost_${K}_${L}.txt"
