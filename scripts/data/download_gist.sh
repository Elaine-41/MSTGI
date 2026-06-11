#!/bin/bash

# 下载和准备Gist数据集的脚本
# 数据集将存储在 /udata_disk/shiyi/gist

set -e

DATASET_DIR="/udata_disk/shiyi/gist"
BASE_URL="http://corpus-texmex.irisa.fr"
GIST_URL="${BASE_URL}/gist.tar.gz"

echo "========== 开始下载Gist数据集 =========="
echo "目标目录: ${DATASET_DIR}"

# 创建目录
mkdir -p "${DATASET_DIR}"
cd "${DATASET_DIR}"

# 检查文件是否已存在
if [ -f "gist.tar.gz" ]; then
    echo "gist.tar.gz 已存在，跳过下载"
else
    echo "正在从 ${GIST_URL} 下载..."
    wget "${GIST_URL}" -O gist.tar.gz
    echo "下载完成"
fi

# 解压文件
if [ -f "gist_base.fvecs" ] && [ -f "gist_query.fvecs" ]; then
    echo "数据集文件已存在，跳过解压"
else
    echo "正在解压..."
    tar -xzf gist.tar.gz
    echo "解压完成"
fi

# 检查文件
echo ""
echo "========== 检查文件 =========="
if [ -f "gist_base.fvecs" ]; then
    echo "✓ gist_base.fvecs 存在"
    ls -lh gist_base.fvecs
else
    echo "✗ gist_base.fvecs 不存在"
fi

if [ -f "gist_query.fvecs" ]; then
    echo "✓ gist_query.fvecs 存在"
    ls -lh gist_query.fvecs
else
    echo "✗ gist_query.fvecs 不存在"
fi

# 检查ground truth文件（可能有不同的命名）
GT_FILE=""
if [ -f "gist_groundtruth.ivecs" ]; then
    GT_FILE="gist_groundtruth.ivecs"
elif [ -f "gist.ivecs" ]; then
    GT_FILE="gist.ivecs"
elif [ -f "groundtruth.ivecs" ]; then
    GT_FILE="groundtruth.ivecs"
fi

if [ -n "$GT_FILE" ]; then
    echo "✓ $GT_FILE 存在"
    ls -lh "$GT_FILE"
else
    echo "✗ Ground truth文件不存在（可能需要单独下载或生成）"
    echo "  可以尝试从 http://corpus-texmex.irisa.fr/ 下载ground truth文件"
fi

echo ""
echo "========== Gist数据集准备完成 =========="
echo "数据集路径: ${DATASET_DIR}"
echo ""
echo "使用示例："
echo "cd GTI"
echo "bin/GTI ${DATASET_DIR}/gist_base.fvecs ${DATASET_DIR}/gist_query.fvecs 0 ${DATASET_DIR}/gist_groundtruth.ivecs 60 10 results/"
