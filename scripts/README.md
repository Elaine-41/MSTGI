# 脚本目录说明

实验与构建相关脚本已按用途分类，均可在**项目根目录**下通过相对路径调用（脚本内部会自动 `cd` 到项目根目录）。

## 目录结构

```
scripts/
├── build/      # 编译脚本
├── run/        # 实验运行脚本（run_*.sh）
├── analysis/   # 结果汇总与分析
├── data/       # 数据集下载与数据相关实验
├── debug/      # 调试脚本
├── misc/       # 其他辅助脚本
└── logs/       # 历史运行日志
```

## 常用命令

### 编译

```bash
bash scripts/build/build_both.sh
```

同时编译 GTI（Wolverine）与 GTI_n2（原始 n2）。

### Gist 本地实验

```bash
bash scripts/run/run_gist_local.sh          # 本地 Datasets/gist 近似搜索 + 内存统计
bash scripts/run/run_gist_update.sh       # 动态更新实验
bash scripts/run/run_gist_k_sweep.sh      # k 值扫描
```

### 通用更新实验

```bash
bash scripts/run/run_update.sh <dataset> [strategy] [wolverine_delete_model]
# 示例
bash scripts/run/run_update.sh sift wolverine
bash scripts/run/run_update.sh deep shg
```

### 数据集下载

```bash
bash scripts/data/download_gist.sh
bash scripts/data/run_gist_experiment.sh   # 使用 /udata_disk/shiyi/gist 路径
```

### 结果分析

```bash
bash scripts/analysis/aggregate_mst_results.sh
bash scripts/analysis/analyze_shg_plan_results.sh
python3 scripts/analysis/plot_results.py
```

## run/ 脚本分类

| 类别 | 脚本 |
|------|------|
| 消融实验 | `run_ablation*.sh` |
| SHG 相关 | `run_shg_*.sh` |
| LSH 相关 | `run_lsh_*.sh`, `run_deep_lsh_experiment.sh` |
| MST 调参 | `run_mst_*.sh`, `aggregate_mst_results.sh` |
| S2 / S2+ | `run_s2_*.sh` |
| 删除策略对比 | `run_compare_*delete*.sh`, `run_baseline_update.sh` |
| Deep / Gist 更新 | `run_deep_*.sh`, `run_gist_*.sh` |
| 其他 | `run_recall_sweep.sh`, `run_gti_ops_sift.sh`, `run_aknn_compression_compare.sh` |

## 其他目录

- `thesis/` — 硕士论文 LaTeX 源文件与参考文献（原 `scripts/` 中的论文材料）
- `archives/` — 历史归档（如 `GTI.tar.gz`）
- `docs/` — 实验与设计文档
- `results/` — 实验输出结果
