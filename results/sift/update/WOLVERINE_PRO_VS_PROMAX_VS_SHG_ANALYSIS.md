# Wolverine 删除模型与 SHG 效果对比分析

对比四种删除方案：**WolverineProMax**、**WolverinePro**、**Wolverine**、**SHG prune0**，在 sift 与 deep 数据集上的表现。

---

## 一、Sift 1M 实验结果

**配置**：10k 插入 + 10k 删除（ratio=0.01），chunk=2000，L=60，k=10

### 1.1 结果汇总

| 指标 | WolverineProMax | WolverinePro | Wolverine | SHG prune0 |
|------|-----------------|--------------|-----------|------------|
| **删除模型** | APPROX_TWOHOP (4) | TWOHOP (3) | SEARCH (2) | markDelete |
| **建库时间 (s)** | 240 | 344 | 337 | 367 |
| **删除总耗时 (s)** | **19.76** | 29.61 | 34.41 | 79.45 |
| **删除 s/item** | **0.00198** | 0.00296 | 0.00344 | 0.00795 |
| **终态 Recall** | **0.797** | **0.797** | **0.797** | 0.784 |
| **终态搜索延迟 (ms)** | **0.65** | 0.83 | 0.82 | 2.0 |

### 1.2 Sift 结论

- **Recall**：三种 Wolverine 均为 0.797，SHG 为 0.784（-1.6%）
- **删除速度**：WolverineProMax 最快（19.76s），Wolverine 最慢（34.41s），约 1.74× 差距；SHG 最慢（79.45s, 4×）
- **推荐**：Sift 上 **WolverineProMax** 综合最优

---

## 二、Deep 1M 实验结果

**配置**：5k 插入 + 5k 删除（ratio=0.005），chunk=1000，L=60，k=10

### 2.1 结果汇总

| 指标 | WolverineProMax | WolverinePro | Wolverine | SHG prune0 |
|------|-----------------|--------------|-----------|------------|
| **删除模型** | APPROX_TWOHOP (4) | TWOHOP (3) | SEARCH (2) | markDelete |
| **建库时间 (s)** | **459** | 593 | 796 | 926 |
| **删除总耗时 (s)** | **5.59** | 15.06 | 34.83 | 45.15 |
| **删除 s/item** | **0.00112** | 0.00301 | 0.00697 | 0.00903 |
| **终态 Recall** | **0.907** | 0.906 | 0.906 | 0.856 |
| **终态搜索延迟 (ms)** | **1.04** | 2.03 | 2.0~4.0 | 5.2 |

### 2.2 Deep 结论

- **Recall**：WolverineProMax 略高（0.907），WolverinePro/Wolverine 均为 0.906；SHG 明显较低（0.856，-5.6%）
- **删除速度**：WolverineProMax 最快（5.59s），Wolverine 次之（34.83s），SHG 最慢（45.15s）
- **推荐**：Deep 上 **WolverineProMax** 综合最优

---

## 三、跨数据集横向对比

### 3.1 Recall

| 数据集 | WolverineProMax | WolverinePro | Wolverine | SHG prune0 |
|--------|-----------------|--------------|-----------|------------|
| **Sift** | 0.797 | 0.797 | 0.797 | 0.784 |
| **Deep** | 0.907 | 0.906 | 0.906 | 0.856 |

### 3.2 删除速度（s/item，越小越快）

| 数据集 | WolverineProMax | WolverinePro | Wolverine | SHG prune0 |
|--------|-----------------|--------------|-----------|------------|
| **Sift** | **0.00198** | 0.00296 | 0.00344 | 0.00795 |
| **Deep** | **0.00112** | 0.00301 | 0.00697 | 0.00903 |

### 3.3 删除速度排序（相对 WolverineProMax）

| 数据集 | WolverinePro | Wolverine | SHG prune0 |
|--------|--------------|-----------|------------|
| **Sift** | 1.5× 慢 | 1.74× 慢 | 4.0× 慢 |
| **Deep** | 2.7× 慢 | 6.2× 慢 | 8.1× 慢 |

---

## 四、综合结论

| 维度 | 最优 | 说明 |
|------|------|------|
| **Recall** | WolverineProMax ≥ WolverinePro = Wolverine | 三者均优于 SHG |
| **删除速度** | WolverineProMax | 在两种数据集上均最快 |
| **搜索延迟** | WolverineProMax | 最低 |
| **建库** | WolverineProMax | 最快 |

**结论**：在 sift 与 deep 上，**WolverineProMax 综合最优**，无需切换到 WolverinePro 或 Wolverine。Wolverine（SEARCH）删除最慢，因需对每个受影响节点做图搜索；WolverinePro（TWOHOP）居中；WolverineProMax（APPROX_TWOHOP）在删除速度与 recall 上均优于其余方案。SHG 在 recall 与删除速度上均逊于 Wolverine 系列。

---

---

## 五、Wolverine (SEARCH) + 方向 1/2 验证（Sift）

在 SEARCH_DELETE 分支扩展方向 1（树辅助）和方向 2（同叶优先）后的验证结果。

### 5.1 结果汇总

| 配置 | 删除总耗时 (s) | 删除 s/item | 终态 Recall |
|------|----------------|-------------|-------------|
| Wolverine 纯 | 34.41 | 0.00344 | 0.797 |
| **Wolverine + 方向 1** | 59.32 | 0.00593 | 0.797 |
| **Wolverine + 方向 2** | **28.27** | **0.00283** | 0.797 |

### 5.2 分析

- **方向 1（树辅助）**：删除耗时约 1.72× 慢于纯 Wolverine（59.32s vs 34.41s），因每批对 ~500 个受影响节点做 `searchTreeRange`。Recall 与基线持平（0.797）。
- **方向 2（同叶优先）**：删除耗时**快于**纯 Wolverine（28.27s vs 34.41s，约 1.22× 加速）。Recall 持平（0.797）。同叶优先在 SEARCH 分支上带来删除加速，可能因更符合空间局部性的候选使 `getNeighborsByHeuristic2` 收敛更快。
- **推荐**：若使用 Wolverine（SEARCH），**建议开启方向 2**；方向 1 仅在追求候选丰富度且可接受删除变慢时考虑。

*数据来源*：
- Wolverine 纯: `wolverine_Wolverine/`
- Wolverine + 方向 1: `wolverine_Wolverine_d1/`（GTI_TREE_AUGMENTED_PATCH=1）
- Wolverine + 方向 2: `wolverine_Wolverine_d2/`（GTI_TREE_PRIORITY_SAME_LEAF=1）

---

## 六、Wolverine (SEARCH) + 方向 2 验证（Deep）

在 Deep 数据集上验证 Wolverine + 方向 2（同叶优先）与纯 Wolverine 的对比。

### 6.1 结果汇总

| 配置 | 删除总耗时 (s) | 删除 s/item | 终态 Recall |
|------|----------------|-------------|-------------|
| Wolverine 纯 | 34.83 | 0.00697 | 0.906 |
| **Wolverine + 方向 2** | **16.45** | **0.00329** | 0.906 |

### 6.2 分析

- **方向 2 在 Deep 上同样加速**：删除耗时约 **2.12× 快于**纯 Wolverine（16.45s vs 34.83s）。Recall 持平（0.906）。
- **跨数据集一致性**：Sift 与 Deep 上，方向 2 均在保持 recall 的前提下显著加速 Wolverine 删除，验证了同叶优先在 SEARCH 分支上的有效性。

*数据来源*：
- Wolverine 纯: `results/deep/update/wolverine_Wolverine/`
- Wolverine + 方向 2: `results/deep/update/wolverine_Wolverine_d2/`（GTI_TREE_PRIORITY_SAME_LEAF=1）

---

## 七、Wolverine (SEARCH) + 方向 2 验证（Gist）

在 Gist 数据集上验证 Wolverine + 方向 2（同叶优先）与纯 Wolverine 的对比。

**配置**：5k 插入 + 50 删除（ratio=0.005），chunk=500/10，L=60，k=10，960 维

### 7.1 结果汇总

| 配置 | 删除总耗时 (s) | 删除 s/item | 终态 Recall |
|------|----------------|-------------|-------------|
| Wolverine 纯 | **2.56** | **0.0513** | 0.85 |
| Wolverine + 方向 2 | 3.95 | 0.0789 | 0.85 |

### 7.2 分析

- **方向 2 在 Gist 上变慢**：删除耗时约 **1.54× 慢于**纯 Wolverine（3.95s vs 2.56s）。Recall 持平（0.85）。
- **跨数据集差异**：Sift、Deep 上方向 2 加速；Gist 上方向 2 变慢。可能原因：Gist 960 维、数据分布不同，同叶优先的额外计算（same_leaf_boost、候选排序）在 Gist 上开销大于收益。
- **推荐**：Gist 上若使用 Wolverine，**不建议开启方向 2**；保持纯 Wolverine 即可。

*数据来源*：
- Wolverine 纯: `results/gist/update/wolverine_Wolverine/`
- Wolverine + 方向 2: `results/gist/update/wolverine_Wolverine_d2/`（GTI_TREE_PRIORITY_SAME_LEAF=1）

---

*总体数据来源*：
- WolverineProMax: `wolverine_baseline/` (sift), `wolverine/` (deep)
- WolverinePro: `wolverine_WolverinePro/`
- Wolverine: `wolverine_Wolverine/`
- SHG prune0: `shg_prune0/`
