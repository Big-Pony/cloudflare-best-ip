#!/bin/bash
# =============================================================================
# GitHub Release 创建辅助脚本
# =============================================================================

set -euo pipefail

REPO="Big-Pony/cloudflare-best-ip"
TAG="v1.0.0"
PACKAGE="cfst_auto_update_20260306.tar.gz"

echo "=== GitHub Release 创建助手 ==="
echo ""
echo "仓库: $REPO"
echo "版本: $TAG"
echo "文件: $PACKAGE"
echo ""

# 检查 GitHub Token
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "⚠️  未设置 GITHUB_TOKEN 环境变量"
    echo ""
    echo "方法1: 设置环境变量后重新运行"
    echo "  export GITHUB_TOKEN=ghp_xxxxxxxxxxxx"
    echo "  ./create_release.sh"
    echo ""
    echo "方法2: 手动创建 Release"
    echo "  1. 访问: https://github.com/$REPO/releases/new"
    echo "  2. 点击 'Choose a tag' 选择 '$TAG'"
    echo "  3. Release title 输入: $TAG"
    echo "  4. 在下方上传文件: $PACKAGE"
    echo "  5. 点击 'Publish release'"
    echo ""
    exit 0
fi

echo "✓ GitHub Token 已设置"
echo ""

# 创建 release
echo "正在创建 Release..."
RELEASE_RESPONSE=$(curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  https://api.github.com/repos/$REPO/releases \
  -d "{
    \"tag_name\": \"$TAG\",
    \"name\": \"$TAG\",
    \"body\": \"CloudflareSpeedTest Auto Update Scripts $TAG\\n\\n## Features\\n- Fast mode: ~30s latency test (vs 10-20min original)\\n- Auto update /etc/hosts every 6 hours\\n- Cross-platform: macOS & Linux support\\n- Automatic backup and DNS flush\\n\\n## Quick Start\\n\\\`\\\`\\\`bash\\nsudo ./auto_update_hosts.sh\\n\\\`\\\`\\\`\\n\\nSee README.md for full documentation.\",
    \"draft\": false,
    \"prerelease\": false
  }")

# 检查响应
if echo "$RELEASE_RESPONSE" | grep -q "\"message\":\"Bad credentials\""; then
    echo "❌ GitHub Token 无效，请检查"
    exit 1
fi

if echo "$RELEASE_RESPONSE" | grep -q "already_exists"; then
    echo "⚠️  Release $TAG 已存在"
    UPLOAD_URL=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
        https://api.github.com/repos/$REPO/releases/tags/$TAG | \
        grep -o '"upload_url": "[^"]*' | cut -d'"' -f4)
else
    UPLOAD_URL=$(echo "$RELEASE_RESPONSE" | grep -o '"upload_url": "[^"]*' | cut -d'"' -f4)
fi

if [[ -z "$UPLOAD_URL" ]]; then
    echo "❌ 创建 Release 失败"
    echo "响应: $RELEASE_RESPONSE"
    exit 1
fi

echo "✓ Release 创建成功"
echo ""

# 上传文件
echo "正在上传 $PACKAGE..."
UPLOAD_URL="${UPLOAD_URL%{*}?name=$PACKAGE"

curl -s -X POST \
  -H "Authorization: token $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github.v3+json" \
  -H "Content-Type: application/gzip" \
  --data-binary "@$PACKAGE" \
  "$UPLOAD_URL" > /dev/null

echo "✓ 文件上传成功"
echo ""
echo "Release URL: https://github.com/$REPO/releases/tag/$TAG"
