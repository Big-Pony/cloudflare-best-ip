#!/bin/bash
# =============================================================================
# CloudflareSpeedTest 调度器 - 混合策略
# 策略: 每天完整测速一次 + 每3分钟监控当前IP质量
# =============================================================================

set -euo pipefail

CFST_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEDULER_LOG="${CFST_DIR}/scheduler.log"
PID_FILE="${CFST_DIR}/.scheduler_pid"

# 默认配置
FULL_CHECK_INTERVAL=86400   # 完整测速间隔：24小时
MONITOR_INTERVAL=180        # 监控检测间隔：3分钟
MONITOR_THRESHOLD=200       # 监控延迟阈值：200ms
CONSECUTIVE_BAD=3           # 连续异常次数触发更新

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$SCHEDULER_LOG"
}

# 获取当前IP
get_current_ip() {
    local domain=$(grep "TARGET_DOMAINS" "${CFST_DIR}/auto_update_hosts.sh" | grep -o '"[^"]*"' | head -1 | tr -d '"')
    grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+${domain}" /etc/hosts 2>/dev/null | awk '{print $1}' | head -1
}

# 快速检测当前IP质量
check_current_ip() {
    local ip=$1
    # 发送3个ping包，快速检测
    local result=$(ping -c 3 -i 0.2 -W 2 "$ip" 2>/dev/null | tail -1)
    local avg_delay=$(echo "$result" | awk -F'/' '{print $5}')
    
    if [[ -z "$avg_delay" ]] || [[ "$avg_delay" == "0" ]]; then
        echo "9999"  # 表示失败
    else
        echo "${avg_delay%.*}"
    fi
}

# 执行完整测速更新
full_update() {
    log "执行完整测速更新..."
    if sudo "${CFST_DIR}/auto_update_hosts.sh" >> "$SCHEDULER_LOG" 2>&1; then
        log "完整更新成功"
        LAST_FULL_UPDATE=$(date +%s)
        CONSECUTIVE_BAD_COUNT=0
        return 0
    else
        log "完整更新失败"
        return 1
    fi
}

# 主调度循环
scheduler_loop() {
    log "=== 调度器启动 ==="
    log "策略: 每${FULL_CHECK_INTERVAL}秒完整测速 + 每${MONITOR_INTERVAL}秒质量监控"
    
    LAST_FULL_UPDATE=$(date +%s)
    CONSECUTIVE_BAD_COUNT=0
    CURRENT_IP=$(get_current_ip)
    
    log "当前IP: $CURRENT_IP"
    log "监控阈值: ${MONITOR_THRESHOLD}ms"
    
    local next_full_check=$LAST_FULL_UPDATE
    local next_monitor_check=$LAST_FULL_UPDATE
    
    while true; do
        local current_time=$(date +%s)
        local need_update=false
        local update_reason=""
        
        # 检查是否需要完整测速（时间到了）
        if [[ "$current_time" -ge "$next_full_check" ]]; then
            need_update=true
            update_reason="定期完整测速（24小时）"
        fi
        
        # 检查监控质量（每3分钟）
        if [[ "$current_time" -ge "$next_monitor_check" ]]; then
            CURRENT_IP=$(get_current_ip)
            local current_delay=$(check_current_ip "$CURRENT_IP")
            
            log "质量检测: IP=$CURRENT_IP, 延迟=${current_delay}ms"
            
            if [[ "$current_delay" -gt "$MONITOR_THRESHOLD" ]]; then
                CONSECUTIVE_BAD_COUNT=$((CONSECUTIVE_BAD_COUNT + 1))
                log "⚠️ 延迟过高 (${current_delay}ms > ${MONITOR_THRESHOLD}ms), 连续异常: ${CONSECUTIVE_BAD_COUNT}/${CONSECUTIVE_BAD}"
                
                if [[ "$CONSECUTIVE_BAD_COUNT" -ge "$CONSECUTIVE_BAD" ]]; then
                    need_update=true
                    update_reason="质量恶化（连续${CONSECUTIVE_BAD}次延迟>${MONITOR_THRESHOLD}ms）"
                fi
            else
                # 质量良好，重置计数
                if [[ "$CONSECUTIVE_BAD_COUNT" -gt 0 ]]; then
                    log "✓ 质量恢复 (${current_delay}ms)"
                    CONSECUTIVE_BAD_COUNT=0
                fi
            fi
            
            next_monitor_check=$((current_time + MONITOR_INTERVAL))
        fi
        
        # 执行更新
        if [[ "$need_update" == true ]]; then
            log "触发更新: $update_reason"
            if full_update; then
                next_full_check=$(($(date +%s) + FULL_CHECK_INTERVAL))
                CURRENT_IP=$(get_current_ip)
            fi
        fi
        
        # 等待下次检查（最多等待60秒，以便及时响应）
        local sleep_time=60
        local time_to_monitor=$((next_monitor_check - $(date +%s)))
        local time_to_full=$((next_full_check - $(date +%s)))
        
        if [[ "$time_to_monitor" -lt "$sleep_time" ]] && [[ "$time_to_monitor" -gt 0 ]]; then
            sleep_time=$time_to_monitor
        fi
        
        sleep "$sleep_time"
    done
}

# 停止调度器
stop_scheduler() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            rm -f "$PID_FILE"
            echo "✓ 调度器已停止"
        else
            echo "调度器未运行"
            rm -f "$PID_FILE"
        fi
    else
        echo "调度器未运行"
    fi
}

# 查看状态
show_status() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            echo "✓ 调度器运行中 (PID: $pid)"
            echo ""
            echo "最近日志:"
            tail -10 "$SCHEDULER_LOG" 2>/dev/null || echo "暂无日志"
        else
            echo "✗ 调度器未运行"
            rm -f "$PID_FILE"
        fi
    else
        echo "✗ 调度器未运行"
    fi
}

# 主程序
case "${1:-}" in
    start)
        if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
            echo "调度器已在运行 (PID: $(cat "$PID_FILE"))"
            exit 1
        fi
        
        # 检查 auto_update_hosts.sh 是否配置了域名
        if grep -q "your-domain.com" "${CFST_DIR}/auto_update_hosts.sh"; then
            echo "⚠️  请先配置域名!"
            echo "   编辑 auto_update_hosts.sh，修改 TARGET_DOMAINS"
            exit 1
        fi
        
        # 后台启动
        nohup bash -c "cd '$CFST_DIR' && source '$0' _run" > /dev/null 2>&1 &
        echo $! > "$PID_FILE"
        echo "✓ 调度器已启动 (PID: $(cat "$PID_FILE"))"
        echo "   查看日志: tail -f $SCHEDULER_LOG"
        ;;
    stop)
        stop_scheduler
        ;;
    status)
        show_status
        ;;
    log)
        tail -f "$SCHEDULER_LOG"
        ;;
    _run)
        # 内部命令：实际运行调度循环
        scheduler_loop
        ;;
    *)
        cat << 'EOF'
CloudflareSpeedTest 调度器 - 智能混合策略

策略说明:
    1. 每24小时执行一次完整测速（保底更新）
    2. 每3分钟检测一次当前IP质量
    3. 如果连续3次检测延迟>200ms，立即触发更新

用法: ./scheduler.sh [命令]

命令:
    start      启动调度器（后台运行）
    stop       停止调度器
    status     查看状态
    log        查看实时日志

示例:
    ./scheduler.sh start    # 启动
    ./scheduler.sh status   # 查看状态
    ./scheduler.sh log      # 查看日志

EOF
        ;;
esac
