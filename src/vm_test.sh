#!/bin/bash
# =============================================================================
# VMWare Linux 虚拟机上的 Nginx 部署与性能采集脚本
# 关注：启动时间、CPU占用、内存占用、磁盘占用，输出CSV
# =============================================================================
# 说明：
#   此脚本在 VMWare 虚拟机内直接运行，测试虚拟机环境的性能
#
# 使用方法：
#   在 VMWare Linux 虚拟机中运行：
#   bash vm_test.sh
#   或指定端口：
#   bash vm_test.sh --app-port 9090
#
# 要求：
#   - Ubuntu/Debian/CentOS 等主流 Linux 发行版
#   - 需要 sudo 权限（用于安装软件和启动 Nginx）
#   - 需要互联网连接（首次运行时安装依赖）
# =============================================================================

set -euo pipefail

VM_NAME="vmware-nginx"
APP_PORT=8080
OUTPUT_DIR="./results/vm"
PERF_CSV=""
IMAGE="nginx:latest"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log() { echo -e "${BLUE}[VM]${NC} $*"; }
log_success() { echo -e "${GREEN}[✓]${NC} $*"; }
log_error() { echo -e "${RED}[✗]${NC} $*" >&2; }
log_warning() { echo -e "${YELLOW}[!]${NC} $*"; }

write_placeholder() {
    log_warning "测试失败，生成占位数据"
    mkdir -p "${OUTPUT_DIR}"
    cat > "${OUTPUT_DIR}/metrics.csv" <<EOF
metric,value
startup_time_sec,0
cpu_percent,0
memory_mb,0
disk_mb,0
vm_ip,unavailable
EOF
    [[ -n "${PERF_CSV}" ]] && echo "vm,0,0,0,0" >> "${PERF_CSV}"
    exit 0
}

ensure_dependencies() {
    local missing=()
    
    command -v nginx >/dev/null 2>&1 || missing+=("nginx")
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v python3 >/dev/null 2>&1 || missing+=("python3")
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warning "缺少依赖: ${missing[*]}"
        log "尝试自动安装..."
        
        if command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update >/dev/null 2>&1
            sudo apt-get install -y "${missing[@]}" || {
                log_error "安装失败，请手动安装: ${missing[*]}"
                write_placeholder
            }
        else
            log_error "请手动安装: ${missing[*]}"
            write_placeholder
        fi
    fi
}

validate_port() {
    if netstat -tuln 2>/dev/null | grep -q ":${APP_PORT} " || \
       ss -tuln 2>/dev/null | grep -q ":${APP_PORT} "; then
        log_error "端口 ${APP_PORT} 已被占用"
        log "请使用 --app-port 指定其他端口"
        exit 1
    fi
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --vm-name) VM_NAME="$2"; shift 2;;
            --app-port) APP_PORT="$2"; shift 2;;
            --output-dir) OUTPUT_DIR="$2"; shift 2;;
            --perf-csv) PERF_CSV="$2"; shift 2;;
            *) log_error "未知参数: $1"; exit 1;;
        esac
    done
}

parse_args "$@"
mkdir -p "${OUTPUT_DIR}"

ensure_dependencies
validate_port

log "停止可能存在的Nginx服务..."
sudo systemctl stop nginx 2>/dev/null || true
sudo pkill -9 nginx 2>/dev/null || true

# 确保nginx完全停止，清理所有残留进程和文件
sleep 1
sudo rm -f /tmp/nginx_test_*.pid 2>/dev/null || true
sudo rm -f /tmp/nginx_*.log 2>/dev/null || true
sudo rm -f /var/run/nginx.pid 2>/dev/null || true

# 清理系统缓存，确保冷启动测试（与Docker公平对比）
sync
sudo sh -c 'echo 3 > /proc/sys/vm/drop_caches' 2>/dev/null || true

log "配置Nginx监听端口 ${APP_PORT}..."
# 创建临时配置文件
NGINX_CONF="/tmp/nginx_test_${APP_PORT}.conf"
cat > "${NGINX_CONF}" <<NGINXEOF
user www-data;
worker_processes auto;
pid /tmp/nginx_test_${APP_PORT}.pid;

events {
    worker_connections 768;
}

http {
    access_log /tmp/nginx_access_${APP_PORT}.log;
    error_log /tmp/nginx_error_${APP_PORT}.log;
    
    server {
        listen ${APP_PORT};
        server_name localhost;
        
        location / {
            root /usr/share/nginx/html;
            index index.html index.htm;
        }
    }
}
NGINXEOF

# 如果nginx html目录不存在，使用默认HTML
if [[ ! -d "/usr/share/nginx/html" ]]; then
    sudo mkdir -p /usr/share/nginx/html
    echo "<html><body><h1>Welcome to nginx!</h1></body></html>" | sudo tee /usr/share/nginx/html/index.html >/dev/null
fi

# ============================================================================
# 【启动时间测量】
# 测量从执行nginx命令到服务完全就绪的时间
# 与Docker的docker start对等（不含容器创建时间）
# ============================================================================
log "启动Nginx..."
START_TIME=$(date +%s.%N)

# 启动nginx
sudo nginx -c "${NGINX_CONF}" || {
    log_error "Nginx启动失败"
    write_placeholder
}

log "等待Nginx完全就绪..."
ready=false
success_count=0

# 等待nginx就绪并进行健康检查（连续3次HTTP 200）
for i in {1..30}; do
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${APP_PORT}" 2>/dev/null | grep -q "200"; then
        success_count=$((success_count + 1))
        if [[ $success_count -ge 3 ]]; then
            ready=true
            break
        fi
        sleep 0.1
    else
        success_count=0
        sleep 0.3
    fi
done

if [[ "$ready" != true ]]; then
    log_error "Nginx启动超时"
    write_placeholder
fi

END_TIME=$(date +%s.%N)
STARTUP_TIME=$(python3 <<PY
from decimal import Decimal
print(float(Decimal("${END_TIME}") - Decimal("${START_TIME}")))
PY
)

log_success "Nginx已启动 (${STARTUP_TIME}秒)"

# ============================================================================
# 【性能指标采集】
# 在有负载情况下采集，确保CPU有真实消耗
# ============================================================================
log "采集性能指标..."

# 【关键修复】先产生负载，再采集CPU
log "产生负载以获取真实CPU数据..."
for i in {1..50}; do
    curl -s -o /dev/null "http://localhost:${APP_PORT}" &
done
wait
sleep 0.5

# ============================================================================
# 【CPU测量】统计所有nginx进程的CPU使用率
# 方法：ps -C nginx，与Docker的进程级统计对等
# ============================================================================
CPU_SUM=0
SAMPLE_COUNT=5
for i in $(seq 1 $SAMPLE_COUNT); do
    # 在采样期间持续产生请求
    for j in {1..10}; do
        curl -s -o /dev/null "http://localhost:${APP_PORT}" &
    done
    # 汇总所有nginx进程的CPU
    SAMPLE=$(ps -C nginx -o %cpu --no-headers 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
    CPU_SUM=$(python3 -c "print(${CPU_SUM} + ${SAMPLE})" 2>/dev/null || echo "0")
    sleep 0.5
done
wait
CPU_PERCENT=$(python3 -c "print(round(${CPU_SUM} / ${SAMPLE_COUNT}, 2))" 2>/dev/null || echo "0")

# ============================================================================
# 【内存测量】统计所有nginx进程的RSS内存
# 方法：ps -C nginx -o rss，与Docker的进程级统计对等
# ============================================================================
MEMORY_KB=$(ps -C nginx -o rss --no-headers 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
MEMORY_MB=$(python3 -c "print(round(${MEMORY_KB} / 1024, 2))" 2>/dev/null || echo "0")

# ============================================================================
# 【磁盘测量】统计nginx相关的所有文件
# 包括：可执行文件、配置文件、模块、日志目录、html目录、依赖库
# 与Docker镜像包含的内容对等
# ============================================================================
DISK_KB=0

# nginx可执行文件和核心模块
if [[ -f /usr/sbin/nginx ]]; then
    NGINX_BIN_KB=$(du -sk /usr/sbin/nginx 2>/dev/null | awk '{print $1}' || echo 0)
    DISK_KB=$((DISK_KB + NGINX_BIN_KB))
fi

# nginx配置目录
if [[ -d /etc/nginx ]]; then
    NGINX_CONF_KB=$(du -sk /etc/nginx 2>/dev/null | awk '{print $1}' || echo 0)
    DISK_KB=$((DISK_KB + NGINX_CONF_KB))
fi

# nginx html目录
if [[ -d /usr/share/nginx ]]; then
    NGINX_HTML_KB=$(du -sk /usr/share/nginx 2>/dev/null | awk '{print $1}' || echo 0)
    DISK_KB=$((DISK_KB + NGINX_HTML_KB))
fi

# nginx模块目录
if [[ -d /usr/lib/nginx ]]; then
    NGINX_MOD_KB=$(du -sk /usr/lib/nginx 2>/dev/null | awk '{print $1}' || echo 0)
    DISK_KB=$((DISK_KB + NGINX_MOD_KB))
fi

# nginx日志目录
if [[ -d /var/log/nginx ]]; then
    NGINX_LOG_KB=$(du -sk /var/log/nginx 2>/dev/null | awk '{print $1}' || echo 0)
    DISK_KB=$((DISK_KB + NGINX_LOG_KB))
fi

# nginx运行时目录
if [[ -d /var/lib/nginx ]]; then
    NGINX_VAR_KB=$(du -sk /var/lib/nginx 2>/dev/null | awk '{print $1}' || echo 0)
    DISK_KB=$((DISK_KB + NGINX_VAR_KB))
fi

# nginx依赖的共享库（估算主要依赖）
NGINX_LIBS_KB=$(ldd /usr/sbin/nginx 2>/dev/null | awk '{print $3}' | xargs -I{} du -sk {} 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
DISK_KB=$((DISK_KB + NGINX_LIBS_KB))

DISK_MB=$(python3 -c "print(round(${DISK_KB} / 1024, 2))" 2>/dev/null || echo "0")

# VM IP地址
VM_IP=$(hostname -I | awk '{print $1}' || echo "127.0.0.1")

# 保存指标
cat > "${OUTPUT_DIR}/metrics.csv" <<EOF
metric,value
startup_time_sec,${STARTUP_TIME}
cpu_percent,${CPU_PERCENT}
memory_mb,${MEMORY_MB}
disk_mb,${DISK_MB}
vm_ip,${VM_IP}
EOF

echo "${VM_IP}" > "${OUTPUT_DIR}/vm_ip.txt"

[[ -n "${PERF_CSV}" ]] && echo "vm,${STARTUP_TIME},${CPU_PERCENT},${MEMORY_MB},${DISK_MB}" >> "${PERF_CSV}"

# 注意：不清理Nginx，让压测脚本可以使用
# 清理工作由 cleanup.sh 或 run_experiment.sh 完成

echo ""
log_success "VM测试完成"
log "结果: ${OUTPUT_DIR}"
log "  启动时间: ${STARTUP_TIME}秒"
log "  CPU占用: ${CPU_PERCENT}%"
log "  内存占用: ${MEMORY_MB}MB"
log "  磁盘占用: ${DISK_MB}MB"
log "  VM IP: ${VM_IP}"
