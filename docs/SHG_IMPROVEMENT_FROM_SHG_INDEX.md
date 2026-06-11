# SHG-Index 借鉴与 GTI SHG 改进指南

## 一、SHG-Index 中除 HEDS 以外的算法

### 1.1 算法概览

| 算法/路径 | 文件位置 | 接口 | 特点 |
|----------|----------|------|------|
| **HEDS (searchKnnShortcuts)** | `heds.h` ~527–630 | `searchKnnShortcuts(Query)` | Shortcuts + PGM 跳层，多分辨率压缩 |
| **searchKnnHNSW** | `heds.h` ~2499–2555 | `searchKnnHNSW(Query)` | 标准 HNSW 逐层下降，全维距离，无 Shortcuts |
| **addPointHNSW** | `heds.h` ~2096–2498 | `addPointHNSW()` | 标准 HNSW 建图，无压缩表示 |

### 1.2 searchKnnHNSW 与 searchKnnShortcuts 的区别

```
searchKnnShortcuts:
  高层遍历 → getDisByLevel(压缩/全维) + levelsSkip(Shortcuts) → 可能跳层
  基底层   → searchBaseLayerST[Prune]

searchKnnHNSW:
  高层遍历 → fstdistfunc_(全维) 逐层贪婪下降，无跳层、无 Shortcuts
  基底层   → searchBaseLayerST（与 Shortcuts 版相同）
```

**searchKnnHNSW** 全程使用全维距离，不做压缩和 PGM 跳层，在高维（如 gist 960D）上通常能获得更高 recall，代价是高层遍历更慢。

### 1.3 example_search 中的使用方式

`example_search.cpp` 中 `algo` 只影响建图（`heds` 时调用 `addDataPoint`），搜索始终使用 `searchKnnShortcuts`。`run_search.sh` 虽遍历 `heds` 和 `hnsw`，但未实际调用 `searchKnnHNSW`。`searchKnnHNSW` 和 `addPointHNSW` 均已实现，可作为备用路径或对比实验。

---

## 二、GTI SHG 改进建议

### 2.1 高维场景下切换为 searchKnnHNSW（提升 recall）

**思路**：当 `data->dim` 超过阈值时，用 `searchKnnHNSW` 代替 `searchKnnShortcuts`，避免压缩和 Shortcuts 在高维上的 recall 损失。

**修改位置**：`GTI/src/gti.cpp` 约 2007–2063 行（`search` 和 `searchExactKnn`）。

**环境变量**：`GTI_SHG_HNSW_FALLBACK_DIM=512`（默认 512，0 表示禁用）。

**伪代码**：

```cpp
// gti.cpp search() 中，替换：
//   auto pq = index_heds->searchKnnShortcuts(q);
// 为：
bool use_hnsw_fallback = (data->dim >= fallback_dim_threshold);
if (use_hnsw_fallback)
    pq = index_heds->searchKnnHNSW(q);
else
    pq = index_heds->searchKnnShortcuts(q);
```

**注意**：`searchKnnHNSW` 需 `Query` 含 `query_Id`；GTI 通过 query slot 已满足，需保证 `isIdAllowed` 正确传入（支持 lazy delete 过滤）。

---

### 2.2 参数对齐 SHG-Index（提升 recall）

| 参数 | SHG-Index 默认 | GTI 当前 | 建议 |
|------|----------------|----------|------|
| M | 48 | 16（来自树） | 增加 `GTI_SHG_M`，高维可试 32–48 |
| ef_construction | 80 | 5*max_m0 | 已有 `GTI_SHG_EF_BUILD`，可试 80–200 |
| ef_ (搜索) | 未显式设置 | 10 | 增加 `GTI_SHG_EF_SEARCH`，可试 50–100 |

**修改位置**：`gti.cpp` `buildGraph()` 中 HEDS 构造与 `setEf()` 调用。

---

### 2.3 buildShortcuts 使用全维距离（提升 recall）

当前 `use_full_dim_level_skip_` 只影响搜索时的 `getDisByLevel`，`buildShortcuts` 中 `getavgDisatLevel`、`getNearestbyLevel` 仍使用压缩表示。

**修改**：在 `heds.h` 的 `buildShortcuts`、`getavgDisatLevel`、`getNearestbyLevel` 等路径中，当 `use_full_dim_level_skip_` 为 true 时，距离计算改用 `fstdistfunc_`/`getDataByInternalId`，与搜索一致。

---

### 2.4 缩短更新时间（rebuildShortcuts 优化）

**现状**：插入后调用 `rebuildShortcuts(num_base, sample_ratio)`，全量重建 Shortcuts 较慢。

**借鉴**：SHG-Index 无增量更新，仅一次性 `buildShortcuts`。GTI 已支持 `GTI_SHG_SHORTCUT_SAMPLE_RATIO` 采样。

**可做优化**：

1. **按插入比例采样**：`sample_ratio = 0.3`，只对约 30% 点重算 Shortcuts。
2. **延迟重建**：`GTI_SHG_REBUILD_AFTER_INSERT=0` 时跳过插入后重建，或累计插入数超过阈值再重建。
3. **增量更新 PGM**：评估 `DynamicPGMIndex::insert_or_assign` 做增量更新的可行性（需设计 key 与映射策略）。

---

### 2.5 搜索时间与 GTI_SHG_PRUNE

**现状**：`GTI_SHG_PRUNE=0` 时禁用 `searchBaseLayerSTPrune` 的剪枝，使用 `searchBaseLayerST`，搜索更快但 recall 可能下降。

**建议**：在高维或 recall 敏感场景保持 prune 开启；低维、追求延迟时可尝试 `GTI_SHG_PRUNE=0`，并对比 recall 与延迟。

---

### 2.6 修改项汇总（按优先级）

| 优先级 | 改动 | 文件 | 预期效果 |
|--------|------|------|----------|
| P0 | 高维时切换到 searchKnnHNSW | gti.cpp | gist 等场景 recall 显著提升 |
| P1 | 支持 GTI_SHG_M、GTI_SHG_EF_SEARCH | gti.cpp | recall 小幅提升 |
| P1 | buildShortcuts 支持全维距离 | heds.h | 高维 recall 再提升 |
| P2 | rebuildShortcuts 采样/延迟策略 | gti.cpp | 插入后更新时间缩短 |
| P2 | GTI_SHG_PRUNE 调参说明 | 文档 | 平衡 recall 与搜索延迟 |

---

## 三、快速验证：高维 HNSW 回退

最小改动验证高维下 HNSW 路径的 recall 收益：

1. 在 `gti.cpp` 的 `search()` 中，当 `data->dim >= 256` 时调用 `searchKnnHNSW` 而不是 `searchKnnShortcuts`。
2. 在 gist 上跑 update 实验，对比 recall。
3. 若 recall 明显提升，再完善 `isIdAllowed`、参数和文档。

---

## 四、参考文件索引

| 功能 | SHG-Index | GTI hnsw_SHG |
|------|-----------|--------------|
| HNSW 搜索 | `hnswlib/heds.h` searchKnnHNSW | `extern_libraries/hnsw_SHG/hnswlib/heds.h` |
| Shortcuts 搜索 | `hnswlib/heds.h` searchKnnShortcuts | 同上 |
| 建图 | addDataPoint / addPointHNSW | addDataPoint |
| 参数 | M=48, ef_constr=80 | m=16, ef 可调 |
