#!/bin/bash

# 运行Gist数据集实验的脚本

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

# 数据集路径
DATASET_DIR="/udata_disk/shiyi/gist"
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
    echo "请先运行: bash scripts/data/download_gist.sh"
    exit 1
fi

if [ ! -f "${DATASET_DIR}/gist_query.fvecs" ]; then
    echo "错误: 查询文件不存在: ${DATASET_DIR}/gist_query.fvecs"
    exit 1
fi

# 检查ground truth文件（可能有不同的命名）
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

# 创建结果目录
mkdir -p "${RESULT_DIR}"

echo "========== 开始Gist数据集实验 =========="
echo "数据集: ${DATASET_DIR}"
echo "结果目录: ${RESULT_DIR}"
echo ""

# 实验参数
L=60      # 候选集大小
K=10      # k-NN中的k

# 运行近似k-NN搜索（需要ground truth）
if [ "$USE_GT" = true ]; then
    echo "运行近似k-NN搜索 (A$K-NNS)..."
    echo "参数: L=$L, k=$K"
    echo ""
    $GTI_BIN \
        "${DATASET_DIR}/gist_base.fvecs" \
        "${DATASET_DIR}/gist_query.fvecs" \
        0 \
        "$GT_FILE" \
        $L \
        $K \
        "${RESULT_DIR}/"
    echo ""
fi

# 运行精确k-NN搜索（不需要ground truth）
echo "运行精确k-NN搜索 (Exact $K-NNS)..."
echo "参数: L=$L, k=$K"
echo ""
$GTI_BIN \
    "${DATASET_DIR}/gist_base.fvecs" \
    "${DATASET_DIR}/gist_query.fvecs" \
    1 \
    $L \
    $K \
    "${RESULT_DIR}/"
echo ""

# 运行精确范围查询
echo "运行精确范围查询 (Exact Range Query)..."
RADIUS=400
echo "参数: radius=$RADIUS"
echo ""
$GTI_BIN \
    "${DATASET_DIR}/gist_base.fvecs" \
    "${DATASET_DIR}/gist_query.fvecs" \
    2 \
    $RADIUS \
    "${RESULT_DIR}/"
echo ""

echo "========== 实验完成 =========="
echo "结果保存在: ${RESULT_DIR}"
