#!/bin/bash

# --- Tailscale 一键卸载脚本 ---

# 默认需要确认
CONFIRM=false

# 检查参数，如果传入 -y 或 --force 则跳过确认
for arg in "$@"; do
    case "$arg" in
        -y|--force)
            CONFIRM=true
            ;;
    esac
done

if [[ "$CONFIRM" == "false" ]]; then
    echo "此脚本将尝试完全卸载 Tailscale。"
    echo "这包括停止服务、删除软件包以及清除相关配置文件和数据目录。"
    echo "如果您在卸载后打算重新安装，请注意您将需要重新认证设备。"
    read -p "您确定要继续吗？(y/N): " user_confirm
    if [[ "$user_confirm" != [yY] ]]; then
        echo "操作已取消。"
        exit 0
    fi
fi

echo "-------------------------------------"
echo "正在停止 Tailscale 服务..."
sudo systemctl stop tailscaled 2>/dev/null
sudo service tailscale stop 2>/dev/null
echo "Tailscale 服务已停止 (如果正在运行)。"

echo "-------------------------------------"
echo "正在检测操作系统并卸载 Tailscale 软件包..."

# 检测操作系统
if grep -Eq "debian|ubuntu|mint" /etc/os-release; then
    echo "检测到 Debian/Ubuntu/Mint 系统，使用 apt 卸载..."
    sudo apt purge -y tailscale
    sudo apt autoremove -y
elif grep -Eq "centos|rhel|fedora" /etc/os-release; then
    echo "检测到 CentOS/RHEL/Fedora 系统，使用 yum/dnf 卸载..."
    if command -v dnf &> /dev/null; then
        sudo dnf remove -y tailscale
    else
        sudo yum remove -y tailscale
    fi
elif grep -Eq "arch" /etc/os-release; then
    echo "检测到 Arch Linux 系统，使用 pacman 卸载..."
    sudo pacman -Rns --noconfirm tailscale
else
    echo "警告：无法自动识别您的操作系统或其包管理器。"
    echo "请尝试手动卸载 Tailscale。"
    echo "例如：'sudo apt purge tailscale' 或 'sudo yum remove tailscale' 等。"
fi

echo "-------------------------------------"
echo "正在删除残留文件和配置..."

# 删除主要数据目录
if [ -d "/var/lib/tailscale" ]; then
    echo "正在删除 /var/lib/tailscale..."
    sudo rm -rf /var/lib/tailscale
else
    echo "/var/lib/tailscale 目录不存在或已被删除。"
fi

# 尝试查找并删除其他配置文件 (谨慎操作)
echo "正在查找并删除其他可能的 Tailscale 配置文件..."
# 仅删除已知与tailscale直接相关的配置文件名，避免误删
find /etc -name "*tailscale*" -type f -delete 2>/dev/null
find /usr/local/bin -name "tailscale*" -type f -delete 2>/dev/null
find /usr/bin -name "tailscale*" -type f -delete 2>/dev/null

echo "-------------------------------------"
echo "正在清理 systemd 单元文件 (如果存在)..."
sudo rm -f /etc/systemd/system/tailscaled.service 2>/dev/null
sudo systemctl daemon-reload 2>/dev/null

echo "-------------------------------------"
echo "正在进行最终检查..."
if ! command -v tailscale &> /dev/null; then
    echo "Tailscale 命令行工具已成功移除。"
else
    echo "警告：Tailscale 命令行工具可能仍存在。请手动检查。"
fi

if [ ! -d "/var/lib/tailscale" ]; then
    echo "/var/lib/tailscale 目录已成功移除。"
else
    echo "警告：/var/lib/tailscale 目录可能仍存在。请手动检查。"
fi

echo "-------------------------------------"
echo "Tailscale 卸载过程已完成。"
echo "如果您在 Tailscale 控制台中仍看到此设备，可能需要手动将其删除。"
