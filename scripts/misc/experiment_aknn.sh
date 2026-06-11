#!/bin/bash

# GTI 近似k-NN搜索参数实验脚本
# 测试不同k值和候选集大小L对性能的影响

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
# 数据集路径（相对于GTI目录）
DATA_PATH="../Datasets/bigann_example_base.fvecs"
QUERY_PATH="../Datasets/bigann_example_query.fvecs"
GROUND_TRUTH_PATH="../Datasets/bigann_example_groundtruth.ivecs"
RESULT_DIR="../Datasets/"

# 进入GTI目录
cd GTI

# GTI可执行文件路径
GTI_BIN="./bin/GTI"

# 参数范围设置
K_VALUES=(10 20 50 100)  # k值：最近邻数量

# 为每个k值动态设置合适的L值范围 (确保L > k)
declare -A L_RANGES
L_RANGES[10]="20 30 50 100 150"  # 对于k=10，L从20开始
L_RANGES[20]="30 50 100 150 200" # 对于k=20，L从30开始
L_RANGES[50]="60 100 150 200 250" # 对于k=50，L从60开始
L_RANGES[100]="120 150 200 250 300" # 对于k=100，L从120开始

# 结果文件
SUMMARY_FILE="../aknn_experiment_results.csv"

echo "开始GTI近似k-NN搜索参数实验..."
echo "参数组合："
echo "k值 (search_para2): ${K_VALUES[*]}"
echo "L值范围 (search_para1，动态调整以确保L > k)："
for k in "${K_VALUES[@]}"; do
    echo "  k=$k: L=${L_RANGES[$k]}"
done
echo ""

# 创建结果汇总文件
echo "k,L,index_time,search_time,recall" > "$SUMMARY_FILE"

# 运行实验
for k in "${K_VALUES[@]}"; do
    # 获取当前k对应的L值范围
    L_RANGE=(${L_RANGES[$k]})

    for L in "${L_RANGE[@]}"; do
        echo "运行实验: k=$k, L=$L"

        # 运行GTI程序
        $GTI_BIN "$DATA_PATH" "$QUERY_PATH" 0 "$GROUND_TRUTH_PATH" "$L" "$k" "$RESULT_DIR"

        # 解析结果文件
        RESULT_FILE="${RESULT_DIR}cost_${k}_${L}.txt"

        if [ -f "$RESULT_FILE" ]; then
            # 提取性能指标
            INDEX_TIME=$(grep "Time of index construction:" "$RESULT_FILE" | awk '{print $5}')
            SEARCH_TIME=$(grep "Search time:" "$RESULT_FILE" | awk '{print $3}')
            RECALL=$(grep "Search recall:" "$RESULT_FILE" | awk '{print $3}')

            # 保存到汇总文件
            echo "$k,$L,$INDEX_TIME,$SEARCH_TIME,$RECALL" >> "$SUMMARY_FILE"

            echo "  结果: 索引时间=${INDEX_TIME}s, 搜索时间=${SEARCH_TIME}s, 召回率=${RECALL}"
        else
            echo "  警告: 结果文件 $RESULT_FILE 未找到"
        fi

        echo ""
    done
done

echo "实验完成！结果已保存到: $SUMMARY_FILE"
echo ""

# 返回上级目录
cd ..

# 显示汇总结果
echo "实验结果汇总:"
echo "================================================================"
cat "$SUMMARY_FILE" | column -t -s','

echo ""
echo "详细分析:"

# 分析不同k值下的最佳L
echo "1. 不同k值下的最佳L选择 (基于召回率和搜索时间):"
for k in "${K_VALUES[@]}"; do
    if grep -q "^$k," "$SUMMARY_FILE"; then
        echo "k=$k:"
        grep "^$k," "$SUMMARY_FILE" | sort -t',' -k5 -nr | head -3 | while IFS=',' read -r k_val l_val idx_time search_time recall; do
            echo "  L=$l_val, 召回率=$recall, 搜索时间=${search_time}s"
        done
        echo ""
    fi
done

# 分析L对性能的影响
echo "2. 固定k=10时，L对性能的影响:"
echo "L,召回率,搜索时间"
grep "^10," "$SUMMARY_FILE" | sort -t',' -k2 -n | while IFS=',' read -r k_val l_val idx_time search_time recall; do
    echo "$l_val,$recall,${search_time}s"
done

echo ""
echo "实验完成！"