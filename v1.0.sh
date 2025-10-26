#!/bin/bash
#
# 文件名: vps-webssh-deploy.sh
# 版本: v2.0
# 作者: chf5762
# 描述: VPS WebSSH服务一键部署和管理脚本
# GitHub: https://github.com/chf5762-sudo/bash
# 
# 功能:
#   - 首次运行: 自动检测环境、安装Docker、部署WebSSH
#   - 再次运行: 进入管理菜单
#   - 管理功能: 启动/停止/重启/状态/日志/配置/卸载
#
# 使用方法:
#   bash <(curl -fsSL https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/vps-webssh-deploy.sh)

set -e

# ============================================
# 配置变量
# ============================================
SCRIPT_VERSION="v2.0"
CONTAINER_NAME="webssh"
WEBSSH_PORT=8899
SSH_PORT=22
SSH_USER="root"
SSH_PASSWORD="@Cyn5762579"
DOCKER_IMAGE="huashengdun/webssh:latest"
CONFIG_FILE="/etc/webssh/config.conf"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================
# 工具函数
# ============================================

# 打印信息
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

# 分隔线
print_line() {
    echo "============================================"
}

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        print_error "请使用root用户运行此脚本"
        exit 1
    fi
}

# 检查系统类型
check_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        print_error "无法识别操作系统"
        exit 1
    fi
    print_info "检测到系统: $OS $VER"
}

# 检查Docker是否安装
check_docker() {
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
        print_success "Docker已安装 (版本: $DOCKER_VERSION)"
        return 0
    else
        print_warning "Docker未安装"
        return 1
    fi
}

# 安装Docker
install_docker() {
    print_info "开始安装Docker..."
    
    # 更新包索引
    print_info "更新包索引..."
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt-get update -qq
    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        yum update -y -q
    fi
    
    # 安装Docker
    print_info "下载并安装Docker..."
    curl -fsSL https://get.docker.com | sh
    
    # 启动Docker服务
    systemctl start docker
    systemctl enable docker
    
    if check_docker; then
        print_success "Docker安装完成"
    else
        print_error "Docker安装失败"
        exit 1
    fi
}

# 配置防火墙
configure_firewall() {
    print_info "配置防火墙..."
    
    # UFW (Ubuntu/Debian)
    if command -v ufw &> /dev/null; then
        if ufw status | grep -q "Status: active"; then
            ufw allow $WEBSSH_PORT/tcp >/dev/null 2>&1
            print_success "UFW防火墙规则已添加"
        fi
    # Firewalld (CentOS/RHEL)
    elif command -v firewall-cmd &> /dev/null; then
        if systemctl is-active --quiet firewalld; then
            firewall-cmd --permanent --add-port=$WEBSSH_PORT/tcp >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
            print_success "Firewalld防火墙规则已添加"
        fi
    else
        print_warning "未检测到防火墙，请手动开放端口 $WEBSSH_PORT"
    fi
}

# 检查容器是否运行
check_container() {
    if docker ps | grep -q $CONTAINER_NAME; then
        return 0
    else
        return 1
    fi
}

# 保存配置
save_config() {
    mkdir -p "$(dirname $CONFIG_FILE)"
    cat > $CONFIG_FILE << EOF
# WebSSH配置文件
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
WEBSSH_PORT=$WEBSSH_PORT
SSH_PORT=$SSH_PORT
SSH_USER=$SSH_USER
SSH_PASSWORD=$SSH_PASSWORD
DOCKER_IMAGE=$DOCKER_IMAGE
CONTAINER_NAME=$CONTAINER_NAME
SCRIPT_VERSION=$SCRIPT_VERSION
EOF
    print_success "配置已保存到 $CONFIG_FILE"
}

# 加载配置
load_config() {
    if [ -f $CONFIG_FILE ]; then
        source $CONFIG_FILE
        print_info "配置已加载"
    fi
}

# ============================================
# 部署功能
# ============================================

# 完整部署流程
deploy_webssh() {
    print_line
    echo "VPS WebSSH 一键部署脚本 $SCRIPT_VERSION"
    print_line
    echo ""
    
    # 1. 检查环境
    print_info "[1/6] 检查运行环境..."
    check_root
    check_system
    
    # 2. 检查并安装Docker
    print_info "[2/6] 检查Docker..."
    if ! check_docker; then
        install_docker
    fi
    
    # 3. 停止旧容器
    print_info "[3/6] 清理旧容器..."
    if docker ps -a | grep -q $CONTAINER_NAME; then
        docker stop $CONTAINER_NAME 2>/dev/null || true
        docker rm $CONTAINER_NAME 2>/dev/null || true
        print_success "旧容器已清理"
    else
        print_info "无需清理"
    fi
    
    # 4. 拉取镜像
    print_info "[4/6] 拉取WebSSH镜像..."
    docker pull $DOCKER_IMAGE
    print_success "镜像拉取完成"
    
    # 5. 启动容器
    print_info "[5/6] 启动WebSSH服务..."
    docker run -d \
        --name $CONTAINER_NAME \
        --restart=always \
        -p $WEBSSH_PORT:8888 \
        -e SAVEPASS=true \
        $DOCKER_IMAGE
    
    sleep 3
    
    if check_container; then
        print_success "WebSSH服务已启动"
    else
        print_error "WebSSH服务启动失败"
        exit 1
    fi
    
    # 6. 配置防火墙
    print_info "[6/6] 配置防火墙..."
    configure_firewall
    
    # 保存配置
    save_config
    
    # 获取服务器IP
    SERVER_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || hostname -I | awk '{print $1}')
    
    # 显示完成信息
    echo ""
    print_line
    print_success "部署完成！"
    print_line
    echo ""
    echo "WebSSH访问地址:"
    echo "  http://$SERVER_IP:$WEBSSH_PORT"
    echo ""
    echo "SSH连接参数:"
    echo "  Hostname: 127.0.0.1"
    echo "  Port: $SSH_PORT"
    echo "  Username: $SSH_USER"
    echo "  Password: $SSH_PASSWORD"
    echo ""
    echo "管理命令:"
    echo "  再次运行此脚本进入管理菜单"
    echo "  $0"
    echo ""
    print_line
}

# ============================================
# 管理功能
# ============================================

# 启动服务
start_service() {
    print_info "启动WebSSH服务..."
    if check_container; then
        print_warning "服务已在运行"
    else
        docker start $CONTAINER_NAME
        sleep 2
        if check_container; then
            print_success "服务已启动"
        else
            print_error "服务启动失败"
        fi
    fi
}

# 停止服务
stop_service() {
    print_info "停止WebSSH服务..."
    if check_container; then
        docker stop $CONTAINER_NAME
        print_success "服务已停止"
    else
        print_warning "服务未运行"
    fi
}

# 重启服务
restart_service() {
    print_info "重启WebSSH服务..."
    docker restart $CONTAINER_NAME
    sleep 2
    if check_container; then
        print_success "服务已重启"
    else
        print_error "服务重启失败"
    fi
}

# 查看状态
show_status() {
    echo ""
    print_line
    echo "WebSSH服务状态"
    print_line
    
    if check_container; then
        print_success "服务运行中"
        echo ""
        echo "容器信息:"
        docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo ""
        echo "资源占用:"
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" $CONTAINER_NAME
    else
        print_warning "服务未运行"
    fi
    
    echo ""
    SERVER_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || hostname -I | awk '{print $1}')
    echo "访问地址: http://$SERVER_IP:$WEBSSH_PORT"
    echo ""
    print_line
}

# 查看日志
show_logs() {
    print_info "显示最近50条日志 (按Ctrl+C退出)..."
    echo ""
    docker logs --tail 50 -f $CONTAINER_NAME
}

# 修改配置
modify_config() {
    echo ""
    print_line
    echo "修改配置"
    print_line
    echo ""
    
    load_config
    
    echo "当前配置:"
    echo "  1. WebSSH端口: $WEBSSH_PORT"
    echo "  2. SSH端口: $SSH_PORT"
    echo "  3. SSH用户: $SSH_USER"
    echo "  4. SSH密码: $SSH_PASSWORD"
    echo ""
    read -p "请选择要修改的配置 (1-4, 0返回): " choice
    
    case $choice in
        1)
            read -p "请输入新的WebSSH端口: " NEW_PORT
            WEBSSH_PORT=$NEW_PORT
            print_info "需要重新部署以应用更改"
            ;;
        2)
            read -p "请输入新的SSH端口: " NEW_PORT
            SSH_PORT=$NEW_PORT
            ;;
        3)
            read -p "请输入新的SSH用户: " NEW_USER
            SSH_USER=$NEW_USER
            ;;
        4)
            read -s -p "请输入新的SSH密码: " NEW_PASS
            echo ""
            SSH_PASSWORD=$NEW_PASS
            ;;
        0)
            return
            ;;
        *)
            print_error "无效选择"
            return
            ;;
    esac
    
    save_config
    print_success "配置已更新"
}

# 卸载服务
uninstall_service() {
    echo ""
    print_warning "警告: 此操作将完全卸载WebSSH服务"
    read -p "确定要继续吗? (yes/no): " confirm
    
    if [ "$confirm" = "yes" ]; then
        print_info "开始卸载..."
        
        # 停止并删除容器
        if docker ps -a | grep -q $CONTAINER_NAME; then
            docker stop $CONTAINER_NAME 2>/dev/null || true
            docker rm $CONTAINER_NAME 2>/dev/null || true
            print_success "容器已删除"
        fi
        
        # 删除镜像
        if docker images | grep -q "huashengdun/webssh"; then
            docker rmi $DOCKER_IMAGE 2>/dev/null || true
            print_success "镜像已删除"
        fi
        
        # 删除配置
        if [ -f $CONFIG_FILE ]; then
            rm -f $CONFIG_FILE
            print_success "配置已删除"
        fi
        
        print_success "卸载完成"
    else
        print_info "已取消卸载"
    fi
}

# 管理菜单
show_menu() {
    while true; do
        echo ""
        print_line
        echo "WebSSH管理菜单 $SCRIPT_VERSION"
        print_line
        echo ""
        echo "  1. 启动服务"
        echo "  2. 停止服务"
        echo "  3. 重启服务"
        echo "  4. 查看状态"
        echo "  5. 查看日志"
        echo "  6. 修改配置"
        echo "  7. 卸载服务"
        echo "  0. 退出"
        echo ""
        read -p "请选择操作 [0-7]: " choice
        
        case $choice in
            1) start_service ;;
            2) stop_service ;;
            3) restart_service ;;
            4) show_status ;;
            5) show_logs ;;
            6) modify_config ;;
            7) uninstall_service ;;
            0) 
                print_info "退出管理菜单"
                exit 0
                ;;
            *)
                print_error "无效选择，请重试"
                ;;
        esac
        
        if [ "$choice" != "5" ]; then
            read -p "按回车键继续..."
        fi
    done
}

# ============================================
# 主程序
# ============================================

main() {
    # 检查是否已安装
    if [ -f $CONFIG_FILE ] && docker ps -a | grep -q $CONTAINER_NAME; then
        # 已安装，进入管理菜单
        load_config
        show_menu
    else
        # 未安装，执行部署
        deploy_webssh
    fi
}

# 运行主程序
main
