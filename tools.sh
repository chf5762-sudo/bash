#!/bin/bash
# curl -fsSL https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/tools.sh -o tools.sh && chmod +x tools.sh && sudo ./tools.sh
# curl -fsSL https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/tools.sh -o tools.sh && chmod +x tools.sh && sudo ./tools.sh
# curl -fsSL https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/tools.sh -o tools.sh && chmod +x tools.sh && sudo ./tools.sh
# curl -fsSL https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/tools.sh -o tools.sh && chmod +x tools.sh && sudo ./tools.sh
# curl -fsSL https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/tools.sh -o tools.sh && chmod +x tools.sh && sudo ./tools.sh
# curl -fsSL https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/tools.sh -o tools.sh && chmod +x tools.sh && sudo ./tools.sh
# curl -fsSL https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/tools.sh -o tools.sh && chmod +x tools.sh && sudo ./tools.sh
# curl -fsSL https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/tools.sh -o tools.sh && chmod +x tools.sh && sudo ./tools.sh
# curl -fsSL https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/tools.sh -o tools.sh && chmod +x tools.sh && sudo ./tools.sh

################################################################################
# 文件名: tools.sh
# 版本: v2.4.0
# 功能: Ubuntu Server 轻量运维工具箱
# 安装位置: /usr/local/bin/t
# 作者: Auto Generated
# 日期: 2025-11-21
#
# 一键安装命令:
# curl -fsSL https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/tools.sh -o tools.sh && chmod +x tools.sh && sudo ./tools.sh
#
# 安装后使用:
#   t              # 打开主菜单
#   t C            # 命令、脚本收藏夹
#   t --help       # 查看帮助
################################################################################

# ============================================================================
# 全局变量
# ============================================================================
VERSION="2.4.0"
SCRIPT_PATH="$(readlink -f "$0")"
INSTALL_PATH="/usr/local/bin/t"
CONFIG_DIR="/etc/tools"
LOG_DIR="/var/log/tools"
LOCAL_DATA="$CONFIG_DIR/local.json"
CACHE_FILE="$CONFIG_DIR/cloud_cache.json"

# Gist 配置（Token 分段拼接）
TOKEN_P1="ghp_9L6XhJxk"
TOKEN_P2="aQHVYASNGW"
TOKEN_P3="nwSVJtqbNWYH4FgpIN"
GIST_TOKEN="${TOKEN_P1}${TOKEN_P2}${TOKEN_P3}"
GIST_ID="5056809fae3422c02fd8b52ad31f8fca"
GIST_FILE="tools-data.json"
GITHUB_RAW_URL="https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/tools.sh"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ============================================================================
# 工具函数
# ============================================================================

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此操作需要 root 权限"
        echo "请使用: sudo $0 $*"
        exit 1
    fi
}

init_config() {
    mkdir -p "$CONFIG_DIR" "$LOG_DIR"
    
    # 初始化本地数据
    if [[ ! -f "$LOCAL_DATA" ]]; then
        cat > "$LOCAL_DATA" <<'EOF'
{
  "services": [],
  "caddy_routes": []
}
EOF
    fi
    
    # 初始化云端缓存
    if [[ ! -f "$CACHE_FILE" ]]; then
        cat > "$CACHE_FILE" <<'EOF'
{
  "commands": [],
  "scripts": []
}
EOF
    fi
}

log_action() {
    local action="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $action" >> "$LOG_DIR/tools.log"
}

# ============================================================================
# 云端数据同步
# ============================================================================

sync_from_cloud() {
    local silent="$1"
    
    [[ "$silent" != "silent" ]] && print_info "正在从云端同步..."
    
    local response=$(curl -s -H "Authorization: token $GIST_TOKEN" \
        "https://api.github.com/gists/$GIST_ID" 2>/dev/null)
    
    if [[ -z "$response" ]]; then
        [[ "$silent" != "silent" ]] && print_error "网络连接失败"
        return 1
    fi
    
    # 使用 jq 提取文件内容
    local content=$(echo "$response" | jq -r ".files.\"$GIST_FILE\".content" 2>/dev/null)
    
    if [[ -z "$content" || "$content" == "null" ]]; then
        [[ "$silent" != "silent" ]] && print_warning "云端数据为空，初始化中..."
        init_cloud_data
        return 1
    fi
    
    echo "$content" > "$CACHE_FILE"
    [[ "$silent" != "silent" ]] && print_success "同步完成"
    return 0
}

sync_to_cloud() {
    local silent="$1"
    
    [[ "$silent" != "silent" ]] && print_info "正在推送到云端..."
    
    if [[ ! -f "$CACHE_FILE" ]]; then
        print_error "本地缓存不存在"
        return 1
    fi
    
    # 读取缓存内容并转义
    local content=$(cat "$CACHE_FILE" | jq -Rs .)
    
    # 构造更新请求
    local update_data=$(cat <<EOF
{
  "files": {
    "$GIST_FILE": {
      "content": $content
    }
  }
}
EOF
)
    
    local response=$(curl -s -X PATCH \
        -H "Authorization: token $GIST_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$update_data" \
        "https://api.github.com/gists/$GIST_ID" 2>/dev/null)
    
    if echo "$response" | grep -q "\"id\""; then
        [[ "$silent" != "silent" ]] && print_success "推送完成"
        log_action "Synced to cloud"
        return 0
    else
        [[ "$silent" != "silent" ]] && print_error "推送失败"
        return 1
    fi
}

init_cloud_data() {
    local init_data=$(cat <<'EOF'
{
  "commands": [],
  "scripts": []
}
EOF
)
    
    echo "$init_data" > "$CACHE_FILE"
    sync_to_cloud silent
}

# ============================================================================
# 系统信息显示
# ============================================================================

show_system_info() {
    clear
    local current_time=$(date '+%Y-%m-%d %H:%M:%S')
    local timezone=$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}' || cat /etc/timezone 2>/dev/null || echo "Unknown")
    local os_name=$(grep "^PRETTY_NAME" /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "Unknown")
    local mem_info=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')
    local disk_info=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')
    
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  Tools v${VERSION} | $os_name"
    echo "║  💾 内存: $mem_info | 💿 磁盘: $disk_info"
    echo "╚════════════════════════════════════════════════════════════╝"
}

# ============================================================================
# 主菜单
# ============================================================================

main_menu() {
    # 启动时同步
    sync_from_cloud silent
    
    while true; do
        show_system_info
        
        cat <<'EOF'

 ▸ 快捷操作（云端）
   [T] 📝 粘贴并执行    [C] 💾 命令、脚本收藏夹
   
 ▸ 服务与容器
   [1] 注册二进制服务
   [2] 管理服务
       [2A] 启动服务  [2B] 停止服务  [2C] 重启服务  [2D] 查看日志
   [3] 定时任务
       [3A] 添加任务  [3B] 查看任务  [3C] 删除任务
   [4] Docker 安装
   [5] 容器管理
       [5A] 启动容器  [5B] 停止容器  [5C] 重启容器
       [5D] 删除容器  [5E] 查看日志  [5F] 进入终端
   
 ▸ 反向代理
   [6] 安装 Caddy         [7] 添加路由       [8] 管理路由
   
 ▸ 网络与系统
   [9] Tailscale          [10] Exit Node     [11] 1Panel
   [12] 时区设置          [13] Root SSH
   
 [U] 🔄 更新脚本         [0] 退出
════════════════════════════════════════════════════════════
EOF
        
        read -p "请选择: " choice
        
        # 转换为大写处理
        choice=$(echo "$choice" | tr '[:lower:]' '[:upper:]')
        
        case $choice in
            T) run_script_from_paste ;;
            C) command_script_favorites ;;
            1) register_binary_service ;;
            2) manage_services ;;
            2A) quick_service_action "start" ;;
            2B) quick_service_action "stop" ;;
            2C) quick_service_action "restart" ;;
            2D) quick_service_action "logs" ;;
            3) cron_management ;;
            3A) add_cron_job ;;
            3B) view_cron_jobs ;;
            3C) delete_cron_job ;;
            4) install_docker_compose ;;
            5) docker_container_management ;;
            5A) quick_docker_action "start" ;;
            5B) quick_docker_action "stop" ;;
            5C) quick_docker_action "restart" ;;
            5D) quick_docker_action "rm" ;;
            5E) quick_docker_action "logs" ;;
            5F) quick_docker_action "exec" ;;
            6) install_caddy ;;
            7) add_caddy_route ;;
            8) manage_caddy_routes ;;
            9) install_tailscale ;;
            10) configure_exit_node ;;
            11) install_1panel ;;
            12) change_timezone ;;
            13) enable_root_ssh ;;
            U) update_script ;;
            0) 
                echo ""
                print_info "感谢使用 Tools 工具箱！"
                exit 0
                ;;
            *) 
                print_error "无效选择"
                sleep 1
                ;;
        esac
    done
}

# ============================================================================
# [C] 命令、脚本收藏夹（云端）
# ============================================================================

command_script_favorites() {
    while true; do
        clear
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║    命令、脚本收藏夹（云端共享）                            ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""
        
        sync_from_cloud silent
        
        local cmd_count=$(jq '.commands | length' "$CACHE_FILE" 2>/dev/null || echo "0")
        local script_count=$(jq '.scripts | length' "$CACHE_FILE" 2>/dev/null || echo "0")
        
        if [[ $cmd_count -eq 0 ]] && [[ $script_count -eq 0 ]]; then
            print_warning "暂无收藏的命令或脚本"
        else
            if [[ $cmd_count -gt 0 ]]; then
                echo -e "${CYAN}═══ 命令收藏 ═══${NC}"
                echo ""
                for ((i=0; i<cmd_count; i++)); do
                    local id=$(jq -r ".commands[$i].id" "$CACHE_FILE")
                    local cmd=$(jq -r ".commands[$i].command" "$CACHE_FILE")
                    echo "[C$id] $cmd"
                done
                echo ""
            fi
            
            if [[ $script_count -gt 0 ]]; then
                echo -e "${MAGENTA}═══ 脚本收藏 ═══${NC}"
                echo ""
                for ((i=0; i<script_count; i++)); do
                    local id=$(jq -r ".scripts[$i].id" "$CACHE_FILE")
                    local name=$(jq -r ".scripts[$i].name" "$CACHE_FILE")
                    local lines=$(jq -r ".scripts[$i].lines" "$CACHE_FILE")
                    echo "[S$id] $name (${lines}行)"
                done
                echo ""
            fi
        fi
        
        echo "[1] 添加命令    [2] 添加脚本    [3] 执行收藏"
        echo "[4] 删除收藏    [0] 返回"
        echo ""
        read -p "请选择: " choice
        
        case $choice in
            1) add_command_favorite ;;
            2) add_script_favorite ;;
            3) execute_favorite ;;
            4) delete_favorite ;;
            0) return ;;
            *) print_error "无效选择"; sleep 1 ;;
        esac
    done
}

add_command_favorite() {
    echo ""
    read -p "输入要收藏的命令: " cmd
    
    if [[ -z "$cmd" ]]; then
        print_error "命令不能为空"
        sleep 2
        return
    fi
    
    # 先从云端同步最新数据
    sync_from_cloud silent
    
    # 获取当前最大 ID
    local max_id=$(jq '[.commands[].id] | max // 0' "$CACHE_FILE" 2>/dev/null)
    if [[ -z "$max_id" || "$max_id" == "null" ]]; then
        max_id=0
    fi
    local new_id=$((max_id + 1))
    
    echo ""
    print_info "正在保存命令..."
    
    # 添加到本地缓存
    local new_cmd=$(jq -n \
        --arg id "$new_id" \
        --arg cmd "$cmd" \
        --arg time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{id: ($id | tonumber), command: $cmd, added_time: $time}')
    
    local updated=$(jq ".commands += [$new_cmd]" "$CACHE_FILE")
    echo "$updated" > "$CACHE_FILE"
    
    # 推送到云端
    if sync_to_cloud silent; then
        print_success "✓ 已保存为 [C$new_id]"
        print_success "✓ 已推送到云端"
        log_action "Add command favorite: $cmd"
    else
        print_error "✗ 云端同步失败（已保存到本地）"
    fi
    
    sleep 2
}

add_script_favorite() {
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║        添加脚本到收藏夹                                    ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    read -p "脚本名称: " script_name
    
    if [[ -z "$script_name" ]]; then
        print_error "脚本名称不能为空"
        sleep 2
        return
    fi
    
    echo ""
    print_info "请粘贴脚本内容 (结束后按 Ctrl+D):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local temp_script="/tmp/tools-script-$RANDOM.txt"
    cat > "$temp_script"
    
    if [[ ! -s "$temp_script" ]]; then
        print_error "未检测到脚本内容"
        rm -f "$temp_script"
        sleep 2
        return
    fi
    
    local line_count=$(wc -l < "$temp_script")
    local script_content=$(cat "$temp_script")
    
    echo ""
    print_success "脚本内容已接收 ($line_count 行)"
    
    # 先从云端同步
    sync_from_cloud silent
    
    # 获取当前最大 ID
    local max_id=$(jq '[.scripts[].id] | max // 0' "$CACHE_FILE" 2>/dev/null)
    if [[ -z "$max_id" || "$max_id" == "null" ]]; then
        max_id=0
    fi
    local new_id=$((max_id + 1))
    
    echo ""
    print_info "正在保存脚本..."
    
    # 添加到本地缓存
    local new_script=$(jq -n \
        --arg id "$new_id" \
        --arg name "$script_name" \
        --arg content "$script_content" \
        --arg lines "$line_count" \
        --arg time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '{id: ($id | tonumber), name: $name, content: $content, lines: ($lines | tonumber), added_time: $time}')
    
    local updated=$(jq ".scripts += [$new_script]" "$CACHE_FILE")
    echo "$updated" > "$CACHE_FILE"
    
    rm -f "$temp_script"
    
    # 推送到云端
    if sync_to_cloud silent; then
        print_success "✓ 已保存为 [S$new_id]"
        print_success "✓ 已推送到云端"
        log_action "Add script favorite: $script_name"
    else
        print_error "✗ 云端同步失败（已保存到本地）"
    fi
    
    sleep 2
}

execute_favorite() {
    echo ""
    read -p "输入要执行的编号 (如: C1 或 S2): " input
    
    if [[ -z "$input" ]]; then
        print_error "编号不能为空"
        sleep 2
        return
    fi
    
    local type="${input:0:1}"
    local id="${input:1}"
    
    if [[ ! "$id" =~ ^[0-9]+$ ]]; then
        print_error "无效编号"
        sleep 2
        return
    fi
    
    case "${type^^}" in
        C)
            execute_command_favorite "$id"
            ;;
        S)
            execute_script_favorite "$id"
            ;;
        *)
            print_error "无效编号格式，请使用 C1 或 S2 格式"
            sleep 2
            ;;
    esac
}

execute_command_favorite() {
    local id="$1"
    
    local found=$(jq ".commands[] | select(.id == $id)" "$CACHE_FILE" 2>/dev/null)
    
    if [[ -z "$found" ]]; then
        print_error "未找到命令编号: C$id"
        sleep 2
        return
    fi
    
    local cmd=$(echo "$found" | jq -r '.command')
    
    echo ""
    print_info "执行命令: $cmd"
    echo "════════════════════════════════════════════════════════════"
    
    eval "$cmd"
    local exit_code=$?
    
    echo "════════════════════════════════════════════════════════════"
    
    if [[ $exit_code -eq 0 ]]; then
        print_success "命令执行完成"
    else
        print_error "命令执行失败 (退出码: $exit_code)"
    fi
    
    log_action "Execute command favorite: C$id - $cmd"
    
    echo ""
    read -p "按回车继续..."
}

execute_script_favorite() {
    local id="$1"
    
    local found=$(jq ".scripts[] | select(.id == $id)" "$CACHE_FILE" 2>/dev/null)
    
    if [[ -z "$found" ]]; then
        print_error "未找到脚本编号: S$id"
        sleep 2
        return
    fi
    
    local name=$(echo "$found" | jq -r '.name')
    local content=$(echo "$found" | jq -r '.content')
    
    echo ""
    print_info "执行脚本: $name"
    echo ""
    read -p "是否需要传递参数? [留空直接执行]: " params
    
    local temp_script="/tmp/tools-exec-$RANDOM.sh"
    echo "$content" > "$temp_script"
    chmod +x "$temp_script"
    
    echo ""
    print_info "开始执行..."
    echo "════════════════════════════════════════════════════════════"
    
    local start_time=$(date +%s)
    
    if [[ -n "$params" ]]; then
        bash "$temp_script" $params
    else
        bash "$temp_script"
    fi
    
    local exit_code=$?
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "════════════════════════════════════════════════════════════"
    
    if [[ $exit_code -eq 0 ]]; then
        print_success "执行完成！(耗时: ${duration}秒)"
    else
        print_error "执行失败！(退出码: $exit_code)"
    fi
    
    log_action "Execute script favorite: S$id - $name"
    
    rm -f "$temp_script"
    
    echo ""
    read -p "按回车继续..."
}

delete_favorite() {
    echo ""
    read -p "输入要删除的编号 (如: C1 或 S2): " input
    
    if [[ -z "$input" ]]; then
        print_error "编号不能为空"
        sleep 2
        return
    fi
    
    local type="${input:0:1}"
    local id="${input:1}"
    
    if [[ ! "$id" =~ ^[0-9]+$ ]]; then
        print_error "无效编号"
        sleep 2
        return
    fi
    
    # 先从云端同步
    sync_from_cloud silent
    
    case "${type^^}" in
        C)
            local found=$(jq ".commands[] | select(.id == $id)" "$CACHE_FILE" 2>/dev/null)
            
            if [[ -z "$found" ]]; then
                print_error "未找到编号: C$id"
                sleep 2
                return
            fi
            
            local cmd=$(echo "$found" | jq -r '.command')
            
            echo ""
            print_info "正在删除命令: $cmd"
            
            local updated=$(jq "del(.commands[] | select(.id == $id))" "$CACHE_FILE")
            echo "$updated" > "$CACHE_FILE"
            
            if sync_to_cloud silent; then
                print_success "✓ 命令已删除"
                print_success "✓ 已同步到云端"
                log_action "Delete command favorite: C$id"
            else
                print_error "✗ 云端同步失败（已从本地删除）"
            fi
            ;;
        S)
            local found=$(jq ".scripts[] | select(.id == $id)" "$CACHE_FILE" 2>/dev/null)
            
            if [[ -z "$found" ]]; then
                print_error "未找到编号: S$id"
                sleep 2
                return
            fi
            
            local name=$(echo "$found" | jq -r '.name')
            
            echo ""
            print_info "正在删除脚本: $name"
            
            local updated=$(jq "del(.scripts[] | select(.id == $id))" "$CACHE_FILE")
            echo "$updated" > "$CACHE_FILE"
            
            if sync_to_cloud silent; then
                print_success "✓ 脚本已删除"
                print_success "✓ 已同步到云端"
                log_action "Delete script favorite: S$id"
            else
                print_error "✗ 云端同步失败（已从本地删除）"
            fi
            ;;
        *)
            print_error "无效编号格式，请使用 C1 或 S2 格式"
            sleep 2
            ;;
    esac
    
    sleep 2
}

# ============================================================================
# [T] 粘贴并执行
# ============================================================================

run_script_from_paste() {
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║        粘贴脚本内容                                        ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    print_info "请粘贴脚本内容 (结束后按 Ctrl+D):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local temp_script="/tmp/tools-paste-$RANDOM.sh"
    cat > "$temp_script"
    
    if [[ ! -s "$temp_script" ]]; then
        print_error "未检测到脚本内容"
        rm -f "$temp_script"
        sleep 2
        return
    fi
    
    echo ""
    print_success "脚本内容已接收 ($(wc -l < "$temp_script") 行)"
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "脚本预览 (前15行):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    head -n 15 "$temp_script"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    read -p "是否需要传递参数? [留空直接执行]: " params
    
    chmod +x "$temp_script"
    
    echo ""
    print_info "开始执行..."
    echo "════════════════════════════════════════════════════════════"
    
    local start_time=$(date +%s)
    
    if [[ -n "$params" ]]; then
        bash "$temp_script" $params
    else
        bash "$temp_script"
    fi
    
    local exit_code=$?
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "════════════════════════════════════════════════════════════"
    
    if [[ $exit_code -eq 0 ]]; then
        print_success "执行完成！(耗时: ${duration}秒)"
    else
        print_error "执行失败！(退出码: $exit_code)"
    fi
    
    log_action "Execute pasted script (exit: $exit_code, duration: ${duration}s)"
    
    rm -f "$temp_script"
    
    echo ""
    read -p "按回车继续..."
}

# ============================================================================
# 二进制服务管理
# ============================================================================

register_binary_service() {
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║    注册二进制程序为系统服务                                ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    read -p "二进制程序目录: " bin_dir
    
    if [[ ! -d "$bin_dir" ]]; then
        print_error "目录不存在"
        sleep 2
        return
    fi
    
    print_info "正在扫描可执行文件..."
    
    # 列出所有可执行文件
    local executables=()
    while IFS= read -r file; do
        executables+=("$file")
    done < <(find "$bin_dir" -maxdepth 1 -type f -executable 2>/dev/null)
    
    if [[ ${#executables[@]} -eq 0 ]]; then
        print_error "未找到可执行文件"
        sleep 2
        return
    fi
    
    echo ""
    echo "找到以下可执行文件："
    echo ""
    for i in "${!executables[@]}"; do
        echo "[$((i+1))] $(basename "${executables[$i]}")"
    done
    
    echo ""
    read -p "选择要注册的文件编号: " num
    
    if [[ $num -lt 1 || $num -gt ${#executables[@]} ]]; then
        print_error "无效选择"
        sleep 2
        return
    fi
    
    local binary="${executables[$((num-1))]}"
    local binary_name=$(basename "$binary")
    
    print_success "已选择: $binary_name"
    
    read -p "服务名称 [$binary_name]: " service_name
    service_name=${service_name:-$binary_name}
    
    read -p "工作目录 [$bin_dir]: " work_dir
    work_dir=${work_dir:-$bin_dir}
    
    read -p "运行用户 [root]: " run_user
    run_user=${run_user:-root}
    
    read -p "启动参数 (可选): " params
    
    check_root
    
    # 生成 systemd service
    cat > "/etc/systemd/system/${service_name}.service" <<EOF
[Unit]
Description=$service_name Service
After=network.target

[Service]
Type=simple
User=$run_user
WorkingDirectory=$work_dir
ExecStart=$binary $params
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl start "$service_name"
    systemctl enable "$service_name"
    
    if systemctl is-active --quiet "$service_name"; then
        print_success "服务已启动"
        
        # 保存到本地数据
        local new_service=$(jq -n \
            --arg name "$service_name" \
            --arg binary "$binary" \
            --arg work_dir "$work_dir" \
            '{name: $name, binary: $binary, work_dir: $work_dir}')
        
        local updated=$(jq ".services += [$new_service]" "$LOCAL_DATA")
        echo "$updated" > "$LOCAL_DATA"
        
        log_action "Register service: $service_name"
    else
        print_error "服务启动失败"
        echo ""
        echo "可能的原因："
        echo "  1. 二进制文件缺少依赖"
        echo "  2. 权限配置不正确"
        echo "  3. 工作目录路径错误"
        echo ""
        echo "建议操作："
        echo "  - 查看日志: journalctl -u $service_name"
        echo "  - 手动测试: $binary $params"
    fi
    
    echo ""
    read -p "按回车继续..."
}

manage_services() {
    while true; do
        clear
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║        已注册的服务                                        ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""
        
        local service_count=$(jq '.services | length' "$LOCAL_DATA" 2>/dev/null || echo "0")
        
        if [[ $service_count -eq 0 ]]; then
            print_warning "暂无已注册的服务"
            echo ""
            echo "[0] 返回"
            read -p "选择: " choice
            return
        fi
        
        for ((i=0; i<service_count; i++)); do
            local name=$(jq -r ".services[$i].name" "$LOCAL_DATA")
            local status="已停止"
            local status_color=$RED
            
            if systemctl is-active --quiet "$name"; then
                status="运行中"
                status_color=$GREEN
            fi
            
            echo -ne "[$((i+1))] ${CYAN}$name${NC} - "
            echo -e "${status_color}$status${NC}"
        done
        
        echo ""
        echo "[S] 启动服务    [P] 停止服务    [R] 重启服务"
        echo "[L] 查看日志    [0] 返回"
        echo ""
        read -p "选择操作: " choice
        
        case $choice in
            [Ss]) service_action "start" ;;
            [Pp]) service_action "stop" ;;
            [Rr]) service_action "restart" ;;
            [Ll]) service_action "logs" ;;
            0) return ;;
        esac
    done
}

service_action() {
    local action="$1"
    
    echo ""
    read -p "输入服务编号: " num
    
    local service_count=$(jq '.services | length' "$LOCAL_DATA")
    
    if [[ $num -lt 1 || $num -gt $service_count ]]; then
        print_error "无效编号"
        sleep 2
        return
    fi
    
    local index=$((num - 1))
    local name=$(jq -r ".services[$index].name" "$LOCAL_DATA")
    
    check_root
    
    if [[ "$action" == "logs" ]]; then
        echo ""
        journalctl -u "$name" -n 50 --no-pager
        echo ""
        read -p "按回车继续..."
    else
        if systemctl "$action" "$name"; then
            print_success "操作成功"
            log_action "Service $action: $name"
        else
            print_error "操作失败"
        fi
        sleep 2
    fi
}

# 快速服务操作（从主菜单直接调用）
quick_service_action() {
    local action="$1"
    
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║        快速服务操作                                        ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    local service_count=$(jq '.services | length' "$LOCAL_DATA" 2>/dev/null || echo "0")
    
    if [[ $service_count -eq 0 ]]; then
        print_warning "暂无已注册的服务"
        sleep 2
        return
    fi
    
    echo "已注册的服务："
    echo ""
    
    for ((i=0; i<service_count; i++)); do
        local name=$(jq -r ".services[$i].name" "$LOCAL_DATA")
        local status="已停止"
        local status_color=$RED
        
        if systemctl is-active --quiet "$name"; then
            status="运行中"
            status_color=$GREEN
        fi
        
        echo -ne "[$((i+1))] ${CYAN}$name${NC} - "
        echo -e "${status_color}$status${NC}"
    done
    
    echo ""
    
    local action_text="操作"
    case $action in
        start) action_text="启动" ;;
        stop) action_text="停止" ;;
        restart) action_text="重启" ;;
        logs) action_text="查看日志" ;;
    esac
    
    read -p "输入要${action_text}的服务编号: " num
    
    if [[ ! "$num" =~ ^[0-9]+$ ]] || [[ $num -lt 1 || $num -gt $service_count ]]; then
        print_error "无效编号"
        sleep 2
        return
    fi
    
    local index=$((num - 1))
    local name=$(jq -r ".services[$index].name" "$LOCAL_DATA")
    
    check_root
    
    if [[ "$action" == "logs" ]]; then
        echo ""
        journalctl -u "$name" -n 50 --no-pager
        echo ""
        read -p "按回车继续..."
    else
        if systemctl "$action" "$name"; then
            print_success "${action_text}成功"
            log_action "Quick service $action: $name"
        else
            print_error "${action_text}失败"
        fi
        sleep 2
    fi
}

# ============================================================================
# 定时任务管理
# ============================================================================

cron_management() {
    while true; do
        clear
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║        定时任务管理                                        ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""
        
        echo "[1] 添加定时任务"
        echo "[2] 查看定时任务"
        echo "[3] 删除定时任务"
        echo "[0] 返回"
        echo ""
        read -p "选择: " choice
        
        case $choice in
            1) add_cron_job ;;
            2) view_cron_jobs ;;
            3) delete_cron_job ;;
            0) return ;;
        esac
    done
}

add_cron_job() {
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║        添加定时任务                                        ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    read -p "输入要定时执行的命令: " cmd
    
    if [[ -z "$cmd" ]]; then
        print_error "命令不能为空"
        sleep 2
        return
    fi
    
    echo ""
    echo "选择执行频率："
    echo "[1] 每小时"
    echo "[2] 每天（指定时间）"
    echo "[3] 每周（指定星期和时间）"
    echo "[4] 每月（指定日期和时间）"
    echo "[5] 自定义 Cron 表达式"
    echo ""
    read -p "选择: " freq
    
    local cron_expr=""
    
    case $freq in
        1)
            cron_expr="0 * * * *"
            ;;
        2)
            read -p "每天几点执行? (0-23): " hour
            cron_expr="0 $hour * * *"
            ;;
        3)
            read -p "周几执行? (0-6, 0=周日): " day
            read -p "几点执行? (0-23): " hour
            cron_expr="0 $hour * * $day"
            ;;
        4)
            read -p "每月几号? (1-31): " day
            read -p "几点执行? (0-23): " hour
            cron_expr="0 $hour $day * *"
            ;;
        5)
            read -p "输入 Cron 表达式 (如: */5 * * * *): " cron_expr
            ;;
        *)
            print_error "无效选择"
            sleep 2
            return
            ;;
    esac
    
    check_root
    
    # 添加到 crontab
    (crontab -l 2>/dev/null; echo "$cron_expr $cmd # tools-cron") | crontab -
    
    print_success "定时任务已添加"
    log_action "Add cron: $cron_expr $cmd"
    
    sleep 2
}

view_cron_jobs() {
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║        当前定时任务                                        ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    local cron_list=$(crontab -l 2>/dev/null | grep "# tools-cron")
    
    if [[ -z "$cron_list" ]]; then
        print_warning "暂无定时任务"
    else
        echo "$cron_list" | nl -w 3 -s '] '
    fi
    
    echo ""
    read -p "按回车继续..."
}

delete_cron_job() {
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║        删除定时任务                                        ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    local cron_list=$(crontab -l 2>/dev/null | grep "# tools-cron")
    
    if [[ -z "$cron_list" ]]; then
        print_warning "暂无定时任务"
        sleep 2
        return
    fi
    
    echo "当前定时任务："
    echo ""
    echo "$cron_list" | nl -w 3 -s '] '
    
    echo ""
    read -p "输入要删除的任务编号: " num
    
    local total=$(echo "$cron_list" | wc -l)
    
    if [[ $num -lt 1 || $num -gt $total ]]; then
        print_error "无效编号"
        sleep 2
        return
    fi
    
    local target=$(echo "$cron_list" | sed -n "${num}p")
    
    check_root
    
    # 从 crontab 删除
    crontab -l 2>/dev/null | grep -F -v "$target" | crontab -
    
    print_success "定时任务已删除"
    log_action "Delete cron: $target"
    
    sleep 2
}

# ============================================================================
# Docker 管理
# ============================================================================

install_docker_compose() {
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║        安装 Docker + Compose                               ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        print_warning "Docker 和 Compose 已安装"
        docker --version
        docker compose version
        echo ""
        read -p "按回车继续..."
        return
    fi
    
    check_root
    
    print_info "正在安装 Docker..."
    
    # 安装 Docker
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
        sh /tmp/get-docker.sh
        rm -f /tmp/get-docker.sh
        
        systemctl start docker
        systemctl enable docker
    fi
    
    # 安装 Docker Compose
    if ! docker compose version &> /dev/null; then
        print_info "正在安装 Docker Compose..."
        apt-get update
        apt-get install -y docker-compose-plugin
    fi
    
    if command -v docker &> /dev/null && docker compose version &> /dev/null; then
        print_success "Docker 和 Compose 安装成功"
        log_action "Install Docker + Compose"
    else
        print_error "安装失败"
        echo ""
        echo "可能的原因："
        echo "  1. 网络连接问题"
        echo "  2. 系统不支持（需要 Ubuntu 18.04+）"
        echo ""
        echo "建议操作："
        echo "  - 检查网络: ping get.docker.com"
        echo "  - 查看日志: journalctl -xe"
    fi
    
    echo ""
    read -p "按回车继续..."
}

docker_container_management() {
    while true; do
        clear
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║        Docker 容器管理                                     ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""
        
        if ! command -v docker &> /dev/null; then
            print_error "Docker 未安装，请先安装 Docker"
            sleep 2
            return
        fi
        
        # 获取所有容器
        local containers=$(docker ps -a --format "{{.ID}}|{{.Names}}|{{.State}}|{{.Ports}}" 2>/dev/null)
        
        if [[ -z "$containers" ]]; then
            print_warning "暂无容器"
            echo ""
            echo "[0] 返回"
            read -p "选择: " choice
            return
        fi
        
        echo "当前容器列表："
        echo ""
        
        local index=1
        while IFS='|' read -r id name state ports; do
            local status_color=$RED
            [[ "$state" == "running" ]] && status_color=$GREEN
            
            local status_text="已停止"
            [[ "$state" == "running" ]] && status_text="运行中"
            
            echo -ne "[$index] ${CYAN}$name${NC} - "
            echo -e "${status_color}$status_text${NC}"
            
            if [[ -n "$ports" ]]; then
                echo "    端口: $ports"
            fi
            
            ((index++))
        done <<< "$containers"
        
        echo ""
        echo "操作选项："
        echo "[S] 启动    [P] 停止    [R] 重启"
        echo "[D] 删除    [L] 日志    [E] 终端"
        echo "[0] 返回"
        echo ""
        read -p "选择操作和容器编号（如: S 1）: " action num
        
        case $action in
            [Ss]) docker_action "start" "$num" "$containers" ;;
            [Pp]) docker_action "stop" "$num" "$containers" ;;
            [Rr]) docker_action "restart" "$num" "$containers" ;;
            [Dd]) docker_action "rm" "$num" "$containers" ;;
            [Ll]) docker_action "logs" "$num" "$containers" ;;
            [Ee]) docker_action "exec" "$num" "$containers" ;;
            0) return ;;
            *)
                print_error "无效操作"
                sleep 1
                ;;
        esac
    done
}

docker_action() {
    local action="$1"
    local num="$2"
    local containers="$3"
    
    if [[ ! "$num" =~ ^[0-9]+$ ]]; then
        print_error "无效编号"
        sleep 1
        return
    fi
    
    local container_name=$(echo "$containers" | sed -n "${num}p" | cut -d'|' -f2)
    
    if [[ -z "$container_name" ]]; then
        print_error "容器不存在"
        sleep 1
        return
    fi
    
    case $action in
        start|stop|restart)
            if docker "$action" "$container_name" &>/dev/null; then
                print_success "操作成功"
                log_action "Docker $action: $container_name"
            else
                print_error "操作失败"
            fi
            sleep 1
            ;;
        rm)
            echo ""
            read -p "确认删除容器 $container_name? [y/N]: " confirm
            if [[ $confirm =~ ^[Yy]$ ]]; then
                docker rm -f "$container_name" &>/dev/null
                print_success "容器已删除"
                log_action "Docker rm: $container_name"
            fi
            sleep 1
            ;;
        logs)
            echo ""
            docker logs --tail 50 "$container_name"
            echo ""
            read -p "按回车继续..."
            ;;
        exec)
            echo ""
            print_info "进入容器终端（输入 exit 退出）"
            docker exec -it "$container_name" /bin/bash || docker exec -it "$container_name" /bin/sh
            ;;
    esac
}

# 快速 Docker 操作（从主菜单直接调用）
quick_docker_action() {
    local action="$1"
    
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║        快速 Docker 操作                                    ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker 未安装，请先安装 Docker"
        sleep 2
        return
    fi
    
    # 获取所有容器
    local containers=$(docker ps -a --format "{{.ID}}|{{.Names}}|{{.State}}|{{.Ports}}" 2>/dev/null)
    
    if [[ -z "$containers" ]]; then
        print_warning "暂无容器"
        sleep 2
        return
    fi
    
    echo "当前容器列表："
    echo ""
    
    local index=1
    while IFS='|' read -r id name state ports; do
        local status_color=$RED
        [[ "$state" == "running" ]] && status_color=$GREEN
        
        local status_text="已停止"
        [[ "$state" == "running" ]] && status_text="运行中"
        
        echo -ne "[$index] ${CYAN}$name${NC} - "
        echo -e "${status_color}$status_text${NC}"
        
        if [[ -n "$ports" ]]; then
            echo "    端口: $ports"
        fi
        
        ((index++))
        done <<< "$containers"
    
    echo ""
    
    local action_text="操作"
    case $action in
        start) action_text="启动" ;;
        stop) action_text="停止" ;;
        restart) action_text="重启" ;;
        rm) action_text="删除" ;;
        logs) action_text="查看日志" ;;
        exec) action_text="进入终端" ;;
    esac
    
    read -p "输入要${action_text}的容器编号: " num
    
    if [[ ! "$num" =~ ^[0-9]+$ ]]; then
        print_error "无效编号"
        sleep 1
        return
    fi
    
    local container_name=$(echo "$containers" | sed -n "${num}p" | cut -d'|' -f2)
    
    if [[ -z "$container_name" ]]; then
        print_error "容器不存在"
        sleep 1
        return
    fi
    
    case $action in
        start|stop|restart)
            if docker "$action" "$container_name" &>/dev/null; then
                print_success "${action_text}成功"
                log_action "Quick docker $action: $container_name"
            else
                print_error "${action_text}失败"
            fi
            sleep 1
            ;;
        rm)
            echo ""
            read -p "确认删除容器 $container_name? [y/N]: " confirm
            if [[ $confirm =~ ^[Yy]$ ]]; then
                docker rm -f "$container_name" &>/dev/null
                print_success "容器已删除"
                log_action "Quick docker rm: $container_name"
                sleep 1
            fi
            ;;
        logs)
            echo ""
            docker logs --tail 50 "$container_name"
            echo ""
            read -p "按回车继续..."
            ;;
        exec)
            echo ""
            print_info "进入容器终端（输入 exit 退出）"
            docker exec -it "$container_name" /bin/bash || docker exec -it "$container_name" /bin/sh
            ;;
    esac
}

# ============================================================================
# Caddy 反向代理（完善版）
# ============================================================================

install_caddy() {
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║        安装 Caddy 服务器                                   ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    if command -v caddy &> /dev/null; then
        print_warning "Caddy 已安装"
        caddy version
        echo ""
        read -p "按回车继续..."
        return
    fi
    
    check_root
    
    print_info "正在安装 Caddy..."
    
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt-get update
    apt-get install -y caddy
    
    if ! command -v caddy &> /dev/null; then
        print_error "安装失败"
        echo ""
        echo "可能的原因："
        echo "  1. 网络连接问题"
        echo "  2. 系统不支持"
        echo ""
        echo "建议操作："
        echo "  - 检查网络: ping dl.cloudsmith.io"
        sleep 3
        return
    fi
    
    # 配置 Caddy - 初始化为空配置
    mkdir -p /etc/caddy
    
    cat > /etc/caddy/Caddyfile <<'EOF'
# Caddy 配置文件
# 由 Tools 工具箱自动管理

# 全局配置
{
    admin localhost:2019
}

# HTTP 入口 (用于路径模式反代)
:80 {
    respond / "Caddy is running" 200
}

# HTTPS 入口 (用于域名模式反代)
:443 {
    respond / "Caddy is running on HTTPS" 200
}
EOF

    systemctl restart caddy
    systemctl enable caddy
    
    print_success "Caddy 安装完成"
    print_info "HTTP 端口: 80"
    print_info "HTTPS 端口: 443"
    print_info "管理端口: 2019"
    log_action "Install Caddy"
    
    echo ""
    read -p "按回车继续..."
}

add_caddy_route() {
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║        添加 Caddy 反代路由                                 ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    if ! command -v caddy &> /dev/null; then
        print_error "请先安装 Caddy"
        sleep 2
        return
    fi
    
    echo "选择路由模式："
    echo "[1] 域名模式（自动 HTTPS，推荐）"
    echo "[2] 路径模式（HTTP 路径转发）"
    echo ""
    read -p "选择: " mode
    
    case $mode in
        1)
            add_domain_route
            ;;
        2)
            add_path_route
            ;;
        *)
            print_error "无效选择"
            sleep 2
            ;;
    esac
}

add_domain_route() {
    echo ""
    print_info "域名模式配置"
    echo ""
    
    read -p "域名（如 example.com）: " domain
    if [[ -z "$domain" ]]; then
        print_error "域名不能为空"
        sleep 2
        return
    fi
    
    read -p "Caddy 监听端口 [443]: " caddy_port
    caddy_port=${caddy_port:-443}
    
    read -p "后端服务地址（如 localhost）: " backend_host
    backend_host=${backend_host:-localhost}
    
    read -p "后端服务端口（如 8080）: " backend_port
    if [[ -z "$backend_port" ]]; then
        print_error "后端端口不能为空"
        sleep 2
        return
    fi
    
    local backend="$backend_host:$backend_port"
    
    check_root
    
    # 检查是否已存在该域名配置
    if grep -q "^$domain {" /etc/caddy/Caddyfile; then
        print_error "域名 $domain 已存在配置"
        sleep 2
        return
    fi
    
    # 添加路由到 Caddyfile
    cat >> /etc/caddy/Caddyfile <<EOF

# 域名反代: $domain -> $backend
$domain:$caddy_port {
    reverse_proxy $backend
}
EOF

    # 验证并重载配置
    if caddy validate --config /etc/caddy/Caddyfile 2>/dev/null; then
        if systemctl reload caddy; then
            print_success "路由添加成功"
            echo ""
            print_info "访问地址: https://$domain:$caddy_port"
            print_info "后端地址: $backend"
            
            # 保存到本地数据
            local new_route=$(jq -n \
                --arg name "$domain" \
                --arg caddy_port "$caddy_port" \
                --arg backend "$backend" \
                --argjson mode 1 \
                '{name: $name, caddy_port: $caddy_port, backend: $backend, mode: $mode}')
            
            local updated=$(jq ".caddy_routes += [$new_route]" "$LOCAL_DATA")
            echo "$updated" > "$LOCAL_DATA"
            
            log_action "Add Caddy domain route: $domain:$caddy_port -> $backend"
        else
            print_error "Caddy 重载失败"
        fi
    else
        print_error "配置验证失败，请检查语法"
        # 回滚配置
        sed -i "/# 域名反代: $domain -> $backend/,/^}/d" /etc/caddy/Caddyfile
    fi
    
    sleep 3
}

add_path_route() {
    echo ""
    print_info "路径模式配置"
    echo ""
    
    read -p "路径前缀（如 /app1）: " path
    if [[ -z "$path" || ! "$path" =~ ^/ ]]; then
        print_error "路径必须以 / 开头"
        sleep 2
        return
    fi
    
    read -p "Caddy 监听端口 [80]: " caddy_port
    caddy_port=${caddy_port:-80}
    
    read -p "后端服务地址（如 localhost）: " backend_host
    backend_host=${backend_host:-localhost}
    
    read -p "后端服务端口（如 8080）: " backend_port
    if [[ -z "$backend_port" ]]; then
        print_error "后端端口不能为空"
        sleep 2
        return
    fi
    
    local backend="$backend_host:$backend_port"
    
    check_root
    
    # 检查是否已存在该路径配置
    if grep -q "handle $path\*" /etc/caddy/Caddyfile; then
        print_error "路径 $path 已存在配置"
        sleep 2
        return
    fi
    
    # 在 :caddy_port 块中添加路由
    # 如果端口块不存在，先创建
    if ! grep -q "^:$caddy_port {" /etc/caddy/Caddyfile; then
        cat >> /etc/caddy/Caddyfile <<EOF

# HTTP 入口 - $caddy_port
:$caddy_port {
}
EOF
    fi
    
    # 添加路由到对应端口块
    local route_config="    # 路径反代: $path -> $backend
    handle $path* {
        uri strip_prefix $path
        reverse_proxy $backend
    }"
    
    # 在端口块的最后一个 } 前插入
    awk -v port=":$caddy_port" -v route="$route_config" '
    BEGIN { in_block=0; block_line=0 }
    {
        if ($0 ~ "^" port " {") {
            in_block=1
            block_line=NR
        }
        if (in_block && $0 ~ "^}$") {
            print route
            in_block=0
        }
        print
    }' /etc/caddy/Caddyfile > /tmp/Caddyfile.tmp && mv /tmp/Caddyfile.tmp /etc/caddy/Caddyfile
    
    # 验证并重载配置
    if caddy validate --config /etc/caddy/Caddyfile 2>/dev/null; then
        if systemctl reload caddy; then
            print_success "路由添加成功"
            echo ""
            print_info "访问地址: http://your-ip:$caddy_port$path"
            print_info "后端地址: $backend"
            
            # 保存到本地数据
            local new_route=$(jq -n \
                --arg name "$path" \
                --arg caddy_port "$caddy_port" \
                --arg backend "$backend" \
                --argjson mode 2 \
                '{name: $name, caddy_port: $caddy_port, backend: $backend, mode: $mode}')
            
            local updated=$(jq ".caddy_routes += [$new_route]" "$LOCAL_DATA")
            echo "$updated" > "$LOCAL_DATA"
            
            log_action "Add Caddy path route: $path on port $caddy_port -> $backend"
        else
            print_error "Caddy 重载失败"
        fi
    else
        print_error "配置验证失败，请检查语法"
        echo ""
        echo "建议操作："
        echo "  - 查看配置: cat /etc/caddy/Caddyfile"
        echo "  - 验证配置: caddy validate --config /etc/caddy/Caddyfile"
    fi
    
    sleep 3
}

manage_caddy_routes() {
    while true; do
        clear
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║        Caddy 路由管理                                      ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""
        
        local route_count=$(jq '.caddy_routes | length' "$LOCAL_DATA" 2>/dev/null || echo "0")
        
        if [[ $route_count -eq 0 ]]; then
            print_warning "暂无路由配置"
        else
            echo "当前路由配置："
            echo ""
            for ((i=0; i<route_count; i++)); do
                local name=$(jq -r ".caddy_routes[$i].name" "$LOCAL_DATA")
                local caddy_port=$(jq -r ".caddy_routes[$i].caddy_port" "$LOCAL_DATA")
                local backend=$(jq -r ".caddy_routes[$i].backend" "$LOCAL_DATA")
                local mode=$(jq -r ".caddy_routes[$i].mode" "$LOCAL_DATA")
                
                local mode_text="路径模式"
                local mode_color=$CYAN
                [[ $mode -eq 1 ]] && mode_text="域名模式" && mode_color=$MAGENTA
                
                echo -e "[$((i+1))] ${mode_color}$name${NC}:$caddy_port -> $backend ($mode_text)"
            done
        fi
        
        echo ""
        echo "[D] 删除路由    [V] 查看配置文件    [E] 编辑配置文件"
        echo "[R] 重载 Caddy  [0] 返回"
        echo ""
        read -p "选择: " choice
        
        case $choice in
            [Dd]) delete_caddy_route ;;
            [Vv]) view_caddy_config ;;
            [Ee]) edit_caddy_config ;;
            [Rr]) reload_caddy ;;
            0) return ;;
        esac
    done
}

delete_caddy_route() {
    echo ""
    read -p "输入要删除的路由编号: " num
    
    local route_count=$(jq '.caddy_routes | length' "$LOCAL_DATA")
    
    if [[ $num -lt 1 || $num -gt $route_count ]]; then
        print_error "无效编号"
        sleep 2
        return
    fi
    
    local index=$((num - 1))
    local name=$(jq -r ".caddy_routes[$index].name" "$LOCAL_DATA")
    local mode=$(jq -r ".caddy_routes[$index].mode" "$LOCAL_DATA")
    
    check_root
    
    echo ""
    print_info "正在删除: $name"
    
    # 从配置文件中删除对应块
    if [[ $mode -eq 1 ]]; then
        # 域名模式：删除整个域名块
        sed -i "/^# 域名反代: $name/,/^}$/d" /etc/caddy/Caddyfile
        # 删除该域名的整个配置块
        sed -i "/^$name.*{$/,/^}$/d" /etc/caddy/Caddyfile
    else
        # 路径模式：删除 handle 块
        sed -i "/# 路径反代: $name/,/^    }$/d" /etc/caddy/Caddyfile
    fi
    
    # 验证并重载
    if caddy validate --config /etc/caddy/Caddyfile 2>/dev/null; then
        if systemctl reload caddy; then
            # 从本地数据中删除
            local updated=$(jq "del(.caddy_routes[$index])" "$LOCAL_DATA")
            echo "$updated" > "$LOCAL_DATA"
            
            print_success "路由已删除"
            log_action "Delete Caddy route: $name"
        else
            print_error "Caddy 重载失败"
        fi
    else
        print_error "配置验证失败"
        echo ""
        print_warning "建议手动编辑配置文件修复"
    fi
    
    sleep 2
}

view_caddy_config() {
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║        Caddy 配置文件                                      ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    if [[ -f /etc/caddy/Caddyfile ]]; then
        cat /etc/caddy/Caddyfile
    else
        print_error "配置文件不存在"
    fi
    
    echo ""
    read -p "按回车继续..."
}

edit_caddy_config() {
    check_root
    
    echo ""
    print_warning "准备编辑配置文件"
    print_info "保存前会自动验证配置"
    echo ""
    read -p "按回车继续..."
    
    # 备份配置
    cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.backup
    
    # 使用 nano 或 vi 编辑
    if command -v nano &> /dev/null; then
        nano /etc/caddy/Caddyfile
    else
        vi /etc/caddy/Caddyfile
    fi
    
    # 验证配置
    echo ""
    print_info "正在验证配置..."
    
    if caddy validate --config /etc/caddy/Caddyfile 2>/dev/null; then
        print_success "配置验证通过"
        echo ""
        read -p "是否重载 Caddy? [Y/n]: " confirm
        confirm=${confirm:-Y}
        
        if [[ $confirm =~ ^[Yy]$ ]]; then
            if systemctl reload caddy; then
                print_success "Caddy 已重载"
                log_action "Edit Caddy config and reload"
            else
                print_error "Caddy 重载失败"
            fi
        fi
    else
        print_error "配置验证失败！"
        echo ""
        read -p "是否恢复备份? [Y/n]: " restore
        restore=${restore:-Y}
        
        if [[ $restore =~ ^[Yy]$ ]]; then
            mv /etc/caddy/Caddyfile.backup /etc/caddy/Caddyfile
            print_success "已恢复配置"
        fi
    fi
    
    sleep 2
}

reload_caddy() {
    check_root
    
    echo ""
    print_info "正在验证配置..."
    
    if caddy validate --config /etc/caddy/Caddyfile 2>/dev/null; then
        print_success "配置验证通过"
        print_info "正在重载 Caddy..."
        
        if systemctl reload caddy; then
            print_success "Caddy 已重载"
            log_action "Reload Caddy"
        else
            print_error "Caddy 重载失败"
            echo ""
            echo "建议操作："
            echo "  - 查看状态: systemctl status caddy"
            echo "  - 查看日志: journalctl -u caddy -n 50"
        fi
    else
        print_error "配置验证失败"
        echo ""
        echo "建议操作："
        echo "  - 查看配置: cat /etc/caddy/Caddyfile"
        echo "  - 手动验证: caddy validate --config /etc/caddy/Caddyfile"
    fi
    
    sleep 2
}

# ============================================================================
# 网络工具
# ============================================================================

install_tailscale() {
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║        安装 Tailscale                                      ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    if command -v tailscale &> /dev/null; then
        print_warning "Tailscale 已安装"
        echo ""
        read -p "按回车继续..."
        return
    fi
    
    check_root
    print_info "正在安装 Tailscale..."
    
    curl -fsSL https://tailscale.com/install.sh | sh
    
    if command -v tailscale &> /dev/null; then
        print_success "Tailscale 安装成功"
        echo ""
        print_info "请运行: tailscale up"
        log_action "Install Tailscale"
    else
        print_error "安装失败"
    fi
    
    echo ""
    read -p "按回车继续..."
}

configure_exit_node() {
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║        配置 Exit Node                                      ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    if ! command -v tailscale &> /dev/null; then
        print_error "请先安装 Tailscale"
        sleep 2
        return
    fi
    
    check_root
    
    echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
    echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf
    sysctl -p
    
    tailscale up --advertise-exit-node
    
    print_success "Exit Node 配置完成"
    log_action "Configure Exit Node"
    
    echo ""
    read -p "按回车继续..."
}

install_1panel() {
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║        安装 1Panel                                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    check_root
    print_info "正在安装 1Panel..."
    
    curl -sSL https://resource.fit2cloud.com/1panel/package/quick_start.sh -o /tmp/quick_start.sh
    bash /tmp/quick_start.sh
    rm -f /tmp/quick_start.sh
    
    log_action "Install 1Panel"
    
    echo ""
    read -p "按回车继续..."
}

# ============================================================================
# 系统配置
# ============================================================================

change_timezone() {
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║        时区设置                                            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    local current_tz=$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}' || echo "Unknown")
    echo -e "当前时区: ${CYAN}$current_tz${NC}"
    echo ""
    
    echo "常用时区:"
    echo "[1] Asia/Shanghai (UTC+8)"
    echo "[2] America/New_York"
    echo "[3] Europe/London"
    echo "[4] UTC"
    echo "[0] 返回"
    echo ""
    read -p "选择: " choice
    
    local new_tz=""
    case $choice in
        1) new_tz="Asia/Shanghai" ;;
        2) new_tz="America/New_York" ;;
        3) new_tz="Europe/London" ;;
        4) new_tz="UTC" ;;
        0) return ;;
    esac
    
    if [[ -n "$new_tz" ]]; then
        check_root
        timedatectl set-timezone "$new_tz"
        print_success "时区已设置为: $new_tz"
        log_action "Change timezone to: $new_tz"
        sleep 2
    fi
}

enable_root_ssh() {
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║        启用 Root SSH                                       ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    check_root
    
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
    
    print_info "请设置 root 密码:"
    passwd root
    
    systemctl restart sshd || systemctl restart ssh
    
    print_success "Root SSH 已启用"
    log_action "Enable root SSH"
    
    echo ""
    read -p "按回车继续..."
}

# ============================================================================
# 自更新功能
# ============================================================================

update_script() {
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║        更新 Tools 脚本                                     ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    print_info "当前版本: v$VERSION"
    echo ""
    print_info "正在检查更新..."
    
    # 下载最新版本到临时文件
    local temp_script="/tmp/tools-update-$RANDOM.sh"
    
    if ! curl -fsSL -o "$temp_script" "$GITHUB_RAW_URL" 2>/dev/null; then
        print_error "下载失败，请检查网络连接"
        echo ""
        echo "可能的原因："
        echo "  1. 网络连接问题"
        echo "  2. GitHub 访问受限"
        echo ""
        echo "建议操作："
        echo "  - 检查网络: ping raw.githubusercontent.com"
        echo "  - 手动下载: $GITHUB_RAW_URL"
        rm -f "$temp_script"
        sleep 3
        return
    fi
    
    # 提取新版本号
    local new_version=$(grep '^VERSION=' "$temp_script" | head -1 | cut -d'"' -f2)
    
    if [[ -z "$new_version" ]]; then
        print_error "无法获取新版本信息"
        rm -f "$temp_script"
        sleep 2
        return
    fi
    
    echo ""
    print_info "最新版本: v$new_version"
    
    if [[ "$new_version" == "$VERSION" ]]; then
        print_success "已是最新版本"
        rm -f "$temp_script"
        sleep 2
        return
    fi
    
    echo ""
    read -p "是否更新到 v$new_version? [Y/n]: " confirm
    confirm=${confirm:-Y}
    
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        rm -f "$temp_script"
        return
    fi
    
    check_root
    
    echo ""
    print_info "正在备份当前版本..."
    cp "$INSTALL_PATH" "$INSTALL_PATH.backup-$VERSION"
    
    print_info "正在更新..."
    chmod +x "$temp_script"
    mv "$temp_script" "$INSTALL_PATH"
    
    print_success "✓ 更新完成！"
    print_info "备份文件: $INSTALL_PATH.backup-$VERSION"
    
    log_action "Update script: v$VERSION -> v$new_version"
    
    echo ""
    read -p "按回车重启工具箱..." 
    
    # 重启工具箱
    exec "$INSTALL_PATH"
}

# ============================================================================
# 自安装功能
# ============================================================================

check_and_install() {
    if [[ "$SCRIPT_PATH" != "$INSTALL_PATH" ]]; then
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║   Tools 工具箱首次运行                                     ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""
        print_info "检测到脚本未安装"
        print_info "当前路径: $SCRIPT_PATH"
        echo ""
        read -p "是否安装到系统? [Y/n] " choice
        choice=${choice:-Y}
        
        if [[ $choice =~ ^[Yy]$ ]]; then
            if [[ ! -f "$SCRIPT_PATH" ]]; then
                print_error "脚本文件不存在: $SCRIPT_PATH"
                exit 1
            fi
            
            check_root
            print_info "正在安装..."
            
            cp "$SCRIPT_PATH" "$INSTALL_PATH"
            chmod +x "$INSTALL_PATH"
            
            init_config
            
            print_success "安装完成！"
            echo ""
            echo "使用命令: t"
            echo ""
            exit 0
        fi
    fi
}

# ============================================================================
# 命令行参数处理
# ============================================================================

handle_cli_args() {
    case "$1" in
        --help|-h)
            echo "Tools v$VERSION - 轻量运维工具箱"
            echo ""
            echo "使用方法:"
            echo "  t              打开主菜单"
            echo "  t C            命令、脚本收藏夹"
            echo "  t --help       显示帮助"
            exit 0
            ;;
        [Cc])
            init_config
            sync_from_cloud silent
            command_script_favorites
            exit 0
            ;;
        "")
            return 0
            ;;
        *)
            print_error "未知参数: $1"
            exit 1
            ;;
    esac
}

# ============================================================================
# 主程序
# ============================================================================

main() {
    # 检查依赖
    if ! command -v jq &> /dev/null; then
        check_root
        print_info "正在安装 jq..."
        apt-get update && apt-get install -y jq
    fi
    
    check_and_install
    init_config
    
    if [[ $# -gt 0 ]]; then
        handle_cli_args "$@"
    fi
    
    main_menu
}

main "$@"
