#!/bin/bash

#######################################################
# 文件名: socks5_deploy_vps1.sh
# 版本号: v1.0
# 功能: 在VPS1上一键部署无认证SOCKS5代理
# 作者: Auto Generated
# 日期: 2025-10-31
#######################################################

set -e

# 配置变量
SOCKS5_PORT=5009
CONTAINER_NAME="socks5-proxy"
IMAGE_NAME="serjs/go-socks5-proxy"
VPS_DOMAIN="vps1.chf5762.cloudns.org"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}================================${NC}"
echo -e "${GREEN}SOCKS5 代理部署脚本 v1.0${NC}"
echo -e "${GREEN}VPS: ${VPS_DOMAIN}${NC}"
echo -e "${GREEN}================================${NC}\n"

# 检查是否为root用户
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        echo -e "${RED}请使用 root 用户运行此脚本${NC}"
        exit 1
    fi
}

# 检查系统环境
check_system() {
    echo -e "${YELLOW}[1/6] 检查系统环境...${NC}"
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        echo -e "${GREEN}检测到系统: $OS${NC}"
    else
        echo -e "${RED}无法识别操作系统${NC}"
        exit 1
    fi
}

# 安装Docker
install_docker() {
    echo -e "${YELLOW}[2/6] 检查并安装 Docker...${NC}"
    
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}Docker 已安装${NC}"
        docker --version
    else
        echo -e "${YELLOW}开始安装 Docker...${NC}"
        
        # 卸载旧版本
        apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
        
        # 更新包索引
        apt-get update
        
        # 安装依赖
        apt-get install -y \
            ca-certificates \
            curl \
            gnupg \
            lsb-release
        
        # 添加Docker官方GPG密钥
        mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        
        # 设置仓库
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # 安装Docker Engine
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        
        # 启动Docker
        systemctl start docker
        systemctl enable docker
        
        echo -e "${GREEN}Docker 安装完成${NC}"
    fi
}

# 配置防火墙
configure_firewall() {
    echo -e "${YELLOW}[3/6] 配置防火墙...${NC}"
    
    if command -v ufw &> /dev/null; then
        ufw allow ${SOCKS5_PORT}/tcp
        echo -e "${GREEN}UFW 防火墙规则已添加${NC}"
    fi
    
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=${SOCKS5_PORT}/tcp
        firewall-cmd --reload
        echo -e "${GREEN}Firewalld 防火墙规则已添加${NC}"
    fi
}

# 部署SOCKS5代理
deploy_socks5() {
    echo -e "${YELLOW}[4/6] 部署 SOCKS5 代理...${NC}"
    
    # 停止并删除旧容器
    if docker ps -a | grep -q ${CONTAINER_NAME}; then
        echo -e "${YELLOW}删除旧容器...${NC}"
        docker stop ${CONTAINER_NAME} 2>/dev/null || true
        docker rm ${CONTAINER_NAME} 2>/dev/null || true
    fi
    
    # 拉取镜像
    echo -e "${YELLOW}拉取 Docker 镜像...${NC}"
    docker pull ${IMAGE_NAME}
    
    # 启动容器
    echo -e "${YELLOW}启动 SOCKS5 容器...${NC}"
    docker run -d \
        --name ${CONTAINER_NAME} \
        --restart=always \
        -p ${SOCKS5_PORT}:1080 \
        ${IMAGE_NAME}
    
    echo -e "${GREEN}SOCKS5 代理部署完成${NC}"
}

# 测试连接
test_connection() {
    echo -e "${YELLOW}[5/6] 测试代理连接...${NC}"
    
    sleep 3
    
    if docker ps | grep -q ${CONTAINER_NAME}; then
        echo -e "${GREEN}✓ 容器运行正常${NC}"
        
        # 测试端口
        if netstat -tunlp | grep -q ":${SOCKS5_PORT}"; then
            echo -e "${GREEN}✓ 端口 ${SOCKS5_PORT} 已开放${NC}"
        else
            echo -e "${RED}✗ 端口 ${SOCKS5_PORT} 未开放${NC}"
        fi
    else
        echo -e "${RED}✗ 容器启动失败${NC}"
        docker logs ${CONTAINER_NAME}
        exit 1
    fi
}

# 生成管理脚本
create_management_script() {
    echo -e "${YELLOW}[6/6] 生成管理脚本...${NC}"
    
    cat > /usr/local/bin/socks5-manage << 'EOF'
#!/bin/bash

CONTAINER_NAME="socks5-proxy"
SOCKS5_PORT=5009
VPS_DOMAIN="vps1.chf5762.cloudns.org"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}  SOCKS5 代理管理菜单${NC}"
    echo -e "${GREEN}================================${NC}"
    echo -e "1. 启动代理"
    echo -e "2. 停止代理"
    echo -e "3. 重启代理"
    echo -e "4. 查看状态"
    echo -e "5. 查看日志"
    echo -e "6. 查看连接信息"
    echo -e "7. 卸载代理"
    echo -e "0. 退出"
    echo -e "${GREEN}================================${NC}"
}

start_proxy() {
    echo -e "${YELLOW}启动代理...${NC}"
    docker start ${CONTAINER_NAME}
    echo -e "${GREEN}代理已启动${NC}"
}

stop_proxy() {
    echo -e "${YELLOW}停止代理...${NC}"
    docker stop ${CONTAINER_NAME}
    echo -e "${GREEN}代理已停止${NC}"
}

restart_proxy() {
    echo -e "${YELLOW}重启代理...${NC}"
    docker restart ${CONTAINER_NAME}
    echo -e "${GREEN}代理已重启${NC}"
}

show_status() {
    echo -e "${YELLOW}代理状态:${NC}"
    docker ps -a | grep ${CONTAINER_NAME}
    echo -e "\n${YELLOW}端口监听:${NC}"
    netstat -tunlp | grep ${SOCKS5_PORT} || echo "端口未监听"
}

show_logs() {
    echo -e "${YELLOW}最近日志:${NC}"
    docker logs --tail 50 ${CONTAINER_NAME}
}

show_connection_info() {
    echo -e "${GREEN}================================${NC}"
    echo -e "${GREEN}  SOCKS5 连接信息${NC}"
    echo -e "${GREEN}================================${NC}"
    echo -e "服务器地址: ${VPS_DOMAIN}"
    echo -e "端口: ${SOCKS5_PORT}"
    echo -e "协议: SOCKS5"
    echo -e "认证: 无"
    echo -e ""
    echo -e "客户端配置示例:"
    echo -e "  地址: ${VPS_DOMAIN}:${SOCKS5_PORT}"
    echo -e "  用户名: (留空)"
    echo -e "  密码: (留空)"
    echo -e "${GREEN}================================${NC}"
}

uninstall_proxy() {
    read -p "确认卸载 SOCKS5 代理? (y/n): " confirm
    if [ "$confirm" = "y" ]; then
        echo -e "${YELLOW}卸载代理...${NC}"
        docker stop ${CONTAINER_NAME} 2>/dev/null || true
        docker rm ${CONTAINER_NAME} 2>/dev/null || true
        docker rmi serjs/go-socks5-proxy 2>/dev/null || true
        rm -f /usr/local/bin/socks5-manage
        echo -e "${GREEN}卸载完成${NC}"
        exit 0
    fi
}

while true; do
    show_menu
    read -p "请选择操作 [0-7]: " choice
    case $choice in
        1) start_proxy ;;
        2) stop_proxy ;;
        3) restart_proxy ;;
        4) show_status ;;
        5) show_logs ;;
        6) show_connection_info ;;
        7) uninstall_proxy ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效选择${NC}" ;;
    esac
    read -p "按回车继续..."
done
EOF

    chmod +x /usr/local/bin/socks5-manage
    echo -e "${GREEN}管理脚本已创建: /usr/local/bin/socks5-manage${NC}"
}

# 显示部署信息
show_info() {
    echo -e "\n${GREEN}================================${NC}"
    echo -e "${GREEN}  部署完成！${NC}"
    echo -e "${GREEN}================================${NC}"
    echo -e "服务器地址: ${VPS_DOMAIN}"
    echo -e "端口: ${SOCKS5_PORT}"
    echo -e "协议: SOCKS5"
    echo -e "认证: 无需用户名密码"
    echo -e ""
    echo -e "${YELLOW}客户端配置:${NC}"
    echo -e "  ${VPS_DOMAIN}:${SOCKS5_PORT}"
    echo -e ""
    echo -e "${YELLOW}管理命令:${NC}"
    echo -e "  socks5-manage    # 打开管理菜单"
    echo -e "${GREEN}================================${NC}\n"
}

# 主流程
main() {
    check_root
    check_system
    install_docker
    configure_firewall
    deploy_socks5
    test_connection
    create_management_script
    show_info
}

main
