#!/bin/bash
# =============================================================================
# 精简版压测脚本（Apache Bench）
# =============================================================================
# 功能：使用Apache Bench对VM和Docker进行压力测试
# 输出：stress.csv (格式: platform,qps,avg_latency_ms,failed,transfer_kbps)
#
# 使用方法:
#   bash stress_test.sh --vm-url http://VM_IP:8080 --docker-url http://localhost:8080
# =============================================================================

set -euo pipefail

# 默认参数
VM_URL="http://localhost:8080"
DOCKER_URL="http://localhost:8080"
TOTAL_REQUESTS=2000
CONCURRENCY=50
OUTPUT_DIR="./results"
OUTPUT_CSV="./results/stress.csv"

# 颜色定义
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

while [[ $# -gt 0 ]]; do
    case "$1" in
        --vm-url) VM_URL="$2"; shift 2;;
        --docker-url) DOCKER_URL="$2"; shift 2;;
        --requests) TOTAL_REQUESTS="$2"; shift 2;;
        --concurrency) CONCURRENCY="$2"; shift 2;;
        --output-dir) OUTPUT_DIR="$2"; shift 2;;
        --output-csv) OUTPUT_CSV="$2"; shift 2;;
        *) echo "未知参数: $1"; exit 1;;
    esac
done

mkdir -p "${OUTPUT_DIR}"
echo "platform,qps,avg_latency_ms,failed,transfer_kbps" > "${OUTPUT_CSV}"

log() { echo -e "${BLUE}[压测]${NC} $*"; }
log_success() { echo -e "${GREEN}[成功]${NC} $*"; }
log_error() { echo -e "${RED}[错误]${NC} $*" >&2; }
log_warning() { echo -e "${YELLOW}[警告]${NC} $*"; }

write_placeholder() {
    log_warning "写入占位数据（所有指标为0）"
    echo "vm,0,0,0,0" >> "${OUTPUT_CSV}"
    echo "docker,0,0,0,0" >> "${OUTPUT_CSV}"
    exit 0
}

validate_dependencies() {
    local missing_deps=()
    
    if ! command -v ab >/dev/null 2>&1; then
        missing_deps+=("ab (Apache Bench)")
    fi
    
    if ! command -v curl >/dev/null 2>&1; then
        missing_deps+=("curl")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "缺少必要工具: ${missing_deps[*]}"
        log "请安装: sudo apt-get install apache2-utils curl"
        write_placeholder
    fi
}

validate_url() {
    local url="$1"
    if [[ ! "$url" =~ ^https?:// ]]; then
        log_error "无效的URL格式: $url"
        return 1
    fi
    return 0
}

validate_parameters() {
    if [[ $TOTAL_REQUESTS -lt 1 ]]; then
        log_error "请求总数必须大于0: $TOTAL_REQUESTS"
        exit 1
    fi
    
    if [[ $CONCURRENCY -lt 1 ]]; then
        log_error "并发数必须大于0: $CONCURRENCY"
        exit 1
    fi
    
    if [[ $CONCURRENCY -gt $TOTAL_REQUESTS ]]; then
        log_warning "并发数($CONCURRENCY)大于请求总数($TOTAL_REQUESTS)，将调整为$TOTAL_REQUESTS"
        CONCURRENCY=$TOTAL_REQUESTS
    fi
    
    validate_url "$VM_URL" || exit 1
    validate_url "$DOCKER_URL" || exit 1
}

validate_dependencies

check_url_accessible() {
    local url="$1"
    local max_retries=3
    local retry_delay=2
    
    for ((i=1; i<=max_retries; i++)); do
        if curl -s -o /dev/null -w "%{http_code}" "${url}" 2>/dev/null | grep -q "200"; then
            return 0
        fi
        if [[ $i -lt $max_retries ]]; then
            log_warning "无法访问 ${url}，${retry_delay}秒后重试... ($i/$max_retries)"
            sleep $retry_delay
        fi
    done
    return 1
}

extract_ab_metrics() {
    local outfile="$1"
    local qps avg failed transfer
    
    qps=$(grep "Requests per second" "${outfile}" 2>/dev/null | awk '{print $4}' | head -1)
    avg=$(grep "Time per request" "${outfile}" 2>/dev/null | head -1 | awk '{print $4}' | head -1)
    failed=$(grep "Failed requests" "${outfile}" 2>/dev/null | awk '{print $3}' | head -1)
    transfer=$(grep "Transfer rate" "${outfile}" 2>/dev/null | awk '{print $3}' | head -1)
    
    # 设置默认值
    qps=${qps:-0}
    avg=${avg:-0}
    failed=${failed:-0}
    transfer=${transfer:-0}
    
    echo "${qps},${avg},${failed},${transfer}"
}

run_ab() {
    local name=$1
    local url=$2
    local outfile="${OUTPUT_DIR}/stress_${name}.txt"

    log "开始压测 ${name}: ${url}"
    log "配置: 请求数=${TOTAL_REQUESTS}, 并发数=${CONCURRENCY}"
    
    # 检查URL可访问性
    if ! check_url_accessible "${url}"; then
        log_error "${name} 无法访问，记录为0"
        echo "${name},0,0,0,0" >> "${OUTPUT_CSV}"
        return 1
    fi
    
    # 执行压测
    log "执行压测，请稍候..."
    if ! ab -n "${TOTAL_REQUESTS}" -c "${CONCURRENCY}" -q "${url}/" > "${outfile}" 2>&1; then
        log_error "${name} 压测失败，检查日志: ${outfile}"
        echo "${name},0,0,0,0" >> "${OUTPUT_CSV}"
        return 1
    fi
    
    # 提取指标
    local metrics
    metrics=$(extract_ab_metrics "${outfile}")
    
    local qps=$(echo "$metrics" | cut -d',' -f1)
    local avg=$(echo "$metrics" | cut -d',' -f2)
    local failed=$(echo "$metrics" | cut -d',' -f3)
    local transfer=$(echo "$metrics" | cut -d',' -f4)
    
    echo "${name},${qps},${avg},${failed},${transfer}" >> "${OUTPUT_CSV}"
    
    log_success "${name} 压测完成"
    log "  QPS: ${qps} 请求/秒"
    log "  平均延迟: ${avg} ms"
    log "  失败请求: ${failed}"
    log "  传输速率: ${transfer} KB/s"
    return 0
}

echo "=================================="
echo "开始压力测试"
echo "=================================="

# 验证参数
validate_parameters

# 显示测试配置
log "测试配置:"
log "  VM URL: ${VM_URL}"
log "  Docker URL: ${DOCKER_URL}"
log "  请求总数: ${TOTAL_REQUESTS}"
log "  并发数: ${CONCURRENCY}"
log "  输出文件: ${OUTPUT_CSV}"
echo ""

# 执行压测
run_ab "vm" "${VM_URL}"
echo ""
run_ab "docker" "${DOCKER_URL}"

echo ""
echo "=================================="
log_success "压测完成！结果已写入: ${OUTPUT_CSV}"
echo "=================================="

