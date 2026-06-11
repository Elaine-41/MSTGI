#!/bin/bash
#
# SHG_prune0 在 gist 上的实验（SHG_prune0.md 中 gist 数据缺失时使用）
# 配置：ratio=0.005，5k insert，2000 delete，chunk=200（与 wolverine_d2 一致）
# 若耗时过长可设置 GIST_TIMEOUT_HOURS 或 SKIP_GIST=1 跳过
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

SKIP_GIST="${SKIP_GIST:-0}"
GIST_TIMEOUT_HOURS="${GIST_TIMEOUT_HOURS:-1}"

BASE="./Datasets/gist/gist_base.fvecs"
QUERY="./Datasets/gist/gist_query.fvecs"
GT="./Datasets/gist/gist_groundtruth.ivecs"
L=60
K=10

export GTI_SHG_REBUILD_AFTER_INSERT=1
export GTI_SHG_SHORTCUT_SAMPLE_RATIO=0.65
export GTI_SHG_PRUNE=0
export GTI_SHG_M=24
export GTI_SHG_EF_BUILD=80
export GTI_SHG_EF_SEARCH=80
export GTI_LSH_ENABLED=0
export GTI_SPLIT_STRATEGY=lb
export GTI_PATCH_DELETE_ONLY=1
export GTI_UPDATE_RATIO=0.005
export GTI_UPDATE_DELETE_N=2000
export GTI_DELETE_CHUNK_SIZE=200
export OMP_NUM_THREADS=1

if [ "$SKIP_GIST" = "1" ]; then
  echo "跳过 gist（SKIP_GIST=1）"
  exit 0
fi

if [ ! -x "./GTI/bin/GTI_shg" ]; then
  echo "错误: GTI_shg 不存在，请先编译 SHG 版本"
  exit 1
fi

if [ ! -f "$BASE" ] || [ ! -f "$QUERY" ] || [ ! -f "$GT" ]; then
  echo "错误: gist 数据集文件不完整"
  exit 1
fi

mkdir -p ./results/gist/update/shg_prune0
mkdir -p ./results/gist/aknn_compare/shg_prune0

echo "########################################"
echo "# SHG_prune0 在 gist 上运行"
echo "# ratio=0.005, 5k insert, 2000 delete, chunk=200"
echo "# 超时: ${GIST_TIMEOUT_HOURS}h (可设置 GIST_TIMEOUT_HOURS)"
echo "########################################"

run_with_timeout() {
  local timeout_sec=$((GIST_TIMEOUT_HOURS * 3600))
  if command -v timeout &>/dev/null; then
    timeout "$timeout_sec" "$@" || { echo "超时 ${GIST_TIMEOUT_HOURS}h，跳过"; exit 124; }
  else
    "$@"
  fi
}

echo "========== [gist] SHG_prune0 A-kNN =========="
run_with_timeout ./GTI/bin/GTI_shg "$BASE" "$QUERY" 0 "$GT" "$L" "$K" ./results/gist/aknn_compare/shg_prune0/ 2>&1 | tee ./results/gist/aknn_compare/shg_prune0/run.log

echo "========== [gist] SHG_prune0 Update =========="
run_with_timeout ./GTI/bin/GTI_shg "$BASE" "$QUERY" 3 "$GT" ./results/gist/update/shg_prune0/ 2>&1 | tee ./results/gist/update/shg_prune0/run.log

echo "########################################"
echo "# gist SHG_prune0 完成"
echo "# 结果: results/gist/update/shg_prune0/, results/gist/aknn_compare/shg_prune0/"
echo "########################################"
