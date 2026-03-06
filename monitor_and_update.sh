#!/bin/bash
# =============================================================================
# CloudflareSpeedTest 智能监控更新脚本
# 功能: 持续监控当前IP质量，只在必要时触发完整测速更新
# =============================================================================

set -euo pipefail

CFST_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${CFST_DIR}/.monitor_config"
LOG_FILE="${CFST_DIR}/monitor.log"
HOSTS_FILE="/etc/hosts"
PID_FILE="${CFST_DIR}/.monitor_pid"

# 默认配置（可在 CONFIG_FILE 中覆盖）
CHECK_INTERVAL=180          # 检测间隔：3分钟（秒）
LATENCY_THRESHOLD=200       # 延迟阈值：超过此值认为IP变差（ms）
LOSS_THRESHOLD=5            # 丢包阈值：超过此值认为IP变差（%）
CONSECUTIVE_BAD=3           # 连续N次检测异常才触发更新
HISTORY_SIZE=10             # 保留最近N次检测记录
MIN_UPDATE_INTERVAL=3600    # 最少间隔1小时才允许更新（防止频繁更新）

# 加载配置
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    fi
}

# 保存配置
save_config() {
    cat > "$CONFIG_FILE" << EOF
# 监控配置
CHECK_INTERVAL=${CHECK_INTERVAL}
LATENCY_THRESHOLD=${LATENCY_THRESHOLD}
LOSS_THRESHOLD=${LOSS_THRESHOLD}
CONSECUTIVE_BAD=${CONSECUTIVE_BAD}
HISTORY_SIZE=${HISTORY_SIZE}
MIN_UPDATE_INTERVAL=${MIN_UPDATE_INTERVAL}
CURRENT_IP=${CURRENT_IP:-}
LAST_UPDATE_TIME=${LAST_UPDATE_TIME:-0}
BAD_COUNT=${BAD_COUNT:-0}
EOF
}

# 日志函数
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

# 获取当前IP
get_current_ip() {
    local domain=$(grep "TARGET_DOMAINS" "${CFST_DIR}/auto_update_hosts.sh" | grep -o '"[^"]*"' | head -1 | tr -d '"')
    grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+${domain}" "$HOSTS_FILE" | awk '{print $1}' | head -1
}

# 检测IP质量 (ping)
check_ip_quality() {
    local ip=$1
    local result=$(ping -c 5 -i 0.2 "$ip" 2>/dev/null | tail -1)
    
    # 解析延迟和丢包
    local avg_delay=$(echo "$result" | awk -F'/' '{print $5}')
    local loss=$(ping -c 5 -i 0.2 "$ip" 2>/dev/null | grep -o '[0-9]\+\.\?[0-9]*%' | head -1 | tr -d '%')
    
    # 如果ping失败
    if [[ -z "$avg_delay" ]] || [[ "$avg_delay" == "0" ]]; then
        echo "failed 100"
        return
    fi
    
    echo "${avg_delay%.*} ${loss:-0}"
}

# 检测是否需要更新
should_update() {
    local current_ip=$(get_current_ip)
    CURRENT_IP=$current_ip
    
    if [[ -z "$current_ip" ]]; then
        log "错误: 无法从hosts获取当前IP"
        return 1
    fi
    
    log "检测当前IP: $current_ip"
    
    # 检测当前IP质量
    local quality=$(check_ip_quality "$current_ip")
    local delay=$(echo "$quality" | awk '{print $1}')
    local loss=$(echo "$quality" | awk '{print $2}')
    
    log "当前延迟: ${delay}ms, 丢包: ${loss}%"
    
    # 记录历史
    echo "$(date +%s) $delay $loss" >> "${CFST_DIR}/.latency_history"
    # 只保留最近N条
    tail -n "$HISTORY_SIZE" "${CFST_DIR}/.latency_history" > "${CFST_DIR}/.latency_history.tmp"
    mv "${CFST_DIR}/.latency_history.tmp" "${CFST_DIR}/.latency_history"
    
    # 判断是否需要更新
    local need_update=false
    local reason=""
    
    # 条件1: ping失败
    if [[ "$delay" == "failed" ]]; then
        BAD_COUNT=$((BAD_COUNT + 1))
        reason="IP无法ping通"
    # 条件2: 延迟过高
    elif [[ "$delay" -gt "$LATENCY_THRESHOLD" ]]; then
        BAD_COUNT=$((BAD_COUNT + 1))
        reason="延迟过高(${delay}ms > ${LATENCY_THRESHOLD}ms)"
    # 条件3: 丢包严重
    elif [[ "${loss%.*}" -gt "$LOSS_THRESHOLD" ]]; then
        BAD_COUNT=$((BAD_COUNT + 1))
        reason="丢包严重(${loss}% > ${LOSS_THRESHOLD}%)"
    else
        # 质量良好，重置计数
        if [[ "$BAD_COUNT" -gt 0 ]]; then
            log "IP质量恢复，重置异常计数"
            BAD_COUNT=0
        fi
    fi
    
    save_config
    
    # 检查连续异常次数
    if [[ "$BAD_COUNT" -ge "$CONSECUTIVE_BAD" ]]; then
        log "连续${CONSECUTIVE_BAD}次检测异常: $reason"
        
        # 检查是否满足最小更新间隔
        local current_time=$(date +%s)
        local time_since_last=$((current_time - LAST_UPDATE_TIME))
        
        if [[ "$time_since_last" -lt "$MIN_UPDATE_INTERVAL" ]]; then
            log "距离上次更新仅${time_since_last}秒，少于${MIN_UPDATE_INTERVAL}秒，暂不更新"
            return 1
        fi
        
        return 0  # 需要更新
    fi
    
    return 1  # 不需要更新
}

# 执行更新
perform_update() {
    log "触发IP更新..."
    
    if "${CFST_DIR}/auto_update_hosts.sh"; then
        LAST_UPDATE_TIME=$(date +%s)
        BAD_COUNT=0
        save_config
        log "IP更新成功"
        
        # 发送通知（macOS）
        if [[ "$OSTYPE" == "darwin"* ]]; then
            osascript -e 'display notification "Cloudflare IP已更新为最优节点" with title "CFST Monitor"' 2>/dev/null || true
        fi
        
        return 0
    else
        log "IP更新失败"
        return 1
    fi
}

# 显示统计
show_stats() {
    echo "=== 监控统计 ==="
    echo ""
    
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        echo "当前IP: ${CURRENT_IP:-未知}"
        echo "上次更新: $(date -r "$LAST_UPDATE_TIME" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '从未')"
        echo "连续异常次数: ${BAD_COUNT:-0}"
        echo ""
        echo "阈值配置:"
        echo "  检测间隔: ${CHECK_INTERVAL}秒"
        echo "  延迟阈值: ${LATENCY_THRESHOLD}ms"
        echo "  丢包阈值: ${LOSS_THRESHOLD}%"
        echo "  连续异常: ${CONSECUTIVE_BAD}次"
        echo "  最小更新间隔: ${MIN_UPDATE_INTERVAL}秒"
    fi
    
    echo ""
    if [[ -f "${CFST_DIR}/.latency_history" ]]; then
        echo "最近延迟记录:"
        echo "时间                  延迟(ms)  丢包(%)"
        echo "----------------------------------------"
        tail -5 "${CFST_DIR}/.latency_history" | while read -r timestamp delay loss; do
            printf "%s  %-8s  %s%%\n" "$(date -r "$timestamp" '+%m-%d %H:%M:%S')" "$delay" "$loss"
        done
    fi
}

# 配置向导
setup_config() {
    echo "=== 监控配置向导 ==="
    echo ""
    
    read -p "检测间隔(秒) [默认180=3分钟]: " input
    CHECK_INTERVAL=${input:-180}
    
    read -p "延迟阈值(ms) [默认200]: " input
    LATENCY_THRESHOLD=${input:-200}
    
    read -p "丢包阈值(%) [默认5]: " input
    LOSS_THRESHOLD=${input:-5}
    
    read -p "连续异常次数触发更新 [默认3]: " input
    CONSECUTIVE_BAD=${input:-3}
    
    read -p "最小更新间隔(秒) [默认3600=1小时]: " input
    MIN_UPDATE_INTERVAL=${input:-3600}
    
    LAST_UPDATE_TIME=$(date +%s)
    BAD_COUNT=0
    
    save_config
    
    echo ""
    echo "✓ 配置已保存到 $CONFIG_FILE"
}

# 监控主循环
monitor_loop() {
    load_config
    
    # 初始化
    if [[ -z "${CURRENT_IP:-}" ]]; then
        CURRENT_IP=$(get_current_ip)
        LAST_UPDATE_TIME=$(date +%s)
        save_config
    fi
    
    log "=== 监控启动 ==="
    log "当前IP: $CURRENT_IP"
    log "检测间隔: ${CHECK_INTERVAL}秒"
    log "延迟阈值: ${LATENCY_THRESHOLD}ms"
    
    # 保存PID
    echo $$ > "$PID_FILE"
    
    # 主循环
    while true; do
        if should_update; then
            perform_update
            # 更新当前IP（可能已变更）
            CURRENT_IP=$(get_current_ip)
        fi
        
        sleep "$CHECK_INTERVAL"
    done
}

# 停止监控
stop_monitor() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            rm -f "$PID_FILE"
            echo "✓ 监控已停止"
        else
            echo "监控未运行"
            rm -f "$PID_FILE"
        fi
    else
        echo "监控未运行"
    fi
}

# 查看状态
show_status() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "✓ 监控运行中 (PID: $pid)"
            show_stats
        else
            echo "✗ 监控未运行 (PID文件残留)"
            rm -f "$PID_FILE"
        fi
    else
        echo "✗ 监控未运行"
    fi
}

# 主程序
case "${1:-}" in
    start)
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "监控已在运行"
            exit 1
        fi
        monitor_loop &
        echo "✓ 监控已启动 (PID: $!)"
        ;;
    stop)
        stop_monitor
        ;;
    status)
        show_status
        ;;
    stats)
        show_stats
        ;;
    config)
        setup_config
        ;;
    check)
        # 立即执行一次检测
        load_config
        if should_update; then
            perform_update
        else
            echo "当前IP质量良好，无需更新"
        fi
        ;;
    log)
        tail -f "$LOG_FILE"
        ;;
    *)
        cat << 'EOF'
CloudflareSpeedTest 智能监控脚本

用法: ./monitor_and_update.sh [命令]

命令:
    start      启动后台监控
    stop       停止监控
    status     查看监控状态
    stats      查看统计信息
    config     配置监控参数
    check      立即执行一次检测
    log        查看实时日志

示例:
    ./monitor_and_update.sh config   # 先配置
    ./monitor_and_update.sh start    # 启动监控
    ./monitor_and_update.sh status   # 查看状态

监控逻辑:
    1. 每3分钟检测一次当前IP的延迟和丢包
    2. 如果连续3次检测异常（延迟>200ms或丢包>5%）
    3. 且距离上次更新超过1小时
    4. 则触发完整测速并更新IP

EOF
        ;;
esac
