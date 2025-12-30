#!/bin/bash
# =============================================================================
# KVM 问题快速修复脚本
# =============================================================================
# 用途：自动修复 KVM 相关错误
# =============================================================================

set -e

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log() { echo -e "${BLUE}[修复]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $*"; }

echo ""
echo "=================================="
echo "  KVM 问题自动修复"
echo "=================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log "开始自动修复..."
echo ""

# 步骤 1: 转换行尾符
log "步骤 1/5: 转换行尾符..."
if command -v dos2unix >/dev/null 2>&1; then
    find . -name "*.sh" -exec dos2unix {} \; 2>/dev/null || true
    log_success "行尾符已转换"
else
    log_warning "dos2unix 未安装，跳过此步骤"
    log "如需安装: sudo apt-get install -y dos2unix"
fi
echo ""

# 步骤 2: 设置执行权限
log "步骤 2/5: 设置执行权限..."
chmod +x *.sh 2>/dev/null || true
log_success "执行权限已设置"
echo ""

# 步骤 3: 迁移旧目录
log "步骤 3/5: 迁移旧的 kvm 目录..."
if [ -d "results/kvm" ]; then
    if [ -d "results/vm" ]; then
        log_warning "results/vm 已存在，备份 kvm 目录..."
        mv results/kvm results/kvm.bak.$(date +%Y%m%d_%H%M%S) 2>/dev/null || true
    else
        mv results/kvm results/vm 2>/dev/null || true
        log_success "目录已迁移: kvm → vm"
    fi
else
    log "未发现旧的 kvm 目录"
fi
echo ""

# 步骤 4: 清除 bash 缓存
log "步骤 4/5: 清除 bash 缓存..."
hash -r 2>/dev/null || true
log_success "缓存已清除"
echo ""

# 步骤 5: 验证版本
log "步骤 5/5: 验证脚本版本..."
if [ -f "check_version.sh" ]; then
    bash check_version.sh
else
    log_warning "check_version.sh 不存在，跳过验证"
fi

echo ""
echo "=================================="
log_success "修复完成！"
echo "=================================="
echo ""

log "下一步："
echo "  1. 运行实验: bash run_experiment.sh"
echo "  2. 如果仍有问题，请查看: 修改总结.md"
echo ""

