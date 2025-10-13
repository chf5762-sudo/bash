#!/bin/bash

# rclone 云盘管理脚本
# 功能：交互式配置、自动挂载、定时同步

set -e

#=============================================================================
# 默认远程名称配置表
#=============================================================================
# 云盘编号 | 云盘名称              | 默认远程名称    | rclone类型
#----------|-----------------------|----------------|------------
# 1        | Google Drive          | googledrive    | drive
# 2        | OneDrive              | onedrive       | onedrive
# 3        | Dropbox               | dropbox        | dropbox
# 4        | SFTP                  | sftp           | sftp
# 5        | FTP                   | ftp            | ftp
# 6        | WebDAV                | webdav         | webdav
# 7        | 百度网盘              | baiduyun       | baidu
# 8        | 阿里云盘              | aliyun         | aliyun
# 9        | 夸克网盘              | quark          | quark
# 10       | 天翼云盘              | tianyi         | 189
# 11       | 和彩云                | hecaiyun       | chinamobile
# 12       | 腾讯云COS             | tencentcos     | cos
# 13       | 阿里云OSS             | aliyunoss      | oss
#=============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置文件路径
RCLONE_CONFIG="/"
SCRIPT_DIR="/opt/rclone-manager"
CONFIG_FILE="$SCRIPT_DIR/config.json"

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 此脚本必须以 root 权限运行${NC}"
        exit 1
    fi
}

# 安装 rclone
install_rclone() {
    if command -v rclone &> /dev/null; then
        echo -e "${GREEN}rclone 已安装${NC}"
        return
    fi
    
    echo -e "${YELLOW}正在安装 rclone...${NC}"
    curl https://rclone.org/install.sh | bash
    echo -e "${GREEN}rclone 安装完成${NC}"
}

# 安装依赖
install_dependencies() {
    echo -e "${YELLOW}正在安装依赖...${NC}"
    if command -v apt-get &> /dev/null; then
        apt-get update
        apt-get install -y fuse jq curl
    elif command -v yum &> /dev/null; then
        yum install -y fuse jq curl
    else
        echo -e "${RED}不支持的系统，请手动安装 fuse 和 jq${NC}"
        exit 1
    fi
}

# 创建脚本目录
create_directories() {
    mkdir -p "$SCRIPT_DIR"
    mkdir -p /var/log/rclone
}

# 显示云盘列表
show_cloud_list() {
    echo -e "\n${BLUE}========== 支持的云盘列表 ==========${NC}"
    echo "国际云盘:"
    echo "  1. Google Drive (谷歌云端硬盘)"
    echo "  2. OneDrive (微软云盘)"
    echo "  3. Dropbox"
    echo "  4. SFTP"
    echo "  5. FTP"
    echo "  6. WebDAV"
    echo ""
    echo "中国云盘:"
    echo "  7. Baidu Netdisk (百度网盘)"
    echo "  8. Aliyun Drive (阿里云盘)"
    echo "  9. Quark Cloud Drive (夸克网盘)"
    echo " 10. China Telecom Cloud (天翼云盘)"
    echo " 11. China Mobile Cloud (和彩云)"
    echo " 12. Tencent COS (腾讯云对象存储)"
    echo " 13. Alibaba OSS (阿里云对象存储)"
    echo -e "${BLUE}====================================${NC}\n"
}

# 获取云盘类型
get_cloud_type() {
    case $1 in
        1) echo "drive" ;;
        2) echo "onedrive" ;;
        3) echo "dropbox" ;;
        4) echo "sftp" ;;
        5) echo "ftp" ;;
        6) echo "webdav" ;;
        7) echo "baidu" ;;
        8) echo "aliyun" ;;
        9) echo "quark" ;;
        10) echo "189" ;;
        11) echo "chinamobile" ;;
        12) echo "cos" ;;
        13) echo "oss" ;;
        *) echo "" ;;
    esac
}

# 获取默认远程名称
get_default_remote_name() {
    case $1 in
        1) echo "googledrive" ;;
        2) echo "onedrive" ;;
        3) echo "dropbox" ;;
        4) echo "sftp" ;;
        5) echo "ftp" ;;
        6) echo "webdav" ;;
        7) echo "baiduyun" ;;
        8) echo "aliyun" ;;
        9) echo "quark" ;;
        10) echo "tianyi" ;;
        11) echo "hecaiyun" ;;
        12) echo "tencentcos" ;;
        13) echo "aliyunoss" ;;
        *) echo "mycloud" ;;
    esac
}

# 配置 rclone
configure_rclone() {
    local remote_name=$1
    local cloud_type=$2
    
    echo -e "${YELLOW}正在配置 rclone...${NC}"
    echo -e "${BLUE}请按照提示完成 OAuth 认证或输入相关信息${NC}"
    
    RCLONE_CONFIG="$RCLONE_CONFIG" rclone config create "$remote_name" "$cloud_type" --non-interactive=false
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}rclone 配置成功${NC}"
    else
        echo -e "${RED}rclone 配置失败${NC}"
        exit 1
    fi
}

# 创建挂载服务
create_mount_service() {
    local remote_name=$1
    local mount_point=$2
    local service_name="rclone-mount-${remote_name}"
    
    cat > "/etc/systemd/system/${service_name}.service" <<EOF
[Unit]
Description=RClone Mount Service for ${remote_name}
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
User=root
Group=root
Environment=RCLONE_CONFIG=${RCLONE_CONFIG}
ExecStartPre=/bin/mkdir -p ${mount_point}
ExecStart=/usr/bin/rclone mount ${remote_name}: ${mount_point} \\
    --config=${RCLONE_CONFIG} \\
    --allow-other \\
    --vfs-cache-mode writes \\
    --vfs-cache-max-age 24h \\
    --vfs-read-chunk-size 128M \\
    --vfs-read-chunk-size-limit off \\
    --buffer-size 512M \\
    --transfers 4 \\
    --checkers 8 \\
    --low-level-retries 10 \\
    --log-file=/var/log/rclone/${remote_name}-mount.log \\
    --log-level INFO
ExecStop=/bin/fusermount -uz ${mount_point}
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "${service_name}.service"
    systemctl start "${service_name}.service"
    
    echo -e "${GREEN}挂载服务 ${service_name} 已创建并启动${NC}"
}

# 创建同步服务
create_sync_service() {
    local remote_name=$1
    local mount_point=$2
    local sync_dir=$3
    local sync_interval=$4
    local service_name="rclone-sync-${remote_name}"
    
    # 创建同步脚本
    cat > "$SCRIPT_DIR/sync-${remote_name}.sh" <<EOF
#!/bin/bash
RCLONE_CONFIG=${RCLONE_CONFIG}
/usr/bin/rclone sync ${remote_name}: ${sync_dir} \\
    --config=${RCLONE_CONFIG} \\
    --transfers 4 \\
    --checkers 8 \\
    --log-file=/var/log/rclone/${remote_name}-sync.log \\
    --log-level INFO
EOF
    
    chmod +x "$SCRIPT_DIR/sync-${remote_name}.sh"
    
    # 创建 systemd service
    cat > "/etc/systemd/system/${service_name}.service" <<EOF
[Unit]
Description=RClone Sync Service for ${remote_name}
After=network-online.target

[Service]
Type=oneshot
User=root
Group=root
ExecStart=$SCRIPT_DIR/sync-${remote_name}.sh
EOF

    # 创建 systemd timer
    cat > "/etc/systemd/system/${service_name}.timer" <<EOF
[Unit]
Description=RClone Sync Timer for ${remote_name}

[Timer]
OnBootSec=5min
OnUnitActiveSec=${sync_interval}
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable "${service_name}.timer"
    systemctl start "${service_name}.timer"
    
    echo -e "${GREEN}同步服务 ${service_name} 已创建并启动 (间隔: ${sync_interval})${NC}"
}

# 保存配置
save_config() {
    local remote_name=$1
    local cloud_type=$2
    local mount_point=$3
    local sync_enabled=$4
    local sync_dir=$5
    local sync_interval=$6
    
    cat > "$CONFIG_FILE" <<EOF
{
    "remote_name": "$remote_name",
    "cloud_type": "$cloud_type",
    "mount_point": "$mount_point",
    "sync_enabled": $sync_enabled,
    "sync_dir": "$sync_dir",
    "sync_interval": "$sync_interval"
}
EOF
}

# 主菜单
main_menu() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     RClone 云盘管理脚本 v1.0          ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    
    show_cloud_list
    
    read -p "请选择云盘类型 (1-13): " cloud_choice
    
    cloud_type=$(get_cloud_type "$cloud_choice")
    if [ -z "$cloud_type" ]; then
        echo -e "${RED}无效选择${NC}"
        exit 1
    fi
    
    # 获取默认远程名称
    default_remote_name=$(get_default_remote_name "$cloud_choice")
    
    read -p "请输入远程名称 [默认: $default_remote_name]: " remote_name
    remote_name=${remote_name:-$default_remote_name}
    
    if [ -z "$remote_name" ]; then
        echo -e "${RED}远程名称不能为空${NC}"
        exit 1
    fi
    
    read -p "请输入挂载目录 (例如: /mnt/cloudrive): " mount_point
    if [ -z "$mount_point" ]; then
        echo -e "${RED}挂载目录不能为空${NC}"
        exit 1
    fi
    
    read -p "是否启用同步功能? (y/n): " enable_sync
    
    sync_enabled=false
    sync_dir=""
    sync_interval=""
    
    if [[ "$enable_sync" == "y" || "$enable_sync" == "Y" ]]; then
        sync_enabled=true
        read -p "请输入本地同步目录 (例如: /data/sync): " sync_dir
        if [ -z "$sync_dir" ]; then
            echo -e "${RED}同步目录不能为空${NC}"
            exit 1
        fi
        
        echo -e "\n同步间隔选项:"
        echo "  1. 每小时"
        echo "  2. 每6小时"
        echo "  3. 每12小时"
        echo "  4. 每天"
        read -p "请选择同步间隔 (1-4): " interval_choice
        
        case $interval_choice in
            1) sync_interval="1h" ;;
            2) sync_interval="6h" ;;
            3) sync_interval="12h" ;;
            4) sync_interval="24h" ;;
            *) sync_interval="6h" ;;
        esac
        
        mkdir -p "$sync_dir"
    fi
    
    # 安装依赖
    install_rclone
    install_dependencies
    create_directories
    
    # 配置 rclone
    configure_rclone "$remote_name" "$cloud_type"
    
    # 创建挂载服务
    create_mount_service "$remote_name" "$mount_point"
    
    # 创建同步服务
    if [ "$sync_enabled" = true ]; then
        create_sync_service "$remote_name" "$mount_point" "$sync_dir" "$sync_interval"
    fi
    
    # 保存配置
    save_config "$remote_name" "$cloud_type" "$mount_point" "$sync_enabled" "$sync_dir" "$sync_interval"
    
    echo -e "\n${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         配置完成！                     ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo -e "\n${BLUE}配置信息:${NC}"
    echo -e "  远程名称: ${YELLOW}$remote_name${NC}"
    echo -e "  云盘类型: ${YELLOW}$cloud_type${NC}"
    echo -e "  挂载目录: ${YELLOW}$mount_point${NC}"
    if [ "$sync_enabled" = true ]; then
        echo -e "  同步目录: ${YELLOW}$sync_dir${NC}"
        echo -e "  同步间隔: ${YELLOW}$sync_interval${NC}"
    fi
    
    echo -e "\n${BLUE}常用命令:${NC}"
    echo -e "  查看挂载状态: ${YELLOW}systemctl status rclone-mount-${remote_name}${NC}"
    if [ "$sync_enabled" = true ]; then
        echo -e "  查看同步状态: ${YELLOW}systemctl status rclone-sync-${remote_name}.timer${NC}"
        echo -e "  手动执行同步: ${YELLOW}systemctl start rclone-sync-${remote_name}${NC}"
    fi
    echo -e "  查看挂载日志: ${YELLOW}tail -f /var/log/rclone/${remote_name}-mount.log${NC}"
    if [ "$sync_enabled" = true ]; then
        echo -e "  查看同步日志: ${YELLOW}tail -f /var/log/rclone/${remote_name}-sync.log${NC}"
    fi
}

# 主程序
check_root
main_menu
