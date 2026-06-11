#!/bin/bash
# 快速测试LSH debug输出（只运行少量查询）

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

export GTI_LSH_ENABLED=1
export GTI_SPLIT_STRATEGY=lb
export OMP_NUM_THREADS=1

LOG_FILE="${ROOT_DIR}/scripts/logs/lsh_debug_test.log"
mkdir -p "$(dirname "$LOG_FILE")"

# 只运行一次查询来查看debug输出
echo "开始测试LSH debug输出..."
echo "注意：构建索引需要时间，请耐心等待"
echo ""

# 运行GTI，将stderr和stdout都重定向到日志
./GTI/bin/GTI ./Datasets/deep/deep1M/deep1M_base.fvecs ./Datasets/deep/deep1M/deep1M_query.fvecs 0 ./Datasets/deep/deep1M/deep1M_groundtruth.ivecs 60 10 ./results/lsh_test/ > "$LOG_FILE" 2>&1

echo ""
echo "测试完成！查看debug输出："
echo "=========================================="
grep -E "LSH|GTI:" "$LOG_FILE" | head -30
echo ""
echo "完整日志保存在: $LOG_FILE"
