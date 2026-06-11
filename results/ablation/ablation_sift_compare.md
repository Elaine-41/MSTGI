# Sift 消融实验对比

**配置**：ratio=0.01，L=60，k=10，n=10000

## 一、结果汇总

| 变体 | aknn_build_s | aknn_search_s | aknn_recall | update_build_s | update_insert_s/item | update_delete_s/item | update_final_recall |
|------|--------------|---------------|-------------|----------------|---------------------|---------------------|---------------------|
| baseline_lb (历史) | ~36 | 0.0011 | 0.979 | ~36 | 0.0017 | — | 0.967 |
| mst_opt (历史) | ~40 | 0.0010 | 0.980 | ~40 | 0.0017 | — | 0.968 |
| wolverine_d2 (历史) | 255 | — | — | 255 | 0.00053 | 0.00283 | 0.797 |
| **mst_wolverine_d2 (新)** | **401** | **0.00078** | **0.878** | **405** | **0.00079** | **0.00407** | **0.793** |

*历史 baseline/mst_opt 来自 `split_compare/mst_param_tuning/mst_param_tuning_all1.csv`（n2 后端）*
*历史 wolverine_d2 来自 `sift/update/wolverine_Wolverine_d2/`*

## 二、对比分析

### 2.1 Recall

| 对比 | mst_wolverine_d2 | 历史 | 差异 |
|------|------------------|------|------|
| vs baseline_lb | 0.793 | 0.967 | **-17.4%**（Wolverine 以 recall 换删除速度，与 n2 差距大）|
| vs mst_opt | 0.793 | 0.968 | **-17.5%**（同上）|
| vs wolverine_d2 | 0.793 | 0.797 | **-0.4%**（基本持平，Sift 上 MST 对删除后 recall 提升有限）|

### 2.2 建库与删除

- **建库**：mst_wolverine_d2 (401s) > wolverine_d2 (255s)，MST 分裂增加建库开销
- **aknn_recall**：mst_wolverine_d2 (0.878) **高于** wolverine 插入后 (0.846)，说明 MST 对图构建阶段 recall 有提升
- **删除**：mst_wolverine_d2 (0.004 s/item) 略慢于 wolverine_d2 (0.003 s/item)
- **插入**：mst_wolverine_d2 (0.00079 s/item) 略慢于 wolverine_d2 (0.00053 s/item)

### 2.3 结论

1. **Sift 上 MST + Wolverine** 与 **纯 Wolverine (LB)**：delete 后 recall 基本持平（0.793 vs 0.797），Sift 为 128 维、基线已较高，MST 对删除后 recall 的提升不如 Deep/Gist 明显。
2. **aknn 阶段**：MST 将图 recall 从 0.846 提升到 0.878（+3.8%），表明分裂策略对图质量有正向作用，但该优势在 delete 后未完全保持。
3. **策略选择**：Sift 若追求最高 recall，选 mst_opt (n2)；若需快速删除，wolverine_d2 与 mst_wolverine_d2 均可，两者 recall 与删除速度接近。
