#!/bin/bash
#
# 消融实验：仅跑 MST + Wolverine_d2 组合（Deep）
# 其他三组（baseline_lb, mst_opt, wolverine_d2）使用 deep 历史结果
# 结果: results/ablation/deep/
# 对比文档: results/ablation/ablation_deep_compare.md
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

GTI_BIN="./GTI/bin/GTI"
BASE="./Datasets/deep/deep1M/deep1M_base.fvecs"
QUERY="./Datasets/deep/deep1M/deep1M_query.fvecs"
GT="./Datasets/deep/deep1M/deep1M_groundtruth.ivecs"
L=60
K=10
UPDATE_RATIO=0.005
RATIO_SUFFIX="0.005"

RESULTS_ROOT="./results/ablation/deep"
CSV="${RESULTS_ROOT}/ablation_compare.csv"

export GTI_LSH_ENABLED=0
export GTI_UPDATE_RATIO="$UPDATE_RATIO"
export OMP_NUM_THREADS=1

if [ ! -f "$BASE" ] || [ ! -f "$QUERY" ] || [ ! -f "$GT" ]; then
  echo "错误: deep 数据集文件不完整"
  exit 1
fi

mkdir -p "$RESULTS_ROOT"
echo "variant,aknn_build_s,aknn_search_s,aknn_recall,update_build_s,update_insert_avg_s,update_delete_avg_s,update_final_recall" > "$CSV"

# Deep MST 最优: exp2 (use_sampling=1, 32/64/0.05)
export GTI_SPLIT_STRATEGY=mst
export GTI_MST_USE_SAMPLING=1
export GTI_MST_FULL_THRESHOLD=32
export GTI_MST_SAMPLE_SIZE=64
export GTI_MST_BALANCE_MIN_FRAC=0.05
export GTI_MST_SEED=42
export GTI_PATCH_DELETE_ONLY=1
export GTI_TREE_PRIORITY_SAME_LEAF=1
export GTI_WOLVERINE_DELETE_MODEL=Wolverine

echo "=========================================="
echo "消融实验: Deep - 仅跑 MST+Wolverine_d2 组合"
echo "历史结果: baseline_lb, mst_opt, wolverine_d2 来自 results/deep/"
echo "结果输出: $RESULTS_ROOT"
echo "=========================================="

dir="${RESULTS_ROOT}/mst_wolverine_d2"
rm -rf "$dir"
mkdir -p "$dir/aknn" "$dir/update"

echo "========== [deep][mst_wolverine_d2] A-kNN =========="
"$GTI_BIN" "$BASE" "$QUERY" 0 "$GT" "$L" "$K" "$dir/aknn/" 2>&1 | tee "$dir/aknn/run.log"

echo "========== [deep][mst_wolverine_d2] Update =========="
"$GTI_BIN" "$BASE" "$QUERY" 3 "$GT" "$dir/update/" 2>&1 | tee "$dir/update/run.log"

aknn_file="$dir/aknn/cost_${K}_${L}.txt"
upd_sum="$dir/update/update_summary_k10_l60_ratio${RATIO_SUFFIX}.txt"
upd_csv="$dir/update/update_curve_k10_l60_ratio${RATIO_SUFFIX}.csv"

aknn_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
aknn_search="$(awk -F: '/Search time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
aknn_recall="$(awk -F: '/Search recall/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
upd_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
upd_insert="$(awk -F: '/Insert avg time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
upd_delete="$(awk -F: '/Delete avg time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
upd_recall="$(tail -1 "$upd_csv" | awk -F, '{print $5}')"

echo "mst_wolverine_d2,${aknn_build},${aknn_search},${aknn_recall},${upd_build},${upd_insert},${upd_delete},${upd_recall}" >> "$CSV"

echo ""
echo "========== 生成对比文档 =========="

# 从历史结果提取 baseline, mst_opt, wolverine_d2
MT="results/split_compare/mst_param_tuning/mst_param_tuning_all1.csv"
W2_SUM="results/deep/update/wolverine_Wolverine_d2/update_summary_k10_l60_ratio0.005.txt"
W2_CSV="results/deep/update/wolverine_Wolverine_d2/update_curve_k10_l60_ratio0.005.csv"

# baseline 均值 (deep,baseline 3 runs): col9=aknn_build,col10=search,col11=recall,col12=upd_build,col13=insert,col14=upd_recall
bl_vals=$(grep "^deep,baseline," "$MT" 2>/dev/null | awk -F, '{a+=$9;b+=$10;c+=$11;d+=$12;e+=$13;f+=$14;n++} END{if(n>0) printf "%.1f,%.4f,%.3f,%.1f,%.6f,%.3f",a/n,b/n,c/n,d/n,e/n,f/n}')
# mst_opt(exp2) 均值 (deep,exp2 3 runs)
mst_vals=$(grep "^deep,exp2," "$MT" 2>/dev/null | awk -F, '{a+=$9;b+=$10;c+=$11;d+=$12;e+=$13;f+=$14;n++} END{if(n>0) printf "%.1f,%.4f,%.3f,%.1f,%.6f,%.3f",a/n,b/n,c/n,d/n,e/n,f/n}')
# wolverine_d2: update 有 build/insert/delete/recall，无独立 aknn
w2_build=$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$W2_SUM" 2>/dev/null | tail -1)
w2_insert=$(awk -F: '/Insert avg time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$W2_SUM" 2>/dev/null | tail -1)
w2_delete=$(awk -F: '/Delete avg time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$W2_SUM" 2>/dev/null | tail -1)
w2_recall=$(tail -1 "$W2_CSV" 2>/dev/null | awk -F, '{print $5}')

# 补充 wolverine_d2 的 aknn（来自同目录若存在，否则留空；wolverine 的 update 含 build 不含独立 aknn，用 update_build 近似）
w2_aknn_build="$w2_build"
w2_aknn_search="—"
w2_aknn_recall="—"

COMPARE_MD="${RESULTS_ROOT}/../ablation_deep_compare.md"
mkdir -p "$(dirname "$COMPARE_MD")"

cat > "$COMPARE_MD" << EOF
# Deep 消融实验对比

**配置**：ratio=0.005，L=60，k=10

## 一、结果汇总

| 变体 | aknn_build_s | aknn_search_s | aknn_recall | update_build_s | update_insert_s | update_delete_s | update_final_recall |
|------|--------------|---------------|-------------|----------------|-----------------|-----------------|---------------------|
| baseline_lb (历史) | $(echo "$bl_vals" | cut -d, -f1) | $(echo "$bl_vals" | cut -d, -f2) | $(echo "$bl_vals" | cut -d, -f3) | $(echo "$bl_vals" | cut -d, -f4) | $(echo "$bl_vals" | cut -d, -f5) | — | $(echo "$bl_vals" | cut -d, -f6) |
| mst_opt (历史) | $(echo "$mst_vals" | cut -d, -f1) | $(echo "$mst_vals" | cut -d, -f2) | $(echo "$mst_vals" | cut -d, -f3) | $(echo "$mst_vals" | cut -d, -f4) | $(echo "$mst_vals" | cut -d, -f5) | — | $(echo "$mst_vals" | cut -d, -f6) |
| wolverine_d2 (历史) | ${w2_build:-—} | ${w2_aknn_search} | ${w2_aknn_recall} | ${w2_build:-—} | ${w2_insert:-—} | ${w2_delete:-—} | ${w2_recall:-—} |
| **mst_wolverine_d2 (新)** | **${aknn_build}** | **${aknn_search}** | **${aknn_recall}** | **${upd_build}** | **${upd_insert}** | **${upd_delete}** | **${upd_recall}** |

*历史 baseline/mst_opt 来自 \`results/split_compare/mst_param_tuning/mst_param_tuning_all1.csv\`（n2 后端 rebuild）*
*历史 wolverine_d2 来自 \`results/deep/update/wolverine_Wolverine_d2/\`*

## 二、对比分析

- **Recall**：mst_wolverine_d2 对比 baseline / mst_opt / wolverine_d2
- **删除速度**：mst_wolverine_d2 与 wolverine_d2 均为 patchDelete，可比
- **建库/搜索**：MST 分裂 vs LB 分裂

## 三、结论

（待补充）

EOF

echo ""
echo "=========================================="
echo "消融实验完成！"
echo "结果: $CSV"
echo "对比文档: $COMPARE_MD"
echo "=========================================="
column -t -s, "$CSV" 2>/dev/null || cat "$CSV"
