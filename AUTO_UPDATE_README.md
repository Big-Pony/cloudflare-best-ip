# CloudflareSpeedTest 自动更新 Hosts 方案

## 📋 项目说明

本项目实现了定期自动测速并更新 hosts 文件中 Cloudflare CDN IP 的功能，帮助你始终使用最优 IP 访问 Cloudflare 加速的网站。

## 🚀 快速开始

### 1. 配置目标域名

编辑 `auto_update_hosts.sh`，修改 `TARGET_DOMAINS` 数组：

```bash
TARGET_DOMAINS=(
    "your-domain.com"
    "www.your-domain.com"
    # 添加更多域名...
)
```

### 2. 测试运行

```bash
# 先手动执行一次，确保正常工作
sudo ./auto_update_hosts.sh
```

### 3. 安装定时任务（macOS）

```bash
# 安装并启动定时任务（每天凌晨 3 点执行）
./manage_service.sh install

# 查看状态
./manage_service.sh status

# 立即执行一次
./manage_service.sh run
```

## 📁 文件说明

| 文件 | 说明 |
|------|------|
| `cfst` | CloudflareSpeedTest 主程序 |
| `auto_update_hosts.sh` | 自动更新脚本（核心） |
| `manage_service.sh` | 服务管理脚本 |
| `com.user.cfst.update.plist` | macOS 定时任务配置 |
| `update.log` | 运行日志 |
| `hosts_backup/` | hosts 文件备份目录 |

## ⚙️ 自定义配置

### 修改测速参数

编辑 `auto_update_hosts.sh` 中的 `CFST_ARGS`：

```bash
# 示例: 只测试延迟低于 150ms、下载速度大于 5MB/s 的 IP
CFST_ARGS="-tl 150 -sl 5 -dn 10 -dt 10 -o ${RESULT_FILE}"
```

常用参数说明：
- `-tl 200`：平均延迟上限（毫秒）
- `-sl 5`：下载速度下限（MB/s）
- `-dn 10`：下载测速数量
- `-dt 10`：单个 IP 下载测速时间（秒）
- `-dd`：禁用下载测速（只按延迟排序）

### 修改执行时间

编辑 `com.user.cfst.update.plist`：

```xml
<!-- 每天凌晨 3 点执行 -->
<key>StartCalendarInterval</key>
<dict>
    <key>Hour</key>
    <integer>3</integer>
    <key>Minute</key>
    <integer>0</integer>
</dict>
```

或改为每隔 N 秒执行：

```xml
<!-- 每 6 小时执行一次 -->
<key>StartInterval</key>
<integer>21600</integer>
```

## 🛠️ 管理命令

```bash
# 查看帮助
./manage_service.sh

# 安装服务
./manage_service.sh install

# 卸载服务
./manage_service.sh uninstall

# 启动/停止服务
./manage_service.sh start
./manage_service.sh stop

# 查看状态
./manage_service.sh status

# 查看日志
./manage_service.sh logs

# 编辑配置
./manage_service.sh edit
```

## 📝 手动使用（Linux 或其他系统）

对于 Linux 系统，可以使用 crontab：

```bash
# 编辑 crontab
sudo crontab -e

# 添加以下行（每天凌晨 3 点执行）
0 3 * * * /bin/bash /path/to/cfst_darwin_arm64/auto_update_hosts.sh >> /path/to/cfst_darwin_arm64/cron.log 2>&1
```

## ⚠️ 注意事项

1. **首次运行需要 sudo**：因为需要修改 `/etc/hosts` 文件
2. **关闭代理测速**：测速时请关闭代理软件，否则结果不准确
3. **域名配置**：务必修改 `TARGET_DOMAINS` 为你自己的域名
4. **备份机制**：每次修改前会自动备份 hosts 文件到 `hosts_backup/`

## 🔍 故障排查

### 问题：提示 "无法找到满足条件的 IP"

**解决方案**：放宽测速条件，修改 `CFST_ARGS`：

```bash
# 提高延迟上限，降低速度要求
CFST_ARGS="-tl 300 -sl 0 -dn 10 -o ${RESULT_FILE}"
```

### 问题：hosts 文件没有更新

**检查步骤**：

```bash
# 1. 查看日志
cat update.log

# 2. 检查权限
sudo ls -la /etc/hosts

# 3. 手动执行看错误
sudo ./auto_update_hosts.sh
```

### 问题：定时任务没有执行

**检查步骤**：

```bash
# 查看任务状态
launchctl list | grep cfst

# 检查 plist 文件语法
plutil -lint ~/Library/LaunchAgents/com.user.cfst.update.plist

# 重新加载
launchctl unload ~/Library/LaunchAgents/com.user.cfst.update.plist
launchctl load ~/Library/LaunchAgents/com.user.cfst.update.plist
```

## 📚 参考链接

- [CloudflareSpeedTest 官方项目](https://github.com/XIU2/CloudflareSpeedTest)
- [Cloudflare IP 段](https://www.cloudflare.com/ips/)
