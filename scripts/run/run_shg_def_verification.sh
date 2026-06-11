#!/bin/bash
#
# SHG 优化方案 D+E+F 对比验证脚本
# 每项独立对比：D(插入后重建)、E(buildShortcuts 采样)、F(levelsSkip 计数)
# 使用 sift 数据集
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

if [ ! -x "./GTI/bin/GTI_shg" ]; then
  echo "错误: GTI_shg 不存在，请先构建 SHG 版本"
  exit 1
fi

echo "========== SHG D+E+F 对比验证 =========="
echo ""

# D 对比：插入后是否 rebuildShortcuts
echo "========== D: rebuildShortcuts 对比 =========="
echo "D0: 无 rebuild (baseline)"
unset GTI_SHG_REBUILD_AFTER_INSERT GTI_SHG_SHORTCUT_SAMPLE_RATIO GTI_SHG_VERBOSE_LEVELSKIP GTI_RESULT_SUFFIX
export GTI_RESULT_SUFFIX=_d_no_rebuild
"$SCRIPT_DIR/run_update.sh" sift shg
echo ""

echo "D1: GTI_SHG_REBUILD_AFTER_INSERT=1"
export GTI_SHG_REBUILD_AFTER_INSERT=1
export GTI_RESULT_SUFFIX=_d_rebuild
"$SCRIPT_DIR/run_update.sh" sift shg
unset GTI_SHG_REBUILD_AFTER_INSERT
echo ""

# E 对比：buildShortcuts 全量 vs 65% 采样
echo "========== E: buildShortcuts 采样对比 =========="
echo "E0: 全量 (GTI_SHG_SHORTCUT_SAMPLE_RATIO=1)"
unset GTI_SHG_SHORTCUT_SAMPLE_RATIO GTI_RESULT_SUFFIX
export GTI_SHG_SHORTCUT_SAMPLE_RATIO=1
export GTI_RESULT_SUFFIX=_e_full
"$SCRIPT_DIR/run_update.sh" sift shg
echo ""

echo "E1: 65% 采样 (GTI_SHG_SHORTCUT_SAMPLE_RATIO=0.65)"
export GTI_SHG_SHORTCUT_SAMPLE_RATIO=0.65
export GTI_RESULT_SUFFIX=_e_sample65
"$SCRIPT_DIR/run_update.sh" sift shg
unset GTI_SHG_SHORTCUT_SAMPLE_RATIO
echo ""

# F 验证：levelsSkip 计数（需 shortcutsSize>=100 才触发）
echo "========== F: levelsSkip 计数验证 =========="
echo "F: GTI_SHG_VERBOSE_LEVELSKIP=1 输出 levelsSkip 统计"
unset GTI_RESULT_SUFFIX
export GTI_SHG_VERBOSE_LEVELSKIP=1
export GTI_RESULT_SUFFIX=_f_verbose
"$SCRIPT_DIR/run_update.sh" sift shg
unset GTI_SHG_VERBOSE_LEVELSKIP
echo ""

echo "========== 完成 =========="
echo "结果目录:"
echo "  D: results/sift/update/shg_d_no_rebuild/  vs  shg_d_rebuild/"
echo "  E: results/sift/update/shg_e_full/        vs  shg_e_sample65/"
echo "  F: results/sift/update/shg_f_verbose/    (含 [F] levelsSkip 计数)"
echo ""
echo "对比方法:"
echo "  D: 比较 recall、insert 后 recall、delete 后 recall 与 插入后 rebuild 耗时"
echo "  E: 比较建库耗时、shortcutsSize、recall、search 延迟"
echo "  F: 检查 run.log 中 [F] levelsSkip: calls= 是否 >0 (shortcutsSize>=100 时生效)"
