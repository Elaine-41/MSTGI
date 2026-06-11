#!/bin/bash
#
# 动态更新实验（支持 gist / deep / sift 数据集）
# 使用 baseline 配置（无 LSH，LB 分裂）
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

GTI_BIN="./GTI/bin/GTI"
GTI_N2_BIN="./GTI/bin/GTI_n2"  # 原始方法，直接删除策略使用
GTI_SHG_BIN="./GTI/bin/GTI_shg"  # SHG 后端，markDelete 删除

# 数据集路径配置
# 格式: "base_path|query_path|gt_path|result_dir"
declare -A DATASETS=(
  ["gist"]="./Datasets/gist/gist_base.fvecs|./Datasets/gist/gist_query.fvecs|./Datasets/gist/gist_groundtruth.ivecs|./results/gist/update"
  ["deep"]="./Datasets/deep/deep1M/deep1M_base.fvecs|./Datasets/deep/deep1M/deep1M_query.fvecs|./Datasets/deep/deep1M/deep1M_groundtruth.ivecs|./results/deep/update"
  ["sift"]="./Datasets/sift/sift/sift_base.fvecs|./Datasets/sift/sift/sift_query.fvecs|./Datasets/sift/sift/sift_groundtruth.ivecs|./results/sift/update"
)

usage() {
  echo "用法: $0 <dataset> [strategy] [wolverine_delete_model]"
  echo "  dataset: gist | deep | sift"
  echo "  strategy: direct | lazy | wolverine | shg | hybrid (默认 hybrid)"
  echo "    direct   - 直接删除一批次"
  echo "    lazy     - 伪删除，超阈值则重建"
  echo "    wolverine- 纯 Wolverine patchDelete"
  echo "    shg      - SHG 后端，markDelete，删除 chunk=2000 与 Wolverine 一致"
  echo "    hybrid   - 混合（伪删除+wolverine）"
  echo "  wolverine_delete_model: 仅当 strategy=wolverine 时有效"
  echo "    WolverineProMax - 近似两跳删除 (默认)"
  echo "    WolverinePro    - 两跳删除"
  echo "    Wolverine       - 搜索删除"
  echo ""
  echo "示例: $0 sift hybrid"
  echo "      $0 sift wolverine                    # 默认 WolverineProMax"
  echo "      $0 sift wolverine WolverinePro       # 验证 WolverinePro"
  echo "      $0 sift wolverine Wolverine          # 验证 Wolverine"
  echo "      GTI_WOLVERINE_DELETE_MODEL=Wolverine $0 sift wolverine  # 环境变量方式"
  exit 1
}

DATASET="${1:-}"
STRATEGY="${2:-hybrid}"
WOLVERINE_DELETE_MODEL="${3:-}"
if [ -z "$DATASET" ] || [ -z "${DATASETS[$DATASET]:-}" ]; then
  echo "错误: 请指定数据集 (gist | deep | sift)"
  usage
fi

# wolverine 策略下，第 3 参数可选指定删除模型
if [ "$STRATEGY" = "wolverine" ] && [ -n "$WOLVERINE_DELETE_MODEL" ]; then
  case "$WOLVERINE_DELETE_MODEL" in
    WolverineProMax|WolverinePro|Wolverine)
      export GTI_WOLVERINE_DELETE_MODEL="$WOLVERINE_DELETE_MODEL"
      GTI_RESULT_SUFFIX="_${WOLVERINE_DELETE_MODEL}"
      [ "${GTI_TREE_PRIORITY_SAME_LEAF:-0}" = "1" ] && GTI_RESULT_SUFFIX="${GTI_RESULT_SUFFIX}_d2"
      export GTI_RESULT_SUFFIX
      ;;
    *) echo "警告: 未知删除模型 '$WOLVERINE_DELETE_MODEL'，忽略" ;;
  esac
fi

IFS='|' read -r BASE QUERY GT RESULT_DIR <<< "${DATASETS[$DATASET]}"
# 结果统一存到 update/<strategy>[/suffix]/
# GTI_RESULT_SUFFIX 用于参数调优（如 _ef200_l120）或删除模型（如 _WolverinePro）
RESULT_DIR="${RESULT_DIR}/${STRATEGY}${GTI_RESULT_SUFFIX:-}"

mkdir -p "$RESULT_DIR"

RUN_BIN="$GTI_BIN"
[[ "$STRATEGY" = "direct" || "$STRATEGY" = "lazy" ]] && [ -x "$GTI_N2_BIN" ] && RUN_BIN="$GTI_N2_BIN"
[[ "$STRATEGY" = "shg" ]] && [ -x "$GTI_SHG_BIN" ] && RUN_BIN="$GTI_SHG_BIN"
[[ "$STRATEGY" = "direct" || "$STRATEGY" = "lazy" ]] && [ ! -x "$GTI_N2_BIN" ] && echo "提示: direct/lazy 策略需原始 GTI_n2，请先运行 build_both.sh"
[[ "$STRATEGY" = "shg" ]] && [ ! -x "$GTI_SHG_BIN" ] && echo "提示: shg 策略需 GTI_shg，请先构建 SHG 版本"

if [ ! -x "$RUN_BIN" ]; then
  echo "错误: 可执行文件不存在: $RUN_BIN"
  exit 1
fi
if [ ! -f "$BASE" ] || [ ! -f "$QUERY" ] || [ ! -f "$GT" ]; then
  echo "错误: 缺少 $DATASET 数据集文件"
  echo "  BASE:  $BASE"
  echo "  QUERY: $QUERY"
  echo "  GT:    $GT"
  exit 1
fi

echo "========== 动态更新实验: $DATASET | 策略: $STRATEGY =========="
echo "  BASE: $BASE"
echo "  RESULT: $RESULT_DIR/"
echo ""

export GTI_LSH_ENABLED="${GTI_LSH_ENABLED:-0}"
export GTI_SPLIT_STRATEGY="${GTI_SPLIT_STRATEGY:-lb}"
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"
unset GTI_DELETE_DIRECT GTI_PATCH_DELETE_ONLY GTI_REBUILD_THRESHOLD GTI_DELETE_CHUNK_SIZE
case "$STRATEGY" in
  direct)   export GTI_DELETE_DIRECT=1 ;;
  lazy)     export GTI_REBUILD_THRESHOLD=999999 ;;
  wolverine) export GTI_PATCH_DELETE_ONLY=1 ;;
  shg)      export GTI_PATCH_DELETE_ONLY=1
            export GTI_DELETE_CHUNK_SIZE=2000 ;;
  hybrid)   ;;
  *) echo "错误: 未知策略 $STRATEGY"; usage ;;
esac
# gist/deep 使用 0.5% 以减少删除耗时；sift 保持 1%
[[ "$DATASET" = "gist" || "$DATASET" = "deep" ]] && export GTI_UPDATE_RATIO="${GTI_UPDATE_RATIO:-0.005}"
# gist: 2000 条删除，每批 200 条（可覆盖：GTI_UPDATE_DELETE_N, GTI_DELETE_CHUNK_SIZE）
[ "$DATASET" = "gist" ] && export GTI_UPDATE_DELETE_N="${GTI_UPDATE_DELETE_N:-2000}"
[ "$DATASET" = "gist" ] && [ "$STRATEGY" = "wolverine" ] && export GTI_DELETE_CHUNK_SIZE="${GTI_DELETE_CHUNK_SIZE:-200}"

LOG="${RESULT_DIR}/run.log"
"$RUN_BIN" "$BASE" "$QUERY" 3 "$GT" "${RESULT_DIR}/" | tee "$LOG"

echo ""
echo "输出: ${RESULT_DIR}/update_curve_k10_l60_ratio0.01.csv"
echo "     ${RESULT_DIR}/update_summary_k10_l60_ratio0.01.txt"
