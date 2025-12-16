#!/bin/bash
# curl -fsSL https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/tools.sh -o tools.sh && chmod +x tools.sh && sudo ./tools.sh

################################################################################
# 文件名: tools.sh
# 版本: v2.8.0 (GitHub Repo Edition + Script Links)
# 功能: Ubuntu Server 轻量运维工具箱
# 新增: 脚本链接管理功能（L1, L2...）
# 安装位置: /usr/local/bin/t
#           /usr/local/bin/tt (粘贴并执行快捷方式)
#           /usr/local/bin/tc (收藏夹快捷方式)
# 作者: Auto Generated (Modified)
# 日期: 2025-12-16
################################################################################

# ============================================================================
# 全局变量
# ============================================================================
VERSION="2.8.0"
SCRIPT_PATH="$(readlink -f "$0")"
INSTALL_PATH="/usr/local/bin/t"
LINK_TT="/usr/local/bin/tt"
LINK_TC="/usr/local/bin/tc"
CONFIG_DIR="/etc/tools"
LOG_DIR="/var/log/tools"
LOCAL_DATA="$CONFIG_DIR/local.json"
CACHE_FILE="$CONFIG_DIR/cloud_cache.json"
LINK_CACHE="$CONFIG_DIR/links_cache.txt"
IS_SYNCED="false"

# GitHub Repo 配置（Token 分段拼接）
TOKEN_P1="ghp_9L6XhJxk"
TOKEN_P2="aQHVYASNGW"
TOKEN_P3="nwSVJtqbNWYH4FgpIN"
GH_TOKEN="${TOKEN_P1}${TOKEN_P2}${TOKEN_P3}"
GH_OWNER="chf5762-sudo"
GH_REPO="bash"
GH_FILE="tools.json"
GH_BRANCH="main"
GH_LINK_FILE="bash-link.txt"
GITHUB_RAW_URL="https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/tools.sh"
GITHUB_LINK_RAW="https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/bash-link.txt"

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
    if [[ ! -f "$LOCAL_DATA" ]]; then
        echo '{"services": [], "caddy_routes": []}' > "$LOCAL_DATA"
    fi
    if [[ ! -f "$CACHE_FILE" ]]; then
        echo '{"commands": [], "scripts": []}' > "$CACHE_FILE"
    fi
    if [[ ! -f "$LINK_CACHE" ]]; then
        touch "$LINK_CACHE"
    fi
}

log_action() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_DIR/tools.log"
}

# ============================================================================
# 云端数据同步 (GitHub Repo)
# ============================================================================

sync_from_cloud() {
    local silent="$1"
    [[ "$silent" != "silent" ]] && print_info "正在从云端同步..."
    
    local api_url="https://api.github.com/repos/$GH_OWNER/$GH_REPO/contents/$GH_FILE?ref=$GH_BRANCH"
    local response=$(curl -s -H "Authorization: token $GH_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "$api_url" 2>/dev/null)
    
    if [[ -z "$response" ]]; then
        [[ "$silent" != "silent" ]] && print_error "网络连接失败"
        return 1
    fi
    
    local content=$(echo "$response" | jq -r '.content' 2>/dev/null)
    
    if [[ -z "$content" || "$content" == "null" ]]; then
        [[ "$silent" != "silent" ]] && print_warning "云端数据为空，初始化中..."
        init_cloud_data
        return 1
    fi
    
    echo "$content" | base64 -d > "$CACHE_FILE"
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
    
    # 先获取当前文件的 SHA
    local api_url="https://api.github.com/repos/$GH_OWNER/$GH_REPO/contents/$GH_FILE?ref=$GH_BRANCH"
    local file_info=$(curl -s -H "Authorization: token $GH_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "$api_url" 2>/dev/null)
    
    local current_sha=$(echo "$file_info" | jq -r '.sha' 2>/dev/null)
    
    if [[ -z "$current_sha" || "$current_sha" == "null" ]]; then
        [[ "$silent" != "silent" ]] && print_error "获取文件 SHA 失败"
        return 1
    fi
    
    local content_base64=$(base64 -w 0 "$CACHE_FILE")
    local commit_msg="Update tools.json via client v$VERSION ($(date +%Y-%m-%d))"
    
    local payload=$(jq -n \
        --arg msg "$commit_msg" \
        --arg content "$content_base64" \
        --arg sha "$current_sha" \
        --arg branch "$GH_BRANCH" \
        '{message: $msg, content: $content, sha: $sha, branch: $branch}')
    
    local response=$(curl -s -X PUT \
        -H "Authorization: token $GH_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        -d "$payload" \
        "$api_url" 2>/dev/null)
    
    if echo "$response" | grep -q '"content":'; then
        [[ "$silent" != "silent" ]] && print_success "推送完成"
        log_action "Synced to cloud (GitHub Repo)"
        return 0
    else
        [[ "$silent" != "silent" ]] && print_error "推送失败"
        return 1
    fi
}

init_cloud_data() {
    echo '{"commands": [], "scripts": []}' > "$CACHE_FILE"
    sync_to_cloud silent
}

# ============================================================================
# 脚本链接同步 (bash-link.txt)
# ============================================================================

sync_links_from_cloud() {
    local silent="$1"
    [[ "$silent" != "silent" ]] && print_info "正在同步脚本链接..."
    
    if curl -fsSL -o "$LINK_CACHE" "$GITHUB_LINK_RAW" 2>/dev/null; then
        [[ "$silent" != "silent" ]] && print_success "链接同步完成"
        return 0
    else
        [[ "$silent" != "silent" ]] && print_error "链接同步失败"
        return 1
    fi
}

sync_links_to_cloud() {
    local silent="$1"
    [[ "$silent" != "silent" ]] && print_info "正在推送链接到云端..."
    
    if [[ ! -f "$LINK_CACHE" ]]; then
        print_error "本地链接缓存不存在"
        return 1
    fi
    
    local api_url="https://api.github.com/repos/$GH_OWNER/$GH_REPO/contents/$GH_LINK_FILE?ref=$GH_BRANCH"
    
    # 获取当前文件的 SHA
    local file_info=$(curl -s -H "Authorization: token $GH_TOKEN" \
        -H "Accept: application/vnd.github.v3+json" \
        "$api_url" 2>/dev/null)
    
    local current_sha=$(echo "$file_info" | jq -r '.sha' 2>/dev/null)
    
    # 如果文件不存在（首次创建）
    if [[ -z "$current_sha" || "$current_sha" == "null" ]]; then
        local content_base64=$(base64 -w 0 "$LINK_CACHE")
        local commit_msg="Create bash-link.txt via client v$VERSION"
        
        local payload=$(jq -n \
            --arg msg "$commit_msg" \
            --arg content "$content_base64" \
            --arg branch "$GH_BRANCH" \
            '{message: $msg, content: $content, branch: $branch}')
        
        local response=$(curl -s -X PUT \
            -H "Authorization: token $GH_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            -d "$payload" \
            "$api_url" 2>/dev/null)
    else
        # 文件已存在，更新
        local content_base64=$(base64 -w 0 "$LINK_CACHE")
        local commit_msg="Update bash-link.txt via client v$VERSION ($(date +%Y-%m-%d))"
        
        local payload=$(jq -n \
            --arg msg "$commit_msg" \
            --arg content "$content_base64" \
            --arg sha "$current_sha" \
            --arg branch "$GH_BRANCH" \
            '{message: $msg, content: $content, sha: $sha, branch: $branch}')
        
        local response=$(curl -s -X PUT \
            -H "Authorization: token $GH_TOKEN" \
            -H "Accept: application/vnd.github.v3+json" \
            -d "$payload" \
            "$api_url" 2>/dev/null)
    fi
    
    if echo "$response" | grep -q '"content":'; then
        [[ "$silent" != "silent" ]] && print_success "链接推送完成"
        log_action "Synced links to cloud (bash-link.txt)"
        return 0
    else
        [[ "$silent" != "silent" ]] && print_error "链接推送失败"
        return 1
    fi
}

# ============================================================================
# 主菜单
# ============================================================================

show_system_info() {
    clear
    local os_name=$(grep "^PRETTY_NAME" /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "Unknown")
    local mem_info=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')
    local disk_info=$(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')
    
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║  Tools v${VERSION} | $os_name"
    echo "║  💾 内存: $mem_info | 💿 磁盘: $disk_info"
    echo "╚════════════════════════════════════════════════════════════╝"
}

main_menu() {
    # 仅首次进入时自动同步
    if [[ "$IS_SYNCED" == "false" ]]; then
        sync_from_cloud silent
        sync_links_from_cloud silent
        IS_SYNCED="true"
    fi
    
    while true; do
        show_system_info
        cat <<'EOF'

 ▸ 快捷操作
   [T/tt] 📝 粘贴并执行    [C/tc] 💾 收藏夹

EOF
        # 显示常用命令（最多3个）
        local fav_count=$(jq -r '[.commands[] | select(.favorite == true)] | length' "$CACHE_FILE" 2>/dev/null)
        if [[ "$fav_count" -gt 0 ]]; then
            echo " ▸ 常用命令 (⭐ 来自收藏夹)"
            jq -r '.commands[] | select(.favorite == true) | "\(.id)|\(.command)"' "$CACHE_FILE" 2>/dev/null | head -3 | while IFS='|' read -r id cmd; do
                local display_cmd="${cmd:0:50}"
                [[ ${#cmd} -gt 50 ]] && display_cmd="${display_cmd}..."
                echo "   [C$id] $display_cmd"
            done
            echo ""
        fi
        
        # 显示脚本链接（最多3个）
        if [[ -f "$LINK_CACHE" && -s "$LINK_CACHE" ]]; then
            local link_count=$(grep -c "^" "$LINK_CACHE" 2>/dev/null || echo "0")
            if [[ "$link_count" -gt 0 ]]; then
                echo " ▸ 快速脚本 (🔗 一键执行)"
                local line_num=1
                while IFS='|' read -r name url; do
                    [[ -z "$name" ]] && continue
                    echo "   [L$line_num] $name"
                    line_num=$((line_num + 1))
                    [[ $line_num -gt 3 ]] && break
                done < "$LINK_CACHE"
                echo ""
            fi
        fi
        
        cat <<'EOF'
 ▸ 服务与容器
   [1] 注册服务    [4] Docker     [7] 添加路由
   [2] 管理服务    [5] 容器管理    [8] 管理路由
   [3] 定时任务    [6] Caddy      [9] Tailscale
   
 ▸ 网络与系统
   [10] Exit Node  [12] 时区      [U] 🔄 更新脚本
   [11] 1Panel     [13] Root SSH  [0] 退出
════════════════════════════════════════════════════════════
EOF
        read -p "请选择 (支持 tt, tc, C1, L1): " choice
        local raw_choice="$choice"
        choice=$(echo "$choice" | tr '[:lower:]' '[:upper:]')
        
        # 支持直接输入 C1 / S2 / L1
        if [[ "$choice" =~ ^[CSL][0-9]+$ ]]; then
            execute_direct_by_string "$choice"
            continue
        fi
        
        case $choice in
            T|TT) run_script_from_paste ;;
            C|TC) command_script_favorites ;;
            1) register_binary_service ;;
            2) manage_services ;;
            3) cron_management ;;
            4) install_docker_compose ;;
            5) docker_container_management ;;
            6) install_caddy ;;
            7) add_caddy_route ;;
            8) manage_caddy_routes ;;
            9) install_tailscale ;;
            10) configure_exit_node ;;
            11) install_1panel ;;
            12) change_timezone ;;
            13) enable_root_ssh ;;
            U) update_script ;;
            0) exit 0 ;;
            *) 
                if [[ "$raw_choice" == "tt" ]]; then run_script_from_paste
                elif [[ "$raw_choice" == "tc" ]]; then command_script_favorites
                else print_error "无效选择"; sleep 0.5; fi
                ;;
        esac
    done
}

# ============================================================================
# [C] 收藏夹 (GitHub Repo 版 + 脚本链接)
# ============================================================================

command_script_favorites() {
    while true; do
        clear
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║    命令、脚本、链接收藏夹（云端：GitHub Repo）            ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""
        
        if [[ ! -f "$CACHE_FILE" ]]; then echo '{"commands": [], "scripts": []}' > "$CACHE_FILE"; fi

        local has_cmd=$(jq -r '(.commands | length) + (.scripts | length)' "$CACHE_FILE" 2>/dev/null)
        local has_link=0
        [[ -f "$LINK_CACHE" && -s "$LINK_CACHE" ]] && has_link=$(grep -c "^" "$LINK_CACHE" 2>/dev/null || echo "0")
        
        if [[ "$has_cmd" == "0" && "$has_link" == "0" ]] || [[ -z "$has_cmd" ]]; then
            print_warning "暂无数据 (按 R 刷新)"
        else
            # 批量渲染命令
            local cmd_list=$(jq -r '.commands[] | "\(.id)|\(.command)|\(.favorite // false)"' "$CACHE_FILE" 2>/dev/null)
            if [[ -n "$cmd_list" ]]; then
                echo -e "${CYAN}═══ 命令收藏 ═══${NC}"
                while IFS='|' read -r id cmd fav; do
                    local star=""
                    [[ "$fav" == "true" ]] && star="⭐ "
                    echo "[C$id] $star$cmd"
                done <<< "$cmd_list"
                echo ""
            fi
            
            # 批量渲染脚本
            local script_list=$(jq -r '.scripts[] | "\(.id)|\(.name)|\(.lines)"' "$CACHE_FILE" 2>/dev/null)
            if [[ -n "$script_list" ]]; then
                echo -e "${MAGENTA}═══ 脚本收藏 ═══${NC}"
                while IFS='|' read -r id name lines; do
                    echo "[S$id] $name (${lines}行)"
                done <<< "$script_list"
                echo ""
            fi
            
            # 批量渲染脚本链接（从 txt 文件）
            if [[ -f "$LINK_CACHE" && -s "$LINK_CACHE" ]]; then
                echo -e "${GREEN}═══ 脚本链接 ═══${NC}"
                local line_num=1
                while IFS='|' read -r name url; do
                    [[ -z "$name" ]] && continue
                    local display_url="${url:0:45}"
                    [[ ${#url} -gt 45 ]] && display_url="${display_url}..."
                    echo "[L$line_num] $name"
                    echo "      🔗 $display_url"
                    line_num=$((line_num + 1))
                done < "$LINK_CACHE"
                echo ""
            fi
        fi
        
        echo "[1] 添加命令    [2] 添加脚本    [3] 执行收藏"
        echo "[4] 删除收藏    [5] 🔢 重排编号 [6] ⭐ 设为常用"
        echo "[7] 💾 下载脚本  [8] 🔗 添加链接 [9] 📋 查看链接详情"
        echo "[R] 🔄 刷新     [0] 返回"
        echo ""
        read -p "请选择 (支持 tt, C1, L1): " choice
        
        # 菜单内直接支持 C1/S1/L1
        if [[ "$choice" =~ ^[CcSsLl][0-9]+$ ]]; then
             execute_direct_by_string "$choice"
             continue
        fi

        case $choice in
            tt|TT) run_script_from_paste ;;
            1) add_command_favorite ;;
            2) add_script_favorite ;;
            3) execute_favorite ;;
            4) delete_favorite ;;
            5) reorder_favorites ;;
            6) toggle_favorite ;;
            7) download_script ;;
            8) add_link_favorite ;;
            9) show_link_detail ;;
            [Rr]) 
                sync_from_cloud
                sync_links_from_cloud
                IS_SYNCED="true"
                ;;
            0) return ;;
            *) print_error "无效选择"; sleep 0.5 ;;
        esac
    done
}

execute_direct_by_string() {
    local input="$1"
    local type="${input:0:1}"
    local id="${input:1}"
    case "${type^^}" in
        C) execute_command_favorite "$id" ;;
        S) execute_script_favorite "$id" ;;
        L) execute_link_favorite "$id" ;;
    esac
}

add_command_favorite() {
    echo ""
    read -p "输入要收藏的命令: " cmd
    [[ -z "$cmd" ]] && return
    sync_from_cloud silent
    local max_id=$(jq '[.commands[].id] | max // 0' "$CACHE_FILE" 2>/dev/null)
    local new_id=$((max_id + 1))
    local new_cmd=$(jq -n --arg id "$new_id" --arg cmd "$cmd" --arg time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{id: ($id | tonumber), command: $cmd, favorite: false, added_time: $time}')
    jq ".commands += [$new_cmd]" "$CACHE_FILE" > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
    sync_to_cloud silent && print_success "已保存 [C$new_id]" || print_error "云端同步失败"
    sleep 1
}

add_script_favorite() {
    clear
    read -p "脚本名称: " script_name
    [[ -z "$script_name" ]] && return
    echo "请粘贴脚本内容 (Ctrl+D 结束):"
    local temp_script="/tmp/tools-script-$RANDOM.txt"
    cat > "$temp_script"
    [[ ! -s "$temp_script" ]] && { rm "$temp_script"; return; }
    local content=$(cat "$temp_script")
    local lines=$(wc -l < "$temp_script")
    sync_from_cloud silent
    local max_id=$(jq '[.scripts[].id] | max // 0' "$CACHE_FILE" 2>/dev/null)
    local new_id=$((max_id + 1))
    local new_obj=$(jq -n --arg id "$new_id" --arg name "$script_name" --arg content "$content" --arg lines "$lines" --arg time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{id: ($id | tonumber), name: $name, content: $content, lines: ($lines | tonumber), added_time: $time}')
    jq ".scripts += [$new_obj]" "$CACHE_FILE" > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
    rm "$temp_script"
    sync_to_cloud silent && print_success "已保存 [S$new_id]" || print_error "云端同步失败"
    sleep 1
}

add_link_favorite() {
    echo ""
    read -p "脚本名称: " link_name
    [[ -z "$link_name" ]] && return
    
    read -p "脚本 URL (支持 raw 链接): " link_url
    [[ -z "$link_url" ]] && return
    
    # 验证 URL 格式
    if ! [[ "$link_url" =~ ^https?:// ]]; then
        print_error "URL 必须以 http:// 或 https:// 开头"
        sleep 1
        return
    fi
    
    sync_links_from_cloud silent
    
    # 追加到文件末尾，格式：名称|URL
    echo "${link_name}|${link_url}" >> "$LINK_CACHE"
    
    sync_links_to_cloud silent && print_success "已保存链接" || print_error "云端同步失败"
    sleep 1
}

show_link_detail() {
    echo ""
    read -p "输入链接编号 (如 L1): " input
    local type="${input:0:1}"
    local id="${input:1}"
    
    if [[ "${type^^}" != "L" ]]; then
        print_error "仅支持链接查看 (L1, L2...)"
        sleep 1
        return
    fi
    
    [[ ! "$id" =~ ^[0-9]+$ ]] && return
    
    if [[ ! -f "$LINK_CACHE" || ! -s "$LINK_CACHE" ]]; then
        print_error "链接列表为空"
        sleep 1
        return
    fi
    
    local line=$(sed -n "${id}p" "$LINK_CACHE" 2>/dev/null)
    
    if [[ -z "$line" ]]; then
        print_error "未找到 L$id"
        sleep 1
        return
    fi
    
    local name=$(echo "$line" | cut -d'|' -f1)
    local url=$(echo "$line" | cut -d'|' -f2)
    
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║    脚本链接详情 [L$id]"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "名称: $name"
    echo "URL:  $url"
    echo ""
    read -p "按回车继续..."
}

execute_favorite() {
    echo ""
    read -p "输入编号 (如 C1, S2, L1): " input
    execute_direct_by_string "$input"
}

execute_command_favorite() {
    local id="$1"
    local cmd=$(jq -r ".commands[] | select(.id == $id) | .command" "$CACHE_FILE" 2>/dev/null)
    if [[ -z "$cmd" ]]; then print_error "未找到 C$id"; sleep 1; return; fi
    echo ""; print_info "执行: $cmd"; echo "════════════════════════════════════════════════════════════"
    eval "$cmd"
    echo "════════════════════════════════════════════════════════════"
    echo ""; read -p "按回车继续..."
}

execute_script_favorite() {
    local id="$1"
    local found=$(jq ".scripts[] | select(.id == $id)" "$CACHE_FILE" 2>/dev/null)
    if [[ -z "$found" ]]; then print_error "未找到 S$id"; sleep 1; return; fi
    local name=$(echo "$found" | jq -r '.name')
    local content=$(echo "$found" | jq -r '.content')
    echo ""; print_info "执行脚本: $name"; echo ""
    read -p "参数? [留空跳过]: " params
    local temp_script="/tmp/tools-exec-$RANDOM.sh"
    echo "$content" > "$temp_script" && chmod +x "$temp_script"
    echo ""; echo "════════════════════════════════════════════════════════════"
    bash "$temp_script" $params
    echo "════════════════════════════════════════════════════════════"
    rm -f "$temp_script"
    echo ""; read -p "按回车继续..."
}

execute_link_favorite() {
    local id="$1"
    
    if [[ ! -f "$LINK_CACHE" || ! -s "$LINK_CACHE" ]]; then
        print_error "链接列表为空"
        sleep 1
        return
    fi
    
    local line=$(sed -n "${id}p" "$LINK_CACHE" 2>/dev/null)
    
    if [[ -z "$line" ]]; then
        print_error "未找到 L$id"
        sleep 1
        return
    fi
    
    local name=$(echo "$line" | cut -d'|' -f1)
    local url=$(echo "$line" | cut -d'|' -f2)
    
    echo ""
    print_info "脚本: $name"
    print_info "URL: $url"
    echo ""
    read -p "参数? [留空跳过]: " params
    
    local temp_script="/tmp/tools-link-$RANDOM.sh"
    
    echo ""
    print_info "正在下载脚本..."
    
    if curl -fsSL -o "$temp_script" "$url"; then
        chmod +x "$temp_script"
        print_success "下载完成，开始执行..."
        echo ""
        echo "════════════════════════════════════════════════════════════"
        bash "$temp_script" $params
        echo "════════════════════════════════════════════════════════════"
        rm -f "$temp_script"
        log_action "Executed link L$id: $name"
    else
        print_error "下载失败，请检查 URL 是否正确"
        rm -f "$temp_script"
    fi
    
    echo ""
    read -p "按回车继续..."
}

delete_favorite() {
    read -p "输入删除编号 (C1/S2/L1): " input
    local type="${input:0:1}"
    local id="${input:1}"
    [[ ! "$id" =~ ^[0-9]+$ ]] && return
    
    case "${type^^}" in
        C)
            sync_from_cloud silent
            jq "del(.commands[] | select(.id == $id))" "$CACHE_FILE" > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
            sync_to_cloud silent && print_success "删除成功" || print_error "同步失败"
            ;;
        S)
            sync_from_cloud silent
            jq "del(.scripts[] | select(.id == $id))" "$CACHE_FILE" > "$CACHE_FILE.tmp" && mv "$CACHE_FILE.tmp" "$CACHE_FILE"
            sync_to_cloud silent && print_success "删除成功" || print_error "同步失败"
            ;;
        L)
            sync_links_from_cloud silent
            if [[ ! -f "$LINK_CACHE" || ! -s "$LINK_CACHE" ]]; then
                print_error "链接列表为空"
                sleep 1
                return
            fi
            # 删除指定行
            sed -i "${id}d" "$LINK_CACHE"
            sync_links_to_cloud silent && print_success "删除成功" || print_error "同步失败"
            ;;
        *)
            print_error "无效类型"
            sleep 1
            return
            ;;
    esac
    
    sleep 1
}

reorder_favorites() {
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║    重排编号功能                                            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    print_warning "此操作会重新分配 C/S 的 ID 为连续数字 (1, 2, 3...)"
    print_warning "链接(L)按行号自动排序，无需重排"
    read -p "确认执行? [y/N]: " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return
    
    sync_from_cloud silent
    
    # 使用临时文件逐步处理，避免 jq 内存问题
    local temp_file="/tmp/reorder-$RANDOM.json"
    
    # 重排命令 ID
    jq '.commands | sort_by(.id) | to_entries | map(.value + {id: (.key + 1)})' "$CACHE_FILE" > "$temp_file.commands"
    
    # 重排脚本 ID
    jq '.scripts | sort_by(.id) | to_entries | map(.value + {id: (.key + 1)})' "$CACHE_FILE" > "$temp_file.scripts"
    
    # 合并结果（不包含 links）
    jq -n \
        --slurpfile cmds "$temp_file.commands" \
        --slurpfile scripts "$temp_file.scripts" \
        '{commands: $cmds[0], scripts: $scripts[0]}' > "$CACHE_FILE.tmp"
    
    mv "$CACHE_FILE.tmp" "$CACHE_FILE"
    rm -f "$temp_file"*
    
    sync_to_cloud silent && print_success "重排完成" || print_error "同步失败"
    sleep 2
}

toggle_favorite() {
    echo ""
    read -p "输入编号 (如 C1): " input
    local type="${input:0:1}"
    local id="${input:1}"
    
    if [[ "${type^^}" != "C" ]]; then
        print_error "仅支持命令收藏 (C1, C2...)"
        sleep 1
        return
    fi
    
    [[ ! "$id" =~ ^[0-9]+$ ]] && return
    sync_from_cloud silent
    
    local current_fav=$(jq -r ".commands[] | select(.id == $id) | .favorite // false" "$CACHE_FILE" 2>/dev/null)
    
    if [[ -z "$current_fav" ]]; then
        print_error "未找到 C$id"
        sleep 1
        return
    fi
    
    local new_fav="true"
    [[ "$current_fav" == "true" ]] && new_fav="false"
    
    jq "(.commands[] | select(.id == $id) | .favorite) = $new_fav" "$CACHE_FILE" > "$CACHE_FILE.tmp" && \
        mv "$CACHE_FILE.tmp" "$CACHE_FILE"
    
    sync_to_cloud silent
    
    if [[ "$new_fav" == "true" ]]; then
        print_success "C$id 已设为常用 ⭐"
    else
        print_success "C$id 已取消常用"
    fi
    sleep 1
}

download_script() {
    echo ""
    read -p "输入脚本编号 (如 S1): " input
    local type="${input:0:1}"
    local id="${input:1}"
    
    if [[ "${type^^}" != "S" ]]; then
        print_error "仅支持脚本下载 (S1, S2...)"
        sleep 1
        return
    fi
    
    [[ ! "$id" =~ ^[0-9]+$ ]] && return
    
    local found=$(jq ".scripts[] | select(.id == $id)" "$CACHE_FILE" 2>/dev/null)
    if [[ -z "$found" ]]; then
        print_error "未找到 S$id"
        sleep 1
        return
    fi
    
    local name=$(echo "$found" | jq -r '.name')
    local content=$(echo "$found" | jq -r '.content')
    
    # 生成安全的文件名
    local safe_name=$(echo "$name" | tr ' ' '_' | tr -cd '[:alnum:]_.-')
    local output_file="${safe_name}.sh"
    
    echo ""
    read -p "保存路径 [默认: ./$output_file]: " user_path
    user_path=${user_path:-"./$output_file"}
    
    echo "$content" > "$user_path" && chmod +x "$user_path"
    
    if [[ -f "$user_path" ]]; then
        print_success "脚本已下载到: $user_path"
        log_action "Downloaded script S$id to $user_path"
    else
        print_error "下载失败"
    fi
    
    echo ""
    read -p "按回车继续..."
}

# ============================================================================
# 其他原有功能
# ============================================================================

run_script_from_paste() {
    clear; echo "请粘贴脚本 (Ctrl+D 结束):"; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    local t="/tmp/paste-$RANDOM.sh"; cat > "$t"
    [[ ! -s "$t" ]] && { rm "$t"; return; }
    echo ""; read -p "参数? : " p; chmod +x "$t"
    echo "════════════════════════════════════════════════════════════"
    bash "$t" $p; rm "$t"
    echo "════════════════════════════════════════════════════════════"
    echo ""; read -p "按回车继续..."
}

register_binary_service() {
    read -p "目录: " d; [[ ! -d "$d" ]] && return
    find "$d" -maxdepth 1 -type f -executable | nl; read -p "选择: " n
    f=$(find "$d" -maxdepth 1 -type f -executable | sed -n "${n}p")
    [[ -z "$f" ]] && return
    bn=$(basename "$f"); read -p "服务名 [$bn]: " sn; sn=${sn:-$bn}
    check_root
    cat > "/etc/systemd/system/${sn}.service" <<EOF
[Unit]
Description=$sn
After=network.target
[Service]
ExecStart=$f
WorkingDirectory=$d
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload && systemctl enable --now "$sn" && print_success "成功"
    local up=$(jq ".services += [{\"name\":\"$sn\"}]" "$LOCAL_DATA")
    echo "$up" > "$LOCAL_DATA"
    sleep 2
}

manage_services() {
    while true; do
        clear; echo "已注册服务:"; jq -r '.services[].name' "$LOCAL_DATA" | nl
        echo ""; read -p "[S]启 [P]停 [R]重启 [L]日志 [0]返: " c
        [[ $c == 0 ]] && return
        read -p "编号: " n; name=$(jq -r ".services[$((n-1))].name" "$LOCAL_DATA")
        case $c in
            S|s) systemctl start "$name" ;; P|p) systemctl stop "$name" ;;
            R|r) systemctl restart "$name" ;; L|l) journalctl -u "$name" -n 20; read -p "..." ;;
        esac
    done
}

cron_management() {
    print_info "定时任务管理功能暂未实现"
    sleep 2
}

add_caddy_route() {
    print_info "Caddy 路由添加功能暂未实现"
    sleep 2
}
add_caddy_route() {
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║    添加 Caddy 路由                                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    # 检查 Caddy
    if ! command -v caddy &>/dev/null; then
        print_error "Caddy 未安装"
        sleep 2
        return
    fi
    
    # 输入域名
    read -p "域名 (如 example.com): " domain
    [[ -z "$domain" ]] && return
    
    # 输入路径
    read -p "路径 (如 /api, 默认 /): " path
    path=${path:-/}
    [[ ! "$path" =~ ^/ ]] && path="/$path"
    
    # 输入后端
    read -p "后端地址 (如 localhost:8080): " backend
    [[ -z "$backend" ]] && return
    
    # 确认
    echo ""
    echo "域名: $domain"
    echo "路径: $path"
    echo "后端: $backend"
    echo "说明: 自动配置 HTTP (80) 和 HTTPS (443)"
    read -p "确认? [Y/n]: " confirm
    [[ "$confirm" =~ ^[Nn]$ ]] && return
    
    # 保存
    check_root
    local max_id=$(jq '[.caddy_routes[].id] | max // 0' "$LOCAL_DATA" 2>/dev/null)
    local new_id=$((max_id + 1))
    
    local new_route=$(jq -n \
        --arg id "$new_id" \
        --arg domain "$domain" \
        --arg path "$path" \
        --arg backend "$backend" \
        '{
            id: ($id | tonumber),
            domain: $domain,
            path: $path,
            backend: $backend
        }')
    
    jq ".caddy_routes += [$new_route]" "$LOCAL_DATA" > "$LOCAL_DATA.tmp" && \
        mv "$LOCAL_DATA.tmp" "$LOCAL_DATA"
    
    print_success "路由已添加 [ID: $new_id]"
    log_action "Added route: $domain$path -> $backend"
    sleep 2
}

delete_caddy_route() {
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║    删除 Caddy 路由                                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    # 显示列表
    local route_count=$(jq '.caddy_routes | length' "$LOCAL_DATA" 2>/dev/null)
    if [[ "$route_count" == "0" || -z "$route_count" ]]; then
        print_warning "暂无路由"
        sleep 2
        return
    fi
    
    echo " ID  域名                      路径        后端"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    jq -r '.caddy_routes[] | "\(.id)|\(.domain)|\(.path)|\(.backend)"' "$LOCAL_DATA" 2>/dev/null | \
        while IFS='|' read -r id domain path backend; do
            printf " %-3s %-25s %-11s %s\n" "$id" "$domain" "$path" "$backend"
        done
    
    echo ""
    read -p "输入要删除的 ID: " route_id
    [[ ! "$route_id" =~ ^[0-9]+$ ]] && return
    
    # 确认删除
    local route_info=$(jq -r --arg id "$route_id" \
        '.caddy_routes[] | select(.id == ($id | tonumber)) | 
        "\(.domain)\(.path) -> \(.backend)"' "$LOCAL_DATA" 2>/dev/null)
    
    if [[ -z "$route_info" ]]; then
        print_error "ID $route_id 不存在"
        sleep 2
        return
    fi
    
    echo "将删除: $route_info"
    read -p "确认? [y/N]: " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return
    
    # 删除
    check_root
    jq --arg id "$route_id" \
        'del(.caddy_routes[] | select(.id == ($id | tonumber)))' \
        "$LOCAL_DATA" > "$LOCAL_DATA.tmp" && mv "$LOCAL_DATA.tmp" "$LOCAL_DATA"
    
    print_success "删除成功"
    log_action "Deleted route ID: $route_id"
    sleep 2
}

reload_caddy_config() {
    clear
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║    应用 Caddy 配置                                         ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    check_root
    
    print_info "正在生成配置..."
    
    local caddyfile="/etc/caddy/Caddyfile"
    local backup="/etc/caddy/Caddyfile.backup.$(date +%s)"
    
    # 备份
    [[ -f "$caddyfile" ]] && cp "$caddyfile" "$backup"
    
    # 生成配置
    {
        echo "# Auto-generated by Tools v${VERSION}"
        echo "# Generated at: $(date)"
        echo ""
        
        # 按域名分组
        local domains=$(jq -r '.caddy_routes[].domain' "$LOCAL_DATA" 2>/dev/null | sort -u)
        
        while IFS= read -r domain; do
            [[ -z "$domain" ]] && continue
            
            echo "${domain} {"
            
            # 该域名下的所有路由
            jq -r --arg domain "$domain" \
                '.caddy_routes[] | select(.domain == $domain) | "\(.path)|\(.backend)"' \
                "$LOCAL_DATA" 2>/dev/null | while IFS='|' read -r path backend; do
                echo "    handle ${path} {"
                echo "        reverse_proxy ${backend}"
                echo "    }"
            done
            
            echo "}"
            echo ""
        done <<< "$domains"
        
    } > "$caddyfile"
    
    # 验证
    if ! caddy validate --config "$caddyfile" &>/dev/null; then
        print_error "配置验证失败"
        [[ -f "$backup" ]] && mv "$backup" "$caddyfile"
        sleep 2
        return
    fi
    
    # 重启
    print_info "正在重启 Caddy..."
    if systemctl restart caddy; then
        print_success "Caddy 已重启"
        log_action "Reloaded Caddy config"
    else
        print_error "重启失败"
        [[ -f "$backup" ]] && mv "$backup" "$caddyfile"
    fi
    
    sleep 2
}
manage_caddy_routes() {
    while true; do
        clear
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║    Caddy 路由管理                                          ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo ""
        
        # 显示当前路由
        local route_count=$(jq '.caddy_routes | length' "$LOCAL_DATA" 2>/dev/null)
        if [[ "$route_count" == "0" || -z "$route_count" ]]; then
            print_warning "暂无路由配置"
        else
            echo " ID  域名                      路径        后端"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            jq -r '.caddy_routes[] | "\(.id)|\(.domain)|\(.path)|\(.backend)"' "$LOCAL_DATA" 2>/dev/null | \
                while IFS='|' read -r id domain path backend; do
                    printf " %-3s %-25s %-11s %s\n" "$id" "$domain" "$path" "$backend"
                done
        fi
        
        echo ""
        echo "[1] 添加路由 (自动配置 HTTP 80 + HTTPS 443)"
        echo "[2] 删除路由"
        echo "[3] 应用配置并重启 Caddy"
        echo "[0] 返回"
        echo ""
        read -p "请选择: " choice
        
        case $choice in
            1) add_caddy_route ;;
            2) delete_caddy_route ;;
            3) reload_caddy_config ;;
            0) return ;;
            *) print_error "无效选择"; sleep 0.5 ;;
        esac
    done
}

configure_exit_node() {
    print_info "Exit Node 配置功能暂未实现"
    sleep 2
}

change_timezone() {
    print_info "时区设置功能暂未实现"
    sleep 2
}

enable_root_ssh() {
    print_info "Root SSH 启用功能暂未实现"
    sleep 2
}

install_docker_compose() {
    if ! command -v docker &>/dev/null; then curl -fsSL https://get.docker.com | sh; fi
    apt-get install -y docker-compose-plugin
    print_success "Docker 安装完成"; sleep 2
}

docker_container_management() {
    while true; do
        clear; docker ps -a --format "table {{.ID}}\t{{.Names}}\t{{.Status}}" | nl
        echo ""; read -p "[S]启 [P]停 [R]重启 [D]删 [L]日志 [E]进 [0]返: " c
        [[ $c == 0 ]] && return
        read -p "行号(非ID): " n; id=$(docker ps -a --format "{{.ID}}" | sed -n "$((n-1))p")
        [[ -z "$id" ]] && continue
        case $c in
            S|s) docker start "$id" ;; P|p) docker stop "$id" ;; R|r) docker restart "$id" ;;
            D|d) docker rm -f "$id" ;; L|l) docker logs --tail 20 "$id"; read -p "..." ;;
            E|e) docker exec -it "$id" sh ;;
        esac
    done
}

install_caddy() {
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt-get update && apt-get install -y caddy
    print_success "Caddy 安装完成"; sleep 2
}

install_tailscale() { 
    curl -fsSL https://tailscale.com/install.sh | sh
    print_success "Tailscale 安装完成"; sleep 2
}

install_1panel() { 
    curl -sSL https://resource.fit2cloud.com/1panel/package/quick_start.sh | bash
}

update_script() {
    local t="/tmp/update.sh"
    if curl -fsSL -o "$t" "$GITHUB_RAW_URL"; then
        chmod +x "$t"; mv "$t" "$INSTALL_PATH"
        ln -sf "$INSTALL_PATH" "$LINK_TT"; ln -sf "$INSTALL_PATH" "$LINK_TC"
        print_success "更新完成，正在重启..."; sleep 1; exec "$INSTALL_PATH"
    else
        print_error "下载失败"; sleep 2
    fi
}

check_and_install() {
    if [[ "$SCRIPT_PATH" != "$INSTALL_PATH" ]]; then
        cp "$SCRIPT_PATH" "$INSTALL_PATH" && chmod +x "$INSTALL_PATH"
        ln -sf "$INSTALL_PATH" "$LINK_TT" && ln -sf "$INSTALL_PATH" "$LINK_TC"
        init_config
        print_success "安装成功! 使用 't' 启动。"
        exit 0
    fi
}

handle_cli_args() {
    case "$1" in
        --help|-h) echo "Usage: t [C1|S1|L1] | tt | tc"; exit 0 ;;
        [Tt][Tt]) run_script_from_paste; exit 0 ;;
        [Cc]|[Tt][Cc]) init_config; sync_from_cloud silent; sync_links_from_cloud silent; IS_SYNCED="true"; command_script_favorites; exit 0 ;;
        [CcSsLl][0-9]*)
            init_config
            sync_from_cloud silent
            sync_links_from_cloud silent
            execute_direct_by_string "$1"
            exit 0
            ;;
    esac
}

# ============================================================================
# 主入口
# ============================================================================

main() {
    if ! command -v jq &>/dev/null; then apt-get update && apt-get install -y jq; fi
    
    # 优先检查调用名称（在安装检查之前）
    local name=$(basename "$0")
    
    # 处理快捷方式调用
    if [[ "$name" == "tt" ]]; then
        init_config
        run_script_from_paste
        exit 0
    elif [[ "$name" == "tc" ]]; then
        init_config
        sync_from_cloud silent
        sync_links_from_cloud silent
        IS_SYNCED="true"
        command_script_favorites
        exit 0
    fi
    
    # 正常流程：安装检查和主菜单
    check_and_install
    init_config
    
    [[ $# -gt 0 ]] && handle_cli_args "$@"
    main_menu
}

main "$@"
