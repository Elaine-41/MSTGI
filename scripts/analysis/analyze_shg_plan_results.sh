#!/bin/bash
#
# 分析 SHG Plan 验证结果：baseline vs prune0
# 若 prune0 recall 明显下降或 search 未提速，则建议回滚 S4
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

echo "========== SHG Plan 验证结果分析 =========="
echo ""

for dataset in sift deep; do
  echo "--- $dataset ---"
  base_dir="./results/${dataset}"
  for typ in update aknn_compare; do
    b_dir="${base_dir}/${typ}/shg_baseline"
    p_dir="${base_dir}/${typ}/shg_prune0"
    if [ -d "$b_dir" ] && [ -d "$p_dir" ]; then
      if [ "$typ" = "update" ]; then
        b_sum=$(ls "$b_dir"/update_summary_*.txt 2>/dev/null | head -1)
        p_sum=$(ls "$p_dir"/update_summary_*.txt 2>/dev/null | head -1)
        if [ -f "$b_sum" ] && [ -f "$p_sum" ]; then
          b_del=$(grep "Delete avg" "$b_sum" | awk '{print $NF}')
          p_del=$(grep "Delete avg" "$p_sum" | awk '{print $NF}')
          b_recall=$(grep -oP "recall.*?\d+\.\d+" "$b_dir/run.log" | tail -1 | grep -oP "\d+\.\d+" | tail -1)
          p_recall=$(grep -oP "recall.*?\d+\.\d+" "$p_dir/run.log" | tail -1 | grep -oP "\d+\.\d+" | tail -1)
          echo "  Update: baseline delete_avg=${b_del}s/item, recall~${b_recall:-?}"
          echo "          prune0   delete_avg=${p_del}s/item, recall~${p_recall:-?}"
        fi
      else
        b_cost=$(ls "$b_dir"/cost_*.txt 2>/dev/null | head -1)
        p_cost=$(ls "$p_dir"/cost_*.txt 2>/dev/null | head -1)
        if [ -f "$b_cost" ] && [ -f "$p_cost" ]; then
          b_search=$(grep "Search time" "$b_cost" | awk -F: '{gsub(/^[ \t]+/,"",$2); print $2}')
          p_search=$(grep "Search time" "$p_cost" | awk -F: '{gsub(/^[ \t]+/,"",$2); print $2}')
          b_recall=$(grep "Search recall" "$b_cost" | awk -F: '{gsub(/^[ \t]+/,"",$2); print $2}')
          p_recall=$(grep "Search recall" "$p_cost" | awk -F: '{gsub(/^[ \t]+/,"",$2); print $2}')
          echo "  A-kNN:  baseline search=${b_search}s, recall=${b_recall}"
          echo "          prune0   search=${p_search}s, recall=${p_recall}"
        fi
      fi
    else
      echo "  $typ: 缺失 baseline 或 prune0 结果"
    fi
  done
  echo ""
done

echo "========== 结论建议 =========="
echo "若 prune0 的 recall 下降超过 0.02 且 search 未明显提速，则回滚 S4（保持 PRUNE 默认开启）"
echo "若 prune0 的 search 提速明显且 recall 下降可接受，可考虑在低维场景使用 GTI_SHG_PRUNE=0"
