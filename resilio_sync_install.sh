#!/bin/bash

# 定义 .deb 包的下载链接
DEB_PACKAGE_URL="https://github.com/chf5762-sudo/bash/raw/main/resilio-sync-arm64.deb"
PACKAGE_FILE="/tmp/resilio-sync-arm64.deb" # 下载到 /tmp 目录

echo "正在从 ${DEB_PACKAGE_URL} 下载 Resilio Sync arm64 包..."
# 使用 curl -L 处理重定向并下载
curl -L -o "$PACKAGE_FILE" "$DEB_PACKAGE_URL"

if [ $? -ne 0 ]; then
    echo "错误：下载 .deb 包失败。请检查网络连接或提供的链接是否有效。"
    exit 1
fi

echo "下载完成：${PACKAGE_FILE}"

# 检测系统是否是 Debian-based
if [ -f /etc/debian_version ] || [ -f /etc/lsb-release ] || [ -f /etc/os-release ] && grep -qE "ID=(debian|ubuntu)" /etc/os-release; then
    echo "检测到 Debian-based 系统，正在安装 Resilio Sync..."
    sudo dpkg -i "$PACKAGE_FILE"
    if [ $? -ne 0 ]; then
        echo "错误：安装 .deb 包失败。可能存在依赖问题。"
        echo "尝试运行 'sudo apt --fix-broken install' 修复依赖，然后再次运行此脚本。"
        rm "$PACKAGE_FILE" # 清理下载的文件
        exit 1
    fi
else
    echo "错误：当前系统似乎不是 Debian-based (如 Ubuntu, Debian)。此脚本仅支持 .deb 包的安装。"
    echo "如果你是 RPM-based 系统 (如 CentOS, Fedora)，你需要找到对应的 .rpm 包并修改脚本。"
    rm "$PACKAGE_FILE" # 清理下载的文件
    exit 1
fi

echo "Resilio Sync 安装成功！"

# 清理下载的 .deb 包
rm "$PACKAGE_FILE"
echo "已清理下载的 .deb 包：${PACKAGE_FILE}"

# 设置 Resilio Sync 服务自启动
echo "正在设置 Resilio Sync 服务开机自启动..."
sudo systemctl enable resilio-sync
echo "Resilio Sync 服务已设置为开机自启动。"

# 启动 Resilio Sync 服务
echo "正在启动 Resilio Sync 服务..."
sudo systemctl start resilio-sync
echo "Resilio Sync 服务已启动。"

# 检查服务状态
echo "Resilio Sync 服务状态:"
sudo systemctl status resilio-sync --no-pager

echo ""
echo "Resilio Sync 已安装并启动。你可以通过浏览器访问 http://localhost:8888 或 http://你的IP地址:8888 来配置它。"
echo ""
echo "常用命令:"
echo "  启动 Resilio Sync: sudo systemctl start resilio-sync"
echo "  停止 Resilio Sync: sudo systemctl stop resilio-sync"
echo "  重启 Resilio Sync: sudo systemctl restart resilio-sync"
echo "  查看 Resilio Sync 状态: sudo systemctl status resilio-sync"
echo "  禁用 Resilio Sync 开机自启动: sudo systemctl disable resilio-sync"

echo ""
echo "注意: 默认情况下，Resilio Sync 以 'rslsync' 用户运行。如果你需要同步当前用户的文件，可能需要进行额外的权限设置。"
echo "  例如 (将rslsync添加到你的用户组): sudo usermod -aG your_user_group rslsync"
echo "  例如 (将你的用户添加到rslsync组): sudo usermod -aG rslsync your_username"
echo "  例如 (设置文件夹读写权限): sudo chmod g+rw /path/to/your/synced_folder"
