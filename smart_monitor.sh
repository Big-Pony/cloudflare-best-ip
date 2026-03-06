#!/bin/bash
# =============================================================================
# CloudflareSpeedTest 智能监控 - 相对阈值策略
# 策略:
#   1. 当前延迟 > 历史最优 * 2 且 当前延迟 > 300ms → 触发更新
#   2. 当前延迟 < 300ms → 无论什么情况都不更新（质量保障）
#   3. 连续3次异常才触发（避免偶发波动）
# =============================================================================

set -euo pipefail

# 清理函数（异常退出时调用）
cleanup() {
    local exit_code=$?
    if [[ -f "$PID_FILE" ]]; then
        rm -f "$PID_FILE"
    fi
    # 记录退出原因
    if [[ $exit_code -ne 0 ]]; then
        log "监控异常退出，退出码: $exit_code"
    fi
    exit $exit_code
}

# 设置trap，捕获常见信号
trap cleanup EXIT INT TERM

CFST_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_FILE="${CFST_DIR}/.monitor_state"
LOG_FILE="${CFST_DIR}/smart_monitor.log"
IP_HISTORY_FILE="${CFST_DIR}/ip_history.log"
PID_FILE="${CFST_DIR}/.smart_monitor_pid"

# 配置
CHECK_INTERVAL=180          # 检测间隔: 3分钟
CONSECUTIVE_BAD=3           # 连续异常次数触发更新
MIN_UPDATE_INTERVAL=1800    # 最少间隔30分钟才允许更新
BASELINE_THRESHOLD=300      # 基础质量线: 低于此值不触发
DEGRADE_MULTIPLIER=2        # 恶化倍数: 当前 > 历史最优 * 2
LOG_MAX_LINES=1000          # 日志文件最大行数

# 日志函数（带日志轮转）
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
    
    # 日志轮转：超过最大行数时保留后50%
    if [[ -f "$LOG_FILE" ]]; then
        local line_count=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
        if [[ "$line_count" -gt "$LOG_MAX_LINES" ]]; then
            tail -n $((LOG_MAX_LINES / 2)) "$LOG_FILE" > "${LOG_FILE}.tmp" && \
            mv "${LOG_FILE}.tmp" "$LOG_FILE"
        fi
    fi
}

# 记录IP切换历史
log_ip_change() {
    local time_str="$1"
    local old_ip="$2"
    local old_latency="$3"
    local new_ip="$4"
    local new_latency="$5"
    
    # 格式: 时间 | 旧IP | 旧延迟 | 新IP | 新延迟
    echo "${time_str} | ${old_ip} | ${old_latency}ms | ${new_ip} | ${new_latency}ms" >> "$IP_HISTORY_FILE"
    
    # 保留最近100条记录
    if [[ -f "$IP_HISTORY_FILE" ]]; then
        local line_count=$(wc -l < "$IP_HISTORY_FILE" 2>/dev/null || echo 0)
        if [[ "$line_count" -gt 100 ]]; then
            tail -n 100 "$IP_HISTORY_FILE" > "${IP_HISTORY_FILE}.tmp" && \
            mv "${IP_HISTORY_FILE}.tmp" "$IP_HISTORY_FILE"
        fi
    fi
}

# 保存状态 (IP, 历史最优延迟, 上次更新时间, 连续异常计数)
save_state() {
    local ip="${1:-}"
    local best="${2:-9999}"
    local last_time="${3:-0}"
    local bad_count="${4:-0}"
    
    cat > "$STATE_FILE" << EOF
CURRENT_IP=${ip}
HISTORY_BEST=${best}
LAST_UPDATE_TIME=${last_time}
BAD_COUNT=${bad_count}
EOF
}

# 加载状态
load_state() {
    if [[ -f "$STATE_FILE" ]]; then
        # 安全加载，防止文件损坏
        if source "$STATE_FILE" 2>/dev/null; then
            : # 加载成功
        else
            log "警告: 状态文件损坏，使用默认值"
            CURRENT_IP=""
            HISTORY_BEST=9999
            LAST_UPDATE_TIME=0
            BAD_COUNT=0
        fi
    fi
    CURRENT_IP=${CURRENT_IP:-}
    HISTORY_BEST=${HISTORY_BEST:-9999}
    LAST_UPDATE_TIME=${LAST_UPDATE_TIME:-0}
    BAD_COUNT=${BAD_COUNT:-0}
}

# 获取当前IP
get_current_ip() {
    local domain
    # 从auto_update_hosts.sh中提取第一个配置的域名
    domain=$(grep -A3 "TARGET_DOMAINS=" "${CFST_DIR}/auto_update_hosts.sh" 2>/dev/null | \
             grep '"' | head -1 | sed 's/.*"\([^"]*\)".*/\1/' | tr -d ' ')
    
    if [[ -z "$domain" ]] || [[ "$domain" == "your-domain.com" ]] || [[ "$domain" == "example.com" ]]; then
        log "错误: 域名未配置或仍为示例值 (domain='${domain}')"
        return 1
    fi
    
    local ip
    ip=$(grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+${domain}" /etc/hosts 2>/dev/null | \
         awk '{print $1}' | head -1)
    
    if [[ -z "$ip" ]]; then
        log "错误: 在hosts文件中未找到域名 '${domain}' 的IP"
        return 1
    fi
    
    echo "$ip"
}

# 检测当前IP延迟 (ping 5次取平均)
check_latency() {
    local ip=$1
    
    if [[ -z "$ip" ]]; then
        echo "9999"
        return
    fi
    
    local result
    result=$(ping -c 5 -i 0.2 -W 2 "$ip" 2>/dev/null | grep 'round-trip' || echo "")
    
    if [[ -z "$result" ]]; then
        echo "9999"  # ping失败
    else
        # 提取平均延迟
        echo "$result" | awk -F'/' '{print $5}' | cut -d'.' -f1
    fi
}

# 记录历史延迟
record_history() {
    local latency=$1
    echo "$(date +%s) $latency" >> "${CFST_DIR}/.latency_history"
    # 保留最近100条
    if [[ -f "${CFST_DIR}/.latency_history" ]]; then
        local line_count
        line_count=$(wc -l < "${CFST_DIR}/.latency_history" 2>/dev/null || echo 0)
        if [[ "$line_count" -gt 100 ]]; then
            tail -n 100 "${CFST_DIR}/.latency_history" > "${CFST_DIR}/.latency_history.tmp" && \
            mv "${CFST_DIR}/.latency_history.tmp" "${CFST_DIR}/.latency_history"
        fi
    fi
}

# 判断是否需要更新
need_update() {
    local current_ip
    current_ip=$(get_current_ip)
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    CURRENT_IP=$current_ip
    
    # 检测当前延迟
    local current_latency
    current_latency=$(check_latency "$current_ip")
    record_history "$current_latency"
    
    log "检测: IP=$current_ip, 当前延迟=${current_latency}ms, 历史最优=${HISTORY_BEST}ms"
    
    # 规则1: 如果 < 300ms，不触发更新（基础质量保障）
    if [[ "$current_latency" -lt "$BASELINE_THRESHOLD" ]]; then
        if [[ "$BAD_COUNT" -gt 0 ]]; then
            log "✓ 质量恢复 (${current_latency}ms < ${BASELINE_THRESHOLD}ms)，重置异常计数"
            BAD_COUNT=0
            save_state "$CURRENT_IP" "$HISTORY_BEST" "$LAST_UPDATE_TIME" "$BAD_COUNT"
        fi
        return 1
    fi
    
    # 规则2: 如果当前延迟 > 历史最优 * 2，说明IP质量恶化
    local degrade_threshold=$((HISTORY_BEST * DEGRADE_MULTIPLIER))
    
    if [[ "$current_latency" -gt "$degrade_threshold" ]]; then
        BAD_COUNT=$((BAD_COUNT + 1))
        log "⚠️ 质量恶化: ${current_latency}ms > ${degrade_threshold}ms (最优${HISTORY_BEST}ms * ${DEGRADE_MULTIPLIER})"
        log "   连续异常: ${BAD_COUNT}/${CONSECUTIVE_BAD}"
        
        if [[ "$BAD_COUNT" -ge "$CONSECUTIVE_BAD" ]]; then
            # 检查最小更新间隔
            local current_time
            current_time=$(date +%s)
            local time_since_last=$((current_time - LAST_UPDATE_TIME))
            
            if [[ "$time_since_last" -lt "$MIN_UPDATE_INTERVAL" ]]; then
                log "   距离上次更新仅${time_since_last}秒，继续监控..."
                save_state "$CURRENT_IP" "$HISTORY_BEST" "$LAST_UPDATE_TIME" "$BAD_COUNT"
                return 1
            fi
            
            log "🔄 触发条件满足，准备更新IP"
            save_state "$CURRENT_IP" "$HISTORY_BEST" "$LAST_UPDATE_TIME" "$BAD_COUNT"
            return 0
        fi
    else
        # 延迟高但还没恶化到阈值（比如历史最优150ms，当前250ms）
        log "当前延迟较高(${current_latency}ms)但未恶化(${degrade_threshold}ms阈值)"
        if [[ "$BAD_COUNT" -gt 0 ]]; then
            BAD_COUNT=$((BAD_COUNT - 1))
        fi
    fi
    
    save_state "$CURRENT_IP" "$HISTORY_BEST" "$LAST_UPDATE_TIME" "$BAD_COUNT"
    return 1
}

# 执行完整测速更新
perform_update() {
    log "=== 开始完整测速更新 ==="
    
    # 记录当前IP和延迟
    local old_ip=$CURRENT_IP
    local old_latency
    old_latency=$(check_latency "$old_ip")
    local update_time
    update_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    log "更新前: IP=$old_ip, 延迟=${old_latency}ms"
    
    # 执行测速
    if sudo "${CFST_DIR}/auto_update_hosts.sh" >> "$LOG_FILE" 2>&1; then
        # 获取新IP
        local new_ip
        new_ip=$(get_current_ip)
        if [[ $? -ne 0 ]]; then
            log "✗ 获取新IP失败"
            return 1
        fi
        
        local new_latency
        new_latency=$(check_latency "$new_ip")
        
        log "更新后: IP=$new_ip, 延迟=${new_latency}ms"
        
        # 记录IP切换历史
        log_ip_change "$update_time" "$old_ip" "$old_latency" "$new_ip" "$new_latency"
        
        # 更新状态
        CURRENT_IP=$new_ip
        HISTORY_BEST=$new_latency
        LAST_UPDATE_TIME=$(date +%s)
        BAD_COUNT=0
        save_state "$CURRENT_IP" "$HISTORY_BEST" "$LAST_UPDATE_TIME" "$BAD_COUNT"
        
        # 通知
        if [[ "$OSTYPE" == "darwin"* ]]; then
            osascript -e "display notification \"IP: $old_ip → $new_ip (${new_latency}ms)\" with title \"CFST更新成功\"" 2>/dev/null || true
        fi
        
        log "✓ 更新成功，已记录到 ip_history.log"
        return 0
    else
        log "✗ 测速失败"
        return 1
    fi
}

# 初始化
init() {
    load_state
    
    # 首次运行，没有历史数据，执行一次完整测速建立基准
    if [[ "$HISTORY_BEST" == "9999" ]] || [[ -z "$CURRENT_IP" ]]; then
        log "首次运行，执行完整测速建立基准..."
        CURRENT_IP=$(get_current_ip) || {
            log "错误: 无法获取当前IP，请检查域名配置"
            exit 1
        }
        if [[ -n "$CURRENT_IP" ]]; then
            local current_latency
            current_latency=$(check_latency "$CURRENT_IP")
            HISTORY_BEST=$current_latency
            LAST_UPDATE_TIME=$(date +%s)
            save_state "$CURRENT_IP" "$HISTORY_BEST" "$LAST_UPDATE_TIME" 0
            log "基准建立: IP=$CURRENT_IP, 延迟=${HISTORY_BEST}ms"
        fi
    fi
}

# 主循环
monitor_loop() {
    init
    
    log "=== 智能监控启动 ==="
    log "策略: 延迟 > 最优*${DEGRADE_MULTIPLIER} 且 > ${BASELINE_THRESHOLD}ms 才触发"
    log "检测间隔: ${CHECK_INTERVAL}秒"
    
    echo $$ > "$PID_FILE"
    
    # 主循环
    while true; do
        if need_update; then
            perform_update || true  # 更新失败不退出
        fi
        
        # 使用sleep，可以被信号中断
        sleep "$CHECK_INTERVAL" &
        wait $! || true
    done
}

# 显示统计
show_stats() {
    echo "=== 智能监控统计 ==="
    echo ""
    
    load_state
    
    echo "当前状态:"
    echo "  IP: ${CURRENT_IP:-未设置}"
    echo "  历史最优延迟: ${HISTORY_BEST}ms"
    echo "  上次更新: $(date -r "$LAST_UPDATE_TIME" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '从未')"
    echo "  连续异常: ${BAD_COUNT}次"
    echo ""
    echo "阈值配置:"
    echo "  基础质量线: ${BASELINE_THRESHOLD}ms (低于此不触发)"
    echo "  恶化倍数: ${DEGRADE_MULTIPLIER}x (当前 > 最优*${DEGRADE_MULTIPLIER})"
    echo "  连续异常: ${CONSECUTIVE_BAD}次才触发"
    echo "  最小更新间隔: ${MIN_UPDATE_INTERVAL}秒"
    
    if [[ -f "${CFST_DIR}/.latency_history" ]]; then
        echo ""
        echo "最近10次检测:"
        echo "时间                延迟(ms)"
        echo "----------------------------"
        tail -10 "${CFST_DIR}/.latency_history" 2>/dev/null | while read -r ts latency; do
            printf "%s  %sms\n" "$(date -r "$ts" '+%m-%d %H:%M' 2>/dev/null || echo 'unknown')" "$latency"
        done
    fi
    
    # 显示IP切换历史
    if [[ -f "$IP_HISTORY_FILE" ]]; then
        echo ""
        echo "IP切换历史 (最近10条):"
        echo "时间                  旧IP              旧延迟   新IP              新延迟"
        echo "--------------------------------------------------------------------------------"
        tail -10 "$IP_HISTORY_FILE" 2>/dev/null | while IFS='|' read -r time_str old_ip old_lat new_ip new_lat; do
            printf "%-20s %-17s %-8s %-17s %s\n" "${time_str// /}" "${old_ip// /}" "${old_lat// /}" "${new_ip// /}" "${new_lat// /}"
        done
    fi
}

# 停止监控
stop_monitor() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
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
        local pid
        pid=$(cat "$PID_FILE")
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
        if [[ -f "$PID_FILE" ]]; then
            local pid
            pid=$(cat "$PID_FILE")
            if kill -0 "$pid" 2>/dev/null; then
                echo "监控已在运行 (PID: $pid)"
                exit 1
            fi
        fi
        
        # 后台运行
        nohup bash "$0" _run > /dev/null 2>&1 &
        echo "✓ 监控已启动 (PID: $!)"
        echo "  查看日志: tail -f $LOG_FILE"
        ;;
    _run)
        monitor_loop
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
    check)
        load_state
        if need_update; then
            perform_update
        else
            echo "当前质量良好，无需更新"
        fi
        ;;
    log)
        tail -f "$LOG_FILE"
        ;;
    history)
        if [[ -f "$IP_HISTORY_FILE" ]]; then
            echo "IP切换历史:"
            echo "时间                  旧IP              旧延迟   新IP              新延迟"
            echo "--------------------------------------------------------------------------------"
            cat "$IP_HISTORY_FILE"
        else
            echo "暂无IP切换记录"
        fi
        ;;
    *)
        cat << 'EOF'
CloudflareSpeedTest 智能监控 - 相对阈值策略

判断逻辑:
    1. 当前延迟 < 300ms → 不更新（质量保障）
    2. 当前延迟 > 历史最优 * 2 → 异常计数+1
    3. 连续3次异常 → 触发完整测速更新

特点:
    ✓ 自适应不同网络环境（无论基础延迟是50ms还是300ms）
    ✓ 基础质量保护（<300ms绝不折腾）
    ✓ 避免偶发波动（连续3次确认）
    ✓ 日志轮转（防止日志文件无限增长）

用法: ./smart_monitor.sh [命令]

命令:
    start      启动后台监控
    stop       停止监控
    status     查看运行状态
    stats      查看详细统计（含IP切换历史）
    check      立即执行一次检测
    log        查看实时日志
    history    查看IP切换历史

EOF
        ;;
esac
