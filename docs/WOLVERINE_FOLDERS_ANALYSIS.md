# Wolverine 实验文件夹策略分析

基于 `run.log` 中的 `[GTI_TREE_AUGMENTED_PATCH]`、`[GTI_TREE_PRIORITY_SAME_LEAF]` 等日志，对各文件夹的策略进行识别。

---

## 一、9 个文件夹策略对照表

| 文件夹 | 方向1（树辅助） | 方向2（同叶优先） | 关键参数 | Delete 耗时 | 终态 recall |
|--------|-----------------|-------------------|----------|-------------|-------------|
| **wolverine_baseline** | 关 | 关 | 纯 patchDelete | 19.76s | 0.797 |
| **wolverine_dir2_baseline** | 关 | 关 | 无 TREE/SAME_LEAF 输出 | 19.92s | 0.797 |
| **wolverine_same_leaf** | 关 | 开 | SAME_LEAF_BOOST=0.999（默认） | 21.80s | 0.797 |
| **wolverine_d2_boost99** | 关 | 开 | SAME_LEAF_BOOST=0.99（加强） | 22.31s | 0.797 |
| **wolverine_mode2_quality** | 关 | 关 | GTI_PATCH_DELETE_MODE=2（SEARCH） | 24.39s | 0.797 |
| **wolverine_tree_aug** | 开 | 关 | max_affected=500, with_tree_cands≈500 | 53.28s | 0.797 |
| **wolverine_dir1_and_dir2** | 开 | 开 | max_affected=500, with_tree_cands≈500 | 55.75s | 0.797 |
| **wolverine_d1_2k_r7** | 开 | 关 | max_affected=2000, radius=7, with_tree_cands≈2000 | 155.38s | 0.797 |
| **wolverine** | 开 | 开 | max_affected=2000, radius=7, with_tree_cands≈2000 | 157.52s | 0.797 |

---

## 二、重复性分析

| 类型 | 文件夹 | 重复对象 | 结论 |
|------|--------|----------|------|
| **与 baseline 重复** | wolverine_dir2_baseline | wolverine_baseline | 两者均无方向1/2，recall 与耗时几乎相同（19.92s vs 19.76s） |
| **方向1+2 加强 与 方向1 加强** | wolverine | wolverine_d1_2k_r7 | 耗时相近（157s vs 155s），方向2 在 2k 场景下几乎无额外开销；d1_2k_r7 命名更清晰 |
| **方向2 默认 vs 加强** | wolverine_d2_boost99 | wolverine_same_leaf | recall 相同，耗时差约 2%；保留 same_leaf 作为方向2 代表即可 |

---

## 三、保留建议（6 个必要文件夹）

| 保留 | 策略 |
|------|------|
| **wolverine_baseline** | 基线（无方向1/2） |
| **wolverine_same_leaf** | 方向2（同叶优先，默认 boost） |
| **wolverine_tree_aug** | 方向1（树辅助，max_affected=500） |
| **wolverine_dir1_and_dir2** | 方向1+2（标准参数） |
| **wolverine_d1_2k_r7** | 方向1 加强（2k, r=7） |
| **wolverine_mode2_quality** | GTI_PATCH_DELETE_MODE=2（质量优先模式） |

---

## 四、待删除（3 个重复）

| 删除 | 原因 |
|------|------|
| **wolverine_dir2_baseline** | 与 baseline 完全重复 |
| **wolverine** | 与 d1_2k_r7 功能重叠，后者命名更清晰 |
| **wolverine_d2_boost99** | 与 same_leaf 效果几乎一致（recall 相同，耗时差 2%） |
