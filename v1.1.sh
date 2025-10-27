#!/bin/bash

################################################################################
# 文件名: openvpn-docker-v1.0.sh
# 版本号: v1.0
# 用途: OpenVPN Docker 一键部署脚本 - Host网络模式
# 作者: chf5762
# 日期: 2025-10-27
# 部署目标: vps1.chf5762.cloudns.org
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
DOMAIN="vps1.chf5762.cloudns.org"
DEFAULT_USER="root"
DEFAULT_PASS="password"

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
    echo "║         OpenVPN Docker 一键部署脚本 v1.0                  ║"
    echo "║         Host网络模式 - 高性能部署                         ║"
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

# 检查并安装Docker
install_docker() {
    if command -v docker &> /dev/null; then
        print_success "Docker 已安装: $(docker --version)"
        return
    fi
    
    print_info "Docker 未安装，开始安装..."
    
    # 更新包索引
    apt-get update -y
    
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

# 检查端口是否被占用
check_port() {
    if netstat -tuln | grep -q ":$OVPN_PORT "; then
        print_error "端口 $OVPN_PORT 已被占用！"
        netstat -tuln | grep ":$OVPN_PORT "
        exit 1
    fi
}

# 配置防火墙
configure_firewall() {
    print_info "配置防火墙规则..."
    
    if command -v ufw &> /dev/null; then
        ufw allow $OVPN_PORT/$OVPN_PROTO comment 'OpenVPN'
        print_success "UFW规则已添加"
    fi
    
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=$OVPN_PORT/$OVPN_PROTO
        firewall-cmd --reload
        print_success "Firewalld规则已添加"
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
    
    # 生成CA证书（自动化，无需交互）
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

# 生成客户端配置
generate_client_configs() {
    print_info "生成15个客户端配置文件..."
    
    mkdir -p /root/openvpn-configs
    
    for client in "${!CLIENTS[@]}"; do
        print_info "生成配置: ${CLIENTS[$client]} ($client)"
        
        # 生成客户端证书
        docker run -v $OVPN_DATA:/etc/openvpn --rm -it kylemanna/openvpn easyrsa build-client-full $client nopass
        
        # 导出配置文件
        docker run -v $OVPN_DATA:/etc/openvpn --rm kylemanna/openvpn ovpn_getclient $client > /root/openvpn-configs/${client}.ovpn
        
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

# 查找可用的HTTP端口
find_available_port() {
    for port in 8888 8000 8080 8081 8082 9000; do
        if ! netstat -tuln | grep -q ":$port "; then
            echo $port
            return
        fi
    done
    echo "8888"  # 默认返回8888
}

# 启动HTTP下载服务
start_http_server() {
    print_info "启动配置文件下载服务..."
    
    HTTP_PORT=$(find_available_port)
    
    # 停止旧的HTTP服务
    pkill -f "python3 -m http.server $HTTP_PORT" 2>/dev/null || true
    
    # 启动HTTP服务
    cd /root/openvpn-configs
    nohup python3 -m http.server $HTTP_PORT > /tmp/openvpn-http.log 2>&1 &
    
    sleep 2
    
    if netstat -tuln | grep -q ":$HTTP_PORT "; then
        print_success "HTTP下载服务已启动: http://$DOMAIN:$HTTP_PORT/"
        
        # 配置防火墙
        if command -v ufw &> /dev/null; then
            ufw allow $HTTP_PORT/tcp comment 'OpenVPN Config Download'
        fi
        
        echo ""
        print_info "配置文件下载地址："
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        for client in "${!CLIENTS[@]}"; do
            echo "  ${CLIENTS[$client]}: http://$DOMAIN:$HTTP_PORT/${client}.ovpn"
        done
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        # 生成二维码（如果安装了qrencode）
        if command -v qrencode &> /dev/null; then
            echo ""
            print_info "扫描二维码访问配置文件列表:"
            qrencode -t ANSIUTF8 "http://$DOMAIN:$HTTP_PORT/"
        else
            print_warning "未安装qrencode，跳过二维码生成（可选安装: apt install qrencode）"
        fi
    else
        print_error "HTTP服务启动失败"
    fi
}

# 创建systemd服务
create_systemd_service() {
    print_info "创建systemd服务..."
    
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
    systemctl enable openvpn-docker.service
    
    print_success "systemd服务已创建并设置开机自启"
}

# 显示管理菜单
show_management_menu() {
    cat > /usr/local/bin/openvpn-manage << 'EOF'
#!/bin/bash

OVPN_DATA="ovpn-data-host"
CONTAINER_NAME="openvpn-host"

menu() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║      OpenVPN 管理菜单                  ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "  1) 添加新客户端"
    echo "  2) 删除客户端"
    echo "  3) 查看连接日志"
    echo "  4) 查看在线客户端"
    echo "  5) 重启OpenVPN服务"
    echo "  6) 停止OpenVPN服务"
    echo "  7) 查看服务状态"
    echo "  8) 重新生成配置下载列表"
    echo "  9) 卸载OpenVPN"
    echo "  0) 退出"
    echo ""
    read -p "请选择 [0-9]: " choice
    
    case $choice in
        1) add_client ;;
        2) remove_client ;;
        3) view_logs ;;
        4) view_online ;;
        5) restart_service ;;
        6) stop_service ;;
        7) check_status ;;
        8) regenerate_list ;;
        9) uninstall ;;
        0) exit 0 ;;
        *) echo "无效选择"; sleep 2; menu ;;
    esac
}

add_client() {
    read -p "输入客户端名称: " client_name
    docker run -v $OVPN_DATA:/etc/openvpn --rm -it kylemanna/openvpn easyrsa build-client-full $client_name nopass
    docker run -v $OVPN_DATA:/etc/openvpn --rm kylemanna/openvpn ovpn_getclient $client_name > /root/openvpn-configs/${client_name}.ovpn
    echo "客户端 $client_name 已创建: /root/openvpn-configs/${client_name}.ovpn"
    read -p "按回车继续..." 
    menu
}

remove_client() {
    read -p "输入要删除的客户端名称: " client_name
    docker run -v $OVPN_DATA:/etc/openvpn --rm -it kylemanna/openvpn easyrsa revoke $client_name
    docker run -v $OVPN_DATA:/etc/openvpn --rm -it kylemanna/openvpn easyrsa gen-crl
    docker restart $CONTAINER_NAME
    rm -f /root/openvpn-configs/${client_name}.ovpn
    echo "客户端 $client_name 已删除"
    read -p "按回车继续..." 
    menu
}

view_logs() {
    docker logs -f $CONTAINER_NAME
}

view_online() {
    docker exec $CONTAINER_NAME cat /etc/openvpn/openvpn-status.log 2>/dev/null || echo "无状态文件"
    read -p "按回车继续..." 
    menu
}

restart_service() {
    docker restart $CONTAINER_NAME
    echo "OpenVPN服务已重启"
    sleep 2
    menu
}

stop_service() {
    docker stop $CONTAINER_NAME
    echo "OpenVPN服务已停止"
    sleep 2
    menu
}

check_status() {
    docker ps | grep $CONTAINER_NAME
    echo ""
    docker stats --no-stream $CONTAINER_NAME 2>/dev/null || echo "容器未运行"
    read -p "按回车继续..." 
    menu
}

regenerate_list() {
    cd /root/openvpn-configs
    ls -lh *.ovpn
    read -p "按回车继续..." 
    menu
}

uninstall() {
    read -p "确认卸载OpenVPN? (yes/no): " confirm
    if [ "$confirm" = "yes" ]; then
        docker stop $CONTAINER_NAME
        docker rm $CONTAINER_NAME
        docker volume rm $OVPN_DATA
        systemctl disable openvpn-docker.service
        rm -f /etc/systemd/system/openvpn-docker.service
        rm -rf /root/openvpn-configs
        echo "OpenVPN已卸载"
        exit 0
    fi
    menu
}

menu
EOF
    
    chmod +x /usr/local/bin/openvpn-manage
    print_success "管理脚本已创建: openvpn-manage"
}

# 测试OpenVPN服务
test_openvpn() {
    print_info "测试OpenVPN服务..."
    
    if docker exec $CONTAINER_NAME ps aux | grep -q openvpn; then
        print_success "OpenVPN进程运行正常"
    else
        print_error "OpenVPN进程未运行"
        return 1
    fi
    
    if docker exec $CONTAINER_NAME netstat -tuln | grep -q ":$OVPN_PORT"; then
        print_success "端口 $OVPN_PORT 监听正常"
    else
        print_error "端口监听异常"
        return 1
    fi
}

# 显示部署总结
show_summary() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗"
    echo "║               OpenVPN 部署完成！                           ║"
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
    echo "  下载方式: HTTP服务器已启动"
    echo ""
    echo -e "${BLUE}内置账户:${NC}"
    echo "  用户名: $DEFAULT_USER"
    echo "  密码: $DEFAULT_PASS"
    echo ""
    echo -e "${BLUE}管理命令:${NC}"
    echo "  openvpn-manage       # 打开管理菜单"
    echo "  docker logs $CONTAINER_NAME  # 查看日志"
    echo "  docker restart $CONTAINER_NAME  # 重启服务"
    echo ""
    echo -e "${YELLOW}注意事项:${NC}"
    echo "  1. 每个设备建议使用独立配置文件"
    echo "  2. 配置文件可共用但同时只能一个设备连接"
    echo "  3. 请妥善保管配置文件，包含完整证书信息"
    echo "  4. 防火墙已自动配置，确保云服务商安全组已开放端口"
    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 主函数
main() {
    print_header
    
    # 1. 检查环境
    check_root
    check_system
    
    # 2. 修复安装环境
    install_docker
    apt-get install -y net-tools qrencode python3 curl
    
    # 3. 选择配置
    select_port_protocol
    check_port
    
    # 4. 配置防火墙
    configure_firewall
    
    # 5. 初始化OpenVPN
    init_openvpn
    
    # 6. 启动服务
    start_openvpn
    
    # 7. 生成客户端配置
    generate_client_configs
    
    # 8. 启动HTTP服务
    start_http_server
    
    # 9. 测试服务
    test_openvpn
    
    # 10. 创建系统服务
    create_systemd_service
    
    # 11. 创建管理脚本
    show_management_menu
    
    # 12. 显示总结
    show_summary
}

# 执行主函数
main
