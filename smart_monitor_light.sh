#!/bin/bash
# =============================================================================
# CloudflareSpeedTest 智能监控 - 轻量版
# 适合低功耗设备（路由器/NAS/笔记本省电模式）
# =============================================================================

set -euo pipefail

CFST_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${CFST_DIR}/smart_monitor.sh" 2>/dev/null || true

# 轻量版配置（覆盖默认配置）
CHECK_INTERVAL=300          # 检测间隔: 5分钟（更省电）
PING_COUNT=3                # ping包数: 3个（更快）
PING_INTERVAL=0.5           # ping间隔: 0.5秒（更慢但省电）

# 轻量版检测函数
check_latency_light() {
    local ip=$1
    # 只发3个包，间隔0.5秒，超时1秒
    local result=$(ping -c $PING_COUNT -i $PING_INTERVAL -W 1 "$ip" 2>/dev/null | grep 'round-trip' || echo "")
    
    if [[ -z "$result" ]]; then
        echo "9999"
    else
        echo "$result" | awk -F'/' '{print $5}' | cut -d'.' -f1
    fi
}

echo "=== 轻量版智能监控 ==="
echo "配置:"
echo "  检测间隔: ${CHECK_INTERVAL}秒 (5分钟)"
echo "  Ping包数: ${PING_COUNT}个"
echo "  预估单次耗时: ~1.5秒"
echo "  每天总耗时: ~18分钟"
echo ""
