#!/usr/bin/env bash
# =============================================================================
# CloudflareSpeedTest 定时任务管理脚本
# 功能: 安装、启动、停止、卸载自动更新服务
# =============================================================================

set -euo pipefail

CFST_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_NAME="com.user.cfst.update.plist"
PLIST_SOURCE="${CFST_DIR}/${PLIST_NAME}"
PLIST_DEST="${HOME}/Library/LaunchAgents/${PLIST_NAME}"

color_green() { echo -e "\033[32m$1\033[0m"; }
color_red() { echo -e "\033[31m$1\033[0m"; }
color_yellow() { echo -e "\033[33m$1\033[0m"; }

show_help() {
    cat << 'EOF'
CloudflareSpeedTest 定时任务管理脚本

用法: ./manage_service.sh [命令]

命令:
    install     安装并启动定时任务
    uninstall   停止并卸载定时任务
    start       启动定时任务
    stop        停止定时任务
    run         立即执行一次更新
    status      查看任务状态
    logs        查看日志
    edit        编辑脚本配置

示例:
    ./manage_service.sh install    # 安装服务
    ./manage_service.sh run        # 立即执行一次
    ./manage_service.sh logs       # 查看日志

EOF
}

check_macos() {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        echo "错误: 此脚本仅适用于 macOS"
        exit 1
    fi
}

install_service() {
    echo "正在安装定时任务..."
    
    # 检查脚本是否存在
    if [[ ! -f "${CFST_DIR}/auto_update_hosts.sh" ]]; then
        color_red "错误: 未找到 auto_update_hosts.sh 脚本"
        exit 1
    fi
    
    # 复制 plist 文件
    cp "$PLIST_SOURCE" "$PLIST_DEST"
    
    # 加载任务
    launchctl load "$PLIST_DEST" 2>/dev/null || launchctl bootstrap gui/$(id -u) "$PLIST_DEST"
    
    color_green "✓ 定时任务已安装"
    echo ""
    echo "执行时间: 每天凌晨 3:00"
    echo "配置文件: $PLIST_DEST"
    echo ""
    echo "你可以通过以下命令管理:"
    echo "  查看状态: ./manage_service.sh status"
    echo "  立即执行: ./manage_service.sh run"
    echo "  停止任务: ./manage_service.sh stop"
}

uninstall_service() {
    echo "正在卸载定时任务..."
    
    # 停止任务
    launchctl unload "$PLIST_DEST" 2>/dev/null || true
    launchctl bootout gui/$(id -u)/com.user.cfst.update 2>/dev/null || true
    
    # 删除 plist 文件
    rm -f "$PLIST_DEST"
    
    color_green "✓ 定时任务已卸载"
}

start_service() {
    echo "正在启动定时任务..."
    launchctl load "$PLIST_DEST" 2>/dev/null || launchctl bootstrap gui/$(id -u) "$PLIST_DEST"
    color_green "✓ 定时任务已启动"
}

stop_service() {
    echo "正在停止定时任务..."
    launchctl unload "$PLIST_DEST" 2>/dev/null || launchctl bootout gui/$(id -u)/com.user.cfst.update 2>/dev/null || true
    color_green "✓ 定时任务已停止"
}

run_now() {
    echo "正在执行更新..."
    echo "=========================================="
    sudo "${CFST_DIR}/auto_update_hosts.sh"
}

show_status() {
    echo "=========================================="
    echo "任务状态"
    echo "=========================================="
    
    if [[ -f "$PLIST_DEST" ]]; then
        color_green "✓ 服务已安装"
        
        # 检查是否正在运行
        if launchctl list | grep -q "com.user.cfst.update"; then
            color_green "✓ 服务正在运行"
        else
            color_yellow "⚠ 服务未运行"
        fi
    else
        color_red "✗ 服务未安装"
    fi
    
    echo ""
    echo "下次执行时间:"
    launchctl list com.user.cfst.update 2>/dev/null || echo "  无法获取"
    
    echo ""
    echo "最近日志:"
    if [[ -f "${CFST_DIR}/update.log" ]]; then
        tail -10 "${CFST_DIR}/update.log"
    else
        echo "  暂无日志"
    fi
}

show_logs() {
    if [[ -f "${CFST_DIR}/update.log" ]]; then
        echo "按 Ctrl+C 退出日志查看"
        tail -f "${CFST_DIR}/update.log"
    else
        echo "暂无日志文件"
    fi
}

edit_config() {
    local editor="${EDITOR:-vi}"
    $editor "${CFST_DIR}/auto_update_hosts.sh"
}

# 主程序
case "${1:-help}" in
    install)
        check_macos
        install_service
        ;;
    uninstall)
        check_macos
        uninstall_service
        ;;
    start)
        check_macos
        start_service
        ;;
    stop)
        check_macos
        stop_service
        ;;
    run)
        run_now
        ;;
    status)
        check_macos
        show_status
        ;;
    logs)
        show_logs
        ;;
    edit)
        edit_config
        ;;
    help|--help|-h|*)
        show_help
        ;;
esac
