#!/bin/bash
# =============================================================================
# CloudflareSpeedTest 快速更新脚本
# 优化: 大幅减少测速时间
# =============================================================================

set -euo pipefail

CFST_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULT_FILE="${CFST_DIR}/fast_result.csv"
NOWIP_FILE="${CFST_DIR}/.nowip_cache"
LOG_FILE="${CFST_DIR}/update.log"
HOSTS_FILE="/etc/hosts"

# 目标域名
TARGET_DOMAINS=(
    "backup.mypayau.com"
)

# 日志函数
log() {
    local msg="[$(date '+%H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

# 检查权限
check_permission() {
    if [[ $EUID -ne 0 ]]; then
        echo "错误: 需要 root 权限"
        echo "请运行: sudo $0"
        exit 1
    fi
}

# 快速测速模式选择
show_menu() {
    echo ""
    echo "=== 快速测速模式 ==="
    echo ""
    echo "1) 极速模式 (仅延迟，约30秒)"
    echo "2) 快速模式 (延迟+少量下载，约1分钟)"
    echo "3) 精简IP模式 (只测优质IP段，约20秒)"
    echo "4) 自定义模式 (手动输入参数)"
    echo ""
    read -p "请选择模式 [1-4]: " choice
    
    case $choice in
        1) MODE="fastest" ;;
        2) MODE="fast" ;;
        3) MODE="minimal" ;;
        4) MODE="custom" ;;
        *) MODE="fast" ;;
    esac
}

# 执行测速
run_speedtest() {
    cd "$CFST_DIR"
    rm -f "$RESULT_FILE"
    
    case $MODE in
        fastest)
            log "模式: 极速模式 (仅延迟测速)"
            # -dd: 禁用下载测速
            # -n 500: 高并发线程
            # -t 2: 每个IP测2次
            # -tl 200: 延迟上限200ms
            ./cfst -dd -n 500 -t 2 -tl 200 -p 5 -o "$RESULT_FILE" -f ip.txt
            ;;
        fast)
            log "模式: 快速模式 (延迟+少量下载)"
            # -dn 3: 只给最快的3个IP测下载
            # -dt 5: 每个IP测5秒
            ./cfst -n 300 -t 2 -tl 200 -dn 3 -dt 5 -p 3 -o "$RESULT_FILE" -f ip.txt
            ;;
        minimal)
            log "模式: 精简IP模式 (只测优质IP段)"
            # 使用自定义的精简IP段
            ./cfst -dd -n 200 -t 2 -tl 300 -p 5 -o "$RESULT_FILE" -f cn_optimized_ips.txt
            ;;
        custom)
            log "模式: 自定义模式"
            read -p "输入cfst参数: " custom_args
            ./cfst $custom_args -o "$RESULT_FILE"
            ;;
    esac
}

# 更新 hosts
update_hosts() {
    local new_ip=$(sed -n '2p' "$RESULT_FILE" | cut -d',' -f1)
    
    if [[ -z "$new_ip" ]]; then
        log "错误: 未找到有效IP"
        exit 1
    fi
    
    log "最优 IP: $new_ip"
    
    # 检查是否已有配置
    local existing_ip=""
    for domain in "${TARGET_DOMAINS[@]}"; do
        existing_ip=$(grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+${domain}" "$HOSTS_FILE" | awk '{print $1}' | head -1)
        if [[ -n "$existing_ip" ]]; then
            break
        fi
    done
    
    if [[ -n "$existing_ip" ]]; then
        # 替换现有IP
        if [[ "$existing_ip" == "$new_ip" ]]; then
            log "IP 未变化 ($existing_ip)"
            return 0
        fi
        
        log "替换: $existing_ip -> $new_ip"
        sed -i '' "s/${existing_ip}/${new_ip}/g" "$HOSTS_FILE"
    else
        # 添加新配置
        log "添加新配置: $new_ip -> ${TARGET_DOMAINS[0]}"
        echo "$new_ip ${TARGET_DOMAINS[0]}" >> "$HOSTS_FILE"
    fi
    
    # 刷新DNS缓存
    dscacheutil -flushcache 2>/dev/null || true
    killall -HUP mDNSResponder 2>/dev/null || true
    log "DNS缓存已刷新"
}

# 显示结果
show_result() {
    echo ""
    log "=== 测速结果 TOP 5 ==="
    echo "IP地址          延迟(ms)  速度(MB/s)"
    echo "----------------------------------------"
    tail -n +2 "$RESULT_FILE" | head -5 | while IFS=',' read -r ip delay speed; do
        printf "%-15s %-9s %s\n" "$ip" "${delay}ms" "${speed}"
    done
}

# 主程序
main() {
    check_permission
    
    # 如果有参数直接执行，否则显示菜单
    if [[ $# -eq 0 ]]; then
        show_menu
    else
        MODE="$1"
    fi
    
    log "=========================================="
    log "开始快速测速 [模式: $MODE]"
    log "=========================================="
    
    run_speedtest
    show_result
    update_hosts
    
    log "完成!"
    echo ""
    echo "当前 hosts 配置:"
    grep "backup.mypayau.com" "$HOSTS_FILE" || echo "未找到"
}

main "$@"
