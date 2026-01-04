#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

VENV_PATH=~/playwright_env
BROWSER_DATA=~/browser_data
VNC_DISPLAY=:99

show_menu() {
    clear
    echo "========================================"
    echo "  Playwright 浏览器自动化管理工具"
    echo "========================================"
    echo "1. 完整安装环境（首次使用）"
    echo "2. 启动 VNC 服务"
    echo "3. 停止 VNC 服务"
    echo "4. 查看服务状态"
    echo "5. 测试浏览器（生成并运行 test.py）"
    echo "6. 设置开机自启动"
    echo "7. 取消开机自启动"
    echo "8. 显示访问地址"
    echo "9. 修复 noVNC 路径问题"
    echo "0. 退出"
    echo "========================================"
}

check_status() {
    echo -e "${YELLOW}检查服务状态...${NC}"
    echo ""
    
    if pgrep Xvfb > /dev/null; then
        echo -e "${GREEN}✓ Xvfb 运行中${NC}"
    else
        echo -e "${RED}✗ Xvfb 未运行${NC}"
    fi
    
    if pgrep x11vnc > /dev/null; then
        echo -e "${GREEN}✓ x11vnc 运行中${NC}"
    else
        echo -e "${RED}✗ x11vnc 未运行${NC}"
    fi
    
    if pgrep websockify > /dev/null; then
        echo -e "${GREEN}✓ websockify 运行中${NC}"
    else
        echo -e "${RED}✗ websockify 未运行${NC}"
    fi
    
    echo ""
}

install_all() {
    echo -e "${YELLOW}开始完整安装...${NC}"
    echo ""
    
    # 1. 更新系统
    echo -e "${YELLOW}[1/7] 更新系统包...${NC}"
    sudo apt update
    
    # 2. 安装基础依赖
    echo -e "${YELLOW}[2/7] 安装基础依赖...${NC}"
    sudo apt install -y python3 python3-venv python3-full python3-pip \
        xvfb x11vnc novnc websockify git
    
    # 3. 创建虚拟环境
    echo -e "${YELLOW}[3/7] 创建 Python 虚拟环境...${NC}"
    if [ ! -d "$VENV_PATH" ]; then
        python3 -m venv $VENV_PATH
    fi
    
    # 4. 安装 Playwright
    echo -e "${YELLOW}[4/7] 安装 Playwright...${NC}"
    source $VENV_PATH/bin/activate
    pip install playwright playwright-stealth
    
    # 5. 下载 Chromium
    echo -e "${YELLOW}[5/7] 下载 Chromium 浏览器...${NC}"
    playwright install chromium
    
    # 6. 安装浏览器依赖
    echo -e "${YELLOW}[6/7] 安装浏览器系统依赖...${NC}"
    playwright install-deps chromium
    
    # 7. 修复 noVNC 路径
    echo -e "${YELLOW}[7/7] 检查 noVNC 配置...${NC}"
    if [ ! -d "/usr/share/novnc" ]; then
        echo -e "${YELLOW}noVNC 目录不存在，尝试修复...${NC}"
        if [ -d "/usr/share/novnc" ]; then
            sudo ln -s /usr/share/novnc /usr/share/novnc
        fi
    fi
    
    # 添加自动激活到 bashrc
    if ! grep -q "source $VENV_PATH/bin/activate" ~/.bashrc; then
        echo "source $VENV_PATH/bin/activate" >> ~/.bashrc
    fi
    
    echo ""
    echo -e "${GREEN}✓ 安装完成！${NC}"
    echo ""
    read -p "按回车继续..."
}

start_vnc() {
    echo -e "${YELLOW}启动 VNC 服务...${NC}"
    
    # 停止旧进程
    pkill Xvfb 2>/dev/null
    pkill x11vnc 2>/dev/null
    pkill websockify 2>/dev/null
    sleep 2
    
    # 启动 Xvfb
    echo "启动 Xvfb..."
    Xvfb $VNC_DISPLAY -screen 0 1920x1200x24 > /dev/null 2>&1 &
    sleep 2
    
    # 启动 x11vnc
    echo "启动 x11vnc..."
    x11vnc -display $VNC_DISPLAY -forever -shared -rfbport 5900 > /dev/null 2>&1 &
    sleep 2
    
    # 启动 websockify
    echo "启动 websockify..."
    if [ -d "/usr/share/novnc" ]; then
        websockify --web=/usr/share/novnc/ 6080 localhost:5900 > /dev/null 2>&1 &
    else
        cd /usr/share/novnc && websockify 6080 localhost:5900 > /dev/null 2>&1 &
    fi
    sleep 2
    
    echo ""
    check_status
    echo -e "${GREEN}✓ VNC 服务已启动${NC}"
    echo ""
    read -p "按回车继续..."
}

stop_vnc() {
    echo -e "${YELLOW}停止 VNC 服务...${NC}"
    pkill Xvfb
    pkill x11vnc
    pkill websockify
    sleep 2
    echo -e "${GREEN}✓ 服务已停止${NC}"
    echo ""
    read -p "按回车继续..."
}

create_test_script() {
    cat > ~/test.py << 'TESTEOF'
import os
import time
import random

os.environ['DISPLAY'] = ':99'

from playwright.sync_api import sync_playwright
from playwright_stealth import stealth_sync

with sync_playwright() as p:
    context = p.chromium.launch_persistent_context(
        user_data_dir="./browser_data",
        headless=False,
        args=[
            '--disable-blink-features=AutomationControlled',
            '--disable-dev-shm-usage',
            '--no-sandbox',
            '--disable-setuid-sandbox'
        ],
        ignore_default_args=['--enable-automation'],
        viewport={'width': 1920, 'height': 1080},
        user_agent='Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36'
    )
    
    page = context.pages[0]
    stealth_sync(page)
    
    # 隐藏 webdriver 特征
    page.add_init_script("""
        Object.defineProperty(navigator, 'webdriver', {get: () => undefined});
        window.navigator.chrome = {runtime: {}};
        Object.defineProperty(navigator, 'plugins', {get: () => [1, 2, 3, 4, 5]});
    """)
    
    print("=" * 50)
    print("浏览器已启动")
    print("请访问 VNC 查看浏览器窗口")
    print("=" * 50)
    
    page.goto('https://google.com')
    
    input("\n【人工登录完成后按回车开始自动化测试】\n")
    
    # === 自动化测试 ===
    print("\n开始自动化操作...")
    
    time.sleep(random.uniform(1, 2))
    page.goto('https://www.google.com/search?q=playwright+automation')
    print(f"页面标题: {page.title()}")
    
    time.sleep(random.uniform(2, 3))
    page.mouse.wheel(0, random.randint(200, 400))
    
    time.sleep(random.uniform(1, 2))
    print("\n✓ 测试完成！登录状态已保存到 ./browser_data")
    print("下次运行将自动保持登录状态\n")
    
    input("按回车关闭浏览器...")
    context.close()
TESTEOF
    
    echo -e "${GREEN}✓ 测试脚本已创建: ~/test.py${NC}"
}

run_test() {
    echo -e "${YELLOW}准备运行测试...${NC}"
    echo ""
    
    # 检查 VNC 是否运行
    if ! pgrep Xvfb > /dev/null; then
        echo -e "${RED}VNC 服务未运行，正在启动...${NC}"
        start_vnc
    fi
    
    # 创建测试脚本
    if [ ! -f ~/test.py ]; then
        echo "创建测试脚本..."
        create_test_script
    fi
    
    echo ""
    echo -e "${GREEN}准备就绪，启动测试...${NC}"
    echo ""
    sleep 2
    
    # 运行测试
    source $VENV_PATH/bin/activate
    cd ~
    python3 test.py
}

setup_autostart() {
    echo -e "${YELLOW}设置开机自启动...${NC}"
    
    # 创建 systemd 服务文件
    sudo tee /etc/systemd/system/playwright-vnc.service > /dev/null << 'SERVICEEOF'
[Unit]
Description=Playwright VNC Service
After=network.target

[Service]
Type=forking
User=root
WorkingDirectory=/root
ExecStart=/bin/bash -c 'Xvfb :99 -screen 0 1920x1200x24 & sleep 2; x11vnc -display :99 -forever -shared -rfbport 5900 & sleep 2; cd /usr/share/novnc && websockify 6080 localhost:5900 &'
ExecStop=/usr/bin/pkill -9 Xvfb; /usr/bin/pkill -9 x11vnc; /usr/bin/pkill -9 websockify
Restart=on-failure

[Install]
WantedBy=multi-user.target
SERVICEEOF
    
    # 启用服务
    sudo systemctl daemon-reload
    sudo systemctl enable playwright-vnc.service
    
    echo ""
    echo -e "${GREEN}✓ 开机自启动已设置${NC}"
    echo "服务将在系统重启后自动启动"
    echo ""
    read -p "按回车继续..."
}

remove_autostart() {
    echo -e "${YELLOW}取消开机自启动...${NC}"
    sudo systemctl disable playwright-vnc.service
    sudo systemctl stop playwright-vnc.service
    sudo rm -f /etc/systemd/system/playwright-vnc.service
    sudo systemctl daemon-reload
    echo -e "${GREEN}✓ 开机自启动已取消${NC}"
    echo ""
    read -p "按回车继续..."
}

show_access_info() {
    clear
    echo "========================================"
    echo "  访问地址信息"
    echo "========================================"
    echo ""
    
    # 获取 Tailscale IP
    TAILSCALE_IP=$(ip addr show tailscale0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    
    # 获取公网 IP
    PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null)
    
    echo -e "${GREEN}noVNC Web 访问地址：${NC}"
    echo ""
    
    if [ -n "$TAILSCALE_IP" ]; then
        echo "Tailscale 内网: http://$TAILSCALE_IP:6080/vnc.html"
    fi
    
    echo "域名访问: http://vps1.beundredig.eu.org:6080/vnc.html"
    
    if [ -n "$PUBLIC_IP" ]; then
        echo "公网 IP: http://$PUBLIC_IP:6080/vnc.html"
    fi
    
    echo ""
    echo -e "${YELLOW}VNC 客户端连接：${NC}"
    if [ -n "$TAILSCALE_IP" ]; then
        echo "地址: $TAILSCALE_IP:5900"
    fi
    echo ""
    echo "========================================"
    echo ""
    read -p "按回车继续..."
}

fix_novnc() {
    echo -e "${YELLOW}修复 noVNC 路径问题...${NC}"
    
    # 检查 noVNC 安装
    if ! dpkg -l | grep -q novnc; then
        echo "安装 noVNC..."
        sudo apt install -y novnc
    fi
    
    # 查找实际路径
    NOVNC_PATH=$(dpkg -L novnc | grep vnc.html | head -1 | xargs dirname)
    
    if [ -n "$NOVNC_PATH" ]; then
        echo -e "${GREEN}找到 noVNC 路径: $NOVNC_PATH${NC}"
        
        # 创建软链接
        if [ ! -L "/usr/share/novnc" ] && [ ! -d "/usr/share/novnc" ]; then
            sudo ln -s "$NOVNC_PATH" /usr/share/novnc
            echo -e "${GREEN}✓ 已创建软链接${NC}"
        fi
    else
        echo -e "${YELLOW}从 GitHub 下载 noVNC...${NC}"
        cd /tmp
        git clone https://github.com/novnc/noVNC.git
        sudo mv noVNC /usr/share/novnc
        echo -e "${GREEN}✓ noVNC 已安装${NC}"
    fi
    
    echo ""
    read -p "按回车继续..."
}

# 主循环
while true; do
    show_menu
    read -p "请选择操作 [0-9]: " choice
    
    case $choice in
        1) install_all ;;
        2) start_vnc ;;
        3) stop_vnc ;;
        4) check_status; read -p "按回车继续..." ;;
        5) run_test ;;
        6) setup_autostart ;;
        7) remove_autostart ;;
        8) show_access_info ;;
        9) fix_novnc ;;
        0) echo "退出"; exit 0 ;;
        *) echo -e "${RED}无效选择${NC}"; sleep 1 ;;
    esac
done
