#!/bin/bash
# =============================================================================
# 题目4精简版一键实验脚本
# =============================================================================
# 功能：
#   - 运行 KVM 与 Docker 的 Nginx 部署与性能采集
#   - 执行压力测试
#   - 输出统一的 performance.csv 与 stress.csv
#   - 生成可视化图表到 results/visualization
#
# 使用方法:
#   sudo bash run_experiment.sh
#
# 要求：
#   - 需要root权限（KVM测试需要）
#   - 已安装所有依赖（运行 install_dependencies.sh）
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_DIR="${SCRIPT_DIR}/results"
VIS_DIR="${RESULT_DIR}/visualization"
PERF_CSV="${RESULT_DIR}/performance.csv"
STRESS_CSV="${RESULT_DIR}/stress.csv"
APP_PORT=8080

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

log() { echo -e "${BLUE}[实验]${NC} $*"; }
log_success() { echo -e "${GREEN}[成功]${NC} $*"; }
log_error() { echo -e "${RED}[错误]${NC} $*" >&2; }
log_warning() { echo -e "${YELLOW}[警告]${NC} $*"; }

print_header() {
    echo ""
    echo "======================================"
    echo "$1"
    echo "======================================"
    echo ""
}

validate_environment() {
    local missing_deps=()
    
    # 检查必需的命令
    for cmd in virsh docker python3 ab curl; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "缺少必要工具: ${missing_deps[*]}"
        log "请先运行: bash install_dependencies.sh"
        exit 1
    fi
    
    # 检查权限
    if [[ $EUID -ne 0 ]]; then
        log_warning "建议使用root权限运行（KVM测试需要）"
        log_warning "如果遇到权限问题，请使用: sudo bash $0"
    fi
}

activate_venv() {
    # 可选激活虚拟环境
    if [[ -d "${SCRIPT_DIR}/venv" ]]; then
        if [[ -f "${SCRIPT_DIR}/venv/bin/activate" ]]; then
            # shellcheck disable=SC1091
            source "${SCRIPT_DIR}/venv/bin/activate"
            log "已激活Python虚拟环境"
        fi
    fi
}

prepare_directories() {
    log "准备结果目录..."
    mkdir -p "${RESULT_DIR}" "${VIS_DIR}"
    
    # 备份旧结果（如果存在）
    if [[ -f "${PERF_CSV}" ]]; then
        local backup="${PERF_CSV}.bak.$(date +%Y%m%d_%H%M%S)"
        mv "${PERF_CSV}" "${backup}"
        log "已备份旧结果: ${backup}"
    fi
    
    # 初始化CSV文件
    echo "platform,startup_time_sec,cpu_percent,memory_mb,disk_mb" > "${PERF_CSV}"
}

run_kvm_test() {
    print_header "步骤 1/4: KVM虚拟机测试"
    
    if ! bash "${SCRIPT_DIR}/vm_test.sh" \
        --vm-name "kvm-nginx" \
        --app-port "${APP_PORT}" \
        --output-dir "${RESULT_DIR}/kvm" \
        --perf-csv "${PERF_CSV}"; then
        log_error "KVM测试失败"
        return 1
    fi
    
    log_success "KVM测试完成"
    return 0
}

run_docker_test() {
    print_header "步骤 2/4: Docker容器测试"
    
    if ! bash "${SCRIPT_DIR}/docker_test.sh" \
        --container-name "docker-nginx" \
        --app-port "${APP_PORT}" \
        --output-dir "${RESULT_DIR}/docker" \
        --perf-csv "${PERF_CSV}"; then
        log_error "Docker测试失败"
        return 1
    fi
    
    log_success "Docker测试完成"
    return 0
}

validate_environment
activate_venv
prepare_directories

# 执行测试
run_kvm_test || log_warning "KVM测试失败，继续执行后续步骤"
run_docker_test || log_warning "Docker测试失败，继续执行后续步骤"

run_stress_test() {
    print_header "步骤 3/4: 压力测试"
    
    # 获取VM IP
    local vm_ip
    if [[ -f "${RESULT_DIR}/kvm/vm_ip.txt" ]]; then
        vm_ip=$(cat "${RESULT_DIR}/kvm/vm_ip.txt" 2>/dev/null || echo "localhost")
    else
        log_warning "未找到VM IP，使用localhost"
        vm_ip="localhost"
    fi
    
    local vm_url="http://${vm_ip}:${APP_PORT}"
    local docker_url="http://localhost:${APP_PORT}"
    
    log "压测目标:"
    log "  VM: ${vm_url}"
    log "  Docker: ${docker_url}"
    
    if ! bash "${SCRIPT_DIR}/stress_test.sh" \
        --vm-url "${vm_url}" \
        --docker-url "${docker_url}" \
        --requests 2000 \
        --concurrency 50 \
        --output-dir "${RESULT_DIR}" \
        --output-csv "${STRESS_CSV}"; then
        log_error "压测失败"
        return 1
    fi
    
    log_success "压测完成"
    return 0
}

run_visualization() {
    print_header "步骤 4/4: 生成可视化图表"
    
    # 验证数据文件存在
    if [[ ! -f "${PERF_CSV}" ]] || [[ ! -f "${STRESS_CSV}" ]]; then
        log_error "数据文件不完整，无法生成图表"
        return 1
    fi
    
    if ! python3 "${SCRIPT_DIR}/visualize_results.py" \
        --performance-csv "${PERF_CSV}" \
        --stress-csv "${STRESS_CSV}" \
        --output-dir "${VIS_DIR}"; then
        log_error "可视化生成失败"
        return 1
    fi
    
    log_success "可视化图表已生成"
    return 0
}

# 执行压测和可视化
run_stress_test || log_warning "压测失败，继续生成可视化"
run_visualization || log_warning "可视化生成失败"

# 显示结果摘要
print_header "实验完成！"
log_success "所有步骤已执行完毕"
echo ""
log "结果文件:"
log "  性能数据: ${PERF_CSV}"
log "  压测数据: ${STRESS_CSV}"
log "  图表目录: ${VIS_DIR}"
echo ""

if [[ -d "${VIS_DIR}" ]]; then
    log "生成的图表:"
    for chart in "${VIS_DIR}"/*.png; do
        if [[ -f "$chart" ]]; then
            log "  - $(basename "$chart")"
        fi
    done
fi

echo ""
log "查看结果:"
log "  cat ${PERF_CSV}"
log "  cat ${STRESS_CSV}"
[[ -d "${VIS_DIR}" ]] && log "  查看图表: ${VIS_DIR}/"
echo ""

