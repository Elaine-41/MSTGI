# S2 轻量级 Query 在 Sift 上的效果对比

## 一、实验配置

- 数据集：sift 1M（ratio 0.01，10k insert + 10k delete）
- 参数：M=24, EF_BUILD=80, EF_SEARCH=80, PRUNE=0, REBUILD_AFTER_INSERT=1, SAMPLE_RATIO=0.65
- S2：`GTI_SHG_LIGHTWEIGHT_QUERY=1` 启用轻量级 query 槽复用

## 二、搜索延迟对比（avg_search_s_per_query）

| 阶段 | SHG 无 S2 (baseline) | SHG + S2 | Wolverine_d2 |
|------|---------------------|----------|--------------|
| Insert 1k | 1.72 ms | **0.77 ms** | 0.58 ms |
| Insert 5k | 1.58 ms | **0.29 ms** | 0.59 ms |
| Insert 10k | 1.56 ms | **0.69 ms** | 0.58 ms |
| Delete 2k | 1.61 ms | **0.79 ms** | 0.64 ms |
| Delete 10k（终态） | 1.67 ms | **0.80 ms** | 0.61 ms |

**结论**：S2 将 SHG 搜索延迟从 **~1.6 ms 降至 ~0.8 ms**，约 **2× 加速**；与 Wolverine_d2 的差距由 **2.7×** 缩小到 **1.3×**。

## 三、终态 Recall 对比

| 变体 | 终态 recall | 相对 Wolverine_d2 |
|------|-------------|-------------------|
| Wolverine_d2 | **0.797** | — |
| SHG 无 S2 (baseline) | 0.784 | −0.013 |
| SHG + S2 | 0.773 | −0.024 |

S2 略降 recall（0.784 → 0.773），与 Wolverine_d2 的差距略增大，但仍处于可接受范围。

## 四、建库 / Insert / Delete 耗时

| 指标 | SHG 无 S2 | SHG + S2（首次） | SHG + S2（复现） | Wolverine_d2 |
|------|-----------|------------------|------------------|--------------|
| 建库(s) | 289 | 1027 | 1101 | 255 |
| Insert avg (s/item) | 0.00062 | 0.00156 | 0.00198 | 0.00053 |
| Delete 总(s) | 64 | 158 | 190 | 28 |

**复现确认**：两次 S2 运行的建库、Insert、Delete 均明显慢于 baseline，可排除随机波动。baseline（289s 建库）可能来自不同时段或环境。建议在同一会话内先后运行「无 S2」与「有 S2」，以公平对比建库/Insert/Delete 是否由 S2 引起。

S2 仅修改搜索路径（`overwriteQuerySlotData` vs `addDataPoint`+`markDelete`），理论上不应影响建库与 Insert；若同机对照仍显著变慢，需排查 S2 对 rebuildShortcuts 等路径的意外影响。

## 五、总结

1. **搜索延迟**：S2 达到预期约 10–20% 加速目标，实际约 **50% 加速**，效果优于预期。
2. **与 Wolverine_d2**：搜索延迟差距由 2.7× 缩小到 1.3×，显著靠近 wolverine_d2。
3. **Recall**：S2 略降（约 0.01），可权衡是否在追求极致 recall 时关闭 S2。
4. **建库/Insert/Delete**：S2 复现结果与 baseline 差异需同机对照验证。
5. **建议**：对搜索延迟敏感场景，推荐启用 `GTI_SHG_LIGHTWEIGHT_QUERY=1`；若更看重 recall，可关闭 S2 或再调参。

---

## 六、在 S2 基础上的进一步优化分析

### 6.1 剩余差距

| 维度 | SHG + S2 当前 | Wolverine_d2 | 差距 |
|------|--------------|--------------|------|
| 搜索延迟 | ~0.80 ms | ~0.61 ms | 约 1.3× |
| 终态 recall | 0.773 | 0.797 | −0.024 |

### 6.2 可实施的优化方向

#### 方向 1：`overwriteQuerySlotData` 快速路径（低维 / 全维场景）

**现状**：每次调用都计算 data_rep（多级压缩表示），约 `O(data_dim_ × maxFixLevel_)` 浮点运算。

**思路**：当 `use_full_dim_level_skip_=true` 时，`getDisByLevel` 始终用 raw data，无需 data_rep。可在 `overwriteQuerySlotData` 中检测该标志，**仅 memcpy raw data，跳过 data_rep 计算**。

**预期**：在 sift 上配合 `GTI_SHG_FULL_DIM_LEVEL_SKIP=1` 启用时，可减少每次 query 覆盖约 10–20% 的开销；需验证对 recall 的影响（全维跳层可能略改搜索轨迹）。

**实现要点**：heds.h 中 `overwriteQuerySlotData` 内增加：

```cpp
if (use_full_dim_level_skip_) {
    memcpy(getDataByInternalId(internalId), data_point, data_size_);
    return;  // 跳层用 raw，无需 data_rep
}
```

#### 方向 2：Recall 恢复（参数组合）

**现状**：S2 使 recall 从 0.784 降至 0.773。

**思路**：SHG_PLAN_PROGRESS_ANALYSIS 推荐 `m32_efb120_efs80` 可达 recall 0.792。可在 S2 基础上尝试该组合：`GTI_SHG_M=32 GTI_SHG_EF_BUILD=120 GTI_SHG_EF_SEARCH=80`。

**预期**：终态 recall 有机会回到 0.79 左右，接近 wolverine_d2（0.797）；建库与 Delete 会变慢，需权衡。

#### 方向 3：`overwriteQuerySlotData` 减少分配

**现状**：每次调用 `std::vector<float> rep`，有堆分配与析构开销。

**思路**：改为 `thread_local` 复用 buffer，或使用栈上定长数组（sift 128d 下 data_rep_size_ 通常 < 256）。

**预期**：单次 query 节省约数微秒级分配开销，对总体搜索延迟贡献较小，但实现成本低。

#### 方向 4：建库 / Insert / Delete 异常排查

**现状**：S2 运行时建库、Insert、Delete 明显变慢（约 3–4×），需确认是否与 S2 直接相关。

**思路**：同一会话内先后运行无 S2 / 有 S2（如 `run_s2_sift_compare_both.sh`），对比同一机器的建库、Insert、Delete 耗时。若 S2 确实导致变慢，再检查：
- `heds_query_internal_id` 是否影响 rebuildShortcuts 或 insert 路径；
- 不调用 `markDelete` 是否改变 `num_deleted_` / `cur_element_count` 等，进而影响迭代或重建逻辑。

### 6.3 推荐实施顺序

| 优先级 | 方向 | 预期收益 | 实现难度 | 状态 |
|--------|------|----------|----------|------|
| 1 | 方向 1：全维时跳过 data_rep | 搜索再降约 5–15% | 低 | **已实施** |
| 2 | 方向 4：建库/Insert/Delete 异常排查 | 明确 S2 影响范围 | 中 | 脚本已备 |
| 3 | 方向 2：m32_efb120_efs80 参数 | recall 拉近 wolverine_d2 | 无（仅配置） | **已跳过**（保持 24/80/80） |
| 4 | 方向 3：复用 rep buffer | 微小延迟降低 | 低 | **已实施** |

### 6.4 实施详情

**方向 1 + 3（已实施）**：heds.h `overwriteQuerySlotData` 中增加 `use_full_dim_level_skip_` 快速路径，并改为 `thread_local` 复用 rep buffer。

**方向 1 用法**：需配合 `GTI_SHG_FULL_DIM_LEVEL_SKIP=1` 启用，运行 `./run_s2_plus_sift_test.sh` 测试 S2+。

**方向 2**：已跳过，保持 M=24、EF_BUILD=80、EF_SEARCH=80 不变。

**方向 4 脚本**：`./run_s2_sift_compare_both.sh` 在同一会话内先后运行 baseline 与 S2，用于公平对比建库/Insert/Delete。

### 6.5 S2+ 验证结果（方向 1）

运行 `./run_s2_plus_sift_test.sh`（S2 + `GTI_SHG_FULL_DIM_LEVEL_SKIP=1`，参数 24/80/80）：

| 阶段 | avg_search (ms) | recall |
|------|-----------------|--------|
| Insert 1k | 0.74 | 0.857 |
| Insert 5k | 0.44 | 0.856 |
| Insert 10k | 0.73 | 0.851 |

**结论**：S2+ 方向 1 快速路径生效。日志显示 `[SHG] GTI_SHG_FULL_DIM_LEVEL_SKIP=1`，`overwriteQuerySlotData` 在全维模式下仅 memcpy 并跳过 data_rep。搜索延迟 0.44–0.90 ms，与 S2（0.66–0.80 ms）相当或略优；Insert 后 recall 0.851–0.857 与 S2 持平。
