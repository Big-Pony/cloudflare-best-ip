# CloudflareSpeedTest 自动优选 IP 方案

🌩 自动测试 Cloudflare CDN 延迟，获取最优 IP 并更新到 hosts 文件

## 📋 功能特点

- ✅ **自动测速**：快速筛选延迟最低的 Cloudflare IP
- ✅ **自动更新**：自动替换 hosts 文件中的旧 IP
- ✅ **定时执行**：支持每6小时自动执行（可自定义）
- ✅ **备份机制**：每次修改前自动备份 hosts 文件
- ✅ **DNS刷新**：更新后自动刷新系统 DNS 缓存
- ✅ **快速模式**：仅测延迟，23秒完成（原方案需10-20分钟）

---

## 🚀 快速开始

### 1. 下载 CloudflareSpeedTest

```bash
# macOS ARM64 (M1/M2/M3)
wget https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.3.4/CloudflareST_macOS_arm64.zip
unzip CloudflareST_macOS_arm64.zip

# macOS AMD64 (Intel)
wget https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.3.4/CloudflareST_macOS_amd64.zip
unzip CloudflareST_macOS_amd64.zip

# Linux AMD64
wget https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.3.4/CloudflareST_linux_amd64.tar.gz
tar -zxf CloudflareST_linux_amd64.tar.gz
```

### 2. 配置文件

编辑 `auto_update_hosts.sh`，修改你的域名：

```bash
# 目标域名列表
TARGET_DOMAINS=(
    "your-domain.com"   # ← 改成你的域名
)
```

### 3. 手动测试运行

```bash
sudo ./auto_update_hosts.sh
```

### 4. 安装定时任务（macOS）

```bash
# 复制配置文件
cp com.user.cfst.update.plist ~/Library/LaunchAgents/

# 加载定时任务
launchctl load ~/Library/LaunchAgents/com.user.cfst.update.plist

# 验证
launchctl list | grep cfst
```

### 5. 安装定时任务（Linux）

```bash
# 编辑 crontab
sudo crontab -e

# 添加以下行（每6小时执行一次）
0 */6 * * * /bin/bash /path/to/auto_update_hosts.sh >> /path/to/update.log 2>&1
```

---

## 📁 文件说明

| 文件 | 说明 |
|------|------|
| `cfst` | CloudflareSpeedTest 主程序 |
| `ip.txt` | Cloudflare IPv4 段数据 |
| `ipv6.txt` | Cloudflare IPv6 段数据 |
| `auto_update_hosts.sh` | **核心脚本**：自动测速并更新 hosts |
| `com.user.cfst.update.plist` | macOS 定时任务配置 |
| `update.log` | 执行日志 |
| `hosts_backup/` | hosts 文件备份目录 |

---

## ⚙️ 配置详解

### 修改测速参数

编辑 `auto_update_hosts.sh` 中的 `CFST_ARGS`：

```bash
# 快速模式（仅延迟，约30秒）
CFST_ARGS="-dd -n 500 -t 2 -tl 200 -o ${RESULT_FILE}"

# 完整模式（延迟+下载速度，约10分钟）
CFST_ARGS="-tl 200 -dn 10 -dt 10 -o ${RESULT_FILE}"
```

### 参数说明

| 参数 | 说明 | 示例 |
|------|------|------|
| `-n 500` | 并发线程数 | 默认200，越高越快 |
| `-t 2` | 每个IP测速次数 | 默认4次 |
| `-tl 200` | 延迟上限(ms) | 只保留<200ms的IP |
| `-sl 5` | 下载速度下限(MB/s) | 只保留>5MB/s的IP |
| `-dn 10` | 下载测速数量 | 给最快的10个IP测下载 |
| `-dt 10` | 下载测速时间(秒) | 每个IP测10秒 |
| `-dd` | 禁用下载测速 | 只按延迟排序 |
| `-f ip.txt` | 指定IP段文件 | 可自定义 |

---

## 🛠️ 管理命令

### macOS

```bash
# 查看定时任务状态
launchctl list | grep cfst

# 停止定时任务
launchctl unload ~/Library/LaunchAgents/com.user.cfst.update.plist

# 启动定时任务
launchctl load ~/Library/LaunchAgents/com.user.cfst.update.plist

# 立即执行一次
sudo ./auto_update_hosts.sh

# 查看日志
tail -f update.log
```

### Linux

```bash
# 查看定时任务
sudo crontab -l

# 编辑定时任务
sudo crontab -e

# 查看日志
tail -f /path/to/update.log
```

---

## ⏰ 定时任务配置

### 每6小时执行（默认）

编辑 `com.user.cfst.update.plist`：

```xml
<key>StartInterval</key>
<integer>21600</integer>  <!-- 6*60*60 = 21600秒 -->
```

### 其他频率

| 频率 | 秒数 |
|------|------|
| 每小时 | 3600 |
| 每3小时 | 10800 |
| 每6小时 | 21600 |
| 每12小时 | 43200 |
| 每天 | 86400 |

### 固定时间点执行

```xml
<key>StartCalendarInterval</key>
<dict>
    <key>Hour</key>
    <integer>3</integer>    <!-- 凌晨3点 -->
    <key>Minute</key>
    <integer>0</integer>
</dict>
```

---

## 🔍 常见问题

### Q: 提示 "无法找到满足条件的 IP"

**A**: 放宽测速条件，修改参数：

```bash
# 提高延迟上限到300ms，取消下载速度限制
CFST_ARGS="-tl 300 -sl 0 -dn 10 -o ${RESULT_FILE}"
```

### Q: hosts 文件没有更新

**A**: 检查步骤：

```bash
# 1. 查看日志
cat update.log

# 2. 检查权限
ls -la /etc/hosts

# 3. 手动执行看错误
sudo ./auto_update_hosts.sh
```

### Q: 定时任务没有执行

**A**: macOS 检查步骤：

```bash
# 查看任务状态
launchctl list | grep cfst

# 检查 plist 文件语法
plutil -lint ~/Library/LaunchAgents/com.user.cfst.update.plist

# 重新加载
launchctl unload ~/Library/LaunchAgents/com.user.cfst.update.plist
launchctl load ~/Library/LaunchAgents/com.user.cfst.update.plist
```

### Q: 如何只测特定IP段？

**A**: 创建自定义IP文件：

```bash
# 创建 custom_ips.txt，每行一个IP段
cat > custom_ips.txt << 'EOF'
104.16.80.0/24
172.64.32.0/24
EOF

# 使用 -f 参数指定
./cfst -f custom_ips.txt -dd -tl 200
```

### Q: 如何恢复 hosts 备份？

**A**: 手动恢复：

```bash
# 查看备份列表
ls hosts_backup/

# 恢复指定备份
sudo cp hosts_backup/hosts_20260306_150243 /etc/hosts

# 刷新DNS缓存
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

---

## 📝 手动测速命令

### 仅测延迟（最快）

```bash
./cfst -dd -n 500 -t 2 -tl 200 -p 10
```

### 延迟+下载速度

```bash
./cfst -tl 200 -dn 10 -dt 10 -p 10
```

### 测指定IP

```bash
./cfst -ip 1.1.1.1,8.8.8.8
```

### 测 IPv6

```bash
./cfst -f ipv6.txt -dd -tl 200
```

---

## 🔗 相关链接

- [CloudflareSpeedTest 官方项目](https://github.com/XIU2/CloudflareSpeedTest)
- [Cloudflare IP 段](https://www.cloudflare.com/ips/)

---

## ⚠️ 注意事项

1. **首次运行需要 sudo**：因为需要修改 `/etc/hosts` 文件
2. **关闭代理测速**：测速时请关闭代理软件，否则结果不准确
3. **域名配置**：务必修改 `TARGET_DOMAINS` 为你自己的域名
4. **备份机制**：每次修改前会自动备份 hosts 文件
5. **定时任务**：macOS 重启后自动生效，无需重复设置

---

## 📊 效果对比

| 方案 | 测速时间 | 结果准确性 | 适用场景 |
|------|----------|-----------|----------|
| 完整模式 | 10-20分钟 | ⭐⭐⭐ 高 | 精确找最快IP |
| **快速模式** | **~30秒** | ⭐⭐ 中 | **日常自动更新** |
| 精简IP模式 | ~10秒 | ⭐⭐ 中 | 已知优质IP段 |

---

**推荐**：日常使用快速模式（`-dd` 仅测延迟），每周或每月用一次完整模式验证。
