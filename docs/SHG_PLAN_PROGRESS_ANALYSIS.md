# SHG 优化计划进度分析

基于 `shg_optimization_plan_update_37f63532.plan.md` 与 `shg_strategy_final_optimization_7b0e62d8.plan.md`，对已实施项、已跑实验与待完成项做汇总分析。sift、deep 数据集已跑完最新验证实验。

---

## 〇、原方案目标（shg_strategy_final_optimization）

**本阶段范围**：sift（128d）、deep（256d），目标为在 recall、搜索延迟或更新时间中**至少一项优于 Wolverine**。

| 阶段 | 内容 | 预期效果 |
|------|------|----------|
| Phase 1 | GTI_SHG_M、GTI_SHG_EF_SEARCH、setEf | 参数可调，recall 提升 |
| Phase 2 | buildShortcuts 全维、PRUNE 调参 | sift 搜索 ≤ Wolverine 1.5×（约 0.9ms） |
| Phase 3 | REBUILD_AFTER_INSERT、SAMPLE_RATIO | 已有实现，删除路径确认 |

**成功标准**：sift recall ≥0.84，搜索在调参后接近 Wolverine。

---

## 一、此次改动有效性分析

### 1.1 S4 (GTI_SHG_PRUNE=0) 验证结果

配置：REBUILD_AFTER_INSERT=1、SAMPLE_RATIO=0.65、M=24、EF_BUILD=80、EF_SEARCH=50。

| 数据集 | 配置 | Delete 总耗时 | Delete avg (s/item) | 终态 recall | Insert 后 recall |
|--------|------|---------------|---------------------|-------------|------------------|
| **sift** | baseline | 104.72s | 0.01047 | **0.717** | 0.712 |
| **sift** | prune0 | **79.45s** | **0.00795** | **0.784** | 0.854 |
| **deep** | baseline | ~49.6s | 0.00993 | **0.852** | 0.847 |
| **deep** | prune0 | **45.1s** | **0.00903** | **0.856** | 0.86 |

**结论**：GTI_SHG_PRUNE=0 在 update 场景下**有效**——delete 更快、终态 recall 更高或持平，**不回滚**，可在 update 流程中采用。

### 1.2 S1 + 参数体系效果

| 指标 | 改动前 (shg 旧) | 改动后 (baseline) | 改动后 (prune0) |
|------|-----------------|-------------------|-----------------|
| A-kNN search | 4.29ms | 2.07ms | 2.26ms |
| A-kNN recall | 0.836 | **0.861** | 0.861 |
| sift 终态 recall | — | 0.717 | **0.784** |

S1 使纯搜索延迟约降 **50%**（4.29→2.07ms），M/EF 参数使 recall 从 0.836 提升到 0.861。

---

## 二、与 GTI（n2）和 Wolverine 的比较

### 2.1 sift（1M，ratio=0.01，update_n=10000）

| 指标 | GTI_n2 (direct) | GTI_n2 (lazy) | Wolverine | SHG baseline | SHG prune0 |
|------|-----------------|---------------|-----------|--------------|------------|
| 建库 | 35s | 33s | **253s** | 359s | 367s |
| Insert 总 | 10s | 8.5s | 5.4s | 7.5s | 7.4s |
| Delete 总 | **1279s** | **1204s** | **24s** | 105s | **79s** |
| 终态 recall | **0.904** | **0.877** | **0.797** | 0.717 | 0.784 |
| 搜索/query | 1.2ms | — | **0.65ms** | 2.0ms | 2.0ms |
| graph_update/批 | — | — | ~0.19s | **~0.0017s** | **~0.0017s** |

### 2.2 deep（1M，ratio=0.005，update_n=5000）

| 指标 | GTI_n2 (lazy) | Wolverine | SHG baseline | SHG prune0 |
|------|---------------|-----------|--------------|------------|
| 建库 | 66s | **459s** | 887s | 926s |
| Delete 总 | **1854s** | **5.6s** | 49.6s | **45.1s** |
| 终态 recall | **0.936** | **0.907** | 0.852 | 0.856 |
| 搜索/query | — | **~1.0ms** | ~5.7ms | ~5.2ms |
| graph_update/批 | — | ~0.2s | **~0.002s** | **~0.002s** |

### 2.3 差距与优势总结

| 维度 | SHG 差距 | SHG 优势 |
|------|----------|----------|
| **recall** | 低于 Wolverine（sift 0.78 vs 0.80，deep 0.86 vs 0.91） | 低于 GTI_n2（n2 recall 最高但 delete 极慢） |
| **搜索延迟** | 约为 Wolverine 2–5×（2ms vs 0.65ms @sift） | 原方案目标 ≤1.5× 未达成 |
| **Delete 总耗时** | 慢于 Wolverine（79s vs 24s @sift） | 远快于 GTI_n2（79s vs 1279s） |
| **graph_update** | — | **约 100× 快于 Wolverine**（markDelete vs patchDelete） |
| **建库** | 慢于 Wolverine | — |

---

## 三、Plan 优化项清单

### 3.1 搜索优化（S1–S4）

| 项 | 方案 | 优先级 | 实施状态 | 验证状态 |
|----|------|--------|----------|----------|
| **S1** | resultsProcessing 世代化（消除每查询 std::fill） | P0 | ✅ 已实施 | ✅ 已跑，搜索降约 25% |
| **S2** | 轻量级 query 表示（避免 addDataPoint+markDelete） | P1 | ❌ 未实施 | — |
| **S3** | resultsProcessing 稀疏化 | P2 | ❌ 未实施 | — |
| **S4** | GTI_SHG_PRUNE=0 轻量剪枝开关 | P1 | ✅ 已实施 | ✅ 已跑，update 场景有效 |

### 3.2 更新/删除优化（U1–U3）

| 项 | 方案 | 优先级 | 实施状态 | 验证状态 |
|----|------|--------|----------|----------|
| **U1** | deleteTree findLeaf 优先 | P0 | ⚠️ 已实施但已回滚 | ✅ 已跑，删除 70s→111s 变慢 |
| **U2** | 批量 1-NN | P2 | ❌ 未实施 | — |
| **U3** | 明确 SHG 优势指标（文档） | — | 部分完成 | — |

---

## 四、已跑实验汇总

### 4.1 已跑实验

| 实验类型 | 数据集 | 配置/策略 | 结果目录 | 备注 |
|----------|--------|-----------|----------|------|
| **Update** | sift | shg (M=24, ef_build=80, ef_search=50) | `sift/update/shg/` | 最新参数化 run |
| **Update** | sift | shg_u1_opt（U1 findLeaf 优先） | `sift/update/shg_u1_opt/` | U1 验证，已回滚 |
| **Update** | sift | wolverine | `sift/update/wolverine/` | 对比基线 |
| **Update** | sift | shg_ef200_l120 | `sift/update/shg_ef200_l120/` | ef/L 调优 |
| **Update** | sift | shg_d_rebuild, shg_e_full, shg_e_sample65 | 各策略目录 | 策略对比 |
| **Update** | deep | shg (M=24) | `deep/update/shg/` | 低维 deep |
| **Update** | gist | shg | `gist/update/shg/` | 高维 gist |
| **A-kNN** | sift | n2 / wolverine / shg | `sift/aknn_compare/` | 纯搜索对比 |
| **A-kNN** | sift | shg_opt（S1 优化后） | `sift/aknn_compare/shg_opt/` | S1 验证 |

### 4.2 未跑实验

| 实验 | 说明 |
|------|------|
| **S4 验证** | 已跑，aknn + update 均有结果 |
| **S2/S3 验证** | 未实施，无实验 |
| **Phase 3 多数据集验证** | deep/gist 有部分 run，无系统对比表 |

---

## 五、改动后的结果分析

### 5.1 最新 SHG 配置（M=24, ef_build=80, ef_search=50）

| 指标 | sift update shg | sift update wolverine |
|------|-----------------|------------------------|
| 建库时间 | ~320s | ~253s |
| 搜索延迟 | ~1.8ms/query | ~0.7ms/query |
| 搜索 recall | ~0.71 | ~0.85 |
| Insert 单点 | ~0.7ms | ~0.68ms |
| **graph_update**（每批 2000） | **~0.0017s** | ~0.19s |
| Delete 总耗时 | ~91s | ~24s |
| Delete recall（终态） | 0.718 | 0.797 |

**结论**：

- **graph_update**：SHG markDelete ≈ 0.0017s/批，Wolverine patchDelete ≈ 0.19s/批，SHG 快约 **100×**。
- **Delete 总耗时**：由 deleteTree 的 1-NN 搜索主导（每点约 9ms），SHG 整体 91s，仍慢于 Wolverine 24s。
- **搜索**：SHG ~1.8ms，Wolverine ~0.7ms，SHG 慢约 **2.5×**；S1 优化后已从 ~4.3ms 降到 ~3.2ms（aknn），但 update 中仍约 1.8ms，与参数、场景有关。

### 5.2 S1 优化效果（A-kNN 纯搜索）

| 配置 | aknn_search_s | aknn_recall |
|------|---------------|-------------|
| 修改前（无 S1） | ~0.00429 | 0.836 |
| 修改后（S1） | ~0.00324 | 0.836 |

S1 使搜索延迟降低约 **25%**，recall 基本不变。

### 5.3 U1 效果（已回滚）

| 配置 | delete 总耗时 | 说明 |
|------|---------------|------|
| search 优先（当前） | ~70–91s | 基线 |
| findLeaf 优先（U1） | ~111s | 变慢，已回滚 |

findLeaf 在 GTI 的 update 流程中难以命中待删点，多数场景仍走 search，并增加 findLeaf 遍历开销。

---

## 六、Plan 完成度与未实现阶段

### 6.1 完成度总览

```text
Phase 1 (P0)
├── S1 resultsProcessing 世代化     ✅ 已实施 ✅ 已验证
└── U1 deleteTree findLeaf 优先      ⚠️ 已实施 ❌ 无效（已回滚）

Phase 2 (P1)
├── S2 轻量级 query 表示            ❌ 未实施
└── S4 轻量剪枝 GTI_SHG_PRUNE=0     ✅ 已实施 ✅ 已跑（update 有效）

Phase 3 (P2)
├── S3 resultsProcessing 稀疏化    ❌ 未实施
├── A/C 参数调优                   🔶 部分（ef200_l120 已跑）
└── 多数据集验证                    🔶 部分（sift/deep/gist 有 run）
```

### 6.2 未实现阶段（暂不实施）

**来自 shg_strategy_final_optimization：**

| 阶段 | 内容 | 状态 |
|------|------|------|
| Phase 2.1 | buildShortcuts 全维距离 | ❌ 未实施。需确认 `getNearestbyLevel`、`getavgDisatLevel` 在 `use_full_dim_level_skip_` 时是否走全维 |
| Phase 2.2 | 搜索瓶颈排查（metric_distance_computations、metric_hops） | ❌ 未实施 |
| Phase 2.2 | 成功标准：sift 搜索 ≤ Wolverine 1.5×（0.9ms） | ❌ 未达成（当前 ~2ms） |
| 暂不实施 | searchKnnHNSW 回退、GTI_SHG_HNSW_FALLBACK_DIM | 高维 gist 后续单独推进 |

**来自 shg_optimization_plan_update：**

| 阶段 | 内容 | 状态 |
|------|------|------|
| S2 | 轻量级 query 表示 | ❌ 未实施 |
| S3 | resultsProcessing 稀疏化 | ❌ 未实施 |
| U2 | 批量 1-NN | ❌ 未实施 |

---

## 七、计划调整建议（2025-02）

### 7.1 目标与优先级调整

**现状**：SHG prune0 相对自身有提升，但与 Wolverine 相比无单项突出优势（recall、搜索、delete 均略逊）。

| 调整项 | 原计划 | 调整后 |
|--------|--------|--------|
| **执行顺序** | 直接实施 S2/S3/U2 | **先参数调优** → 再 S/U 实施 |
| **参数调优范围** | 仅 M=24、EF=80/50 | M=24/32，EF_BUILD=80/120/160，EF_SEARCH=50/80 多组合验证 |
| **固定配置** | — | REBUILD_AFTER_INSERT=1、SAMPLE_RATIO=0.65 **必须** |
| **基线复用** | — | shg_prune0 等现有数据可复用，不重复跑 |

### 7.2 执行路线图

```text
1. 参数调优（M、EF_BUILD、EF_SEARCH）
   - 固定：REBUILD=1, SAMPLE_RATIO=0.65, PRUNE=0
   - 多组合：M∈{24,32}, EF_BUILD∈{80,120,160}, EF_SEARCH∈{50,80}
   - 数据集：sift（必跑）、deep（可选）

2. S/U 阶段实施（参数调优完成后）
   - S2 轻量级 query 表示
   - S3 resultsProcessing 稀疏化
   - U2 批量 1-NN
   - 跳过已做实验，复用 baseline；效果不如则回滚
```

---

## 八、参数调优结果（sift，2025-02）

固定配置：REBUILD_AFTER_INSERT=1、SAMPLE_RATIO=0.65、GTI_SHG_PRUNE=0。  
数据来源：`results/sift/update/shg_*/update_summary_k10_l60_ratio0.010.txt`、`update_curve_k10_l60_ratio0.010.csv`。  
调优脚本：`run_shg_param_tuning.sh`（基线 M24/80/50 复用 `shg_prune0`）。

### 8.1 各组合完整数据

| 组合 | M | EF_BUILD | EF_SEARCH | 建库(s) | Insert avg | Delete 总(s) | Delete avg | 终态 recall | Insert 后 recall | 搜索(ms) |
|------|---|----------|-----------|---------|------------|--------------|------------|-------------|------------------|----------|
| prune0（基线） | 24 | 80 | 50 | 367 | 0.00074 | 79.45 | 0.00795 | **0.784** | 0.854 | 2.10 |
| m24_efb80_efs80 | 24 | 80 | 80 | **289** | 0.00062 | **64.13** | **0.00641** | **0.784** | 0.854 | **1.67** |
| m24_efb120_efs50 | 24 | 120 | 50 | 432 | 0.00083 | 73.13 | 0.00731 | **0.789** | **0.866** | 2.56 |
| m24_efb120_efs80 | 24 | 120 | 80 | 430 | 0.00084 | 73.81 | 0.00738 | **0.789** | **0.866** | 2.60 |
| m32_efb80_efs50 | 32 | 80 | 50 | 298 | 0.00064 | **63.26** | **0.00633** | 0.780 | 0.854 | **1.67** |
| m32_efb120_efs80 | 32 | 120 | 80 | 452 | 0.00077 | 72.44 | 0.00724 | **0.792** | **0.867** | 2.70 |
| **Wolverine** | — | — | — | **253** | 0.00068 | **24** | **0.00239** | **0.797** | 0.846 | **0.65** |

### 8.2 各组合逐一分析

| 组合 | 优势 | 劣势 | 适用场景 |
|------|------|------|----------|
| **prune0（基线）** | 终态 recall 0.784，与 m24_efb80 系列持平 | 建库最慢 367s，Delete 79s 较慢 | 作为对比基线 |
| **m24_efb80_efs80** | 建库 **289s 最短**，Delete 64s、搜索 1.67ms 均快 | recall 与基线持平 0.784 | **综合推荐**：建库+Delete+搜索均衡 |
| **m24_efb120_efs50** | 终态 recall 0.789、Insert 后 0.866，优于基线 | 建库 432s 慢，Delete 73s，搜索 2.56ms | 需要较高 recall 且可接受长建库 |
| **m24_efb120_efs80** | 终态 recall 0.789、Insert 后 0.866 | 建库 430s、Delete 73.8s、搜索 2.6ms 均偏慢 | 与 efs50 类似，EF_SEARCH 加大无明显收益 |
| **m32_efb80_efs50** | **Delete 63.26s 最快**，建库 298s 较快，搜索 1.67ms | 终态 recall 0.780 略低于基线 | **Delete 优先**：update 密集场景 |
| **m32_efb120_efs80** | **终态 recall 0.792 最高**，Insert 后 0.867 | 建库 452s 最慢，Delete 72s，搜索 2.7ms | **Recall 优先**：质量敏感场景 |

### 8.3 分析结论

**1. Delete 耗时最优：M=32 EF_BUILD=80 EF_SEARCH=50**

- Delete 总 63.26s、单点 0.00633s，比基线 prune0（79.45s）快约 **20%**。
- 终态 recall 0.780，略低于基线 0.784（-0.004）。
- 建库 298s，比基线 367s 快约 19%。

**2. 综合性价比：M=24 EF_BUILD=80 EF_SEARCH=80**

- Delete 64.13s，与 M=32 组合接近。
- 终态 recall 与基线持平 0.784。
- 建库 **289s** 为所有组合中最短。
- 搜索 **1.67ms**，比基线 2.1ms 快约 20%。

**3. Recall 最优：M=32 EF_BUILD=120 EF_SEARCH=80**

- 终态 recall **0.792**，为 SHG 中最高。
- 代价：建库 452s、Delete 72.44s、搜索 2.7ms，均偏慢。

**4. EF_BUILD=120 的影响**

- 建库时间明显增加（约 +140s）。
- recall 提升约 0.005–0.008。
- Delete 与搜索略慢，整体 trade-off 偏负。

**5. EF_SEARCH 的影响（50 vs 80）**

- 同 M、同 EF_BUILD 下：EF_SEARCH=80 时搜索更快（1.67ms vs 2.1ms @ M24/80），Delete 也更快（64s vs 79s）。
- EF_SEARCH=80 对 recall 几乎无影响（0.784 vs 0.784 @ M24/80）。
- **结论**：EF_SEARCH 提升到 80 在 M24/80 上有明显收益，在 EF_BUILD=120 时收益不明显。

**6. M 参数影响（24 vs 32）**

- 同 EF_BUILD=80 下：M=32 建库更快（298s vs 367s）、Delete 更快（63s vs 79s），但终态 recall 略低（0.780 vs 0.784）。
- 同 EF_BUILD=120 下：M=32 recall 更高（0.792 vs 0.789），建库与 Delete 更慢。
- **结论**：M=32 在图更密时加速 delete/build，EF_BUILD 高时 recall 受益；EF_BUILD=80 时 M=32 以少量 recall 换显著速度。

**7. 与 Wolverine 对比**

- Wolverine：Delete 24s、recall 0.797、搜索 0.65ms、Insert 后 recall 0.846。
- 最优 SHG：Delete 仍约 2.6× 慢，终态 recall 低 0.01–0.02，搜索约 2.5× 慢；Insert 后 recall（0.854–0.867）略优于 Wolverine。
- graph_update 优势（约 100×）未改变整体耗时，因 deleteTree 的 1-NN 搜索占主导。

### 8.4 推荐配置

| 场景 | 推荐配置 | 说明 |
|------|----------|------|
| **追求 Delete 最快** | M=32, EF_BUILD=80, EF_SEARCH=50 | Delete 63s，recall 略降 |
| **综合平衡** | M=24, EF_BUILD=80, EF_SEARCH=80 | 建库最短、Delete/recall 均衡 |
| **追求 Recall** | M=32, EF_BUILD=120, EF_SEARCH=80 | recall 0.792，建库与 Delete 较慢 |

---

## 九、SHG+ 与 SHG+S2+ 介绍及综合对比（sift 详表 + 三数据集 §9.4，2025-02）

### 9.1 方案定义

| 方案 | 定义 | 关键配置 |
|------|------|----------|
| **SHG baseline** | SHG prune0 优化版，无 S2 | M=24, EF=80/80, PRUNE=0，无 GTI_SHG_LIGHTWEIGHT_QUERY |
| **SHG+（S2）** | SHG + 轻量级 query 槽复用 | `GTI_SHG_LIGHTWEIGHT_QUERY=1`，每查询用 `overwriteQuerySlotData` 替代 addDataPoint+markDelete |
| **SHG+S2+** | SHG+ + 全维跳层快速路径 | `GTI_SHG_LIGHTWEIGHT_QUERY=1` + `GTI_SHG_FULL_DIM_LEVEL_SKIP=1`，`overwriteQuerySlotData` 仅 memcpy 跳过 data_rep |

### 9.2 综合对比（sift 1M，ratio 0.01，10k insert + 10k delete）

| 指标 | SHG baseline | SHG+ (S2) | SHG+S2+ | Wolverine_d2 |
|------|--------------|-----------|---------|--------------|
| **建库(s)** | **289** | 1027–1101 | 576 | 255 |
| **Insert avg (s/item)** | **0.00062** | 0.00156–0.00198 | 0.00128 | **0.00053** |
| **Delete 总(s)** | **64** | 158–190 | 193 | **28** |
| **Insert 阶段搜索(ms)** | 1.56–1.72 | 0.66–0.80 | **0.44–0.90** | 0.58–0.59 |
| **Delete 阶段搜索(ms)** | 1.61–1.67 | 0.72–0.87 | **0.39–1.07** | 0.61–0.64 |
| **终态 recall** | **0.784** | 0.773 | 0.774 | **0.797** |
| **Insert 后 recall** | 0.854 | 0.849 | 0.851 | 0.846 |

### 9.3 优劣与适用场景

| 方案 | 优势 | 劣势 | 适用场景 |
|------|------|------|----------|
| **SHG baseline** | Delete 64s、recall 0.784 较高 | 搜索 1.6+ ms | 优先 recall、Delete 时间 |
| **SHG+ (S2)** | 搜索 ~0.8 ms，约 2× 加速 | 建库/Insert/Delete 存在异常变慢 | 搜索延迟敏感，建库需同机对照 |
| **SHG+S2+** | 搜索 0.39–0.90 ms 最优，接近 Wolverine | Delete 193s 慢、recall 0.774 略降 | 追求最低搜索延迟 |
| **Wolverine_d2** | Delete 28s、recall 0.797、搜索 0.61 ms 综合最优 | — | 默认首选 |

**数据来源**：sift baseline `shg_m24_efb80_efs80`，S2 `shg_prune0_opt_s2`，S2+ `shg_prune0_opt_s2_plus`，详见 [S2_SIFT_COMPARISON.md](S2_SIFT_COMPARISON.md)。

### 9.4 三数据集：shg_prune0 vs SHG+S2+（统一对比，2025-02）

**对比对象**

| 名称 | 含义 |
|------|------|
| **shg_prune0** | `GTI_SHG_PRUNE=0`，无 `GTI_SHG_LIGHTWEIGHT_QUERY` / 无全维跳层 |
| **SHG+S2+** | `GTI_SHG_LIGHTWEIGHT_QUERY=1` + `GTI_SHG_FULL_DIM_LEVEL_SKIP=1` |

**实验协议（各数据集一致策略：M=24，EF_BUILD=80，EF_SEARCH=80，REBUILD_AFTER_INSERT=1，SAMPLE_RATIO=0.65，chunked update）**

| 数据集 | 向量维 | ratio | Insert / Delete | 结果目录 |
|--------|--------|-------|-----------------|----------|
| **sift** | 128 | 0.01 | 10000 / 10000 | `sift/update/shg_prune0/` vs `shg_prune0_opt_s2_plus/` |
| **deep** | 256 | 0.005 | 5000 / 5000 | `deep/update/shg_prune0/` vs `shg_prune0_opt_s2_plus/` |
| **gist** | 960 | 0.005 | 5000 / **2000** | `gist/update/shg_prune0/` vs `shg_prune0_opt_s2_plus/` |

*gist 的 delete 仅 2000 条（chunk=200），与 deep 的 5000 条 delete 不可直接比较 delete 总时长的绝对数值；可比较单位 delete 时间、建库、Insert、搜索与 recall。*

**指标表**（建库 / Insert / Delete 来自 `update_summary_*.txt`；终态 recall 与搜索为 `update_curve_*.csv` **最后一行**）

| 数据集 | 方案 | 建库 (s) | Insert avg (s/条) | Delete avg (s/条) | Delete 总 (s) | 终态 recall | 终态搜索 (ms/q) |
|--------|------|----------|-------------------|-------------------|---------------|-------------|-----------------|
| sift | shg_prune0 | 367.1 | 0.000742 | 0.007945 | **79.45** | **0.784** | **2.10** |
| sift | SHG+S2+ | 576.0 | 0.001281 | 0.019283 | 192.83 | 0.774 | **0.77** |
| deep | shg_prune0 | 926.3 | 0.001619 | 0.009029 | **45.15** | **0.856** | **5.20** |
| deep | SHG+S2+ | **423.6** | **0.000927** | **0.003681** | **18.41** | 0.849 | **0.36** |
| gist | shg_prune0 | 2767.9 | 0.004669 | 0.091179 | 182.36 | **0.712** | **6.91** |
| gist | SHG+S2+ | **947.6** | **0.001891** | 0.094246 | 188.49 | 0.698 | **2.07** |

**跨数据集结论**

| 数据集 | SHG+S2+ 相对 shg_prune0 | 简要结论 |
|--------|-------------------------|----------|
| **sift** | 建库 +57%，Delete 总 +143%，recall −0.010，搜索约 **2.7× 更快** | 搜索收益明显；更新路径（Insert/Delete）整体变慢，与 sift 上历史现象一致 |
| **deep** | 建库 **−54%**，Insert / Delete 明显更快，recall −0.007，搜索约 **14× 更快** | **全面占优**（除终态 recall 略降） |
| **gist** | 建库 **−66%**，Insert 约 **2.5 faster**，Delete 总基本持平（+3%），recall −0.014，搜索约 **3.3× 更快** | 高维下 S2+ 对建库与单条 Insert、搜索帮助大；Delete 单条仍重，总 delete 与 prune0 接近 |

**数据来源**：

- sift：`update_summary_k10_l60_ratio0.010.txt`、`update_curve_k10_l60_ratio0.010.csv`
- deep / gist：`update_summary_k10_l60_ratio0.005.txt`、`update_curve_k10_l60_ratio0.005.csv`
- gist shg_prune0 跑完记录见 `results/gist/update/shg_prune0/run.log`

---

## 十、建议的后续动作

1. **推荐配置**：优先使用 `M=24, EF_BUILD=80, EF_SEARCH=80` 或 `M=32, EF_BUILD=80, EF_SEARCH=50`，在 delete 与建库上优于原基线。
2. **更新场景推荐**：采用 `GTI_SHG_PRUNE=0` + 上述参数，sift 上 delete 更快、recall 不降。
3. **S2 / S2+**：sift / deep / gist 三数据集上 **shg_prune0 vs SHG+S2+** 已汇总于 **§9.4**；若需极致 recall，可仍以 prune0 或调高 EF 为主。
4. **Phase 2.1 验证**：确认 buildShortcuts 全维路径完整性，评估 recall 提升空间。
5. **U1 替代方案**：探索「插入阶段记录 (vector, leaf) 映射供删除复用」，避免对 findLeaf 的依赖。
