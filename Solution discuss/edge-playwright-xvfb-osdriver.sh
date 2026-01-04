#!/bin/bash

# 颜色定义
G='\033[0;32m'
Y='\033[1;33m'
R='\033[0;31m'
NC='\033[0m'

# 检查权限
if [ "$EUID" -ne 0 ]; then 
  echo -e "${R}错误: 请使用 sudo 运行此脚本${NC}"
  exit 1
fi

# ====================================================
# 函数：配置开机自启 (方案 C 自动化)
# ====================================================
setup_autostart() {
    echo -e "${Y}正在配置开机自动启动虚拟显示 (XVFB)...${NC}"
    # 检查 crontab 是否已经有记录，没有则添加
    CRON_CMD="@reboot /usr/bin/Xvfb :99 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset > /dev/null 2>&1 &"
    (crontab -l 2>/dev/null | grep -F "$CRON_CMD") || (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
    echo -e "${G}已成功添加开机自启任务到 Crontab。${NC}"
}

# ====================================================
# 函数：配置环境变量 (DISPLAY=:99)
# ====================================================
setup_display_env() {
    echo -e "${Y}正在配置 DISPLAY 环境变量...${NC}"
    export DISPLAY=:99
    # 写入用户配置文件
    if ! grep -q "export DISPLAY=:99" ~/.bashrc; then
        echo 'export DISPLAY=:99' >> ~/.bashrc
    fi
    # 写入系统全局环境
    if ! grep -q "DISPLAY=:99" /etc/environment; then
        echo 'DISPLAY=:99' >> /etc/environment
    fi
}

# ====================================================
# 函数：安装所有
# ====================================================
install_all() {
    echo -e "${Y}--- 开始全量安装 ---${NC}"
    rm -f /etc/apt/sources.list.d/caddy*.list
    apt update
    
    echo -e "${Y}步骤 1: 安装 XVFB 及图形工具...${NC}"
    apt install -y xvfb x11-utils xauth curl python3-pip python3-venv tmux net-tools gpg
    
    setup_display_env
    setup_autostart
    
    echo -e "${Y}步骤 2: 安装 Microsoft Edge...${NC}"
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-edge.gpg
    echo "deb [arch=arm64 signed-by=/usr/share/keyrings/microsoft-edge.gpg] https://packages.microsoft.com/repos/edge stable main" > /etc/apt/sources.list.d/microsoft-edge.list
    apt update && apt install -y microsoft-edge-stable
    
    echo -e "${Y}步骤 3: 配置 Python 环境...${NC}"
    mkdir -p ~/commander_vps && cd ~/commander_vps
    python3 -m venv venv
    source venv/bin/activate
    pip install playwright fastapi uvicorn
    
    echo -e "${Y}步骤 4: 安装驱动补丁...${NC}"
    playwright install-deps
    
    echo -e "${G}安装成功！已配置开机自启。${NC}"
}

# ====================================================
# 函数：检测、修复与环境激活
# ====================================================
check_and_fix() {
    echo -e "${Y}--- 正在检查系统环境 ---${NC}"
    
    if ! pgrep Xvfb >/dev/null; then
        echo -e "${Y}[修复] 发现 XVFB 未运行，正在启动...${NC}"
        Xvfb :99 -screen 0 1920x1080x24 -ac +extension GLX +render -noreset &
        sleep 2
    else
        echo -e "[${G}OK${NC}] XVFB 正在运行"
    fi

    if [ "$DISPLAY" != ":99" ]; then
        echo -e "${Y}[修复] 重新声明 DISPLAY 变量...${NC}"
        export DISPLAY=:99
    fi
    
    setup_autostart # 顺便检查自启配置
    echo -e "${G}环境检查并修复完成！${NC}"
}

# ====================================================
# 函数：一键测试环境
# ====================================================
test_env() {
    # 确保在运行测试前环境是激活的
    if [ ! -f ~/commander_vps/venv/bin/activate ]; then
        echo -e "${R}错误: 虚拟环境不存在，请先执行选项 1 安装${NC}"
        return
    fi
    
    source ~/commander_vps/venv/bin/activate
    export DISPLAY=:99
    echo -e "${Y}正在启动 Edge 验证环境 (模拟脚本控制)...${NC}"
    
    python3 - <<EOF
import os
from playwright.sync_api import sync_playwright
print(f"检测到显示器变量: {os.getenv('DISPLAY')}")
try:
    with sync_playwright() as p:
        # 使用你安装的 Edge 浏览器
        browser = p.chromium.launch(executable_path='/usr/bin/microsoft-edge-stable', headless=True)
        page = browser.new_page()
        print("正在尝试访问百度...")
        page.goto("https://www.baidu.com", timeout=15000)
        title = page.title()
        if "百度" in title:
            print(f"\033[0;32m[成功]\033[0m 浏览器运行正常，页面标题: {title}")
        else:
            print(f"\033[1;33m[警告]\033[0m 页面已打开但标题不匹配: {title}")
        browser.close()
except Exception as e:
    print(f"\033[0;31m[失败]\033[0m 错误原因: {e}")
EOF
}

# ====================================================
# 菜单主界面
# ====================================================
while true; do
    clear
    echo "==========================================="
    echo "   Edge 自动化管理系统 - Ubuntu ARM64"
    echo "==========================================="
    echo -e "1) ${G}安装所有 (全量部署 + 开机自启)${NC}"
    echo -e "2) ${Y}检测并修复 (手动拉起服务/修复变量)${NC}"
    echo -e "3) ${G}一键测试环境 (模拟脚本运行)${NC}"
    echo "4) 退出"
    echo "==========================================="
    read -p "请选择 [1-4]: " choice

    case $choice in
        1) install_all; read -p "按回车键继续..." ;;
        2) check_and_fix; read -p "按回车键继续..." ;;
        3) test_env; read -p "按回车键继续..." ;;
        4) exit 0 ;;
        *) echo -e "${R}无效选项${NC}"; sleep 1 ;;
    esac
done
