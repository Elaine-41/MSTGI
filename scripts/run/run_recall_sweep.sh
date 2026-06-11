#!/bin/bash
#
# Wolverine 召回调参扫实验：GTI_WOLVERINE_EF_BUILD × GTI_SEARCH_EF_MULTIPLIER
# 结果存到 results/sift/update/recall_sweep/
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"
cd "$ROOT"

GTI_BIN="./GTI/bin/GTI"
BASE="./Datasets/sift/sift/sift_base.fvecs"
QUERY="./Datasets/sift/sift/sift_query.fvecs"
GT="./Datasets/sift/sift/sift_groundtruth.ivecs"
OUT_DIR="./results/sift/update/recall_sweep"
SUM_FILE="update_summary_k10_l60_ratio0.01.txt"
CSV_FILE="update_curve_k10_l60_ratio0.01.csv"

[ ! -x "$GTI_BIN" ] && { echo "错误: $GTI_BIN 不存在"; exit 1; }
[ ! -f "$BASE" ] && { echo "错误: 数据集不存在"; exit 1; }

mkdir -p "$OUT_DIR"
export GTI_LSH_ENABLED=0
export GTI_SPLIT_STRATEGY=lb
export OMP_NUM_THREADS=1
export GTI_PATCH_DELETE_ONLY=1

# 组合: ef_build × ef_multiplier
# ef_build: 100(原), 160(n2对齐), 200
# ef_multiplier: 5(默认), 8, 10
EF_BUILDS=(100 160 200)
EF_MULTS=(5 8 10)

echo "========== Wolverine 召回扫参 =========="
echo "ef_build: ${EF_BUILDS[*]}"
echo "ef_multiplier: ${EF_MULTS[*]}"
echo ""

RESULT_CSV="${OUT_DIR}/sweep_results.csv"
echo "ef_build,ef_mult,build_s,insert_s,delete_s,recall_after_insert,recall_after_delete" > "$RESULT_CSV"

for ef_build in "${EF_BUILDS[@]}"; do
  for ef_mult in "${EF_MULTS[@]}"; do
    name="efb${ef_build}_em${ef_mult}"
    dir="${OUT_DIR}/${name}"
    mkdir -p "$dir"
    echo ">>> $name (ef_build=$ef_build, ef_mult=$ef_mult) <<<"
    export GTI_WOLVERINE_EF_BUILD=$ef_build
    export GTI_SEARCH_EF_MULTIPLIER=$ef_mult
    "$GTI_BIN" "$BASE" "$QUERY" 3 "$GT" "${dir}/" | tee "${dir}/run.log" || true
    if [[ -f "$dir/$SUM_FILE" && -f "$dir/$CSV_FILE" ]]; then
      idx=$(awk '/^Time of index construction:/ {print $NF}' "$dir/$SUM_FILE")
      ia=$(awk '/^Insert avg time \(s\/item\):/ {print $NF}' "$dir/$SUM_FILE")
      in=$(awk '/^Insert n:/ {print $NF}' "$dir/$SUM_FILE")
      da=$(awk '/^Delete avg time \(s\/item\):/ {print $NF}' "$dir/$SUM_FILE")
      dn=$(awk '/^Delete n:/ {print $NF}' "$dir/$SUM_FILE")
      insert_s=$(awk "BEGIN {printf \"%.2f\", $ia*$in}")
      delete_s=$(awk "BEGIN {printf \"%.2f\", $da*$dn}")
      r_insert=$(awk -F, '/^insert,/ {r=$NF} END {print r}' "$dir/$CSV_FILE")
      r_delete=$(grep -E "delete_" "$dir/$CSV_FILE" | tail -1 | awk -F, '{print $NF}')
      echo "$ef_build,$ef_mult,$idx,$insert_s,$delete_s,$r_insert,$r_delete" >> "$RESULT_CSV"
      echo "  recall_insert=$r_insert, recall_delete=$r_delete"
    fi
    echo ""
  done
done

echo "========== 汇总 =========="
column -t -s, "$RESULT_CSV"
echo ""
echo "结果: $RESULT_CSV"
echo "各配置详情: ${OUT_DIR}/efb*_em*/"
