#!/bin/bash
#
# GTI OPS 测试：类似 Wolverine 的 search→delete 循环，输出 recall,search_OPS,delete_OPS,insert_OPS
# 对比 lazy 和 wolverine 两种删除策略，结果存到 results/sift/update/<strategy>/
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

GTI_BIN="./GTI/bin/GTI"
GTI_N2_BIN="./GTI/bin/GTI_n2"

BASE="./Datasets/sift/sift/sift_base.fvecs"
QUERY="./Datasets/sift/sift/sift_query.fvecs"
GT="./Datasets/sift/sift/sift_groundtruth.ivecs"
UPDATE_DIR="./results/sift/update"

# 循环次数，可设置 GTI_OPS_CIRCUL_SUM 覆盖（默认 5，与 Wolverine 对比可设为 50）
CIRCUL="${GTI_OPS_CIRCUL_SUM:-5}"
export GTI_OPS_CIRCUL_SUM="$CIRCUL"
export GTI_UPDATE_RATIO="${GTI_UPDATE_RATIO:-0.01}"
export GTI_SEARCH_L="${GTI_SEARCH_L:-60}"

# 策略：lazy 用 GTI_n2，wolverine 用 GTI
STRATEGIES="${GTI_STRATEGIES:-lazy wolverine}"

usage() {
  echo "用法: $0 [run]"
  echo "  默认仅汇总；加 run 执行测试"
  echo "  策略: lazy | wolverine (可设 GTI_STRATEGIES='lazy wolverine')"
  echo "  结果: $UPDATE_DIR/<strategy>/ops_k10_l60.csv"
  exit 1
}

[[ ! -f "$BASE" ]] && { echo "错误: 数据集不存在 $BASE"; exit 1; }
mkdir -p "$UPDATE_DIR"

if [[ "${1:-}" = "run" ]]; then
  echo "========== GTI OPS 测试: sift (${STRATEGIES}) circul=$CIRCUL =========="
  for name in $STRATEGIES; do
    echo ""
    echo ">>> 策略: $name <<<"
    RESULT_DIR="${UPDATE_DIR}/${name}"
    mkdir -p "$RESULT_DIR"

    if [[ "$name" = "lazy" ]]; then
      RUN_BIN="$GTI_N2_BIN"
      unset GTI_PATCH_DELETE_ONLY
      export GTI_REBUILD_THRESHOLD="${GTI_REBUILD_THRESHOLD:-5000}"
    else
      RUN_BIN="$GTI_BIN"
      unset GTI_REBUILD_THRESHOLD
      export GTI_PATCH_DELETE_ONLY=1
    fi

    [[ ! -x "$RUN_BIN" ]] && { echo "错误: $name 需 $RUN_BIN，请先运行 build_both.sh"; exit 1; }

    LOG="${RESULT_DIR}/run_ops.log"
    "$RUN_BIN" "$BASE" "$QUERY" 4 "$GT" "${RESULT_DIR}/" | tee "$LOG"
    echo "结果: ${RESULT_DIR}/ops_k10_l60.csv"
  done
  echo ""
  echo "OPS 测试完成"
fi

# 汇总
echo ""
echo "=============================================================="
echo "  GTI OPS 结果 (results/sift/update/)"
echo "=============================================================="
for name in $STRATEGIES; do
  csv="${UPDATE_DIR}/${name}/ops_k10_l60.csv"
  if [[ -f "$csv" ]]; then
    echo "  $name: $csv"
    echo "    $(wc -l < "$csv") 行 (含表头)"
    head -3 "$csv"
  else
    echo "  $name: (无结果，请先运行 $0 run)"
  fi
  echo ""
done
