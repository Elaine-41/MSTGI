# SHG Plan 验证结果汇总

## 实验配置

- **基线**：`GTI_SHG_REBUILD_AFTER_INSERT=1` + `GTI_SHG_SHORTCUT_SAMPLE_RATIO=0.65` + `GTI_SHG_M=24` + `GTI_SHG_EF_BUILD=80` + `GTI_SHG_EF_SEARCH=50`
- **S4**：在基线上增加 `GTI_SHG_PRUNE=0`（禁用 searchBaseLayerSTPrune 剪枝）

## Sift 结果

| 实验 | 建库(s) | Search(ms) | Recall(insert) | Recall(delete后) | Delete总耗时(s) | Delete avg(s/item) |
|------|---------|------------|---------------|------------------|-----------------|-------------------|
| **baseline** | 359 | ~2.0 | 0.712 | **0.717** | 104.72 | 0.01047 |
| **prune0**   | 367 | ~1.9 | 0.854 | **0.784** | **79.45** | **0.00795** |

**结论（sift update）**：S4 (PRUNE=0) **优于** 基线——delete 提速 ~24%，recall 提升 0.067。

| 实验 | A-kNN Search(ms) | A-kNN Recall |
|------|------------------|--------------|
| **baseline** | **2.07** | 0.861 |
| **prune0**   | 2.26 | 0.861 |

**结论（sift aknn）**：baseline 搜索略快 ~9%，recall 相同。纯搜索场景 baseline 占优。

## Deep 结果

（实验进行中，待补充）

## 综合结论

- **Update 场景**：sift 上 GTI_SHG_PRUNE=0 明显更优，建议在 update 流程中可采用
- **A-kNN 纯搜索**：baseline（PRUNE 开启）略优，保持默认
- **S4 回滚决策**：**不回滚**——S4 在 update 场景有益，可通过环境变量按需选择

## S2/S3 状态

- **S2 轻量级 query 表示**：暂缓——需 heds 新增接口，改动大
- **S3 resultsProcessing 稀疏化**：暂缓——实现复杂度高
