#!/bin/bash

################################################################################
# 文件名: tools.sh
# 版本: v2.0.0
# 功能: Ubuntu Server 运维工具箱 (云端共享版)
# 安装位置: /usr/local/bin/t
# 作者: Auto Generated
# 日期: 2025-11-15
#
# GitHub: https://github.com/chf5762-sudo/bash
# Raw链接: https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/tools.sh
#
# 一键安装命令:
# curl -fsSL https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/tools.sh -o tools.sh && chmod +x tools.sh && sudo ./tools.sh
#
# 安装后使用:
#   t              # 打开主菜单
#   t A            # 执行扩展程序 A
#   t --help       # 查看帮助
################################################################################

# ============================================================================
# 全局变量
# ============================================================================
VERSION="2.0.0"
SCRIPT_PATH="$(readlink -f "$0")"
INSTALL_PATH="/usr/local/bin/t"
CONFIG_DIR="/etc/tools"
LOG_DIR="/var/log/tools"
CACHE_FILE="$CONFIG_DIR/cloud_cache.json"
LOCAL_DATA="$CONFIG_DIR/local.json"

# 固定的 Gist 配置
GIST_TOKEN="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"
GIST_ID="5056809fae3422c02fd8b52ad31f8fca"
GIST_FILE="share_ssh.json"

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
  "caddy_routes": [],
  "local_scripts": []
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
    
    # 提取文件内容
    local content=$(echo "$response" | grep -A 999999 "\"$GIST_FILE\"" | grep '"content":' | head -1 | sed 's/.*"content": "//; s/".*//' | sed 's/\\n/\n/g' | sed 's/\\"/"/g')
    
    if [[ -z "$content" ]]; then
        [[ "$silent" != "silent" ]] && print_error "云端数据为空，初始化中..."
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
  "version": "2.0.0",
  "last_update": "",
  "last_sync_host": "",
  "scripts": [],
  "commands": [],
  "extensions": []
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
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║          Tools v${VERSION} - 云端共享运维工具箱            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
    
    local current_time=$(date '+%Y-%m-%d %H:%M:%S %Z')
    echo -e "${CYAN}⏰ 时间:${NC} $current_time"
    
    local timezone=$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}' || cat /etc/timezone 2>/dev/null || echo "Unknown")
    echo -e "${CYAN}🌍 时区:${NC} $timezone"
    
    if [[ -f /etc/os-release ]]; then
        local os_name=$(grep "^PRETTY_NAME" /etc/os-release | cut -d'"' -f2)
        echo -e "${CYAN}💻 系统:${NC} $os_name"
    fi
    
    local arch=$(uname -m)
    echo -e "${CYAN}🔧 架构:${NC} $arch"
    
    local cpu_cores=$(nproc)
    echo -e "${CYAN}⚙️  CPU:${NC} ${cpu_cores} 核"
    
    local mem_total=$(free -h | awk '/^Mem:/ {print $2}')
    local mem_used=$(free -h | awk '/^Mem:/ {print $3}')
    echo -e "${CYAN}💾 内存:${NC} ${mem_used} / ${mem_total}"
    
    local disk_info=$(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')
    echo -e "${CYAN}💿 磁盘:${NC} $disk_info"
    
    echo -ne "${CYAN}🌐 IPv4:${NC} "
    local ipv4=$(curl -s -4 --max-time 2 https://api.ipify.org 2>/dev/null || echo "获取失败")
    echo "$ipv4"
    
    echo ""
    echo "════════════════════════════════════════════════════════════"
}

# ============================================================================
# 主菜单
# ============================================================================

main_menu() {
    # 启动时同步
    sync_from_cloud silent
    
    while true; do
        show_system_info
        
        # 读取扩展程序
        local extensions=()
        if [[ -f "$CACHE_FILE" ]]; then
            local ext_count=$(jq '.extensions | length' "$CACHE_FILE" 2>/dev/null || echo "0")
            for ((i=0; i<ext_count; i++)); do
                local name=$(jq -r ".extensions[$i].name" "$CACHE_FILE" 2>/dev/null)
                local shortcut=$(jq -r ".extensions[$i].shortcut" "$CACHE_FILE" 2>/dev/null)
                extensions+=("[$shortcut] $name")
            done
        fi
        
        echo "╔════════════════════════════════════════════════════════════════════╗"
        echo "║  快捷操作              │  扩展程序 (云端共享)                       ║"
        echo "║  [T] 📝 粘贴并执行     │  [C] 管理扩展程序                         ║"
        echo "╠════════════════════════════════════════════════════════════════════╣"
        echo "║  远程脚本          │  常用命令          │  二进制服务              ║"
        echo "║  [1] 脚本收藏      │  [4] 命令收藏      │  [7] 注册服务           ║"
        echo "║  [2] 脚本历史      │  [5] 命令历史      │  [8] 管理服务           ║"
        echo "║  [3] 定时任务      │  [6] 查看定时      │                         ║"
        echo "╠════════════════════════════════════════════════════════════════════╣"
        echo "║  Caddy 反代        │  环境安装          │  网络工具                ║"
        echo "║  [10] 安装Caddy    │  [14] Docker       │  [17] Tailscale         ║"
        echo "║  [11] 添加路由     │  [15] Compose      │  [18] Exit Node         ║"
        echo "║  [12] 管理路由     │  [16] 防火墙       │  [19] 1Panel            ║"
        echo "╠════════════════════════════════════════════════════════════════════╣"
        echo "║  系统配置          │  云同步            │  其他                    ║"
        echo "║  [20] 调整时区     │  [22] 手动同步     │  [0] 退出               ║"
        echo "║  [21] Root SSH     │  [23] 查看云端     │                         ║"
        echo "╠════════════════════════════════════════════════════════════════════╣"
        
        # 显示扩展程序（每行5个）
        if [[ ${#extensions[@]} -gt 0 ]]; then
            echo -n "║  🚀 扩展快捷: "
            local count=0
            for ext in "${extensions[@]}"; do
                echo -n "$ext  "
                ((count++))
                if [[ $count -eq 5 ]]; then
                    echo "║"
                    echo -n "║                "
                    count=0
                fi
            done
            if [[ $count -gt 0 ]]; then
                # 填充剩余空间
                local padding=$((5 - count))
                for ((i=0; i<padding; i++)); do
                    echo -n "            "
                done
                echo "║"
            fi
        else
            echo "║  🚀 扩展快捷: 暂无扩展程序，按 C 添加                              ║"
        fi
        
        echo "╚════════════════════════════════════════════════════════════════════╝"
        echo ""
        read -p "请选择: " choice
        
        # 处理扩展程序快捷键
        if [[ "$choice" =~ ^[A-Z]$ ]]; then
            execute_extension "$choice"
            continue
        fi
        
        case $choice in
            [Tt]) run_script_from_paste ;;
            [Cc]) manage_extensions ;;
            1) script_collection ;;
            2) script_history ;;
            3) cron_management ;;
            4) command_collection ;;
            5) command_history ;;
            6) view_cron_jobs ;;
            7) register_binary_service ;;
            8) manage_services ;;
            10) install_caddy ;;
            11) add_caddy_route ;;
            12) manage_caddy_routes ;;
            14) install_docker ;;
            15) install_docker_compose ;;
            16) firewall_management ;;
            17) install_tailscale ;;
            18) configure_exit_node ;;
            19) install_1panel ;;
            20) change_timezone ;;
            21) enable_root_ssh ;;
            22) manual_sync ;;
            23) view_cloud_data ;;
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
# 扩展程序管理
# ============================================================================

manage_extensions() {
    while true; do
        clear
        echo "╔════════════════════════════════════════╗"
        echo "║        扩展程序管理 (云端共享)          ║"
        echo "╚════════════════════════════════════════╝"
        echo ""
        
        sync_from_cloud silent
        
        if [[ ! -f "$CACHE_FILE" ]]; then
            print_error "云端数据加载失败"
            sleep 2
            return
        fi
        
        local ext_count=$(jq '.extensions | length' "$CACHE_FILE" 2>/dev/null || echo "0")
        
        if [[ $ext_count -eq 0 ]]; then
            print_warning "暂无扩展程序"
            echo ""
            echo "[1] 添加扩展程序"
            echo "[0] 返回"
            read -p "选择: " choice
            
            case $choice in
                1) add_extension ;;
                0) return ;;
            esac
            continue
        fi
        
        echo "当前扩展程序:"
        echo ""
        for ((i=0; i<ext_count; i++)); do
            local name=$(jq -r ".extensions[$i].name" "$CACHE_FILE")
            local shortcut=$(jq -r ".extensions[$i].shortcut" "$CACHE_FILE")
            local desc=$(jq -r ".extensions[$i].description" "$CACHE_FILE")
            local type=$(jq -r ".extensions[$i].type" "$CACHE_FILE")
            
            echo "[$shortcut] ${CYAN}$name${NC}"
            echo "    描述: $desc"
            echo "    类型: $type"
            echo ""
        done
        
        echo "[1] 添加扩展"
        echo "[2] 删除扩展"
        echo "[3] 测试扩展"
        echo "[0] 返回"
        echo ""
        read -p "选择: " choice
        
        case $choice in
            1) add_extension ;;
            2) delete_extension ;;
            3) test_extension ;;
            0) return ;;
        esac
    done
}

add_extension() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║        添加扩展程序                     ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    read -p "扩展名称: " name
    if [[ -z "$name" ]]; then
        print_error "名称不能为空"
        sleep 2
        return
    fi
    
    read -p "描述: " description
    
    echo ""
    echo "类型:"
    echo "[1] 命令"
    echo "[2] 脚本 URL"
    read -p "选择 [1]: " type_choice
    type_choice=${type_choice:-1}
    
    local type=""
    local content=""
    
    case $type_choice in
        1)
            type="command"
            read -p "命令内容: " content
            ;;
        2)
            type="script"
            read -p "脚本 URL: " content
            ;;
        *)
            print_error "无效选择"
            sleep 2
            return
            ;;
    esac
    
    if [[ -z "$content" ]]; then
        print_error "内容不能为空"
        sleep 2
        return
    fi
    
    # 自动分配快捷键
    local ext_count=$(jq '.extensions | length' "$CACHE_FILE" 2>/dev/null || echo "0")
    local shortcut=$(printf "\\$(printf '%03o' $((65 + ext_count)))")  # A=65
    
    if [[ $ext_count -ge 26 ]]; then
        print_error "扩展程序已达上限 (26个)"
        sleep 2
        return
    fi
    
    # 添加到云端数据
    local new_ext=$(cat <<EOF
{
  "id": "ext_$(date +%s)",
  "name": "$name",
  "shortcut": "$shortcut",
  "description": "$description",
  "type": "$type",
  "content": "$content",
  "added_by": "$(hostname)",
  "added_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)
    
    local updated=$(jq ".extensions += [$new_ext]" "$CACHE_FILE")
    echo "$updated" > "$CACHE_FILE"
    
    # 更新时间戳
    local with_timestamp=$(jq ".last_update = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\" | .last_sync_host = \"$(hostname)\"" "$CACHE_FILE")
    echo "$with_timestamp" > "$CACHE_FILE"
    
    if sync_to_cloud; then
        print_success "扩展程序已添加: [$shortcut] $name"
        log_action "Add extension: $name"
    else
        print_error "同步失败"
    fi
    
    sleep 2
}

delete_extension() {
    echo ""
    read -p "输入要删除的快捷键 (A-Z): " shortcut
    shortcut=$(echo "$shortcut" | tr '[:lower:]' '[:upper:]')
    
    if [[ ! "$shortcut" =~ ^[A-Z]$ ]]; then
        print_error "无效快捷键"
        sleep 2
        return
    fi
    
    # 查找并删除
    local name=$(jq -r ".extensions[] | select(.shortcut == \"$shortcut\") | .name" "$CACHE_FILE" 2>/dev/null)
    
    if [[ -z "$name" ]]; then
        print_error "未找到扩展程序"
        sleep 2
        return
    fi
    
    read -p "确认删除 '$name'? [y/N] " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        return
    fi
    
    local updated=$(jq "del(.extensions[] | select(.shortcut == \"$shortcut\"))" "$CACHE_FILE")
    echo "$updated" > "$CACHE_FILE"
    
    # 重新分配快捷键
    local reassigned=$(jq '.extensions | to_entries | map(.value + {shortcut: (65 + .key | [.] | implode)}) | {version: "2.0.0", last_update: "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'", last_sync_host: "'$(hostname)'", scripts: [], commands: [], extensions: .}' "$CACHE_FILE")
    
    # 保留原有 scripts 和 commands
    local scripts=$(jq '.scripts' "$CACHE_FILE")
    local commands=$(jq '.commands' "$CACHE_FILE")
    reassigned=$(echo "$reassigned" | jq ".scripts = $scripts | .commands = $commands")
    
    echo "$reassigned" > "$CACHE_FILE"
    
    if sync_to_cloud; then
        print_success "扩展程序已删除"
        log_action "Delete extension: $name"
    else
        print_error "同步失败"
    fi
    
    sleep 2
}

execute_extension() {
    local shortcut="$1"
    
    sync_from_cloud silent
    
    local ext=$(jq -r ".extensions[] | select(.shortcut == \"$shortcut\")" "$CACHE_FILE" 2>/dev/null)
    
    if [[ -z "$ext" ]]; then
        print_error "未找到扩展程序: $shortcut"
        sleep 2
        return
    fi
    
    local name=$(echo "$ext" | jq -r '.name')
    local type=$(echo "$ext" | jq -r '.type')
    local content=$(echo "$ext" | jq -r '.content')
    
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║  执行扩展: $name"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    case $type in
        command)
            print_info "执行命令: $content"
            echo ""
            eval "$content"
            ;;
        script)
            print_info "执行脚本: $content"
            echo ""
            local temp_script="/tmp/ext-script-$RANDOM.sh"
            if curl -fsSL -o "$temp_script" "$content" 2>/dev/null; then
                chmod +x "$temp_script"
                bash "$temp_script"
                rm -f "$temp_script"
            else
                print_error "脚本下载失败"
            fi
            ;;
    esac
    
    echo ""
    read -p "按回车继续..."
}

test_extension() {
    echo ""
    read -p "输入要测试的快捷键 (A-Z): " shortcut
    execute_extension "$(echo "$shortcut" | tr '[:lower:]' '[:upper:]')"
}

# ============================================================================
# 脚本管理
# ============================================================================

run_script_from_paste() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║        粘贴脚本内容                     ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    print_info "请粘贴脚本内容 (结束后按 Ctrl+D):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
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
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "脚本预览 (前15行):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    head -n 15 "$temp_script"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    echo "[1] 立即执行"
    echo "[2] 执行并收藏"
    echo "[0] 取消"
    echo ""
    read -p "选择: " action
    
    case $action in
        1)
            execute_pasted_script "$temp_script"
            ;;
        2)
            execute_pasted_script "$temp_script"
            echo ""
            save_pasted_script "$temp_script"
            ;;
        0)
            rm -f "$temp_script"
            return
            ;;
    esac
    
    rm -f "$temp_script"
}

execute_pasted_script() {
    local script_file="$1"
    
    echo ""
    read -p "是否需要传递参数? [留空直接执行]: " params
    
    chmod +x "$script_file"
    
    echo ""
    print_info "开始执行..."
    echo "════════════════════════════════════"
    
    local start_time=$(date +%s)
    
    if [[ -n "$params" ]]; then
        bash "$script_file" $params
    else
        bash "$script_file"
    fi
    
    local exit_code=$?
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "════════════════════════════════════"
    
    if [[ $exit_code -eq 0 ]]; then
        print_success "执行完成！(耗时: ${duration}秒)"
    else
        print_error "执行失败！(退出码: $exit_code)"
    fi
    
    log_action "Execute pasted script (exit: $exit_code, duration: ${duration}s)"
    
    echo ""
    read -p "按回车继续..."
}

save_pasted_script() {
    local script_file="$1"
    
    echo ""
    read -p "脚本别名: " alias
    if [[ -z "$alias" ]]; then
        print_error "别名不能为空"
        sleep 2
        return
    fi
    
    read -p "描述 (可选): " description
    
    # Base64 编码脚本内容
    local content_base64=$(base64 -w 0 "$script_file" 2>/dev/null || base64 "$script_file" 2>/dev/null)
    
    # 添加到云端数据
    local new_script=$(cat <<EOF
{
  "id": "script_$(date +%s)",
  "alias": "$alias",
  "type": "paste",
  "source": "pasted",
  "content": "$content_base64",
  "description": "$description",
  "added_by": "$(hostname)",
  "added_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)
    
    sync_from_cloud silent
    
    local updated=$(jq ".scripts += [$new_script]" "$CACHE_FILE")
    echo "$updated" > "$CACHE_FILE"
    
    # 更新时间戳
    local with_timestamp=$(jq ".last_update = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\" | .last_sync_host = \"$(hostname)\"" "$CACHE_FILE")
    echo "$with_timestamp" > "$CACHE_FILE"
    
    if sync_to_cloud; then
        print_success "脚本已保存到云端收藏"
        log_action "Save pasted script: $alias"
    else
        print_error "同步失败"
    fi
    
    sleep 2
}

script_collection() {
    while true; do
        clear
        echo "╔════════════════════════════════════════╗"
        echo "║        脚本收藏夹 (云端共享)            ║"
        echo "╚════════════════════════════════════════╝"
        echo ""
        
        sync_from_cloud silent
        
        if [[ ! -f "$CACHE_FILE" ]]; then
            print_error "云端数据加载失败"
            sleep 2
            return
        fi
        
        local script_count=$(jq '.scripts | length' "$CACHE_FILE" 2>/dev/null || echo "0")
        
        if [[ $script_count -eq 0 ]]; then
            print_warning "暂无收藏的脚本"
            echo ""
            echo "[1] 添加脚本 URL"
            echo "[0] 返回"
            read -p "选择: " choice
            
            case $choice in
                1) add_script_url ;;
                0) return ;;
            esac
            continue
        fi
        
        echo "当前收藏的脚本:"
        echo ""
        for ((i=0; i<script_count; i++)); do
            local alias=$(jq -r ".scripts[$i].alias" "$CACHE_FILE")
            local type=$(jq -r ".scripts[$i].type" "$CACHE_FILE")
            local source=$(jq -r ".scripts[$i].source" "$CACHE_FILE")
            local desc=$(jq -r ".scripts[$i].description" "$CACHE_FILE")
            local added_by=$(jq -r ".scripts[$i].added_by" "$CACHE_FILE")
            
            echo "[$((i+1))] ${CYAN}$alias${NC} ($type)"
            [[ -n "$desc" && "$desc" != "null" ]] && echo "    描述: $desc"
            [[ "$type" == "url" ]] && echo "    URL: $source"
            echo "    来源: $added_by"
            echo ""
        done
        
        echo "[A] 添加脚本 URL"
        echo "[D] 删除脚本"
        echo "[0] 返回"
        echo ""
        read -p "选择 (输入编号执行): " choice
        
        case $choice in
            [Aa]) add_script_url ;;
            [Dd]) delete_script ;;
            0) return ;;
            [0-9]*)
                if [[ $choice -ge 1 && $choice -le $script_count ]]; then
                    execute_cloud_script $((choice - 1))
                else
                    print_error "无效编号"
                    sleep 1
                fi
                ;;
        esac
    done
}

add_script_url() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║        添加脚本 URL                     ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    read -p "脚本 URL: " url
    if [[ -z "$url" ]]; then
        print_error "URL 不能为空"
        sleep 2
        return
    fi
    
    read -p "脚本别名: " alias
    if [[ -z "$alias" ]]; then
        print_error "别名不能为空"
        sleep 2
        return
    fi
    
    read -p "描述 (可选): " description
    
    # 添加到云端数据
    local new_script=$(cat <<EOF
{
  "id": "script_$(date +%s)",
  "alias": "$alias",
  "type": "url",
  "source": "$url",
  "content": null,
  "description": "$description",
  "added_by": "$(hostname)",
  "added_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)
    
    sync_from_cloud silent
    
    local updated=$(jq ".scripts += [$new_script]" "$CACHE_FILE")
    echo "$updated" > "$CACHE_FILE"
    
    local with_timestamp=$(jq ".last_update = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\" | .last_sync_host = \"$(hostname)\"" "$CACHE_FILE")
    echo "$with_timestamp" > "$CACHE_FILE"
    
    if sync_to_cloud; then
        print_success "脚本已添加到云端收藏"
        log_action "Add script URL: $alias"
    else
        print_error "同步失败"
    fi
    
    sleep 2
}

execute_cloud_script() {
    local index=$1
    
    local type=$(jq -r ".scripts[$index].type" "$CACHE_FILE")
    local alias=$(jq -r ".scripts[$index].alias" "$CACHE_FILE")
    
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║  执行脚本: $alias"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    local temp_script="/tmp/cloud-script-$RANDOM.sh"
    
    case $type in
        url)
            local source=$(jq -r ".scripts[$index].source" "$CACHE_FILE")
            print_info "正在下载脚本..."
            
            if curl -fsSL -o "$temp_script" "$source" 2>/dev/null; then
                print_success "下载完成"
            else
                print_error "下载失败"
                rm -f "$temp_script"
                sleep 2
                return
            fi
            ;;
        paste)
            local content_base64=$(jq -r ".scripts[$index].content" "$CACHE_FILE")
            print_info "正在解码脚本..."
            
            echo "$content_base64" | base64 -d > "$temp_script" 2>/dev/null
            if [[ ! -s "$temp_script" ]]; then
                print_error "解码失败"
                rm -f "$temp_script"
                sleep 2
                return
            fi
            print_success "解码完成"
            ;;
    esac
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "脚本预览 (前15行):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    head -n 15 "$temp_script"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    read -p "是否执行? [Y/n] " confirm
    confirm=${confirm:-Y}
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        read -p "传递参数 (可选): " params
        
        chmod +x "$temp_script"
        
        echo ""
        print_info "开始执行..."
        echo "════════════════════════════════════"
        
        local start_time=$(date +%s)
        
        if [[ -n "$params" ]]; then
            bash "$temp_script" $params
        else
            bash "$temp_script"
        fi
        
        local exit_code=$?
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        echo "════════════════════════════════════"
        
        if [[ $exit_code -eq 0 ]]; then
            print_success "执行完成！(耗时: ${duration}秒)"
        else
            print_error "执行失败！(退出码: $exit_code)"
        fi
        
        log_action "Execute cloud script: $alias (exit: $exit_code)"
    fi
    
    rm -f "$temp_script"
    
    echo ""
    read -p "按回车继续..."
}

delete_script() {
    echo ""
    read -p "输入要删除的脚本编号: " num
    
    local script_count=$(jq '.scripts | length' "$CACHE_FILE")
    
    if [[ $num -lt 1 || $num -gt $script_count ]]; then
        print_error "无效编号"
        sleep 2
        return
    fi
    
    local index=$((num - 1))
    local alias=$(jq -r ".scripts[$index].alias" "$CACHE_FILE")
    
    read -p "确认删除 '$alias'? [y/N] " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        return
    fi
    
    local updated=$(jq "del(.scripts[$index])" "$CACHE_FILE")
    echo "$updated" > "$CACHE_FILE"
    
    local with_timestamp=$(jq ".last_update = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\" | .last_sync_host = \"$(hostname)\"" "$CACHE_FILE")
    echo "$with_timestamp" > "$CACHE_FILE"
    
    if sync_to_cloud; then
        print_success "脚本已删除"
        log_action "Delete script: $alias"
    else
        print_error "同步失败"
    fi
    
    sleep 2
}

script_history() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║        脚本执行历史                     ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    if [[ ! -f "$LOG_DIR/tools.log" ]]; then
        print_warning "暂无执行历史"
    else
        echo "最近执行记录:"
        echo ""
        grep "Execute" "$LOG_DIR/tools.log" | tail -n 20
    fi
    
    echo ""
    read -p "按回车继续..."
}

# ============================================================================
# 命令管理
# ============================================================================

command_collection() {
    while true; do
        clear
        echo "╔════════════════════════════════════════╗"
        echo "║        常用命令收藏 (云端共享)          ║"
        echo "╚════════════════════════════════════════╝"
        echo ""
        
        sync_from_cloud silent
        
        if [[ ! -f "$CACHE_FILE" ]]; then
            print_error "云端数据加载失败"
            sleep 2
            return
        fi
        
        local cmd_count=$(jq '.commands | length' "$CACHE_FILE" 2>/dev/null || echo "0")
        
        if [[ $cmd_count -eq 0 ]]; then
            print_warning "暂无收藏的命令"
            echo ""
            echo "[1] 添加命令"
            echo "[0] 返回"
            read -p "选择: " choice
            
            case $choice in
                1) add_command ;;
                0) return ;;
            esac
            continue
        fi
        
        echo "╔════╦═══════════════════╦═══════════════════════════════╗"
        echo "║ #  ║ 别名              ║ 命令                          ║"
        echo "╠════╬═══════════════════╬═══════════════════════════════╣"
        
        for ((i=0; i<cmd_count; i++)); do
            local alias=$(jq -r ".commands[$i].alias" "$CACHE_FILE")
            local cmd=$(jq -r ".commands[$i].command" "$CACHE_FILE")
            local cmd_short="${cmd:0:29}"
            printf "║ %-2s ║ %-17s ║ %-29s ║\n" "$((i+1))" "$alias" "$cmd_short"
        done
        
        echo "╚════╩═══════════════════╩═══════════════════════════════╝"
        echo ""
        echo "[A] 添加命令"
        echo "[D] 删除命令"
        echo "[0] 返回"
        echo ""
        read -p "选择 (输入编号执行): " choice
        
        case $choice in
            [Aa]) add_command ;;
            [Dd]) delete_command ;;
            0) return ;;
            [0-9]*)
                if [[ $choice -ge 1 && $choice -le $cmd_count ]]; then
                    execute_cloud_command $((choice - 1))
                else
                    print_error "无效编号"
                    sleep 1
                fi
                ;;
        esac
    done
}

add_command() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║        添加常用命令                     ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    read -p "命令内容: " cmd
    if [[ -z "$cmd" ]]; then
        print_error "命令不能为空"
        sleep 2
        return
    fi
    
    read -p "命令别名: " alias
    if [[ -z "$alias" ]]; then
        print_error "别名不能为空"
        sleep 2
        return
    fi
    
    read -p "分类 [自定义]: " category
    category=${category:-"自定义"}
    
    # 添加到云端数据
    local new_cmd=$(cat <<EOF
{
  "id": "cmd_$(date +%s)",
  "alias": "$alias",
  "command": "$cmd",
  "category": "$category",
  "added_by": "$(hostname)",
  "added_time": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)
    
    sync_from_cloud silent
    
    local updated=$(jq ".commands += [$new_cmd]" "$CACHE_FILE")
    echo "$updated" > "$CACHE_FILE"
    
    local with_timestamp=$(jq ".last_update = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\" | .last_sync_host = \"$(hostname)\"" "$CACHE_FILE")
    echo "$with_timestamp" > "$CACHE_FILE"
    
    if sync_to_cloud; then
        print_success "命令已添加到云端收藏"
        log_action "Add command: $alias"
    else
        print_error "同步失败"
    fi
    
    sleep 2
}

execute_cloud_command() {
    local index=$1
    
    local alias=$(jq -r ".commands[$index].alias" "$CACHE_FILE")
    local cmd=$(jq -r ".commands[$index].command" "$CACHE_FILE")
    
    echo ""
    print_info "执行命令: $cmd"
    echo ""
    read -p "确认执行? [Y/n] " confirm
    confirm=${confirm:-Y}
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        echo ""
        local start_time=$(date +%s)
        eval "$cmd"
        local exit_code=$?
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        echo ""
        if [[ $exit_code -eq 0 ]]; then
            print_success "命令执行完成 (耗时: ${duration}秒)"
        else
            print_error "命令执行失败 (退出码: $exit_code)"
        fi
        
        log_action "Execute command: $alias ($cmd) - exit: $exit_code"
    fi
    
    echo ""
    read -p "按回车继续..."
}

delete_command() {
    echo ""
    read -p "输入要删除的命令编号: " num
    
    local cmd_count=$(jq '.commands | length' "$CACHE_FILE")
    
    if [[ $num -lt 1 || $num -gt $cmd_count ]]; then
        print_error "无效编号"
        sleep 2
        return
    fi
    
    local index=$((num - 1))
    local alias=$(jq -r ".commands[$index].alias" "$CACHE_FILE")
    
    read -p "确认删除 '$alias'? [y/N] " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        return
    fi
    
    local updated=$(jq "del(.commands[$index])" "$CACHE_FILE")
    echo "$updated" > "$CACHE_FILE"
    
    local with_timestamp=$(jq ".last_update = \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\" | .last_sync_host = \"$(hostname)\"" "$CACHE_FILE")
    echo "$with_timestamp" > "$CACHE_FILE"
    
    if sync_to_cloud; then
        print_success "命令已删除"
        log_action "Delete command: $alias"
    else
        print_error "同步失败"
    fi
    
    sleep 2
}

command_history() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║        命令执行历史                     ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    if [[ ! -f "$LOG_DIR/tools.log" ]]; then
        print_warning "暂无执行历史"
    else
        echo "最近执行记录:"
        echo ""
        grep "Execute command" "$LOG_DIR/tools.log" | tail -n 20
    fi
    
    echo ""
    read -p "按回车继续..."
}

# ============================================================================
# 定时任务管理
# ============================================================================

cron_management() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║        定时任务管理                     ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    echo "[1] 添加定时任务"
    echo "[2] 删除定时任务"
    echo "[3] 查看定时任务"
    echo "[0] 返回"
    echo ""
    read -p "选择: " choice
    
    case $choice in
        1) add_cron_job ;;
        2) delete_cron_job ;;
        3) view_cron_jobs ;;
        0) return ;;
    esac
}

add_cron_job() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║        添加定时任务                     ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    # 从命令收藏选择
    sync_from_cloud silent
    
    local cmd_count=$(jq '.commands | length' "$CACHE_FILE" 2>/dev/null || echo "0")
    
    if [[ $cmd_count -eq 0 ]]; then
        print_error "请先添加命令"
        sleep 2
        return
    fi
    
    print_info "选择要定时执行的命令:"
    echo ""
    
    for ((i=0; i<cmd_count; i++)); do
        local alias=$(jq -r ".commands[$i].alias" "$CACHE_FILE")
        local cmd=$(jq -r ".commands[$i].command" "$CACHE_FILE")
        echo "[$((i+1))] $alias - $cmd"
    done
    
    echo ""
    read -p "选择命令编号: " cmd_num
    
    if [[ $cmd_num -lt 1 || $cmd_num -gt $cmd_count ]]; then
        print_error "无效选择"
        sleep 2
        return
    fi
    
    local index=$((cmd_num - 1))
    local alias=$(jq -r ".commands[$index].alias" "$CACHE_FILE")
    local cmd=$(jq -r ".commands[$index].command" "$CACHE_FILE")
    
    echo ""
    echo "执行频率:"
    echo "[1] 每小时"
    echo "[2] 每天"
    echo "[3] 每周"
    echo "[4] 每月"
    echo "[5] 自定义 Cron"
    read -p "选择: " freq
    
    local cron_expr=""
    
    case $freq in
        1) cron_expr="0 * * * *" ;;
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
            read -p "输入 Cron 表达式: " cron_expr
            ;;
        *)
            print_error "无效选择"
            sleep 2
            return
            ;;
    esac
    
    check_root
    
    # 添加到 crontab
    (crontab -l 2>/dev/null; echo "$cron_expr $cmd # tools-$alias") | crontab -
    
    print_success "定时任务已添加"
    log_action "Add cron: $alias ($cron_expr)"
    
    sleep 2
}

delete_cron_job() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║        删除定时任务                     ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    # 显示所有 tools 创建的定时任务
    local cron_list=$(crontab -l 2>/dev/null | grep "# tools-")
    
    if [[ -z "$cron_list" ]]; then
        print_warning "暂无定时任务"
        sleep 2
        return
    fi
    
    echo "当前定时任务:"
    echo ""
    local index=1
    while IFS= read -r line; do
        echo "[$index] $line"
        ((index++))
    done <<< "$cron_list"
    
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

view_cron_jobs() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║        查看定时任务                     ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    local cron_list=$(crontab -l 2>/dev/null | grep "# tools-")
    
    if [[ -z "$cron_list" ]]; then
        print_warning "暂无定时任务"
    else
        echo "当前定时任务:"
        echo ""
        echo "$cron_list"
    fi
    
    echo ""
    read -p "按回车继续..."
}

# ============================================================================
# 二进制服务管理 (本地)
# ============================================================================

register_binary_service() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║    注册二进制程序为系统服务              ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    read -p "二进制程序目录: " bin_dir
    
    if [[ ! -d "$bin_dir" ]]; then
        print_error "目录不存在"
        sleep 2
        return
    fi
    
    print_info "正在扫描目录..."
    
    local binary=$(find "$bin_dir" -maxdepth 1 -type f -executable -exec ls -lh {} \; 2>/dev/null | sort -k5 -hr | head -n1 | awk '{print $NF}')
    
    if [[ -z "$binary" ]]; then
        print_error "未找到可执行文件"
        sleep 2
        return
    fi
    
    local binary_name=$(basename "$binary")
    print_success "检测到: $binary_name"
    
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
        local new_service=$(cat <<EOF
{
  "name": "$service_name",
  "binary": "$binary",
  "work_dir": "$work_dir"
}
EOF
)
        local updated=$(jq ".services += [$new_service]" "$LOCAL_DATA")
        echo "$updated" > "$LOCAL_DATA"
        
        log_action "Register service: $service_name"
    else
        print_error "服务启动失败"
    fi
    
    echo ""
    read -p "按回车继续..."
}

manage_services() {
    while true; do
        clear
        echo "╔════════════════════════════════════════╗"
        echo "║        已注册的服务                     ║"
        echo "╚════════════════════════════════════════╝"
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
        echo "[1] 启动服务"
        echo "[2] 停止服务"
        echo "[3] 重启服务"
        echo "[4] 查看状态"
        echo "[0] 返回"
        echo ""
        read -p "选择: " choice
        
        case $choice in
            1) service_action "start" ;;
            2) service_action "stop" ;;
            3) service_action "restart" ;;
            4) service_action "status" ;;
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
    
    if [[ "$action" == "status" ]]; then
        echo ""
        systemctl status "$name"
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

# ============================================================================
# Caddy 反向代理
# ============================================================================

install_caddy() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║        安装 Caddy 服务器                ║"
    echo "╚════════════════════════════════════════╝"
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
        sleep 3
        return
    fi
    
    # 配置 Caddy
    mkdir -p /etc/caddy
    
    cat > /etc/caddy/Caddyfile <<'EOF'
:8443 {
    respond / "Caddy is running on port 8443" 200
}
EOF

    systemctl restart caddy
    systemctl enable caddy
    
    print_success "Caddy 安装完成"
    log_action "Install Caddy"
    
    echo ""
    read -p "按回车继续..."
}

add_caddy_route() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║        添加 Caddy 反代路由              ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    if ! command -v caddy &> /dev/null; then
        print_error "请先安装 Caddy"
        sleep 2
        return
    fi
    
    read -p "路径前缀 (如 /app1): " path
    if [[ -z "$path" || ! "$path" =~ ^/ ]]; then
        print_error "路径必须以 / 开头"
        sleep 2
        return
    fi
    
    read -p "后端地址 (如 localhost:8080): " backend
    if [[ -z "$backend" ]]; then
        print_error "后端地址不能为空"
        sleep 2
        return
    fi
    
    check_root
    
    # 添加路由到 Caddyfile
    sed -i "/^:8443 {/a\\    route ${path}/* {\\n        uri strip_prefix ${path}\\n        reverse_proxy ${backend}\\n    }" /etc/caddy/Caddyfile
    
    if caddy reload --config /etc/caddy/Caddyfile 2>/dev/null; then
        print_success "路由添加成功"
        
        # 保存到本地数据
        local new_route=$(cat <<EOF
{
  "path": "$path",
  "backend": "$backend"
}
EOF
)
        local updated=$(jq ".caddy_routes += [$new_route]" "$LOCAL_DATA")
        echo "$updated" > "$LOCAL_DATA"
        
        log_action "Add Caddy route: $path -> $backend"
    else
        print_error "配置错误"
    fi
    
    echo ""
    read -p "按回车继续..."
}

manage_caddy_routes() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║        Caddy 路由管理                   ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    local route_count=$(jq '.caddy_routes | length' "$LOCAL_DATA" 2>/dev/null || echo "0")
    
    if [[ $route_count -eq 0 ]]; then
        print_warning "暂无路由配置"
    else
        for ((i=0; i<route_count; i++)); do
            local path=$(jq -r ".caddy_routes[$i].path" "$LOCAL_DATA")
            local backend=$(jq -r ".caddy_routes[$i].backend" "$LOCAL_DATA")
            echo "[$((i+1))] $path -> $backend"
        done
    fi
    
    echo ""
    read -p "按回车继续..."
}

# ============================================================================
# 环境安装
# ============================================================================

install_docker() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║        安装 Docker                      ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    if command -v docker &> /dev/null; then
        print_warning "Docker 已安装"
        docker --version
        echo ""
        read -p "按回车继续..."
        return
    fi
    
    check_root
    print_info "正在安装 Docker..."
    
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sh /tmp/get-docker.sh
    rm -f /tmp/get-docker.sh
    
    systemctl start docker
    systemctl enable docker
    
    if command -v docker &> /dev/null; then
        print_success "Docker 安装成功"
        log_action "Install Docker"
    else
        print_error "安装失败"
    fi
    
    echo ""
    read -p "按回车继续..."
}

install_docker_compose() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║        安装 Docker Compose              ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    if docker compose version &> /dev/null; then
        print_warning "Docker Compose 已安装"
        docker compose version
        echo ""
        read -p "按回车继续..."
        return
    fi
    
    check_root
    print_info "正在安装 Docker Compose..."
    
    apt-get update
    apt-get install -y docker-compose-plugin
    
    if docker compose version &> /dev/null; then
        print_success "Docker Compose 安装成功"
        log_action "Install Docker Compose"
    else
        print_error "安装失败"
    fi
    
    echo ""
    read -p "按回车继续..."
}

firewall_management() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║        防火墙管理                       ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    echo "[1] 关闭防火墙"
    echo "[2] 开启防火墙"
    echo "[0] 返回"
    echo ""
    read -p "选择: " choice
    
    check_root
    
    case $choice in
        1)
            if command -v ufw &> /dev/null; then
                ufw disable
            fi
            if systemctl is-active --quiet firewalld; then
                systemctl stop firewalld
                systemctl disable firewalld
            fi
            print_success "防火墙已关闭"
            log_action "Disable firewall"
            ;;
        2)
            if ! command -v ufw &> /dev/null; then
                apt-get install -y ufw
            fi
            ufw --force enable
            print_success "防火墙已开启"
            log_action "Enable firewall"
            ;;
    esac
    
    sleep 2
}

install_tailscale() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║        安装 Tailscale                   ║"
    echo "╚════════════════════════════════════════╝"
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
    echo "╔════════════════════════════════════════╗"
    echo "║        配置 Exit Node                   ║"
    echo "╚════════════════════════════════════════╝"
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
    echo "╔════════════════════════════════════════╗"
    echo "║        安装 1Panel                      ║"
    echo "╚════════════════════════════════════════╝"
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
    echo "╔════════════════════════════════════════╗"
    echo "║        时区设置                         ║"
    echo "╚════════════════════════════════════════╝"
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
    echo "╔════════════════════════════════════════╗"
    echo "║        启用 Root SSH                    ║"
    echo "╚════════════════════════════════════════╝"
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
# 云同步管理
# ============================================================================

manual_sync() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║        手动同步                         ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    echo "[1] 从云端拉取"
    echo "[2] 推送到云端"
    echo "[0] 返回"
    echo ""
    read -p "选择: " choice
    
    case $choice in
        1) sync_from_cloud ;;
        2) sync_to_cloud ;;
    esac
    
    echo ""
    read -p "按回车继续..."
}

view_cloud_data() {
    clear
    echo "╔════════════════════════════════════════╗"
    echo "║        云端数据                         ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    sync_from_cloud silent
    
    if [[ -f "$CACHE_FILE" ]]; then
        local last_update=$(jq -r '.last_update' "$CACHE_FILE")
        local last_host=$(jq -r '.last_sync_host' "$CACHE_FILE")
        local script_count=$(jq '.scripts | length' "$CACHE_FILE")
        local cmd_count=$(jq '.commands | length' "$CACHE_FILE")
        local ext_count=$(jq '.extensions | length' "$CACHE_FILE")
        
        echo "最后更新: $last_update"
        echo "更新来源: $last_host"
        echo ""
        echo "脚本收藏: $script_count 个"
        echo "命令收藏: $cmd_count 个"
        echo "扩展程序: $ext_count 个"
        echo ""
        echo "Gist URL: https://gist.github.com/$GIST_ID"
    else
        print_error "云端数据加载失败"
    fi
    
    echo ""
    read -p "按回车继续..."
}

# ============================================================================
# 自安装功能
# ============================================================================

check_and_install() {
    if [[ "$SCRIPT_PATH" != "$INSTALL_PATH" ]]; then
        echo "╔════════════════════════════════════════╗"
        echo "║   Tools 工具箱首次运行                  ║"
        echo "╚════════════════════════════════════════╝"
        echo ""
        print_info "检测到脚本未安装"
        echo ""
        read -p "是否安装到系统? [Y/n] " choice
        choice=${choice:-Y}
        
        if [[ $choice =~ ^[Yy]$ ]]; then
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
            echo "Tools v$VERSION - 云端共享运维工具箱"
            echo ""
            echo "使用方法:"
            echo "  t              打开主菜单"
            echo "  t A            执行扩展程序 A"
            echo "  t --help       显示帮助"
            exit 0
            ;;
        [A-Z])
            init_config
            sync_from_cloud silent
            execute_extension "$1"
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