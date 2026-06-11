#!/bin/bash
#
# 在 Gist 数据集上测试不同 k 值下的 A k-NN：
#   - 记录每个 k 的索引构建时间、平均搜索时间、召回率、峰值内存（RSS）
#   - 结果输出为 CSV，便于画 “k vs time/recall” 曲线
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

DATASET_DIR="./Datasets/gist"
GTI_BIN="./GTI/bin/GTI"
RESULT_DIR="./results/gist/pre_experiments/k_sweep_L60"

BASE="${DATASET_DIR}/gist_base.fvecs"
QUERY="${DATASET_DIR}/gist_query.fvecs"
GT="${DATASET_DIR}/gist_groundtruth.ivecs"

L=60
# 你可以按需修改此列表，例如增加 15,25,35,45 等
K_LIST=(1 5 10 20 30 40 50)

mkdir -p "$RESULT_DIR"

if [ ! -x "$GTI_BIN" ]; then
  echo "错误: GTI可执行文件不存在或不可执行: $GTI_BIN"
  exit 1
fi
if [ ! -f "$BASE" ] || [ ! -f "$QUERY" ] || [ ! -f "$GT" ]; then
  echo "错误: 缺少数据集文件（base/query/groundtruth）于 $DATASET_DIR"
  exit 1
fi

CSV="${RESULT_DIR}/k_sweep_L${L}.csv"
echo "k,build_time,search_time,recall,rss_kb,rss_gb" > "$CSV"

# 为稳定结果，限制为单线程（可按需放开）
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"

for K in "${K_LIST[@]}"; do
  echo "========== k = ${K} =========="
  TIME_LOG="${RESULT_DIR}/time_k${K}_L${L}.txt"
  rm -f "$TIME_LOG"

  set +e
  /usr/bin/time -v "$GTI_BIN" \
      "$BASE" \
      "$QUERY" \
      0 \
      "$GT" \
      "$L" \
      "$K" \
      "$RESULT_DIR/" 2> "$TIME_LOG"
  rc=$?
  set -e

  if [ $rc -ne 0 ]; then
    echo "警告: k=${K} 运行失败，退出码=$rc，跳过此 k（详见 $TIME_LOG）"
    continue
  fi

  RESULT_FILE="${RESULT_DIR}/cost_${K}_${L}.txt"
  if [ ! -f "$RESULT_FILE" ]; then
    echo "警告: 结果文件不存在: $RESULT_FILE，跳过此 k"
    continue
  fi

  # 从结果文件中解析索引构建时间、搜索时间、召回率
  BUILD_TIME="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$RESULT_FILE" | tail -1)"
  SEARCH_TIME="$(awk -F: '/Search time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$RESULT_FILE" | tail -1)"
  RECALL="$(awk -F: '/Search recall/ {gsub(/^[ \t]+/,"",$2); print $2}' "$RESULT_FILE" | tail -1)"

  # 从 /usr/bin/time -v 日志解析峰值 RSS
  RSS_KB="$(awk -F: '/Maximum resident set size/ {gsub(/^[ \t]+/,"",$2); print $2}' "$TIME_LOG" | tail -1)"
  if [ -z "$RSS_KB" ]; then
    RSS_KB=0
  fi
  RSS_GB="$(awk -v kb="$RSS_KB" 'BEGIN{printf "%.6f", (kb==0?0:kb/1024/1024)}')"

  echo "k=${K}: build=${BUILD_TIME}s, search=${SEARCH_TIME}s, recall=${RECALL}, RSS=${RSS_KB}KB"
  echo "${K},${BUILD_TIME},${SEARCH_TIME},${RECALL},${RSS_KB},${RSS_GB}" >> "$CSV"
done

echo ""
echo "k 扫描结果已写入: $CSV"
