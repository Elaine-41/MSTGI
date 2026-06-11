#!/bin/bash
#
# S2+ 在 deep 与 gist 上的验证：S2 + GTI_SHG_FULL_DIM_LEVEL_SKIP=1
# 参数：M=24, EF_BUILD=80, EF_SEARCH=80, PRUNE=0
# 先跑 deep（ratio 0.005, 5k insert + 5k delete），再跑 gist（5k insert + 2000 delete）
# 结果：results/{deep,gist}/update/shg_prune0_opt_s2_plus/
# 对比 baseline：results/{deep,gist}/update/shg_prune0/
#

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"
cd "$ROOT_DIR"

export GTI_SHG_M=24
export GTI_SHG_EF_BUILD=80
export GTI_SHG_EF_SEARCH=80
export GTI_SHG_REBUILD_AFTER_INSERT=1
export GTI_SHG_SHORTCUT_SAMPLE_RATIO=0.65
export GTI_SHG_PRUNE=0
export GTI_SHG_FULL_DIM_LEVEL_SKIP=1
export GTI_SHG_LIGHTWEIGHT_QUERY=1
export GTI_LSH_ENABLED=0
export GTI_SPLIT_STRATEGY=lb
export GTI_PATCH_DELETE_ONLY=1
export OMP_NUM_THREADS=1

[ ! -x "./GTI/bin/GTI_shg" ] && { echo "错误: GTI_shg 不存在"; exit 1; }

run_deep() {
  local BASE="./Datasets/deep/deep1M/deep1M_base.fvecs"
  local QUERY="./Datasets/deep/deep1M/deep1M_query.fvecs"
  local GT="./Datasets/deep/deep1M/deep1M_groundtruth.ivecs"
  [ ! -f "$BASE" ] || [ ! -f "$QUERY" ] || [ ! -f "$GT" ] && { echo "跳过 deep: 数据集缺失"; return 1; }

  export GTI_UPDATE_RATIO=0.005
  unset GTI_UPDATE_DELETE_N
  export GTI_DELETE_CHUNK_SIZE=2000

  local OUT="./results/deep/update/shg_prune0_opt_s2_plus"
  mkdir -p "$OUT"
  echo "########################################"
  echo "# [1/2] deep S2+ Update (5k insert + 5k delete)"
  echo "########################################"
  ./GTI/bin/GTI_shg "$BASE" "$QUERY" 3 "$GT" "$OUT/" 2>&1 | tee "$OUT/run.log"
  echo "[deep] 完成: $OUT/"
}

run_gist() {
  local BASE="./Datasets/gist/gist_base.fvecs"
  local QUERY="./Datasets/gist/gist_query.fvecs"
  local GT="./Datasets/gist/gist_groundtruth.ivecs"
  [ ! -f "$BASE" ] || [ ! -f "$QUERY" ] || [ ! -f "$GT" ] && { echo "跳过 gist: 数据集缺失"; return 1; }

  export GTI_UPDATE_RATIO=0.005
  export GTI_UPDATE_DELETE_N=2000
  export GTI_DELETE_CHUNK_SIZE=200

  local OUT="./results/gist/update/shg_prune0_opt_s2_plus"
  mkdir -p "$OUT"
  echo "########################################"
  echo "# [2/2] gist S2+ Update (5k insert + 2000 delete)"
  echo "########################################"
  ./GTI/bin/GTI_shg "$BASE" "$QUERY" 3 "$GT" "$OUT/" 2>&1 | tee "$OUT/run.log"
  echo "[gist] 完成: $OUT/"
}

echo "########################################"
echo "# S2+ 验证: deep -> gist"
echo "# 对比 baseline: shg_prune0"
echo "########################################"
run_deep || true
run_gist || true
echo "########################################"
echo "# 完成. 对比: results/{deep,gist}/update/shg_prune0/ vs shg_prune0_opt_s2_plus/"
echo "########################################"
