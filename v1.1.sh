#!/bin/bash

################################################################################
# OpenVPN Docker 一键部署脚本 - Host网络模式
################################################################################
#
# 功能特点:
#   - 自动安装Docker（如果未安装）
#   - 使用Host网络模式（性能最优）
#   - 支持防封锁端口选择（443/53/22等伪装端口）
#   - 自动生成CA证书和客户端配置
#   - 支持二维码扫描下载配置文件
#   - 自动检测可用HTTP端口（避免8888/8000冲突）
#
# 使用方法:
#   1. 上传此脚本到服务器
#   2. chmod +x openvpn-install.sh
#   3. sudo ./openvpn-install.sh
#   4. 按提示选择配置选项
#   5. 下载生成的 .ovpn 文件导入客户端
#
# 推荐配置:
#   - 端口: 443 (伪装HTTPS，最难被封)
#   - 协议: TCP (配合443端口效果最佳)
#
################################################################################

set -e

echo "=========================================="
echo "  OpenVPN Docker 一键部署脚本"
echo "  Host网络模式 + 防封锁配置"
echo "=========================================="
echo ""

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then 
    echo "❌ 请使用 root 用户运行此脚本"
    echo "   运行: sudo $0"
    exit 1
fi

# 检查Docker是否安装
echo "步骤 1/8: 检查Docker环境..."
if ! command -v docker &> /dev/null; then
    echo "Docker 未安装，正在安装..."
    curl -fsSL https://get.docker.com | sh
    systemctl start docker
    systemctl enable docker
    echo "✓ Docker 安装完成"
else
    echo "✓ Docker 已安装"
fi
echo ""

# 获取服务器公网IP
echo "步骤 2/8: 检测服务器信息..."
SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || curl -s ipecho.net/plain)
echo "检测到服务器公网IP: $SERVER_IP"
echo ""

# 询问使用域名还是IP
read -p "使用域名还是IP? (输入域名或直接回车使用 $SERVER_IP): " SERVER_ADDR
if [ -z "$SERVER_ADDR" ]; then
    SERVER_ADDR=$SERVER_IP
fi

# 询问客户端名称
read -p "输入客户端名称 (默认: client): " CLIENT_NAME
CLIENT_NAME=${CLIENT_NAME:-client}

# 询问VPN端口
echo ""
echo "步骤 3/8: 选择VPN端口..."
echo "选择VPN端口 (推荐使用常见服务端口防止封锁):"
echo "  1) 443  - HTTPS端口 (最不容易被封，强烈推荐) ⭐⭐⭐⭐⭐"
echo "  2) 53   - DNS端口 (不易被封) ⭐⭐⭐⭐"
echo "  3) 22   - SSH端口 ⭐⭐⭐"
echo "  4) 8443 - 备用HTTPS端口 ⭐⭐⭐"
echo "  5) 1194 - OpenVPN标准端口 (容易被识别和封锁) ⭐"
echo "  6) 自定义端口"
read -p "请选择 (1-6, 默认: 1): " PORT_CHOICE
PORT_CHOICE=${PORT_CHOICE:-1}

case $PORT_CHOICE in
    1) VPN_PORT=443 ;;
    2) VPN_PORT=53 ;;
    3) VPN_PORT=22 ;;
    4) VPN_PORT=8443 ;;
    5) VPN_PORT=1194 ;;
    6) 
        read -p "输入自定义端口 (1-65535): " VPN_PORT
        if ! [[ "$VPN_PORT" =~ ^[0-9]+$ ]] || [ "$VPN_PORT" -lt 1 ] || [ "$VPN_PORT" -gt 65535 ]; then
            echo "无效端口，使用默认 443"
            VPN_PORT=443
        fi
        ;;
    *)
        echo "无效选择，使用默认 443"
        VPN_PORT=443
        ;;
esac

echo "✓ 已选择端口: $VPN_PORT"
echo ""

# 询问VPN协议
echo "步骤 4/8: 选择传输协议..."
read -p "选择协议 (udp/tcp, 推荐tcp配合443端口伪装HTTPS, 默认: tcp): " VPN_PROTOCOL
VPN_PROTOCOL=${VPN_PROTOCOL:-tcp}

# 如果选择了443端口但使用UDP，给出提示
if [ "$VPN_PORT" = "443" ] && [ "$VPN_PROTOCOL" = "udp" ]; then
    echo "⚠️  提示: 443端口通常用于TCP (HTTPS)，使用UDP可能更容易被识别"
    read -p "是否改用TCP协议? (y/n, 推荐: y): " CHANGE_TO_TCP
    if [ "$CHANGE_TO_TCP" = "y" ]; then
        VPN_PROTOCOL="tcp"
        echo "✓ 已切换为TCP协议"
    fi
fi

# 使用 host 网络模式
NETWORK_MODE="host"

echo ""
echo "=========================================="
echo "配置信息确认:"
echo "----------------------------------------"
echo "  服务器地址: $SERVER_ADDR"
echo "  VPN端口: $VPN_PORT"
echo "  传输协议: $VPN_PROTOCOL"
echo "  网络模式: host (直接使用宿主机网络)"
echo "  客户端名称: $CLIENT_NAME"
if [ "$VPN_PORT" = "443" ] && [ "$VPN_PROTOCOL" = "tcp" ]; then
    echo "  防封锁: ✓ 最佳配置 (伪装HTTPS流量)"
fi
echo "=========================================="
read -p "确认配置无误? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "❌ 已取消安装"
    exit 0
fi
echo ""

# 创建数据卷
echo "步骤 5/8: 创建数据卷..."
docker volume create --name ovpn-data
echo "✓ 数据卷创建完成"
echo ""

# 生成配置
echo "步骤 6/8: 生成OpenVPN配置..."
docker run -v ovpn-data:/etc/openvpn --rm kylemanna/openvpn ovpn_genconfig -u $VPN_PROTOCOL://$SERVER_ADDR:$VPN_PORT
echo "✓ 配置生成完成"
echo ""

# 生成CA证书 (使用非交互模式)
echo "步骤 7/8: 生成CA证书..."
echo "正在生成CA证书，请稍候..."
# 使用 expect 或直接传入空值来完全自动化
docker run -v ovpn-data:/etc/openvpn --rm kylemanna/openvpn bash -c "
echo 'OpenVPN-CA' | ovpn_initpki nopass
"
if [ $? -ne 0 ]; then
    echo "⚠️  自动模式失败，切换到交互模式..."
    echo "提示: 在 'Common Name' 提示时直接按回车使用默认值"
    docker run -v ovpn-data:/etc/openvpn --rm -it kylemanna/openvpn ovpn_initpki nopass
fi
echo "✓ CA证书生成完成"
echo ""

# 停止并删除已存在的容器
if docker ps -a | grep -q openvpn; then
    echo "检测到旧容器，正在清理..."
    docker stop openvpn 2>/dev/null || true
    docker rm openvpn 2>/dev/null || true
    echo "✓ 旧容器已清理"
fi

# 启动OpenVPN服务器
echo "步骤 8/8: 启动OpenVPN服务器 (Host网络模式)..."
docker run -v ovpn-data:/etc/openvpn -d \
    --network host \
    --cap-add=NET_ADMIN \
    --restart=always \
    --name openvpn \
    kylemanna/openvpn

echo "✓ 容器已启动，直接使用宿主机 $VPN_PORT 端口"
echo ""

# 等待容器启动
sleep 3

# 生成客户端证书
echo "生成客户端配置..."
docker run -v ovpn-data:/etc/openvpn --rm -it kylemanna/openvpn easyrsa build-client-full $CLIENT_NAME nopass

# 导出客户端配置文件
echo "导出客户端配置文件..."
docker run -v ovpn-data:/etc/openvpn --rm kylemanna/openvpn ovpn_getclient $CLIENT_NAME > ~/$CLIENT_NAME.ovpn

echo ""
echo "=========================================="
echo "✓ OpenVPN 安装完成!"
echo "=========================================="
echo "客户端配置文件: ~/$CLIENT_NAME.ovpn"

# 询问是否生成二维码
echo ""
read -p "是否生成二维码方便手机扫描下载? (y/n): " GEN_QR
if [ "$GEN_QR" = "y" ]; then
    # 安装qrencode
    if ! command -v qrencode &> /dev/null; then
        echo "正在安装二维码生成工具..."
        if command -v apt &> /dev/null; then
            apt update && apt install -y qrencode
        elif command -v yum &> /dev/null; then
            yum install -y qrencode
        fi
    fi
    
    # 检测可用端口（从9000-9999随机选择）
    HTTP_PORT=9000
    while netstat -tuln 2>/dev/null | grep -q ":$HTTP_PORT " || ss -tuln 2>/dev/null | grep -q ":$HTTP_PORT "; do
        HTTP_PORT=$((HTTP_PORT + 1))
        if [ $HTTP_PORT -gt 9999 ]; then
            echo "❌ 端口9000-9999都被占用，请手动指定端口"
            read -p "输入临时HTTP端口 (建议10000-65535): " HTTP_PORT
            break
        fi
    done
    
    echo "使用临时HTTP端口: $HTTP_PORT"
    
    # 启动临时HTTP服务器
    echo "正在启动临时文件服务器..."
    cd ~
    python3 -m http.server $HTTP_PORT > /dev/null 2>&1 &
    HTTP_PID=$!
    
    sleep 2
    
    # 生成下载链接
    DOWNLOAD_URL="http://$SERVER_IP:$HTTP_PORT/$CLIENT_NAME.ovpn"
    
    echo ""
    echo "=========================================="
    echo "📱 手机扫描下面的二维码下载配置文件:"
    echo "=========================================="
    echo "$DOWNLOAD_URL" | qrencode -t ansiutf8
    echo ""
    echo "下载链接: $DOWNLOAD_URL"
    echo ""
    echo "⚠️  注意: 请确保防火墙开放 $HTTP_PORT 端口"
    echo "   临时开放: ufw allow $HTTP_PORT/tcp"
    echo "   下载完成后按任意键关闭文件服务器..."
    read -n 1
    
    # 关闭HTTP服务器
    kill $HTTP_PID 2>/dev/null
    echo ""
    echo "✓ 文件服务器已关闭"
    echo "   关闭防火墙端口: ufw delete allow $HTTP_PORT/tcp"
fi

echo ""
echo "=========================================="
echo "📋 配置防火墙"
echo "=========================================="
echo "需要开放VPN端口: $VPN_PORT/$VPN_PROTOCOL"
echo ""
if [ "$VPN_PORT" = "443" ] && [ "$VPN_PROTOCOL" = "tcp" ]; then
    echo "✓ 使用443/TCP端口，流量伪装为HTTPS，最佳防封锁方案"
fi
echo "防火墙配置命令:"
if command -v ufw &> /dev/null; then
    echo "  ufw allow $VPN_PORT/$VPN_PROTOCOL"
    echo "  ufw reload"
elif command -v firewall-cmd &> /dev/null; then
    echo "  firewall-cmd --add-port=$VPN_PORT/$VPN_PROTOCOL --permanent"
    echo "  firewall-cmd --reload"
else
    echo "  请手动配置防火墙开放 $VPN_PORT/$VPN_PROTOCOL 端口"
fi

echo ""
echo "=========================================="
echo "📱 客户端使用说明"
echo "=========================================="
echo "1. 下载配置文件: ~/$CLIENT_NAME.ovpn"
echo ""
echo "2. 安装OpenVPN客户端:"
echo "   - Windows: OpenVPN GUI"
echo "   - macOS: Tunnelblick"
echo "   - Linux: sudo apt install openvpn"
echo "   - Android: OpenVPN for Android"
echo "   - iOS: OpenVPN Connect"
echo ""
echo "3. 导入配置文件并连接"
echo ""
echo "4. 其他下载方式:"
echo "   SCP下载: scp root@$SERVER_IP:~/$CLIENT_NAME.ovpn ./"
echo "   临时HTTP: cd ~ && python3 -m http.server 9000"
echo "   查看内容: cat ~/$CLIENT_NAME.ovpn"

echo ""
echo "=========================================="
echo "🔧 常用管理命令"
echo "=========================================="
echo "查看日志:"
echo "  docker logs -f openvpn"
echo ""
echo "服务控制:"
echo "  docker stop openvpn      # 停止服务"
echo "  docker start openvpn     # 启动服务"
echo "  docker restart openvpn   # 重启服务"
echo ""
echo "添加新客户端:"
echo "  docker run -v ovpn-data:/etc/openvpn --rm -it kylemanna/openvpn \\"
echo "    easyrsa build-client-full 新客户端名称 nopass"
echo "  docker run -v ovpn-data:/etc/openvpn --rm kylemanna/openvpn \\"
echo "    ovpn_getclient 新客户端名称 > ~/新客户端名称.ovpn"
echo ""
echo "吊销客户端:"
echo "  docker run -v ovpn-data:/etc/openvpn --rm -it kylemanna/openvpn \\"
echo "    ovpn_revokeclient 客户端名称"
echo ""
echo "快速更换端口 (如果被封锁):"
echo "  docker stop openvpn && docker rm openvpn"
echo "  重新运行本脚本，选择不同的端口"
echo ""
echo "查看连接状态:"
echo "  docker exec openvpn cat /etc/openvpn/openvpn-status.log"
echo ""
echo "完全卸载:"
echo "  docker stop openvpn && docker rm openvpn"
echo "  docker volume rm ovpn-data"

echo ""
echo "=========================================="
echo "🎉 部署完成!"
echo "=========================================="
echo "配置文件位置: ~/$CLIENT_NAME.ovpn"
echo "立即下载并导入客户端即可使用"
echo ""
echo "如有问题，请查看日志: docker logs -f openvpn"
echo "=========================================="
