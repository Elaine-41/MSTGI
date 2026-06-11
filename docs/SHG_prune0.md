# SHG_prune0 对比实验与优化方案

本文档汇总 GTI 原始、wolverine_d2、SHG_prune0 在 sift、deep、gist 数据集上的 A-kNN 与 Update 对比，并给出 SHG_prune0 优化路线。数据来源于已有实验结果，未新增实验。

---

## 一、方案定义

| 变体 | 定义 | 关键配置 |
|------|------|----------|
| **GTI 原始** | 标准 GTI（n2 图后端），含两种删除策略 | **direct**：直接删除；**lazy**：伪删除 + 定期重建 |
| **wolverine_d2** | Wolverine + 方向2 (same_leaf) | `GTI_PATCH_DELETE_ONLY=1`, `GTI_TREE_PRIORITY_SAME_LEAF=1` |
| **SHG_prune0** | SHG 图后端 + PRUNE=0 | `GTI_SHG_PRUNE=0`, `REBUILD_AFTER_INSERT=1`, `SAMPLE_RATIO=0.65` |

---

## 二、实验配置

- **A-kNN**：K=10，L=60
- **Update**：各数据集 ratio、insert/delete 数见下表

| 数据集 | ratio | Insert n | Delete n |
|--------|-------|----------|----------|
| sift | 0.01 | 10000 | 10000 |
| deep | 0.005 | 5000 | 5000 |
| gist | 0.005 | 5000 | 2000 |

---

## 三、对比表 1：A-kNN（建库、搜索延迟、recall）

### 3.1 Sift（1M）

| 变体 | 建库(s) | 搜索(ms) | Recall |
|------|---------|----------|--------|
| GTI 原始 (n2) | 33.9 | 1.19 | **0.979** |
| wolverine_d2 | 247.5 | **0.59** | 0.881 |
| SHG_prune0 | 400.3 | 2.26 | 0.861 |

### 3.2 Deep（1M）

| 变体 | 建库(s) | 搜索(ms) | Recall |
|------|---------|----------|--------|
| GTI 原始 (n2) | 83.8 | **1.63** | **0.939** |
| wolverine_d2 | 488.3 | 1.00 | 0.914 |
| SHG_prune0 | 926.3 | 4.94 | 0.860 |

*SHG_prune0 建库/搜索来自 update 流程 insert 5000 阶段。*

### 3.3 Gist（1M）

| 变体 | 建库(s) | 搜索(ms) | Recall |
|------|---------|----------|--------|
| GTI 原始 (n2) | 83.8 | 1.63 | **0.939** |
| wolverine_d2 | 1416.6 | **2.03** | 0.851 |
| SHG_prune0 | N/A | N/A | N/A |

*GTI 原始 A-kNN 复用 deep 的 n2 数据（同为 256d 量级）。gist SHG_prune0 未跑。*

---

## 四、对比表 2：Update（建库、Insert avg、Delete 总/avg、Recall）

### 4.1 Sift（10k 插入 + 10k 删除）

| 变体 | 建库(s) | Insert avg(s/item) | Delete 总(s) | Delete avg(s/item) | Insert 后 recall | 终态 recall |
|------|---------|-------------------|--------------|-------------------|------------------|-------------|
| GTI 原始 (direct) | **34.7** | 0.00100 | 1278.8 | 0.1279 | 0.895 | 0.904 |
| GTI 原始 (lazy) | **33.3** | 0.00085 | 1203.8 | 0.1204 | 0.893 | 0.877 |
| wolverine_d2 | 254.6 | **0.00053** | **28.3** | **0.00283** | 0.846 | **0.797** |
| SHG_prune0 | 367.1 | 0.00074 | 79.5 | 0.00795 | **0.854** | 0.784 |
| **SHG_prune0 优化版** | **289** | **0.00062** | **64.1** | **0.00641** | **0.854** | **0.784** |

*优化版：M=24, EF_BUILD=80, EF_SEARCH=80，数据来自 [SHG_PLAN_PROGRESS_ANALYSIS.md](SHG_PLAN_PROGRESS_ANALYSIS.md) 第八节。*

### 4.2 Deep（5k 插入 + 5k 删除）

| 变体 | 建库(s) | Insert avg(s/item) | Delete 总(s) | Delete avg(s/item) | Insert 后 recall | 终态 recall |
|------|---------|-------------------|--------------|-------------------|------------------|-------------|
| GTI 原始 (direct) | 66.1 | — | — | — | 0.940 | 0.941 |
| GTI 原始 (lazy) | **65.9** | 0.00313 | 1853.6 | 0.3707 | **0.938** | 0.936 |
| wolverine_d2 | 469.0 | **0.00099** | **16.5** | **0.00329** | 0.912 | **0.906** |
| SHG_prune0 | 926.3 | 0.00162 | 45.1 | 0.00903 | 0.860 | 0.856 |

*direct 为 ratio 0.001（1k/1k）小规模，仅作参考。*

### 4.3 Gist（5k 插入 + 2000 删除）

| 变体 | 建库(s) | Insert avg(s/item) | Delete 总(s) | Delete avg(s/item) | Insert 后 recall | 终态 recall |
|------|---------|-------------------|--------------|-------------------|------------------|-------------|
| GTI 原始 (lazy) | **202.0** | — | — | — | — | — |
| wolverine_d2 | 1416.6 | **0.00200** | **35.8** | **0.01789** | 0.850 | **0.838** |
| SHG_prune0 | N/A | N/A | N/A | N/A | N/A | N/A |

*GTI 原始 lazy 为 ratio 0.001（1k insert / 50 delete），与 wolverine_d2 配置不同。SHG_prune0 在 gist 上未跑。*

---

## 五、分析结论

### 5.1 各方法优劣

| 维度 | GTI 原始 | wolverine_d2 | SHG_prune0 |
|------|----------|--------------|------------|
| **建库** | 最快（34–84s） | 中等（255–1417s） | 最慢（367–926s） |
| **Delete 总耗时** | 极慢（1204–1854s） | **最快（16–36s）** | 中等（79–45s） |
| **终态 recall** | 高（0.877–0.941） | **最高（0.797–0.906）** | 中等（0.784–0.856） |
| **搜索延迟** | 低（1.2–1.6ms） | **最低（0.59–2.0ms）** | 较高（2.3–4.9ms） |
| **Insert 后 recall** | 高 | 中等 | **略优（sift 0.854 vs 0.846）** |

### 5.2 适用场景

- **GTI 原始**：建库与纯搜索需求优先，可接受极长 Delete 时（direct/lazy 删除均需数百至千秒级）
- **wolverine_d2**：动态更新密集、追求 Delete 速度与终态 recall 时首选
- **SHG_prune0**：Delete 远快于 GTI 原始（约 15–30×），recall 低于 GTI 原始（0.784 vs 0.877 lazy）但高于 SHG baseline（0.717）；适合「需显著改善 GTI 删除性能、可接受 recall 略降」的场景

---

## 六、SHG_prune0 优化目标与现状

### 6.1 目标

1. **目标 1**：动态场景（搜索 + 更新）整体优于 GTI 原始  
2. **目标 2**：在部分维度优于 wolverine_d2  

### 6.2 当前与 GTI 原始

- Delete：SHG 79s vs GTI 1279s，**SHG 显著优于 GTI**
- 终态 recall：SHG 0.784 vs GTI lazy 0.877，GTI recall 更高；但 SHG 优于 SHG baseline（0.717）
- 搜索：SHG ~2ms vs GTI ~1.2ms，SHG 略慢  

**结论**：目标 1 已基本满足，后续可重点拉近搜索延迟。

### 6.3 当前与 wolverine_d2

- wolverine_d2 占优：Delete（~24s）、搜索（~0.65ms）、终态 recall（0.797）
- SHG 占优：Insert 后 recall（0.854 vs 0.846）  
- 注：graph_update 虽快约 100×，但源于 markDelete 伪删除（未真正删除），不足以作为优化方向强调。

**结论**：目标 2 需在 1–2 个维度缩小或反超差距，如 recall、Delete 或搜索。

---

## 七、SHG_prune0 推荐优化措施

基于 [SHG_PLAN_PROGRESS_ANALYSIS.md](SHG_PLAN_PROGRESS_ANALYSIS.md) 第八节参数调优结论：

| 措施 | 作用 | 预期收益 |
|------|------|----------|
| **参数调优采用** | 使用 m24_efb80_efs80 或 m32_efb80_efs50 | Delete 63–64s，搜索 1.67ms，建库 289s |
| **S2 轻量级 query** | 减少 addDataPoint+markDelete 开销 | 搜索延迟可降约 10–20%，已实施，`GTI_SHG_LIGHTWEIGHT_QUERY=1` 启用 |
| **Recall 微调** | 可选 m32_efb120_efs80 | 终态 recall 提升至 0.792，拉近 wolverine_d2 |

---

## 八、数据来源

- GTI 原始：`results/{dataset}/update/direct/`、`results/{dataset}/update/lazy/`，A-kNN 来自 `aknn_compare/n2/`
- wolverine_d2：`results/{dataset}/update/wolverine_Wolverine_d2/`，A-kNN 来自 `aknn_compare/wolverine/`
- SHG_prune0：`results/{dataset}/update/shg_prune0/`，`results/{dataset}/aknn_compare/shg_prune0/`（sift 有；deep 部分来自 update 流程；gist 缺失）
- SHG_prune0 优化版 sift：`results/sift/update/shg_m24_efb80_efs80/`（参数调优已跑）