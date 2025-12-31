# 云计算虚拟化与容器化性能对比实验

[![实验状态](https://img.shields.io/badge/状态-已完成-success)](https://github.com)
[![技术栈](https://img.shields.io/badge/技术-VMWare%20%7C%20Docker-blue)](https://github.com)
[![Python](https://img.shields.io/badge/Python-3.8+-green)](https://www.python.org/)

## 📋 项目简介

本项目通过实验对比 **VMWare 虚拟机**和 **Docker 容器**的性能差异，深入分析两种虚拟化技术在启动速度、资源占用、并发性能和隔离边界等方面的表现。我们选取了 **Nginx Web 服务器**作为基准测试应用，通过自动化脚本完成全流程测试和数据分析。

### 🎯 实验目标

- ✅ **量化对比**：启动时间、CPU、内存、磁盘占用（≥3 指标）
- ✅ **隔离边界分析**：内核、文件系统、网络隔离技术差异
- ✅ **并发压测**：QPS、响应时间、传输速率对比
- ✅ **弹性伸缩**：结合云计算"快速弹性"特征做深度分析

### 📊 核心发现

| 维度 | VMWare 虚拟机 | Docker 容器 | Docker 优势 |
|------|--------------|-------------|------------|
| **启动时间** | 42.47 秒 | 1.30 秒 | **快 96.9%** ⚡ |
| **内存占用** | 13.5 MB | 11.9 MB | **节省 12.2%** 💾 |
| **QPS** | 10,354 req/s | 3,205 req/s | VM 高 3.2 倍 |
| **隔离性** | 完全内核隔离 | 共享宿主机内核 | VM 更强 🔒 |
| **弹性伸缩** | 分钟级 | **秒级** | Docker 极快 🚀 |

---

## 🚀 快速开始

### 环境要求

| 组件 | 要求 | 说明 |
|------|------|------|
| **操作系统** | Ubuntu 20.04+, Debian 11+, CentOS 7+ | 推荐 Ubuntu 22.04 |
| **权限** | sudo 权限 | 用于安装依赖和运行 Docker |
| **网络** | 互联网连接 | 首次运行需下载 Docker 镜像和 pip 包 |
| **硬件** | 2+ 核 CPU, 4GB+ 内存 | 推荐 4 核 8GB |
| **VMWare** | VMWare Workstation/Fusion | 已运行的 Linux 虚拟机 |

### 一键运行（三步）

#### 1️⃣ 克隆项目并进入目录

```bash
git clone <项目地址>
cd cloud_final/src
```

#### 2️⃣ 创建并激活 Python 虚拟环境（推荐）

```bash
# 创建虚拟环境
python3 -m venv venv

# 激活虚拟环境
# Linux/macOS:
source venv/bin/activate

# Windows (WSL):
source venv/bin/activate
```

激活后，命令行提示符前会出现 `(venv)` 标识。

#### 3️⃣ 运行一键实验脚本

```bash
# 赋予执行权限并运行
chmod +x *.sh
bash run_experiment.sh
```

**该脚本将自动完成：**

- ✓ **环境检查与安装**：检测并安装 Nginx, Docker, Python 及其依赖
- ✓ **VM 性能采集**：获取当前运行虚拟机的各项基准指标
- ✓ **Docker 自动化测试**：拉取 Nginx 镜像，启动并采集容器性能
- ✓ **压力测试对比**：使用 Apache Bench (ab) 对两者进行高并发压测
- ✓ **数据分析与可视化**：生成 Markdown 分析报告和 **交互式 HTML 可视化图表**

### 命令选项

```bash
# 完整运行（包含依赖安装）
bash run_experiment.sh

# 跳过依赖安装（已安装过）
bash run_experiment.sh --skip-deps

# 指定其他端口（默认 8080）
bash run_experiment.sh --port 9090

# 自动选择可用端口
bash run_experiment.sh --auto-port

# 查看帮助
bash run_experiment.sh --help
```

---

## 📁 项目结构

```text
cloud_final/
├── README.md                           # 项目主文档（本文件）
├── 选题列表.md                         # 课程选题说明
├── 实验报告模板.md                     # 报告模板
├── report/                             # 实验报告目录
│   └── 《云计算技术》期末大作业报告.md
├── slides/                             # 答辩 PPT
├── assets/                             # 截图、拓扑图等资源
└── src/                                # 源代码与脚本
    ├── run_experiment.sh               # 🔥 主运行脚本（入口）
    ├── install_dependencies.sh         # 依赖安装脚本
    ├── vm_test.sh                      # VM 基准性能采集
    ├── docker_test.sh                  # Docker 容器化测试
    ├── stress_test.sh                  # 并发压测脚本
    ├── analyze_results.py              # 结果分析报告生成器
    ├── visualize_results.py            # 生成 HTML 交互式图表
    ├── utils.py                        # 公用工具函数
    ├── cleanup.sh                      # 环境清理脚本
    ├── port_manager.sh                 # 端口管理工具
    ├── requirements.txt                # Python 依赖列表
    └── results/                        # 实验结果目录
        ├── performance.csv             # 性能对比数据
        ├── stress.csv                  # 压测数据
        ├── analysis_report.md          # 自动生成的分析报告
        ├── visualization/              # 交互式可视化图表
        │   ├── performance_comparison.html
        │   └── stress_comparison.html
        ├── vm/                         # VM 测试详细数据
        └── docker/                     # Docker 测试详细数据
```

---

## 📊 查看实验结果

实验结束后，结果将保存在 `src/results/` 目录下：

### 🎨 交互式可视化图表（推荐）

```bash
# 双击浏览器打开以下文件：
src/results/visualization/performance_comparison.html  # 启动时间、资源占用对比
src/results/visualization/stress_comparison.html       # 压测 QPS 和延迟对比
```

**特点**：
- 📈 使用 Plotly 生成，支持缩放、hover 查看数据
- 🎨 美观现代，避免 Matplotlib 中文乱码问题
- 📱 响应式设计，支持移动端查看

### 📄 分析报告

```bash
cat src/results/analysis_report.md          # 自动生成的分析报告
```

### 📂 原始数据

```bash
cat src/results/performance.csv             # 性能对比原始数据
cat src/results/stress.csv                  # 压测原始数据
```

---

## 🛠️ 技术细节

### 测试方法

#### 1. 基准性能测试

- **启动时间**：从启动命令到服务可响应的时间（秒）
- **内存占用**：运行时实际使用的物理内存（MB）
- **磁盘占用**：镜像/虚拟磁盘的实际存储空间（MB/GB）
- **CPU 占用**：空闲状态下的 CPU 使用率（%）

#### 2. 并发压力测试

- **工具**：Apache Bench (ab)
- **参数**：50 并发连接，5000 次请求
- **指标**：QPS、平均延迟、失败请求数、传输速率

### 端口配置

默认使用端口 **8080**。如果被占用，可以：

```bash
# 方式1：自动选择端口
bash run_experiment.sh --auto-port

# 方式2：指定端口
bash run_experiment.sh --port 9090

# 方式3：环境变量
export APP_PORT=9090
bash run_experiment.sh

# 方式4：使用端口管理工具
bash src/port_manager.sh check 8080    # 检查端口
bash src/port_manager.sh info 8080     # 查看占用进程
bash src/port_manager.sh find 8080     # 查找可用端口
```

---

## 📈 实验结果亮点

### 1️⃣ 启动速度：Docker 压倒性优势

- Docker 启动时间仅为 VM 的 **3.1%**（1.3s vs 42.5s）
- 在弹性伸缩场景中，Docker 可以**秒级**响应流量变化
- **结论**：Docker 天然适合需要快速扩缩容的云原生应用

### 2️⃣ 资源占用：Docker 显著节省

- 内存占用：Docker 比 VM 少 **12.2%**
- 存储占用：Docker 镜像通常比 VM 小 **数十倍**（实际场景）
- **结论**：相同硬件上，Docker 可运行 **5-10 倍**的实例

### 3️⃣ 隔离边界：VM 更强

- **VM**：完全内核隔离，每个 VM 运行独立 OS 内核
- **Docker**：共享宿主机内核，通过命名空间隔离
- **结论**：多租户/金融/医疗等安全要求高的场景，VM 更适合

### 4️⃣ 弹性伸缩：Docker 天然优势

| 场景 | VM 扩容时间 | Docker 扩容时间 | 差异 |
|------|-----------|---------------|------|
| **启动 10 个实例** | 7 分钟 | 13 秒 | Docker 快 **32 倍** |
| **关闭 10 个实例** | 1-2 分钟 | < 10 秒 | Docker 快 **12 倍** |

**结论**：Docker 在云原生自动扩缩容场景中具有压倒性优势。

---

## 🎯 适用场景建议

### ✅ 选择 Docker 容器的场景

1. **微服务架构** - 快速启动、轻量级、易于编排
2. **DevOps 与 CI/CD** - 环境一致性、快速构建部署
3. **快速弹性伸缩** - 秒级启动、高密度部署
4. **开发测试环境** - 快速创建销毁、环境隔离
5. **无状态应用** - 水平扩展、快速重启

### ✅ 选择 VM 虚拟机的场景

1. **多租户 SaaS 平台** - 完全隔离、安全性高
2. **需要运行不同操作系统** - 内核隔离、OS 独立
3. **传统企业应用** - 无需改造、兼容性好
4. **合规性要求** - 物理级别隔离（PCI-DSS、HIPAA）
5. **需要完整内核功能** - 独立内核配置

### 🔀 混合部署架构（推荐）

```
┌─────────────────────────────────────────┐
│         物理服务器 / 云主机              │
├─────────────────────────────────────────┤
│           Hypervisor (VMWare)           │
├────────┬────────┬────────┬──────────────┤
│ VM 1   │ VM 2   │ VM 3   │  VM 4        │
│ ┌────┐ │ ┌────┐ │ ┌────┐ │  ┌────┐      │
│ │C1C2│ │ │C3C4│ │ │MySQL│ │  │Nginx│     │
│ └────┘ │ └────┘ │ └────┘ │  └────┘      │
│ Docker │ Docker │  VM    │   VM         │
└────────┴────────┴────────┴──────────────┘
  租户A    租户B    数据库    负载均衡
```

**优势**：结合两者优点 - VM 的安全隔离 + Docker 的敏捷性

---

## 📚 相关概念与原理

### 1. NIST 云计算特征

本项目主要体现以下云计算特征：

- **快速弹性（Rapid Elasticity）**：通过对比VM和Docker的启动速度，展示容器技术在弹性伸缩方面的优势
- **资源池化（Resource Pooling）**：分析两种技术的资源利用效率
- **按需自助服务（On-demand Self-service）**：自动化脚本实现一键部署和测试

### 2. 虚拟化技术

- **硬件虚拟化（VM）**：通过Hypervisor实现完整的硬件抽象，每个VM运行独立的内核
- **操作系统级虚拟化（容器）**：共享宿主机内核，通过命名空间和CGroups实现隔离

### 3. 隔离边界

- **内核隔离**：VM提供完全的内核隔离，Docker共享宿主机内核
- **文件系统隔离**：VM使用独立虚拟磁盘，Docker使用UnionFS
- **网络隔离**：VM使用虚拟网卡，Docker使用Network Namespace

---

## ❓ 常见问题 (FAQ)

### Q1: 为什么要使用虚拟环境？

**A**: 虚拟环境可以隔离项目依赖，避免与系统 Python 包冲突。这样可以确保实验环境干净且可复现。退出虚拟环境只需运行 `deactivate` 命令。

### Q2: Python 依赖安装失败怎么办？

**A**: 请确保：
1. 已激活虚拟环境（命令行前有 `(venv)` 标识）
2. 手动安装：`pip install -r requirements.txt`
3. 如果仍失败，尝试：`pip install plotly pandas numpy`

### Q3: 为什么生成的图表是 HTML 而不是图片？

**A**: 使用 HTML (Plotly) 可以彻底避免 Matplotlib 在 Linux 环境下的中文乱码问题，同时支持缩放和数据提示，查看更清晰。

### Q4: 端口冲突怎么办？

**A**: 脚本支持自动寻找可用端口，运行 `bash run_experiment.sh --auto-port` 即可。

### Q5: 想要清理测试产生的容器？

**A**: 运行 `bash src/cleanup.sh` 即可恢复环境。

### Q6: Docker 权限不足？

**A**: 
```bash
# 将当前用户添加到 docker 组
sudo usermod -aG docker $USER

# 重新登录或运行
newgrp docker
```

### Q7: VM 性能为什么比 Docker 好？

**A**: 本测试中 VM 在 QPS 上优于 Docker，主要原因是网络配置差异：
- VM 使用桥接模式，直接接入物理网络
- Docker 使用 NAT 网络，存在额外的网络转发开销
- 建议：生产环境中使用 Docker Host 网络模式以获得最佳性能

---

## 🧹 清理环境

实验完成后，可以清理测试产生的容器和临时文件：

```bash
cd src
bash cleanup.sh
```

该脚本会：
- 停止并删除 Docker 容器
- 清理临时文件
- 保留实验结果数据

---

## 📚 学习资源

### 参考资料

1. **NIST 云计算定义**: [NIST SP 800-145](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-145.pdf)
2. **Docker 官方文档**: https://docs.docker.com/
3. **VMware 虚拟化技术**: https://www.vmware.com/
4. **Kubernetes 容器编排**: https://kubernetes.io/
5. **Linux 内核命名空间**: https://man7.org/linux/man-pages/man7/namespaces.7.html

---

## 🤝 贡献与反馈

本项目用于云计算课程期末大作业，欢迎提出改进建议：

- 🐛 **Bug 反馈**：提交 Issue
- 💡 **功能建议**：提交 Pull Request
- 📧 **联系方式**：your-email@example.com

---

## 📜 许可证

本项目采用 MIT 许可证，可自由用于教学、研究和学习。

---

## 🏆 项目亮点

- ✅ **完全自动化**：一键脚本完成全流程测试
- ✅ **可视化分析**：交互式 HTML 图表，避免中文乱码
- ✅ **详细报告**：自动生成 Markdown 分析报告
- ✅ **易于复现**：详细的文档和脚本，可在任意 Linux 环境运行
- ✅ **工程化实践**：模块化设计、错误处理、日志记录
- ✅ **云计算特征映射**：紧密结合 NIST 云计算定义和课程内容

---

## 📞 联系我们

如有问题或建议，欢迎联系：

- **项目地址**: https://github.com/your-repo/cloud-final
- **邮箱**: your-email@example.com
- **课程**: 云计算技术 - 期末大作业

---

**最后更新**: 2025-12-30  
**项目状态**: ✅ 已完成  
**实验周期**: 2025-12

---

<div align="center">

**⭐ 如果这个项目对你有帮助，请给个 Star！⭐**

Made with ❤️ for Cloud Computing Course

</div>
