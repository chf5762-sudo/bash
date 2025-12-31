#!/bin/bash

# XFCE4 + xrdp 智能安装脚本
# 功能: 
# - 安装 XFCE4 桌面环境
# - 配置 xrdp 远程桌面
# - 智能 HDMI 检测(有显示器才启动图形界面)
# - 摄像头调试工具

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 日志文件
LOG_FILE="/var/log/xfce_xrdp_install.log"

# 打印函数
print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_step() {
    echo -e "${CYAN}[步骤] $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $1" >> "$LOG_FILE"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $1" >> "$LOG_FILE"
}

# 检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then 
        print_error "请使用 root 权限运行此脚本"
        echo "使用方法: sudo $0"
        exit 1
    fi
}

# 检查网络连接
check_network() {
    print_step "检查网络连接..."
    if ping -c 1 8.8.8.8 &> /dev/null; then
        print_success "网络连接正常"
        return 0
    else
        print_error "网络连接失败,请检查网络设置"
        exit 1
    fi
}

# 更新系统
update_system() {
    print_step "更新软件源..."
    apt-get update >> "$LOG_FILE" 2>&1
    if [ $? -eq 0 ]; then
        print_success "软件源更新完成"
    else
        print_warning "软件源更新遇到问题,继续安装..."
    fi
}

# 安装 X Server
install_xserver() {
    print_step "安装 X Server..."
    
    apt-get install -y \
        xserver-xorg \
        xserver-xorg-core \
        xserver-xorg-input-all \
        xserver-xorg-video-fbdev \
        x11-xserver-utils \
        xinit \
        >> "$LOG_FILE" 2>&1
    
    if [ $? -eq 0 ]; then
        print_success "X Server 安装完成"
    else
        print_error "X Server 安装失败"
        exit 1
    fi
}

# 安装 XFCE4 桌面环境
install_xfce4() {
    print_step "安装 XFCE4 桌面环境..."
    echo "这可能需要几分钟时间,请耐心等待..."
    
    apt-get install -y \
        xfce4 \
        xfce4-goodies \
        xfce4-terminal \
        >> "$LOG_FILE" 2>&1
    
    if [ $? -eq 0 ]; then
        print_success "XFCE4 安装完成"
    else
        print_error "XFCE4 安装失败"
        exit 1
    fi
}

# 安装 xrdp
install_xrdp() {
    print_step "安装 xrdp 远程桌面..."
    
    apt-get install -y \
        xrdp \
        >> "$LOG_FILE" 2>&1
    
    if [ $? -eq 0 ]; then
        print_success "xrdp 安装完成"
    else
        print_error "xrdp 安装失败"
        exit 1
    fi
}

# 配置 xrdp
configure_xrdp() {
    print_step "配置 xrdp..."
    
    # 备份原始配置
    if [ -f /etc/xrdp/xrdp.ini ]; then
        cp /etc/xrdp/xrdp.ini /etc/xrdp/xrdp.ini.backup
    fi
    
    # 配置 xrdp.ini - 优化性能
    cat > /etc/xrdp/xrdp.ini << 'EOF'
[Globals]
ini_version=1
fork=true
port=3389
tcp_nodelay=true
tcp_keepalive=true
security_layer=negotiate
crypt_level=high
certificate=
key_file=
ssl_protocols=TLSv1.2, TLSv1.3
autorun=
allow_channels=true
allow_multimon=true
bitmap_cache=true
bitmap_compression=true
bulk_compression=true
max_bpp=32
new_cursors=true
use_fastpath=both

[Xorg]
name=Xorg
lib=libxup.so
username=ask
password=ask
ip=127.0.0.1
port=-1
code=20
EOF

    # 配置启动脚本 - 使用 XFCE4
    cat > /etc/xrdp/startwm.sh << 'EOF'
#!/bin/sh
# xrdp X session start script

if [ -r /etc/default/locale ]; then
  . /etc/default/locale
  export LANG LANGUAGE
fi

# 启动 XFCE4
startxfce4
EOF

    chmod +x /etc/xrdp/startwm.sh
    
    # 添加 xrdp 用户到 ssl-cert 组
    adduser xrdp ssl-cert 2>/dev/null
    
    print_success "xrdp 配置完成"
}

# 安装摄像头调试工具
install_camera_tools() {
    print_step "安装摄像头调试工具..."
    
    apt-get install -y \
        cheese \
        guvcview \
        v4l-utils \
        ffmpeg \
        >> "$LOG_FILE" 2>&1
    
    if [ $? -eq 0 ]; then
        print_success "摄像头工具安装完成"
        echo ""
        echo -e "${CYAN}摄像头工具说明:${NC}"
        echo "  - cheese: 简单的摄像头查看器"
        echo "  - guvcview: 高级摄像头工具(可调参数)"
        echo "  - v4l2-ctl: 命令行工具,查看摄像头信息"
        echo "  - ffmpeg: 视频捕获和测试"
        echo ""
    else
        print_warning "摄像头工具安装失败(不影响主要功能)"
    fi
}

# 创建 HDMI 检测脚本
create_hdmi_detection() {
    print_step "创建 HDMI 智能检测服务..."
    
    # HDMI 检测脚本
    cat > /usr/local/bin/hdmi-detect.sh << 'EOF'
#!/bin/bash

# HDMI 检测脚本
LOG_FILE="/var/log/hdmi-detect.log"

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 检测 HDMI 连接状态
check_hdmi() {
    # 方法1: 检查 /sys/class/drm
    if [ -d "/sys/class/drm" ]; then
        for card in /sys/class/drm/card*/status; do
            if [ -f "$card" ]; then
                status=$(cat "$card" 2>/dev/null)
                if [ "$status" = "connected" ]; then
                    log_message "检测到 HDMI 连接: $card"
                    return 0
                fi
            fi
        done
    fi
    
    # 方法2: 使用 xrandr (如果 X 已运行)
    if command -v xrandr &> /dev/null; then
        if xrandr 2>/dev/null | grep -q " connected"; then
            log_message "xrandr 检测到显示器连接"
            return 0
        fi
    fi
    
    log_message "未检测到 HDMI 连接"
    return 1
}

# 启动图形界面
start_graphical() {
    log_message "启动图形界面..."
    systemctl isolate graphical.target
}

# 主逻辑
log_message "开始 HDMI 检测"

if check_hdmi; then
    log_message "HDMI 已连接,准备启动图形界面"
    start_graphical
else
    log_message "HDMI 未连接,保持命令行模式"
    systemctl isolate multi-user.target
fi
EOF

    chmod +x /usr/local/bin/hdmi-detect.sh
    
    # 创建 systemd 服务
    cat > /etc/systemd/system/hdmi-detect.service << 'EOF'
[Unit]
Description=HDMI Detection and Auto Start X
After=multi-user.target
Before=graphical.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/hdmi-detect.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # 启用服务
    systemctl daemon-reload
    systemctl enable hdmi-detect.service >> "$LOG_FILE" 2>&1
    
    print_success "HDMI 智能检测服务创建完成"
}

# 创建手动控制脚本
create_control_scripts() {
    print_step "创建手动控制脚本..."
    
    # 启动图形界面脚本
    cat > /usr/local/bin/start-gui << 'EOF'
#!/bin/bash
echo "正在启动图形界面..."
if [ "$DISPLAY" = "" ]; then
    startx
else
    echo "图形界面已在运行"
fi
EOF
    chmod +x /usr/local/bin/start-gui
    
    # 停止图形界面脚本
    cat > /usr/local/bin/stop-gui << 'EOF'
#!/bin/bash
echo "正在停止图形界面..."
systemctl isolate multi-user.target
pkill -u $USER X
EOF
    chmod +x /usr/local/bin/stop-gui
    
    print_success "控制脚本创建完成"
    echo "  - start-gui: 手动启动图形界面"
    echo "  - stop-gui: 停止图形界面"
}

# 配置防火墙(如果存在)
configure_firewall() {
    print_step "配置防火墙规          ..."
    
    if command -v ufw &> /dev/null; then
        ufw allow 3389/tcp >> "$LOG_FILE" 2>&1
        print_success "UFW 防火墙已开放 3389 端口"
    elif command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-port=3389/tcp >> "$LOG_FILE" 2>&1
        firewall-cmd --reload >> "$LOG_FILE" 2>&1
        print_success "firewalld 防火墙已开放 3389 端口"
    else
        print_warning "未检测到防火墙,跳过配置"
    fi
}

# 启动服务
start_services() {
    print_step "启动 xrdp 服务..."
    
    systemctl enable xrdp >> "$LOG_FILE" 2>&1
    systemctl start xrdp >> "$LOG_FILE" 2>&1
    
    if systemctl is-active --quiet xrdp; then
        print_success "xrdp 服务启动成功"
    else
        print_error "xrdp 服务启动失败"
        echo "请查看日志: journalctl -u xrdp"
        exit 1
    fi
}

# 设置默认启动模式
set_default_target() {
    print_step "配置启动模式..."
    
    # 设置默认为 multi-user (命令行)
    # HDMI 检测服务会根据实际情况切换
    systemctl set-default multi-user.target >> "$LOG_FILE" 2>&1
    
    print_success "默认启动模式: 命令行 (智能检测 HDMI)"
}

# 创建用户配置
setup_user_config() {
    print_step "配置用户环境..."
    
    # 获取所有普通用户
    for user_home in /home/*; do
        if [ -d "$user_home" ]; then
            username=$(basename "$user_home")
            
            # 创建 .xsession 文件
            cat > "$user_home/.xsession" << 'EOF'
#!/bin/sh
startxfce4
EOF
            chown $username:$username "$user_home/.xsession"
            chmod +x "$user_home/.xsession"
        fi
    done
    
    print_success "用户环境配置完成"
}

# 系统测试
system_test() {
    print_step "执行系统测试..."
    
    echo ""
    echo -e "${YELLOW}=== 服务状态 ===${NC}"
    
    # 测试 xrdp
    if systemctl is-active --quiet xrdp; then
        print_success "xrdp 服务运行中"
    else
        print_error "xrdp 服务未运行"
    fi
    
    # 测试端口
    if netstat -tuln 2>/dev/null | grep -q ":3389"; then
        print_success "xrdp 端口 3389 已监听"
    else
        print_warning "端口 3389 未监听"
    fi
    
    # HDMI 检测
    echo ""
    echo -e "${YELLOW}=== HDMI 状态 ===${NC}"
    if [ -d "/sys/class/drm" ]; then
        for card in /sys/class/drm/card*/status; do
            if [ -f "$card" ]; then
                status=$(cat "$card" 2>/dev/null)
                if [ "$status" = "connected" ]; then
                    print_success "检测到 HDMI 连接"
                else
                    echo -e "${CYAN}HDMI 状态: $status${NC}"
                fi
            fi
        done
    fi
    
    echo ""
}

# 显示完成信息
show_completion_info() {
    clear
    print_header "安装完成!"
    
    echo ""
    echo -e "${GREEN}✓ XFCE4 桌面环境已安装${NC}"
    echo -e "${GREEN}✓ xrdp 远程桌面已配置${NC}"
    echo -e "${GREEN}✓ HDMI 智能检测已启用${NC}"
    echo -e "${GREEN}✓ 摄像头调试工具已安装${NC}"
    echo ""
    
    echo -e "${CYAN}=== 使用说明 ===${NC}"
    echo ""
    
    echo -e "${YELLOW}1. 远程桌面连接:${NC}"
    echo "   - 使用 RDP 客户端连接到: $(hostname -I | awk '{print $1}'):3389"
    echo "   - Windows: 使用 '远程桌面连接'"
    echo "   - Mac: 使用 'Microsoft Remote Desktop'"
    echo "   - Linux: 使用 'rdesktop' 或 'Remmina'"
    echo ""
    
    echo -e "${YELLOW}2. HDMI 显示:${NC}"
    echo "   - 连接 HDMI: 自动启动图形界面"
    echo "   - 断开 HDMI: 保持命令行模式"
    echo "   - 手动启动图形界面: start-gui"
    echo "   - 停止图形界面: stop-gui"
    echo ""
    
    echo -e "${YELLOW}3. 摄像头调试:${NC}"
    echo "   - 图形界面工具: cheese 或 guvcview"
    echo "   - 命令行查看设备: v4l2-ctl --list-devices"
    echo "   - 测试摄像头: v4l2-ctl -d /dev/video0 --list-formats-ext"
    echo "   - 录制视频: ffmpeg -i /dev/video0 output.mp4"
    echo ""
    
    echo -e "${YELLOW}4. 日志位置:${NC}"
    echo "   - 安装日志: $LOG_FILE"
    echo "   - HDMI 检测日志: /var/log/hdmi-detect.log"
    echo "   - xrdp 日志: /var/log/xrdp.log"
    echo ""
    
    echo -e "${YELLOW}5. 重要提示:${NC}"
    echo "   - 首次远程连接需要输入用户名和密码"
    echo "   - 建议重启系统以完全应用所有配置: reboot"
    echo "   - xrdp 会为每个用户创建独立的桌面会话"
    echo ""
    
    echo -e "${RED}是否现在重启系统? (y/n)${NC}"
    read -p "输入选择: " reboot_choice
    
    if [ "$reboot_choice" = "y" ] || [ "$reboot_choice" = "Y" ]; then
        echo "系统将在 5 秒后重启..."
        sleep 5
        reboot
    else
        echo -e "${GREEN}安装完成!记得稍后重启系统。${NC}"
    fi
}

# 主函数
main() {
    clear
    print_header "XFCE4 + xrdp 智能安装程序"
    
    echo ""
    echo "此脚本将安装:"
    echo "  ✓ XFCE4 桌面环境"
    echo "  ✓ xrdp 远程桌面服务"
    echo "  ✓ X Server 图形服务器"
    echo "  ✓ HDMI 智能检测(自动判断是否启动图形界面)"
    echo "  ✓ 摄像头调试工具(cheese, guvcview, v4l-utils, ffmpeg)"
    echo ""
    echo -e "${YELLOW}预计安装时间: 5-10 分钟${NC}"
    echo ""
    read -p "按回车键开始安装,或 Ctrl+C 取消..."
    
    echo ""
    echo "开始安装..." | tee "$LOG_FILE"
    echo ""
    
    # 执行安装步骤
    check_root
    check_network
    update_system
    install_xserver
    install_xfce4
    install_xrdp
    configure_xrdp
    install_camera_tools
    create_hdmi_detection
    create_control_scripts
    configure_firewall
    setup_user_config
    set_default_target
    start_services
    system_test
    
    # 显示完成信息
    show_completion_info
}

# 运行主程序
main
