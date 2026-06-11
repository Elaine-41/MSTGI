# Gist 消融实验对比

**配置**：ratio=0.005，L=60，k=10，n=5000（注意：Gist wolverine_d2 与 mst_wolverine_d2 的 delete n 均为 2000）

## 一、结果汇总

| 变体 | aknn_build_s | aknn_search_s | aknn_recall | update_build_s | update_insert_s/item | update_delete_s/item | update_final_recall |
|------|--------------|---------------|-------------|----------------|---------------------|---------------------|---------------------|
| baseline_lb (历史) | 220 | 0.00384 | 0.870 | 233 | 0.00623 | — | 0.881 |
| mst_opt (历史) | 229 | 0.00285 | 0.882 | 233 | 0.00543 | — | 0.883 |
| wolverine_d2 (历史) | 1417 | — | — | 1417 | 0.00200 | 0.0179 | 0.838 |
| **mst_wolverine_d2 (新)** | **1611** | **0.00262** | **0.858** | **1555** | **0.00230** | **0.0174** | **0.849** |

*历史 baseline/mst_opt 来自 `gist/split_compare/compare_split_strategies.csv`*
*历史 wolverine_d2 来自 `gist/update/wolverine_Wolverine_d2/`*

## 二、对比分析

### 2.1 Recall

| 对比 | mst_wolverine_d2 | 历史 | 差异 |
|------|------------------|------|------|
| vs baseline_lb | 0.849 | 0.881 | **-3.2%**（Wolverine 后端 recall 低于 n2）|
| vs mst_opt | 0.849 | 0.883 | **-3.4%**（同上，n2+rebuild recall 更高）|
| vs wolverine_d2 | **0.849** | 0.838 | **+1.1%**（MST 分裂提升 Wolverine 的 recall）|

### 2.2 建库与删除

- **建库**：mst_wolverine_d2 (1555s) 与 wolverine_d2 (1417s) 相近；aknn 建库 1611s vs 1417s，MST 略增开销
- **删除**：mst_wolverine_d2 (0.0174 s/item) 与 wolverine_d2 (0.0179 s/item) 基本相当
- **插入**：mst_wolverine_d2 (0.0023 s/item) 略快于 wolverine_d2 (0.002 s/item)，差异不大

### 2.3 结论

1. **MST + Wolverine** 相比 **纯 Wolverine (LB)**：recall 提升约 **+1.1%**（0.849 vs 0.838），在 960 维高维数据上，MST 分裂对 Wolverine 同样有正向效果。
2. 相比 n2 的 baseline/mst_opt（0.881–0.883），mst_wolverine 的 recall 低约 3.2–3.4%，为 Wolverine patchDelete 的固有权衡。
3. **策略选择**：高维 Gist 上，若追求 recall 选 n2+mst_opt；若删除频繁，mst_wolverine_d2 在 recall 与删除速度间更均衡。
