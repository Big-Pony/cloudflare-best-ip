#!/usr/bin/env bash
# =============================================================================
# CloudflareSpeedTest 自动更新 Hosts 脚本
# 功能: 定期测速并自动替换 Hosts 中的 Cloudflare CDN IP
# 作者: 基于 XIU2 的脚本优化
# =============================================================================

set -euo pipefail

# 配置项
CFST_DIR="$(cd "$(dirname "$0")" && pwd)"
RESULT_FILE="${CFST_DIR}/result_hosts.csv"
NOWIP_FILE="${CFST_DIR}/.nowip_cache"
LOG_FILE="${CFST_DIR}/update.log"
HOSTS_FILE="/etc/hosts"
BACKUP_DIR="${CFST_DIR}/hosts_backup"

# CloudflareSpeedTest 参数配置（可根据需求调整）
# 快速模式: 仅延迟测速 (约30秒)
CFST_ARGS="-dd -n 500 -t 2 -tl 200 -o ${RESULT_FILE}"
# 完整模式(较慢): -tl 200 -dn 10 -dt 10 -o ${RESULT_FILE}

# 目标域名列表（⚠️ 修改为你需要加速的域名）
TARGET_DOMAINS=(
    "backup.mypayau.com"
    # "www.your-domain.com"
    # "api.your-domain.com"
)

# =============================================================================
# 日志函数
# =============================================================================
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

# =============================================================================
# 检查权限
# =============================================================================
check_permission() {
    if [[ $EUID -ne 0 ]]; then
        log "错误: 需要 root 权限来修改 /etc/hosts 文件"
        log "请使用: sudo $0"
        exit 1
    fi
}

# =============================================================================
# 初始化检查
# =============================================================================
init_check() {
    cd "$CFST_DIR"
    
    # 检查 cfst 是否存在
    if [[ ! -f "./cfst" ]]; then
        log "错误: 未找到 cfst 程序"
        exit 1
    fi
    
    # 创建备份目录
    mkdir -p "$BACKUP_DIR"
    
    # 检查目标域名是否已配置（不是示例域名）
    if [[ ${#TARGET_DOMAINS[@]} -eq 0 ]] || [[ "${TARGET_DOMAINS[0]}" == "your-domain.com" ]] || [[ "${TARGET_DOMAINS[0]}" == "example.com" ]]; then
        log "警告: 请先在脚本中配置 TARGET_DOMAINS 目标域名"
        exit 1
    fi
    
    # 如果缓存文件不存在，尝试从 hosts 文件读取现有 IP
    if [[ ! -e "$NOWIP_FILE" ]]; then
        log "首次运行，尝试从 hosts 文件读取现有 Cloudflare IP..."
        
        # 尝试找到已配置的 IP
        for domain in "${TARGET_DOMAINS[@]}"; do
            local existing_ip=$(grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+[[:space:]]+${domain}" "$HOSTS_FILE" | awk '{print $1}' | head -1)
            if [[ -n "$existing_ip" ]]; then
                log "找到现有 IP: $existing_ip (域名: $domain)"
                echo "$existing_ip" > "$NOWIP_FILE"
                break
            fi
        done
        
        # 如果 hosts 中没有找到，使用默认 IP
        if [[ ! -e "$NOWIP_FILE" ]]; then
            log "hosts 中未找到配置，使用默认 IP: 104.16.80.100"
            echo "104.16.80.100" > "$NOWIP_FILE"
            
            # 自动添加到 hosts
            log "自动添加域名到 hosts 文件..."
            for domain in "${TARGET_DOMAINS[@]}"; do
                if ! grep -q "$domain" "$HOSTS_FILE"; then
                    echo "104.16.80.100 ${domain}" >> "$HOSTS_FILE"
                    log "已添加: 104.16.80.100 ${domain}"
                fi
            done
        fi
    fi
}

# =============================================================================
# 执行测速
# =============================================================================
run_speedtest() {
    log "开始测速..."
    log "测速参数: $CFST_ARGS"
    
    # 清理旧结果
    rm -f "$RESULT_FILE"
    
    # 执行测速
    if ! ./cfst $CFST_ARGS; then
        log "错误: 测速程序执行失败"
        exit 1
    fi
    
    # 检查结果文件
    if [[ ! -f "$RESULT_FILE" ]]; then
        log "错误: 测速结果文件不存在"
        exit 1
    fi
    
    # 检查结果行数（第一行是标题）
    local line_count=$(wc -l < "$RESULT_FILE" | tr -d ' ')
    if [[ "$line_count" -le 1 ]]; then
        log "警告: 没有找到满足条件的 IP，跳过更新"
        exit 0
    fi
}

# =============================================================================
# 获取最优 IP
# =============================================================================
get_best_ip() {
    # 从结果文件读取最优 IP（第二行第一列）
    local best_ip=$(sed -n '2p' "$RESULT_FILE" | cut -d',' -f1)
    
    if [[ -z "$best_ip" ]]; then
        log "错误: 无法从结果文件中提取 IP"
        exit 1
    fi
    
    echo "$best_ip"
}

# =============================================================================
# 更新 Hosts 文件
# =============================================================================
update_hosts() {
    local old_ip=$(cat "$NOWIP_FILE")
    local new_ip=$1
    
    # 如果 IP 没有变化，跳过
    if [[ "$old_ip" == "$new_ip" ]]; then
        log "IP 未变化 ($old_ip)，无需更新"
        return 0
    fi
    
    log "旧 IP: $old_ip"
    log "新 IP: $new_ip"
    
    # 备份 hosts 文件（带时间戳）
    local backup_file="${BACKUP_DIR}/hosts_$(date +%Y%m%d_%H%M%S)"
    cp "$HOSTS_FILE" "$backup_file"
    log "已备份 hosts 到: $backup_file"
    
    # 替换 IP（兼容 macOS 和 Linux）
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/${old_ip}/${new_ip}/g" "$HOSTS_FILE"
    else
        # Linux
        sed -i "s/${old_ip}/${new_ip}/g" "$HOSTS_FILE"
    fi
    
    # 更新缓存
    echo "$new_ip" > "$NOWIP_FILE"
    
    log "hosts 文件更新成功"
    
    # 显示更新后的记录
    log "更新后的记录:"
    for domain in "${TARGET_DOMAINS[@]}"; do
        local line=$(grep "$domain" "$HOSTS_FILE" | head -1)
        log "  $line"
    done
    
    # 刷新 DNS 缓存（macOS）
    if [[ "$OSTYPE" == "darwin"* ]]; then
        log "刷新 DNS 缓存..."
        dscacheutil -flushcache 2>/dev/null || true
        killall -HUP mDNSResponder 2>/dev/null || true
        log "DNS 缓存已刷新"
    fi
}

# =============================================================================
# 清理旧备份（保留最近 10 个）
# =============================================================================
cleanup_backups() {
    local backup_count=$(ls -1 "$BACKUP_DIR"/hosts_* 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$backup_count" -gt 10 ]]; then
        ls -1t "$BACKUP_DIR"/hosts_* | tail -n +11 | xargs rm -f
        log "已清理旧备份文件，保留最近 10 个"
    fi
}

# =============================================================================
# 显示测速结果摘要
# =============================================================================
show_summary() {
    log "=== 测速结果摘要 ==="
    log "IP, 延迟(ms), 下载速度(MB/s)"
    sed -n '2,6p' "$RESULT_FILE" | while IFS=',' read -r ip delay speed; do
        log "  $ip, ${delay}ms, ${speed}MB/s"
    done
}

# =============================================================================
# 主程序
# =============================================================================
main() {
    log "=========================================="
    log "CloudflareSpeedTest 自动更新任务开始"
    log "=========================================="
    
    check_permission
    init_check
    run_speedtest
    
    local best_ip=$(get_best_ip)
    show_summary
    update_hosts "$best_ip"
    cleanup_backups
    
    log "=========================================="
    log "任务完成"
    log "=========================================="
}

# 执行主程序
main "$@"
