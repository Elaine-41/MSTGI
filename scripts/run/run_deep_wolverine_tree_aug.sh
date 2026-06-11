#!/bin/bash
#
# Deep 数据集：wolverine + 方向1（树辅助候选池）
# 使用 max_affected=200、radius=3.0 使 deep 上实验能在合理时间内完成
# （deep 256D，树搜索比 sift 慢，需降低参数）
#
# 用法: "$SCRIPT_DIR/run_deep_wolverine_tree_aug.sh"
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"

export GTI_TREE_AUGMENTED_PATCH=1
export GTI_TREE_PATCH_MAX_AFFECTED=200
export GTI_TREE_PATCH_RADIUS=3.0
export GTI_RESULT_SUFFIX=_tree_aug
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"
export GTI_UPDATE_RATIO="${GTI_UPDATE_RATIO:-0.005}"

echo "========== Deep wolverine+方向1 (max_affected=200, radius=3.0) =========="
"$SCRIPT_DIR/run_update.sh" deep wolverine
