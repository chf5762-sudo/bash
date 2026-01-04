#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m'

VENV_PATH=~/playwright_env
BROWSER_DATA=~/browser_data
VNC_DISPLAY=:99

show_menu() {
    clear
    echo "========================================"
    echo "  Playwright 浏览器自动化管理工具"
    echo "========================================"
    echo ""
    
    # 检查服务状态
    if pgrep Xvfb > /dev/null; then
        echo -e "${GREEN}● VNC: 运行中${NC}"
    else
        echo -e "${RED}● VNC: 已停止${NC}"
    fi
    
    if pgrep -f browser_daemon > /dev/null; then
        echo -e "${GREEN}● 浏览器: 运行中${NC}"
    else
        echo -e "${RED}● 浏览器: 已停止${NC}"
    fi
    
    echo ""
    echo "========================================"
    echo "1. 完整安装环境（首次使用）"
    echo "2. 启动 VNC 服务"
    echo "3. 启动浏览器（访问 Gemini）"
    echo "4. 停止浏览器"
    echo "5. 重启浏览器"
    echo "6. 打开 Google（后台）"
    echo "7. 打开 YouTube（后台）"
    echo "8. 打开 Gmail（后台）"
    echo "9. 查看服务状态"
    echo "10. 显示访问地址"
    echo "11. 设置开机自启动（VNC + 浏览器）"
    echo "12. 取消开机自启动"
    echo "0. 退出"
    echo "========================================"
}

install_all() {
    echo -e "${YELLOW}开始完整安装...${NC}"
    echo ""
    
    # 1. 更新系统
    echo -e "${YELLOW}[1/8] 更新系统包...${NC}"
    sudo apt update
    
    # 2. 安装基础依赖
    echo -e "${YELLOW}[2/8] 安装基础依赖...${NC}"
    sudo apt install -y python3 python3-venv python3-full python3-pip \
        xvfb x11vnc novnc websockify git screen
    
    # 3. 创建虚拟环境
    echo -e "${YELLOW}[3/8] 创建 Python 虚拟环境...${NC}"
    if [ ! -d "$VENV_PATH" ]; then
        python3 -m venv $VENV_PATH
    fi
    
    # 4. 安装 Playwright
    echo -e "${YELLOW}[4/8] 安装 Playwright...${NC}"
    source $VENV_PATH/bin/activate
    pip install playwright playwright-stealth flask
    
    # 5. 下载 Chromium
    echo -e "${YELLOW}[5/8] 下载 Chromium 浏览器...${NC}"
    playwright install chromium
    
    # 6. 安装浏览器依赖
    echo -e "${YELLOW}[6/8] 安装浏览器系统依赖...${NC}"
    playwright install-deps chromium
    
    # 7. 创建浏览器守护进程脚本
    echo -e "${YELLOW}[7/8] 创建浏览器脚本...${NC}"
    create_browser_daemon
    
    # 8. 添加自动激活
    echo -e "${YELLOW}[8/8] 配置环境...${NC}"
    if ! grep -q "source $VENV_PATH/bin/activate" ~/.bashrc; then
        echo "source $VENV_PATH/bin/activate" >> ~/.bashrc
    fi
    
    echo ""
    echo -e "${GREEN}✓ 安装完成！${NC}"
    echo ""
    read -p "按回车继续..."
}

create_browser_daemon() {
    cat > ~/browser_daemon.py << 'PYEOF'
import os
os.environ['DISPLAY'] = ':99'

from playwright.sync_api import sync_playwright
import time
import sys

print("启动浏览器守护进程...")

# 获取启动URL，默认为 Gemini
start_url = sys.argv[1] if len(sys.argv) > 1 else 'https://gemini.google.com/app'

with sync_playwright() as p:
    context = p.chromium.launch_persistent_context(
        user_data_dir="./browser_data",
        headless=False,
        devtools=False,
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
    
    page = context.pages[0] if context.pages else context.new_page()
    
    # 隐藏自动化特征
    page.add_init_script("""
        Object.defineProperty(navigator, 'webdriver', {get: () => undefined});
        window.navigator.chrome = {runtime: {}};
        Object.defineProperty(navigator, 'plugins', {get: () => [1, 2, 3, 4, 5]});
    """)
    
    print(f"打开: {start_url}")
    page.goto(start_url)
    page.wait_for_load_state('domcontentloaded')
    
    # 添加快捷工具栏
    try:
        page.evaluate("""
            const toolbar = document.createElement('div');
            toolbar.style.cssText = 'position:fixed;top:0;left:0;right:0;background:linear-gradient(135deg,#667eea,#764ba2);padding:10px;z-index:999999;display:flex;gap:8px;box-shadow:0 2px 10px rgba(0,0,0,0.3);';
            
            const shortcuts = [
                {name: '🏠 Google', url: 'https://google.com', color: '#4285f4'},
                {name: '🤖 Gemini', url: 'https://gemini.google.com/app', color: '#8e44ad'},
                {name: '🎬 YouTube', url: 'https://youtube.com', color: '#ff0000'},
                {name: '✉️ Gmail', url: 'https://gmail.com', color: '#ea4335'}
            ];
            
            shortcuts.forEach(item => {
                const btn = document.createElement('a');
                btn.href = item.url;
                btn.textContent = item.name;
                btn.style.cssText = `color:white;padding:6px 12px;background:${item.color};text-decoration:none;border-radius:5px;font-size:13px;font-weight:500;transition:all 0.3s;box-shadow:0 2px 5px rgba(0,0,0,0.2);`;
                btn.onmouseover = () => btn.style.transform = 'translateY(-2px)';
                btn.onmouseout = () => btn.style.transform = 'translateY(0)';
                toolbar.appendChild(btn);
            });
            
            document.body.prepend(toolbar);
        """)
    except:
        pass
    
    print("✓ 浏览器已启动")
    print("访问 VNC 查看: http://你的IP:6080/vnc.html")
    
    # 保持运行
    try:
        while True:
            time.sleep(60)
    except KeyboardInterrupt:
        print("\n关闭浏览器...")
        context.close()
PYEOF
}

start_vnc() {
    echo -e "${YELLOW}启动 VNC 服务...${NC}"
    
    pkill Xvfb 2>/dev/null
    pkill x11vnc 2>/dev/null
    pkill websockify 2>/dev/null
    sleep 2
    
    echo "启动 Xvfb..."
    Xvfb $VNC_DISPLAY -screen 0 1920x1200x24 > /dev/null 2>&1 &
    sleep 2
    
    echo "启动 x11vnc..."
    x11vnc -display $VNC_DISPLAY -forever -shared -rfbport 5900 > /dev/null 2>&1 &
    sleep 2
    
    echo "启动 websockify..."
    websockify --web=/usr/share/novnc/ 6080 localhost:5900 > /dev/null 2>&1 &
    sleep 2
    
    echo -e "${GREEN}✓ VNC 服务已启动${NC}"
    echo ""
    read -p "按回车继续..."
}

start_browser() {
    echo -e "${YELLOW}启动浏览器（Gemini）...${NC}"
    
    # 检查 VNC
    if ! pgrep Xvfb > /dev/null; then
        echo -e "${YELLOW}VNC 未运行，正在启动...${NC}"
        start_vnc
    fi
    
    # 停止旧浏览器
    pkill -f browser_daemon 2>/dev/null
    sleep 2
    
    # 确保脚本存在
    if [ ! -f ~/browser_daemon.py ]; then
        create_browser_daemon
    fi
    
    # 启动浏览器
    source $VENV_PATH/bin/activate
    cd ~
    nohup python3 browser_daemon.py > browser.log 2>&1 &
    sleep 3
    
    if pgrep -f browser_daemon > /dev/null; then
        echo -e "${GREEN}✓ 浏览器已启动${NC}"
    else
        echo -e "${RED}✗ 启动失败，查看日志: cat ~/browser.log${NC}"
    fi
    
    echo ""
    read -p "按回车继续..."
}

stop_browser() {
    echo -e "${YELLOW}停止浏览器...${NC}"
    pkill -f browser_daemon
    pkill -f chromium
    sleep 2
    echo -e "${GREEN}✓ 浏览器已停止${NC}"
    echo ""
    read -p "按回车继续..."
}

restart_browser() {
    stop_browser
    start_browser
}

open_url_background() {
    local url=$1
    local name=$2
    
    echo -e "${YELLOW}后台打开 $name...${NC}"
    
    # 创建临时脚本
    cat > /tmp/open_url.py << URLEOF
import os
os.environ['DISPLAY'] = ':99'
from playwright.sync_api import sync_playwright

try:
    with sync_playwright() as p:
        context = p.chromium.connect_over_cdp("http://localhost:9222")
        page = context.new_page()
        page.goto('$url')
        print("✓ 已打开: $url")
except Exception as e:
    # 如果CDP连接失败，直接打开新浏览器
    context = p.chromium.launch_persistent_context(
        user_data_dir="./browser_data",
        headless=False,
        args=['--no-sandbox', '--disable-dev-shm-usage']
    )
    page = context.pages[0] if context.pages else context.new_page()
    page.goto('$url')
    print("✓ 已打开: $url")
URLEOF
    
    source $VENV_PATH/bin/activate
    python3 /tmp/open_url.py
    rm /tmp/open_url.py
    
    echo -e "${GREEN}✓ $name 已在浏览器中打开${NC}"
    echo ""
    read -p "按回车继续..."
}

check_status() {
    clear
    echo "========================================"
    echo "  服务状态"
    echo "========================================"
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
    
    if pgrep -f browser_daemon > /dev/null; then
        echo -e "${GREEN}✓ 浏览器守护进程运行中${NC}"
    else
        echo -e "${RED}✗ 浏览器未运行${NC}"
    fi
    
    echo ""
    echo "========================================"
    echo ""
    read -p "按回车继续..."
}

show_access_info() {
    clear
    echo "========================================"
    echo "  访问地址"
    echo "========================================"
    echo ""
    
    TAILSCALE_IP=$(ip addr show tailscale0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
    PUBLIC_IP=$(curl -s ifconfig.me 2>/dev/null)
    
    echo -e "${GREEN}noVNC 访问地址：${NC}"
    echo ""
    
    if [ -n "$TAILSCALE_IP" ]; then
        echo "  Tailscale: http://$TAILSCALE_IP:6080/vnc.html"
    fi
    
    echo "  域名: http://vps1.beundredig.eu.org:6080/vnc.html"
    
    if [ -n "$PUBLIC_IP" ]; then
        echo "  公网: http://$PUBLIC_IP:6080/vnc.html"
    fi
    
    echo ""
    echo "========================================"
    echo ""
    read -p "按回车继续..."
}

setup_autostart() {
    echo -e "${YELLOW}设置开机自启动...${NC}"
    
    # 确保脚本存在
    if [ ! -f ~/browser_daemon.py ]; then
        create_browser_daemon
    fi
    
    # VNC 服务
    sudo tee /etc/systemd/system/playwright-vnc.service > /dev/null << 'VNCEOF'
[Unit]
Description=Playwright VNC Service
After=network.target

[Service]
Type=forking
User=root
WorkingDirectory=/root
ExecStart=/bin/bash -c 'Xvfb :99 -screen 0 1920x1200x24 > /dev/null 2>&1 & sleep 2; x11vnc -display :99 -forever -shared -rfbport 5900 > /dev/null 2>&1 & sleep 2; websockify --web=/usr/share/novnc/ 6080 localhost:5900 > /dev/null 2>&1 &'
ExecStop=/usr/bin/pkill Xvfb; /usr/bin/pkill x11vnc; /usr/bin/pkill websockify
Restart=on-failure

[Install]
WantedBy=multi-user.target
VNCEOF
    
    # 浏览器服务
    sudo tee /etc/systemd/system/playwright-browser.service > /dev/null << 'BROWSEREOF'
[Unit]
Description=Playwright Browser Daemon
After=network.target playwright-vnc.service

[Service]
Type=simple
User=root
WorkingDirectory=/root
Environment="DISPLAY=:99"
ExecStart=/root/playwright_env/bin/python3 /root/browser_daemon.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
BROWSEREOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable playwright-vnc.service
    sudo systemctl enable playwright-browser.service
    
    echo ""
    echo -e "${GREEN}✓ 开机自启动已设置${NC}"
    echo "  重启后将自动启动 VNC + 浏览器（Gemini）"
    echo ""
    read -p "按回车继续..."
}

remove_autostart() {
    echo -e "${YELLOW}取消开机自启动...${NC}"
    sudo systemctl disable playwright-vnc.service
    sudo systemctl disable playwright-browser.service
    sudo systemctl stop playwright-vnc.service
    sudo systemctl stop playwright-browser.service
    echo -e "${GREEN}✓ 开机自启动已取消${NC}"
    echo ""
    read -p "按回车继续..."
}

# 主循环
while true; do
    show_menu
    read -p "请选择操作 [0-12]: " choice
    
    case $choice in
        1) install_all ;;
        2) start_vnc ;;
        3) start_browser ;;
        4) stop_browser ;;
        5) restart_browser ;;
        6) open_url_background "https://google.com" "Google" ;;
        7) open_url_background "https://youtube.com" "YouTube" ;;
        8) open_url_background "https://gmail.com" "Gmail" ;;
        9) check_status ;;
        10) show_access_info ;;
        11) setup_autostart ;;
        12) remove_autostart ;;
        0) echo "退出"; exit 0 ;;
        *) echo -e "${RED}无效选择${NC}"; sleep 1 ;;
    esac
done
