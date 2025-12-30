#!/bin/bash
# =============================================================================
# 清理脚本 - 清理实验创建的VM和Docker容器
# =============================================================================
# 功能说明：
#   清理实验过程中创建的VM、Docker容器和相关资源
#
# 使用方法：
#   sudo bash cleanup.sh [--all]
#   --all: 同时清理结果目录
# =============================================================================

set -e

# 默认参数
CLEAN_ALL=false
VM_NAME="test-vm-nginx"
DOCKER_CONTAINER_NAME="test-docker-nginx"

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            CLEAN_ALL=true
            shift
            ;;
        --vm-name)
            VM_NAME="$2"
            shift 2
            ;;
        --container-name)
            DOCKER_CONTAINER_NAME="$2"
            shift 2
            ;;
        *)
            echo "未知参数: $1"
            exit 1
            ;;
    esac
done

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[清理]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

# 清理VM测试（Nginx进程）
cleanup_vm() {
    log_info "清理VM测试Nginx进程"
    
    # 查找并停止测试Nginx进程
    local nginx_pids=$(ps aux | grep "nginx.*-c /tmp/nginx-" | grep -v grep | awk '{print $2}')
    
    if [ -n "$nginx_pids" ]; then
        log_info "停止Nginx测试进程..."
        for pid in $nginx_pids; do
            if kill -0 "$pid" 2>/dev/null; then
                sudo kill "$pid" 2>/dev/null || true
                log_info "已停止进程: $pid"
            fi
        done
        sleep 1
        
        # 强制停止未响应的进程
        nginx_pids=$(ps aux | grep "nginx.*-c /tmp/nginx-" | grep -v grep | awk '{print $2}')
        if [ -n "$nginx_pids" ]; then
            for pid in $nginx_pids; do
                if kill -0 "$pid" 2>/dev/null; then
                    sudo kill -9 "$pid" 2>/dev/null || true
                    log_info "强制停止进程: $pid"
                fi
            done
        fi
        
        log_success "Nginx测试进程已清理"
    else
        log_info "未找到运行中的Nginx测试进程"
    fi
    
    # 清理临时Nginx配置和文件
    log_info "清理临时文件..."
    sudo rm -f /tmp/nginx-*.conf 2>/dev/null || true
    sudo rm -f /tmp/nginx-*.html 2>/dev/null || true
    sudo rm -f /tmp/nginx-*.log 2>/dev/null || true
    sudo rm -f /tmp/nginx-*.pid 2>/dev/null || true
    log_success "临时文件已清理"
    
    # 迁移旧的 kvm 目录到 vm（如果存在）
    if [ -d "results/kvm" ] && [ ! -d "results/vm" ]; then
        log_info "检测到旧版 kvm 目录，重命名为 vm..."
        mv results/kvm results/vm 2>/dev/null || true
        log_success "目录已更新"
    fi
}

# 清理Docker容器
cleanup_docker() {
    log_info "清理Docker容器: ${DOCKER_CONTAINER_NAME}"
    
    # 检查docker命令是否可用
    if ! command -v docker >/dev/null 2>&1; then
        log_warning "Docker未安装，跳过容器清理"
        return 0
    fi
    
    # 检查容器是否存在
    if docker ps -a 2>/dev/null | grep -q "${DOCKER_CONTAINER_NAME}"; then
        # 停止容器
        if docker ps 2>/dev/null | grep -q "${DOCKER_CONTAINER_NAME}"; then
            log_info "停止容器..."
            if docker stop "${DOCKER_CONTAINER_NAME}" 2>/dev/null; then
                log_success "容器已停止"
            else
                log_warning "停止容器失败"
            fi
        fi
        
        # 删除容器
        log_info "删除容器..."
        if docker rm "${DOCKER_CONTAINER_NAME}" 2>/dev/null; then
            log_success "容器已删除"
        else
            log_warning "删除容器失败"
        fi
        
        log_success "Docker容器已清理"
    else
        log_info "Docker容器不存在，跳过"
    fi
}

# 清理结果目录
cleanup_results() {
    if [ "$CLEAN_ALL" = true ]; then
        log_info "清理结果目录..."
        if [ -d "results" ]; then
            # 显示结果目录大小
            local size=$(du -sh results 2>/dev/null | awk '{print $1}')
            log_info "结果目录大小: ${size:-未知}"
            
            # 非交互模式下默认不删除
            if [[ -t 0 ]]; then
                # 交互模式
                read -p "确定要删除所有实验结果吗? (y/N): " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    rm -rf results
                    log_success "结果目录已删除"
                else
                    log_info "保留结果目录"
                fi
            else
                # 非交互模式
                log_warning "非交互模式，跳过结果目录删除"
                log_info "如需删除，请在交互模式下运行"
            fi
        else
            log_info "结果目录不存在"
        fi
    else
        log_info "使用 --all 参数可同时清理结果目录"
    fi
}

# 显示帮助信息
show_help() {
    cat <<EOF
使用方法: bash cleanup.sh [选项]

清理实验过程中创建的虚拟机和Docker容器

选项:
  --all                  同时清理结果目录
  --vm-name NAME         指定要清理的VM名称（默认: test-vm-nginx）
  --container-name NAME  指定要清理的容器名称（默认: test-docker-nginx）
  -h, --help            显示此帮助信息

示例:
  bash cleanup.sh                    # 清理默认VM和容器
  bash cleanup.sh --all              # 清理VM、容器和结果目录
  bash cleanup.sh --vm-name my-vm    # 清理指定名称的VM

EOF
}

# 主函数
main() {
    # 检查帮助参数
    for arg in "$@"; do
        if [[ "$arg" == "-h" ]] || [[ "$arg" == "--help" ]]; then
            show_help
            exit 0
        fi
    done
    
    log_info "=========================================="
    log_info "实验资源清理脚本"
    log_info "=========================================="
    
    # 检查权限
    if [ "$EUID" -ne 0 ]; then 
        log_warning "建议使用sudo运行以清理所有资源"
        log_info "如遇权限问题，请使用: sudo bash $0 $*"
    fi
    
    echo ""
    log_info "清理配置:"
    log_info "  VM名称: ${VM_NAME}"
    log_info "  容器名称: ${DOCKER_CONTAINER_NAME}"
    log_info "  清理结果: ${CLEAN_ALL}"
    echo ""
    
    # 清理VM
    cleanup_vm
    echo ""
    
    # 清理Docker
    cleanup_docker
    echo ""
    
    # 清理结果目录（可选）
    cleanup_results
    
    echo ""
    log_success "=========================================="
    log_success "清理完成！"
    log_success "=========================================="
}

main "$@"

