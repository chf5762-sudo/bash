#!/bin/bash

################################################################################
# 文件名: tools.sh
# 版本: v1.1.0 (patched)
# 功能: Ubuntu Server 运维工具箱
# 安装位置: /usr/local/bin/t
# 作者: Auto Generated (patched)
# 日期: 2025-11-15
##一键安装命令 (复制粘贴到 SSH):
# ┌─────────────────────────────────────────────────────────────────────┐
# │ curl -fsSL https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/tools.sh -o tools.sh && chmod +x tools.sh && sudo ./tools.sh │
# └─────────────────────────────────────────────────────────────────────┘
#
# 或使用 wget:
# ┌─────────────────────────────────────────────────────────────────────┐
# │ wget -O tools.sh https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/tools.sh && chmod +x tools.sh && sudo ./tools.sh │
# └─────────────────────────────────────────────────────────────────────┘
#
# GitHub: https://github.com/chf5762-sudo/bash
# Raw链接: https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/tools.sh
#
# 主要增强:
#  - 完整实现 Gist 同步（上传/下载/还原），使用 python3 做 JSON 编解码
#  - 支持将粘贴的脚本保存到收藏（本地 paste 文件），并可同步
#  - 提高对临时文件、JSON 转义、find/ls 解析等的稳定性
################################################################################

VERSION="1.1.0-patched"
SCRIPT_PATH="$(readlink -f "$0")"
INSTALL_PATH="/usr/local/bin/t"
CONFIG_DIR="/etc/tools"
LOG_DIR="/var/log/tools"
DATA_FILE="$CONFIG_DIR/data.json"
SYNC_CONFIG="$CONFIG_DIR/sync.conf"
CADDY_CONFIG="/etc/caddy/Caddyfile"
PASTES_DIR="$CONFIG_DIR/pastes"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }

# 检查是否为 root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此操作需要 root 权限"
        echo "请使用: sudo $0 $*"
        exit 1
    fi
}

# 初始化配置目录
init_config() {
    mkdir -p "$CONFIG_DIR" "$LOG_DIR" "$PASTES_DIR"

    # 初始化数据文件
    if [[ ! -f "$DATA_FILE" ]]; then
        cat > "$DATA_FILE" <<'EOF'
{
  "scripts": [],
  "commands": [],
  "services": [],
  "caddy_routes": [],
  "cron_jobs": [],
  "extensions": []
}
EOF
    fi

    # 初始化列表文件
    touch "$CONFIG_DIR/scripts.list"
    touch "$CONFIG_DIR/commands.list"
    touch "$CONFIG_DIR/services.list"
    touch "$CONFIG_DIR/cron.list"
    touch "$CONFIG_DIR/extensions.list"
    touch "$CONFIG_DIR/script_history.log"
    touch "$CONFIG_DIR/command_history.log"
    touch "$CONFIG_DIR/caddy_routes.list"
}

# 记录日志
log_action() {
    local action="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $action" >> "$LOG_DIR/tools.log"
}

# 简化框线显示（避免乱码）
print_header() {
    local title="$1"
    echo "========================================"
    printf "  %s\n" "$title"
    echo "========================================"
}

show_system_info() {
    clear
    print_header "Tools v${VERSION} - 服务器运维工具箱"
    echo ""

    local current_time=$(date '+%Y-%m-%d %H:%M:%S %Z')
    echo -e "${CYAN}⏰ 当前时间:${NC} $current_time"

    local timezone=$(timedatectl 2>/dev/null | awk -F': ' '/Time zone/ {print $2}' || cat /etc/timezone 2>/dev/null || echo "Unknown")
    echo -e "${CYAN}🌍 时区:${NC} $timezone"

    if [[ -f /etc/os-release ]]; then
        local os_name=$(grep "^PRETTY_NAME" /etc/os-release | cut -d'"' -f2)
        echo -e "${CYAN}💻 系统:${NC} $os_name"
    fi

    local arch=$(uname -m)
    echo -e "${CYAN}🔧 架构:${NC} $arch"

    local cpu_model=$(grep -m1 "model name" /proc/cpuinfo | cut -d':' -f2 | xargs)
    local cpu_cores=$(nproc)
    echo -e "${CYAN}⚙️  CPU:${NC} $cpu_model (${cpu_cores} 核)"

    local mem_total=$(free -h | awk '/^Mem:/ {print $2}')
    local mem_used=$(free -h | awk '/^Mem:/ {print $3}')
    echo -e "${CYAN}💾 内存:${NC} ${mem_used} / ${mem_total}"

    local disk_info=$(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')
    echo -e "${CYAN}💿 磁盘:${NC} $disk_info"

    echo -ne "${CYAN}🌐 IPv4:${NC} "
    local ipv4=$(curl -s -4 https://api.ipify.org 2>/dev/null || curl -s -4 http://ifconfig.me 2>/dev/null || echo "获取失败")
    echo "$ipv4"

    echo -ne "${CYAN}🌐 IPv6:${NC} "
    local ipv6=$(curl -s -6 https://api64.ipify.org 2>/dev/null || curl -s -6 http://ifconfig.me 2>/dev/null || echo "未配置/获取失败")
    echo "$ipv6"

    echo ""
    echo "========================================"
}

# 自安装功能
check_and_install() {
    if [[ "$SCRIPT_PATH" != "$INSTALL_PATH" ]]; then
        print_header "Tools 工具箱首次运行"
        echo ""
        print_info "检测到脚本未安装到系统"
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
            echo "现在可以使用以下命令:"
            echo "  t              # 打开主菜单"
            echo "  t --help       # 查看帮助"
            echo ""
            exit 0
        else
            print_warning "已取消安装，使用临时模式运行"
            init_config
        fi
    fi
}

main_menu() {
    while true; do
        show_system_info

        echo "快捷操作:"
        echo "[T] 粘贴并执行脚本"
        echo ""
        echo "1) 运行远程脚本    2) 脚本收藏      3) 脚本历史"
        echo "4) 命令收藏        5) 命令历史      6) 定时任务"
        echo "7) 安装二进制      8) 注册服务      9) 管理服务"
        echo "10) 安装Caddy      11) 添加路由     12) 管理路由"
        echo "14) Docker         15) Compose      16) 防火墙"
        echo "17) Tailscale      18) Exit Node    19) 1Panel"
        echo "20) 调整时区       21) Root SSH      22) Gist同步"
        echo "23) 扩展脚本       0) 退出"
        echo ""

        # 扩展显示
        if [[ -f "$CONFIG_DIR/extensions.list" ]] && [[ -s "$CONFIG_DIR/extensions.list" ]]; then
            echo "扩展脚本："
            while IFS='|' read -r num name url desc added_time; do
                printf "  [%-3s] %s\n" "$num" "$name"
            done < "$CONFIG_DIR/extensions.list"
            echo ""
        fi

        read -p "请选择: " choice

        case $choice in
            [Tt]) run_script_from_paste ;;
            1) run_script_from_url_menu ;;
            2) script_collection ;;
            3) script_history ;;
            4) command_collection ;;
            5) command_history ;;
            6) cron_management ;;
            7) install_binary_service ;;
            8) register_binary_service ;;
            9) manage_services ;;
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
            21) enable_root_ssh_ultimate ;;
            22) setup_gist_sync ;;
            23) manage_extensions ;;
            0)
                echo ""
                print_info "感谢使用 Tools 工具箱！"
                exit 0
                ;;
            *)
                if [[ -f "$CONFIG_DIR/extensions.list" ]]; then
                    local ext_line=$(grep "^${choice}|" "$CONFIG_DIR/extensions.list")
                    if [[ -n "$ext_line" ]]; then
                        local ext_url=$(echo "$ext_line" | cut -d'|' -f3)
                        local ext_name=$(echo "$ext_line" | cut -d'|' -f2)
                        run_extension_script "$ext_url" "$ext_name"
                    else
                        print_error "无效选择"
                        sleep 1
                    fi
                else
                    print_error "无效选择"
                    sleep 1
                fi
                ;;
        esac
    done
}

change_timezone() {
    clear
    print_header "时区设置"
    echo ""
    local current_tz=$(timedatectl 2>/dev/null | awk -F': ' '/Time zone/ {print $2}' || cat /etc/timezone 2>/dev/null || echo "Unknown")
    echo -e "当前时区: ${CYAN}$current_tz${NC}"
    echo -e "当前时间: ${CYAN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo ""
    echo "常用时区:"
    echo "[1] Asia/Shanghai (中国标准时间 UTC+8)"
    echo "[2] America/New_York"
    echo "[3] America/Los_Angeles"
    echo "[4] Europe/London"
    echo "[5] Asia/Tokyo"
    echo "[6] Asia/Singapore"
    echo "[7] UTC"
    echo "[8] 自定义"
    echo "[0] 返回"
    echo ""
    read -p "选择: " choice
    local new_tz=""
    case $choice in
        1) new_tz="Asia/Shanghai" ;;
        2) new_tz="America/New_York" ;;
        3) new_tz="America/Los_Angeles" ;;
        4) new_tz="Europe/London" ;;
        5) new_tz="Asia/Tokyo" ;;
        6) new_tz="Asia/Singapore" ;;
        7) new_tz="UTC" ;;
        8)
            echo ""
            echo "可用时区列表: timedatectl list-timezones"
            read -p "输入时区 (如 Asia/Shanghai): " new_tz
            ;;
        0) return ;;
        *)
            print_error "无效选择"
            sleep 2
            return
            ;;
    esac

    if [[ -z "$new_tz" ]]; then
        print_error "时区不能为空"
        sleep 2
        return
    fi

    check_root

    echo ""
    print_info "正在设置时区为: $new_tz"

    if timedatectl set-timezone "$new_tz" 2>/dev/null; then
        print_success "时区设置成功"
        echo -e "新时区: ${GREEN}$new_tz${NC}"
        echo -e "新时间: ${GREEN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
        log_action "Change timezone to: $new_tz"
    else
        print_error "时区设置失败"
    fi

    echo ""
    read -p "按回车继续..."
}

# -------------------------
# 远程脚本管理（含粘贴保存）
# -------------------------

run_script_from_url_menu() {
    clear
    print_header "从 URL 运行脚本"
    echo ""
    read -p "请输入脚本 URL: " url

    if [[ -z "$url" ]]; then
        print_error "URL 不能为空"
        sleep 2
        return
    fi

    print_info "正在下载脚本..."

    local temp_script
    temp_script="$(mktemp /tmp/tools-script-XXXXXX.sh)"

    if curl -fsSL -o "$temp_script" "$url" 2>/dev/null || wget -q -O "$temp_script" "$url" 2>/dev/null; then
        local size
        size=$(stat -c%s "$temp_script" 2>/dev/null || stat -f%z "$temp_script" 2>/dev/null)
        print_success "下载完成 ($size bytes)"
        preview_and_execute_script "$temp_script" "$url"
        rm -f "$temp_script"
    else
        rm -f "$temp_script"
        print_error "下载失败，请检查 URL 是否正确"
        sleep 2
    fi
}

run_remote_script() {
    clear
    print_header "运行远程脚本"
    echo ""
    echo "请选择脚本来源:"
    echo "[1] URL 地址"
    echo "[2] 粘贴脚本内容"
    echo "[0] 返回"
    echo ""
    read -p "选择: " choice

    case $choice in
        1) run_script_from_url_menu ;;
        2) run_script_from_paste ;;
        0) return ;;
        *) print_error "无效选择"; sleep 1; run_remote_script ;;
    esac
}

run_script_from_url() { run_script_from_url_menu; }

run_script_from_paste() {
    clear
    print_header "粘贴脚本内容"
    echo ""
    print_info "请粘贴脚本内容 (结束后按 Ctrl+D):"
    echo "----------------------------------------"

    local temp_script
    temp_script="$(mktemp /tmp/tools-paste-XXXXXX.sh)"
    cat > "$temp_script"

    if [[ ! -s "$temp_script" ]]; then
        print_error "未检测到脚本内容"
        rm -f "$temp_script"
        sleep 2
        return
    fi

    echo ""
    print_success "脚本内容已接收"

    preview_and_execute_script "$temp_script" "pasted-content"
    rm -f "$temp_script"
}

preview_and_execute_script() {
    local script_file="$1"
    local source="$2"

    echo ""
    echo "----------------------------------------"
    echo "脚本预览 (前15行):"
    echo "----------------------------------------"
    head -n 15 "$script_file"
    echo "----------------------------------------"
    echo ""

    echo "[1] 立即执行"
    echo "[2] 保存到收藏"
    echo "[0] 取消"
    echo ""
    read -p "选择: " action

    case $action in
        1)
            execute_script "$script_file" "$source"
            # 运行后允许保存（粘贴或 URL）
            echo ""
            read -p "是否保存到收藏? [y/N] " save_choice
            if [[ $save_choice =~ ^[Yy]$ ]]; then
                save_script_to_collection "$source" "$script_file"
            fi
            ;;
        2)
            save_script_to_collection "$source" "$script_file"
            ;;
        0)
            return
            ;;
        *)
            print_error "无效选择"
            ;;
    esac
}

execute_script() {
    local script_file="$1"
    local source="$2"

    echo ""
    read -p "是否需要传递参数? [留空直接执行]: " params

    chmod +x "$script_file"

    echo ""
    print_info "开始执行..."
    echo "----------------------------------------"

    local start_time
    start_time=$(date +%s)

    if [[ -n "$params" ]]; then
        bash "$script_file" $params
    else
        bash "$script_file"
    fi

    local exit_code=$?
    local end_time
    end_time=$(date +%s)
    local duration
    duration=$((end_time - start_time))

    echo "----------------------------------------"

    if [[ $exit_code -eq 0 ]]; then
        print_success "执行完成！(耗时: ${duration}秒)"
    else
        print_error "执行失败！(退出码: $exit_code)"
    fi

    log_action "Execute script: $source (exit: $exit_code, duration: ${duration}s)"

    # 保存历史
    echo "$(date '+%Y-%m-%d %H:%M:%S')|$source|$exit_code|${duration}s" >> "$CONFIG_DIR/script_history.log"

    echo ""
    read -p "按回车继续..."
}

# 保存脚本收藏：支持 URL 或本地脚本文件（用于粘贴）
# 用法: save_script_to_collection <source_identifier> [script_file]
# - 如果 source_identifier 为 URL / file path -> 直接保存 url
# - 如果 source_identifier == pasted-content 并提供 script_file -> 保存为本地 paste 文件，记录为 paste:<filename>
save_script_to_collection() {
    local source="$1"
    local script_file="$2"

    echo ""
    read -p "脚本别名: " alias_name
    if [[ -z "$alias_name" ]]; then
        print_error "别名不能为空"
        sleep 1
        return
    fi
    read -p "描述 (可选): " description

    local record_url=""

    if [[ "$source" == "pasted-content" && -n "$script_file" ]]; then
        # 保存到本地 paste 文件
        local safe_name
        safe_name="$(echo "$alias_name" | tr ' /' '__')" || safe_name="$alias_name"
        local ts
        ts=$(date +%s)
        local paste_file="$PASTES_DIR/${safe_name}_${ts}.sh"
        cp "$script_file" "$paste_file"
        chmod 600 "$paste_file"
        record_url="paste:$(basename "$paste_file")"
        print_success "已保存本地粘贴为: $paste_file"
    else
        # source 可能为 URL 或本地 file path
        record_url="$source"
    fi

    echo "${alias_name}|${record_url}|${description}|$(date '+%Y-%m-%d %H:%M:%S')" >> "$CONFIG_DIR/scripts.list"

    print_success "已保存到收藏"
    log_action "Save script: $alias_name ($record_url)"

    # 触发云同步（如果配置）
    sync_to_gist &>/dev/null || true

    sleep 1
}

script_collection() {
    while true; do
        clear
        print_header "脚本收藏夹"

        if [[ ! -f "$CONFIG_DIR/scripts.list" ]] || [[ ! -s "$CONFIG_DIR/scripts.list" ]]; then
            print_warning "暂无收藏的脚本"
            echo ""
            echo "[0] 返回"
            read -p "选择: " choice
            return
        fi

        local index=1
        while IFS='|' read -r alias url desc added_time; do
            echo "[$index] ${CYAN}$alias${NC}"
            if [[ "$url" == paste:* ]]; then
                echo "    本地粘贴文件: ${url#paste:}"
            else
                echo "    URL: $url"
            fi
            [[ -n "$desc" ]] && echo "    描述: $desc"
            echo ""
            ((index++))
        done < "$CONFIG_DIR/scripts.list"

        echo "[D] 删除脚本"
        echo "[0] 返回"
        echo ""
        read -p "选择 (输入编号执行): " choice

        case $choice in
            [Dd]) delete_script_from_collection ;;
            0) return ;;
            [0-9]*)
                local line
                line=$(sed -n "${choice}p" "$CONFIG_DIR/scripts.list")
                if [[ -n "$line" ]]; then
                    local url
                    url=$(echo "$line" | cut -d'|' -f2)
                    if [[ "$url" == paste:* ]]; then
                        local pf="$PASTES_DIR/${url#paste:}"
                        if [[ -f "$pf" ]]; then
                            preview_and_execute_script "$pf" "$url"
                        else
                            print_error "本地粘贴文件不存在"
                            sleep 2
                        fi
                    else
                        run_script_from_url_direct "$url"
                    fi
                fi
                ;;
        esac
    done
}

run_script_from_url_direct() {
    local url="$1"
    local temp_script
    temp_script="$(mktemp /tmp/tools-script-XXXXXX.sh)"

    print_info "正在下载脚本..."

    if curl -fsSL -o "$temp_script" "$url" 2>/dev/null || wget -q -O "$temp_script" "$url" 2>/dev/null; then
        execute_script "$temp_script" "$url"
        rm -f "$temp_script"
    else
        rm -f "$temp_script"
        print_error "下载失败"
        sleep 2
    fi
}

delete_script_from_collection() {
    echo ""
    read -p "输入要删除的脚本编号: " num

    local line
    line=$(sed -n "${num}p" "$CONFIG_DIR/scripts.list")
    if [[ -z "$line" ]]; then
        print_error "无效编号"
        sleep 2
        return
    fi

    local alias
    alias=$(echo "$line" | cut -d'|' -f1)
    local url
    url=$(echo "$line" | cut -d'|' -f2)

    read -p "确认删除 '$alias'? [y/N] " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        sed -i "${num}d" "$CONFIG_DIR/scripts.list"
        # 如果是 paste 文件，也删除本地文件
        if [[ "$url" == paste:* ]]; then
            local pf="$PASTES_DIR/${url#paste:}"
            rm -f "$pf"
        fi
        print_success "已删除"
        log_action "Delete script: $alias"
        sync_to_gist &>/dev/null || true
    fi

    sleep 1
}

script_history() {
    clear
    print_header "脚本执行历史"

    if [[ ! -f "$CONFIG_DIR/script_history.log" ]] || [[ ! -s "$CONFIG_DIR/script_history.log" ]]; then
        print_warning "暂无执行历史"
    else
        echo "最近 20 条执行记录:"
        echo ""
        tail -n 20 "$CONFIG_DIR/script_history.log" | while IFS='|' read -r time source exit_code duration; do
            if [[ $exit_code -eq 0 ]]; then
                echo -e "${GREEN}✓${NC} $time - $source (${duration})"
            else
                echo -e "${RED}✗${NC} $time - $source (退出码: $exit_code, ${duration})"
            fi
        done
    fi

    echo ""
    read -p "按回车继续..."
}

# -------------------------
# 常用命令管理（不变）
# -------------------------
command_collection() {
    while true; do
        clear
        print_header "常用命令收藏"

        if [[ ! -f "$CONFIG_DIR/commands.list" ]] || [[ ! -s "$CONFIG_DIR/commands.list" ]]; then
            print_warning "暂无收藏的命令"
            echo ""
            echo "[1] 添加命令"
            echo "[0] 返回"
            read -p "选择: " choice

            case $choice in
                1) add_command_menu ;;
                0) return ;;
            esac
            continue
        fi

        echo "命令列表:"
        echo ""

        local index=1
        while IFS='|' read -r alias cmd type category; do
            printf "[%d] %s - %s\n" "$index" "$alias" "$cmd"
            ((index++))
        done < "$CONFIG_DIR/commands.list"

        echo ""
        echo "[A] 添加命令"
        echo "[D] 删除命令"
        echo "[T] 定时任务"
        echo "[0] 返回"
        echo ""
        read -p "选择 (输入编号执行): " choice

        case $choice in
            [Aa]) add_command_menu ;;
            [Dd]) delete_command ;;
            [Tt]) cron_management ;;
            0) return ;;
            [0-9]*)
                local line
                line=$(sed -n "${choice}p" "$CONFIG_DIR/commands.list")
                if [[ -n "$line" ]]; then
                    local cmd
                    cmd=$(echo "$line" | cut -d'|' -f2)
                    local alias
                    alias=$(echo "$line" | cut -d'|' -f1)
                    execute_command "$cmd" "$alias"
                fi
                ;;
        esac
    done
}

add_command_menu() {
    clear
    print_header "添加常用命令"
    echo ""
    echo "命令类型:"
    echo "[1] Docker 命令"
    echo "[2] 系统服务命令"
    echo "[3] 自定义命令"
    echo "[0] 返回"
    echo ""
    read -p "选择: " choice

    case $choice in
        1) add_docker_command ;;
        2) add_service_command ;;
        3) add_custom_command ;;
        0) return ;;
    esac
}

add_docker_command() {
    echo ""
    echo "Docker 操作:"
    echo "[1] 重启容器 (restart)"
    echo "[2] 停止容器 (stop)"
    echo "[3] 启动容器 (start)"
    echo "[4] 查看日志 (logs)"
    echo "[5] 查看容器 (ps)"
    read -p "选择: " op

    read -p "容器名称: " container
    read -p "命令别名: " alias

    local cmd=""
    case $op in
        1) cmd="docker restart $container" ;;
        2) cmd="docker stop $container" ;;
        3) cmd="docker start $container" ;;
        4) cmd="docker logs -f --tail 50 $container" ;;
        5) cmd="docker ps -a" ;;
    esac

    echo "$alias|$cmd|docker|Docker" >> "$CONFIG_DIR/commands.list"
    print_success "命令已保存"
    log_action "Add docker command: $alias"
    sync_to_gist &>/dev/null || true
    sleep 1
}

add_service_command() {
    echo ""
    echo "服务操作:"
    echo "[1] 启动服务 (start)"
    echo "[2] 停止服务 (stop)"
    echo "[3] 重启服务 (restart)"
    echo "[4] 查看状态 (status)"
    read -p "选择: " op

    read -p "服务名称: " service
    read -p "命令别名 [${op}-${service}]: " alias
    alias=${alias:-"${op}-${service}"}

    local cmd=""
    case $op in
        1) cmd="systemctl start $service" ;;
        2) cmd="systemctl stop $service" ;;
        3) cmd="systemctl restart $service" ;;
        4) cmd="systemctl status $service" ;;
    esac

    echo "$alias|$cmd|service|服务管理" >> "$CONFIG_DIR/commands.list"
    print_success "命令已保存"
    log_action "Add service command: $alias"
    sync_to_gist &>/dev/null || true
    sleep 1
}

add_custom_command() {
    echo ""
    read -p "命令内容: " cmd
    read -p "命令别名: " alias
    read -p "分类 [自定义]: " category
    category=${category:-"自定义"}

    echo "$alias|$cmd|custom|$category" >> "$CONFIG_DIR/commands.list"
    print_success "命令已保存"
    log_action "Add custom command: $alias"
    sync_to_gist &>/dev/null || true
    sleep 1
}

execute_command() {
    local cmd="$1"
    local alias="$2"

    echo ""
    print_info "执行命令: $cmd"
    echo ""
    read -p "确认执行? [Y/n] " confirm
    confirm=${confirm:-Y}

    if [[ $confirm =~ ^[Yy]$ ]]; then
        echo ""
        local start_time
        start_time=$(date +%s)
        eval "$cmd"
        local exit_code=$?
        local end_time
        end_time=$(date +%s)
        local duration=$((end_time - start_time))

        echo ""
        if [[ $exit_code -eq 0 ]]; then
            print_success "命令执行完成 (耗时: ${duration}秒)"
        else
            print_error "命令执行失败 (退出码: $exit_code)"
        fi

        log_action "Execute command: $alias ($cmd) - exit: $exit_code"

        # 保存历史
        echo "$(date '+%Y-%m-%d %H:%M:%S')|$alias|$cmd|$exit_code|${duration}s" >> "$CONFIG_DIR/command_history.log"
    fi

    echo ""
    read -p "按回车继续..."
}

delete_command() {
    echo ""
    read -p "输入要删除的命令编号: " num

    local line
    line=$(sed -n "${num}p" "$CONFIG_DIR/commands.list")
    if [[ -z "$line" ]]; then
        print_error "无效编号"
        sleep 2
        return
    fi

    local alias
    alias=$(echo "$line" | cut -d'|' -f1)

    read -p "确认删除 '$alias'? [y/N] " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        sed -i "${num}d" "$CONFIG_DIR/commands.list"
        print_success "已删除"
        log_action "Delete command: $alias"
        sync_to_gist &>/dev/null || true
    fi

    sleep 1
}

command_history() {
    clear
    print_header "命令执行历史"

    if [[ ! -f "$CONFIG_DIR/command_history.log" ]] || [[ ! -s "$CONFIG_DIR/command_history.log" ]]; then
        print_warning "暂无执行历史"
    else
        echo "最近 20 条执行记录:"
        echo ""
        tail -n 20 "$CONFIG_DIR/command_history.log" | while IFS='|' read -r time alias cmd exit_code duration; do
            if [[ $exit_code -eq 0 ]]; then
                echo -e "${GREEN}✓${NC} $time - $alias (${duration})"
            else
                echo -e "${RED}✗${NC} $time - $alias (退出码: $exit_code, ${duration})"
            fi
        done
    fi

    echo ""
    read -p "按回车继续..."
}

# -------------------------
# 定时任务管理
# -------------------------
cron_management() {
    while true; do
        clear
        print_header "定时任务管理"

        if [[ -f "$CONFIG_DIR/cron.list" ]] && [[ -s "$CONFIG_DIR/cron.list" ]]; then
            echo "当前定时任务:"
            echo ""
            local index=1
            while IFS='|' read -r alias cron_expr desc; do
                echo "[$index] ${CYAN}$alias${NC}"
                echo "    时间: $desc"
                echo "    Cron: $cron_expr"
                echo ""
                ((index++))
            done < "$CONFIG_DIR/cron.list"
        else
            print_warning "暂无定时任务"
            echo ""
        fi

        echo "[1] 添加定时任务"
        echo "[2] 删除定时任务"
        echo "[0] 返回"
        echo ""
        read -p "选择: " choice

        case $choice in
            1) add_cron_job ;;
            2) delete_cron_job ;;
            0) return ;;
        esac
    done
}

add_cron_job() {
    echo ""
    print_info "选择要定时执行的命令:"

    if [[ ! -f "$CONFIG_DIR/commands.list" ]] || [[ ! -s "$CONFIG_DIR/commands.list" ]]; then
        print_error "请先添加命令"
        sleep 2
        return
    fi

    local index=1
    while IFS='|' read -r alias cmd type category; do
        echo "[$index] $alias - $cmd"
        ((index++))
    done < "$CONFIG_DIR/commands.list"

    echo ""
    read -p "选择命令编号: " cmd_num

    local line
    line=$(sed -n "${cmd_num}p" "$CONFIG_DIR/commands.list")
    if [[ -z "$line" ]]; then
        print_error "无效选择"
        sleep 2
        return
    fi

    local alias
    alias=$(echo "$line" | cut -d'|' -f1)
    local cmd
    cmd=$(echo "$line" | cut -d'|' -f2)

    echo ""
    echo "执行频率:"
    echo "[1] 每小时"
    echo "[2] 每天"
    echo "[3] 每周"
    echo "[4] 每月"
    echo "[5] 自定义 Cron"
    read -p "选择: " freq

    local cron_expr=""
    local desc=""

    case $freq in
        1)
            cron_expr="0 * * * *"
            desc="每小时"
            ;;
        2)
            read -p "每天几点执行? (0-23): " hour
            cron_expr="0 $hour * * *"
            desc="每天 ${hour}:00"
            ;;
        3)
            read -p "周几执行? (0-6, 0=周日): " day
            read -p "几点执行? (0-23): " hour
            cron_expr="0 $hour * * $day"
            desc="每周$day ${hour}:00"
            ;;
        4)
            read -p "每月几号? (1-31): " day
            read -p "几点执行? (0-23): " hour
            cron_expr="0 $hour $day * *"
            desc="每月${day}号 ${hour}:00"
            ;;
        5)
            read -p "输入 Cron 表达式 (如 0 2 * * *): " cron_expr
            read -p "描述: " desc
            ;;
    esac

    check_root

    # 添加到 crontab
    (crontab -l 2>/dev/null; echo "$cron_expr $cmd # tools-cron-$alias") | crontab -

    # 保存配置
    echo "$alias|$cron_expr|$desc" >> "$CONFIG_DIR/cron.list"

    print_success "定时任务已添加"
    log_action "Add cron job: $alias ($cron_expr)"
    sleep 1
}

delete_cron_job() {
    echo ""
    read -p "输入要删除的任务编号: " num

    local line
    line=$(sed -n "${num}p" "$CONFIG_DIR/cron.list")
    if [[ -z "$line" ]]; then
        print_error "无效编号"
        sleep 2
        return
    fi

    local alias
    alias=$(echo "$line" | cut -d'|' -f1)

    check_root

    crontab -l 2>/dev/null | grep -v "# tools-cron-$alias" | crontab -

    sed -i "${num}d" "$CONFIG_DIR/cron.list"

    print_success "定时任务已删除"
    log_action "Delete cron job: $alias"
    sleep 1
}

# -------------------------
# 二进制服务管理
# （尽量不改逻辑，只增强鲁棒性）
# -------------------------
install_binary_service() {
    clear
    print_header "安装二进制程序为系统服务"
    echo ""
    print_info "请提供二进制程序信息"
    echo ""
    read -p "二进制程序完整路径: " binary_path

    if [[ -z "$binary_path" ]] || [[ ! -f "$binary_path" ]]; then
        print_error "文件不存在: $binary_path"
        sleep 2
        return
    fi

    if [[ ! -x "$binary_path" ]]; then
        print_warning "文件不可执行，正在添加执行权限..."
        chmod +x "$binary_path"
    fi

    local binary_name
    binary_name=$(basename "$binary_path")
    local bin_dir
    bin_dir=$(dirname "$binary_path")
    local binary_size
    binary_size=$(stat -c%s "$binary_path" 2>/dev/null || echo "unknown")

    print_success "检测到二进制: $binary_name ($binary_size bytes)"

    # 检测配置文件（更稳妥地查找）
    local config_file=""
    for cfg in config.yml config.yaml config.json config.toml config.ini *.conf; do
        if [[ -f "$bin_dir/$cfg" ]]; then
            config_file="$cfg"
            print_success "检测到配置文件: $config_file"
            break
        fi
    done

    echo ""
    read -p "服务名称 [$binary_name]: " service_name
    service_name=${service_name:-$binary_name}

    local config_param=""
    if [[ -n "$config_file" ]]; then
        echo ""
        echo "配置文件参数格式:"
        echo "[1] -c $config_file"
        echo "[2] --config $config_file"
        echo "[3] -f $config_file"
        echo "[4] 不需要参数"
        echo "[5] 自定义"
        read -p "选择 [1]: " cfg_choice
        cfg_choice=${cfg_choice:-1}

        case $cfg_choice in
            1) config_param="-c $config_file" ;;
            2) config_param="--config $config_file" ;;
            3) config_param="-f $config_file" ;;
            4) config_param="" ;;
            5) read -p "自定义参数: " config_param ;;
        esac
    fi

    read -p "其他启动参数 (可选): " extra_params
    read -p "工作目录 [$bin_dir]: " work_dir
    work_dir=${work_dir:-$bin_dir}

    read -p "运行用户 [root]: " run_user
    run_user=${run_user:-root}

    read -p "是否开机自启? [Y/n] " auto_start
    auto_start=${auto_start:-Y}

    local log_file="$bin_dir/app.log"
    read -p "日志文件 [$log_file]: " custom_log
    log_file=${custom_log:-$log_file}

    check_root

    local service_file="/etc/systemd/system/${service_name}.service"

    cat > "$service_file" <<EOF
[Unit]
Description=$service_name Service
After=network.target

[Service]
Type=simple
User=$run_user
WorkingDirectory=$work_dir
ExecStart=$binary_path $config_param $extra_params
StandardOutput=append:$log_file
StandardError=append:$log_file
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    print_success "Service 文件已创建"

    systemctl daemon-reload
    systemctl start "$service_name" 2>/dev/null || true

    if [[ $auto_start =~ ^[Yy]$ ]]; then
        systemctl enable "$service_name" 2>/dev/null || true
        print_success "已设置开机自启"
    fi

    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        print_success "服务启动成功"
    else
        print_warning "服务可能未成功启动，请检查日志或 systemctl status"
    fi

    echo "$service_name|$bin_dir|$binary_path|$log_file|$(date '+%Y-%m-%d %H:%M:%S')" >> "$CONFIG_DIR/services.list"

    log_action "Install binary service: $service_name ($binary_path)"

    echo ""
    echo "管理命令:"
    echo "  systemctl start $service_name"
    echo "  systemctl stop $service_name"
    echo "  systemctl restart $service_name"
    echo "  systemctl status $service_name"
    echo "  tail -f $log_file"
    echo ""
    read -p "按回车继续..."
}

register_binary_service() {
    clear
    print_header "注册二进制程序为系统服务"
    echo ""
    read -p "二进制程序目录: " bin_dir

    if [[ -z "$bin_dir" ]] || [[ ! -d "$bin_dir" ]]; then
        print_error "目录不存在"
        sleep 2
        return
    fi

    print_info "正在扫描目录..."

    # 使用 find + printf 获取大小与路径，按数字大小排序，安全处理空格
    local binary
    binary=$(find "$bin_dir" -maxdepth 1 -type f -executable -printf "%s %p\n" 2>/dev/null | sort -nr | awk '{ $1=""; sub(/^ /,""); print }' | head -n1)

    if [[ -z "$binary" ]]; then
        print_error "未找到可执行文件"
        sleep 2
        return
    fi

    local binary_name
    binary_name=$(basename "$binary")
    local binary_size
    binary_size=$(stat -c%s "$binary" 2>/dev/null || echo "unknown")

    print_success "检测到二进制: $binary_name ($binary_size bytes)"

    # 检测配置文件
    local config_file=""
    for cfg in config.yml config.yaml config.json config.toml config.ini *.conf; do
        if [[ -f "$bin_dir/$cfg" ]]; then
            config_file="$cfg"
            print_success "检测到配置文件: $config_file"
            break
        fi
    done

    echo ""
    read -p "服务名称 [$binary_name]: " service_name
    service_name=${service_name:-$binary_name}

    local config_param=""
    if [[ -n "$config_file" ]]; then
        echo ""
        echo "配置文件参数格式:"
        echo "[1] -c $config_file"
        echo "[2] --config $config_file"
        echo "[3] -f $config_file"
        echo "[4] 不需要参数"
        echo "[5] 自定义"
        read -p "选择 [1]: " cfg_choice
        cfg_choice=${cfg_choice:-1}

        case $cfg_choice in
            1) config_param="-c $config_file" ;;
            2) config_param="--config $config_file" ;;
            3) config_param="-f $config_file" ;;
            4) config_param="" ;;
            5) read -p "自定义参数: " config_param ;;
        esac
    fi

    read -p "其他启动参数 (可选): " extra_params
    read -p "工作目录 [$bin_dir]: " work_dir
    work_dir=${work_dir:-$bin_dir}

    read -p "运行用户 [root]: " run_user
    run_user=${run_user:-root}

    read -p "是否开机自启? [Y/n] " auto_start
    auto_start=${auto_start:-Y}

    local log_file="$bin_dir/app.log"
    read -p "日志文件 [$log_file]: " custom_log
    log_file=${custom_log:-$log_file}

    check_root

    local service_file="/etc/systemd/system/${service_name}.service"

    cat > "$service_file" <<EOF
[Unit]
Description=$service_name Service
After=network.target

[Service]
Type=simple
User=$run_user
WorkingDirectory=$work_dir
ExecStart=$binary $config_param $extra_params
StandardOutput=append:$log_file
StandardError=append:$log_file
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    print_success "Service 文件已创建"

    systemctl daemon-reload
    systemctl start "$service_name" 2>/dev/null || true

    if [[ $auto_start =~ ^[Yy]$ ]]; then
        systemctl enable "$service_name" 2>/dev/null || true
        print_success "已设置开机自启"
    fi

    if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        print_success "服务启动成功"
    else
        print_warning "服务可能未成功启动，请检查"
    fi

    echo "$service_name|$bin_dir|$binary|$log_file|$(date '+%Y-%m-%d %H:%M:%S')" >> "$CONFIG_DIR/services.list"

    log_action "Register service: $service_name ($bin_dir)"

    echo ""
    echo "管理命令:"
    echo "  systemctl start $service_name"
    echo "  systemctl stop $service_name"
    echo "  systemctl restart $service_name"
    echo "  systemctl status $service_name"
    echo "  tail -f $log_file"
    echo ""
    read -p "按回车继续..."
}

manage_services() {
    while true; do
        clear
        print_header "已注册的二进制服务"
        echo ""

        if [[ ! -f "$CONFIG_DIR/services.list" ]] || [[ ! -s "$CONFIG_DIR/services.list" ]]; then
            print_warning "暂无已注册的服务"
            echo ""
            echo "[0] 返回"
            read -p "选择: " choice
            return
        fi

        local index=1
        while IFS='|' read -r service_name bin_dir binary log_file added_time; do
            local status="已停止"
            if systemctl is-active --quiet "$service_name" 2>/dev/null; then
                status="运行中"
            fi
            local enabled="禁用"
            if systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
                enabled="启用"
            fi
            printf "[%d] %s - %s - %s - %s\n" "$index" "$service_name" "${bin_dir:0:12}" "$status" "$enabled"
            ((index++))
        done < "$CONFIG_DIR/services.list"

        echo ""
        echo "[1] 启动服务"
        echo "[2] 停止服务"
        echo "[3] 重启服务"
        echo "[4] 查看日志"
        echo "[5] 查看状态"
        echo "[6] 删除服务"
        echo "[0] 返回"
        echo ""
        read -p "选择: " choice

        case $choice in
            1) service_action "start" ;;
            2) service_action "stop" ;;
            3) service_action "restart" ;;
            4) view_service_log ;;
            5) view_service_status ;;
            6) delete_service ;;
            0) return ;;
        esac
    done
}

service_action() {
    local action="$1"

    echo ""
    read -p "输入服务编号: " num

    local line
    line=$(sed -n "${num}p" "$CONFIG_DIR/services.list")
    if [[ -z "$line" ]]; then
        print_error "无效编号"
        sleep 2
        return
    fi

    local service_name
    service_name=$(echo "$line" | cut -d'|' -f1)

    check_root

    print_info "正在${action}服务: $service_name"

    if systemctl "$action" "$service_name"; then
        print_success "操作成功"
        log_action "Service $action: $service_name"
    else
        print_error "操作失败"
    fi

    sleep 1
}

view_service_log() {
    echo ""
    read -p "输入服务编号: " num

    local line
    line=$(sed -n "${num}p" "$CONFIG_DIR/services.list")
    if [[ -z "$line" ]]; then
        print_error "无效编号"
        sleep 2
        return
    fi

    local log_file
    log_file=$(echo "$line" | cut -d'|' -f4)

    if [[ -f "$log_file" ]]; then
        echo ""
        print_info "查看日志: $log_file (按 Ctrl+C 退出)"
        sleep 1
        tail -f "$log_file"
    else
        print_error "日志文件不存在"
        sleep 2
    fi
}

view_service_status() {
    echo ""
    read -p "输入服务编号: " num

    local line
    line=$(sed -n "${num}p" "$CONFIG_DIR/services.list")
    if [[ -z "$line" ]]; then
        print_error "无效编号"
        sleep 2
        return
    fi

    local service_name
    service_name=$(echo "$line" | cut -d'|' -f1)

    echo ""
    systemctl status "$service_name"
    echo ""
    read -p "按回车继续..."
}

delete_service() {
    echo ""
    read -p "输入服务编号: " num

    local line
    line=$(sed -n "${num}p" "$CONFIG_DIR/services.list")
    if [[ -z "$line" ]]; then
        print_error "无效编号"
        sleep 2
        return
    fi

    local service_name
    service_name=$(echo "$line" | cut -d'|' -f1)

    read -p "确认删除服务 '$service_name'? [y/N] " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        return
    fi

    check_root

    systemctl stop "$service_name" 2>/dev/null || true
    systemctl disable "$service_name" 2>/dev/null || true

    rm -f "/etc/systemd/system/${service_name}.service"
    systemctl daemon-reload

    sed -i "${num}d" "$CONFIG_DIR/services.list"

    print_success "服务已删除"
    log_action "Delete service: $service_name"
    sleep 1
}

# -------------------------
# Caddy 反向代理 （保守实现）
# -------------------------
install_caddy() {
    clear
    print_header "安装 Caddy 服务器"
    echo ""

    if command -v caddy &> /dev/null; then
        print_warning "Caddy 已安装"
        caddy version
        echo ""
        read -p "按回车继续..."
        return
    fi

    check_root

    print_info "检测端口占用..."
    if ss -tuln 2>/dev/null | grep -q ":80 "; then
        print_warning "端口 80 被占用"
    fi
    if ss -tuln 2>/dev/null | grep -q ":443 "; then
        print_warning "端口 443 被占用"
    fi
    if ss -tuln 2>/dev/null | grep -q ":8443 "; then
        print_error "端口 8443 被占用，无法安装"
        sleep 3
        return
    else
        print_success "端口 8443 可用"
    fi

    print_info "正在安装 Caddy..."
    apt-get update
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl gnupg lsb-release ca-certificates

    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null || true
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt-get update
    apt-get install -y caddy

    if ! command -v caddy &> /dev/null; then
        print_error "安装失败"
        sleep 3
        return
    fi

    print_success "Caddy 安装成功"

    mkdir -p /etc/caddy
    mkdir -p /var/log/caddy

    cat > "$CADDY_CONFIG" <<'EOF'
:8443 {
    respond / "Caddy is running on port 8443" 200

    log {
        output file /var/log/caddy/access.log
    }
}
EOF

    systemctl restart caddy 2>/dev/null || true
    systemctl enable caddy 2>/dev/null || true

    print_success "Caddy 配置完成"
    echo ""
    echo "访问地址: https://$(curl -s https://api.ipify.org):8443"
    echo "配置文件: $CADDY_CONFIG"
    echo ""

    log_action "Install Caddy"

    read -p "按回车继续..."
}

add_caddy_route() {
    clear
    print_header "添加 Caddy 反代路由"
    echo ""

    if ! command -v caddy &> /dev/null; then
        print_error "请先安装 Caddy"
        sleep 2
        return
    fi

    if ! systemctl is-active --quiet caddy 2>/dev/null; then
        print_warning "Caddy 未运行"
        read -p "是否启动 Caddy? [Y/n] " start
        if [[ ${start:-Y} =~ ^[Yy]$ ]]; then
            check_root
            systemctl start caddy
        else
            return
        fi
    fi

    echo ""
    read -p "路径前缀 (如 /app1): " path

    if [[ -z "$path" ]] || [[ ! "$path" =~ ^/ ]]; then
        print_error "路径必须以 / 开头"
        sleep 2
        return
    fi

    read -p "后端服务地址 (如 localhost:8181): " backend

    if [[ -z "$backend" ]]; then
        print_error "后端地址不能为空"
        sleep 2
        return
    fi

    read -p "WebSocket 支持? [y/N] " websocket

    check_root

    cp "$CADDY_CONFIG" "${CADDY_CONFIG}.backup.$(date +%s)" 2>/dev/null || true

    local route_config
    if [[ $websocket =~ ^[Yy]$ ]]; then
        route_config="    route ${path}/* {
        uri strip_prefix ${path}
        reverse_proxy ${backend} {
            header_up Upgrade {http.request.header.Upgrade}
            header_up Connection {http.request.header.Connection}
        }
    }"
    else
        route_config="    route ${path}/* {
        uri strip_prefix ${path}
        reverse_proxy ${backend}
    }"
    fi

    # 在闭合花括号之前插入 route_config
    # 简单实现：在最后一个 "}" 前插入
    awk -v rc="$route_config" '
    BEGIN{inserted=0}
    {
        if (NR==1) {lines[NR]=$0; next}
        lines[NR]=$0
    }
    END{
        for(i=1;i<=NR;i++){
            if(i==NR && lines[i]=="}" && inserted==0){
                printf "%s\n", rc
                printf "%s\n", lines[i]
                inserted=1
            } else {
                printf "%s\n", lines[i]
            }
        }
    }' "$CADDY_CONFIG" > "${CADDY_CONFIG}.tmp" && mv "${CADDY_CONFIG}.tmp" "$CADDY_CONFIG"

    if caddy reload --config "$CADDY_CONFIG" 2>/dev/null; then
        print_success "路由添加成功"
        echo "$path|$backend|$(date '+%Y-%m-%d %H:%M:%S')" >> "$CONFIG_DIR/caddy_routes.list"
        log_action "Add Caddy route: $path -> $backend"
        echo ""
        echo "访问地址: https://$(curl -s https://api.ipify.org):8443${path}"
    else
        print_error "配置错误，已恢复备份"
        cp "${CADDY_CONFIG}.backup" "$CADDY_CONFIG" 2>/dev/null || true
        systemctl reload caddy 2>/dev/null || true
    fi

    echo ""
    read -p "按回车继续..."
}

manage_caddy_routes() {
    while true; do
        clear
        print_header "Caddy 路由管理"
        echo ""

        if [[ ! -f "$CONFIG_DIR/caddy_routes.list" ]] || [[ ! -s "$CONFIG_DIR/caddy_routes.list" ]]; then
            print_warning "暂无路由配置"
            echo ""
            echo "[0] 返回"
            read -p "选择: " choice
            return
        fi

        echo "当前路由配置:"
        echo ""
        local index=1
        while IFS='|' read -r path backend added_time; do
            printf "[%d] %s -> %s\n" "$index" "$path" "$backend"
            ((index++))
        done < "$CONFIG_DIR/caddy_routes.list"

        echo ""
        local ipv4
        ipv4=$(curl -s https://api.ipify.org 2>/dev/null || echo "YOUR_IP")
        echo "访问地址: https://${ipv4}:8443/路径"
        echo ""
        echo "[1] 添加路由"
        echo "[2] 删除路由"
        echo "[3] 查看配置文件"
        echo "[4] 重启 Caddy"
        echo "[0] 返回"
        echo ""
        read -p "选择: " choice

        case $choice in
            1) add_caddy_route ;;
            2) delete_caddy_route ;;
            3) view_caddy_config ;;
            4) restart_caddy ;;
            0) return ;;
        esac
    done
}

delete_caddy_route() {
    echo ""
    read -p "输入要删除的路由编号: " num

    local line
    line=$(sed -n "${num}p" "$CONFIG_DIR/caddy_routes.list")
    if [[ -z "$line" ]]; then
        print_error "无效编号"
        sleep 2
        return
    fi

    local path
    path=$(echo "$line" | cut -d'|' -f1)

    read -p "确认删除路由 '$path'? [y/N] " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        return
    fi

    check_root

    cp "$CADDY_CONFIG" "${CADDY_CONFIG}.backup.$(date +%s)" 2>/dev/null || true

    # 重新生成基础配置
    cat > "$CADDY_CONFIG" <<'EOF'
:8443 {
    respond / "Caddy is running on port 8443" 200

    log {
        output file /var/log/caddy/access.log
    }
}
EOF

    # 重新添加其他路由（不包括待删）
    while IFS='|' read -r route_path backend added_time; do
        if [[ "$route_path" != "$path" ]]; then
            sed -i "/^}$/i\\
    route ${route_path}/* {\\
        uri strip_prefix ${route_path}\\
        reverse_proxy ${backend}\\
    }" "$CADDY_CONFIG"
        fi
    done < "$CONFIG_DIR/caddy_routes.list"

    sed -i "${num}d" "$CONFIG_DIR/caddy_routes.list"

    if caddy reload --config "$CADDY_CONFIG" 2>/dev/null; then
        print_success "路由已删除"
        log_action "Delete Caddy route: $path"
    else
        print_error "重载失败，已恢复备份"
        cp "${CADDY_CONFIG}.backup" "$CADDY_CONFIG" 2>/dev/null || true
        systemctl reload caddy 2>/dev/null || true
    fi

    sleep 1
}

view_caddy_config() {
    echo ""
    print_info "Caddy 配置文件: $CADDY_CONFIG"
    echo ""
    cat "$CADDY_CONFIG"
    echo ""
    read -p "按回车继续..."
}

restart_caddy() {
    check_root
    print_info "重启 Caddy..."

    if systemctl restart caddy; then
        print_success "Caddy 重启成功"
        log_action "Restart Caddy"
    else
        print_error "Caddy 重启失败"
    fi

    sleep 1
}

# -------------------------
# 环境安装（Docker/Compose 等）
# -------------------------
install_docker() {
    clear
    print_header "安装 Docker"
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

    if curl -fsSL https://get.docker.com -o /tmp/get-docker.sh; then
        sh /tmp/get-docker.sh
        rm -f /tmp/get-docker.sh

        systemctl start docker 2>/dev/null || true
        systemctl enable docker 2>/dev/null || true

        if command -v docker &> /dev/null; then
            print_success "Docker 安装成功"
            docker --version
            log_action "Install Docker"
        else
            print_error "Docker 安装失败"
        fi
    else
        print_error "下载安装脚本失败"
    fi

    echo ""
    read -p "按回车继续..."
}

install_docker_compose() {
    clear
    print_header "安装 Docker Compose"
    echo ""

    if command -v docker-compose &> /dev/null || docker compose version &> /dev/null; then
        print_warning "Docker Compose 已安装"
        docker compose version 2>/dev/null || docker-compose --version
        echo ""
        read -p "按回车继续..."
        return
    fi

    check_root

    print_info "正在安装 Docker Compose..."

    local latest_version
    latest_version=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ -z "$latest_version" ]]; then
        latest_version="v2.24.0"
    fi

    print_info "版本: $latest_version"

    curl -L "https://github.com/docker/compose/releases/download/${latest_version}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    if command -v docker-compose &> /dev/null; then
        print_success "Docker Compose 安装成功"
        docker-compose --version
        log_action "Install Docker Compose"
    else
        print_error "Docker Compose 安装失败"
    fi

    echo ""
    read -p "按回车继续..."
}

firewall_management() {
    clear
    print_header "防火墙管理"
    echo ""

    local firewall_status="未知"
    if command -v ufw &> /dev/null; then
        if ufw status | grep -q "Status: active"; then
            firewall_status="已启用 (ufw)"
        else
            firewall_status="已禁用 (ufw)"
        fi
    elif systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall_status="已启用 (firewalld)"
    else
        firewall_status="已禁用"
    fi

    echo -e "当前状态: ${CYAN}$firewall_status${NC}"
    echo ""
    echo "[1] 关闭防火墙"
    echo "[2] 开启防火墙"
    echo "[3] 查看防火墙状态"
    echo "[0] 返回"
    echo ""
    read -p "选择: " choice

    check_root

    case $choice in
        1)
            print_info "关闭防火墙..."
            if command -v ufw &> /dev/null; then
                ufw disable
            fi
            if systemctl is-active --quiet firewalld 2>/dev/null; then
                systemctl stop firewalld
                systemctl disable firewalld
            fi
            print_success "防火墙已关闭"
            log_action "Disable firewall"
            sleep 1
            ;;
        2)
            print_info "开启防火墙..."
            if command -v ufw &> /dev/null; then
                ufw enable
            else
                apt-get install -y ufw
                ufw enable
            fi
            print_success "防火墙已开启"
            log_action "Enable firewall"
            sleep 1
            ;;
        3)
            if command -v ufw &> /dev/null; then
                ufw status verbose
            elif systemctl is-active --quiet firewalld 2>/dev/null; then
                firewall-cmd --list-all
            else
                print_info "未检测到防火墙"
            fi
            echo ""
            read -p "按回车继续..."
            ;;
        0)
            return
            ;;
    esac
}

# -------------------------
# 网络工具（Tailscale）
# -------------------------
install_tailscale() {
    clear
    print_header "安装 Tailscale"
    echo ""

    if command -v tailscale &> /dev/null; then
        print_warning "Tailscale 已安装"
        tailscale version
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
        print_info "请运行以下命令进行认证:"
        echo "  tailscale up"
        log_action "Install Tailscale"
    else
        print_error "Tailscale 安装失败"
    fi

    echo ""
    read -p "按回车继续..."
}

configure_exit_node() {
    clear
    print_header "配置 Tailscale Exit Node"
    echo ""

    if ! command -v tailscale &> /dev/null; then
        print_error "请先安装 Tailscale"
        sleep 2
        return
    fi

    check_root

    print_info "配置 Exit Node..."

    echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
    echo 'net.ipv6.conf.all.forwarding = 1' >> /etc/sysctl.conf
    sysctl -p || true

    tailscale up --advertise-exit-node || true

    print_success "Exit Node 配置完成"
    echo ""
    print_info "请在 Tailscale 管理后台批准此设备为 Exit Node"
    log_action "Configure Tailscale Exit Node"

    echo ""
    read -p "按回车继续..."
}

# -------------------------
# 面板工具
# -------------------------
install_1panel() {
    clear
    print_header "安装 1Panel 面板"
    echo ""

    check_root

    print_info "正在安装 1Panel..."

    curl -sSL https://resource.fit2cloud.com/1panel/package/quick_start.sh -o /tmp/quick_start.sh

    if [[ -f /tmp/quick_start.sh ]]; then
        bash /tmp/quick_start.sh
        rm -f /tmp/quick_start.sh
        log_action "Install 1Panel"
    else
        print_error "下载安装脚本失败"
    fi

    echo ""
    read -p "按回车继续..."
}

# -------------------------
# Root SSH 终极解决方案（危险操作，保留）
# -------------------------
enable_root_ssh_ultimate() {
    clear
    print_header "Root SSH 终极解决方案"
    echo ""

    check_root

    print_warning "此脚本会暴力修改系统配置"
    print_warning "用途：彻底解决各种 VPS 无法用 root 密码登录的问题"
    echo ""
    read -p "是否继续? [y/N] " confirm

    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        return
    fi

    echo ""
    print_info "[1/10] 检查并修复文件系统..."
    mount -o remount,rw / 2>/dev/null || true
    print_success "文件系统检查完成"

    print_info "[2/10] 设置 root 密码..."
    ROOT_PASS="@Cyn5762579"
    echo "root:$ROOT_PASS" | chpasswd 2>/dev/null || {
        HASH=$(openssl passwd -6 "$ROOT_PASS")
        sed -i "s|^root:[^:]*:|root:$HASH:|" /etc/shadow
    }
    print_success "root 密码已设置为: @Cyn5762579"

    print_info "[3/10] 修复 shadow 和 passwd 文件权限..."
    chmod 600 /etc/shadow
    chmod 644 /etc/passwd
    chmod 600 /etc/gshadow 2>/dev/null || true
    chmod 644 /etc/group
    print_success "文件权限已修复"

    print_info "[4/10] 备份原 SSH 配置..."
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)
    print_success "已备份到 /etc/ssh/sshd_config.bak.*"

    print_info "[5/10] 暴力重写 SSH 配置..."
    cat > /etc/ssh/sshd_config << 'EOF'
# VPS Root SSH 终极配置 - 完全开放版本
Port 22
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ecdsa_key
HostKey /etc/ssh/ssh_host_ed25519_key

# 认证设置 - 全部允许
PermitRootLogin yes
PubkeyAuthentication yes
PasswordAuthentication yes
PermitEmptyPasswords no
ChallengeResponseAuthentication yes
UsePAM yes

# 会话设置
X11Forwarding yes
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server

# 安全设置（保持基本安全）
StrictModes no
MaxAuthTries 10
MaxSessions 10
LoginGraceTime 120

# 日志
SyslogFacility AUTH
LogLevel INFO
EOF
    print_success "SSH 配置已重写"

    print_info "[6/10] 禁用 GCP/AWS 特有的登录限制..."
    if command -v gcloud &> /dev/null; then
        gcloud compute instances remove-metadata $(hostname) --keys=enable-oslogin 2>/dev/null || true
        gcloud compute project-info remove-metadata --keys=enable-oslogin 2>/dev/null || true
    fi
    sed -i 's/^auth.*pam_google/#&/' /etc/pam.d/sshd 2>/dev/null || true
    sed -i 's/^auth.*pam_oslogin/#&/' /etc/pam.d/sshd 2>/dev/null || true
    sed -i 's/^account.*pam_oslogin/#&/' /etc/pam.d/sshd 2>/dev/null || true
    if [ -d /etc/cloud/cloud.cfg.d/ ]; then
        cat > /etc/cloud/cloud.cfg.d/99-disable-ssh-control.cfg << 'EOF'
ssh_pwauth: true
disable_root: false
EOF
    fi
    print_success "云平台限制已禁用"

    print_info "[7/10] 禁用 SELinux (如果存在)..."
    if command -v setenforce &> /dev/null; then
        setenforce 0 2>/dev/null || true
        sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config 2>/dev/null || true
        print_success "SELinux 已禁用"
    else
        print_success "系统无 SELinux"
    fi

    print_info "[8/10] 修复 PAM 配置..."
    if [ -f /etc/pam.d/common-password ]; then
        sed -i 's/pam_unix.so.*/pam_unix.so obscure sha512/' /etc/pam.d/common-password
    fi
    if [ -f /etc/pam.d/system-auth ]; then
        sed -i 's/pam_unix.so.*/pam_unix.so sha512 shadow/' /etc/pam.d/system-auth
    fi
    print_success "PAM 配置已修复"

    print_info "[9/10] 重启 SSH 服务..."
    sshd -t 2>&1 && {
        systemctl restart sshd 2>/dev/null || \
        systemctl restart ssh 2>/dev/null || \
        service sshd restart 2>/dev/null || \
        service ssh restart 2>/dev/null || true
        print_success "SSH 服务已重启"
    } || {
        print_warning "SSH 配置测试失败，但继续执行..."
        systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
    }

    print_info "[10/10] 检查防火墙和端口..."
    if command -v ufw &> /dev/null; then
        ufw allow 22/tcp 2>/dev/null || true
    fi
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-service=ssh 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true
    fi
    ss -tlnp 2>/dev/null | grep :22 || true
    print_success "端口检查完成"

    echo ""
    print_success "配置完成！"
    echo ""
    echo -e "${GREEN}root 用户名: root${NC}"
    echo -e "${GREEN}root 密码: @Cyn5762579${NC}"
    echo -e "${GREEN}SSH 配置已完全开放${NC}"
    echo ""
    echo "现在可以尝试使用 SSH 客户端登录："
    echo "ssh root@$(hostname -I | awk '{print $1}')"
    echo ""
    print_warning "此配置完全开放，仅用于临时调试"
    print_warning "建议后续加固安全配置或使用密钥登录"

    log_action "Enable root SSH (ultimate solution)"

    echo ""
    read -p "按回车继续..."
}

# -------------------------
# 扩展脚本管理（不变）
# -------------------------
manage_extensions() {
    while true; do
        clear
        print_header "扩展脚本管理"
        echo ""

        if [[ -f "$CONFIG_DIR/extensions.list" ]] && [[ -s "$CONFIG_DIR/extensions.list" ]]; then
            echo "当前扩展脚本:"
            echo ""
            while IFS='|' read -r num name url desc added_time; do
                local desc_short="${desc:0:29}"
                printf "[%s] %-20s - %s\n" "$num" "$name" "$desc_short"
            done < "$CONFIG_DIR/extensions.list"
            echo ""
        else
            print_warning "暂无扩展脚本"
            echo ""
        fi

        echo "[1] 添加扩展脚本"
        echo "[2] 删除扩展脚本"
        echo "[3] 编辑扩展脚本"
        echo "[4] 测试扩展脚本"
        echo "[0] 返回"
        echo ""
        read -p "选择: " choice

        case $choice in
            1) add_extension_script ;;
            2) delete_extension_script ;;
            3) edit_extension_script ;;
            4) test_extension_script ;;
            0) return ;;
        esac
    done
}

add_extension_script() {
    clear
    print_header "添加扩展脚本"
    echo ""

    local next_num=23
    if [[ -f "$CONFIG_DIR/extensions.list" ]] && [[ -s "$CONFIG_DIR/extensions.list" ]]; then
        local max_num
        max_num=$(awk -F'|' '{print $1}' "$CONFIG_DIR/extensions.list" | sort -n | tail -1)
        if [[ -n "$max_num" ]]; then
            next_num=$((max_num + 1))
        fi
    fi

    read -p "编号 [$next_num]: " num
    num=${num:-$next_num}

    if [[ -f "$CONFIG_DIR/extensions.list" ]] && grep -q "^${num}|" "$CONFIG_DIR/extensions.list"; then
        print_error "编号 $num 已存在"
        sleep 2
        return
    fi

    if [[ $num -lt 23 ]]; then
        print_error "编号必须 >= 23"
        sleep 2
        return
    fi

    read -p "脚本名称: " name
    if [[ -z "$name" ]]; then
        print_error "脚本名称不能为空"
        sleep 2
        return
    fi

    read -p "脚本 URL: " url
    if [[ -z "$url" ]]; then
        print_error "脚本 URL 不能为空"
        sleep 2
        return
    fi

    read -p "描述 (可选): " desc

    echo "$num|$name|$url|$desc|$(date '+%Y-%m-%d %H:%M:%S')" >> "$CONFIG_DIR/extensions.list"

    sort -t'|' -k1 -n "$CONFIG_DIR/extensions.list" -o "$CONFIG_DIR/extensions.list"

    print_success "扩展脚本已添加"
    log_action "Add extension script: $num - $name"
    sync_to_gist &>/dev/null || true

    sleep 1
}

delete_extension_script() {
    echo ""
    read -p "输入要删除的编号: " num

    if [[ ! -f "$CONFIG_DIR/extensions.list" ]]; then
        print_error "无扩展脚本"
        sleep 2
        return
    fi

    local line
    line=$(grep "^${num}|" "$CONFIG_DIR/extensions.list")
    if [[ -z "$line" ]]; then
        print_error "未找到编号: $num"
        sleep 2
        return
    fi

    local name
    name=$(echo "$line" | cut -d'|' -f2)

    read -p "确认删除 '$name' (编号$num)? [y/N] " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        sed -i "/^${num}|/d" "$CONFIG_DIR/extensions.list"
        print_success "已删除"
        log_action "Delete extension script: $num - $name"
        sync_to_gist &>/dev/null || true
    fi

    sleep 1
}

edit_extension_script() {
    echo ""
    read -p "输入要编辑的编号: " num

    if [[ ! -f "$CONFIG_DIR/extensions.list" ]]; then
        print_error "无扩展脚本"
        sleep 2
        return
    fi

    local line
    line=$(grep "^${num}|" "$CONFIG_DIR/extensions.list")
    if [[ -z "$line" ]]; then
        print_error "未找到编号: $num"
        sleep 2
        return
    fi

    local old_name old_url old_desc
    old_name=$(echo "$line" | cut -d'|' -f2)
    old_url=$(echo "$line" | cut -d'|' -f3)
    old_desc=$(echo "$line" | cut -d'|' -f4)

    echo ""
    echo "当前配置:"
    echo "编号: $num"
    echo "名称: $old_name"
    echo "URL: $old_url"
    echo "描述: $old_desc"
    echo ""

    read -p "新名称 [$old_name]: " new_name
    new_name=${new_name:-$old_name}

    read -p "新 URL [$old_url]: " new_url
    new_url=${new_url:-$old_url}

    read -p "新描述 [$old_desc]: " new_desc
    new_desc=${new_desc:-$old_desc}

    sed -i "/^${num}|/c\\${num}|${new_name}|${new_url}|${new_desc}|$(date '+%Y-%m-%d %H:%M:%S')" "$CONFIG_DIR/extensions.list"

    print_success "已更新"
    log_action "Edit extension script: $num - $new_name"
    sync_to_gist &>/dev/null || true

    sleep 1
}

test_extension_script() {
    echo ""
    read -p "输入要测试的编号: " num

    if [[ ! -f "$CONFIG_DIR/extensions.list" ]]; then
        print_error "无扩展脚本"
        sleep 2
        return
    fi

    local line
    line=$(grep "^${num}|" "$CONFIG_DIR/extensions.list")
    if [[ -z "$line" ]]; then
        print_error "未找到编号: $num"
        sleep 2
        return
    fi

    local url name
    url=$(echo "$line" | cut -d'|' -f3)
    name=$(echo "$line" | cut -d'|' -f2)

    run_extension_script "$url" "$name"
}

run_extension_script() {
    local url="$1"
    local name="$2"

    print_info "正在下载扩展脚本: $name"

    local temp_script
    temp_script="$(mktemp /tmp/tools-ext-XXXXXX.sh)"

    if curl -fsSL -o "$temp_script" "$url" 2>/dev/null || wget -q -O "$temp_script" "$url" 2>/dev/null; then
        print_success "下载完成"
        chmod +x "$temp_script"

        echo ""
        print_info "开始执行扩展脚本..."
        echo "----------------------------------------"

        bash "$temp_script"
        local exit_code=$?

        echo "----------------------------------------"

        if [[ $exit_code -eq 0 ]]; then
            print_success "扩展脚本执行完成"
        else
            print_error "扩展脚本执行失败 (退出码: $exit_code)"
        fi

        rm -f "$temp_script"

        log_action "Run extension script: $name (exit: $exit_code)"

        echo ""
        read -p "按回车继续..."
    else
        rm -f "$temp_script"
        print_error "下载失败，请检查 URL"
        sleep 2
    fi
}

# -------------------------
# 云同步（GitHub Gist） - 已完整实现 upload/download/restore
#   - 依赖 python3，用于安全 JSON 编码/解析
# -------------------------

setup_gist_sync() {
    clear
    print_header "GitHub Gist 云同步配置"
    echo ""

    if [[ -f "$SYNC_CONFIG" ]]; then
        # shellcheck disable=SC1090
        source "$SYNC_CONFIG"
        if [[ -n "$GIST_TOKEN" ]]; then
            print_info "云同步已启用"
            echo "Gist ID: ${GIST_ID:0:12}..."
            echo ""
            echo "[1] 立即同步"
            echo "[2] 从云端下载"
            echo "[3] 重新配置"
            echo "[4] 禁用同步"
            echo "[0] 返回"
            echo ""
            read -p "选择: " choice

            case $choice in
                1) sync_to_gist_manual ;;
                2) sync_from_gist ;;
                3) configure_gist_sync ;;
                4) disable_gist_sync ;;
                0) return ;;
            esac
            return
        fi
    fi

    configure_gist_sync
}

configure_gist_sync() {
    clear
    print_header "配置 GitHub Gist 同步"
    echo ""

    echo "步骤1: 获取 GitHub Token"
    echo "----------------------------------------"
    echo ""
    echo -e "${CYAN}📋 Token 生成链接:${NC}"
    echo -e "${GREEN}https://github.com/settings/tokens/new${NC}"
    echo ""
    echo "配置说明:"
    echo "1. Note: tools-sync"
    echo "2. Expiration: No expiration"
    echo "3. 勾选权限: gist"
    echo "4. 生成后复制 Token"
    echo ""
    echo "----------------------------------------"
    echo ""
    read -p "请输入 GitHub Token: " token

    if [[ -z "$token" ]]; then
        print_error "Token 不能为空"
        sleep 2
        return
    fi

    print_info "正在验证 Token..."

    local test_response
    test_response=$(curl -s -H "Authorization: token $token" https://api.github.com/user)
    local username
    username=$(echo "$test_response" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('login',''))" 2>/dev/null || echo "")

    if [[ -z "$username" ]]; then
        print_error "Token 验证失败，请检查 Token 是否正确"
        echo ""
        echo "常见错误:"
        echo "- Token 复制不完整"
        echo "- Token 没有勾选 gist 权限"
        echo "- Token 已过期或被删除"
        sleep 3
        return
    fi

    print_success "Token 有效，GitHub 用户: ${GREEN}$username${NC}"

    echo ""
    echo "步骤2: 同步模式"
    echo "----------------------------------------"
    echo "[1] 私有 Gist（推荐）"
    echo "[2] 公开 Gist"
    echo ""
    read -p "选择 [1]: " mode
    mode=${mode:-1}

    local is_public="false"
    if [[ $mode == "2" ]]; then
        is_public="true"
    fi

    echo ""
    print_info "正在创建 Gist..."

    local init_data
    init_data=$(cat <<JSON
{
  "version": "1.0.0",
  "last_update": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "sync_from": "$(hostname)",
  "scripts": [],
  "commands": [],
  "extensions": []
}
JSON
)

    # 使用 python3 构造并发送请求
    local gist_response
    gist_response=$(python3 - <<PY
import sys, json, urllib.request, urllib.error
token = "${token}"
is_public = ${is_public}
desc = "Tools Sync Data"
data = {
  "description": desc,
  "public": is_public,
  "files": {
    "tools-sync-data.json": {
      "content": '''${init_data}'''
    }
  }
}
req = urllib.request.Request("https://api.github.com/gists", data=json.dumps(data).encode("utf-8"), headers={
    "Authorization": "token " + token,
    "Content-Type": "application/json",
    "User-Agent": "tools-sync-script"
})
try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        print(resp.read().decode("utf-8"))
except Exception as e:
    print("ERROR:"+str(e))
PY
)

    local gist_id
    gist_id=$(echo "$gist_response" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null || echo "")

    if [[ -z "$gist_id" ]]; then
        print_error "创建 Gist 失败"
        echo ""
        echo "可能原因: Token 权限不足或网络问题"
        echo "错误信息:"
        echo "$gist_response" | head -n 20
        sleep 5
        return
    fi

    print_success "Gist 创建成功"
    echo ""
    echo "Gist ID: ${CYAN}$gist_id${NC}"
    if [[ $is_public == "true" ]]; then
        echo "Gist URL: ${GREEN}https://gist.github.com/$username/$gist_id${NC}"
    else
        echo "Gist URL: ${YELLOW}https://gist.github.com/$gist_id${NC} (私有)"
    fi

    # 保存配置
    cat > "$SYNC_CONFIG" <<EOF
GIST_TOKEN="$token"
GIST_ID="$gist_id"
GIST_PUBLIC="$is_public"
ENABLED="true"
EOF
    chmod 600 "$SYNC_CONFIG"

    echo ""
    print_success "云同步配置完成！"
    echo ""
    log_action "Configure Gist sync"

    echo ""
    read -p "按回车继续..."
}

# helper: 检查 python3
require_python3() {
    if ! command -v python3 &>/dev/null; then
        print_error "同步功能需要 python3，请先安装 (sudo apt-get install -y python3) 后重试。"
        return 1
    fi
    return 0
}

# sync_to_gist: 自动同步（异步调用也可以）
sync_to_gist() {
    if [[ ! -f "$SYNC_CONFIG" ]]; then
        return 0
    fi

    # shellcheck disable=SC1090
    source "$SYNC_CONFIG"

    if [[ "$ENABLED" != "true" ]]; then
        return 0
    fi

    require_python3 || return 0

    # 收集 scripts
    local scripts_json
    scripts_json="[]"
    if [[ -f "$CONFIG_DIR/scripts.list" ]]; then
        scripts_json="$(python3 - <<PY
import json,sys
out=[]
with open("$CONFIG_DIR/scripts.list",encoding="utf-8") as f:
    for line in f:
        line=line.rstrip("\n")
        if not line: continue
        parts=line.split("|")
        alias=parts[0] if len(parts)>0 else ""
        url=parts[1] if len(parts)>1 else ""
        desc=parts[2] if len(parts)>2 else ""
        added=parts[3] if len(parts)>3 else ""
        item={"alias":alias,"url":url,"description":desc,"added_time":added}
        # 如果为本地 paste，尝试读取 content
        if url.startswith("paste:"):
            pf="$PASTES_DIR/" + url.split("paste:")[1]
            try:
                with open(pf,encoding="utf-8") as pfh:
                    content=pfh.read()
                item["content"]=content
            except Exception:
                item["content"]=""
        out.append(item)
print(json.dumps(out,ensure_ascii=False))
PY
)"
    fi

    # 收集 commands
    local commands_json
    commands_json="[]"
    if [[ -f "$CONFIG_DIR/commands.list" ]]; then
        commands_json="$(python3 - <<PY
import json,sys
out=[]
with open("$CONFIG_DIR/commands.list",encoding="utf-8") as f:
    for line in f:
        line=line.rstrip("\n")
        if not line: continue
        parts=line.split("|")
        alias=parts[0] if len(parts)>0 else ""
        cmd=parts[1] if len(parts)>1 else ""
        typ=parts[2] if len(parts)>2 else ""
        cat=parts[3] if len(parts)>3 else ""
        out.append({"alias":alias,"command":cmd,"type":typ,"category":cat})
print(json.dumps(out,ensure_ascii=False))
PY
)"
    fi

    # 收集 extensions
    local extensions_json
    extensions_json="[]"
    if [[ -f "$CONFIG_DIR/extensions.list" ]]; then
        extensions_json="$(python3 - <<PY
import json,sys
out=[]
with open("$CONFIG_DIR/extensions.list",encoding="utf-8") as f:
    for line in f:
        line=line.rstrip("\n")
        if not line: continue
        parts=line.split("|")
        num=parts[0] if len(parts)>0 else ""
        name=parts[1] if len(parts)>1 else ""
        url=parts[2] if len(parts)>2 else ""
        desc=parts[3] if len(parts)>3 else ""
        added=parts[4] if len(parts)>4 else ""
        out.append({"number":num,"name":name,"url":url,"description":desc,"added_time":added})
print(json.dumps(out,ensure_ascii=False))
PY
)"
    fi

    # 生成 sync_data
    local sync_data
    sync_data=$(python3 - <<PY
import json,sys
data={
 "version":"1.0.0",
 "last_update":"%s",
 "sync_from":"%s",
 "scripts":%s,
 "commands":%s,
 "extensions":%s
}
print(json.dumps(data,ensure_ascii=False))
PY
"$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(hostname)" "$scripts_json" "$commands_json" "$extensions_json")

    # 把 sync_data 上传到 Gist
    # 先把内容字符串做 JSON 字符串转义
    local escaped
    escaped=$(python3 - <<PY
import json,sys
s=sys.stdin.read()
print(json.dumps(s))
PY
"$sync_data")

    local payload
    payload="{\"files\":{\"tools-sync-data.json\":{\"content\":$escaped}}}"

    local response
    response=$(curl -s -X PATCH \
        -H "Authorization: token $GIST_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "https://api.github.com/gists/$GIST_ID")

    # 简单判断是否成功（response 包含 id）
    if echo "$response" | grep -q "\"id\""; then
        # success
        log_action "Sync to Gist"
    else
        # failure logged
        log_action "Sync to Gist FAILED"
    fi
}

sync_to_gist_manual() {
    if [[ ! -f "$SYNC_CONFIG" ]]; then
        print_error "请先配置云同步"
        sleep 2
        return
    fi

    # shellcheck disable=SC1090
    source "$SYNC_CONFIG"

    if [[ "$ENABLED" != "true" ]]; then
        print_error "云同步未启用"
        sleep 2
        return
    fi

    require_python3 || return 0

    print_info "正在同步到云端..."

    sync_to_gist

    print_success "同步请求已发出（查看日志以确认）"
    sleep 1
}

# 从 Gist 下载并还原到本地（会覆盖本地 scripts/commands/extensions 对应文件）
sync_from_gist() {
    if [[ ! -f "$SYNC_CONFIG" ]]; then
        print_error "请先配置云同步"
        sleep 2
        return
    fi

    # shellcheck disable=SC1090
    source "$SYNC_CONFIG"

    require_python3 || return 0

    print_info "正在从云端下载..."

    local response
    response=$(curl -s -H "Authorization: token $GIST_TOKEN" "https://api.github.com/gists/$GIST_ID")

    # 解析出文件 content
    local content
    content=$(python3 - <<PY
import sys,json
j=json.load(sys.stdin)
files=j.get("files",{})
f=files.get("tools-sync-data.json",{})
print(f.get("content",""))
PY
<<<"$response")

    if [[ -z "$content" ]]; then
        print_error "下载失败或内容为空"
        sleep 2
        return
    fi

    # content 是 JSON 字符串，解析并写回本地配置
    python3 - <<PY
import json,sys,os
cfg_dir = "$CONFIG_DIR"
pastes_dir = "$PASTES_DIR"
data = json.loads("""$content""")
# 还原 scripts
scripts = data.get("scripts", [])
with open(os.path.join(cfg_dir,"scripts.list"),"w",encoding="utf-8") as sf:
    for s in scripts:
        alias = s.get("alias","")
        url = s.get("url","")
        desc = s.get("description","")
        added = s.get("added_time","")
        # 如果 content 字段存在（来自 paste），写本地文件并改写 url 为 paste:filename
        if not url and s.get("content"):
            name_safe = alias.replace(" ","_")[:20]
            fname = f"{name_safe}_{int(__import__('time').time())}.sh"
            os.makedirs(pastes_dir, exist_ok=True)
            pf = os.path.join(pastes_dir,fname)
            with open(pf,"w",encoding="utf-8") as ph:
                ph.write(s.get("content",""))
            url = "paste:"+fname
        elif s.get("content") and url.startswith("paste:")==False and url.startswith("http")==False:
            # 如果 url 为空但有 content
            name_safe = alias.replace(" ","_")[:20]
            fname = f"{name_safe}_{int(__import__('time').time())}.sh"
            os.makedirs(pastes_dir, exist_ok=True)
            pf = os.path.join(pastes_dir,fname)
            with open(pf,"w",encoding="utf-8") as ph:
                ph.write(s.get("content",""))
            url = "paste:"+fname
        sf.write(f"{alias}|{url}|{desc}|{added}\n")
# 还原 commands
commands = data.get("commands", [])
with open(os.path.join(cfg_dir,"commands.list"),"w",encoding="utf-8") as cf:
    for c in commands:
        alias = c.get("alias","")
        cmd = c.get("command","")
        typ = c.get("type","custom")
        cat = c.get("category","")
        cf.write(f"{alias}|{cmd}|{typ}|{cat}\n")
# 还原 extensions
extensions = data.get("extensions", [])
with open(os.path.join(cfg_dir,"extensions.list"),"w",encoding="utf-8") as exf:
    for e in extensions:
        num = e.get("number","")
        name = e.get("name","")
        url = e.get("url","")
        desc = e.get("description","")
        added = e.get("added_time","")
        exf.write(f"{num}|{name}|{url}|{desc}|{added}\n")
print("OK")
PY
    local ok=$?
    if [[ $ok -eq 0 ]]; then
        print_success "下载并还原成功（请检查脚本/命令是否符合预期）"
        log_action "Sync from Gist"
    else
        print_error "还原失败"
    fi

    echo ""
    read -p "按回车继续..."
}

disable_gist_sync() {
    read -p "确认禁用云同步? [y/N] " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        rm -f "$SYNC_CONFIG"
        print_success "云同步已禁用"
        log_action "Disable Gist sync"
        sleep 1
    fi
}

# -------------------------
# 命令行参数处理
# -------------------------
handle_cli_args() {
    case "$1" in
        --help|-h)
            echo "Tools v$VERSION - 服务器运维工具箱"
            echo ""
            echo "使用方法:"
            echo "  t              打开主菜单"
            echo "  t --cmd NAME   执行保存的命令"
            echo "  t --help       显示帮助"
            echo ""
            exit 0
            ;;
        --cmd)
            if [[ -z "$2" ]]; then
                print_error "请指定命令别名"
                exit 1
            fi

            if [[ ! -f "$CONFIG_DIR/commands.list" ]]; then
                print_error "未找到命令"
                exit 1
            fi

            local found=false
            while IFS='|' read -r alias cmd type category; do
                if [[ "$alias" == "$2" ]]; then
                    execute_command "$cmd" "$alias"
                    found=true
                    break
                fi
            done < "$CONFIG_DIR/commands.list"

            if [[ $found == false ]]; then
                print_error "未找到命令: $2"
                exit 1
            fi

            exit 0
            ;;
        --version|-v)
            echo "Tools v$VERSION"
            exit 0
            ;;
        "")
            # 无参数，显示主菜单
            return 0
            ;;
        *)
            print_error "未知参数: $1"
            echo "使用 t --help 查看帮助"
            exit 1
            ;;
    esac
}

# 主程序
main() {
    check_and_install
    init_config

    if [[ $# -gt 0 ]]; then
        handle_cli_args "$@"
    fi

    main_menu
}

main "$@"
# 一键安装命令 (复制粘贴到 SSH):
# ┌─────────────────────────────────────────────────────────────────────┐
# │ curl -fsSL https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/tools.sh -o tools.sh && chmod +x tools.sh && sudo ./tools.sh │
# └─────────────────────────────────────────────────────────────────────┘
#
# 或使用 wget:
# ┌─────────────────────────────────────────────────────────────────────┐
# │ wget -O tools.sh https://raw.githubusercontent.com/chf5762-sudo/bash/refs/heads/main/tools.sh && chmod +x tools.sh && sudo ./tools.sh │
# └─────────────────────────────────────────────────────────────────────┘
#