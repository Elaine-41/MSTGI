#!/bin/bash
#
# 汇总MST参数调优实验结果，计算每组3次运行的平均值
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

RESULTS_ROOT="./results/split_compare/mst_param_tuning"
CSV_ALL="${RESULTS_ROOT}/mst_param_tuning_all.csv"
CSV_AGGREGATED="${RESULTS_ROOT}/mst_param_tuning_aggregated.csv"

if [ ! -f "$CSV_ALL" ]; then
  echo "错误: 结果文件不存在: $CSV_ALL"
  exit 1
fi

echo "正在汇总实验结果..."

# 创建汇总CSV（平均值）
echo "dataset,variant,split_strategy,use_sampling,full_threshold,sample_size,balance_min_frac,aknn_build_s,aknn_search_s,aknn_recall,update_build_s,update_insert_avg_s_per_item,update_final_recall" > "$CSV_AGGREGATED"

# 使用awk计算每组3次运行的平均值
awk -F',' '
BEGIN {
  OFS=","
}
NR == 1 { next }  # 跳过标题行
{
  key = $1 "," $2 "," $4 "," $5 "," $6 "," $7 "," $8  # dataset,variant,split_strategy,use_sampling,full_threshold,sample_size,balance_min_frac
  count[key]++
  aknn_build[key] += $9
  aknn_search[key] += $10
  aknn_recall[key] += $11
  update_build[key] += $12
  update_insert[key] += $13
  update_recall[key] += $14
}
END {
  for (key in count) {
    n = count[key]
    split(key, parts, ",")
    print parts[1], parts[2], parts[3], parts[4], parts[5], parts[6], parts[7], \
          aknn_build[key]/n, aknn_search[key]/n, aknn_recall[key]/n, \
          update_build[key]/n, update_insert[key]/n, update_recall[key]/n
  }
}' "$CSV_ALL" | sort >> "$CSV_AGGREGATED"

echo "汇总完成！结果已保存到: $CSV_AGGREGATED"
echo ""
echo "汇总结果预览:"
head -20 "$CSV_AGGREGATED" | column -t -s','
