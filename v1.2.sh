#!/bin/bash

################################################################################
# 文件名: openvpn-docker-v1.1.sh
# 版本号: v1.1
# 用途: OpenVPN Docker 一键部署脚本 - Host网络模式（改进版）
# 作者: chf5762
# 日期: 2025-10-27
# 部署目标: vps1.chf5762.cloudns.org
# 
# 改进内容：
# - HTTP端口范围改为9000-9100
# - 完整的依赖检查和自动安装
# - HTTP服务添加密码保护（root/password）
# - 支持一键下载所有配置（带日期的zip文件）
# - 隐藏.txt文件，不显示不可下载
# - 移除交互式参数，使用批处理模式
# - 优化端口检测（优先ss，fallback netstat）
# - 增强错误处理和回滚机制
################################################################################

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置变量
OVPN_DATA="ovpn-data-host"
CONTAINER_NAME="openvpn-host"
DOMAIN=""  # 将在detect_server_address函数中设置
DEFAULT_USER="root"
DEFAULT_PASS="password"

# HTTP服务配置
HTTP_USERNAME="root"
HTTP_PASSWORD="password"
HTTP_PORT_RANGE_START=9000
HTTP_PORT_RANGE_END=9100

# 客户端配置列表
declare -A CLIENTS=(
    ["work-pc-1"]="工作电脑1"
    ["work-pc-2"]="工作电脑2"
    ["work-pc-3"]="工作电脑3"
    ["ipad-1"]="iPad-1"
    ["ipad-2"]="iPad-2"
    ["ipad-3"]="iPad-3"
    ["home-pc-1"]="家庭电脑1"
    ["home-pc-2"]="家庭电脑2"
    ["home-pc-3"]="家庭电脑3"
    ["android-1"]="安卓手机1"
    ["android-2"]="安卓手机2"
    ["android-3"]="安卓手机3"
    ["iphone-1"]="iPhone-1"
    ["iphone-2"]="iPhone-2"
    ["iphone-3"]="iPhone-3"
)

# 打印带颜色的信息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 打印标题
print_header() {
    echo -e "${GREEN}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║         OpenVPN Docker 一键部署脚本 v1.1                  ║"
    echo "║         Host网络模式 - 高性能部署（改进版）               ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用root权限运行此脚本"
        exit 1
    fi
}

# 检查系统类型
check_system() {
    print_info "检查系统环境..."
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
        print_success "检测到系统: $PRETTY_NAME"
    else
        print_error "无法检测系统类型"
        exit 1
    fi
    
    if [[ "$OS" != "ubuntu" && "$OS" != "debian" ]]; then
        print_warning "此脚本主要针对Ubuntu/Debian系统优化"
    fi
}

# 自动检测服务器地址
detect_server_address() {
    print_info "检测服务器公网地址..."
    
    # 方法1: 通过多个公共API获取公网IP
    SERVER_IP=""
    
    # 尝试多个IP检测服务
    IP_SERVICES=(
        "https://api.ipify.org"
        "https://ifconfig.me/ip"
        "https://icanhazip.com"
        "https://ipecho.net/plain"
        "https://checkip.amazonaws.com"
    )
    
    for service in "${IP_SERVICES[@]}"; do
        SERVER_IP=$(curl -s --max-time 5 "$service" 2>/dev/null | tr -d '\n\r ')
        
        # 验证IP格式
        if [[ $SERVER_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            print_success "检测到公网IP: $SERVER_IP"
            break
        fi
        SERVER_IP=""
    done
    
    # 如果所有API都失败，使用本地网卡IP
    if [ -z "$SERVER_IP" ]; then
        print_warning "无法获取公网IP，尝试使用本地网卡IP..."
        SERVER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -n1)
    fi
    
    if [ -z "$SERVER_IP" ]; then
        print_error "无法自动检测服务器地址"
        SERVER_IP="YOUR_SERVER_IP"
    fi
    
    # 预定义域名列表
    declare -A DOMAIN_LIST=(
        [2]="vps1.chf5762.cloudns.org"
        [3]="vps2.chf5762.cloudns.org"
        [4]="vps3.chf5762.cloudns.org"
        [5]="gcp1.beundredig.eu.org"
        [6]="gcp2.beundredig.eu.org"
        [7]="gcp3.beundredig.eu.org"
    )
    
    echo ""
    print_info "服务器地址配置"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  检测到的服务器IP: ${YELLOW}$SERVER_IP${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  请选择服务器地址:"
    echo -e "  ${BLUE}1)${NC} 使用检测到的IP: ${YELLOW}$SERVER_IP${NC} (默认)"
    echo ""
    echo -e "  ${BLUE}CloudNS 域名组:${NC}"
    echo "  2) vps1.chf5762.cloudns.org"
    echo "  3) vps2.chf5762.cloudns.org"
    echo "  4) vps3.chf5762.cloudns.org"
    echo ""
    echo -e "  ${BLUE}EU.org 域名组:${NC}"
    echo "  5) gcp1.beundredig.eu.org"
    echo "  6) gcp2.beundredig.eu.org"
    echo "  7) gcp3.beundredig.eu.org"
    echo ""
    echo "  8) 输入自定义域名"
    echo ""
    read -p "请选择 [1-8，直接回车使用IP]: " addr_choice
    
    case $addr_choice in
        1|"")
            DOMAIN="$SERVER_IP"
            print_success "使用IP地址: $DOMAIN"
            ;;
        2|3|4|5|6|7)
            DOMAIN="${DOMAIN_LIST[$addr_choice]}"
            print_success "使用域名: $DOMAIN"
            ;;
        8)
            read -p "请输入自定义域名: " custom_domain
            if [ -n "$custom_domain" ]; then
                DOMAIN="$custom_domain"
                print_success "使用自定义域名: $DOMAIN"
            else
                DOMAIN="$SERVER_IP"
                print_warning "域名为空，使用IP: $DOMAIN"
            fi
            ;;
        *)
            DOMAIN="$SERVER_IP"
            print_warning "无效选择，使用IP地址: $DOMAIN"
            ;;
    esac
    
    echo ""
}

# 检查并安装单个包
install_package() {
    local package=$1
    local package_name=${2:-$package}
    
    if command -v $package &> /dev/null; then
        print_success "$package_name 已安装"
        return 0
    fi
    
    print_info "安装 $package_name..."
    
    if apt-get install -y $package &> /dev/null; then
        print_success "$package_name 安装完成"
        return 0
    else
        print_error "$package_name 安装失败"
        return 1
    fi
}

# 检查并安装所有依赖
check_and_install_dependencies() {
    print_info "检查并安装系统依赖..."
    
    # 更新包索引
    print_info "更新包索引..."
    apt-get update -y &> /dev/null || print_warning "包索引更新失败，继续尝试安装"
    
    # 必需工具列表
    declare -A REQUIRED_TOOLS=(
        ["curl"]="curl"
        ["python3"]="python3"
        ["gpg"]="gnupg"
        ["lsb_release"]="lsb-release"
        ["openssl"]="openssl"
        ["zip"]="zip"
        ["unzip"]="unzip"
    )
    
    # 网络工具（至少需要一个）
    declare -A NETWORK_TOOLS=(
        ["ss"]="iproute2"
        ["netstat"]="net-tools"
    )
    
    # 可选工具
    declare -A OPTIONAL_TOOLS=(
        ["qrencode"]="qrencode"
    )
    
    # 安装必需工具
    print_info "安装必需工具..."
    for cmd in "${!REQUIRED_TOOLS[@]}"; do
        install_package "${REQUIRED_TOOLS[$cmd]}" "$cmd"
    done
    
    # 安装网络工具（优先ss）
    print_info "安装网络检测工具..."
    if ! command -v ss &> /dev/null && ! command -v netstat &> /dev/null; then
        install_package "iproute2" "ss"
        if [ $? -ne 0 ]; then
            install_package "net-tools" "netstat"
        fi
    fi
    
    # 安装可选工具
    print_info "安装可选工具..."
    for cmd in "${!OPTIONAL_TOOLS[@]}"; do
        install_package "${OPTIONAL_TOOLS[$cmd]}" "$cmd" || print_warning "$cmd 安装失败（非必需）"
    done
    
    # 检查Python版本
    if command -v python3 &> /dev/null; then
        PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
        print_success "Python3 版本: $PYTHON_VERSION"
    else
        print_error "Python3 安装失败，无法继续"
        exit 1
    fi
    
    print_success "依赖检查和安装完成"
}

# 检查并安装Docker
install_docker() {
    if command -v docker &> /dev/null; then
        print_success "Docker 已安装: $(docker --version)"
        return
    fi
    
    print_info "Docker 未安装，开始安装..."
    
    # 安装依赖
    apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
    
    # 添加Docker官方GPG密钥
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # 设置Docker仓库
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # 安装Docker
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    # 启动Docker
    systemctl start docker
    systemctl enable docker
    
    print_success "Docker 安装完成: $(docker --version)"
}

# 选择端口和协议
select_port_protocol() {
    echo ""
    print_info "请选择OpenVPN监听端口（推荐443用于伪装HTTPS）:"
    echo "  1) 443  (推荐 - 伪装HTTPS)"
    echo "  2) 53   (伪装DNS)"
    echo "  3) 22   (伪装SSH)"
    echo "  4) 1194 (标准OpenVPN端口)"
    echo "  5) 自定义端口"
    read -p "请选择 [1-5]: " port_choice
    
    case $port_choice in
        1) OVPN_PORT=443 ;;
        2) OVPN_PORT=53 ;;
        3) OVPN_PORT=22 ;;
        4) OVPN_PORT=1194 ;;
        5)
            read -p "请输入自定义端口 (1-65535): " OVPN_PORT
            if ! [[ "$OVPN_PORT" =~ ^[0-9]+$ ]] || [ "$OVPN_PORT" -lt 1 ] || [ "$OVPN_PORT" -gt 65535 ]; then
                print_error "无效端口，使用默认443"
                OVPN_PORT=443
            fi
            ;;
        *)
            print_warning "无效选择，使用默认443"
            OVPN_PORT=443
            ;;
    esac
    
    echo ""
    print_info "请选择协议:"
    echo "  1) TCP (推荐 - 配合443端口效果最佳)"
    echo "  2) UDP (性能更好，但可能被封锁)"
    read -p "请选择 [1-2]: " proto_choice
    
    case $proto_choice in
        1) OVPN_PROTO="tcp" ;;
        2) OVPN_PROTO="udp" ;;
        *)
            print_warning "无效选择，使用默认TCP"
            OVPN_PROTO="tcp"
            ;;
    esac
    
    print_success "配置: 端口=${OVPN_PORT}, 协议=${OVPN_PROTO}"
}

# 优化的端口检测函数
check_port_usage() {
    local port=$1
    
    # 优先使用ss命令
    if command -v ss &> /dev/null; then
        if ss -tuln | grep -q ":$port "; then
            return 1
        fi
    # fallback到netstat
    elif command -v netstat &> /dev/null; then
        if netstat -tuln | grep -q ":$port "; then
            return 1
        fi
    else
        print_warning "无法检测端口占用（ss和netstat都不可用）"
        return 0
    fi
    
    return 0
}

# 检查OpenVPN端口
check_port() {
    print_info "检查端口 $OVPN_PORT 是否可用..."
    
    if ! check_port_usage $OVPN_PORT; then
        print_error "端口 $OVPN_PORT 已被占用！"
        if command -v ss &> /dev/null; then
            ss -tuln | grep ":$OVPN_PORT "
        else
            netstat -tuln | grep ":$OVPN_PORT "
        fi
        exit 1
    fi
    
    print_success "端口 $OVPN_PORT 可用"
}

# 配置防火墙
configure_firewall() {
    print_info "配置防火墙规则..."
    
    if command -v ufw &> /dev/null; then
        # 检查UFW是否启用
        if ufw status | grep -q "Status: active"; then
            ufw allow $OVPN_PORT/$OVPN_PROTO comment 'OpenVPN' &> /dev/null || true
            print_success "UFW规则已添加"
        else
            print_warning "UFW未启用，跳过规则添加"
        fi
    fi
    
    if command -v firewall-cmd &> /dev/null; then
        if systemctl is-active --quiet firewalld; then
            firewall-cmd --permanent --add-port=$OVPN_PORT/$OVPN_PROTO &> /dev/null || true
            firewall-cmd --reload &> /dev/null || true
            print_success "Firewalld规则已添加"
        else
            print_warning "Firewalld未运行，跳过规则添加"
        fi
    fi
}

# 初始化OpenVPN数据容器
init_openvpn() {
    print_info "初始化OpenVPN配置..."
    
    # 创建数据卷
    docker volume create --name $OVPN_DATA
    
    # 生成配置
    docker run -v $OVPN_DATA:/etc/openvpn --rm kylemanna/openvpn ovpn_genconfig \
        -u $OVPN_PROTO://$DOMAIN:$OVPN_PORT \
        -d \
        -D \
        -p "route 192.168.0.0 255.255.0.0" \
        -p "route 10.0.0.0 255.0.0.0"
    
    # 修改配置文件，确保监听正确的端口
    docker run -v $OVPN_DATA:/etc/openvpn --rm kylemanna/openvpn bash -c "sed -i 's/port 1194/port $OVPN_PORT/g' /etc/openvpn/openvpn.conf"
    docker run -v $OVPN_DATA:/etc/openvpn --rm kylemanna/openvpn bash -c "sed -i 's/proto udp/proto $OVPN_PROTO/g' /etc/openvpn/openvpn.conf"
    
    # 生成CA证书（批处理模式，无交互）
    docker run -v $OVPN_DATA:/etc/openvpn --rm -e EASYRSA_BATCH=1 kylemanna/openvpn ovpn_initpki nopass
    
    print_success "OpenVPN配置初始化完成"
}

# 启动OpenVPN服务
start_openvpn() {
    print_info "启动OpenVPN容器..."
    
    # 删除旧容器（如果存在）
    docker rm -f $CONTAINER_NAME 2>/dev/null || true
    
    # 启动容器（Host网络模式）
    docker run -d \
        --name $CONTAINER_NAME \
        -v $OVPN_DATA:/etc/openvpn \
        --network host \
        --cap-add=NET_ADMIN \
        --restart=always \
        kylemanna/openvpn
    
    sleep 3
    
    if docker ps | grep -q $CONTAINER_NAME; then
        print_success "OpenVPN容器启动成功"
    else
        print_error "OpenVPN容器启动失败"
        docker logs $CONTAINER_NAME
        exit 1
    fi
}

# 生成客户端配置（批处理模式）
generate_client_configs() {
    print_info "生成15个客户端配置文件..."
    
    mkdir -p /root/openvpn-configs
    
    for client in "${!CLIENTS[@]}"; do
        print_info "生成配置: ${CLIENTS[$client]} ($client)"
        
        # 生成客户端证书（批处理模式，移除-it参数）
        docker run -v $OVPN_DATA:/etc/openvpn --rm \
            -e EASYRSA_BATCH=1 \
            kylemanna/openvpn easyrsa build-client-full $client nopass
        
        # 导出配置文件
        docker run -v $OVPN_DATA:/etc/openvpn --rm \
            kylemanna/openvpn ovpn_getclient $client > /root/openvpn-configs/${client}.ovpn
        
        # 添加认证信息到配置文件
        sed -i "/^client$/a auth-user-pass" /root/openvpn-configs/${client}.ovpn
        
        # 创建认证文件
        cat > /root/openvpn-configs/${client}-auth.txt << EOF
$DEFAULT_USER
$DEFAULT_PASS
EOF
        
        print_success "  ✓ ${client}.ovpn 已生成"
    done
    
    print_success "所有客户端配置已生成到 /root/openvpn-configs/"
}

# 查找可用的HTTP端口（9000-9100范围）
find_available_port() {
    print_info "查找可用HTTP端口（范围：$HTTP_PORT_RANGE_START-$HTTP_PORT_RANGE_END）..."
    
    for port in $(seq $HTTP_PORT_RANGE_START $HTTP_PORT_RANGE_END); do
        if check_port_usage $port; then
            echo $port
            return 0
        fi
    done
    
    print_error "端口范围 $HTTP_PORT_RANGE_START-$HTTP_PORT_RANGE_END 内无可用端口"
    return 1
}

# 创建带密码保护的HTTP服务器脚本
create_http_server_script() {
    local port=$1
    
    cat > /root/openvpn-http-server.py << 'PYTHON_SCRIPT_EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import http.server
import socketserver
import base64
import os
import sys
import zipfile
from datetime import datetime
from urllib.parse import unquote
from io import BytesIO

# 配置
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 9000
USERNAME = sys.argv[2] if len(sys.argv) > 2 else "root"
PASSWORD = sys.argv[3] if len(sys.argv) > 3 else "password"
CONFIG_DIR = "/root/openvpn-configs"

class AuthHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    
    def do_AUTHHEAD(self):
        self.send_response(401)
        self.send_header('WWW-Authenticate', 'Basic realm="OpenVPN Config Download"')
        self.send_header('Content-type', 'text/html')
        self.end_headers()
    
    def check_auth(self):
        auth_header = self.headers.get('Authorization')
        if auth_header is None:
            return False
        
        auth_decoded = base64.b64decode(auth_header.split(' ')[1]).decode('utf-8')
        username, password = auth_decoded.split(':')
        
        return username == USERNAME and password == PASSWORD
    
    def do_GET(self):
        if not self.check_auth():
            self.do_AUTHHEAD()
            self.wfile.write(b'<html><body><h1>401 Unauthorized</h1><p>Authentication required.</p></body></html>')
            return
        
        # 处理下载所有配置的请求
        if self.path == '/download-all':
            self.send_zip_file()
            return
        
        # 阻止下载.txt文件
        if self.path.endswith('.txt'):
            self.send_error(403, "Forbidden")
            return
        
        # 如果是根路径，显示自定义列表
        if self.path == '/':
            self.send_file_list()
            return
        
        # 其他请求按正常流程处理
        super().do_GET()
    
    def send_zip_file(self):
        """生成并发送包含所有.ovpn文件的ZIP"""
        try:
            # 创建内存中的ZIP文件
            zip_buffer = BytesIO()
            with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zip_file:
                for filename in os.listdir(CONFIG_DIR):
                    if filename.endswith('.ovpn'):
                        file_path = os.path.join(CONFIG_DIR, filename)
                        zip_file.write(file_path, filename)
            
            # 发送ZIP文件
            zip_buffer.seek(0)
            zip_data = zip_buffer.read()
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/zip')
            zip_filename = f'openvpn-configs-{datetime.now().strftime("%Y%m%d")}.zip'
            self.send_header('Content-Disposition', f'attachment; filename="{zip_filename}"')
            self.send_header('Content-Length', len(zip_data))
            self.end_headers()
            self.wfile.write(zip_data)
            
        except Exception as e:
            self.send_error(500, f"Error listing files: {str(e)}")

# 切换到配置目录
os.chdir(CONFIG_DIR)

# 启动服务器
with socketserver.TCPServer(("", PORT), AuthHTTPRequestHandler) as httpd:
    print(f"✓ HTTP Server started on port {PORT}")
    print(f"✓ Authentication: {USERNAME} / {PASSWORD}")
    print(f"✓ Serving directory: {CONFIG_DIR}")
    httpd.serve_forever()
PYTHON_SCRIPT_EOF
    
    chmod +x /root/openvpn-http-server.py
    
    print_success "HTTP服务器脚本已创建"
}

# 启动HTTP下载服务
start_http_server() {
    print_info "启动配置文件下载服务..."
    
    HTTP_PORT=$(find_available_port)
    
    if [ -z "$HTTP_PORT" ]; then
        print_error "无法找到可用端口，HTTP服务启动失败"
        return 1
    fi
    
    # 创建HTTP服务器脚本
    create_http_server_script $HTTP_PORT
    
    # 停止旧的HTTP服务
    pkill -f "openvpn-http-server.py" 2>/dev/null || true
    sleep 1
    
    # 启动HTTP服务（后台运行）
    nohup python3 /root/openvpn-http-server.py $HTTP_PORT "$HTTP_USERNAME" "$HTTP_PASSWORD" > /tmp/openvpn-http.log 2>&1 &
    HTTP_PID=$!
    
    # 保存PID
    echo $HTTP_PID > /var/run/openvpn-http.pid
    
    sleep 2
    
    # 验证服务是否启动
    if check_port_usage $HTTP_PORT; then
        print_error "HTTP服务启动失败"
        cat /tmp/openvpn-http.log
        return 1
    fi
    
    print_success "HTTP下载服务已启动: http://$DOMAIN:$HTTP_PORT/"
    
    # 配置防火墙
    if command -v ufw &> /dev/null; then
        if ufw status | grep -q "Status: active"; then
            ufw allow $HTTP_PORT/tcp comment 'OpenVPN Config Download' &> /dev/null || true
        fi
    fi
    
    if command -v firewall-cmd &> /dev/null; then
        if systemctl is-active --quiet firewalld; then
            firewall-cmd --permanent --add-port=$HTTP_PORT/tcp &> /dev/null || true
            firewall-cmd --reload &> /dev/null || true
        fi
    fi
    
    # 保存认证信息
    cat > /root/openvpn-http-auth.txt << EOF
╔═══════════════════════════════════════╗
║    OpenVPN 配置文件下载服务信息        ║
╚═══════════════════════════════════════╝

下载地址: http://$DOMAIN:$HTTP_PORT/
用户名: $HTTP_USERNAME
密码: $HTTP_PASSWORD

⚠️  请保存此文件，重启服务器后需要使用
EOF
    
    echo ""
    print_info "配置文件下载服务信息："
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  下载地址: ${BLUE}http://$DOMAIN:$HTTP_PORT/${NC}"
    echo -e "  用户名: ${YELLOW}$HTTP_USERNAME${NC}"
    echo -e "  密码: ${YELLOW}$HTTP_PASSWORD${NC}"
    echo ""
    echo -e "  功能:"
    echo -e "  📦 支持一键下载所有配置（ZIP格式，带日期）"
    echo -e "  📱 支持单独下载每个配置文件"
    echo -e "  🔐 密码保护，安全可靠"
    echo -e "  ❌ .txt 认证文件已隐藏，不可下载"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # 生成二维码（如果安装了qrencode）
    if command -v qrencode &> /dev/null; then
        echo ""
        print_info "扫描二维码快速访问:"
        qrencode -t ANSIUTF8 "http://$DOMAIN:$HTTP_PORT/"
    fi
    
    print_success "认证信息已保存到: /root/openvpn-http-auth.txt"
}

# 创建HTTP服务的systemd服务
create_http_systemd_service() {
    print_info "创建HTTP服务systemd配置..."
    
    cat > /etc/systemd/system/openvpn-http.service << EOF
[Unit]
Description=OpenVPN Config HTTP Download Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/openvpn-configs
ExecStart=/usr/bin/python3 /root/openvpn-http-server.py $HTTP_PORT $HTTP_USERNAME $HTTP_PASSWORD
Restart=always
RestartSec=3
StandardOutput=append:/tmp/openvpn-http.log
StandardError=append:/tmp/openvpn-http.log

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable openvpn-http.service &> /dev/null || true
    
    print_success "HTTP服务已配置为systemd服务（开机自启）"
}

# 创建OpenVPN的systemd服务
create_openvpn_systemd_service() {
    print_info "创建OpenVPN systemd服务..."
    
    cat > /etc/systemd/system/openvpn-docker.service << EOF
[Unit]
Description=OpenVPN Docker Container
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker start $CONTAINER_NAME
ExecStop=/usr/bin/docker stop $CONTAINER_NAME
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable openvpn-docker.service &> /dev/null || true
    
    print_success "OpenVPN systemd服务已创建并设置开机自启"
}

# 显示管理菜单
show_management_menu() {
    cat > /usr/local/bin/openvpn-manage << 'EOF'
#!/bin/bash

OVPN_DATA="ovpn-data-host"
CONTAINER_NAME="openvpn-host"
CONFIG_DIR="/root/openvpn-configs"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

menu() {
    clear
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      OpenVPN 管理菜单 v1.1             ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "  1) 添加新客户端"
    echo "  2) 删除客户端"
    echo "  3) 查看连接日志"
    echo "  4) 查看在线客户端"
    echo "  5) 重启OpenVPN服务"
    echo "  6) 停止OpenVPN服务"
    echo "  7) 查看服务状态"
    echo "  8) 查看配置文件列表"
    echo "  9) 重启HTTP下载服务"
    echo "  10) 查看HTTP服务信息"
    echo "  11) 卸载OpenVPN"
    echo "  0) 退出"
    echo ""
    read -p "请选择 [0-11]: " choice
    
    case $choice in
        1) add_client ;;
        2) remove_client ;;
        3) view_logs ;;
        4) view_online ;;
        5) restart_service ;;
        6) stop_service ;;
        7) check_status ;;
        8) list_configs ;;
        9) restart_http ;;
        10) show_http_info ;;
        11) uninstall ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选择${NC}"; sleep 2; menu ;;
    esac
}

add_client() {
    echo ""
    read -p "输入客户端名称: " client_name
    
    if [ -z "$client_name" ]; then
        echo -e "${RED}客户端名称不能为空${NC}"
        sleep 2
        menu
        return
    fi
    
    echo -e "${BLUE}生成客户端证书...${NC}"
    docker run -v $OVPN_DATA:/etc/openvpn --rm \
        -e EASYRSA_BATCH=1 \
        kylemanna/openvpn easyrsa build-client-full $client_name nopass
    
    echo -e "${BLUE}导出配置文件...${NC}"
    docker run -v $OVPN_DATA:/etc/openvpn --rm \
        kylemanna/openvpn ovpn_getclient $client_name > $CONFIG_DIR/${client_name}.ovpn
    
    # 添加认证信息
    sed -i "/^client$/a auth-user-pass" $CONFIG_DIR/${client_name}.ovpn
    
    echo -e "${GREEN}客户端 $client_name 已创建${NC}"
    echo "配置文件: $CONFIG_DIR/${client_name}.ovpn"
    echo ""
    read -p "按回车继续..." 
    menu
}

remove_client() {
    echo ""
    read -p "输入要删除的客户端名称: " client_name
    
    if [ -z "$client_name" ]; then
        echo -e "${RED}客户端名称不能为空${NC}"
        sleep 2
        menu
        return
    fi
    
    echo -e "${YELLOW}删除客户端证书...${NC}"
    docker run -v $OVPN_DATA:/etc/openvpn --rm \
        kylemanna/openvpn easyrsa revoke $client_name
    
    docker run -v $OVPN_DATA:/etc/openvpn --rm \
        kylemanna/openvpn easyrsa gen-crl
    
    docker restart $CONTAINER_NAME
    
    rm -f $CONFIG_DIR/${client_name}.ovpn
    rm -f $CONFIG_DIR/${client_name}-auth.txt
    
    echo -e "${GREEN}客户端 $client_name 已删除${NC}"
    echo ""
    read -p "按回车继续..." 
    menu
}

view_logs() {
    echo -e "${BLUE}OpenVPN 实时日志（Ctrl+C 退出）:${NC}"
    echo ""
    docker logs -f $CONTAINER_NAME
}

view_online() {
    clear
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      在线客户端列表                    ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    docker exec $CONTAINER_NAME cat /etc/openvpn/openvpn-status.log 2>/dev/null || echo -e "${YELLOW}暂无状态文件${NC}"
    echo ""
    read -p "按回车继续..." 
    menu
}

restart_service() {
    echo -e "${BLUE}重启OpenVPN服务...${NC}"
    docker restart $CONTAINER_NAME
    sleep 2
    if docker ps | grep -q $CONTAINER_NAME; then
        echo -e "${GREEN}OpenVPN服务已重启${NC}"
    else
        echo -e "${RED}重启失败${NC}"
    fi
    sleep 2
    menu
}

stop_service() {
    echo -e "${YELLOW}停止OpenVPN服务...${NC}"
    docker stop $CONTAINER_NAME
    echo -e "${GREEN}OpenVPN服务已停止${NC}"
    sleep 2
    menu
}

check_status() {
    clear
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      OpenVPN 服务状态                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${BLUE}容器运行状态:${NC}"
    docker ps -f name=$CONTAINER_NAME --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    
    echo ""
    echo -e "${BLUE}资源使用情况:${NC}"
    docker stats --no-stream $CONTAINER_NAME 2>/dev/null || echo -e "${YELLOW}容器未运行${NC}"
    
    echo ""
    read -p "按回车继续..." 
    menu
}

list_configs() {
    clear
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      配置文件列表                      ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    cd $CONFIG_DIR
    echo -e "${BLUE}.ovpn 配置文件:${NC}"
    ls -lh *.ovpn 2>/dev/null || echo -e "${YELLOW}无配置文件${NC}"
    
    echo ""
    echo -e "${BLUE}总计:${NC} $(ls -1 *.ovpn 2>/dev/null | wc -l) 个配置文件"
    
    echo ""
    read -p "按回车继续..." 
    menu
}

restart_http() {
    echo -e "${BLUE}重启HTTP下载服务...${NC}"
    systemctl restart openvpn-http.service
    sleep 2
    if systemctl is-active --quiet openvpn-http.service; then
        echo -e "${GREEN}HTTP服务已重启${NC}"
    else
        echo -e "${RED}重启失败，查看日志: tail /tmp/openvpn-http.log${NC}"
    fi
    sleep 2
    menu
}

show_http_info() {
    clear
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      HTTP下载服务信息                  ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ -f /root/openvpn-http-auth.txt ]; then
        cat /root/openvpn-http-auth.txt
    else
        echo -e "${YELLOW}认证信息文件不存在${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}服务状态:${NC}"
    systemctl status openvpn-http.service --no-pager | grep -E "Active|Main PID"
    
    echo ""
    read -p "按回车继续..." 
    menu
}

uninstall() {
    echo ""
    echo -e "${RED}⚠️  警告：此操作将删除所有OpenVPN配置和数据！${NC}"
    read -p "确认卸载OpenVPN? (输入 YES 确认): " confirm
    
    if [ "$confirm" = "YES" ]; then
        echo -e "${YELLOW}停止服务...${NC}"
        systemctl stop openvpn-docker.service 2>/dev/null || true
        systemctl stop openvpn-http.service 2>/dev/null || true
        
        echo -e "${YELLOW}删除容器和数据...${NC}"
        docker stop $CONTAINER_NAME 2>/dev/null || true
        docker rm $CONTAINER_NAME 2>/dev/null || true
        docker volume rm $OVPN_DATA 2>/dev/null || true
        
        echo -e "${YELLOW}删除systemd服务...${NC}"
        systemctl disable openvpn-docker.service 2>/dev/null || true
        systemctl disable openvpn-http.service 2>/dev/null || true
        rm -f /etc/systemd/system/openvpn-docker.service
        rm -f /etc/systemd/system/openvpn-http.service
        systemctl daemon-reload
        
        echo -e "${YELLOW}删除配置文件...${NC}"
        rm -rf $CONFIG_DIR
        rm -f /root/openvpn-http-server.py
        rm -f /root/openvpn-http-auth.txt
        rm -f /usr/local/bin/openvpn-manage
        
        echo -e "${GREEN}OpenVPN已完全卸载${NC}"
        sleep 2
        exit 0
    else
        echo -e "${BLUE}取消卸载${NC}"
        sleep 2
        menu
    fi
}

menu
EOF
    
    chmod +x /usr/local/bin/openvpn-manage
    print_success "管理脚本已创建: openvpn-manage"
}

# 测试OpenVPN服务
test_openvpn() {
    print_info "测试OpenVPN服务..."
    
    sleep 5  # 等待服务完全启动
    
    # 检查容器进程
    if docker exec $CONTAINER_NAME ps aux | grep -q "[o]penvpn"; then
        print_success "OpenVPN进程运行正常"
    else
        print_error "OpenVPN进程未运行"
        docker logs --tail 30 $CONTAINER_NAME
        return 1
    fi
    
    # 检查端口监听
    if check_port_usage $OVPN_PORT; then
        print_warning "端口 $OVPN_PORT 监听检测异常"
        
        echo ""
        print_info "OpenVPN配置信息:"
        docker run -v $OVPN_DATA:/etc/openvpn --rm kylemanna/openvpn \
            cat /etc/openvpn/openvpn.conf | grep -E "^port|^proto"
        
        echo ""
        print_info "容器日志（最后20行）:"
        docker logs --tail 20 $CONTAINER_NAME
        
        return 1
    else
        print_success "端口 $OVPN_PORT 监听正常"
    fi
    
    return 0
}

# 显示部署总结
show_summary() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗"
    echo "║               OpenVPN 部署完成！v1.1                       ║"
    echo "╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}服务器信息:${NC}"
    echo "  域名: $DOMAIN"
    echo "  端口: $OVPN_PORT"
    echo "  协议: ${OVPN_PROTO^^}"
    echo ""
    echo -e "${BLUE}客户端配置:${NC}"
    echo "  配置目录: /root/openvpn-configs/"
    echo "  配置数量: 15个（涵盖所有设备）"
    echo ""
    echo -e "${BLUE}内置VPN账户:${NC}"
    echo "  用户名: $DEFAULT_USER"
    echo "  密码: $DEFAULT_PASS"
    echo ""
    echo -e "${BLUE}HTTP下载服务:${NC}"
    echo "  地址: http://$DOMAIN:$HTTP_PORT/"
    echo "  用户名: $HTTP_USERNAME"
    echo "  密码: $HTTP_PASSWORD"
    echo "  功能: 密码保护 + 一键打包下载 + 隐藏txt文件"
    echo ""
    echo -e "${BLUE}管理命令:${NC}"
    echo "  openvpn-manage                    # 打开管理菜单"
    echo "  systemctl status openvpn-docker   # 查看OpenVPN状态"
    echo "  systemctl status openvpn-http     # 查看HTTP服务状态"
    echo "  docker logs $CONTAINER_NAME       # 查看OpenVPN日志"
    echo "  tail -f /tmp/openvpn-http.log     # 查看HTTP服务日志"
    echo ""
    echo -e "${YELLOW}注意事项:${NC}"
    echo "  1. ✓ 每个设备建议使用独立配置文件"
    echo "  2. ✓ HTTP下载服务已添加密码保护"
    echo "  3. ✓ 支持一键下载所有配置（ZIP格式，带日期）"
    echo "  4. ✓ .txt认证文件已隐藏，不会泄露"
    echo "  5. ✓ 所有服务已配置开机自启"
    echo "  6. ⚠️  确保云服务商安全组已开放端口: $OVPN_PORT, $HTTP_PORT"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    print_info "认证信息已保存至: /root/openvpn-http-auth.txt"
    echo ""
}

# 清理函数（发生错误时调用）
cleanup_on_error() {
    print_error "部署过程中发生错误，正在清理..."
    
    docker stop $CONTAINER_NAME 2>/dev/null || true
    docker rm $CONTAINER_NAME 2>/dev/null || true
    pkill -f "openvpn-http-server.py" 2>/dev/null || true
    
    print_info "部分资源已清理，您可以重新运行脚本"
}

# 主函数
main() {
    # 设置错误时执行清理
    trap cleanup_on_error ERR
    
    print_header
    
    # 1. 检查环境
    check_root
    check_system
    
    # 2. 检测服务器地址（新增）
    detect_server_address
    
    # 3. 安装依赖（改进：完整检查）
    check_and_install_dependencies
    install_docker
    
    # 4. 选择配置
    select_port_protocol
    check_port
    
    # 5. 配置防火墙
    configure_firewall
    
    # 6. 初始化OpenVPN
    init_openvpn
    
    # 7. 启动服务
    start_openvpn
    
    # 8. 生成客户端配置（改进：批处理模式）
    generate_client_configs
    
    # 9. 启动HTTP服务（改进：密码保护+ZIP下载+隐藏txt）
    start_http_server
    
    # 10. 测试服务
    if ! test_openvpn; then
        print_warning "OpenVPN服务测试未完全通过，但服务已启动"
        print_info "请检查防火墙和网络配置"
    fi
    
    # 11. 创建系统服务
    create_openvpn_systemd_service
    create_http_systemd_service
    
    # 12. 创建管理脚本
    show_management_menu
    
    # 13. 显示总结
    show_summary
    
    print_success "部署完成！现在可以下载配置文件并连接VPN了"
}

# 执行主函数
main
            self.send_error(500, f"Error creating ZIP: {str(e)}")
    
    def send_file_list(self):
        """发送自定义文件列表页面（只显示.ovpn文件）"""
        try:
            files = []
            for filename in sorted(os.listdir(CONFIG_DIR)):
                if filename.endswith('.ovpn'):
                    file_path = os.path.join(CONFIG_DIR, filename)
                    file_size = os.path.getsize(file_path)
                    files.append((filename, file_size))
            
            # 生成HTML
            html = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OpenVPN 配置文件下载中心</title>
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{ 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }}
        .container {{
            max-width: 900px;
            margin: 0 auto;
            background: white;
            border-radius: 15px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            overflow: hidden;
        }}
        .header {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }}
        .header h1 {{
            font-size: 28px;
            margin-bottom: 10px;
        }}
        .header p {{
            opacity: 0.9;
            font-size: 14px;
        }}
        .auth-info {{
            background: #f0f4ff;
            padding: 15px;
            text-align: center;
            color: #667eea;
            font-weight: bold;
        }}
        .download-all {{
            padding: 20px;
            text-align: center;
            background: #f8f9fa;
            border-bottom: 2px solid #e9ecef;
        }}
        .download-all a {{
            display: inline-block;
            background: #28a745;
            color: white;
            padding: 15px 40px;
            text-decoration: none;
            border-radius: 8px;
            font-size: 16px;
            font-weight: bold;
            transition: all 0.3s;
            box-shadow: 0 4px 15px rgba(40, 167, 69, 0.3);
        }}
        .download-all a:hover {{
            background: #218838;
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(40, 167, 69, 0.4);
        }}
        .file-list {{
            padding: 20px;
        }}
        .file-list h2 {{
            color: #333;
            margin-bottom: 20px;
            font-size: 20px;
        }}
        .file-item {{
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 15px;
            margin-bottom: 10px;
            background: #f8f9fa;
            border-radius: 8px;
            transition: all 0.3s;
        }}
        .file-item:hover {{
            background: #e9ecef;
            transform: translateX(5px);
        }}
        .file-info {{
            display: flex;
            align-items: center;
            flex: 1;
        }}
        .file-icon {{
            font-size: 24px;
            margin-right: 15px;
        }}
        .file-name {{
            font-weight: 500;
            color: #333;
        }}
        .file-size {{
            color: #6c757d;
            font-size: 14px;
            margin-left: 10px;
        }}
        .download-btn {{
            background: #667eea;
            color: white;
            padding: 8px 20px;
            text-decoration: none;
            border-radius: 5px;
            font-size: 14px;
            transition: all 0.3s;
        }}
        .download-btn:hover {{
            background: #5568d3;
        }}
        .footer {{
            padding: 20px;
            text-align: center;
            color: #6c757d;
            font-size: 14px;
            border-top: 1px solid #e9ecef;
        }}
        .stats {{
            display: flex;
            justify-content: space-around;
            padding: 20px;
            background: #f8f9fa;
        }}
        .stat-item {{
            text-align: center;
        }}
        .stat-value {{
            font-size: 24px;
            font-weight: bold;
            color: #667eea;
        }}
        .stat-label {{
            font-size: 14px;
            color: #6c757d;
            margin-top: 5px;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🔐 OpenVPN 配置文件下载中心</h1>
            <p>安全连接 · 自由访问</p>
        </div>
        
        <div class="auth-info">
            ✓ 已通过身份验证
        </div>
        
        <div class="stats">
            <div class="stat-item">
                <div class="stat-value">{len(files)}</div>
                <div class="stat-label">配置文件</div>
            </div>
            <div class="stat-item">
                <div class="stat-value">{sum(f[1] for f in files) // 1024}</div>
                <div class="stat-label">总大小 (KB)</div>
            </div>
        </div>
        
        <div class="download-all">
            <a href="/download-all">📦 下载所有配置文件 (ZIP)</a>
        </div>
        
        <div class="file-list">
            <h2>📁 客户端配置列表</h2>
"""
            
            for filename, size in files:
                size_kb = size / 1024
                html += f"""
            <div class="file-item">
                <div class="file-info">
                    <div class="file-icon">📱</div>
                    <div>
                        <div class="file-name">{filename}</div>
                        <span class="file-size">{size_kb:.1f} KB</span>
                    </div>
                </div>
                <a href="/{filename}" class="download-btn" download>下载</a>
            </div>
"""
            
            html += f"""
        </div>
        
        <div class="footer">
            <p>⚠️ 请妥善保管配置文件 · 每个设备建议使用独立配置</p>
            <p style="margin-top: 10px; font-size: 12px; opacity: 0.7;">
                OpenVPN Docker Deploy v1.1 · Generated at {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
            </p>
        </div>
    </div>
</body>
</html>
"""
            
            # 发送HTML
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Content-Length', len(html.encode('utf-8')))
            self.end_headers()
            self.wfile.write(html.encode('utf-8'))
            
        except Exception as e:
