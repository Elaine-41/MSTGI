# Deep 消融实验对比

**配置**：ratio=0.005，L=60，k=10，n=5000

## 一、结果汇总

| 变体 | aknn_build_s | aknn_search_s | aknn_recall | update_build_s | update_insert_s/item | update_delete_s/item | update_final_recall |
|------|--------------|---------------|-------------|----------------|---------------------|---------------------|---------------------|
| baseline_lb (历史) | ~74 | 0.0014 | 0.942 | ~74 | 0.0026 | — | 0.937 |
| mst_opt (历史) | ~78 | 0.0014 | 0.958 | ~79 | 0.0027 | — | 0.958 |
| wolverine_d2 (历史) | 469 | — | — | 469 | 0.00099 | 0.00329 | 0.906 |
| **mst_wolverine_d2 (新)** | **707** | **0.00125** | **0.934** | **703** | **0.00162** | **0.00503** | **0.925** |

*历史 baseline/mst_opt 来自 `split_compare/mst_param_tuning/mst_param_tuning_all1.csv`（n2 后端）*
*历史 wolverine_d2 来自 `deep/update/wolverine_Wolverine_d2/`*

## 二、对比分析

### 2.1 Recall

| 对比 | mst_wolverine_d2 | 历史 | 差异 |
|------|------------------|------|------|
| vs baseline_lb | 0.925 | 0.937 | **-1.2%**（MST+Wolverine 略低，因 Wolverine 图 recall 换删除速度）|
| vs mst_opt | 0.925 | 0.958 | **-3.3%**（mst_opt 为 n2+rebuild，recall 最高；mst_wolverine 用 patchDelete，有 recall 损失）|
| vs wolverine_d2 | **0.925** | 0.906 | **+1.9%**（MST 分裂提升 Wolverine 的 recall）|

### 2.2 建库与删除

- **建库**：mst_wolverine_d2 (707s) > wolverine_d2 (469s)，因 MST 分裂计算开销更大
- **删除**：mst_wolverine_d2 (0.005 s/item) 略慢于 wolverine_d2 (0.003 s/item)，但仍在同一量级
- **插入**：mst_wolverine_d2 (0.0016 s/item) 略慢于 wolverine_d2 (0.001 s/item)

### 2.3 结论

1. **MST + Wolverine** 相比 **纯 Wolverine (LB)**：recall 提升约 **+1.9%**（0.925 vs 0.906），验证 MST 分裂对 Wolverine 后端有正向作用。
2. 相比 n2 的 mst_opt（0.958），mst_wolverine 的 recall 低约 3.3%，是 patchDelete 的固有权衡。
3. **策略选择**：若追求 recall，选 mst_opt (n2)；若需快速删除，选 mst_wolverine_d2，在 recall 与删除速度间取得更好平衡。
