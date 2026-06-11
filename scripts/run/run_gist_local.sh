#!/bin/bash

# 运行Gist数据集实验的脚本（使用本地Datasets/gist目录）

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

# 数据集路径
DATASET_DIR="./Datasets/gist"
GTI_BIN="./GTI/bin/GTI"
RESULT_DIR="./results/gist"

# 检查GTI可执行文件
if [ ! -f "$GTI_BIN" ]; then
    echo "错误: GTI可执行文件不存在: $GTI_BIN"
    echo "请先编译GTI项目"
    exit 1
fi

# 检查数据集文件
if [ ! -f "${DATASET_DIR}/gist_base.fvecs" ]; then
    echo "错误: 数据集文件不存在: ${DATASET_DIR}/gist_base.fvecs"
    exit 1
fi

if [ ! -f "${DATASET_DIR}/gist_query.fvecs" ]; then
    echo "错误: 查询文件不存在: ${DATASET_DIR}/gist_query.fvecs"
    exit 1
fi

# 检查ground truth文件
GT_FILE=""
if [ -f "${DATASET_DIR}/gist_groundtruth.ivecs" ]; then
    GT_FILE="${DATASET_DIR}/gist_groundtruth.ivecs"
elif [ -f "${DATASET_DIR}/gist.ivecs" ]; then
    GT_FILE="${DATASET_DIR}/gist.ivecs"
elif [ -f "${DATASET_DIR}/groundtruth.ivecs" ]; then
    GT_FILE="${DATASET_DIR}/groundtruth.ivecs"
fi

if [ -z "$GT_FILE" ]; then
    echo "警告: Ground truth文件不存在"
    echo "将跳过近似k-NN搜索（需要ground truth），只运行精确搜索"
    USE_GT=false
else
    USE_GT=true
    echo "找到Ground truth文件: $GT_FILE"
fi

# 创建结果目录（当前只做近似搜索，结果保存到预实验目录）
APPROX_RESULT_DIR="${RESULT_DIR}/pre_experiments/approximate"
mkdir -p "${APPROX_RESULT_DIR}"

echo "========== 开始Gist数据集实验 =========="
echo "数据集: ${DATASET_DIR}"
echo "近似搜索结果目录: ${APPROX_RESULT_DIR}"
echo "（已按需求暂缓精确搜索）"
echo ""

# 实验参数
L=60      # 候选集大小
K=10      # k-NN中的k

# 运行近似k-NN搜索（需要ground truth），同时采集峰值内存
if [ "$USE_GT" = true ]; then
    echo "运行近似k-NN搜索 (A$K-NNS)..."
    echo "参数: L=$L, k=$K"
    echo "结果将保存到: ${APPROX_RESULT_DIR}/"
    echo "命令: $GTI_BIN ${DATASET_DIR}/gist_base.fvecs ${DATASET_DIR}/gist_query.fvecs 0 $GT_FILE $L $K ${APPROX_RESULT_DIR}/"
    echo ""

    TIME_LOG="${APPROX_RESULT_DIR}/time_mem_k${K}_l${L}.txt"
    rm -f "$TIME_LOG"

    # 使用 /usr/bin/time -v 采集峰值 RSS
    set +e
    /usr/bin/time -v "$GTI_BIN" \
        "${DATASET_DIR}/gist_base.fvecs" \
        "${DATASET_DIR}/gist_query.fvecs" \
        0 \
        "$GT_FILE" \
        $L \
        $K \
        "${APPROX_RESULT_DIR}/" 2> "$TIME_LOG"
    rc=$?
    set -e

    if [ $rc -ne 0 ]; then
        echo "错误: GTI 运行失败，退出码=$rc；请查看 $TIME_LOG"
        exit $rc
    fi

    # 解析峰值RSS（KB），并附加到结果文件中
    RSS_KB="$(awk -F: '/Maximum resident set size/ {gsub(/^[ \t]+/,"",$2); print $2}' "$TIME_LOG" | tail -1)"
    if [ -n "$RSS_KB" ]; then
        RSS_GB="$(awk -v kb="$RSS_KB" 'BEGIN{printf "%.6f", kb/1024/1024}')"
        RSS_TB="$(awk -v gb="$RSS_GB" 'BEGIN{printf "%.6f", gb/1024}')"

        # 估算数据集本身的大小（base + query 文件字节数），用来近似扣除“数据规模”占用
        BASE_BYTES=$(stat -c%s "${DATASET_DIR}/gist_base.fvecs")
        QUERY_BYTES=$(stat -c%s "${DATASET_DIR}/gist_query.fvecs")
        DATASET_KB=$(( (BASE_BYTES + QUERY_BYTES) / 1024 ))
        INDEX_KB=$(( RSS_KB > DATASET_KB ? RSS_KB - DATASET_KB : 0 ))
        INDEX_GB="$(awk -v kb="$INDEX_KB" 'BEGIN{printf "%.6f", kb/1024/1024}')"
        RESULT_FILE="${APPROX_RESULT_DIR}/cost_${K}_${L}.txt"
        {
          echo ""
          echo "Peak RSS (all): ${RSS_KB} KB (${RSS_GB} GB, ${RSS_TB} TB)"
          echo "Approx index RSS (excluding base+query files): ${INDEX_KB} KB (${INDEX_GB} GB)"
        } >> "$RESULT_FILE"
        echo "已将内存信息写入: $RESULT_FILE"
    else
        echo "警告: 未能从 /usr/bin/time -v 解析峰值RSS；请查看 $TIME_LOG"
    fi

    echo ""
fi

# 跳过精确范围查询（根据用户要求）
# echo "运行精确范围查询 (Exact Range Query)..."
# RADIUS=400
# echo "参数: radius=$RADIUS"
# echo "命令: $GTI_BIN ${DATASET_DIR}/gist_base.fvecs ${DATASET_DIR}/gist_query.fvecs 2 $RADIUS ${RESULT_DIR}/"
# echo ""
# $GTI_BIN \
#     "${DATASET_DIR}/gist_base.fvecs" \
#     "${DATASET_DIR}/gist_query.fvecs" \
#     2 \
#     $RADIUS \
#     "${RESULT_DIR}/"
# echo ""

echo "========== 实验完成 =========="
echo ""
echo "近似搜索结果保存在: ${APPROX_RESULT_DIR}/"
if [ "$USE_GT" = true ]; then
    ls -lh "${APPROX_RESULT_DIR}/" 2>/dev/null || echo "近似搜索结果目录为空"
fi