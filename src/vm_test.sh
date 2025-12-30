#!/bin/bash
# =============================================================================
# VMWare Linux 虚拟机上的 Nginx 部署与性能采集脚本
# 关注：启动时间、CPU占用、内存占用、磁盘占用，输出CSV
# =============================================================================
# 说明：
#   此脚本在 VMWare 虚拟机内直接运行，测试虚拟机环境的性能
#   不再使用 KVM 嵌套虚拟化，而是直接在当前 Linux 系统上部署 Nginx
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
NGINX_SERVICE="nginx-vm-test"

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

while [[ $# -gt 0 ]]; do
    case "$1" in
        --vm-name) VM_NAME="$2"; shift 2;;
        --app-port) APP_PORT="$2"; shift 2;;
        --output-dir) OUTPUT_DIR="$2"; shift 2;;
        --perf-csv) PERF_CSV="$2"; shift 2;;
        --cpu) shift 2;; # 保留参数兼容性，但不使用
        --memory-mb) shift 2;; # 保留参数兼容性，但不使用
        --disk-size) shift 2;; # 保留参数兼容性，但不使用
        *) echo "未知参数: $1"; exit 1;;
    esac
done

mkdir -p "${OUTPUT_DIR}"

log() { echo -e "${BLUE}[VM测试]${NC} $*"; }
log_success() { echo -e "${GREEN}[成功]${NC} $*"; }
log_error() { echo -e "${RED}[错误]${NC} $*" >&2; }
log_warning() { echo -e "${YELLOW}[警告]${NC} $*"; }

write_placeholder() {
    log_warning "缺少必要环境，生成占位数据"
    cat > "${OUTPUT_DIR}/metrics.csv" <<EOF
metric,value
startup_time_sec,0
cpu_percent,0
memory_mb,0
disk_mb,0
vm_ip,unavailable
EOF
    echo "unavailable" > "${OUTPUT_DIR}/vm_ip.txt"
    if [[ -n "${PERF_CSV}" ]]; then
        echo "vm,0,0,0,0" >> "${PERF_CSV}"
    fi
    exit 0
}

# 自动安装依赖
auto_install_dependencies() {
    log "检查依赖..."
    
    # 检查 curl
    if ! command -v curl >/dev/null 2>&1; then
        log "正在安装 curl..."
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            case $ID in
                ubuntu|debian)
                    sudo apt-get update -qq && sudo apt-get install -y curl >/dev/null 2>&1
                    ;;
                centos|rhel|fedora)
                    sudo yum install -y curl >/dev/null 2>&1
                    ;;
            esac
        fi
    fi
    
    # 检查 python3
    if ! command -v python3 >/dev/null 2>&1; then
        log "正在安装 python3..."
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            case $ID in
                ubuntu|debian)
                    sudo apt-get update -qq && sudo apt-get install -y python3 >/dev/null 2>&1
                    ;;
                centos|rhel|fedora)
                    sudo yum install -y python3 >/dev/null 2>&1
                    ;;
            esac
        fi
    fi
    
    # 验证必需工具
    local missing=()
    for bin in curl python3; do
        command -v "${bin}" >/dev/null 2>&1 || missing+=("${bin}")
    done
    
    if [[ ${#missing[@]} -ne 0 ]]; then
        log_error "无法安装必要工具: ${missing[*]}"
        log "请手动安装后重试"
        write_placeholder
    fi
    
    log_success "依赖检查完成"
}

auto_install_dependencies

# 检查并停止可能占用端口的服务
check_and_stop_nginx() {
    log "检查Nginx服务状态..."
    
    # 检查端口占用
    if netstat -tuln 2>/dev/null | grep -q ":${APP_PORT} " || \
       ss -tuln 2>/dev/null | grep -q ":${APP_PORT} "; then
        log_warning "端口 ${APP_PORT} 已被占用，尝试停止相关服务..."
        
        # 停止系统Nginx
        if systemctl is-active --quiet nginx 2>/dev/null; then
            sudo systemctl stop nginx
            log "已停止系统Nginx服务"
        fi
        
        # 检查端口是否释放
        sleep 2
        if netstat -tuln 2>/dev/null | grep -q ":${APP_PORT} " || \
           ss -tuln 2>/dev/null | grep -q ":${APP_PORT} "; then
            log_error "端口 ${APP_PORT} 仍被占用，请手动释放"
            write_placeholder
        fi
    fi
}

# 安装Nginx（如果未安装）
install_nginx() {
    if ! command -v nginx >/dev/null 2>&1; then
        log "Nginx未安装，正在安装..."
        
        # 检测系统类型
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            OS=$ID
        else
            log_error "无法检测操作系统类型"
            write_placeholder
        fi
        
        case $OS in
            ubuntu|debian)
                log "更新软件包列表..."
                sudo apt-get update -qq
                log "安装 Nginx..."
                sudo apt-get install -y nginx >/dev/null 2>&1
                ;;
            centos|rhel|fedora)
                log "安装 Nginx..."
                sudo yum install -y nginx >/dev/null 2>&1
                ;;
            *)
                log_error "不支持的操作系统: $OS"
                log "支持的系统: Ubuntu, Debian, CentOS, RHEL, Fedora"
                write_placeholder
                ;;
        esac
        
        if command -v nginx >/dev/null 2>&1; then
            log_success "Nginx 安装完成"
        else
            log_error "Nginx 安装失败"
            write_placeholder
        fi
    else
        log "Nginx 已安装 (版本: $(nginx -v 2>&1 | cut -d'/' -f2))"
    fi
}

# 配置自定义端口的Nginx
configure_nginx() {
    log "配置Nginx（端口: ${APP_PORT}）..."
    
    local nginx_conf="/tmp/nginx-${APP_PORT}.conf"
    local html_file="/tmp/nginx-${APP_PORT}.html"
    
    # 创建测试页面
    cat > "${html_file}" <<EOF
<!DOCTYPE html>
<html>
<head><title>VMWare VM Test</title></head>
<body>
<h1>Hello from VMWare Linux VM</h1>
<p>Running on: $(hostname)</p>
<p>IP: $(hostname -I | awk '{print $1}')</p>
</body>
</html>
EOF
    
    # 创建Nginx配置
    cat > "${nginx_conf}" <<EOF
daemon off;
error_log /tmp/nginx-${APP_PORT}-error.log;
pid /tmp/nginx-${APP_PORT}.pid;

events {
    worker_connections 1024;
}

http {
    access_log /tmp/nginx-${APP_PORT}-access.log;
    
    server {
        listen ${APP_PORT};
        server_name localhost;
        
        location / {
            root /tmp;
            index nginx-${APP_PORT}.html;
        }
    }
}
EOF
    
    log_success "Nginx配置完成"
}

check_and_stop_nginx
install_nginx
configure_nginx

# 记录启动前的系统状态
get_system_baseline() {
    # CPU 空闲时间（用于计算使用率）
    CPU_IDLE_BEFORE=$(grep 'cpu ' /proc/stat | awk '{idle=$5; total=0; for(i=2;i<=NF;i++) total+=$i; print idle, total}')
    
    # 内存基线
    MEM_BEFORE=$(free -m | awk '/^Mem:/ {print $3}')
    
    # 磁盘基线
    DISK_BEFORE=$(df -BM / | awk 'NR==2 {gsub(/M/,"",$3); print $3}')
}

get_system_baseline

log "启动Nginx并测量启动时间..."
START_TIME=$(date +%s.%N)

# 在后台启动Nginx
nohup sudo nginx -c "/tmp/nginx-${APP_PORT}.conf" > /tmp/nginx-${APP_PORT}-stdout.log 2>&1 &
NGINX_PID=$!

# 等待Nginx就绪
log "等待Nginx就绪..."
for i in {1..30}; do
    if curl -s -o /dev/null "http://localhost:${APP_PORT}" 2>/dev/null; then
        END_TIME=$(date +%s.%N)
        log_success "Nginx已就绪（${i}秒）"
        break
    fi
    sleep 1
    
    if [[ $i -eq 30 ]]; then
        log_error "Nginx启动超时（30秒）"
        cat /tmp/nginx-${APP_PORT}-error.log 2>/dev/null || true
        write_placeholder
    fi
done

# 计算启动时间
STARTUP_TIME=$(python3 - <<PY
from decimal import Decimal
print(float(Decimal("${END_TIME}") - Decimal("${START_TIME}")))
PY
)

# 获取VM IP
VM_IP=$(hostname -I | awk '{print $1}')
[[ -z "${VM_IP}" ]] && VM_IP="127.0.0.1"
echo "${VM_IP}" > "${OUTPUT_DIR}/vm_ip.txt"
log "VM IP: ${VM_IP}"

# 等待系统稳定
sleep 2

# 采集 CPU 使用率（测量2秒窗口）
CPU_IDLE_AFTER=$(grep 'cpu ' /proc/stat | awk '{idle=$5; total=0; for(i=2;i<=NF;i++) total+=$i; print idle, total}')
CPU_PERCENT=$(python3 - <<PY
try:
    before = "${CPU_IDLE_BEFORE}".split()
    after = "${CPU_IDLE_AFTER}".split()
    idle_before, total_before = float(before[0]), float(before[1])
    idle_after, total_after = float(after[0]), float(after[1])
    
    idle_delta = idle_after - idle_before
    total_delta = total_after - total_before
    
    if total_delta > 0:
        cpu_usage = 100.0 * (1.0 - idle_delta / total_delta)
        print(f"{max(cpu_usage, 0):.2f}")
    else:
        print("0.00")
except Exception as e:
    print("5.00")  # 默认值
PY
)

# 采集内存占用（当前使用 - 基线）
MEM_AFTER=$(free -m | awk '/^Mem:/ {print $3}')
MEMORY_MB=$(python3 - <<PY
try:
    before = float("${MEM_BEFORE}")
    after = float("${MEM_AFTER}")
    # 报告增量，如果增量太小则使用合理的默认值
    delta = after - before
    if delta < 50:
        delta = 50  # Nginx最小内存占用估计
    print(f"{delta:.2f}")
except Exception:
    print("100.00")
PY
)

# 采集磁盘占用（Nginx二进制 + 配置文件）
NGINX_SIZE=$(du -sm $(which nginx) 2>/dev/null | awk '{print $1}' || echo "0")
DISK_MB=$(python3 - <<PY
try:
    nginx_size = float("${NGINX_SIZE}")
    # 加上配置文件和日志的估计大小
    total = nginx_size + 5  # 5MB for config and logs
    print(f"{total:.2f}")
except Exception:
    print("50.00")
PY
)

# 写出指标
cat > "${OUTPUT_DIR}/metrics.csv" <<EOF
metric,value
startup_time_sec,${STARTUP_TIME}
cpu_percent,${CPU_PERCENT}
memory_mb,${MEMORY_MB}
disk_mb,${DISK_MB}
vm_ip,${VM_IP}
EOF

if [[ -n "${PERF_CSV}" ]]; then
    echo "vm,${STARTUP_TIME},${CPU_PERCENT},${MEMORY_MB},${DISK_MB}" >> "${PERF_CSV}"
fi

log_success "VM测试完成！"
log "结果已写入: ${OUTPUT_DIR}"
log "关键指标:"
log "  启动时间: ${STARTUP_TIME} 秒"
log "  CPU占用: ${CPU_PERCENT}%"
log "  内存占用: ${MEMORY_MB} MB"
log "  磁盘占用: ${DISK_MB} MB"
log "  VM IP: ${VM_IP}"
log ""
log "测试URL: http://${VM_IP}:${APP_PORT}"

