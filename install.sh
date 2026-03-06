#!/bin/bash
# =============================================================================
# CloudflareSpeedTest 安装配置脚本
# 自动检测路径并配置 plist 文件
# =============================================================================

set -euo pipefail

CFST_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_SOURCE="${CFST_DIR}/com.user.cfst.update.plist"
PLIST_DEST="${HOME}/Library/LaunchAgents/com.user.cfst.update.plist"

color_green() { echo -e "\033[32m$1\033[0m"; }
color_red() { echo -e "\033[31m$1\033[0m"; }
color_yellow() { echo -e "\033[33m$1\033[0m"; }

echo ""
echo "=== CloudflareSpeedTest 安装配置 ==="
echo ""

# 检查域名配置
echo "1. 检查域名配置..."
CURRENT_DOMAIN=$(grep -A2 "TARGET_DOMAINS=" "${CFST_DIR}/auto_update_hosts.sh" | grep '"' | head -1 | tr -d '"' | tr -d ' ')
if [[ "$CURRENT_DOMAIN" == "your-domain.com" ]]; then
    color_yellow "⚠️  域名未配置，当前是示例: your-domain.com"
    read -p "请输入你的域名 (例如: example.com): " DOMAIN
    if [[ -n "$DOMAIN" ]]; then
        sed -i '' "s/\"your-domain.com\"/\"$DOMAIN\"/" "${CFST_DIR}/auto_update_hosts.sh"
        color_green "✓ 域名已设置为: $DOMAIN"
    else
        color_red "✗ 域名不能为空"
        exit 1
    fi
else
    color_green "✓ 当前域名: $CURRENT_DOMAIN"
    read -p "是否修改域名? [y/N]: " CHANGE_DOMAIN
    if [[ "$CHANGE_DOMAIN" =~ ^[Yy]$ ]]; then
        read -p "请输入新域名: " DOMAIN
        if [[ -n "$DOMAIN" ]]; then
            sed -i '' "s/\"$CURRENT_DOMAIN\"/\"$DOMAIN\"/" "${CFST_DIR}/auto_update_hosts.sh"
            color_green "✓ 域名已更新为: $DOMAIN"
        fi
    fi
fi

echo ""

# 配置 plist 文件（仅 macOS）
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "2. 配置定时任务..."
    
    # 创建临时 plist 文件，替换路径
    sed -e "s|/path/to/cfst|$CFST_DIR|g" "$PLIST_SOURCE" > "$PLIST_DEST"
    
    color_green "✓ 定时任务配置已生成: $PLIST_DEST"
    
    echo ""
    read -p "是否立即启动定时任务? [Y/n]: " START_SERVICE
    if [[ ! "$START_SERVICE" =~ ^[Nn]$ ]]; then
        launchctl unload "$PLIST_DEST" 2>/dev/null || true
        launchctl load "$PLIST_DEST"
        color_green "✓ 定时任务已启动"
    fi
else
    echo "2. 跳过定时任务配置（非 macOS 系统）"
    echo "   Linux 用户请使用 crontab 配置定时任务"
fi

echo ""
echo "=== 配置完成 ==="
echo ""
echo "使用方法:"
echo "  手动执行: sudo ${CFST_DIR}/auto_update_hosts.sh"
echo "  查看日志: tail -f ${CFST_DIR}/update.log"
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "  停止服务: launchctl unload $PLIST_DEST"
    echo "  启动服务: launchctl load $PLIST_DEST"
fi
echo ""

# 询问是否立即测试
read -p "是否立即运行测试? [y/N]: " RUN_TEST
if [[ "$RUN_TEST" =~ ^[Yy]$ ]]; then
    echo ""
    sudo "${CFST_DIR}/auto_update_hosts.sh"
fi
