# SHG 优化实施记录

本文档记录各优化项的修改细节与验证步骤，便于实施时跟踪。

---

## S1. resultsProcessing 世代化（已实施，有效）

**目标**：消除每查询 `std::fill` 约 6M floats 的开销。

**修改**：

1. **heds.h**：增加 `resultsProcessing_epoch_`、`search_epoch_`；`pruneDisCompute` 中按 epoch 判断有效性
2. **heds.h** `searchKnnShortcuts`：每次调用 `search_epoch_++`，写入 `resultsProcessing` 时同步写 `resultsProcessing_epoch_`
3. **gti.cpp**：`resultsProcessing` resize 时同步 resize `resultsProcessing_epoch_`，移除 `std::fill`

**验证结果**（sift 1M, K=10, L=60）：
- 修改前：aknn_search_s ≈ 0.00429
- 修改后：aknn_search_s ≈ 0.00324（**约 25% 降低**）
- recall 保持 0.836

---

## U1. deleteTree findLeaf 优先（已回滚）

**目标**：对「删除刚插入数据」场景，用 findLeaf 代替 search。

**实施结果**：在 sift update 实验中，findLeaf 优先导致删除总耗时从 70s 升至 111s。推断 findLeaf 在 GTI 更新流程中未能匹配到待删点（或匹配路径开销大），每次均 fallback 到 search，且 findLeaf 遍历本身增加额外开销。**已回滚**，恢复 search 优先逻辑。后续可考虑：在插入阶段记录 (vector, leaf) 映射供删除复用，或调试 findLeaf 在 GTI 结构下的匹配条件。

---

## 注意：gti.cpp 的 S1 修改

若使用 `git checkout` 回退了 gti.cpp，需手动恢复 SHG 版本并补上 S1 修改。S1 在 gti.cpp 的修改为：

在 `#elif defined(GTI_USE_SHG)` 的 search 与 searchExactKnn 中：
- 将 `std::fill(...)` 移除
- 在 `resultsProcessing.resize(rp_size)` 后增加：`index_heds->resultsProcessing_epoch_.resize(rp_size);`

---

## S2. 轻量级 query 表示（已实施）

**目标**：避免每查询 `addDataPoint` + `markDelete` 的完整流程，降低约 10–20% 搜索延迟。

**修改**（已实施）：
1. **heds.h**：新增 `overwriteQuerySlotData(const void* data_point, tableint internalId)`，仅覆盖 raw data 与 data_rep，不做图邻接更新
2. **gti.cpp**：当 `GTI_SHG_LIGHTWEIGHT_QUERY` 环境变量设置时，首查询用 `addDataPoint` 激活槽并缓存 `heds_query_internal_id`，后续查询用 `overwriteQuerySlotData` 替代 `addDataPoint`+`markDelete`
3. **gti.h**：新增 `heds_query_internal_id` 成员，在 (re)build 时重置为 0

**用法**：`GTI_SHG_LIGHTWEIGHT_QUERY=1 ./bin/GTI_shg ...` 或 `export GTI_SHG_LIGHTWEIGHT_QUERY=1`

**验证**：同 S1，对比启用/未启用时的搜索延迟与 recall。

---

## S4. 轻量剪枝开关（已实施，验证中）

**目标**：通过 `GTI_SHG_PRUNE=0` 回退到 `searchBaseLayerST`，评估 recall/延迟 trade-off。

**修改**：
- heds.h 616–626：增加环境变量检查，若 `GTI_SHG_PRUNE=0` 则调用 `searchBaseLayerST` 而非 `searchBaseLayerSTPrune`

**验证**：
- 运行 `./run_shg_plan_validation.sh` 完成 sift/deep 的 baseline 与 prune0 对比
- 运行 `./analyze_shg_plan_results.sh` 查看分析结果
- **回滚原则**：若 prune0 的 recall 下降超过 0.02 且 search 未明显提速，则保持 PRUNE 默认开启，不推荐使用 GTI_SHG_PRUNE=0

---

## A. 参数调优

**修改**：
- gti.cpp buildGraphSec：读取 `GTI_SHG_EF_BUILD`，默认 160
- gti.cpp search 调用处：支持 `GTI_SHG_SEARCH_L` 覆盖 L 参数

**验证**：
- `GTI_SHG_EF_BUILD=200 GTI_SHG_SEARCH_L=120 ./run_update.sh sift shg`
- 对比 recall、搜索延迟、建库耗时、删除总耗时
