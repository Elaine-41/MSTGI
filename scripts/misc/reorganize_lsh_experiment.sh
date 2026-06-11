#!/bin/bash
#
# 重新组织LSH实验结果文件夹结构
# 新结构：
#   results/lsh_experiment/
#     {dataset}/
#       baseline/
#         run{1,2,3}/
#       lsh_comparison/
#         run{1,2,3}/
#       param_sweep/
#         {config_id}/
#           run{1,2}/
#     summary/
#       *.csv
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

SRC_DIR="./results/lsh_experiment"
DST_DIR="./results/lsh_experiment_reorganized"

echo "开始重新组织LSH实验结果..."
echo "源目录: $SRC_DIR"
echo "目标目录: $DST_DIR"
echo ""

# 创建新目录结构
mkdir -p "$DST_DIR/summary"
for dataset in deep gist sift; do
  mkdir -p "$DST_DIR/$dataset/baseline"
  mkdir -p "$DST_DIR/$dataset/lsh_comparison"
  mkdir -p "$DST_DIR/$dataset/param_sweep"
done

# 移动CSV文件到summary目录
if [ -f "$SRC_DIR/deep_lsh_comparison.csv" ]; then
  cp "$SRC_DIR/deep_lsh_comparison.csv" "$DST_DIR/summary/"
fi
if [ -f "$SRC_DIR/lsh_multi_dataset_comparison.csv" ]; then
  cp "$SRC_DIR/lsh_multi_dataset_comparison.csv" "$DST_DIR/summary/"
fi
if [ -f "$SRC_DIR/lsh_param_sweep.csv" ]; then
  cp "$SRC_DIR/lsh_param_sweep.csv" "$DST_DIR/summary/"
fi

# 移动baseline实验
for dataset in deep gist sift; do
  # 有数据集前缀的baseline
  for run in 1 2 3; do
    if [ -d "$SRC_DIR/${dataset}_baseline_run${run}" ]; then
      mv "$SRC_DIR/${dataset}_baseline_run${run}" "$DST_DIR/$dataset/baseline/run${run}"
      echo "移动: ${dataset}_baseline_run${run} -> $dataset/baseline/run${run}"
    fi
  done
  
  # 没有数据集前缀的baseline（假设是deep的）
  if [ "$dataset" = "deep" ]; then
    for run in 1 2 3; do
      if [ -d "$SRC_DIR/baseline_run${run}" ]; then
        if [ ! -d "$DST_DIR/$dataset/baseline/run${run}" ]; then
          mv "$SRC_DIR/baseline_run${run}" "$DST_DIR/$dataset/baseline/run${run}"
          echo "移动: baseline_run${run} -> $dataset/baseline/run${run}"
        else
          echo "跳过: baseline_run${run} (目标已存在)"
        fi
      fi
    done
  fi
done

# 移动LSH对比实验
for dataset in deep gist sift; do
  for run in 1 2 3; do
    if [ -d "$SRC_DIR/${dataset}_lsh_run${run}" ]; then
      mv "$SRC_DIR/${dataset}_lsh_run${run}" "$DST_DIR/$dataset/lsh_comparison/run${run}"
      echo "移动: ${dataset}_lsh_run${run} -> $dataset/lsh_comparison/run${run}"
    fi
  done
done

# 移动没有数据集前缀的lsh_run（假设是deep的）
for run in 1 2 3; do
  if [ -d "$SRC_DIR/lsh_run${run}" ]; then
    if [ ! -d "$DST_DIR/deep/lsh_comparison/run${run}" ]; then
      mv "$SRC_DIR/lsh_run${run}" "$DST_DIR/deep/lsh_comparison/run${run}"
      echo "移动: lsh_run${run} -> deep/lsh_comparison/run${run}"
    else
      echo "跳过: lsh_run${run} (目标已存在)"
    fi
  fi
done

# 移动参数扫描实验
for dataset in deep gist sift; do
  # 匹配模式: {dataset}_ef{L}L_L{L}K{K}s{s}d{d}_run{run}
  for dir in "$SRC_DIR/${dataset}_ef"*_run*; do
    if [ -d "$dir" ]; then
      # 提取配置ID (例如: ef5L_L2K4s4d16)
      config_id=$(basename "$dir" | sed "s/${dataset}_//" | sed "s/_run[0-9]*$//")
      run_num=$(basename "$dir" | sed "s/.*_run//")
      
      mkdir -p "$DST_DIR/$dataset/param_sweep/$config_id"
      mv "$dir" "$DST_DIR/$dataset/param_sweep/$config_id/run${run_num}"
      echo "移动: $(basename "$dir") -> $dataset/param_sweep/$config_id/run${run_num}"
    fi
  done
done

echo ""
echo "重新组织完成！"
echo "新结构位于: $DST_DIR"
echo ""
echo "目录结构："
tree -L 3 "$DST_DIR" 2>/dev/null || find "$DST_DIR" -type d | sort
