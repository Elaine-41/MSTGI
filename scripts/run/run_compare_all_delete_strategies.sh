#!/bin/bash
#
# 四种删除策略对比：直接删除 / 伪删除 / Wolverine / 混合
# 结果统一存到 results/<dataset>/update/<strategy>/
# 指标：索引构建、插入、删除各阶段时间 + 各阶段 recall
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

GTI_BIN="./GTI/bin/GTI"
GTI_N2_BIN="./GTI/bin/GTI_n2"  # 原始方法，直接删除(一批次)使用
GTI_SHG_BIN="./GTI/bin/GTI_shg"  # SHG 后端，markDelete 删除
DATASET="${1:-sift}"

# 结果根目录：统一存到 update/ 下各策略子目录
declare -A DATASETS=(
  ["gist"]="./Datasets/gist/gist_base.fvecs|./Datasets/gist/gist_query.fvecs|./Datasets/gist/gist_groundtruth.ivecs|./results/gist/update"
  ["deep"]="./Datasets/deep/deep1M/deep1M_base.fvecs|./Datasets/deep/deep1M/deep1M_query.fvecs|./Datasets/deep/deep1M/deep1M_groundtruth.ivecs|./results/deep/update"
  ["sift"]="./Datasets/sift/sift/sift_base.fvecs|./Datasets/sift/sift/sift_query.fvecs|./Datasets/sift/sift/sift_groundtruth.ivecs|./results/sift/update"
)

# 五种策略：direct/lazy 用 GTI_n2(原始)，wolverine/hybrid 用 GTI(Wolverine)，shg 用 GTI_shg
# direct:   直接删除一批次，原始 GTI 方法（n2 buildFromDeletion，重建很慢）
# lazy:     伪删除，超阈值则原始方法重建（GTI_n2）
# wolverine: 纯 Wolverine patchDelete，每批直接 patch delete
# hybrid:   伪删除+Wolverine，超阈值集中 patch delete
# shg:      SHG 后端 markDelete，chunk=2000 与 Wolverine 一致
declare -A STRATEGIES=(
  ["direct"]="GTI_DELETE_DIRECT=1"
  ["lazy"]="GTI_REBUILD_THRESHOLD=5000"
  ["wolverine"]="GTI_PATCH_DELETE_ONLY=1"
  ["hybrid"]=""
  ["shg"]="GTI_PATCH_DELETE_ONLY=1 GTI_DELETE_CHUNK_SIZE=2000"
)
declare -A STRATEGY_BIN=(
  ["direct"]="GTI_n2"
  ["lazy"]="GTI_n2"
  ["wolverine"]="GTI"
  ["hybrid"]="GTI"
  ["shg"]="GTI_shg"
)

usage() {
  echo "用法: $0 <dataset> [run]"
  echo "  dataset: sift | deep | gist (默认 sift)"
  echo "  run: 可选，若为 run 则执行四种策略；否则仅汇总已有结果"
  echo ""
  echo "四种策略结果目录: results/<dataset>/update/<strategy>/"
  echo "  direct    - 直接删除（一批次）"
  echo "  lazy      - 伪删除（超阈值则重建）"
  echo "  wolverine - 纯 Wolverine patchDelete"
  echo "  hybrid    - 混合（伪删除+wolverine）"
  exit 1
}

[[ -z "$DATASET" || -z "${DATASETS[$DATASET]:-}" ]] && usage

IFS='|' read -r BASE QUERY GT UPDATE_DIR <<< "${DATASETS[$DATASET]}"

# 默认：gist/deep 0.5%，sift 1%。可通过 GTI_UPDATE_RATIO 覆盖（如 0.01=1%）
if [[ -n "${GTI_UPDATE_RATIO:-}" ]]; then
  UPDATE_RATIO="$GTI_UPDATE_RATIO"
else
  [[ "$DATASET" = "sift" ]] && UPDATE_RATIO="0.01" || UPDATE_RATIO="0.005"
fi
export GTI_UPDATE_RATIO="$UPDATE_RATIO"
echo "GTI_UPDATE_RATIO=$UPDATE_RATIO (update_n = data_size * $UPDATE_RATIO)"

# 可选：GTI_STRATEGIES="lazy wolverine shg" 仅运行指定策略（如与 lazy/wolverine 对比 SHG）
STRATEGY_LIST="${GTI_STRATEGIES:-direct lazy wolverine hybrid shg}"
STRATEGY_LIST=($STRATEGY_LIST)

if [[ "${2:-}" = "run" ]]; then
  echo "========== 运行删除策略: $DATASET (${STRATEGY_LIST[*]}) =========="
  for name in "${STRATEGY_LIST[@]}"; do
    echo ""
    echo ">>> 策略: $name <<<"
    RESULT_DIR="${UPDATE_DIR}/${name}"
    mkdir -p "$RESULT_DIR"
    RUN_BIN="$GTI_BIN"
    [[ "${STRATEGY_BIN[$name]}" = "GTI_n2" ]] && RUN_BIN="$GTI_N2_BIN"
    [[ "${STRATEGY_BIN[$name]}" = "GTI_shg" ]] && RUN_BIN="$GTI_SHG_BIN"
    [[ ! -x "$RUN_BIN" ]] && { echo "错误: $name 需 ${STRATEGY_BIN[$name]}，请先运行 build_both.sh 或 SHG 构建"; exit 1; }
    export GTI_LSH_ENABLED="${GTI_LSH_ENABLED:-0}"
    export GTI_SPLIT_STRATEGY="${GTI_SPLIT_STRATEGY:-lb}"
    export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"
    # gist 默认限制删除 50 条以缩短耗时；显式设置 GTI_UPDATE_DELETE_N 可覆盖（如 1000 与插入同量）
    [ "$DATASET" = "gist" ] && export GTI_UPDATE_DELETE_N="${GTI_UPDATE_DELETE_N:-50}"
    unset GTI_DELETE_DIRECT GTI_PATCH_DELETE_ONLY GTI_REBUILD_THRESHOLD GTI_DELETE_CHUNK_SIZE
    eval "export ${STRATEGIES[$name]}"
    LOG="${RESULT_DIR}/run.log"
    # gist 使用 n2(direct/lazy) 时 buildFromDeletion 易段错误，失败则跳过；wolverine/hybrid 无此问题
    if [[ "$DATASET" = "gist" && ( "$name" = "direct" || "$name" = "lazy" ) ]]; then
      "$RUN_BIN" "$BASE" "$QUERY" 3 "$GT" "${RESULT_DIR}/" | tee "$LOG" || { echo "注意: gist $name 失败，跳过"; true; }
    else
      "$RUN_BIN" "$BASE" "$QUERY" 3 "$GT" "${RESULT_DIR}/" | tee "$LOG"
    fi
  done
  echo ""
  echo "四种策略均已运行完成"
fi

# 汇总对比（文件名随 UPDATE_RATIO 变化；process 输出 ratio 为 3 位小数如 0.010）
RATIO_FMT=$(printf "%.3f" "$UPDATE_RATIO")
SUM_FILE="update_summary_k10_l60_ratio${UPDATE_RATIO}.txt"
SUM_FILE_ALT="update_summary_k10_l60_ratio${RATIO_FMT}.txt"
CSV_FILE="update_curve_k10_l60_ratio${UPDATE_RATIO}.csv"
CSV_FILE_ALT="update_curve_k10_l60_ratio${RATIO_FMT}.csv"
STRATEGY_NAMES=("direct:直接删除(一批次)" "lazy:伪删除" "wolverine:Wolverine" "hybrid:混合" "shg:SHG")

echo ""
echo "=============================================================="
echo "  四种删除策略对比: $DATASET (results/${DATASET}/update/)"
echo "=============================================================="

# 表头：各阶段时间 + 各阶段召回
printf "%-22s %8s %8s %8s %8s %10s %10s\n" "策略" "构建(s)" "插入(s)" "删除(s)" "总(s)" "R@插入后" "R@删除后"
printf "%s\n" "-------------------------------------------------------------------------------"

for entry in "${STRATEGY_NAMES[@]}"; do
  key="${entry%%:*}"
  label="${entry#*:}"
  dir="${UPDATE_DIR}/${key}"
  sum="$dir/$SUM_FILE"; [[ ! -f "$sum" ]] && sum="$dir/$SUM_FILE_ALT"
  csv="$dir/$CSV_FILE"; [[ ! -f "$csv" ]] && csv="$dir/$CSV_FILE_ALT"
  if [[ ! -f "$sum" ]]; then
    printf "%-22s %s\n" "$label" "(无结果)"
    continue
  fi
  idx_time=$(awk '/^Time of index construction:/ {print $NF}' "$sum" 2>/dev/null || echo "0")
  insert_avg=$(awk '/^Insert avg time \(s\/item\):/ {print $NF}' "$sum" 2>/dev/null || echo "0")
  insert_n=$(awk '/^Insert n:/ {print $NF}' "$sum" 2>/dev/null || echo "0")
  delete_n=$(awk '/^Delete n:/ {print $NF}' "$sum" 2>/dev/null || echo "0")
  delete_avg=$(awk '/^Delete avg time \(s\/item\):/ {print $NF}' "$sum" 2>/dev/null || echo "0")
  insert_total=$(awk "BEGIN {printf \"%.2f\", $insert_avg * $insert_n}" 2>/dev/null || echo "0")
  delete_total=$(awk "BEGIN {printf \"%.2f\", $delete_avg * $delete_n}" 2>/dev/null || echo "0")
  total=$(awk "BEGIN {printf \"%.2f\", $idx_time + $insert_total + $delete_total}" 2>/dev/null || echo "0")
  recall_insert="-"
  recall_delete="-"
  if [[ -f "$csv" ]]; then
    recall_insert=$(awk -F, '/^insert,/ {r=$NF} END {print r}' "$csv")
    recall_delete=$(grep -E "delete_|delete_rebuild|delete_patch" "$csv" 2>/dev/null | tail -1 | awk -F, '{print $NF}')
    [[ -z "$recall_delete" ]] && recall_delete=$(tail -1 "$csv" | awk -F, '{print $NF}')
  fi
  printf "%-22s %8.2f %8.2f %8.2f %8.2f %10s %10s\n" "$label" "$idx_time" "$insert_total" "$delete_total" "$total" "$recall_insert" "$recall_delete"
done

echo ""
echo "--- 各阶段 Recall 曲线 (CSV) ---"
for entry in "${STRATEGY_NAMES[@]}"; do
  key="${entry%%:*}"
  label="${entry#*:}"
  csv="${UPDATE_DIR}/${key}/${CSV_FILE}"
  [[ ! -f "$csv" ]] && csv="${UPDATE_DIR}/${key}/${CSV_FILE_ALT}"
  [[ -f "$csv" ]] && echo "  $label: $csv"
done

# 生成统一汇总 CSV（各阶段时间+召回）
OUTPUT_CSV="${UPDATE_DIR}/comparison_all_strategies.csv"
echo "strategy,backend,idx_s,insert_s,delete_s,total_s,recall_after_insert,recall_after_delete" > "$OUTPUT_CSV"
for entry in "${STRATEGY_NAMES[@]}"; do
  key="${entry%%:*}"
  dir="${UPDATE_DIR}/${key}"
  sum="$dir/$SUM_FILE"; [[ ! -f "$sum" ]] && sum="$dir/$SUM_FILE_ALT"
  csv="$dir/$CSV_FILE"; [[ ! -f "$csv" ]] && csv="$dir/$CSV_FILE_ALT"
  [[ ! -f "$sum" ]] && continue
  backend="${STRATEGY_BIN[$key]:-GTI}"
  idx_time=$(awk '/^Time of index construction:/ {print $NF}' "$sum")
  insert_avg=$(awk '/^Insert avg time \(s\/item\):/ {print $NF}' "$sum")
  insert_n=$(awk '/^Insert n:/ {print $NF}' "$sum")
  delete_n=$(awk '/^Delete n:/ {print $NF}' "$sum")
  delete_avg=$(awk '/^Delete avg time \(s\/item\):/ {print $NF}' "$sum")
  insert_total=$(awk "BEGIN {printf \"%.4f\", $insert_avg * $insert_n}")
  delete_total=$(awk "BEGIN {printf \"%.4f\", $delete_avg * $delete_n}")
  total=$(awk "BEGIN {printf \"%.4f\", $idx_time + $insert_total + $delete_total}")
  recall_insert="-"
  recall_delete="-"
  if [[ -f "$csv" ]]; then
    recall_insert=$(awk -F, '/^insert,/ {r=$NF} END {print r+0}' "$csv")
    recall_delete=$(grep -E "delete_|delete_rebuild|delete_patch" "$csv" 2>/dev/null | tail -1 | awk -F, '{print $NF}')
    [[ -z "$recall_delete" ]] && recall_delete=$(tail -1 "$csv" | awk -F, '{print $NF}')
  fi
  echo "$key,$backend,$idx_time,$insert_total,$delete_total,$total,$recall_insert,$recall_delete" >> "$OUTPUT_CSV"
done
echo ""
echo "统一汇总: $OUTPUT_CSV"
echo "  direct/lazy=GTI_n2(原始), wolverine/hybrid=GTI(Wolverine), shg=GTI_shg"
