#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""实验结果分析报告生成器（精简版）"""

import argparse
import pandas as pd
from datetime import datetime
from pathlib import Path
import sys

from utils import setup_logging, ensure_dir_exists


def generate_report(perf_csv: str, stress_csv: str, output_file: str, charts_dir: str = None):
    """生成分析报告"""
    # 读取数据
    perf_df = pd.read_csv(perf_csv)
    stress_df = pd.read_csv(stress_csv)
    
    vm_perf = perf_df[perf_df['platform'] == 'vm'].iloc[0]
    docker_perf = perf_df[perf_df['platform'] == 'docker'].iloc[0]
    vm_stress = stress_df[stress_df['platform'] == 'vm'].iloc[0]
    docker_stress = stress_df[stress_df['platform'] == 'docker'].iloc[0]
    
    report = []
    
    # 标题
    report.append("# VM vs Docker 性能对比分析报告\n\n")
    report.append(f"**生成时间**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")
    report.append("---\n\n")
    
    # 1. 执行摘要
    report.append("## 1. 执行摘要\n\n")
    report.append("本报告对比了VM（VMWare虚拟化）和Docker容器在部署相同应用（Nginx）时的性能表现。\n\n")
    
    startup_speedup = vm_perf['startup_time_sec'] / docker_perf['startup_time_sec'] if docker_perf['startup_time_sec'] > 0 else 0
    qps_leader = "VM" if vm_stress['qps'] > docker_stress['qps'] else "Docker"
    
    report.append("### 关键发现\n\n")
    if startup_speedup > 1:
        report.append(f"- **启动速度**: Docker比VM快 **{startup_speedup:.1f}倍**（{docker_perf['startup_time_sec']:.2f}秒 vs {vm_perf['startup_time_sec']:.2f}秒）\n")
    report.append(f"- **并发性能**: {qps_leader} 的QPS更高（{max(vm_stress['qps'], docker_stress['qps']):,.0f}）\n")
    report.append(f"- **隔离性**: VM提供内核级隔离，Docker提供进程级隔离\n")
    report.append(f"- **推荐场景**: Docker适合微服务和快速弹性伸缩，VM适合强隔离和传统应用\n\n")
    
    # 图表链接
    if charts_dir:
        report.append("### 可视化图表\n\n")
        report.append("交互式图表请查看：\n\n")
        report.append(f"- [性能对比图](./visualization/performance_comparison.html)\n")
        report.append(f"- [压测对比图](./visualization/stress_comparison.html)\n\n")
    
    # 2. 性能指标对比
    report.append("## 2. 性能指标对比\n\n")
    
    report.append("### 2.1 启动时间\n\n")
    report.append("| 平台 | 启动时间 |\n")
    report.append("|------|---------|\n")
    report.append(f"| VM | {vm_perf['startup_time_sec']:.2f} 秒 |\n")
    report.append(f"| Docker | {docker_perf['startup_time_sec']:.2f} 秒 |\n\n")
    
    report.append("### 2.2 资源占用\n\n")
    report.append("| 指标 | VM | Docker |\n")
    report.append("|------|----|--------|\n")
    report.append(f"| CPU占用 | {vm_perf['cpu_percent']:.2f}% | {docker_perf['cpu_percent']:.2f}% |\n")
    report.append(f"| 内存占用 | {vm_perf['memory_mb']:.1f} MB | {docker_perf['memory_mb']:.1f} MB |\n")
    report.append(f"| 磁盘占用 | {vm_perf['disk_mb']:.1f} MB | {docker_perf['disk_mb']:.1f} MB |\n\n")
    
    report.append("### 2.3 并发性能\n\n")
    report.append("| 指标 | VM | Docker |\n")
    report.append("|------|----|--------|\n")
    report.append(f"| QPS | {vm_stress['qps']:,.0f} | {docker_stress['qps']:,.0f} |\n")
    report.append(f"| 平均延迟 | {vm_stress['avg_latency_ms']:.2f} ms | {docker_stress['avg_latency_ms']:.2f} ms |\n")
    report.append(f"| 传输速率 | {vm_stress['transfer_kbps']:,.2f} KB/s | {docker_stress['transfer_kbps']:,.2f} KB/s |\n\n")
    
    # 3. 隔离边界分析
    report.append("## 3. 隔离边界技术差异\n\n")
    
    report.append("| 维度 | VM | Docker |\n")
    report.append("|------|----|--------|\n")
    report.append("| 内核隔离 | 完全隔离（独立内核） | 共享宿主机内核 |\n")
    report.append("| 文件系统 | 独立虚拟磁盘 | UnionFS分层文件系统 |\n")
    report.append("| 网络隔离 | 虚拟网卡 | Network Namespace |\n")
    report.append("| 安全级别 | 高（内核级） | 中（进程级） |\n\n")
    
    # 4. 适用场景
    report.append("## 4. 适用场景建议\n\n")
    
    report.append("### 选择Docker的场景\n\n")
    report.append("- 微服务架构和云原生应用\n")
    report.append("- 需要快速部署和弹性伸缩\n")
    report.append("- DevOps和CI/CD流水线\n")
    report.append("- 资源受限，需要高密度部署\n\n")
    
    report.append("### 选择VM的场景\n\n")
    report.append("- 多租户环境，需要强隔离\n")
    report.append("- 需要运行不同操作系统\n")
    report.append("- 传统应用迁移\n")
    report.append("- 安全合规性要求极高\n\n")
    
    # 5. 结论
    report.append("## 5. 结论\n\n")
    report.append("通过本次实验对比：\n\n")
    report.append("1. **性能方面**: Docker在启动速度方面明显优于VM\n")
    report.append("2. **隔离性方面**: VM提供更强的内核级隔离\n")
    report.append("3. **技术选择**: 应根据具体业务需求、安全要求来选择合适的技术\n\n")
    
    report.append("---\n\n")
    report.append(f"*本报告由自动化脚本生成 | 生成时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}*\n")
    
    # 写入文件
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(''.join(report))
    
    print(f"[OK] 分析报告已生成: {output_file}")


def main():
    parser = argparse.ArgumentParser(description="生成分析报告")
    parser.add_argument("--performance-csv", required=True, help="performance.csv路径")
    parser.add_argument("--stress-csv", required=True, help="stress.csv路径")
    parser.add_argument("--output-file", required=True, help="输出报告文件路径")
    parser.add_argument("--charts-dir", help="图表目录路径（可选）")
    parser.add_argument("--verbose", "-v", action="store_true", help="详细日志")
    
    args = parser.parse_args()
    setup_logging(args.verbose)
    
    try:
        generate_report(args.performance_csv, args.stress_csv, args.output_file, args.charts_dir)
    except Exception as e:
        print(f"[ERROR] 生成报告时出错: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()

