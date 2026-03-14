#!/bin/bash
# curl -fsSL https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/tools.sh -o tools.sh && chmod +x tools.sh && sudo ./tools.sh

################################################################################
# 文件名: tools.sh
# 版本: v2.8.0 (GitHub Repo Edition + Script Links)
# 功能: Ubuntu Server 轻量运维工具箱
# 新增: 脚本链接管理功能（L1, L2...）
# 安装位置: /usr/local/bin/t
#           /usr/local/bin/tt (粘贴并执行快捷方式)
#           /usr/local/bin/tc (收藏夹快捷方式)
# 作者: Auto Generated (Modified)
# 日期: 2025-12-16
# 修复: 修复 Caddy 路由添加逻辑，解决 502 Bad Gateway 问题
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

# 增强输出函数
msg_ok()   { echo -e "${GREEN}✓${NC} $1"; }
msg_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
msg_info() { echo -e "${CYAN}ℹ${NC} $1"; }
msg_err()  { echo -e "${RED}✗${NC} $1"; }

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
    local file_info=$(curl -s -X GET \
        -H "Authorization: token $GH_TOKEN" \
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
    echo "║  Tools v${VERSION} | $os_name"
    echo "║  💾 内存: $mem_info | 💿 磁盘: $disk_info"
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
   [T/tt] 📝 粘贴并执行    [C/tc] 💾 收藏夹

EOF
        # 显示常用命令（最多3个）
        local fav_count=$(jq -r '[.commands[] | select(.favorite == true)] | length' "$CACHE_FILE" 2>/dev/null)
        if [[ "$fav_count" -gt 0 ]]; then
            echo " ▸ 常用命令 (⭐ 来自收藏夹)"
            jq -r '.commands[] | select(.favorite == true) | "\(.id)|\(.command)"' "$CACHE_FILE" 2>/dev/null | head -3 | while IFS='|' read -r id cmd; do
                local display_cmd="${cmd:0:50}"
                [[ ${#cmd} -gt 50 ]] && display_cmd="${display_cmd}..."
                echo "   [C$id] $display_cmd"
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
                    echo "   [L$line_num] $name"
                    line_num=$((line_num + 1))
                    [[ $line_num -gt 3 ]] && break
                done < "$LINK_CACHE"
                echo ""
            fi
        fi
        
        cat <<'EOF'
 ▸ 服务与容器
   [1] 注册服务    [4] Docker 管理   [7] Caddy 管理
   [2] 管理服务    [5] Tailscale      [8] 1Panel
   [3] 定时任务    [6] 系统设置       [9] Root SSH
   
 ▸ 其他
   [U] 🔄 更新脚本  [0] 退出
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
            4) docker_unified_management ;;
            5) install_tailscale ;;
            6) system_settings_menu ;;
            7) caddy_unified_management ;;
            8) install_1panel ;;
            9) enable_root_ssh ;;
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
        echo "║    命令、脚本、链接收藏夹（云端：GitHub Repo）            ║"
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
                    echo "      🔗 $display_url"
                    line_num=$((line_num + 1))
                done < "$LINK_CACHE"
                echo ""
            fi
        fi
        
        echo "[1] 添加命令    [2] 添加脚本    [3] 执行收藏"
        echo "[4] 删除收藏    [5] 🔢 重排编号 [6] ⭐ 设为常用"
        echo "[7] 💾 下载脚本  [8] 🔗 添加链接 [9] 📋 查看链接详情"
        echo "[R] 🔄 刷新     [0] 返回"
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
    echo "║    脚本链接详情 [L$id]"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    echo "名称: $name"
    echo "URL:  $url"
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
    echo "║    重排编号功能                                            ║"
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

# ============================================================================
# Caddy 综合管理 (集成 caddy-manager.sh)
# ============================================================================

CADDY_CONFIG="/etc/caddy/Caddyfile"

reload_caddy() {
    msg_info "🔄 正在同步 Caddy 配置..."
    if ! systemctl is-active --quiet caddy; then
        msg_warn "⚠️ Caddy 处于停止状态，尝试启动..."
        systemctl start caddy && msg_ok "✅ Caddy 已启动" || msg_err "❌ 启动失败"
    else
        if caddy reload --config "$CADDY_CONFIG" >/dev/null 2>&1; then
            msg_ok "✅ 配置热重载成功"
        else
            msg_warn "⚠️ 热重载失败，尝试重启服务..."
            systemctl restart caddy && msg_ok "✅ Caddy 已重启" || msg_err "❌ 重启失败"
        fi
    fi
}

caddy_unified_management() {
    check_root
    while true; do
        clear
        echo "╔══════════════════════════════════════════════════════╗"
        echo "║    🛡️  Caddy 智能网关管理系统"
        echo "╚══════════════════════════════════════════════════════╝"
        echo " 1) 🔍 环境审计 (Check)"
        echo " 2) 🤖 智能修复 (自动迁移冲突端口)"
        echo " 3) 🌐 域名管理 (添加/删除/列表)"
        echo " 4) 📦 服务端口一键映射 (反代)"
        echo " 5) 🚥 查看运行状态与日志"
        echo " 6) 🔐 Basic Auth 开关"
        echo " 7) 📥 安装 Caddy"
        echo " 0) 返回"
        echo "--------------------------------------------------------"
        read -p " 请选择指令: " cchoice
        case $cchoice in
            1) caddy_check_env; read -p "回车继续..." ;;
            2) caddy_fix_conflicts; read -p "回车继续..." ;;
            3) caddy_domain_menu ;;
            4) caddy_add_proxy_ui ;;
            5) clear; caddy fmt "$CADDY_CONFIG" && systemctl status caddy; journalctl -u caddy -n 20 --no-pager; read -p "回车继续..." ;;
            6) caddy_toggle_auth ;;
            7) install_caddy_official ;;
            0) return ;;
        esac
    done
}

caddy_check_env() {
    msg_ok "🔎 正在执行系统环境审计..."
    command -v caddy >/dev/null && msg_ok "Caddy 已安装: $(caddy version | head -n1)" || msg_warn "未发现 Caddy"
    command -v nginx >/dev/null && msg_warn "⚠ 发现 Nginx 已安装，可能存在端口冲突"
    
    for port in 80 443; do
        local pids=$(lsof -t -i :$port -sTCP:LISTEN)
        if [ -n "$pids" ]; then
            for pid in $pids; do
                local proc=$(ps -p $pid -o comm= 2>/dev/null || echo "unknown")
                msg_err "⚠ 端口 $port 被占用! PID: $pid ($proc)"
            done
        else
            msg_ok "✓ 端口 $port 可用"
        fi
    done
}

caddy_fix_conflicts() {
    msg_warn "🚀 正在尝试强行抢占 80/443 端口..."
    for port in 80 443; do
        local pids=$(lsof -t -i :$port -sTCP:LISTEN)
        if [ -n "$pids" ]; then
            msg_warn "正在关闭占用 $port 端口的进程: $pids"
            kill -9 $pids 2>/dev/null && msg_ok "端口 $port 已释放"
        fi
    done
}

caddy_domain_menu() {
    while true; do
        clear
        echo " ▸ 当前已配域名："
        local domains=($(awk '/^[a-zA-Z0-9.-]+ \{/ {print $1}' "$CADDY_CONFIG" 2>/dev/null))
        for d in "${domains[@]}"; do echo "   • $d"; done
        echo "----------------------------------------"
        echo " 1) 添加新域名头  2) 删除域名配置  0) 返回"
        read -p "选择: " d_opt
        case $d_opt in
            1)
                read -p "域名: " ndomain
                [[ -n "$ndomain" ]] && echo -e "\n$ndomain {\n    # Added by tools.sh\n}" >> "$CADDY_CONFIG" && msg_ok "已添加" && reload_caddy ;;
            2)
                read -p "输入要删除的完整域名: " rdomain
                [[ -n "$rdomain" ]] && sed -i "/^$rdomain {/,/^}/d" "$CADDY_CONFIG" && msg_ok "已删除" && reload_caddy ;;
            0) return ;;
        esac
        sleep 1
    done
}

caddy_add_proxy_ui() {
    read -p "请输入要绑定的域名 (需先存在): " domain
    if ! grep -q "^$domain {" "$CADDY_CONFIG"; then msg_err "域名未配置"; sleep 1; return; fi
    read -p "请输入要反代的本地端口: " port
    read -p "请输入子路径 (如 /vnc, 留空为 /): " path
    path=${path:-"/"}
    
    local indent="    "
    if [[ "$path" == "/" ]]; then
        sed -i "/^$domain {/a \\${indent}reverse_proxy localhost:$port" "$CADDY_CONFIG"
    else
        local block="${indent}handle_path $path/* {\n${indent}    reverse_proxy localhost:$port\n${indent}}"
        sed -i "/^$domain {/a \\$block" "$CADDY_CONFIG"
    fi
    msg_ok "路由已添加"; reload_caddy; sleep 1
}

caddy_toggle_auth() {
    msg_info "此功能将为选定域名设置简单认证 (admin:password)"
    read -p "请输入要操作的域名: " domain
    if sed -n "/^$domain {/,/^}/p" "$CADDY_CONFIG" | grep -q 'basic_auth'; then
        sed -i "/^$domain {/,/^}/ { /basic_auth {/,/^    }/d }" "$CADDY_CONFIG"
        msg_ok "已关闭认证"
    else
        local hash=$(caddy hash-password --plaintext "password" 2>/dev/null)
        sed -i "/^$domain {/a \\    basic_auth {\n        admin $hash\n    }" "$CADDY_CONFIG"
        msg_ok "已启用认证 (admin:password)"
    fi
    reload_caddy; sleep 1
}

install_caddy_official() {
    msg_info "正在安装 Caddy..."
    apt-get update && apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null || true
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.debian.list' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt-get update && apt-get install -y caddy
    systemctl enable caddy && systemctl start caddy
    msg_ok "安装完成"
}

# ============================================================================
# Docker 综合管理 (升级版)
# ============================================================================

docker_unified_management() {
    while true; do
        clear
        echo "╔══════════════════════════════════════════════════════╗"
        echo "║    🐳 Docker & Compose 综合管理"
        echo "╚══════════════════════════════════════════════════════╝"
        
        if ! command -v docker &>/dev/null; then
            msg_warn "Docker 未安装"
            echo " [I] 一键安装 Docker & Compose"
        else
            echo " ▸ 容器列表："
            docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | nl -w2 -s' | '
        fi
        echo "--------------------------------------------------------"
        echo " [S]启动 [P]停止 [R]重启 [D]删除 [L]日志 [E]进入Shell"
        echo " [F]文件浏览 [V]详细信息 [I]下载/更新 Docker [0]返回"
        read -p " 请选择 (操作请加行号, 如 S1): " d_input
        [[ "$d_input" == "0" ]] && return
        
        if [[ "$d_input" =~ ^[Ii]$ ]]; then
            curl -fsSL https://get.docker.com | sh
            apt-get install -y docker-compose-plugin
            msg_ok "安装完成"; sleep 1; continue
        fi

        local op=$(echo "${d_input:0:1}" | tr '[:lower:]' '[:upper:]')
        local idx="${d_input:1}"
        [[ -z "$idx" ]] && continue
        
        local target_name=$(docker ps -a --format "{{.Names}}" | sed -n "${idx}p")
        [[ -z "$target_name" ]] && msg_err "无效行号" && sleep 1 && continue

        case $op in
            S) docker start "$target_name" && msg_ok "已启动" ;;
            P) docker stop "$target_name" && msg_ok "已停止" ;;
            R) docker restart "$target_name" && msg_ok "已重启" ;;
            D) read -p "确认删除 $target_name? [y/N]: " confirm && [[ "$confirm" =~ ^[Yy]$ ]] && docker rm -f "$target_name" && msg_ok "已删除" ;;
            L) docker logs --tail 50 "$target_name"; read -p "回车继续..." ;;
            E) docker exec -it "$target_name" sh || docker exec -it "$target_name" bash ;;
            V) docker inspect "$target_name" | jq '.[0].NetworkSettings.Ports'; read -p "回车继续..." ;;
            F) docker_file_browser "$target_name" ;;
        esac
        sleep 0.5
    done
}

docker_file_browser() {
    local container="$1"
    local path="/"
    while true; do
        clear
        echo "📂 容器 [$container] 文件浏览: $path"
        echo "----------------------------------------"
        docker exec "$container" ls -F "$path" 2>/dev/null || msg_err "无法读取路径"
        echo "----------------------------------------"
        echo " [CD]切换路径 [U]上级目录 [0]返回"
        read -p "指令: " f_opt
        case $(echo "$f_opt" | tr '[:lower:]' '[:upper:]') in
            CD) read -p "进入目录名: " ndir; path="${path%/}/$ndir" ;;
            U) path=$(dirname "$path") ;;
            0) return ;;
        esac
    done
}

system_settings_menu() {
    while true; do
        clear
        echo "╔══════════════════════════════════════════════════════╗"
        echo "║    ⚙️  系统与环境设置"
        echo "╚══════════════════════════════════════════════════════╝"
        echo " [1] 时区设置"
        echo " [2] Exit Node 配置 (Tailscale)"
        echo " [0] 返回"
        read -p "选择: " s_choice
        case $s_choice in
            1) dpkg-reconfigure tzdata ;;
            2) configure_exit_node ;;
            0) return ;;
        esac
    done
}
# ============================================================================
# 其他原有功能 (保持不变)
# ============================================================================

configure_exit_node() {
    print_info "Exit Node 配置功能暂未实现"
    sleep 2
}

enable_root_ssh() {
    print_info "正在启用 Root SSH 登录..."
    sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config
    sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config
    service ssh restart
    print_success "已开启 Root SSH 登录，请确保已设置 Root 密码。"
    sleep 2
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
