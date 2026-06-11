# GTI SHG 策略改进指南

依据 SHG-Index 源码与现有实验数据，针对两类数据制定改进路径，使 SHG 在部分场景下具备 Wolverine 无法替代的价值。

---

## 目标总览

| 数据类型 | 目标 | 成功标准 |
|----------|------|----------|
| **低维（sift 128d, deep 96d）** | 在 recall、搜索、或更新时间中至少一项优于 Wolverine | 实验可量化体现优势 |
| **高维（gist 960d）** | 达到可用 recall，可选 searchKnnHNSW 回退或参数调优 | recall ≥ 0.75，可对比 lazy/wolverine |

---

## 一、现状对比（依据 results/）

### 1.1 Sift (128d) — SHG vs Wolverine

| 指标 | Wolverine | SHG | 差距 |
|------|-----------|-----|------|
| 建库 | 341s | 534s | SHG 慢 57% |
| recall（建库后） | 0.881 | 0.836 | SHG 低 0.045 |
| recall（插入后） | 0.846 | 0.825 | SHG 低 0.021 |
| recall（删除后） | 0.797 | 0.756 | SHG 低 0.041 |
| 搜索 ms/query | 0.58 | 4.98 | SHG 慢 8.6x |
| 插入 s/item | 0.000535 | 0.001008 | SHG 慢 1.9x |
| 删除 s/item | 0.00105 | 0.00688 | SHG 慢 6.5x |

### 1.2 Deep (96d) — Wolverine

recall 0.912→0.907，SHG 缺少直接对比数据，可假定与 sift 趋势类似。

### 1.3 Gist (960d) — SHG vs Wolverine

| 指标 | Wolverine | SHG 压缩 | SHG 全维跳层 |
|------|-----------|----------|--------------|
| recall（插入后） | 0.851 | 0.47 | 0.55 |
| 搜索 ms/query | ~12–17 | ~12–17 | ~2.6–3.2 |

高维下 SHG 主要问题是 recall 过低；全维跳层已带来提升，但仍明显落后 Wolverine。

---

## 二、低维数据（sift, deep）改进：建立相对 Wolverine 的优势

目标：在 recall、搜索延迟、或更新时间中至少一项优于 Wolverine。

### 2.1 策略 A：提升 recall，争取追上或超过 Wolverine

| 改动 | 文件 | 环境变量/实现 | 预期 |
|------|------|---------------|------|
| 增大 M | gti.cpp | `GTI_SHG_M=24` 或 `32`（默认用树 m=16） | 图更密，recall 提升 |
| 增大 ef_construction | gti.cpp | `GTI_SHG_EF_BUILD=80`（SHG-Index 默认 80） | 建图质量提升 |
| 增大搜索 ef | gti.cpp | `GTI_SHG_EF_SEARCH=50`（当前 ef_=10） | 基底层 beam 更宽，recall 提升 |

**实现要点**：在 `buildGraph()` 中，SHG 分支优先读取 `GTI_SHG_M`、`GTI_SHG_EF_BUILD`；首次搜索前根据 `GTI_SHG_EF_SEARCH` 调用 `index_heds->setEf()`。

**验证**：sift 上 rerun update，比较 `recall_after_insert` 与 `recall_after_delete`。

---

### 2.2 策略 B：缩短搜索时间，利用 level-skipping

理论：Shortcuts + 跳层应减少高层遍历和距离计算，搜索应比标准 HNSW 更省。

现状：sift 上 SHG 4.98ms vs Wolverine 0.58ms，说明存在明显瓶颈。

| 改动 | 说明 | 预期 |
|------|------|------|
| 关闭 prune | `GTI_SHG_PRUNE=0` | 去掉 `searchBaseLayerSTPrune` 的剪枝开销，可能提速 |
| 提高 ef_ 减少无效搜索 | `GTI_SHG_EF_SEARCH=30~50` | 避免因 ef 太小导致多次无效尝试 |
| 检查 level-skip 是否生效 | `GTI_SHG_VERBOSE_LEVELSKIP=1` | 确认 `levelsSkip` 被调用且跳层合理 |
| 优化 Shortcuts 质量 | 提高 `GTI_SHG_EF_BUILD` | 更准的 Shortcuts → 更有效跳层 → 更少计算 |

**实现要点**：在 `gti.cpp` 的搜索路径前后记录 `metric_distance_computations`、`metric_hops`，对比 Shortcuts 与 HNSW 路径，定位瓶颈。

**成功标准**：sift 上 SHG 搜索 ≤ Wolverine 的 1.5x（约 0.9ms 以内）。

---

### 2.3 策略 C：缩短更新时间（插入 / 删除）

| 改动 | 说明 | 预期 |
|------|------|------|
| 插入后不重建 Shortcuts | `GTI_SHG_REBUILD_AFTER_INSERT=0` | 插入阶段省去 rebuild 时间 |
| 采样重建 | `GTI_SHG_SHORTCUT_SAMPLE_RATIO=0.5` | 重建时只对 50% 点重算，加快 rebuild |
| 延迟重建 | 累计插入超过 N 再 rebuild | 插入阶段进一步缩短 |

**注意**：删除时间主要由 tree 的 `deleteTree` 主导，`markDelete` 为 O(1)。若实测 SHG 删除仍明显慢于 Wolverine，需确认是否在删除路径中触发了不必要的 `rebuildShortcuts`。

**成功标准**：sift 上 SHG 单次插入平均时间 ≤ Wolverine 的 1.2x（约 0.00064s/item）。

---

### 2.4 低维推荐执行顺序

1. **先做策略 A（参数）**：`GTI_SHG_M=24`、`GTI_SHG_EF_BUILD=80`、`GTI_SHG_EF_SEARCH=50`，在 sift 上跑完整 update 流程。
2. **再做策略 B（搜索）**：在策略 A 基础上尝试 `GTI_SHG_PRUNE=0`，对比 recall 与搜索延迟。
3. **最后做策略 C（更新）**：视需求调整 `GTI_SHG_REBUILD_AFTER_INSERT` 和 `GTI_SHG_SHORTCUT_SAMPLE_RATIO`。

---

## 三、高维数据（gist）改进：回退与参数并行

目标：在 gist 上达到可用 recall（≥ 0.75），并兼顾搜索与更新时间。

### 3.1 方案 1：searchKnnHNSW 回退（优先）

**思路**：当 `data->dim >= GTI_SHG_HNSW_FALLBACK_DIM` 时，改用 `searchKnnHNSW`，完全不用 Shortcuts 和压缩，全程全维距离。

| 项目 | 说明 |
|------|------|
| 接口 | `heds.h` 中 `searchKnnHNSW(Query)`，已存在 |
| 修改位置 | `gti.cpp` 中 `search()`、`searchExactKnn()` 的 SHG 分支 |
| 环境变量 | `GTI_SHG_HNSW_FALLBACK_DIM=256`（默认，0 表示禁用） |
| 预期 recall | 有望接近或达到 lazy/wolverine 水平（0.85+） |
| 预期搜索 | 略慢于 Shortcuts 路径，但可接受 |

**实现要点**：

```cpp
// gti.cpp 中，SHG 搜索分支
unsigned fallback_dim = 256;
if (const char *s = std::getenv("GTI_SHG_HNSW_FALLBACK_DIM"))
    fallback_dim = (unsigned)std::strtoul(s, nullptr, 10);
auto pq = (fallback_dim > 0 && data->dim >= fallback_dim)
    ? index_heds->searchKnnHNSW(q)
    : index_heds->searchKnnShortcuts(q);
```

需保证 `searchKnnHNSW` 能正确使用 `isIdAllowed`（lazy delete 过滤）。若当前实现无该参数，需在 heds 中扩展接口或在外层过滤结果。

---

### 3.2 方案 2：继续优化 searchKnnShortcuts 参数

若暂不启用 HNSW 回退，可通过参数减轻高维下的 recall 损失：

| 参数 | 建议值 | 说明 |
|------|--------|------|
| `GTI_SHG_FULL_DIM_LEVEL_SKIP` | 1 | 已实现，搜索层用全维距离 |
| `GTI_SHG_EF_BUILD` | 120–200 | 建图更充分 |
| `GTI_SHG_M` | 24–32 | 图更密（若与树 m 解耦） |
| `GTI_SHG_EF_SEARCH` | 80–100 | 基底层 beam 更宽 |

当前全维跳层在 gist 上约 0.55 recall，与 Wolverine 0.85 仍有差距，参数调优可小幅提升，但难以根本解决问题，高维仍建议以 HNSW 回退为主。

---

### 3.3 高维推荐执行顺序

1. **实现并启用 HNSW 回退**：`GTI_SHG_HNSW_FALLBACK_DIM=256`，在 gist 上跑 update。
2. **对比 recall 与延迟**：与 Wolverine、lazy 对比，确认达到可用水平。
3. **可选参数微调**：在 HNSW 回退基础上再调 `GTI_SHG_EF_BUILD`、`GTI_SHG_EF_SEARCH`，在 recall 与搜索时间间取折中。

---

## 四、SHG-Index 可借鉴的算法与参数

### 4.1 除 HEDS 外的搜索路径

| 路径 | 文件 | 特点 |
|------|------|------|
| searchKnnShortcuts | heds.h | Shortcuts + PGM 跳层，多分辨率压缩 |
| searchKnnHNSW | heds.h | 标准 HNSW 逐层全维距离，无 Shortcuts |

高维场景下可优先使用 `searchKnnHNSW` 作为回退路径。

### 4.2 参数对比

| 参数 | SHG-Index | GTI 当前 |
|------|-----------|----------|
| M | 48 | 16（树 m） |
| ef_construction | 80 | 5*max_m0 |
| ef_（搜索） | 未显式设置 | 10 |

低维、高维均可参考 SHG-Index 适当提高 M 与 ef 系列参数。

---

## 五、修改项与优先级汇总

### 5.1 低维（sift, deep）— 建立相对 Wolverine 的优势

| 优先级 | 改动 | 文件 | 目标 |
|--------|------|------|------|
| P0 | `GTI_SHG_M`、`GTI_SHG_EF_BUILD`、`GTI_SHG_EF_SEARCH` | gti.cpp | recall 追上 Wolverine |
| P1 | 支持 `GTI_SHG_PRUNE`，排查搜索瓶颈 | gti.cpp / heds.h | 搜索时间优于 Wolverine |
| P2 | `GTI_SHG_REBUILD_AFTER_INSERT`、采样重建 | gti.cpp | 插入时间优于 Wolverine |

### 5.2 高维（gist）— 达到可用性能

| 优先级 | 改动 | 文件 | 目标 |
|--------|------|------|------|
| P0 | 高维自动切换 searchKnnHNSW | gti.cpp | recall ≥ 0.75 |
| P1 | 支持 `GTI_SHG_HNSW_FALLBACK_DIM` | gti.cpp | 可配置回退阈值 |
| P2 | HNSW 路径支持 isIdAllowed | heds.h | 正确过滤 lazy delete |

### 5.3 通用

| 优先级 | 改动 | 文件 |
|--------|------|------|
| P2 | buildShortcuts 全维距离模式 | heds.h |
| P2 | 完善 `GTI_SHG_*` 环境变量文档 | README / docs |

---

## 六、验证命令示例

### 低维（sift）— 参数优先

```bash
# 策略 A：recall 优先
export GTI_SHG_M=24
export GTI_SHG_EF_BUILD=80
export GTI_SHG_EF_SEARCH=50
./run_update.sh sift shg

# 策略 B：搜索优先（在 A 基础上）
export GTI_SHG_PRUNE=0
./run_update.sh sift shg
```

### 高维（gist）— HNSW 回退

```bash
# 启用 HNSW 回退（dim>=256 时）
export GTI_SHG_HNSW_FALLBACK_DIM=256
./run_update.sh gist shg
```

---

## 七、参考文件

| 功能 | SHG-Index | GTI hnsw_SHG |
|------|------------|--------------|
| HNSW 回退搜索 | `hnswlib/heds.h` searchKnnHNSW | `extern_libraries/hnsw_SHG/hnswlib/heds.h` |
| Shortcuts 搜索 | `hnswlib/heds.h` searchKnnShortcuts | 同上 |
| 建图 | addDataPoint | addDataPoint |
| 参数 | M=48, ef_constr=80 | m=16，可通过 GTI_SHG_* 覆盖 |
