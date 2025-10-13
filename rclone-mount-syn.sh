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
    apt update && apt install -y rclone fuse unzip curl expect
elif command -v yum &> /dev/null; then
    yum install -y rclone fuse unzip curl expect
elif command -v dnf &> /dev/null; then
    dnf install -y rclone fuse unzip curl expect
else
    echo -e "${RED}不支持的包管理器。请手动安装 rclone、fuse 和 expect。${NC}"
    exit 1
fi
echo -e "${GREEN}rclone, fuse 和 expect 安装完成。${NC}"
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
    [1]="Google Drive (drive)"
    [2]="OneDrive (onedrive)"
    [3]="Dropbox (dropbox)"
    [4]="Amazon S3 / S3 compatible (s3)"
    [5]="Google Cloud Storage (GCS) (gcs)"
    [6]="Amazon Drive (amazon cloud drive)"
    [7]="Mega (mega)"
    [8]="pCloud (pcloud)"
    [9]="Box (box)"
    [10]="SFTP / FTP / WebDAV (通用) (sftp/ftp/webdav)"
    [11]="Baidu Netdisk (百度网盘) (baidu)"
    [12]="Aliyun Drive (阿里云盘) (aliyundrive)"
    [13]="Quark Cloud Drive (夸克网盘) (quark)"
    [14]="China Telecom Cloud (天翼云盘) (chunghwadrive)"
    [15]="China Mobile Cloud (和彩云/移动云盘) (cmcccloud)" # 这是一个推测值，可能需要根据实际rclone类型列表调整
    [16]="Tencent COS (腾讯云对象存储) (cos)"
    [17]="Alibaba OSS (阿里云对象存储) (oss)"
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
    cloud_info="${CLOUD_DRIVES[$opt]}"
    if [[ -z "$cloud_info" ]]; then
        echo -e "${RED}无效的选择: $opt，跳过。${NC}"
        continue
    fi
    
    # 从云盘信息中解析出显示名称和 rclone 类型提示 (括号内部分)
    cloud_name=$(echo "$cloud_info" | sed -E 's/\s*\((.*)\)//')
    rclone_type_hint=$(echo "$cloud_info" | sed -E 's/.*\(//;s/\)//')

    echo -e "${YELLOW}--- 正在配置 ${cloud_name} ---${NC}"
    
    # 提示用户输入远程名称 (默认为云盘名称的小写和下划线)
    default_remote_name=$(echo "$cloud_name" | tr '[:upper:] ' '[:lower:]_' | sed 's/[^a-z0-9_]//g')
    read -p "请输入此云盘的远程名称 (例如 baiduyun, 默认: $default_remote_name): " remote_name
    remote_name="${remote_name:-$default_remote_name}"

    echo -e "${YELLOW}即将开始 rclone config 交互式配置。请注意在本地浏览器中授权！${NC}"
    echo -e "${YELLOW}当提示输入 'Storage' 类型时，您可以输入 '$rclone_type_hint' 或根据列表选择数字。${NC}"
    echo -e "${YELLOW}大多数 'yes/no' 提示会尝试自动回车确认。${NC}"

    # 使用 expect 自动化 rclone config 内部的 yes/no 提示
    # 注意: expect 无法完全替代人工输入，尤其是在需要粘贴 token 或选择数字类型时。
    expect -c "
        set timeout -1
        spawn rclone config --config=$RCLONE_CONFIG_PATH
        # 如果是第一个远程，会提示创建新的，否则会显示菜单
        expect {
            \"No remotes found, make a new one?\" {
                send \"n\\r\"
                expect \"name\"
                send \"$remote_name\\r\"
            }
            \"e) Exit\" {
                send \"n\\r\"
                expect \"name\"
                send \"$remote_name\\r\"
            }
        }
        
        # 匹配 Storage 提示，这里用户需要手动输入类型或数字
        # 如果用户输入的类型提示是明确的，可以尝试自动输入，但存在风险
        # 更好的做法是提示用户手动输入
        expect \"Storage\" {
             # 这里可以尝试发送 rclone_type_hint，但如果类型不是精确匹配，会失败
             # 确保在云盘列表中的类型提示与 rclone config 内部的实际类型字符串匹配
             send \"$rclone_type_hint\\r\"
        }

        # 尝试自动化处理常见的默认选项，回车即是 YES
        # 这个循环会尝试匹配各种常见的 rclone config 提示并发送回车
        # 它会在遇到无法自动处理的（例如需要粘贴 token 或明确选择）时暂停
        while {1} {
            expect {
                -re \"(client_id|client_secret|scope|token_url|auth_url|provider|advanced config|auto config|Team Drive|server_side_encryption|region|endpoint|access_key_id|secret_access_key|Yes this is OK|root_folder_id|config:)\" {
                    send -- \"\\r\"
                }
                # 如果遇到需要用户粘贴token的提示，interact 会将控制权交给用户
                -re \"(rclone-token|code|Enter a value for.*:|Enter an existing remote.*:|Enter an Id for.*:)\" {
                    interact
                }
                # 匹配到 rclone config 的主菜单，表示一个远程配置完成
                \"e) Exit\" {
                    send \"q\\r\" # 退出 rclone config 菜单
                    break
                }
                # 如果超时或者遇到其他情况，也退出循环
                timeout {
                    puts \"Timeout reached, exiting expect script. Manual interaction may be needed.\"
                    break
                }
                eof {
                    puts \"EOF reached, exiting expect script.\"
                    break
                }
            }
        }
    "
    # 确认配置完成
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
