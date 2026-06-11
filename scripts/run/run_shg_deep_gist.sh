#!/bin/bash
#
# 对 deep 和 gist 运行 SHG 策略，并更新与 lazy/wolverine 的对比
# 用法: "$SCRIPT_DIR/run_shg_deep_gist.sh" [deep|gist|all]
#   deep  - 仅运行 deep
#   gist  - 仅运行 gist  
#   all   - 两者都运行（默认）
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT"
cd "$ROOT"

if [ ! -x "./GTI/bin/GTI_shg" ]; then
  echo "错误: GTI_shg 不存在，请先构建 SHG 版本"
  echo "  cd GTI && mkdir -p build_shg && cd build_shg"
  echo "  cmake -DGTI_USE_SHG=ON -DGTI_USE_WOLVERINE=OFF .. && make"
  exit 1
fi

MODE="${1:-all}"

run_one() {
  local ds=$1
  echo ""
  echo "========== SHG: $ds =========="
  "$SCRIPT_DIR/run_update.sh" "$ds" shg
}

case "$MODE" in
  deep) run_one deep ;;
  gist) run_one gist ;;
  all)
    run_one deep
    run_one gist
    ;;
  *) echo "用法: $0 [deep|gist|all]"; exit 1 ;;
esac

echo ""
echo "========== 更新对比汇总 =========="
for ds in deep gist; do
  if [[ "$MODE" = "all" || "$MODE" = "$ds" ]]; then
    echo ""
    "$SCRIPT_DIR/run_compare_all_delete_strategies.sh" "$ds"
  fi
done
