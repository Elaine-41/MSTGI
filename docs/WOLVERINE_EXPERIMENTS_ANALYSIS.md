# Wolverine 实验回顾与 SHG 对比分析

基于 sift 1M、10k 插入 + 10k 删除（ratio=0.01）的实验结果，汇总 Wolverine 方向 1+2 改进策略的效果，并与 SHG 参数调优方案对比。

---

## 一、失败实验目录清理

以下子目录因无法完成实验（总线错误、std::bad_alloc、未生成 update_summary 等）已被删除：

| 目录 | 失败原因 |
|------|----------|
| `wolverine_max0` | 总线错误（max_affected=0 全量树搜索，加入 max_cands_per_label 前） |
| `wolverine_max5k` | std::bad_alloc（第二批删除时内存不足） |
| `wolverine_max10k` | std::bad_alloc |
| `wolverine_max_affected0` | 与 max0 类似，未完成 |
| `wolverine_d1d2_2k_r7_boost99` | 目录几乎为空或未正常运行 |

---

## 二、成功实验：方向 1+2 策略结果汇总

### 2.1 实验配置说明

| 配置名 | 对应目录 | 方向 1（树辅助） | 方向 2（同叶优先） | 关键参数 |
|--------|----------|------------------|--------------------|----------|
| **Baseline** | wolverine_baseline | 关 | 关 | 纯 Wolverine patchDelete |
| **方向 1** | wolverine_tree_aug | 开 | 关 | max_affected=500, radius 默认 |
| **方向 2** | wolverine_same_leaf | 关 | 开 | GTI_SAME_LEAF_BOOST=0.999 |
| **方向 2 加强** | wolverine_d2_boost99 | 关 | 开 | SAME_LEAF_BOOST=0.99 |
| **方向 1+2** | wolverine_dir1_and_dir2 | 开 | 开 | 两者同时开启 |
| **方向 1 加强** | wolverine_d1_2k_r7 | 开 | 关 | max_affected=2000, radius=7.0 |
| **Mode 2 质量** | wolverine_mode2_quality | — | — | GTI_PATCH_DELETE_MODE=2 |

### 2.2 核心指标对比

| 配置 | 终态 recall | Delete avg (s/item) | Delete 总耗时 (10k) | 建库时间 |
|------|-------------|---------------------|----------------------|----------|
| **Baseline** | **0.797** | **0.001976** | **19.76 s** | 240 s |
| 方向 1 (tree_aug) | 0.797 | 0.005328 | 53.28 s | 249 s |
| 方向 2 (same_leaf) | 0.797 | 0.002180 | 21.80 s | 240 s |
| 方向 2 加强 (boost99) | 0.797 | 0.002231 | 22.31 s | — |
| **方向 1+2** | 0.797 | 0.005575 | 55.75 s | 244 s |
| 方向 1 加强 (2k_r7) | 0.797 | 0.015538 | 155.38 s | 244 s |
| Mode 2 质量 | 0.797 | 0.002439 | 24.39 s | — |

### 2.3 删除阶段 Recall 曲线

各 Wolverine 配置的 recall 曲线**完全一致**，终态均为 0.797：

| 已删除数 | recall |
|----------|--------|
| 2000 | 0.846 |
| 4000 | 0.846 |
| 6000 | 0.824 |
| 8000 | 0.808 |
| 10000 | **0.797** |

### 2.4 分析结论

1. **Recall 未提升**：方向 1、方向 2 及组合在 sift 1M、1% 删除场景下，终态 recall 均与 baseline 相同（0.797）。可能原因：
   - 方向 1：树候选与图两跳候选重叠率高，补链选边与 baseline 差异不大
   - 方向 2：同叶候选与距离排序结果高度重合
   - 删除比例 1% 可能不足以体现 GTI 树结构的辅助收益

2. **删除耗时**：
   - 方向 1 明显增加耗时（~2.7× baseline），方向 1 加强（2k_r7）更达 ~7.9×
   - 方向 2 开销较小（~1.1× baseline）
   - 方向 1+2 耗时接近方向 1，方向 2 额外开销可忽略

3. **推荐**：若追求 recall 不变、删除尽量快，维持 **Baseline** 或 **方向 2**（same_leaf）即可；方向 1 在 recall 无提升的情况下带来显著耗时增加。

---

## 三、Wolverine vs SHG 方案对比

参考 `SHG_PLAN_PROGRESS_ANALYSIS.md` 第八节参数调优结果，将 Wolverine 与 SHG 调优后的最佳配置进行对比。

### 3.1 对比表（sift，10k insert + 10k delete）

| 指标 | Wolverine Baseline | Wolverine 方向1+2 | SHG m24_efb80_efs80（综合推荐） | SHG m32_efb120_efs80（Recall 最优） |
|------|--------------------|-------------------|----------------------------------|-------------------------------------|
| **建库时间** | **240 s** | 244 s | **289 s** | 452 s |
| **Delete 总耗时** | **19.76 s** | 55.75 s | 64.13 s | 72.44 s |
| **Delete avg (s/item)** | **0.00198** | 0.00558 | 0.00641 | 0.00724 |
| **终态 recall** | **0.797** | 0.797 | 0.784 | **0.792** |
| Insert 后 recall | 0.846 | 0.846 | 0.854 | 0.867 |
| 搜索延迟 (ms) | **0.65** | ~0.66 | 1.67 | 2.70 |

### 3.2 各方案优势分析

| 方案 | 优势 | 劣势 | 适用场景 |
|------|------|------|----------|
| **Wolverine Baseline** | Delete 最快（19.76 s）、recall 最高（0.797）、搜索最快（0.65 ms）、建库最快（240 s） | — | **综合首选**：update 密集、对 recall 和延迟敏感 |
| **Wolverine 方向1+2** | Recall 与 baseline 持平，具备 GTI 树辅助扩展能力 | Delete 约 2.8× 慢于 baseline，recall 无提升 | 实验/可扩展性验证，非生产推荐 |
| **SHG m24_efb80_efs80** | 建库 289 s 为 SHG 中最短，Delete 64 s、搜索 1.67 ms 均衡；graph_update 约 **100×** 快于 Wolverine | Recall 0.784 低于 Wolverine，Delete 约 3.2× 慢 | 若 graph 更新频率极高、可接受 recall 略降 |
| **SHG m32_efb120_efs80** | Recall 0.792 为 SHG 最高，Insert 后 recall 0.867 | 建库 452 s 最慢，Delete 72 s，搜索 2.7 ms | 质量敏感、建库一次性、可接受长 delete |

### 3.3 SHG 特有优势（来自 SHG_PLAN_PROGRESS_ANALYSIS）

- **graph_update**：SHG 使用 markDelete，每批约 0.0017 s，Wolverine patchDelete 约 0.19 s，SHG 快约 **100×**
- **Delete 总耗时**：仍由 deleteTree 的 1-NN 搜索主导，SHG 整体 64–79 s，慢于 Wolverine 19.76 s
- **参数调优后**：M=24 EF_BUILD=80 EF_SEARCH=80 综合性价比最佳；M=32 EF_BUILD=120 EF_SEARCH=80 为 recall 优先配置

### 3.4 小结

| 维度 | 优势方案 |
|------|----------|
| **Recall** | Wolverine（0.797）> SHG 最优（0.792）> SHG 综合（0.784） |
| **Delete 耗时** | Wolverine Baseline（19.76 s）<< SHG（64–79 s） |
| **建库时间** | Wolverine（240 s）< SHG 综合（289 s）< SHG recall 优先（452 s） |
| **搜索延迟** | Wolverine（0.65 ms）< SHG 综合（1.67 ms）< SHG recall 优先（2.70 ms） |
| **graph_update** | SHG（~0.0017 s/批）>> Wolverine（~0.19 s/批） |

**结论**：在 sift 1M、1% 更新场景下，Wolverine 在 recall、Delete 耗时、建库和搜索上均优于 SHG。SHG 的主要优势在 graph_update 的极快速度，但 deleteTree 的 1-NN 搜索 dominates 总 delete 耗时，因此整体 delete 仍慢于 Wolverine。Wolverine 方向 1+2 未带来 recall 提升，且删除耗时增加，建议维持 baseline 作为生产配置。

---

## 四、输出文件与引用

- Wolverine 实验：`results/sift/update/wolverine_*/`
- SHG 调优实验：`results/sift/update/shg_m24_efb80_efs80/`、`shg_m32_efb120_efs80/` 等
- SHG 分析文档：`docs/SHG_PLAN_PROGRESS_ANALYSIS.md`（第八节参数调优）
- Recall 验证：`results/sift/update/recall_comparison_analysis.md`
