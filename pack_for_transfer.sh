#!/bin/bash
# =============================================================================
# 打包脚本 - 用于将配置好的项目打包，方便复制到其他电脑
# =============================================================================

set -euo pipefail

CFST_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_NAME="cfst_auto_update_$(date +%Y%m%d).tar.gz"

echo "=== CloudflareSpeedTest 打包工具 ==="
echo ""

# 清理旧日志和临时文件
echo "清理临时文件..."
rm -f "${CFST_DIR}"/*.csv
rm -f "${CFST_DIR}"/.nowip_cache
rm -f "${CFST_DIR}"/update*.log
rm -f "${CFST_DIR}"/*.error.log

# 创建打包清单
cat > "${CFST_DIR}/MANIFEST.txt" << 'EOF'
CloudflareSpeedTest 自动优选 IP 方案
=====================================

打包时间: PACKAGE_TIME
域名配置: TARGET_DOMAIN

包含文件:
- cfst: CloudflareSpeedTest 主程序
- ip.txt / ipv6.txt: IP段数据
- auto_update_hosts.sh: 自动更新脚本（已配置）
- com.user.cfst.update.plist: macOS定时任务配置
- fast_update.sh: 快速交互式脚本
- quick_test.sh: 快速测速脚本
- cn_optimized_ips.txt: 国内优化IP段
- manage_service.sh: 服务管理工具
- README.md: 完整使用文档

快速开始:
1. 解压后进入目录
2. 检查 auto_update_hosts.sh 中的域名配置
3. 运行: sudo ./auto_update_hosts.sh
4. 安装定时任务（见 README.md）

更多信息请查看 README.md
EOF

# 替换变量
DOMAIN=$(grep -A2 "TARGET_DOMAINS=" "${CFST_DIR}/auto_update_hosts.sh" | grep '"' | head -1 | tr -d '"')
sed -i '' "s/PACKAGE_TIME/$(date '+%Y-%m-%d %H:%M:%S')/" "${CFST_DIR}/MANIFEST.txt"
sed -i '' "s/TARGET_DOMAIN/${DOMAIN}/" "${CFST_DIR}/MANIFEST.txt"

# 打包
echo "正在打包..."
cd "${CFST_DIR}"
tar -czf "${PACKAGE_NAME}" \
    cfst \
    ip.txt \
    ipv6.txt \
    auto_update_hosts.sh \
    com.user.cfst.update.plist \
    fast_update.sh \
    quick_test.sh \
    cn_optimized_ips.txt \
    manage_service.sh \
    README.md \
    MANIFEST.txt \
    AUTO_UPDATE_README.md

# 清理临时文件
rm -f "${CFST_DIR}/MANIFEST.txt"

# 输出结果
echo ""
echo "=== 打包完成 ==="
echo ""
echo "文件名: ${PACKAGE_NAME}"
echo "位置: ${CFST_DIR}/${PACKAGE_NAME}"
echo "大小: $(du -h "${CFST_DIR}/${PACKAGE_NAME}" | cut -f1)"
echo ""
echo "你可以将这个文件复制到其他电脑使用:"
echo "  1. 复制文件到新电脑"
echo "  2. 解压: tar -xzf ${PACKAGE_NAME}"
echo "  3. 检查域名配置"
echo "  4. 运行: sudo ./auto_update_hosts.sh"
echo ""
