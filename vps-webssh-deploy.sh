#!/bin/bash
#
# 文件名: vps-webssh-deploy.sh
# 版本: v2.3
# 作者: chf5762
# 描述: VPS WebSSH服务一键部署和管理脚本 (Host网络模式)
# GitHub: https://github.com/chf5762-sudo/bash
# 
# 更新日志 v2.3:
#   - 采用host网络模式解决容器无法访问宿主机SSH问题
#   - 优化网络配置,确保WebSSH能连接到127.0.0.1:22
#   - 添加SSH服务检查和自动修复
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
SCRIPT_VERSION="v2.3"
CONTAINER_NAME="webssh"
WEBSSH_PORT=8899
SSH_PORT=22
SSH_USER="root"
SSH_PASSWORD="password"
# Docker镜像将根据架构自动选择
DOCKER_IMAGE=""
CONFIG_FILE="/etc/webssh/config.conf"
NETWORK_MODE="host"  # 使用host网络模式

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

# 检测CPU架构并选择合适的镜像
detect_architecture() {
    local arch=$(uname -m)
    
    case $arch in
        x86_64|amd64)
            DOCKER_IMAGE="snsyzb/webssh:latest"
            print_info "检测到架构: x86_64/AMD64"
            print_info "使用镜像: $DOCKER_IMAGE"
            ;;
        aarch64|arm64)
            DOCKER_IMAGE="darktohka/webssh-docker:latest"
            print_info "检测到架构: ARM64"
            print_info "使用镜像: $DOCKER_IMAGE (支持ARM64)"
            ;;
        armv7l|armhf)
            DOCKER_IMAGE="darktohka/webssh-docker:latest"
            print_info "检测到架构: ARMv7"
            print_info "使用镜像: $DOCKER_IMAGE (支持ARMv7)"
            ;;
        *)
            print_warning "检测到未知架构: $arch"
            print_info "尝试使用多架构镜像: darktohka/webssh-docker:latest"
            DOCKER_IMAGE="darktohka/webssh-docker:latest"
            ;;
    esac
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

# 检查SSH服务
check_ssh_service() {
    print_info "检查SSH服务..."
    
    # 检查SSH服务是否运行
    if systemctl is-active --quiet sshd || systemctl is-active --quiet ssh; then
        print_success "SSH服务运行正常"
        
        # 检查SSH端口监听
        if ss -tlnp | grep -q ":$SSH_PORT " || netstat -tlnp 2>/dev/null | grep -q ":$SSH_PORT "; then
            print_success "SSH端口 $SSH_PORT 监听正常"
        else
            print_warning "SSH端口 $SSH_PORT 未监听"
        fi
        
        # 测试本地SSH连接
        if timeout 3 bash -c "</dev/tcp/127.0.0.1/$SSH_PORT" 2>/dev/null; then
            print_success "本地SSH连接测试通过"
        else
            print_warning "本地SSH连接测试失败,尝试修复..."
            # 重启SSH服务
            systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
            sleep 2
            if timeout 3 bash -c "</dev/tcp/127.0.0.1/$SSH_PORT" 2>/dev/null; then
                print_success "SSH服务修复成功"
            else
                print_error "SSH服务修复失败,请手动检查"
            fi
        fi
    else
        print_error "SSH服务未运行"
        print_info "尝试启动SSH服务..."
        systemctl start sshd 2>/dev/null || systemctl start ssh 2>/dev/null
        sleep 2
        if systemctl is-active --quiet sshd || systemctl is-active --quiet ssh; then
            print_success "SSH服务启动成功"
        else
            print_error "SSH服务启动失败,请手动检查"
            exit 1
        fi
    fi
}

# 配置SSH允许密码登录
configure_ssh() {
    print_info "检查SSH配置..."
    
    SSH_CONFIG="/etc/ssh/sshd_config"
    NEED_RESTART=false
    
    # 确保PasswordAuthentication开启
    if grep -q "^PasswordAuthentication no" $SSH_CONFIG; then
        print_info "启用SSH密码认证..."
        sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' $SSH_CONFIG
        NEED_RESTART=true
    elif ! grep -q "^PasswordAuthentication yes" $SSH_CONFIG; then
        echo "PasswordAuthentication yes" >> $SSH_CONFIG
        NEED_RESTART=true
    fi
    
    # 确保PermitRootLogin开启
    if grep -q "^PermitRootLogin" $SSH_CONFIG; then
        if ! grep -q "^PermitRootLogin yes" $SSH_CONFIG; then
            print_info "允许root登录..."
            sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' $SSH_CONFIG
            NEED_RESTART=true
        fi
    else
        echo "PermitRootLogin yes" >> $SSH_CONFIG
        NEED_RESTART=true
    fi
    
    if [ "$NEED_RESTART" = true ]; then
        print_info "重启SSH服务以应用配置..."
        systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null
        sleep 2
        print_success "SSH配置已更新"
    else
        print_success "SSH配置正常"
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
        print_warning "未检测到防火墙,请手动开放端口 $WEBSSH_PORT"
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
NETWORK_MODE=$NETWORK_MODE
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
    echo "网络模式: Host Mode (解决SSH连接问题)"
    print_line
    echo ""
    
    # 1. 检查环境
    print_info "[1/9] 检查运行环境..."
    check_root
    check_system
    detect_architecture
    
    # 2. 检查并安装Docker
    print_info "[2/9] 检查Docker..."
    if ! check_docker; then
        install_docker
    fi
    
    # 3. 检查SSH服务
    print_info "[3/9] 检查SSH服务..."
    check_ssh_service
    
    # 4. 配置SSH
    print_info "[4/9] 配置SSH..."
    configure_ssh
    
    # 5. 停止旧容器
    print_info "[5/9] 清理旧容器..."
    if docker ps -a | grep -q $CONTAINER_NAME; then
        docker stop $CONTAINER_NAME 2>/dev/null || true
        docker rm $CONTAINER_NAME 2>/dev/null || true
        print_success "旧容器已清理"
    else
        print_info "无需清理"
    fi
    
    # 6. 拉取镜像
    print_info "[6/9] 拉取WebSSH镜像..."
    docker pull $DOCKER_IMAGE
    print_success "镜像拉取完成"
    
    # 7. 启动容器
    print_info "[7/9] 启动WebSSH服务 (Host网络模式)..."
    
    # 使用host网络模式启动容器
    if [[ "$DOCKER_IMAGE" == "darktohka/webssh-docker"* ]]; then
        # darktohka 镜像 - host模式
        docker run -d \
            --name $CONTAINER_NAME \
            --restart=always \
            --network host \
            $DOCKER_IMAGE \
            --port=$WEBSSH_PORT \
            --fbidhttp=False \
            --xheaders=False
    else
        # snsyzb 镜像 - host模式
        docker run -d \
            --name $CONTAINER_NAME \
            --restart=always \
            --network host \
            -e SAVEPASS=true \
            $DOCKER_IMAGE \
            wssh --address=0.0.0.0 --port=$WEBSSH_PORT
    fi
    
    sleep 3
    
    if check_container; then
        print_success "WebSSH服务已启动"
    else
        print_error "WebSSH服务启动失败"
        print_info "查看容器日志:"
        docker logs $CONTAINER_NAME
        exit 1
    fi
    
    # 8. 配置防火墙
    print_info "[8/9] 配置防火墙..."
    configure_firewall
    
    # 9. 保存配置
    print_info "[9/9] 保存配置..."
    save_config
    
    # 测试服务
    print_info "测试WebSSH服务..."
    sleep 2
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:$WEBSSH_PORT | grep -q "200\|301\|302"; then
        print_success "WebSSH服务测试通过"
    else
        print_warning "WebSSH服务可能未正常启动,请查看日志"
    fi
    
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
    echo "网络模式: Host Mode"
    echo "系统架构: $(uname -m)"
    echo "使用镜像: $DOCKER_IMAGE"
    echo ""
    echo "SSH连接参数 (在WebSSH界面中使用):"
    echo "  Hostname: 127.0.0.1 或 localhost"
    echo "  Port: $SSH_PORT"
    echo "  Username: $SSH_USER"
    echo "  Password: $SSH_PASSWORD"
    echo ""
    echo "管理命令:"
    echo "  再次运行此脚本进入管理菜单"
    echo "  bash <(curl -fsSL https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/vps-webssh-deploy.sh)"
    echo ""
    echo "查看日志:"
    echo "  docker logs -f $CONTAINER_NAME"
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
        docker ps --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}\t{{.Networks}}"
        echo ""
        echo "资源占用:"
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" $CONTAINER_NAME
        echo ""
        echo "最近日志:"
        docker logs --tail 10 $CONTAINER_NAME
    else
        print_warning "服务未运行"
        echo ""
        echo "容器信息:"
        docker ps -a --filter "name=$CONTAINER_NAME" --format "table {{.Names}}\t{{.Status}}"
    fi
    
    echo ""
    SERVER_IP=$(curl -s ifconfig.me || curl -s ipinfo.io/ip || hostname -I | awk '{print $1}')
    echo "访问地址: http://$SERVER_IP:$WEBSSH_PORT"
    echo "网络模式: $NETWORK_MODE"
    echo ""
    print_line
}

# 查看日志
show_logs() {
    print_info "显示最近50条日志 (按Ctrl+C退出)..."
    echo ""
    docker logs --tail 50 -f $CONTAINER_NAME
}

# 测试SSH连接
test_ssh_connection() {
    echo ""
    print_line
    echo "测试SSH连接"
    print_line
    echo ""
    
    print_info "检查SSH服务..."
    if systemctl is-active --quiet sshd || systemctl is-active --quiet ssh; then
        print_success "SSH服务运行中"
    else
        print_error "SSH服务未运行"
        return
    fi
    
    print_info "测试端口连接..."
    if timeout 3 bash -c "</dev/tcp/127.0.0.1/$SSH_PORT" 2>/dev/null; then
        print_success "SSH端口 $SSH_PORT 可访问"
    else
        print_error "SSH端口 $SSH_PORT 无法访问"
        return
    fi
    
    print_info "测试WebSSH服务..."
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:$WEBSSH_PORT | grep -q "200\|301\|302"; then
        print_success "WebSSH服务正常"
    else
        print_error "WebSSH服务异常"
    fi
    
    echo ""
    print_success "所有测试通过!"
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
            read -p "是否立即重新部署? (y/n): " redeploy
            if [ "$redeploy" = "y" ] || [ "$redeploy" = "Y" ]; then
                save_config
                detect_architecture
                docker stop $CONTAINER_NAME 2>/dev/null || true
                docker rm $CONTAINER_NAME 2>/dev/null || true
                
                # 使用host网络模式重新部署
                if [[ "$DOCKER_IMAGE" == "darktohka/webssh-docker"* ]]; then
                    docker run -d \
                        --name $CONTAINER_NAME \
                        --restart=always \
                        --network host \
                        $DOCKER_IMAGE \
                        --port=$WEBSSH_PORT \
                        --fbidhttp=False \
                        --xheaders=False
                else
                    docker run -d \
                        --name $CONTAINER_NAME \
                        --restart=always \
                        --network host \
                        -e SAVEPASS=true \
                        $DOCKER_IMAGE \
                        wssh --address=0.0.0.0 --port=$WEBSSH_PORT
                fi
                
                configure_firewall
                print_success "重新部署完成"
            fi
            ;;
        2)
            read -p "请输入新的SSH端口: " NEW_PORT
            SSH_PORT=$NEW_PORT
            save_config
            print_info "请确保SSH服务也使用相同端口"
            ;;
        3)
            read -p "请输入新的SSH用户: " NEW_USER
            SSH_USER=$NEW_USER
            save_config
            ;;
        4)
            read -s -p "请输入新的SSH密码: " NEW_PASS
            echo ""
            SSH_PASSWORD=$NEW_PASS
            save_config
            print_info "请确保系统用户密码已同步修改"
            ;;
        0)
            return
            ;;
        *)
            print_error "无效选择"
            return
            ;;
    esac
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
        if docker images | grep -q "$DOCKER_IMAGE"; then
            read -p "是否同时删除Docker镜像? (y/n): " del_image
            if [ "$del_image" = "y" ] || [ "$del_image" = "Y" ]; then
                docker rmi $DOCKER_IMAGE 2>/dev/null || true
                print_success "镜像已删除"
            fi
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
        echo "  6. 测试连接"
        echo "  7. 修改配置"
        echo "  8. 卸载服务"
        echo "  0. 退出"
        echo ""
        read -p "请选择操作 [0-8]: " choice
        
        case $choice in
            1) start_service ;;
            2) stop_service ;;
            3) restart_service ;;
            4) show_status ;;
            5) show_logs ;;
            6) test_ssh_connection ;;
            7) modify_config ;;
            8) uninstall_service ;;
            0) 
                print_info "退出管理菜单"
                exit 0
                ;;
            *)
                print_error "无效选择,请重试"
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
        # 已安装,进入管理菜单
        load_config
        # 加载架构信息
        if [ -z "$DOCKER_IMAGE" ]; then
            detect_architecture
        fi
        show_menu
    else
        # 未安装,执行部署
        deploy_webssh
    fi
}

# 运行主程序
main
