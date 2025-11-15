#!/bin/bash
# WireGuard Docker 一键部署脚本 (Host 网络模式)
# 自动配置宿主机系统参数和 Docker 容器
# 
# 使用方法:
# curl -sL https://你的GitHub地址/wireguard-docker.sh | sudo bash -s -- -y
# curl -sL https://你的GitHub地址/wireguard-docker.sh | sudo bash -s -- -y -p 8000 -n 10

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 默认配置
WG_PORT=8000
WG_PEERS=5
WG_DIR="/opt/wireguard"
CONTAINER_NAME="wireguard"
TIMEZONE="Asia/Singapore"
SERVER_URL=""
CONFIRM=false

# 打印函数
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# 显示帮助
show_help() {
    cat << EOF
WireGuard Docker 一键部署脚本 (Host 模式)

用法: $0 [选项]

选项:
  -y, --yes               跳过确认提示
  -p, --port PORT         WireGuard 端口 (默认: 8000)
  -n, --peers NUM         客户端数量 (默认: 5)
  -u, --url URL           服务器公网 IP 或域名 (不填自动检测)
  -d, --dir PATH          配置文件目录 (默认: /opt/wireguard)
  -t, --timezone TZ       时区 (默认: Asia/Singapore)
  -h, --help              显示帮助信息

示例:
  $0                                          # 交互式安装
  $0 -y                                       # 自动安装
  $0 -y -p 51820 -n 10                       # 自定义端口和客户端数
  $0 -y -u vpn.example.com                   # 指定域名
  $0 -y -p 8000 -u 1.2.3.4                   # 指定 IP 和端口

EOF
}

# 解析参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes)
                CONFIRM=true
                shift
                ;;
            -p|--port)
                WG_PORT="$2"
                shift 2
                ;;
            -n|--peers)
                WG_PEERS="$2"
                shift 2
                ;;
            -u|--url)
                SERVER_URL="$2"
                shift 2
                ;;
            -d|--dir)
                WG_DIR="$2"
                shift 2
                ;;
            -t|--timezone)
                TIMEZONE="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 检查 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要 root 权限运行"
        exit 1
    fi
}

# 检查 Docker
check_docker() {
    print_info "检查 Docker..."
    
    if ! command -v docker &> /dev/null; then
        print_warn "Docker 未安装，正在安装..."
        install_docker
    else
        print_info "Docker 已安装: $(docker --version)"
    fi
    
    # 检查 Docker 服务
    if ! systemctl is-active --quiet docker; then
        print_info "启动 Docker 服务..."
        systemctl start docker
        systemctl enable docker
    fi
}

# 安装 Docker
install_docker() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            ubuntu|debian)
                apt-get update
                apt-get install -y ca-certificates curl gnupg
                install -m 0755 -d /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/$ID/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
                chmod a+r /etc/apt/keyrings/docker.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID $(lsb_release -cs) stable" | \
                    tee /etc/apt/sources.list.d/docker.list > /dev/null
                apt-get update
                apt-get install -y docker-ce docker-ce-cli containerd.io
                ;;
            centos|rhel|fedora)
                yum install -y yum-utils
                yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                yum install -y docker-ce docker-ce-cli containerd.io
                ;;
            *)
                print_error "不支持的操作系统: $ID"
                exit 1
                ;;
        esac
        
        systemctl start docker
        systemctl enable docker
        print_success "Docker 安装完成"
    fi
}

# 获取公网 IP
get_public_ip() {
    if [[ -n "$SERVER_URL" ]]; then
        print_info "使用指定的服务器地址: $SERVER_URL"
        return
    fi
    
    print_info "检测公网 IP..."
    
    # 尝试多个服务
    SERVER_URL=$(curl -s --max-time 5 https://api.ipify.org || \
                 curl -s --max-time 5 https://ifconfig.me || \
                 curl -s --max-time 5 https://icanhazip.com)
    
    if [[ -z "$SERVER_URL" ]]; then
        print_warn "无法自动检测公网 IP"
        read -p "请手动输入服务器公网 IP 或域名: " SERVER_URL
        if [[ -z "$SERVER_URL" ]]; then
            print_error "服务器地址不能为空"
            exit 1
        fi
    else
        print_info "检测到公网 IP: $SERVER_URL"
    fi
}

# 检查端口占用
check_port() {
    if ss -tuln | grep -q ":$WG_PORT "; then
        print_error "端口 $WG_PORT 已被占用"
        ss -tuln | grep ":$WG_PORT"
        exit 1
    fi
    print_info "端口 $WG_PORT 可用"
}

# 配置宿主机系统参数（关键修改）
configure_host_sysctl() {
    print_info "配置宿主机系统参数..."
    
    local sysctl_conf="/etc/sysctl.d/99-wireguard.conf"
    
    # 创建或更新 sysctl 配置文件
    cat > "$sysctl_conf" << EOF
# WireGuard 所需的系统参数
# 由 WireGuard Docker 安装脚本自动生成

# IP 转发 (必需)
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# WireGuard 路由标记 (Host 模式必需)
net.ipv4.conf.all.src_valid_mark = 1

# 网络优化参数
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 防止 SYN flood 攻击
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 8192

# 增加连接跟踪表大小
net.netfilter.nf_conntrack_max = 262144
EOF
    
    # 应用配置
    print_info "应用系统参数..."
    if sysctl -p "$sysctl_conf" >/dev/null 2>&1; then
        print_success "系统参数配置完成"
    else
        print_warn "部分系统参数配置失败（可能是因为内核模块未加载）"
        print_info "关键参数已设置，容器仍可正常运行"
    fi
    
    # 验证关键参数
    print_info "验证关键参数..."
    local ip_forward=$(sysctl -n net.ipv4.ip_forward)
    local src_valid_mark=$(sysctl -n net.ipv4.conf.all.src_valid_mark)
    
    if [[ "$ip_forward" == "1" ]] && [[ "$src_valid_mark" == "1" ]]; then
        print_success "关键参数验证通过 ✓"
        echo "  net.ipv4.ip_forward = $ip_forward"
        echo "  net.ipv4.conf.all.src_valid_mark = $src_valid_mark"
    else
        print_error "关键参数设置失败"
        echo "  net.ipv4.ip_forward = $ip_forward (需要: 1)"
        echo "  net.ipv4.conf.all.src_valid_mark = $src_valid_mark (需要: 1)"
        exit 1
    fi
}

# 配置防火墙
configure_firewall() {
    print_info "配置防火墙..."
    
    # UFW (Ubuntu)
    if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
        print_info "配置 UFW..."
        ufw allow $WG_PORT/udp comment 'WireGuard' || true
        print_info "UFW 规则已添加"
    fi
    
    # firewalld (CentOS/RHEL)
    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        print_info "配置 firewalld..."
        firewall-cmd --permanent --add-port=$WG_PORT/udp || true
        firewall-cmd --reload || true
        print_info "firewalld 规则已添加"
    fi
    
    # iptables (通用)
    if ! iptables -C INPUT -p udp --dport $WG_PORT -j ACCEPT 2>/dev/null; then
        iptables -I INPUT -p udp --dport $WG_PORT -j ACCEPT
        print_info "iptables 规则已添加"
    fi
}

# 停止并删除旧容器
cleanup_old_container() {
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_warn "发现已存在的容器，正在删除..."
        docker stop $CONTAINER_NAME 2>/dev/null || true
        docker rm $CONTAINER_NAME 2>/dev/null || true
        print_info "旧容器已删除"
    fi
}

# 创建配置目录
create_config_dir() {
    print_info "创建配置目录: $WG_DIR"
    mkdir -p "$WG_DIR/config"
    chmod 755 "$WG_DIR"
}

# 启动 WireGuard 容器（关键修改：移除 --sysctl 参数）
start_wireguard() {
    print_info "启动 WireGuard 容器 (Host 网络模式)..."
    
    docker run -d \
        --name=$CONTAINER_NAME \
        --cap-add=NET_ADMIN \
        --cap-add=SYS_MODULE \
        --network=host \
        -e PUID=1000 \
        -e PGID=1000 \
        -e TZ=$TIMEZONE \
        -e SERVERURL=$SERVER_URL \
        -e SERVERPORT=$WG_PORT \
        -e PEERS=$WG_PEERS \
        -e PEERDNS=auto \
        -e INTERNAL_SUBNET=10.13.13.0 \
        -e ALLOWEDIPS=0.0.0.0/0,::/0 \
        -e PERSISTENTKEEPALIVE_PEERS=25 \
        -e LOG_CONFS=true \
        -v $WG_DIR/config:/config \
        -v /lib/modules:/lib/modules:ro \
        --restart unless-stopped \
        lscr.io/linuxserver/wireguard:latest
    
    print_success "WireGuard 容器已启动"
}

# 等待容器初始化
wait_for_container() {
    print_info "等待容器初始化（这可能需要几秒钟）..."
    sleep 5
    
    # 检查容器状态
    if ! docker ps | grep -q $CONTAINER_NAME; then
        print_error "容器启动失败，查看日志..."
        docker logs $CONTAINER_NAME
        exit 1
    fi
    
    # 等待配置文件生成
    local count=0
    while [[ ! -f "$WG_DIR/config/peer1/peer1.conf" ]] && [[ $count -lt 30 ]]; do
        sleep 1
        ((count++))
    done
    
    if [[ -f "$WG_DIR/config/peer1/peer1.conf" ]]; then
        print_success "配置文件生成完成"
    else
        print_warn "配置文件生成可能需要更长时间，请稍后检查"
    fi
}

# 显示配置信息
show_config() {
    echo ""
    echo "======================================"
    print_success "WireGuard 部署完成！"
    echo "======================================"
    echo ""
    print_info "服务器信息："
    echo "  地址: $SERVER_URL"
    echo "  端口: $WG_PORT (UDP)"
    echo "  网络模式: Host"
    echo "  客户端数量: $WG_PEERS"
    echo "  配置目录: $WG_DIR/config"
    echo ""
    print_info "客户端配置文件位置："
    for i in $(seq 1 $WG_PEERS); do
        if [[ -d "$WG_DIR/config/peer$i" ]]; then
            echo "  Peer $i: $WG_DIR/config/peer$i/"
        fi
    done
    echo ""
    print_info "查看 QR 码（在手机上扫描）："
    echo "  docker exec -it $CONTAINER_NAME /app/show-peer 1"
    echo ""
    print_info "常用命令："
    echo "  查看日志: docker logs -f $CONTAINER_NAME"
    echo "  重启容器: docker restart $CONTAINER_NAME"
    echo "  停止容器: docker stop $CONTAINER_NAME"
    echo "  启动容器: docker start $CONTAINER_NAME"
    echo "  查看状态: docker ps | grep $CONTAINER_NAME"
    echo "  进入容器: docker exec -it $CONTAINER_NAME bash"
    echo ""
    print_info "客户端配置："
    echo "  1. 电脑客户端: 复制 $WG_DIR/config/peer1/peer1.conf 文件"
    echo "  2. 手机客户端: 扫描 QR 码或导入配置文件"
    echo ""
    
    # 显示第一个客户端的 QR 码
    if [[ -f "$WG_DIR/config/peer1/peer1.png" ]]; then
        print_info "Peer 1 QR 码已生成: $WG_DIR/config/peer1/peer1.png"
        echo ""
        print_warn "在终端显示 QR 码："
        docker exec $CONTAINER_NAME /app/show-peer 1 2>/dev/null || echo "  (请稍后运行上面的命令)"
    fi
    
    echo ""
    print_info "配置文件内容预览 (Peer 1):"
    if [[ -f "$WG_DIR/config/peer1/peer1.conf" ]]; then
        echo "  ----------------------------------------"
        cat "$WG_DIR/config/peer1/peer1.conf" | sed 's/^/  /'
        echo "  ----------------------------------------"
    fi
    
    echo ""
    print_info "宿主机系统配置："
    echo "  配置文件: /etc/sysctl.d/99-wireguard.conf"
    echo "  IP 转发: $(sysctl -n net.ipv4.ip_forward)"
    echo "  路由标记: $(sysctl -n net.ipv4.conf.all.src_valid_mark)"
}

# 确认安装
confirm_install() {
    if [[ "$CONFIRM" == "false" ]]; then
        echo ""
        print_warn "即将部署 WireGuard Docker 容器，配置如下："
        echo "  服务器地址: ${SERVER_URL:-自动检测}"
        echo "  监听端口: $WG_PORT (UDP)"
        echo "  客户端数量: $WG_PEERS"
        echo "  配置目录: $WG_DIR"
        echo "  网络模式: host (高性能)"
        echo "  时区: $TIMEZONE"
        echo ""
        print_info "将修改宿主机配置："
        echo "  - /etc/sysctl.d/99-wireguard.conf (系统参数)"
        echo "  - 防火墙规则 (允许端口 $WG_PORT)"
        echo ""
        
        if [[ -t 0 ]]; then
            read -p "确认继续？ (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_info "安装已取消"
                exit 0
            fi
        else
            print_warn "检测到非交互式模式，请使用 -y 参数"
            exit 1
        fi
    fi
}

# 主函数
main() {
    echo "======================================"
    echo "  WireGuard Docker 一键部署脚本"
    echo "  Network Mode: Host (高性能)"
    echo "  自动配置宿主机和容器"
    echo "======================================"
    echo ""
    
    parse_args "$@"
    check_root
    get_public_ip
    confirm_install
    
    check_docker
    check_port
    configure_host_sysctl    # 关键步骤：先配置宿主机
    configure_firewall
    cleanup_old_container
    create_config_dir
    start_wireguard          # 然后启动容器（不带 --sysctl）
    wait_for_container
    show_config
    
    echo ""
    print_success "部署完成！请使用客户端配置文件连接 VPN"
    print_info "系统参数已持久化，重启后自动生效"
}

main "$@"