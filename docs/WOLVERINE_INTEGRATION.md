# GTI + Wolverine 集成说明

## 1. 方案 A：可选 Wolverine 后端（已实现）

通过 CMake 选项 `GTI_USE_WOLVERINE` 开启或关闭 Wolverine，便于对比删除策略效果。

### 1.1 编译与运行

**启用 Wolverine**（删除使用 patch-delete）：
```bash
cd GTI-Graph-based-Tree-Index/GTI
mkdir -p build && cd build
cmake -DGTI_USE_WOLVERINE=ON ..
make
cd ../..
./run_update.sh sift
```

**禁用 Wolverine**（默认，使用 n2 原始删除流程）：
```bash
cd GTI/build
cmake -DGTI_USE_WOLVERINE=OFF ..
make
cd ../..
./run_update.sh sift
```

### 1.2 sift 测试结果（1M 数据，10k 插入 + 10k 删除）

| 指标 | Wolverine 开启 | Wolverine 关闭 (n2) |
|------|----------------|---------------------|
| 索引构建 | ~159s（ef_build=100） | ~34s |
| 插入后召回 (10k 插入) | ~0.88（ef_search=5*L） | ~0.98 |
| 删除后召回 (10k 删除) | ~0.80 | - |
| 单次搜索耗时 | ~0.56ms（ef=300） | ~0.96ms |
| 图更新耗时/批次 | ~0.18–0.27s | 较长 (buildFromDeletion) |

- Wolverine 使用 `patchDelete`（模式 4：APPROXIMATE_TWOHOP_DELETE），无需 `buildFromDeletion`，图更新耗时稳定。
- 召回提升：`setEf(5*L)` 与 n2 对齐，插入后召回由 0.85→0.88，删除后由 0.76→0.80。

### 1.3 数据格式支持

Wolverine 原生使用 `.fbin` 格式，GTI 使用 `.fvecs` 和 `.ivecs`。已在 Wolverine 的 `hnsw_Wolverine.h` 中增加 GTI 格式读取：

| 格式 | 结构 | Wolverine 函数 |
|------|------|----------------|
| **fvecs** | 每向量: 4B dim + dim×4B float | `readInitDataFvecs`, `readQuerysFvecs` |
| **ivecs** | 每行: 4B k + k×4B int | `readGroundTruthIvecs` |

---

## 2. 索引构建过程详细对比

### 2.1 原 GTI (n2) 构建流程

| 阶段 | 操作 | 特点 |
|------|------|------|
| 1. AddData | 遍历 entries_sec，`index_hnsw->AddData(data->vecs[oid])` | 仅将向量存入 `data_list_`，不做图连接 |
| 2. Build | `index_hnsw->Build(m, max_m0, ef_construction, n_threads)` | 核心：**并行**构建图 |
| 2a. BuildGraph | `#pragma omp parallel for schedule(dynamic, 128)` 遍历 i=1..N | 每个线程独立 `VisitedList`，可并行插入 |
| 2b. InsertNode | 对每个点：随机 level → 从 enterpoint 沿高层下降 → 在 0 层做 beam search (ef_construction 候选) → mutuallyConnect | 多线程同时插入不同节点 |
| 2c. MergeEdges | 若启用 graph_merging，做第二遍反向构建并合并 | 可选后处理 |

**时间瓶颈**：单次 Build 内多线程并行，1M 点约 34s。

### 2.2 Wolverine 构建流程

| 阶段 | 操作 | 特点 |
|------|------|------|
| 1. 初始化 | `new L2Space`、`new HierarchicalNSW(..., ef_construction, ...)` | 预分配内存 |
| 2. addPoint 循环 | `for i in entries_sec: index_wolverine->addPoint(vec, label)` | **完全串行**，逐个插入 |
| 2a. 每点 addPoint | ① 分配槽位 ② 从 enterpoint 沿各层贪心下降 ③ 每层 `searchBaseLayer(currObj, point, level)` 使用 **ef_construction** 候选 ④ `mutuallyConnectNewElement` 双向连边 | 点 i+1 依赖点 i 插入后的图状态 |
| 3. setEf | `index_wolverine->setEf(50)` | 设置**搜索时** ef，与构建无关 |

**时间瓶颈**：N 次串行 addPoint，每次含 O(log N) 层 × O(ef_construction) 的 beam search，且无法并行（图状态强依赖）。

### 2.3 构建时间差异原因总结

| 因素 | n2 | Wolverine |
|------|-----|-----------|
| **并行** | ✅ OMP 多线程 InsertNode | ❌ 串行 addPoint |
| **每点复杂度** | 同量级 beam search | 同量级，但 ef_build 已 cap 到 100 |
| **总复杂度** | O(N × ef / n_threads) 有效 | O(N × ef) 无并行 |
| **典型耗时** | ~34s (1M) | ~163s (1M) |

Wolverine 为 hnswlib 风格增量构建，不支持 n2 式批量并行 Build，因此构建时间显著更长。

### 2.4 召回提升：搜索 ef 对齐 n2

n2 的 `SearchByVectorM` 使用 `ef_search = 5*L`（如 L=60 时为 300），而 Wolverine 原先固定 `setEf(50)`，搜索 beam 过窄导致召回偏低。已改为在每次搜索前调用 `setEf(std::max(50, 5*L))`，与 n2 的 ef 策略对齐，以提升召回。

### 2.5 进一步提升 Wolverine 召回（可选调参）

Wolverine 相较 n2 删除后召回约低 10%（如 0.796 vs 0.877），可通过环境变量提升：

| 环境变量 | 默认 | 说明 | 效果 |
|----------|------|------|------|
| `GTI_WOLVERINE_EF_BUILD` | ef_construction(160) | 构建时 beam 宽度 | 提高可改善图质量，构建变慢 |
| `GTI_SEARCH_EF_MULTIPLIER` | 5 | 搜索 ef = 倍数×L | 提高到 8 或 10 可提升召回，搜索变慢 |

**默认已与 n2 对齐**：`ef_build=160`, `ef_mult=5`，扫参显示再提高对召回提升有限（~0.1%）。

### 2.6 首批插入召回 88% vs n2 98% 的原因分析

插入第一批 1000 条后，Wolverine 召回约 88%，n2 约 98%，相差约 10%。可能原因：

| 因素 | n2 | Wolverine |
|------|-----|-----------|
| **插入后图状态** | 每批插入后执行 `UnloadModel` + 全量 `AddData` + `Build`，即**全图重建** | 仅对新增点做 `addPoint`，**增量插入**，不重建 |
| **图质量** | 每次插入后都得到针对当前数据分布的“最优”图 | 图在初始 1M 构建后不再整体优化，新增点的邻居选择依赖既有图 |
| **插入顺序** | 并行 Build 导致等效乱序 | 树 BFS 序（`GTI_WOLVERINE_SHUFFLE_ORDER=1` 可打乱，实测提升有限） |

**结论**：主要差距来自 n2 每批插入后全图重建，而 Wolverine 使用增量图。Wolverine 目前无批量重建接口，若要接近 n2 召回，可考虑：① 定期用 Wolverine 全量重建（实现成本高）；② 继续调高 `GTI_WOLVERINE_EF_BUILD`（构建变慢）；③ 接受增量图带来的召回差距，换取快速 patchDelete。

### 2.7 其他提升召回方向（从索引构建/搜索入手）

在 ef 对齐后召回仍较 n2 低约 8%，可尝试以下方向：

| 方向 | 说明 | 实现难度 |
|------|------|----------|
| **增大搜索 L** | update 中 L=60，图返回 L 个候选再树求精。`GTI_SEARCH_L=120` 可提高候选覆盖 | 低，已支持 env |
| **图插入顺序** | Wolverine 按树遍历顺序 addPoint，n2 并行 Build 等效乱序。`GTI_WOLVERINE_SHUFFLE_ORDER=1` 打乱插入顺序（实测对首批召回提升有限） | 低，已支持 env |
| **分裂策略** | `GTI_SPLIT_STRATEGY=mst` 可改善空间划分，或影响第二层分布 | 低，已有 env 支持 |
| **增大 M** | m=16，`GTI_M=24` 或 32 可得更密图 | 低，已支持 env |
| **树容量** | capacity_up_l=2 产生很多小叶。调整或影响 entries_sec 分布 | 中 |
| **patchDelete 参数** | delete_model、newLinkSize 等可能影响删除后图质量 | 中，需读 Wolverine 源码 |

**快速试验 L、M 与插入顺序**（见 2.6 关于 88% 差距的说明）：
```bash
export GTI_SEARCH_L=120              # 图候选数 60→120，可提升召回
export GTI_M=24                      # 图连通度 16→24，构建更密图
export GTI_WOLVERINE_SHUFFLE_ORDER=1 # 打乱图插入顺序（对 88% 首批召回提升有限，主因见 2.6 节）
./run_update.sh sift wolverine
```

---

## 3. GTI 与 Wolverine 删除逻辑对比

| 方面 | GTI (n2) | Wolverine (hnswlib) |
|------|----------|---------------------|
| 策略 | lazy_delete → 超阈值则 rebuild | patchDelete：直接修图、补链 |
| 删除流程 | deleteNeighbor + deleteData + reinsertData + buildFromDeletion | 一次性 patch，更新邻居并回收槽位 |
| 索引体积 | 持续增大 | 可收缩，内部 id 复用 |
| 召回 | 随删除累积下降 | 删除后仍可保持较好召回 |

---

## 4. 集成方案（设计）

GTI 第二层图使用 `n2::Hnsw`，与 Wolverine 的 `hnswlib::HierarchicalNSW` 接口和实现不同，需要做适配层。

### 方案 A：可选 Wolverine 后端（编译选项）

1. 在 GTI 中加入 Wolverine 作为可选图后端（如 `GTI_USE_WOLVERINE`）
2. 在 `buildGraphSec` 中：用 `addPoint` 替代 `n2::AddData` / `Build`
3. 在 `deleteGraph` 中：调用 `patchDelete` 替代当前的 delete + rebuild
4. 在搜索中：实现与 `SearchByVectorM` 等价的接口，包装 Wolverine 的 `searchKnn`

**关于「能否用 n2 批量构建 + Wolverine 删除」：不可行。** n2 与 Wolverine（hnswlib）的图结构不兼容：n2 使用自有格式，Wolverine 使用 hnswlib 的 `label_lookup_`、`linkLists_` 等。`patchDelete` 必须作用在 Wolverine 自身构建的图上；若用 n2 构建，则没有可用的 Wolverine 图，无法执行 patch-delete。若要使用 Wolverine 删除，构建阶段也必须用 Wolverine 的 `addPoint`。

### 方案 B：Wolverine 风格的 delete 优化

在保持 n2 的前提下，参考 Wolverine 的 patch 思路，改进 n2 的 rebuild 流程：

- 在 `buildFromDeletion` 前，对受影响的邻居做“补链”（如两跳、近似两跳）
- 需要修改或扩展 n2 的图操作接口

---

## 5. 当前 GTI 删除流程简述

```cpp
// process.cpp: 分批 lazy delete
gti->deleteGTI_lazyOids(chunk_oids);  // 仅标记

// 超过 rebuild_threshold 时
gti->deleteGTI(&all_delete_obj, true);  // 调用 deleteTree + deleteGraph

// gti.cpp deleteGraph:
// 1. 遍历删除节点，做 range search 找反向邻居
// 2. index_hnsw->deleteNeighbor(...)
// 3. index_hnsw->deleteData(gid)
// 4. index_hnsw->reinsertData(reinsert_gids)
// 5. index_hnsw->buildFromDeletion()  // 开销最大
```

---

## 6. Wolverine patchDelete 模式

| 模式 | 说明 |
|------|------|
| VIOLENT_DELETE (0) | 仅标记删除 |
| PINTOPOUT_DELETE (1) | 从邻居中移除被删节点，用其邻居补空 |
| SEARCH_DELETE (2) | 搜索找新邻居 |
| TWOHOP_DELETE (3) | 两跳邻居选新边 |
| APPROXIMATE_TWOHOP_DELETE (4) | 近似两跳，质量与效率折中 |

### 6.1 树辅助候选池（GTI_TREE_AUGMENTED_PATCH）

**方向 1 实现**：利用 GTI 树的 `searchTreeRange` 为 patchDelete 提供额外补链候选，与图候选合并。支持 APPROXIMATE_TWOHOP 与 **SEARCH**（Wolverine）分支；SEARCH 分支将树候选与 `MYsearchBaseLayer` 图搜索候选合并。

**启用方式**：
```bash
GTI_TREE_AUGMENTED_PATCH=1 GTI_RESULT_SUFFIX=_tree_aug ./run_update.sh sift wolverine
```

**环境变量**：

| 变量 | 默认 | 说明 |
|------|------|------|
| `GTI_TREE_AUGMENTED_PATCH` | 0 | 设为 `1` 启用树辅助 |
| `GTI_TREE_PATCH_RADIUS` | 5.0 | searchTreeRange 的半径 |
| `GTI_TREE_PATCH_MAX_AFFECTED` | 500 | 每批最多为多少个受影响节点注入树候选；设为 `0` 表示不限制，对所有受影响节点做树搜索 |
| `GTI_TREE_PATCH_MAX_CANDS_PER_LABEL` | 256 | 每个受影响节点最多保留的树候选数（按距离排序后截断），用于 max_affected 较大时避免 OOM |

**sift 初步验证（max_affected=500）**：终态 recall 与基线相当（~0.797），删除耗时约 2.6×（因每批对 500 个受影响节点做 searchTreeRange）。可调高 `GTI_TREE_PATCH_MAX_AFFECTED`（如 2000、5000）或设为 `0` 评估理论上限；可增大 `GTI_TREE_PATCH_RADIUS`（如 7.0）以获取更多树候选。方向 1 的 searchTreeRange 已并行化。

### 6.2 树引导补链优先级（GTI_TREE_PRIORITY_SAME_LEAF）

**方向 2 实现**：在候选池中优先考虑与受影响节点同叶（同簇）的节点，使补链更符合空间局部性。

**启用方式**：
```bash
GTI_TREE_PRIORITY_SAME_LEAF=1 GTI_RESULT_SUFFIX=_same_leaf ./run_update.sh sift wolverine
```

**环境变量**：

| 变量 | 默认 | 说明 |
|------|------|------|
| `GTI_TREE_PRIORITY_SAME_LEAF` | 0 | 设为 `1` 启用同叶优先 |
| `GTI_SAME_LEAF_BOOST` | 0.999 | 同叶候选的距离修正系数（d×boost）；0.99 使同叶优先更明显，0.95 更强 |

**实现说明**：在 patchDelete 的 PINTOPOUT、TWOHOP、APPROXIMATE_TWOHOP、**SEARCH** 分支中，对候选进行距离排序时，对同叶候选施加 `GTI_SAME_LEAF_BOOST`× 距离修正，使其在距离相近时优先被选中。SEARCH（Wolverine）分支现已支持方向 2。

**sift 初步验证**：终态 recall 与基线相当（~0.797），删除耗时约 1.1×（~22s vs ~20s，同叶集合构建与查找开销）。可与方向 1 同时启用。可尝试 `GTI_SAME_LEAF_BOOST=0.99` 以强化同叶优先。

### 6.3 跨方向可选参数

| 变量 | 默认 | 说明 |
|------|------|------|
| `GTI_WOLVERINE_DELETE_MODEL` | WolverineProMax | 可选删除模型：**WolverineProMax**（4=APPROX_TWOHOP）、**WolverinePro**（3=TWOHOP）、**Wolverine**（2=SEARCH）；与 test.sh 的 deletemodelmap 对应 |
| `GTI_PATCH_DELETE_MODE` | 4 | patchDelete 模式（数字）：1=PINTOPOUT，2=SEARCH，3=TWOHOP，4=APPROXIMATE_TWOHOP；`GTI_WOLVERINE_DELETE_MODEL` 优先 |
| `GTI_PATCH_NEW_LINK_SIZE` | m | 补链时每节点新增边数；适当增大（如 24、32）可能提升 recall |

### 6.4 推荐的调参组合示例

```bash
# 方向 1 加强：覆盖更多节点 + 更大半径
GTI_TREE_AUGMENTED_PATCH=1 GTI_TREE_PATCH_MAX_AFFECTED=2000 GTI_TREE_PATCH_RADIUS=7.0 \
  GTI_RESULT_SUFFIX=_d1_2k_r7 ./run_update.sh sift wolverine

# 方向 2 加强：同叶优先更明显
GTI_TREE_PRIORITY_SAME_LEAF=1 GTI_SAME_LEAF_BOOST=0.99 \
  GTI_RESULT_SUFFIX=_d2_boost99 ./run_update.sh sift wolverine

# 方向 1+2 组合 + 高质量模式（质量上界参考）
GTI_TREE_AUGMENTED_PATCH=1 GTI_TREE_PRIORITY_SAME_LEAF=1 \
  GTI_TREE_PATCH_MAX_AFFECTED=2000 GTI_SAME_LEAF_BOOST=0.99 \
  GTI_PATCH_DELETE_MODE=2 GTI_RESULT_SUFFIX=_d1d2_quality ./run_update.sh sift wolverine

# 验证不同删除模型效果（WolverineProMax / WolverinePro / Wolverine）
./run_update.sh sift wolverine WolverineProMax   # 默认，结果到 wolverine_WolverineProMax/
./run_update.sh sift wolverine WolverinePro      # 两跳删除
./run_update.sh sift wolverine Wolverine         # 搜索删除

# Wolverine (SEARCH) + 方向 1+2 组合（SEARCH 现已支持树辅助与同叶优先）
GTI_TREE_AUGMENTED_PATCH=1 GTI_TREE_PRIORITY_SAME_LEAF=1 \
  GTI_RESULT_SUFFIX=_d1d2_search ./run_update.sh sift wolverine Wolverine
```

---

## 7. 测试与对比

### Wolverine 原生 + GTI sift

```bash
cd test/Wolverine
./run_wolverine_gti_sift.sh 50
```

### GTI 更新实验

```bash
cd test/GTI-Graph-based-Tree-Index/GTI-Graph-based-Tree-Index
./run_update.sh sift
```

可在 recall、删除耗时、索引体积等方面对比两种实现。
