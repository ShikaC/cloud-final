#!/bin/bash
# =============================================================================
# 精简版 Docker Nginx 部署与性能采集脚本
# =============================================================================
# 功能：部署Docker容器并收集性能指标
# 指标：启动时间、CPU占用、内存占用、磁盘占用
# 输出：metrics.csv 和 performance.csv
#
# 使用方法:
#   bash docker_test.sh --container-name docker-nginx --app-port 8080
# =============================================================================

set -euo pipefail

# 默认参数
CONTAINER_NAME="docker-nginx"
APP_PORT=8080
OUTPUT_DIR="./results/docker"
PERF_CSV=""
IMAGE="nginx:alpine"

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

while [[ $# -gt 0 ]]; do
    case "$1" in
        --container-name) CONTAINER_NAME="$2"; shift 2;;
        --app-port) APP_PORT="$2"; shift 2;;
        --output-dir) OUTPUT_DIR="$2"; shift 2;;
        --perf-csv) PERF_CSV="$2"; shift 2;;
        --image) IMAGE="$2"; shift 2;;
        *) echo "未知参数: $1"; exit 1;;
    esac
done

mkdir -p "${OUTPUT_DIR}"

log() { echo -e "${BLUE}[Docker]${NC} $*"; }
log_success() { echo -e "${GREEN}[成功]${NC} $*"; }
log_error() { echo -e "${RED}[错误]${NC} $*" >&2; }
log_warning() { echo -e "${YELLOW}[警告]${NC} $*"; }

write_placeholder() {
    log_warning "缺少Docker或执行失败，生成占位数据"
    mkdir -p "${OUTPUT_DIR}"
    cat > "${OUTPUT_DIR}/metrics.csv" <<EOF
metric,value
startup_time_sec,0
cpu_percent,0
memory_mb,0
disk_mb,0
container_ip,unavailable
EOF
    if [[ -n "${PERF_CSV}" ]]; then
        echo "docker,0,0,0,0" >> "${PERF_CSV}"
    fi
    exit 0
}

validate_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker未安装"
        log "请安装Docker: sudo apt-get install docker.io"
        write_placeholder
    fi
    
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker守护进程未运行或权限不足"
        log "请确保Docker服务已启动: sudo systemctl start docker"
        log "或将当前用户添加到docker组: sudo usermod -aG docker \$USER"
        write_placeholder
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

validate_docker
validate_port

# 清理旧容器
log "检查并清理旧容器..."
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    log "删除已存在的容器: ${CONTAINER_NAME}"
    docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || {
        log_error "无法删除容器，可能权限不足"
        write_placeholder
    }
fi

log "拉取镜像 ${IMAGE}..."
if ! docker pull "${IMAGE}" >/dev/null 2>&1; then
    log_error "拉取镜像失败: ${IMAGE}"
    log "请检查网络连接或使用其他镜像"
    write_placeholder
fi
log_success "镜像准备完成"

log "启动容器并测量启动时间..."
START_TIME=$(date +%s.%N)
docker run -d --name "${CONTAINER_NAME}" -p "${APP_PORT}:80" "${IMAGE}" >/dev/null

# 获取容器IP
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "${CONTAINER_NAME}" 2>/dev/null || echo "")
log "容器IP: ${CONTAINER_IP:-未获取}"

# 等待容器就绪
log "等待容器就绪..."
local ready=false
for i in {1..30}; do
    if curl -s -o /dev/null "http://localhost:${APP_PORT}" 2>/dev/null; then
        ready=true
        log_success "容器已就绪 (${i}秒)"
        break
    fi
    sleep 1
done

if [[ "$ready" != true ]]; then
    log_error "容器启动超时（30秒）"
    docker logs "${CONTAINER_NAME}" 2>&1 | tail -20
    write_placeholder
fi

END_TIME=$(date +%s.%N)
STARTUP_TIME=$(python3 - <<PY
from decimal import Decimal
print(Decimal("${END_TIME}") - Decimal("${START_TIME}"))
PY
)

# 采集指标
STATS=$(docker stats --no-stream --format "{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}}" "${CONTAINER_NAME}" | head -1)
CPU_PERCENT=$(echo "${STATS}" | cut -d',' -f1 | tr -d '%')
MEM_USAGE_RAW=$(echo "${STATS}" | cut -d',' -f2)
MEMORY_MB=$(python3 - <<PY
import re,sys
raw="${MEM_USAGE_RAW}"
used = raw.split('/')[0].strip() if '/' in raw else raw
num = float(re.sub('[^0-9.]','', used) or 0)
if 'GiB' in used or 'GB' in used: num *= 1024
print(f"{num:.2f}")
PY
)

IMAGE_BYTES=$(docker image inspect "${IMAGE}" --format '{{.Size}}' 2>/dev/null || echo 0)
CONTAINER_BYTES=$(docker container inspect --size "${CONTAINER_NAME}" --format '{{.SizeRootFs}}' 2>/dev/null || echo 0)
DISK_BYTES=$(python3 - <<PY
try:
    img=int("${IMAGE_BYTES}")
    cnt=int("${CONTAINER_BYTES}")
    print(img+cnt)
except Exception:
    print(0)
PY
)
DISK_MB=$(python3 - <<PY
try:
    print(f"{float(${DISK_BYTES})/1024/1024:.2f}")
except Exception:
    print("0")
PY
)

cat > "${OUTPUT_DIR}/metrics.csv" <<EOF
metric,value
startup_time_sec,${STARTUP_TIME}
cpu_percent,${CPU_PERCENT}
memory_mb,${MEMORY_MB}
disk_mb,${DISK_MB}
container_ip,${CONTAINER_IP:-unavailable}
EOF

if [[ -n "${PERF_CSV}" ]]; then
    echo "docker,${STARTUP_TIME},${CPU_PERCENT},${MEMORY_MB},${DISK_MB}" >> "${PERF_CSV}"
fi

echo ""
log_success "Docker测试完成！"
log "结果目录: ${OUTPUT_DIR}"
log "  - metrics.csv: 详细指标"
[[ -n "${PERF_CSV}" ]] && log "  - ${PERF_CSV}: 性能汇总"

# 显示关键指标
echo ""
log "关键指标:"
log "  启动时间: ${STARTUP_TIME} 秒"
log "  CPU占用: ${CPU_PERCENT}%"
log "  内存占用: ${MEMORY_MB} MB"
log "  磁盘占用: ${DISK_MB} MB"
log "  容器IP: ${CONTAINER_IP:-unavailable}"

