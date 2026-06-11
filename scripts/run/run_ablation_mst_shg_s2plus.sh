#!/bin/bash
#
# 消融：MST + SHG S2+（关闭 Wolverine，使用 GTI_shg）
# S2+ = GTI_SHG_LIGHTWEIGHT_QUERY=1 + GTI_SHG_FULL_DIM_LEVEL_SKIP=1
# SHG 图参数按数据集选「文档中的最佳/推荐组合」（见 SHG_PLAN_PROGRESS_ANALYSIS §8–§9）：
#   - Sift: M32 EF120 EF80 — §8.4「追求 Recall」终态 recall 最高（与 mst_opt 高 recall 对比更公平）
#   - Deep: M24 EF80 EF80 — §9.4 三数据集 S2+ 统一协议 + run_s2_plus_deep_gist（deep 无单独调优表）
#   - Gist: M24 EF120 EF80 — 960 维沿用 §8.2 提高 EF_BUILD 换 recall 的思路（避免 M32 建库过重）
# 固定：REBUILD_AFTER_INSERT=1, SHORTCUT_SAMPLE_RATIO=0.65, PRUNE=0
# 可选：SHG_PROFILE=legacy 时三数据集均 M24/80/80，与 run_s2_plus_*.sh、历史 shg_prune0_opt_s2_plus 对齐
#
# 顺序：sift -> deep -> gist
# 输出：results/ablation/{sift,deep,gist}/mst_shg_s2plus/{aknn,update}/
# 可选：ABLATION_DATASETS="deep gist" 仅跑指定数据集（空格分隔），默认全跑
#
# MST 各数据集最佳组合（与 split_compare/mst_param_tuning + 实验结果整理汇总 一致）：
#   - Deep:  exp2  采样 1, thr=32, sample=64, balance=0.05
#   - Sift:  exp2  同上（mst_opt；非 mst_full 200/300）
#   - Gist:  mst_full_4  全量 0, thr=200, sample=200, balance=0.1
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

SHG_BIN="./GTI/bin/GTI_shg"
L=60
K=10

if [ ! -x "$SHG_BIN" ]; then
  echo "错误: $SHG_BIN 不存在，请先编译 SHG 版本"
  exit 1
fi

export GTI_LSH_ENABLED=0
export OMP_NUM_THREADS=1

# S2+ 标志（各数据集共用）；M/EF 在 run_one 内按数据集设置
export GTI_SHG_REBUILD_AFTER_INSERT=1
export GTI_SHG_SHORTCUT_SAMPLE_RATIO=0.65
export GTI_SHG_PRUNE=0
export GTI_SHG_FULL_DIM_LEVEL_SKIP=1
export GTI_SHG_LIGHTWEIGHT_QUERY=1

export GTI_PATCH_DELETE_ONLY=1
# 不使用 Wolverine / GTI 主程序

run_one() {
  local ds_name="$1"
  local base_file="$2"
  local query_file="$3"
  local gt_file="$4"
  local update_ratio="$5"
  local ratio_suffix="$6"
  local mst_use_sampling="$7"
  local mst_full_threshold="$8"
  local mst_sample_size="$9"
  local mst_balance="${10}"
  local gist_delete_opts="${11:-0}"
  local shg_m="${12:-}"
  local shg_efb="${13:-}"
  local shg_efs="${14:-}"
  if [ -z "$shg_m" ] || [ -z "$shg_efb" ] || [ -z "$shg_efs" ]; then
    echo "错误: run_one 缺少 SHG 参数 (M EF_BUILD EF_SEARCH)"
    return 1
  fi

  local RESULTS_ROOT="./results/ablation/${ds_name}"
  local dir="${RESULTS_ROOT}/mst_shg_s2plus"
  local CSV="${RESULTS_ROOT}/ablation_compare.csv"

  if [ ! -f "$base_file" ] || [ ! -f "$query_file" ] || [ ! -f "$gt_file" ]; then
    echo "跳过 ${ds_name}: 数据集文件不完整"
    return 1
  fi

  mkdir -p "$RESULTS_ROOT"
  if [ ! -f "$CSV" ]; then
    echo "variant,aknn_build_s,aknn_search_s,aknn_recall,update_build_s,update_insert_avg_s,update_delete_avg_s,update_final_recall" > "$CSV"
  fi

  export GTI_UPDATE_RATIO="$update_ratio"
  export GTI_SPLIT_STRATEGY=mst
  export GTI_MST_USE_SAMPLING="$mst_use_sampling"
  export GTI_MST_FULL_THRESHOLD="$mst_full_threshold"
  export GTI_MST_SAMPLE_SIZE="$mst_sample_size"
  export GTI_MST_BALANCE_MIN_FRAC="$mst_balance"
  export GTI_MST_SEED=42

  export GTI_SHG_M="$shg_m"
  export GTI_SHG_EF_BUILD="$shg_efb"
  export GTI_SHG_EF_SEARCH="$shg_efs"

  if [ "$gist_delete_opts" = "1" ]; then
    export GTI_UPDATE_DELETE_N=2000
    export GTI_DELETE_CHUNK_SIZE=200
  else
    unset GTI_UPDATE_DELETE_N
    export GTI_DELETE_CHUNK_SIZE=2000
  fi

  rm -rf "$dir"
  mkdir -p "$dir/aknn" "$dir/update"

  echo "=========================================="
  echo "消融: ${ds_name} - MST + SHG S2+ (GTI_shg)"
  echo "MST: sampling=${mst_use_sampling}, thr=${mst_full_threshold}, sample=${mst_sample_size}, bal=${mst_balance}"
  echo "SHG: M=${shg_m} EF_BUILD=${shg_efb} EF_SEARCH=${shg_efs} + S2+"
  echo "ratio=${update_ratio}, 输出: $dir"
  echo "=========================================="

  echo "========== [${ds_name}][mst_shg_s2plus] A-kNN =========="
  "$SHG_BIN" "$base_file" "$query_file" 0 "$gt_file" "$L" "$K" "$dir/aknn/" 2>&1 | tee "$dir/aknn/run.log"

  echo "========== [${ds_name}][mst_shg_s2plus] Update =========="
  "$SHG_BIN" "$base_file" "$query_file" 3 "$gt_file" "$dir/update/" 2>&1 | tee "$dir/update/run.log"

  local aknn_file="$dir/aknn/cost_${K}_${L}.txt"
  local upd_sum="$dir/update/update_summary_k10_l60_ratio${ratio_suffix}.txt"
  local upd_csv="$dir/update/update_curve_k10_l60_ratio${ratio_suffix}.csv"

  local aknn_build aknn_search aknn_recall upd_build upd_insert upd_delete upd_recall
  aknn_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_search="$(awk -F: '/Search time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  aknn_recall="$(awk -F: '/Search recall/ {gsub(/^[ \t]+/,"",$2); print $2}' "$aknn_file" | tail -1)"
  upd_build="$(awk -F: '/Time of index construction/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_insert="$(awk -F: '/Insert avg time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_delete="$(awk -F: '/Delete avg time/ {gsub(/^[ \t]+/,"",$2); print $2}' "$upd_sum" | tail -1)"
  upd_recall="$(tail -1 "$upd_csv" | awk -F, '{print $5}')"

  # 去重：若已有 mst_shg_s2plus 行则删掉再追加
  if [ -f "$CSV" ]; then
    grep -v '^mst_shg_s2plus,' "$CSV" > "${CSV}.tmp" 2>/dev/null || cp "$CSV" "${CSV}.tmp"
    mv "${CSV}.tmp" "$CSV"
  fi
  echo "mst_shg_s2plus,${aknn_build},${aknn_search},${aknn_recall},${upd_build},${upd_insert},${upd_delete},${upd_recall}" >> "$CSV"

  echo "[${ds_name}] 完成: $CSV"
  column -t -s, "$CSV" 2>/dev/null || cat "$CSV"
}

# SHG 三数据集 M / EF_BUILD / EF_SEARCH
# 默认 best：按文档分数据集最优；legacy 与 run_s2_plus_*.sh 一致（全 24/80/80，便于对齐历史 shg_prune0_opt_s2_plus）
SHG_PROFILE="${SHG_PROFILE:-best}"
if [ "$SHG_PROFILE" = "legacy" ]; then
  echo ">>> SHG_PROFILE=legacy：三数据集均 M24 EF80 EF80（与旧 S2+ 落盘一致）"
  SIFT_M=24; SIFT_EFB=80; SIFT_EFS=80
  DEEP_M=24; DEEP_EFB=80; DEEP_EFS=80
  GIST_M=24; GIST_EFB=80; GIST_EFS=80
else
  echo ">>> SHG_PROFILE=best：Sift m32/120/80，Deep m24/80/80，Gist m24/120/80"
  SIFT_M=32; SIFT_EFB=120; SIFT_EFS=80
  DEEP_M=24; DEEP_EFB=80; DEEP_EFS=80
  GIST_M=24; GIST_EFB=120; GIST_EFS=80
fi

# 仅跑部分数据集时设置 ABLATION_DATASETS="deep gist" 等
run_dataset() {
  local name="$1"
  if [ -z "${ABLATION_DATASETS:-}" ]; then return 0; fi
  [[ " ${ABLATION_DATASETS} " == *" ${name} "* ]]
}

# 1) Sift：MST exp2 + SHG（§8.4 Recall 最优 m32_efb120_efs80，或 legacy）
if run_dataset "sift"; then
run_one "sift" \
  "./Datasets/sift/sift/sift_base.fvecs" \
  "./Datasets/sift/sift/sift_query.fvecs" \
  "./Datasets/sift/sift/sift_groundtruth.ivecs" \
  "0.01" "0.010" \
  1 32 64 0.05 \
  "0" \
  "${SIFT_M}" "${SIFT_EFB}" "${SIFT_EFS}"
else echo ">>> 跳过 sift（ABLATION_DATASETS=${ABLATION_DATASETS:-全部}）"; fi

# 2) Deep：MST exp2 + SHG
if run_dataset "deep"; then
run_one "deep" \
  "./Datasets/deep/deep1M/deep1M_base.fvecs" \
  "./Datasets/deep/deep1M/deep1M_query.fvecs" \
  "./Datasets/deep/deep1M/deep1M_groundtruth.ivecs" \
  "0.005" "0.005" \
  1 32 64 0.05 \
  "0" \
  "${DEEP_M}" "${DEEP_EFB}" "${DEEP_EFS}"
else echo ">>> 跳过 deep（ABLATION_DATASETS=${ABLATION_DATASETS:-全部}）"; fi

# 3) Gist：MST mst_full_4 + SHG
if run_dataset "gist"; then
run_one "gist" \
  "./Datasets/gist/gist_base.fvecs" \
  "./Datasets/gist/gist_query.fvecs" \
  "./Datasets/gist/gist_groundtruth.ivecs" \
  "0.005" "0.005" \
  0 200 200 0.1 \
  "1" \
  "${GIST_M}" "${GIST_EFB}" "${GIST_EFS}"
else echo ">>> 跳过 gist（ABLATION_DATASETS=${ABLATION_DATASETS:-全部}）"; fi

echo ""
echo "=========================================="
echo "MST + SHG S2+ 三数据集消融完成"
echo "结果: results/ablation/{sift,deep,gist}/mst_shg_s2plus/"
echo "=========================================="
