#!/bin/bash
# =============================================================================
# 版本检查脚本 - 确认是否使用最新版本
# =============================================================================

set -e

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log() { echo -e "${BLUE}[检查]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $*"; }

echo ""
echo "=================================="
echo "  脚本版本检查"
echo "=================================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

all_ok=true

# 检查 vm_test.sh
log "检查 vm_test.sh..."
if grep -q "VMWare Linux 虚拟机上的 Nginx 部署与性能采集脚本" vm_test.sh; then
    if grep -q "不再使用 KVM 嵌套虚拟化" vm_test.sh; then
        log_success "vm_test.sh 版本正确（新版本）"
    else
        log_warning "vm_test.sh 可能是旧版本"
        all_ok=false
    fi
else
    log_error "vm_test.sh 版本错误（旧版本 KVM）"
    all_ok=false
fi

# 检查输出目录设置
if grep -q 'OUTPUT_DIR="./results/vm"' vm_test.sh; then
    log_success "输出目录设置正确（使用 vm）"
elif grep -q 'OUTPUT_DIR="./results/kvm"' vm_test.sh; then
    log_error "输出目录设置错误（仍使用 kvm）"
    all_ok=false
else
    log_warning "无法确认输出目录设置"
fi

# 检查平台名称
if grep -q 'echo "vm,' vm_test.sh; then
    log_success "平台名称正确（使用 vm）"
elif grep -q 'echo "kvm,' vm_test.sh; then
    log_error "平台名称错误（仍使用 kvm）"
    all_ok=false
else
    log_warning "无法确认平台名称"
fi

echo ""
log "检查 run_experiment.sh..."
if grep -q "虚拟化与容器化性能对比实验" run_experiment.sh; then
    log_success "run_experiment.sh 版本正确"
else
    log_warning "run_experiment.sh 可能是旧版本"
    all_ok=false
fi

# 检查函数名称
if grep -q "run_vm_test()" run_experiment.sh; then
    log_success "函数名称正确（run_vm_test）"
elif grep -q "run_kvm_test()" run_experiment.sh; then
    log_error "函数名称错误（仍使用 run_kvm_test）"
    all_ok=false
fi

echo ""
log "检查 stress_test.sh..."
if grep -q 'run_ab "vm"' stress_test.sh; then
    log_success "stress_test.sh 平台名称正确（使用 vm）"
elif grep -q 'run_ab "kvm"' stress_test.sh; then
    log_error "stress_test.sh 平台名称错误（仍使用 kvm）"
    all_ok=false
fi

echo ""
echo "=================================="
if [ "$all_ok" = true ]; then
    log_success "所有脚本版本正确！"
    echo ""
    log "可以正常运行实验："
    echo "  bash run_experiment.sh"
else
    log_error "检测到旧版本或配置错误！"
    echo ""
    log "可能的原因："
    echo "  1. 脚本文件未更新"
    echo "  2. 使用了缓存的旧版本"
    echo "  3. 从 Windows 复制后行尾符问题"
    echo ""
    log "解决方案："
    echo "  1. 重新下载或拉取最新代码"
    echo "     git pull"
    echo ""
    echo "  2. 如果从 Windows 复制，转换行尾符"
    echo "     sudo apt-get install -y dos2unix"
    echo "     find . -name '*.sh' -exec dos2unix {} \;"
    echo ""
    echo "  3. 确保脚本有执行权限"
    echo "     chmod +x *.sh"
    echo ""
    echo "  4. 清理并重新运行"
    echo "     bash cleanup.sh"
    echo "     bash run_experiment.sh"
fi
echo "=================================="
echo ""

