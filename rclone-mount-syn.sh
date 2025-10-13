#!/bin/bash

# Rclone 云盘自动配置脚本
# 支持多种云盘的挂载和同步功能

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置文件路径
RCLONE_CONFIG="/"
LOG_DIR="/var/log/rclone"

# 打印带颜色的消息
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

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本必须以root权限运行"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    print_info "检查并安装依赖..."
    
    if command -v apt &> /dev/null; then
        apt update
        apt install -y curl fuse wget unzip
    elif command -v yum &> /dev/null; then
        yum install -y curl fuse wget unzip
    elif command -v dnf &> /dev/null; then
        dnf install -y curl fuse wget unzip
    else
        print_error "不支持的包管理器"
        exit 1
    fi
    
    print_success "依赖安装完成"
}

# 安装Rclone
install_rclone() {
    if command -v rclone &> /dev/null; then
        print_warning "Rclone 已安装，版本: $(rclone version | head -n1)"
        read -p "是否重新安装? (y/n): " reinstall
        if [[ ! $reinstall =~ ^[Yy]$ ]]; then
            return
        fi
    fi
    
    print_info "开始安装 Rclone..."
    curl https://rclone.org/install.sh | bash
    print_success "Rclone 安装完成"
}

# 显示云盘选择菜单
show_cloud_menu() {
    clear
    echo "=========================================="
    echo "          选择云盘类型"
    echo "=========================================="
    echo ""
    echo "国际云盘:"
    echo "  1) Google Drive (谷歌云端硬盘)"
    echo "  2) OneDrive (微软云盘)"
    echo "  3) Dropbox"
    echo "  4) SFTP"
    echo "  5) WebDAV"
    echo ""
    echo "中国云盘:"
    echo "  6) Baidu Netdisk (百度网盘)"
    echo "  7) Aliyun Drive (阿里云盘)"
    echo "  8) Quark Cloud Drive (夸克网盘)"
    echo "  9) China Telecom Cloud (天翼云盘)"
    echo " 10) China Mobile Cloud (和彩云)"
    echo " 11) Tencent COS (腾讯云对象存储)"
    echo " 12) Alibaba OSS (阿里云对象存储)"
    echo ""
    echo "  0) 退出"
    echo "=========================================="
}

# 获取云盘类型代码
get_cloud_type() {
    case $1 in
        1) echo "drive" ;;
        2) echo "onedrive" ;;
        3) echo "dropbox" ;;
        4) echo "sftp" ;;
        5) echo "webdav" ;;
        6) echo "baidunetdisk" ;;
        7) echo "aliyundrive" ;;
        8) echo "quark" ;;
        9) echo "ctcloud" ;;
        10) echo "chinamobile" ;;
        11) echo "tencentcos" ;;
        12) echo "oss" ;;
        *) echo "" ;;
    esac
}

# 获取云盘名称
get_cloud_name() {
    case $1 in
        1) echo "Google Drive" ;;
        2) echo "OneDrive" ;;
        3) echo "Dropbox" ;;
        4) echo "SFTP" ;;
        5) echo "WebDAV" ;;
        6) echo "百度网盘" ;;
        7) echo "阿里云盘" ;;
        8) echo "夸克网盘" ;;
        9) echo "天翼云盘" ;;
        10) echo "和彩云" ;;
        11) echo "腾讯云COS" ;;
        12) echo "阿里云OSS" ;;
        *) echo "未知" ;;
    esac
}

# 配置云盘
configure_cloud() {
    show_cloud_menu
    read -p "请选择云盘类型 (0-12): " choice
    
    if [[ $choice == "0" ]]; then
        print_info "退出配置"
        exit 0
    fi
    
    cloud_type=$(get_cloud_type $choice)
    cloud_name=$(get_cloud_name $choice)
    
    if [[ -z $cloud_type ]]; then
        print_error "无效的选择"
        exit 1
    fi
    
    print_info "开始配置: $cloud_name"
    
    read -p "请输入配置名称 (例如: mypan): " remote_name
    
    # 设置配置文件路径
    export RCLONE_CONFIG=$RCLONE_CONFIG
    
    print_warning "即将进入 Rclone 配置界面..."
    print_info "请按以下步骤操作:"
    echo "  1. 输入 'n' 创建新配置"
    echo "  2. 输入配置名称: $remote_name"
    echo "  3. 选择存储类型: $cloud_type"
    echo "  4. 按提示完成后续配置"
    echo ""
    read -p "按回车键继续..."
    
    rclone config
    
    # 验证配置
    if rclone listremotes | grep -q "^${remote_name}:$"; then
        print_success "云盘配置成功: $remote_name"
    else
        print_error "配置失败或未找到配置: $remote_name"
        exit 1
    fi
}

# 配置挂载目录
configure_mount() {
    echo ""
    print_info "配置挂载目录"
    
    read -p "请输入挂载目录路径 (默认: /mnt/$remote_name): " mount_dir
    mount_dir=${mount_dir:-/mnt/$remote_name}
    
    # 创建挂载目录
    mkdir -p "$mount_dir"
    print_success "挂载目录创建: $mount_dir"
    
    # 询问远程路径
    read -p "请输入云盘远程路径 (默认: /，即根目录): " remote_path
    remote_path=${remote_path:-/}
}

# 配置同步功能
configure_sync() {
    echo ""
    read -p "是否启用同步功能? (y/n): " enable_sync
    
    if [[ ! $enable_sync =~ ^[Yy]$ ]]; then
        sync_enabled=false
        return
    fi
    
    sync_enabled=true
    
    read -p "请输入本地同步目录 (例如: /data/sync): " sync_dir
    
    if [[ -z $sync_dir ]]; then
        print_error "同步目录不能为空"
        exit 1
    fi
    
    # 创建同步目录
    mkdir -p "$sync_dir"
    print_success "同步目录创建: $sync_dir"
    
    # 配置定时同步
    echo ""
    print_info "配置定时同步"
    echo "  1) 每小时同步一次"
    echo "  2) 每6小时同步一次"
    echo "  3) 每天同步一次 (凌晨2点)"
    echo "  4) 每周同步一次 (周日凌晨2点)"
    echo "  5) 自定义cron表达式"
    echo "  6) 不设置定时同步"
    
    read -p "请选择定时方式 (1-6): " sync_schedule
    
    case $sync_schedule in
        1) cron_expression="0 * * * *" ;;
        2) cron_expression="0 */6 * * *" ;;
        3) cron_expression="0 2 * * *" ;;
        4) cron_expression="0 2 * * 0" ;;
        5)
            read -p "请输入cron表达式: " cron_expression
            ;;
        6)
            cron_expression=""
            print_info "跳过定时同步设置"
            ;;
        *)
            print_warning "无效选择，使用默认值: 每天凌晨2点"
            cron_expression="0 2 * * *"
            ;;
    esac
}

# 创建systemd服务
create_systemd_service() {
    print_info "创建 systemd 挂载服务..."
    
    # 创建日志目录
    mkdir -p "$LOG_DIR"
    
    # 创建挂载服务
    cat > "/etc/systemd/system/rclone-${remote_name}.service" <<EOF
[Unit]
Description=Rclone Mount Service for ${remote_name}
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
Environment=RCLONE_CONFIG=${RCLONE_CONFIG}
ExecStartPre=/bin/mkdir -p ${mount_dir}
ExecStart=/usr/bin/rclone mount ${remote_name}:${remote_path} ${mount_dir} \\
    --config=${RCLONE_CONFIG} \\
    --allow-other \\
    --allow-non-empty \\
    --vfs-cache-mode writes \\
    --vfs-cache-max-size 10G \\
    --vfs-cache-max-age 24h \\
    --buffer-size 32M \\
    --dir-cache-time 12h \\
    --poll-interval 15s \\
    --umask 000 \\
    --log-level INFO \\
    --log-file=${LOG_DIR}/${remote_name}-mount.log
ExecStop=/bin/fusermount -uz ${mount_dir}
Restart=on-failure
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
EOF
    
    print_success "挂载服务创建成功: rclone-${remote_name}.service"
}

# 创建同步服务和定时器
create_sync_service() {
    if [[ $sync_enabled != true ]]; then
        return
    fi
    
    print_info "创建 systemd 同步服务..."
    
    # 创建同步服务
    cat > "/etc/systemd/system/rclone-sync-${remote_name}.service" <<EOF
[Unit]
Description=Rclone Sync Service for ${remote_name}
After=network-online.target rclone-${remote_name}.service
Wants=network-online.target

[Service]
Type=oneshot
Environment=RCLONE_CONFIG=${RCLONE_CONFIG}
ExecStart=/usr/bin/rclone sync ${remote_name}:${remote_path} ${sync_dir} \\
    --config=${RCLONE_CONFIG} \\
    --transfers 4 \\
    --checkers 8 \\
    --log-level INFO \\
    --log-file=${LOG_DIR}/${remote_name}-sync.log \\
    --stats 10s \\
    --stats-one-line
User=root
EOF
    
    print_success "同步服务创建成功: rclone-sync-${remote_name}.service"
    
    # 如果设置了定时同步，创建定时器
    if [[ -n $cron_expression ]]; then
        # 转换cron为systemd timer
        create_systemd_timer
    fi
    
    # 创建手动同步脚本
    cat > "/usr/local/bin/rclone-sync-${remote_name}.sh" <<EOF
#!/bin/bash
systemctl start rclone-sync-${remote_name}.service
systemctl status rclone-sync-${remote_name}.service
EOF
    
    chmod +x "/usr/local/bin/rclone-sync-${remote_name}.sh"
    print_success "手动同步脚本创建: /usr/local/bin/rclone-sync-${remote_name}.sh"
}

# 创建systemd定时器或crontab
create_systemd_timer() {
    if [[ -z $cron_expression ]]; then
        return
    fi
    
    print_info "设置定时同步..."
    
    # 添加到crontab
    cron_cmd="$cron_expression /usr/bin/systemctl start rclone-sync-${remote_name}.service >> ${LOG_DIR}/${remote_name}-cron.log 2>&1"
    
    # 检查是否已存在
    if crontab -l 2>/dev/null | grep -q "rclone-sync-${remote_name}"; then
        print_warning "定时任务已存在，跳过添加"
    else
        (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -
        print_success "定时同步已设置"
    fi
}

# 启动服务
start_services() {
    print_info "启动服务..."
    
    systemctl daemon-reload
    
    # 启动挂载服务
    systemctl enable "rclone-${remote_name}.service"
    systemctl start "rclone-${remote_name}.service"
    
    sleep 3
    
    if systemctl is-active --quiet "rclone-${remote_name}.service"; then
        print_success "挂载服务启动成功"
    else
        print_error "挂载服务启动失败，请查看日志: journalctl -u rclone-${remote_name}.service"
        exit 1
    fi
    
    # 如果启用了同步，启用同步服务
    if [[ $sync_enabled == true ]]; then
        systemctl enable "rclone-sync-${remote_name}.service"
        print_success "同步服务已启用"
        
        # 询问是否立即执行一次同步
        read -p "是否立即执行一次同步? (y/n): " do_sync_now
        if [[ $do_sync_now =~ ^[Yy]$ ]]; then
            print_info "开始同步..."
            systemctl start "rclone-sync-${remote_name}.service"
            sleep 2
            systemctl status "rclone-sync-${remote_name}.service" --no-pager
        fi
    fi
}

# 显示配置摘要
show_summary() {
    echo ""
    echo "=========================================="
    echo "          配置完成"
    echo "=========================================="
    echo ""
    echo "云盘名称: $cloud_name"
    echo "配置名称: $remote_name"
    echo "挂载目录: $mount_dir"
    echo "远程路径: $remote_path"
    echo "配置文件: $RCLONE_CONFIG"
    echo ""
    
    if [[ $sync_enabled == true ]]; then
        echo "同步目录: $sync_dir"
        if [[ -n $cron_expression ]]; then
            echo "定时同步: $cron_expression"
        fi
        echo ""
    fi
    
    echo "常用命令:"
    echo "  查看挂载状态: systemctl status rclone-${remote_name}"
    echo "  查看挂载日志: tail -f ${LOG_DIR}/${remote_name}-mount.log"
    echo "  重启挂载: systemctl restart rclone-${remote_name}"
    echo "  停止挂载: systemctl stop rclone-${remote_name}"
    echo ""
    
    if [[ $sync_enabled == true ]]; then
        echo "  手动同步: /usr/local/bin/rclone-sync-${remote_name}.sh"
        echo "  查看同步日志: tail -f ${LOG_DIR}/${remote_name}-sync.log"
        echo "  查看定时任务: crontab -l | grep rclone-sync-${remote_name}"
        echo ""
    fi
    
    echo "  查看挂载点: df -h | grep $mount_dir"
    echo "  列出文件: ls -lh $mount_dir"
    echo ""
    echo "=========================================="
}

# 主函数
main() {
    clear
    echo "=========================================="
    echo "    Rclone 云盘自动配置脚本"
    echo "=========================================="
    echo ""
    
    check_root
    install_dependencies
    install_rclone
    configure_cloud
    configure_mount
    configure_sync
    create_systemd_service
    create_sync_service
    start_services
    show_summary
    
    print_success "所有配置完成！"
}

# 运行主函数
main
