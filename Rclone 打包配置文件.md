您需要打包的不仅仅是代码，更重要的是配置和状态文件。

🚀 打包项目（Rclone 配置环境）的完整指南
以下是您需要打包的关键文件、目录，以及一个一键打包脚本。

1. 关键文件和目录
文件/目录	描述	重要性
Rclone 可执行文件	/root/rclone-integrated/rclone/rclone	Rclone 的核心程序，您可能需要将整个 /root/rclone-integrated/ 目录打包。
Rclone 配置文件	/root/.config/rclone/rclone.conf	最重要！ 包含您的百度 API Key、Secret 和授权 Token。部署到新机器后，位置不能变。
Systemd 服务文件	/etc/systemd/system/rclone-baidu.service /etc/systemd/system/rclone-mirror-data.service /etc/systemd/system/rclone-sync.timer	包含所有挂载、同步和定时任务的逻辑和路径配置。
本地数据目录	/root/data/BaiduShare	可选： 如果您想保留已下载的文件，可以打包。如果不想，则跳过。

导出到 Google 表格
2. 一键打包脚本 (pack_rclone_config.sh)
这个脚本将所有必要的文件和配置打包到一个 .tar.gz 文件中。

Bash

#!/bin/bash

# --- 打包配置变量 ---
BACKUP_DIR="/root/rclone_backup"
BACKUP_FILE="rclone_baidu_config_$(date +%Y%m%d).tar.gz"
RCLONE_ROOT="/root/rclone-integrated"
CONFIG_DIR="/root/.config/rclone"
SYSTEMD_DIR="/etc/systemd/system"

echo "--- 1. 创建备份临时目录 ---"
mkdir -p "$BACKUP_DIR/systemd"
mkdir -p "$BACKUP_DIR/config"

echo "--- 2. 复制配置文件和可执行文件 ---"
# 复制Rclone程序和依赖
cp -r "$RCLONE_ROOT" "$BACKUP_DIR/"
echo "Rclone程序已复制。"

# 复制配置文件
cp -r "$CONFIG_DIR" "$BACKUP_DIR/config/"
echo "Rclone配置文件已复制。"

echo "--- 3. 复制Systemd服务文件 ---"
# 复制Systemd服务文件
cp "$SYSTEMD_DIR/rclone-baidu.service" "$BACKUP_DIR/systemd/"
cp "$SYSTEMD_DIR/rclone-mirror-data.service" "$BACKUP_DIR/systemd/"
cp "$SYSTEMD_DIR/rclone-sync.timer" "$BACKUP_DIR/systemd/"
echo "Systemd文件已复制。"

echo "--- 4. 执行打包操作 ---"
cd "$BACKUP_DIR"
tar -czf "../$BACKUP_FILE" *

# 清理临时目录
cd /root
rm -rf "$BACKUP_DIR"

echo "========================================================"
echo "✨ Rclone 配置环境打包完成！"
echo "打包文件位于：/root/$BACKUP_FILE"
echo "请务必安全保管此文件，其中包含您的百度 API Token！"
echo "========================================================"
3. 部署到新机器的步骤（极速部署）
在新服务器上，您只需要将文件放回原位，然后启动服务即可。

传输文件： 将 $BACKUP_FILE 传输到新服务器的 /root/ 目录。

解压文件：

Bash

tar -xzf rclone_baidu_config_*.tar.gz
恢复目录结构：

Bash

cp -r ./rclone-integrated /root/
cp -r ./config/rclone /root/.config/
cp ./systemd/*.service /etc/systemd/system/
cp ./systemd/*.timer /etc/systemd/system/
创建挂载和数据目录：

Bash

mkdir -p /root/BaiduDisk
mkdir -p /root/data/BaiduShare
启动服务：

Bash

systemctl daemon-reload
systemctl enable rclone-baidu.service rclone-mirror-data.service rclone-sync.timer
systemctl start rclone-baidu.service
systemctl start rclone-sync.timer
启动完毕！您的新机器已完全同步到之前的配置。
