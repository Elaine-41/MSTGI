#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""基于 6.2 表格绘制折线图与柱状图（英文标签避免字体方框）"""

import matplotlib.pyplot as plt

OUT_DIR = "/home/shiyi/test/GTI-Graph-based-Tree-Index/GTI-Graph-based-Tree-Index/results"

# ========== 图1: Recall 对比柱状图 (GTI vs Wolverine 三数据集) ==========
def fig1_recall_bar():
    fig, ax = plt.subplots(figsize=(8, 5))
    datasets = ['Sift', 'Gist', 'Deep']
    gti_recalls = [0.877, 0.874, 0.936]  # lazy
    wolverine_recalls = [0.796, 0.850, 0.907]
    x = range(len(datasets))
    w = 0.35
    bars1 = ax.bar([i - w/2 for i in x], gti_recalls, w, label='GTI (lazy)', color='#2ecc71')
    bars2 = ax.bar([i + w/2 for i in x], wolverine_recalls, w, label='Wolverine', color='#3498db')
    ax.set_xticks(x)
    ax.set_xticklabels(datasets)
    ax.set_ylabel('Recall (after delete)')
    ax.set_title('Recall: GTI vs Wolverine')
    ax.legend()
    ax.set_ylim(0.7, 1.0)
    for b in bars1 + bars2:
        ax.annotate(f'{b.get_height():.3f}', xy=(b.get_x() + b.get_width()/2, b.get_height()),
                    ha='center', va='bottom', fontsize=9, rotation=0)
    plt.tight_layout()
    plt.savefig(f'{OUT_DIR}/fig1_recall_comparison.png', dpi=150, bbox_inches='tight')
    plt.close()
    print('Saved fig1_recall_comparison.png')

# ========== 图2: 删除时间对比柱状图 (s/item, 对数) ==========
def fig2_delete_time_bar():
    fig, ax = plt.subplots(figsize=(10, 5))
    labels = ['Sift\ndirect', 'Sift\nlazy', 'Sift\nwolverine', 'Gist\nlazy', 'Gist\nwolverine',
              'Deep\nlazy', 'Deep\nwolverine', 'SHG\nno_rebuild', 'SHG\nrebuild']
    delete_times = [0.128, 0.120, 0.001, 0.035, 0.004, 0.371, 0.001, 0.018, 0.007]
    colors = ['#e74c3c', '#e74c3c', '#3498db', '#e74c3c', '#3498db', '#e74c3c', '#3498db', '#9b59b6', '#9b59b6']
    bars = ax.bar(labels, delete_times, color=colors)
    ax.set_ylabel('Delete time (s/item)')
    ax.set_title('Delete Time Comparison (lower is better)')
    ax.set_yscale('log')
    ax.set_ylim(0.0005, 0.5)
    plt.xticks(rotation=15, ha='right')
    plt.tight_layout()
    plt.savefig(f'{OUT_DIR}/fig2_delete_time_comparison.png', dpi=150, bbox_inches='tight')
    plt.close()
    print('Saved fig2_delete_time_comparison.png')

# ========== 图3: MST Recall 提升柱状图 ==========
def fig3_mst_recall_bar():
    fig, ax = plt.subplots(figsize=(6, 5))
    datasets = ['Deep', 'Gist']
    baseline = [0.937, 0.881]
    mst_best = [0.958, 0.889]
    x = range(len(datasets))
    w = 0.35
    ax.bar([i - w/2 for i in x], baseline, w, label='LB baseline', color='#95a5a6')
    ax.bar([i + w/2 for i in x], mst_best, w, label='MST best', color='#27ae60')
    ax.set_xticks(x)
    ax.set_xticklabels(datasets)
    ax.set_ylabel('Recall (after delete)')
    ax.set_title('MST-Split Recall Improvement')
    ax.legend()
    ax.set_ylim(0.85, 1.0)
    for i, (b, m) in enumerate(zip(baseline, mst_best)):
        ax.annotate(f'+{(m-b)*100:.1f}%', xy=(i, m), ha='center', va='bottom', fontsize=11)
    plt.tight_layout()
    plt.savefig(f'{OUT_DIR}/fig3_mst_recall_improvement.png', dpi=150, bbox_inches='tight')
    plt.close()
    print('Saved fig3_mst_recall_improvement.png')

# ========== 图4: OPS 对比柱状图 ==========
def fig4_ops_bar():
    fig, ax = plt.subplots(figsize=(5, 5))
    labels = ['Lazy', 'Wolverine']
    insert_ops = [1027, 1819]
    delete_ops = [189, 3516]
    x = range(len(labels))
    w = 0.35
    ax.bar([i - w/2 for i in x], insert_ops, w, label='insert_OPS', color='#1abc9c')
    ax.bar([i + w/2 for i in x], delete_ops, w, label='delete_OPS', color='#e67e22')
    ax.set_xticks(x)
    ax.set_xticklabels(labels)
    ax.set_ylabel('OPS (ops/s)')
    ax.set_title('OPS Throughput (Sift)')
    ax.legend()
    for b in ax.patches:
        ax.annotate(f'{b.get_height():.0f}', xy=(b.get_x() + b.get_width()/2, b.get_height()),
                    ha='center', va='bottom', fontsize=10)
    plt.tight_layout()
    plt.savefig(f'{OUT_DIR}/fig4_ops_comparison.png', dpi=150, bbox_inches='tight')
    plt.close()
    print('Saved fig4_ops_comparison.png')

# ========== 图5: Recall vs 删除时间 折线/散点 (权衡曲线) ==========
def fig5_tradeoff():
    fig, ax = plt.subplots(figsize=(8, 6))
    # 数据: (delete_s/item, recall)
    points = [
        (0.371, 0.936, 'Deep lazy'),
        (0.128, 0.904, 'Sift direct'),
        (0.120, 0.877, 'Sift lazy'),
        (0.035, 0.874, 'Gist lazy'),
        (0.018, 0.756, 'SHG no_rebuild'),
        (0.007, 0.756, 'SHG rebuild'),
        (0.004, 0.850, 'Gist wolverine'),
        (0.001, 0.796, 'Sift wolverine'),
        (0.001, 0.907, 'Deep wolverine'),
    ]
    x = [p[0] for p in points]
    y = [p[1] for p in points]
    labels = [p[2] for p in points]
    colors = ['#27ae60' if 'lazy' in l or 'direct' in l else '#3498db' if 'wolverine' in l else '#9b59b6' for l in labels]
    ax.scatter(x, y, s=100, c=colors, alpha=0.8, edgecolors='black', linewidth=0.5)
    for i, (xi, yi, lab) in enumerate(zip(x, y, labels)):
        ax.annotate(lab, (xi, yi), xytext=(5, 5), textcoords='offset points', fontsize=8)
    ax.set_xlabel('Delete time (s/item)')
    ax.set_ylabel('Recall (after delete)')
    ax.set_title('Recall vs Delete Time Tradeoff')
    ax.set_xscale('log')
    ax.set_xlim(0.0005, 0.5)
    ax.set_ylim(0.72, 0.98)
    plt.tight_layout()
    plt.savefig(f'{OUT_DIR}/fig5_recall_delete_tradeoff.png', dpi=150, bbox_inches='tight')
    plt.close()
    print('Saved fig5_recall_delete_tradeoff.png')

if __name__ == '__main__':
    fig1_recall_bar()
    fig2_delete_time_bar()
    fig3_mst_recall_bar()
    fig4_ops_bar()
    fig5_tradeoff()
    print('All figures saved to', OUT_DIR)
