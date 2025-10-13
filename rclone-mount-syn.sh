#!/bin/bash

# --- Rclone 云盘管理一键脚本 ---
# 作者: AI Assistant
# 功能: 自动安装rclone, 交互式配置并挂载多个云盘, 设置开机自启动, 并提供同步选项。
# rclone 配置文件路径: /rclone.conf (按用户要求)

# 定义颜色
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 定义 rclone 配置文件路径
RCLONE_CONFIG_PATH="/rclone.conf"

# 确保脚本以root权限运行
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 sudo 运行此脚本。${NC}"
    exit 1
fi

# --- 1. 安装 rclone 和 fuse ---
echo -e "${GREEN}--- 1. 正在安装/更新 rclone 和 fuse ---${NC}"
if command -v apt &> /dev/null; then
    apt update && apt install -y rclone fuse unzip curl
elif command -v yum &> /dev/null; then
    yum install -y rclone fuse unzip curl
elif command -v dnf &> /dev/null; then
    dnf install -y rclone fuse unzip curl
else
    echo -e "${RED}不支持的包管理器。请手动安装 rclone 和 fuse。${NC}"
    exit 1
fi
echo -e "${GREEN}rclone 和 fuse 安装完成。${NC}"
echo ""

# 检查 rclone 是否安装成功
if ! command -v rclone &> /dev/null; then
    echo -e "${RED}rclone 安装失败，请检查安装过程。${NC}"
    exit 1
fi

# 确保配置文件存在或可创建
touch "$RCLONE_CONFIG_PATH" # 尝试创建或更新文件，确保权限
chmod 600 "$RCLONE_CONFIG_PATH" # 设置文件权限，只有所有者可读写

# --- 2. 选择云盘进行配置 ---
declare -A CLOUD_DRIVES
CLOUD_DRIVES=(
    [1]="Google Drive"
    [2]="OneDrive"
    [3]="Dropbox"
    [4]="Amazon S3 / S3 compatible"
    [5]="Google Cloud Storage (GCS)"
    [6]="Amazon Drive"
    [7]="Mega"
    [8]="pCloud"
    [9]="Box"
    [10]="SFTP / FTP / WebDAV (通用)"
    [11]="Baidu Netdisk (百度网盘)"
    [12]="Aliyun Drive (阿里云盘)"
    [13]="Quark Cloud Drive (夸克网盘)"
    [14]="China Telecom Cloud (天翼云盘)"
    [15]="China Mobile Cloud (和彩云/移动云盘)"
    [16]="Tencent COS (腾讯云对象存储)"
    [17]="Alibaba OSS (阿里云对象存储)"
)

echo -e "${GREEN}--- 2. 请选择需要配置的云盘 (可多选，输入序号，例如 1 2 11): ---${NC}"
for key in $(seq 1 ${#CLOUD_DRIVES[@]}); do
    echo -e "${YELLOW}  $key) ${CLOUD_DRIVES[$key]}${NC}"
done

read -p "您的选择 (例如: 1 11 12，不输入则退出): " selected_options
echo ""

# 如果用户未输入任何内容，则退出
if [ -z "$selected_options" ]; then
    echo -e "${RED}未选择任何云盘，脚本退出。${NC}"
    exit 0
fi

declare -A configured_remotes # 存储已配置的远程名称和挂载点

# 配置选定的云盘
for opt in $selected_options; do
    cloud_name="${CLOUD_DRIVES[$opt]}"
    if [[ -z "$cloud_name" ]]; then
        echo -e "${RED}无效的选择: $opt，跳过。${NC}"
        continue
    fi

    echo -e "${YELLOW}--- 正在配置 ${cloud_name} ---${NC}"
    
    # 提示用户输入远程名称 (默认为云盘名称的小写和下划线)
    default_remote_name=$(echo "$cloud_name" | tr '[:upper:] ' '[:lower:]_' | sed 's/[^a-z0-9_]//g')
    read -p "请输入此云盘的远程名称 (例如 baiduyun, 默认: $default_remote_name): " remote_name
    remote_name="${remote_name:-$default_remote_name}"

    echo -e "${YELLOW}即将开始 rclone config 交互式配置。请按照提示操作。${NC}"
    echo -e "${YELLOW}当提示 'name' 时输入 '${remote_name}'。${NC}"
    echo -e "${YELLOW}当提示 'Storage' 时，请根据列表选择数字。${NC}"
    echo -e "${YELLOW}提示 'yes/no' 时，直接按回车键通常表示 'yes'。${NC}"
    echo -e "${YELLOW}当要求在本地浏览器授权并粘贴 Token 时，请务必完成操作。${NC}"
    echo -e "${YELLOW}-----------------------------------------------------------${NC}"

    # 运行 rclone config，完全交由用户交互，不再传递 --remote-name
    # 用户在 rclone config 菜单中选择 n (New remote) 后，会提示输入 name
    sudo rclone config --config="$RCLONE_CONFIG_PATH"

    echo -e "${YELLOW}-----------------------------------------------------------${NC}"
    read -p "${YELLOW}请确保 ${remote_name} 已成功配置 (检查 '/rclone.conf' 文件)。按 Enter 继续...${NC}"

    read -p "请输入 ${remote_name} 的挂载目录 (例如: /mnt/${remote_name}, 默认: /mnt/${remote_name}): " mount_point
    mount_point="${mount_point:-/mnt/$remote_name}" # 默认挂载到 /mnt/远程名称

    configured_remotes["$remote_name"]="$mount_point"
    echo -e "${GREEN}${cloud_name} 配置完成。${NC}"
    echo ""
done

if [ ${#configured_remotes[@]} -eq 0 ]; then
    echo -e "${RED}没有配置任何云盘，脚本退出。${NC}"
    exit 0
fi

# --- 3. 挂载云盘并设置开机自启动 ---
echo -e "${GREEN}--- 3. 正在挂载云盘并设置开机自启动 ---${NC}"

for remote_name in "${!configured_remotes[@]}"; do
    mount_point="${configured_remotes[$remote_name]}"

    echo -e "${YELLOW}正在为 ${remote_name} (${mount_point}) 创建挂载点和 systemd 服务...${NC}"

    mkdir -p "$mount_point"
    if [ ! -d "$mount_point" ]; then
        echo -e "${RED}无法创建挂载点 ${mount_point}，请检查权限或路径。${NC}"
        continue
    fi
    
    # 创建 systemd 服务文件
    SERVICE_FILE="/etc/systemd/system/rclone-${remote_name}.service"
    cat << EOF > "$SERVICE_FILE"
[Unit]
Description=Rclone Mount for ${remote_name}
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/rclone mount ${remote_name}: "${mount_point}" --config=${RCLONE_CONFIG_PATH} --umask 000 --allow-other --vfs-cache-mode writes --dir-cache-time 24h --poll-interval 1m --log-file=/var/log/rclone-${remote_name}.log -v --daemon-timeout 10m
ExecStop=/bin/fusermount -uz "${mount_point}"
Restart=on-failure
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

    # 启用并启动服务
    systemctl daemon-reload
    systemctl enable rclone-"${remote_name}".service
    systemctl start rclone-"${remote_name}".service

    if systemctl is-active --quiet rclone-"${remote_name}".service; then
        echo -e "${GREEN}云盘 ${remote_name} 挂载成功并已设置开机自启动。${NC}"
        echo "您可以通过 'ls -l ${mount_point}' 查看内容。"
        echo "日志文件位于: /var/log/rclone-${remote_name}.log"
    else
        echo -e "${RED}云盘 ${remote_name} 挂载失败或服务启动失败。请检查日志。${NC}"
        echo "运行 'sudo systemctl status rclone-${remote_name}.service' 查看详情。"
    fi
    echo ""
done

# --- 4. 配置同步功能 (可选) ---
read -p "${YELLOW}是否需要配置同步功能？ (将挂载的目录同步到本地文件夹，以便离线使用) [Y/n]: ${NC}" sync_choice
sync_choice=$(echo "${sync_choice:-Y}" | tr '[:upper:]' '[:lower:]') # 默认 Y

if [[ "$sync_choice" == "y" ]]; then
    echo -e "${GREEN}--- 4. 配置同步功能 ---${NC}"
    for remote_name in "${!configured_remotes[@]}"; do
        mount_point="${configured_remotes[$remote_name]}"

        read -p "${YELLOW}是否同步远程 ${remote_name} (${mount_point}) 的内容到本地？ [Y/n]: ${NC}" individual_sync_choice
        individual_sync_choice=$(echo "${individual_sync_choice:-Y}" | tr '[:upper:]' '[:lower:]') # 默认 Y

        if [[ "$individual_sync_choice" == "y" ]]; then
            read -p "请输入本地同步目录的路径 (例如: /data/offline_${remote_name}, 默认: /data/offline_${remote_name}): " local_sync_dir
            local_sync_dir="${local_sync_dir:-/data/offline_${remote_name}}"
            
            mkdir -p "$local_sync_dir"
            if [ ! -d "$local_sync_dir" ]; then
                echo -e "${RED}无法创建本地同步目录 ${local_sync_dir}，请检查权限或路径。跳过同步配置。${NC}"
                continue
            fi

            echo -e "${YELLOW}正在为 ${remote_name} 设置同步到 ${local_sync_dir}...${NC}"

            # 创建同步脚本
            SYNC_SCRIPT="/usr/local/bin/rclone_sync_${remote_name}.sh"
            cat << EOF > "$SYNC_SCRIPT"
#!/bin/bash
# Rclone Sync Script for ${remote_name}
# Source: ${mount_point}/
# Destination: ${local_sync_dir}/

# 日志文件
LOG_FILE="/var/log/rclone_sync_${remote_name}.log"

# 使用 rclone copy 或 rclone sync
# copy: 只复制新文件和修改过的文件
# sync: 使目标目录与源目录完全一致 (会删除目标目录中源目录没有的文件)
# 推荐使用 copy，更安全
echo "[$(date)] Starting sync for ${remote_name}..." >> \$LOG_FILE
/usr/bin/rclone copy "${mount_point}/" "${local_sync_dir}/" --config=${RCLONE_CONFIG_PATH} --exclude ".DS_Store" --log-file=\$LOG_FILE --log-level INFO --fast-list --transfers 4 --checkers 8
if [ \$? -eq 0 ]; then
    echo "[$(date)] Sync for ${remote_name} completed successfully." >> \$LOG_FILE
else
    echo "[$(date)] Sync for ${remote_name} failed. Check \$LOG_FILE for details." >> \$LOG_FILE
fi
EOF
            chmod +x "$SYNC_SCRIPT"

            # 创建 Crontab 定时任务
            read -p "${YELLOW}请输入同步频率 (分钟，例如 60 表示每小时同步一次，输入 0 表示手动同步，默认 60): ${NC}" sync_interval
            sync_interval="${sync_interval:-60}" # 默认 60 分钟
            if [[ "$sync_interval" =~ ^[0-9]+$ ]] && [ "$sync_interval" -gt 0 ]; then
                (crontab -l 2>/dev/null; echo "*/$sync_interval * * * * $SYNC_SCRIPT") | crontab -
                echo -e "${GREEN}已设置 ${remote_name} 每 ${sync_interval} 分钟同步一次到 ${local_sync_dir}。${NC}"
            else
                echo -e "${YELLOW}未设置自动同步，您可以使用命令 'sudo ${SYNC_SCRIPT}' 手动执行同步。${NC}"
            fi
            echo "同步日志文件位于: /var/log/rclone_sync_${remote_name}.log"
            echo ""
        fi
    done
    echo -e "${GREEN}同步功能配置完成。${NC}"
else
    echo -e "${YELLOW}跳过同步功能配置。${NC}"
fi

echo -e "${GREEN}--- 所有配置完成！---${NC}"
echo "您现在可以使用 'df -h' 查看挂载的云盘，并使用 'ls -l /mnt/' 查看内容。"
echo "如果遇到问题，请检查相应的 rclone 服务日志 ('/var/log/rclone-*.log') 和同步日志 ('/var/log/rclone_sync_*.log')。"
echo "rclone 配置文件位于: ${RCLONE_CONFIG_PATH}"
