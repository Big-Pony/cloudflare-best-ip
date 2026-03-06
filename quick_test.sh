#!/bin/bash
# 快速测速脚本 - 仅延迟测速

cd "$(dirname "$0")"

echo "=== 快速延迟测速模式 ==="
echo "不测下载速度，只按延迟排序..."
echo ""

# -dd: 禁用下载测速
# -n 500: 增加并发线程数
# -t 2: 每个IP测2次（默认4次）
# -tl 200: 只输出延迟<200ms的IP
# -p 10: 显示前10个结果
./cfst -dd -n 500 -t 2 -tl 200 -p 10 -o quick_result.csv

echo ""
echo "=== 最优 IP 结果 ==="
if [[ -f quick_result.csv ]]; then
    # 显示结果（跳过标题行）
    tail -n +2 quick_result.csv | head -5 | while IFS=',' read -r ip delay speed; do
        echo "IP: $ip | 延迟: ${delay}ms"
    done
    
    # 提取最优IP
    best_ip=$(sed -n '2p' quick_result.csv | cut -d',' -f1)
    echo ""
    echo "推荐 IP: $best_ip"
fi
