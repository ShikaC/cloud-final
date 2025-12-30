#!/bin/bash
# =============================================================================
# 虚拟化与容器化性能对比实验 - 一键运行脚本
# =============================================================================
# 功能：
#   - 系统环境检查
#   - 运行 VM 与 Docker 的 Nginx 部署与性能采集
#   - 执行压力测试
#   - 输出统一的 performance.csv 与 stress.csv
#   - 生成可视化图表到 results/visualization
#   - 显示详细的结果报告
#
# 使用方法:
#   bash run_experiment.sh              # 完整流程（包含依赖安装）
#   bash run_experiment.sh --skip-deps  # 跳过依赖安装
#
# 要求：
#   - Ubuntu/Debian/CentOS 等 Linux 系统
#   - 需要 sudo 权限
#   - 需要网络连接（首次运行）
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULT_DIR="${SCRIPT_DIR}/results"
VIS_DIR="${RESULT_DIR}/visualization"
PERF_CSV="${RESULT_DIR}/performance.csv"
STRESS_CSV="${RESULT_DIR}/stress.csv"
APP_PORT=${APP_PORT:-8080}
SKIP_DEPS=false
AUTO_PORT=false

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

log() { echo -e "${BLUE}[实验]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*" >&2; }
log_warning() { echo -e "${YELLOW}[!]${NC} $*"; }
log_info() { echo -e "${CYAN}[i]${NC} $*"; }

print_banner() {
    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║                                                              ║${NC}"
    echo -e "${BOLD}${CYAN}║     云计算虚拟化与容器化性能对比实验                          ║${NC}"
    echo -e "${BOLD}${CYAN}║     VM vs Docker 性能测试                                    ║${NC}"
    echo -e "${BOLD}${CYAN}║                                                              ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

check_and_fix_port() {
    log "检查端口 ${APP_PORT}..."
    
    local port_in_use=false
    if command -v ss >/dev/null 2>&1; then
        ss -tuln 2>/dev/null | grep -q ":${APP_PORT} " && port_in_use=true
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tuln 2>/dev/null | grep -q ":${APP_PORT} " && port_in_use=true
    fi
    
    if [[ "$port_in_use" == "true" ]]; then
        log_warning "端口 ${APP_PORT} 已被占用"
        
        if [[ "$AUTO_PORT" == "true" ]]; then
            for ((i=0; i<50; i++)); do
                local test_port=$((APP_PORT + i))
                if ! (ss -tuln 2>/dev/null | grep -q ":${test_port} " || netstat -tuln 2>/dev/null | grep -q ":${test_port} "); then
                    APP_PORT=$test_port
                    log_success "自动选择端口: ${APP_PORT}"
                    return
                fi
            done
            log_error "无法找到可用端口"
            exit 1
        else
            log_warning "请选择操作："
            echo "  1. 使用其他端口"
            echo "  2. 退出"
            read -p "请选择 [1-2]: " -n 1 -r choice
            echo ""
            
            case $choice in
                1)
                    read -p "请输入新端口号: " new_port
                    if [[ "$new_port" =~ ^[0-9]+$ ]] && [[ $new_port -ge 1024 ]] && [[ $new_port -le 65535 ]]; then
                        APP_PORT=$new_port
                        check_and_fix_port
                    else
                        log_error "无效的端口号"
                        exit 1
                    fi
                    ;;
                2)
                    exit 0
                    ;;
                *)
                    log_error "无效的选择"
                    exit 1
                    ;;
            esac
        fi
    else
        log_success "端口 ${APP_PORT} 可用"
    fi
}

install_dependencies() {
    log "安装依赖..."
    if bash "${SCRIPT_DIR}/install_dependencies.sh"; then
        log_success "依赖安装完成"
    else
        log_error "依赖安装失败"
        exit 1
    fi
}

activate_venv() {
    if [[ -d "${SCRIPT_DIR}/venv" && -f "${SCRIPT_DIR}/venv/bin/activate" ]]; then
        source "${SCRIPT_DIR}/venv/bin/activate"
        log "已激活Python虚拟环境"
    fi
}

prepare_directories() {
    log "准备结果目录..."
    mkdir -p "${RESULT_DIR}" "${VIS_DIR}"
    
    if [[ -f "${PERF_CSV}" ]]; then
        local backup="${PERF_CSV}.bak.$(date +%Y%m%d_%H%M%S)"
        mv "${PERF_CSV}" "${backup}"
        log "已备份旧结果"
    fi
    
    echo "platform,startup_time_sec,cpu_percent,memory_mb,disk_mb" > "${PERF_CSV}"
}

run_vm_test() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━ 步骤 1/4: VM 虚拟机测试 ━━━━${NC}"
    echo ""
    
    if ! bash "${SCRIPT_DIR}/vm_test.sh" \
        --vm-name "vmware-nginx" \
        --app-port "${APP_PORT}" \
        --output-dir "${RESULT_DIR}/vm" \
        --perf-csv "${PERF_CSV}"; then
        log_error "VM测试失败"
        return 1
    fi
    
    log_success "VM测试完成"
    return 0
}

run_docker_test() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━ 步骤 2/4: Docker容器测试 ━━━━${NC}"
    echo ""
    
    if ! docker info >/dev/null 2>&1; then
        log_warning "Docker需要sudo权限"
        sudo bash "${SCRIPT_DIR}/docker_test.sh" \
            --container-name "docker-nginx" \
            --app-port "${APP_PORT}" \
            --output-dir "${RESULT_DIR}/docker" \
            --perf-csv "${PERF_CSV}" || return 1
    else
        bash "${SCRIPT_DIR}/docker_test.sh" \
            --container-name "docker-nginx" \
            --app-port "${APP_PORT}" \
            --output-dir "${RESULT_DIR}/docker" \
            --perf-csv "${PERF_CSV}" || return 1
    fi
    
    log_success "Docker测试完成"
    return 0
}

run_vm_stress() {
    local vm_ip="localhost"
    [[ -f "${RESULT_DIR}/vm/vm_ip.txt" ]] && vm_ip=$(cat "${RESULT_DIR}/vm/vm_ip.txt")
    local vm_url="http://${vm_ip}:${APP_PORT}"
    
    log "VM压测目标: ${vm_url}"
    
    # 初始化stress.csv（只在第一次调用时）
    if [[ ! -f "${STRESS_CSV}" ]]; then
        echo "platform,qps,avg_latency_ms,failed,transfer_kbps" > "${STRESS_CSV}"
    fi
    
    # 预热
    log "预热VM..."
    ab -n 100 -c 10 -q "${vm_url}/" > /dev/null 2>&1 || true
    sleep 1
    
    # 正式压测
    log "正式压测VM..."
    local outfile="${RESULT_DIR}/stress_vm.txt"
    if ab -n 2000 -c 50 -q "${vm_url}/" > "${outfile}" 2>&1; then
        local qps=$(grep "Requests per second" "${outfile}" 2>/dev/null | awk '{print $4}' | head -1)
        local avg=$(grep "Time per request" "${outfile}" 2>/dev/null | head -1 | awk '{print $4}' | head -1)
        local failed=$(grep "Failed requests" "${outfile}" 2>/dev/null | awk '{print $3}' | head -1)
        local transfer=$(grep "Transfer rate" "${outfile}" 2>/dev/null | awk '{print $3}' | head -1)
        echo "vm,${qps:-0},${avg:-0},${failed:-0},${transfer:-0}" >> "${STRESS_CSV}"
        log_success "VM压测完成: QPS=${qps:-0}, 延迟=${avg:-0}ms"
    else
        echo "vm,0,0,0,0" >> "${STRESS_CSV}"
        log_error "VM压测失败"
    fi
}

run_docker_stress() {
    local docker_url="http://localhost:${APP_PORT}"
    
    log "Docker压测目标: ${docker_url}"
    
    # 预热
    log "预热Docker..."
    ab -n 100 -c 10 -q "${docker_url}/" > /dev/null 2>&1 || true
    sleep 1
    
    # 正式压测
    log "正式压测Docker..."
    local outfile="${RESULT_DIR}/stress_docker.txt"
    if ab -n 2000 -c 50 -q "${docker_url}/" > "${outfile}" 2>&1; then
        local qps=$(grep "Requests per second" "${outfile}" 2>/dev/null | awk '{print $4}' | head -1)
        local avg=$(grep "Time per request" "${outfile}" 2>/dev/null | head -1 | awk '{print $4}' | head -1)
        local failed=$(grep "Failed requests" "${outfile}" 2>/dev/null | awk '{print $3}' | head -1)
        local transfer=$(grep "Transfer rate" "${outfile}" 2>/dev/null | awk '{print $3}' | head -1)
        echo "docker,${qps:-0},${avg:-0},${failed:-0},${transfer:-0}" >> "${STRESS_CSV}"
        log_success "Docker压测完成: QPS=${qps:-0}, 延迟=${avg:-0}ms"
    else
        echo "docker,0,0,0,0" >> "${STRESS_CSV}"
        log_error "Docker压测失败"
    fi
}

cleanup_vm() {
    log "清理VM Nginx..."
    sudo pkill -9 nginx 2>/dev/null || true
    sudo rm -f /tmp/nginx_test_*.pid 2>/dev/null || true
    sleep 1
}

cleanup_docker() {
    log "清理Docker容器..."
    docker rm -f docker-nginx 2>/dev/null || true
    sleep 1
}

run_visualization() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━ 步骤 4/4: 生成可视化图表 ━━━━${NC}"
    echo ""
    
    if [[ ! -f "${PERF_CSV}" ]] || [[ ! -f "${STRESS_CSV}" ]]; then
        log_error "数据文件不完整"
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

show_results() {
    echo ""
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${GREEN}  实验完成！${NC}"
    echo -e "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    
    log_info "结果文件："
    echo "  ✓ 性能数据: ${PERF_CSV}"
    echo "  ✓ 压测数据: ${STRESS_CSV}"
    echo "  ✓ 图表目录: ${VIS_DIR}/"
    echo ""
    
    if [[ -f "${PERF_CSV}" ]]; then
        log_info "性能对比："
        column -t -s ',' "${PERF_CSV}" 2>/dev/null | sed 's/^/  /' || cat "${PERF_CSV}" | sed 's/^/  /'
        echo ""
    fi
    
    log_info "下一步："
    echo "  • 查看图表: cd ${VIS_DIR}"
    echo "  • 清理环境: bash ${SCRIPT_DIR}/cleanup.sh"
    echo "  • 再次运行: bash $0"
    echo ""
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-deps) SKIP_DEPS=true; shift ;;
            --port) APP_PORT="$2"; shift 2 ;;
            --auto-port) AUTO_PORT=true; shift ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "未知参数: $1"; show_help; exit 1 ;;
        esac
    done
}

show_help() {
    cat <<EOF
使用方法: bash run_experiment.sh [选项]

选项:
  --skip-deps      跳过依赖安装
  --port <端口>     指定使用的端口号（默认: 8080）
  --auto-port      自动查找可用端口
  -h, --help       显示此帮助信息

示例:
  bash run_experiment.sh                    # 完整运行
  bash run_experiment.sh --skip-deps        # 跳过依赖安装
  bash run_experiment.sh --port 9090        # 使用端口9090
  bash run_experiment.sh --auto-port        # 自动选择端口
  APP_PORT=9090 bash run_experiment.sh      # 通过环境变量设置端口
EOF
}

parse_args "$@"

print_banner

if [ "$SKIP_DEPS" = false ]; then
    install_dependencies
else
    log_info "跳过依赖安装"
fi

check_and_fix_port
activate_venv
prepare_directories

# ============================================================================
# 【测试流程】
# 为确保公平性，每个平台单独完成"性能测试+压测"后再清理
# ============================================================================

echo ""
echo -e "${BOLD}${BLUE}━━━━ 阶段 1/3: VM 虚拟机测试 ━━━━${NC}"
echo ""

# VM性能测试
run_vm_test || log_warning "VM测试失败"

# VM压测（nginx仍在运行）
log "开始VM压测..."
run_vm_stress || log_warning "VM压测失败"

# 清理VM nginx，释放端口
cleanup_vm

# 等待系统稳定
log "等待系统稳定..."
sleep 2

echo ""
echo -e "${BOLD}${BLUE}━━━━ 阶段 2/3: Docker 容器测试 ━━━━${NC}"
echo ""

# Docker性能测试
run_docker_test || log_warning "Docker测试失败"

# Docker压测（容器仍在运行）
log "开始Docker压测..."
run_docker_stress || log_warning "Docker压测失败"

# 清理Docker容器
cleanup_docker

echo ""
echo -e "${BOLD}${BLUE}━━━━ 阶段 3/3: 生成可视化图表 ━━━━${NC}"
echo ""

run_visualization || log_warning "可视化失败"

show_results
