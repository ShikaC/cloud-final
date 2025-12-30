#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# =============================================================================
# 读取 performance.csv 与 stress.csv 生成对比图表
# 输出目录：--output-dir (默认 ./results/visualization)
# =============================================================================

import argparse
import os
import sys
import logging
from pathlib import Path
from typing import List, Optional

import pandas as pd
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import seaborn as sns  # noqa: E402


def load_csv(path: str, required_cols: List[str]) -> pd.DataFrame:
    """加载CSV文件并验证必需的列
    
    Args:
        path: CSV文件路径
        required_cols: 必需的列名列表
        
    Returns:
        pandas DataFrame
        
    Raises:
        FileNotFoundError: 文件不存在
        ValueError: 缺少必需的列
    """
    if not Path(path).exists():
        raise FileNotFoundError(f"文件不存在: {path}")
    
    try:
        df = pd.read_csv(path)
    except Exception as e:
        raise ValueError(f"无法读取CSV文件 {path}: {e}")
    
    missing = [c for c in required_cols if c not in df.columns]
    if missing:
        raise ValueError(f"{path} 缺少必需的列: {missing}")
    
    logging.info(f"成功加载 {path}: {len(df)} 行数据")
    return df


def ensure_chinese_font() -> None:
    """确保中文字体可用
    
    尝试加载常见的中文字体，优先使用系统字体，其次尝试加载额外路径的字体。
    如果找不到中文字体，matplotlib会使用默认字体，可能导致中文显示为方框。
    """
    import matplotlib.font_manager as fm

    # 候选中文字体列表（按优先级排序）
    candidates = [
        "SimHei",           # 黑体
        "Microsoft YaHei",  # 微软雅黑
        "WenQuanYi Micro Hei",  # 文泉驿微米黑
        "Noto Sans CJK SC",     # 思源黑体
        "Source Han Sans CN",   # 思源黑体（Adobe版本）
    ]

    # 额外尝试从常见路径加载字体（含 WSL 访问 Windows 字体）
    extra_paths = [
        "/usr/share/fonts/truetype/wqy/wqy-microhei.ttc",
        "/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc",
        "/mnt/c/Windows/Fonts/simhei.ttf",
        "/mnt/c/Windows/Fonts/msyh.ttc",
    ]
    
    for font_path in extra_paths:
        if os.path.exists(font_path):
            try:
                fm.fontManager.addfont(font_path)
                logging.debug(f"成功加载字体: {font_path}")
            except Exception as e:
                logging.debug(f"加载字体失败 {font_path}: {e}")

    # 查找可用的中文字体
    available = [f.name for f in fm.fontManager.ttflist]
    for name in candidates:
        if name in available:
            plt.rcParams["font.family"] = name
            logging.info(f"使用中文字体: {name}")
            break
    else:
        logging.warning("未找到中文字体，图表中的中文可能显示为方框")
    
    # 解决负号显示问题
    plt.rcParams["axes.unicode_minus"] = False


def bar(ax: plt.Axes, df: pd.DataFrame, x: str, y: str, 
        title: str, ylabel: str, fmt: str = "{:.2f}", 
        palette: Optional[List[str]] = None) -> None:
    """绘制柱状图
    
    Args:
        ax: matplotlib轴对象
        df: 数据框
        x: x轴列名
        y: y轴列名
        title: 图表标题
        ylabel: y轴标签
        fmt: 数值格式化字符串
        palette: 颜色方案
    """
    palette = palette or ["#4ECDC4", "#FF6B6B"]
    
    try:
        bars = sns.barplot(ax=ax, data=df, x=x, y=y, palette=palette, legend=False)
        
        # 在柱子上添加数值标签
        for patch, val in zip(bars.patches, df[y].tolist()):
            height = patch.get_height()
            if height > 0:  # 只为有效值添加标签
                ax.text(
                    patch.get_x() + patch.get_width() / 2,
                    height,
                    fmt.format(val),
                    ha="center",
                    va="bottom",
                    fontsize=10,
                    fontweight="bold",
                )
        
        ax.set_title(title, fontsize=12, fontweight="bold")
        ax.set_ylabel(ylabel)
        ax.set_xlabel("")  # 清除x轴标签
        ax.grid(axis="y", alpha=0.2)
    except Exception as e:
        logging.error(f"绘制图表失败 '{title}': {e}")
        raise


def plot_performance(perf_df: pd.DataFrame, out_dir: str) -> None:
    """绘制性能对比图表
    
    Args:
        perf_df: 性能数据框
        out_dir: 输出目录
    """
    try:
        fig, axes = plt.subplots(2, 2, figsize=(12, 8))
        bar(axes[0, 0], perf_df, "platform", "startup_time_sec", "启动时间对比", "秒", "{:.2f}")
        bar(axes[0, 1], perf_df, "platform", "cpu_percent", "CPU 占用", "%", "{:.1f}%")
        bar(axes[1, 0], perf_df, "platform", "memory_mb", "内存占用", "MB", "{:.1f}")
        bar(axes[1, 1], perf_df, "platform", "disk_mb", "磁盘占用", "MB", "{:.1f}")
        
        fig.suptitle("VM vs Docker 资源对比", fontsize=14, fontweight="bold")
        fig.tight_layout()
        
        output_path = Path(out_dir) / "performance_comparison.png"
        fig.savefig(output_path, dpi=300, bbox_inches='tight')
        plt.close(fig)
        
        logging.info(f"性能图表已保存: {output_path}")
        print(f"✓ 性能图表: {output_path}")
    except Exception as e:
        logging.error(f"生成性能图表失败: {e}")
        raise


def plot_stress(stress_df: pd.DataFrame, out_dir: str) -> None:
    """绘制压测结果对比图表
    
    Args:
        stress_df: 压测数据框
        out_dir: 输出目录
    """
    try:
        fig, axes = plt.subplots(1, 2, figsize=(12, 5))
        bar(axes[0], stress_df, "platform", "qps", "压测 QPS", "每秒请求数", "{:.0f}")
        bar(
            axes[1],
            stress_df,
            "platform",
            "avg_latency_ms",
            "平均延迟",
            "毫秒",
            "{:.1f}ms",
            palette=["#95E1D3", "#F38181"],
        )
        
        fig.suptitle("压测结果对比", fontsize=14, fontweight="bold")
        fig.tight_layout()
        
        output_path = Path(out_dir) / "stress_comparison.png"
        fig.savefig(output_path, dpi=300, bbox_inches='tight')
        plt.close(fig)
        
        logging.info(f"压测图表已保存: {output_path}")
        print(f"✓ 压测图表: {output_path}")
    except Exception as e:
        logging.error(f"生成压测图表失败: {e}")
        raise


def main() -> None:
    """主函数"""
    parser = argparse.ArgumentParser(
        description="生成性能与压测对比图表",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
  python3 visualize_results.py \\
    --performance-csv ./results/performance.csv \\
    --stress-csv ./results/stress.csv \\
    --output-dir ./results/visualization \\
    --verbose
        """
    )
    parser.add_argument("--performance-csv", required=True, help="performance.csv 路径")
    parser.add_argument("--stress-csv", required=True, help="stress.csv 路径")
    parser.add_argument("--output-dir", default="./results/visualization", help="输出目录")
    parser.add_argument("--verbose", "-v", action="store_true", help="显示详细日志")
    args = parser.parse_args()

    # 配置日志
    log_level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(
        level=log_level,
        format='%(asctime)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )

    try:
        # 创建输出目录
        os.makedirs(args.output_dir, exist_ok=True)
        logging.info(f"输出目录: {args.output_dir}")
        
        # 配置图表样式
        ensure_chinese_font()
        sns.set_style("whitegrid")

        # 加载数据
        perf_df = load_csv(
            args.performance_csv, 
            ["platform", "startup_time_sec", "cpu_percent", "memory_mb", "disk_mb"]
        )
        stress_df = load_csv(
            args.stress_csv, 
            ["platform", "qps", "avg_latency_ms", "failed", "transfer_kbps"]
        )

        # 生成图表
        plot_performance(perf_df, args.output_dir)
        plot_stress(stress_df, args.output_dir)
        
        print(f"\n✓ 所有图表已输出到: {args.output_dir}")
    except Exception as e:
        logging.error(f"生成图表失败: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()

