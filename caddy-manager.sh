#!/bin/bash
# ============================================================
#  Caddy 综合管理与 SSL 自动化工具
#  用法: ./caddy_manager.sh <命令> [参数]
# ============================================================

CADDY_CONFIG="/etc/caddy/Caddyfile"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m' # Added CYAN color
NC='\033[0m'

# 1. 颜色与输出函数 (更名为专有的前缀，避免与系统命令如 msg_info 冲突)
msg_ok()   { echo -e "${GREEN}$1${NC}"; }
msg_warn() { echo -e "${YELLOW}$1${NC}"; }
msg_info() { echo -e "${CYAN}$1${NC}"; }
msg_err()  { echo -e "${RED}$1${NC}"; }

# 1.1 智能重载函数
reload_caddy() {
    msg_info "🔄 正在同步 Caddy 配置..."
    # 检查服务是否运行
    if ! systemctl is-active --quiet caddy; then
        msg_warn "⚠️ Caddy 当前处于停止状态，正在尝试启动..."
        systemctl start caddy && msg_ok "✅ Caddy 已成功启动" || msg_err "❌ 启动失败，请检查 Caddyfile 语法 (使用 caddy fmt 查看)"
    else
        # 尝试静默重载
        if caddy reload --config "$CADDY_CONFIG" >/dev/null 2>&1; then
            msg_ok "✅ 配置重载成功 (Hot Reload)"
        else
            msg_warn "⚠️ 热重载失败 (可能是端口被抢占)，正在尝试重启服务..."
            systemctl restart caddy && msg_ok "✅ Caddy 服务已重启" || msg_err "❌ 重启失败，建议检查 80/443 端口占用情况"
        fi
    fi
}

# 0. 安装与卸载 Caddy (Ubuntu/Debian)
install_caddy() {
    msg_ok "[INFO] 📥 正在准备安装官方 Caddy..."
    apt-get update
    apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null || true
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.debian.list' | tee /etc/apt/sources.list.d/caddy-stable.list
    apt-get update
    apt-get install -y caddy
    msg_ok "✅ Caddy 安装完成。"
}

uninstall_caddy() {
    msg_warn "🚨 这是一个危险操作，将卸载 Caddy 及其所有配置。确认请输入 'UNINSTALL'："
    read -r confirm
    if [ "$confirm" == "UNINSTALL" ]; then
        apt-get remove --purge -y caddy
        rm -rf /etc/caddy
        msg_ok "✅ Caddy 已卸载并清除配置。"
    else
        msg_ok "操作已取消。"
    fi
}

# 1. 环境自检
check_env() {
    msg_ok "🔎 正在执行系统环境审计..."
    
    # 检查 Caddy
    if command -v caddy >/dev/null; then
        msg_ok "✓ Caddy 已安装: $(caddy version | head -n1)"
    else
        msg_warn "✗ 未发现 Caddy 二进制文件"
    fi

    # 检查 Nginx
    if command -v nginx >/dev/null; then
        msg_warn "⚠ 发现 Nginx 已安装，可能存在端口冲突"
    else
        msg_ok "✓ 未发现 Nginx，减少了潜在冲突"
    fi

    # 检查 80/443 占用
    check_port 80
    check_port 443
}

check_port() {
    local port=$1
    # 仅查找处于 LISTEN 状态的本地监听进程
    local pids=$(lsof -t -i :$port -sTCP:LISTEN)
    if [ -n "$pids" ]; then
        for pid in $pids; do
            local proc=$(ps -p $pid -o comm= 2>/dev/null || echo "unknown")
            msg_err "⚠ 端口 $port 被占用! PID: $pid ($proc) [监听中]"
        done
    else
        msg_ok "✓ 端口 $port 目前可用 (无本地监听)"
    fi
}

# 2. 强行抢占端口 (暴力模式)
seize_ports() {
    msg_ok "🚀 正在尝试强行抢占 80/443 端口..."
    for port in 80 443; do
        local pids=$(lsof -t -i :$port -sTCP:LISTEN)
        if [ -n "$pids" ]; then
            msg_warn "正在终结占用 $port 端口的监听进程: $pids"
            kill -9 $pids 2>/dev/null || true
        fi
    done
    msg_ok "✅ 端口清理完毕，建议立即重启 Caddy"
}

# 2.4 辅助功能：寻找空闲端口
find_free_port() {
    local start_port=$1
    local port=$start_port
    while lsof -i :$port >/dev/null 2>&1; do
        port=$((port + 1))
    done
    echo $port
}

# 2.5 智能冲突自动修复 (识别 -> 关闭 -> 挪动 -> 重启)
fix_conflicts() {
    msg_ok "🤖 正在启动通用端口迁移程序..."
    local fixed=0
    for port in 80 443; do
        local pids=$(lsof -t -i :$port -sTCP:LISTEN)
        [ -z "$pids" ] && continue
        
        for pid in $pids; do
            local full_cmd=$(cat /proc/$pid/cmdline | xargs -0 echo 2>/dev/null)
            local comm=$(ps -p $pid -o comm= 2>/dev/null)
            
            msg_warn "────────────────────────────────────────"
            msg_warn "发现冲突进程: $comm (PID: $pid)"
            msg_warn "当前占用端口: $port"
            
            # 特殊处理：如果是关键系统组件，先提示
            if [[ "$full_cmd" == *"antigravity-server"* ]] || [[ "$full_cmd" == *"tailscaled"* ]]; then
                 msg_ok "ℹ️  识别为已知服务，将尝试安全迁移路径..."
            fi

            # 1. 寻找新端口
            local base_new_port=8081
            [ "$port" == "443" ] && base_new_port=444
            local new_port=$(find_free_port $base_new_port)
            msg_ok "📌 计划将该服务迁移至新端口: $new_port"

            # 2. 尝试构建新启动命令 (核心逻辑：替换参数中的端口)
            local new_cmd=$(echo "$full_cmd" | sed -E "s/([: =])$port([ $]|$)/\1$new_port\2/g")
            
            # 3. 执行迁移
            msg_warn "⚡ 正在关闭旧进程并尝试重新开启..."
            kill -9 $pid 2>/dev/null
            sleep 1
            
            # 4. 这里的重启比较复杂，如果是 systemd 管理的，其实很难通过脚本直接改参数
            # 我们这里尝试后台执行新命令
            nohup $new_cmd > /tmp/migrated_${comm}.msg_ok 2>&1 &
            
            msg_ok "✅ 迁移尝试完成！"
            msg_ok "   新命令: $new_cmd"
            msg_ok "   提示: 如果该服务是通过 systemd 管理的，请手动修改对应的 .service 文件以实现持久化。"
            fixed=$((fixed + 1))
        done
    done

    # 验证修复结果
    msg_ok "🏁 正在重新校验 80/443 状态..."
    sleep 1
    local still_blocked=0
    for port in 80 443; do
        if lsof -i :$port -sTCP:LISTEN >/dev/null; then
            msg_err "❌ 端口 $port 仍然处于监听状态！迁移未完全成功。"
            still_blocked=$((still_blocked + 1))
        fi
    done

    if [ $still_blocked -eq 0 ] && [ $fixed -gt 0 ]; then
        msg_ok "✨ 智能迁移已完成，所有监听冲突已清除。"
    elif [ $fixed -eq 0 ]; then
        msg_ok "👌 未发现需要迁移的本地监听服务。"
    fi
}

# 6. Basic Auth 开关 (默认无密码，启用时 admin:password)
toggle_basic_auth() {
    local domains=($(awk '/^[a-zA-Z0-9.-]+ \{/ {print $1}' "$CADDY_CONFIG"))
    if [ ${#domains[@]} -eq 0 ]; then
        msg_err "未找到任何域名配置"; return
    fi

    echo -e "\n请选择要操作的域名："
    for i in "${!domains[@]}"; do echo " $((i+1))) ${domains[$i]}"; done
    read -p "请选择域名序号: " d_idx
    if ! [[ "$d_idx" =~ ^[0-9]+$ ]] || [ "$d_idx" -lt 1 ] || [ "$d_idx" -gt ${#domains[@]} ]; then
        msg_err "无效选择"; return
    fi
    local domain=${domains[$((d_idx-1))]}

    # 检查当前是否已开启 basic_auth
    if sed -n "/^$domain {/,/^}/p" "$CADDY_CONFIG" | grep -q 'basic_auth'; then
        # 已启用 -> 关闭
        msg_warn "🔓 正在关闭 $domain 的 Basic Auth..."
        sed -i "/^$domain {/,/^}/ {
            /basic_auth {/,/^    }/d
        }" "$CADDY_CONFIG"
        msg_ok "✅ Basic Auth 已关闭 (无密码模式)"
    else
        # 未启用 -> 开启
        msg_ok "🔐 正在为 $domain 开启 Basic Auth (admin:password)..."
        local hash=$(caddy hash-password --plaintext "password" 2>/dev/null)
        # 在域名块的第一行后插入 basic_auth 块
        sed -i "/^$domain {/a\\    basic_auth {\n        admin $hash\n    }" "$CADDY_CONFIG"
        msg_ok "✅ Basic Auth 已启用 (用户: admin, 密码: password)"
    fi
    reload_caddy
}

# 7. 交互式菜单
show_menu() {
    clear
    echo -e "${CYAN}===========================================${NC}"
    echo -e "${CYAN}      🛡️  Caddy 智能网关管理系统 ${NC}"
    echo -e "${CYAN}===========================================${NC}"
    echo -e " 1) 🔍 环境审计 (Check)"
    echo -e " 2) 🤖 智能修复 (自动迁移冲突端口)"
    echo -e " 3) 🌐 主域名管理 (CRUD 域名头)"
    echo -e " 4) 📦 服务端口一键绑定"
    echo -e " 5) 🚥 查看 Caddy 运行状态"
    echo -e " 6) 📋 罗列所有详细配置"
    echo -e " 7) 🗑️  重置 Caddyfile"
    echo -e " 8) 📥 安装 Caddy"
    echo -e " 9) 🚮 卸载 Caddy"
    echo -e " a) 🔐 Basic Auth 开关 (默认无密码)"
    echo -e " 0) 🚪 退出"
    echo -e "${CYAN}-------------------------------------------${NC}"
    read -p " 请选择指令 [0-9/a]: " choice
    
    case $choice in
        1) check_env; read -p "按回车继续..."; show_menu ;;
        2) fix_conflicts; read -p "按回车继续..."; show_menu ;;
        3) domain_management_menu; show_menu ;;
        4) unified_workspace_bind; read -p "按回车继续..."; show_menu ;;
        5) caddy fmt "$CADDY_CONFIG" && systemctl status caddy; read -p "按回车继续..."; show_menu ;;
        6) list_configs; read -p "按回车继续..."; show_menu ;;
        7) clean_config; read -p "按回车继续..."; show_menu ;;
        8) install_caddy; read -p "按回车继续..."; show_menu ;;
        9) uninstall_caddy; read -p "按回车继续..."; show_menu ;;
        a) toggle_basic_auth; read -p "按回车继续..."; show_menu ;;
        0) exit 0 ;;
        *) show_menu ;;
    esac
}

# 3.1 主域名管理菜单 (CRUD)
domain_management_menu() {
    clear
    echo -e "${CYAN}===========================================${NC}"
    echo -e "${CYAN}       🌐 主域名管理中心 ${NC}"
    echo -e "${CYAN}===========================================${NC}"
    msg_ok "当前已配置的域名头："
    local domains=($(awk '/^[a-zA-Z0-9.-]+ \{/ {print $1}' "$CADDY_CONFIG"))
    if [ ${#domains[@]} -eq 0 ]; then
        msg_warn "   (暂无域名配置)"
    else
        for d in "${domains[@]}"; do echo -e "   • $d"; done
    fi
    echo -e "-------------------------------------------"
    echo -e " 1) ✨ 登记新域名"
    echo -e " 2) 🗑️  注销域名"
    echo -e " 3) 🔗 为特定端口快速绑定 HTTPS"
    echo -e " 0) 🔙 返回主菜单"
    echo -e "-------------------------------------------"
    read -p " 请选择指令 [0-3]: " dchoice
    case $dchoice in
        1) 
            read -p "请输入要登记的域名: " ndomain
            [ -n "$ndomain" ] && add_domain_head "$ndomain"
            domain_management_menu ;;
        2) 
            read -p "请输入要注销的域名: " rdomain
            [ -n "$rdomain" ] && delete_domain_binding "$rdomain"
            domain_management_menu ;;
        3) add_proxy_ui; domain_management_menu ;;
        0) return ;;
        *) domain_management_menu ;;
    esac
}

# 3.2 增加域名头 (空块)
add_domain_head() {
    local domain=$1
    if grep -q "^$domain {" "$CADDY_CONFIG"; then
        msg_warn "域名 $domain 已存在"
        return
    fi
    echo -e "\n$domain {\n    # 域名入口已创建，请使用一键绑定功能填充服务\n}" >> "$CADDY_CONFIG"
    msg_ok "✅ 域名头 $domain 已添加至配置文件。"
    reload_caddy
}

# 3. 罗列反代配置
list_configs() {
    msg_ok "📋 当前 Caddyfile 反代配置预览："
    if [ ! -f "$CADDY_CONFIG" ]; then
        msg_err "配置文件不存在: $CADDY_CONFIG"
        return
    fi
    echo "----------------------------------------"
    awk '/^[a-zA-Z0-9.-]+(:[0-9]+)? \{/ {print $1}' "$CADDY_CONFIG" | while read -r line; do
        echo -e "${YELLOW}➤${NC} $line"
    done
    echo "----------------------------------------"
}

# 5. 快速单一端口绑定 (Custom Port Bind)
add_proxy_ui() {
    # 询问域名
    local domains=($(awk '/^[a-zA-Z0-9.-]+ \{/ {print $1}' "$CADDY_CONFIG"))
    local target_domain=""
    if [ ${#domains[@]} -gt 0 ]; then
        echo "可用的域名头："
        for i in "${!domains[@]}"; do echo " $((i+1))) ${domains[$i]}"; done
        read -p "请选择域名序号 (或输入新域名): " d_input
        if [[ "$d_input" =~ ^[0-9]+$ ]] && [ "$d_input" -le ${#domains[@]} ]; then
            target_domain=${domains[$((d_input-1))]}
        else
            target_domain=$d_input
        fi
    else
        read -p "请输入要绑定的域名: " target_domain
    fi
    [ -z "$target_domain" ] && return

    msg_ok "🔍 正在扫描系统中活跃的监听服务..."
    echo -e "------------------------------------------------"
    echo -e " ID\t进程名\t\t端口"
    echo -e "------------------------------------------------"
    
    local services=($(lsof -nP -i -sTCP:LISTEN | grep -v "caddy" | grep -v ":22 " | awk 'NR>1 {print $1":"$9}' | sed 's/.*://' | sort -un))
    
    if [ ${#services[@]} -eq 0 ]; then
        msg_warn "未发现可用的非系统服务端口。"
        read -p "请输入手动指定的本地端口: " local_port
    else
        local i=1
        for port in "${services[@]}"; do
            local pname=$(lsof -i :$port -sTCP:LISTEN -t | xargs ps -p -o comm= 2>/dev/null | head -n1)
            echo -e " $i)\t${pname:-未知}\t\t$port"
            i=$((i + 1))
        done
        echo -e " c)\t手动输入自定义端口"
        echo -e "------------------------------------------------"
        read -p "请选择要绑定的服务编号 [1-$((${#services[@]}))]: " choice
        
        if [ "$choice" == "c" ]; then
            read -p "请输入自定义本地端口: " local_port
        else
            if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#services[@]} ]; then
                local_port=${services[$((choice-1))]}
            else
                msg_err "无效选择"
                return
            fi
        fi
    fi

    [ -z "$local_port" ] && return
    read -p "是否需要指定外部访问端口? (默认 443, 直接加回车跳过): " ext_port

    add_proxy "$target_domain" "$local_port" "$ext_port"
}

# 5.5 全系统实例扫描与打包绑定 (支持多用户追加)
unified_workspace_bind() {
    # 1. 首先确定域名
    local domains=($(awk '/^[a-zA-Z0-9.-]+ \{/ {print $1}' "$CADDY_CONFIG"))
    local main_domain=""
    if [ ${#domains[@]} -gt 0 ]; then
        echo -e "\n请选择用于绑定的域名头："
        for i in "${!domains[@]}"; do echo " $((i+1))) ${domains[$i]}"; done
        read -p "请选择序号 (或直接输入新域名): " d_idx
        if [[ "$d_idx" =~ ^[0-9]+$ ]] && [ "$d_idx" -le ${#domains[@]} ]; then
            main_domain=${domains[$((d_idx-1))]}
        else
            main_domain=$d_idx
        fi
    else
        read -p "请输入要绑定的主域名: " main_domain
    fi
    [ -z "$main_domain" ] && return

    msg_ok "📦 正在执行全系统服务审计与实例探测..."
    
    local instance_names=()
    local instance_ports=()
    local instance_types=()
    local instance_descs=()

    # 1.1 探测 Docker 容器
    while read -r line; do
        [ -z "$line" ] && continue
        local name=$(echo "$line" | awk '{print $1}')
        local port_info=$(echo "$line" | cut -d' ' -f2-)
        local ports=$(echo "$port_info" | grep -oP '\d+(?=->)' | sort -un | tr '\n' ',' | sed 's/,$//')
        if [ -n "$ports" ]; then
            instance_names+=("$name")
            instance_ports+=("$ports")
            instance_types+=("Docker")
            instance_descs+=("容器实例: $name")
        fi
    done < <(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null)

    # 1.2 探测其他监听进程
    while read -r line; do
        [ -z "$line" ] && continue
        local pname=$(echo "$line" | awk '{print $1}')
        local port=$(echo "$line" | awk '{print $3}' | sed 's/.*://')
        if [[ "$pname" != "caddy" && "$pname" != "sshd" && "$pname" != "docker-pr" ]]; then
            local desc="$pname 服务"
            [[ "$pname" == "node" ]] && desc="Node.js 应用"
            [[ "$pname" == "python"* ]] && desc="Python 应用"
            [[ "$pname" == "tailscale"* ]] && desc="Tailscale 服务"
            
            local found=0
            for i in "${!instance_names[@]}"; do
                if [[ "${instance_names[$i]}" == "$pname" && "${instance_types[$i]}" == "Process" ]]; then
                    if [[ ! "${instance_ports[$i]}" =~ (^|,)$port(,|$) ]]; then
                        instance_ports[$i]="${instance_ports[$i]},$port"
                    fi
                    found=1; break
                fi
            done
            if [ $found -eq 0 ]; then
                instance_names+=("$pname"); instance_ports+=("$port")
                instance_types+=("Process"); instance_descs+=("$desc")
            fi
        fi
    done < <(lsof -nP -i -sTCP:LISTEN | awk 'NR>1 {print $1" "$2" "$9}')

    if [ ${#instance_names[@]} -eq 0 ]; then
        msg_err "未发现任何活跃的服务实例。"
        return
    fi

    echo -e "\n-------------------------------------------------------------------------"
    printf " %-3s %-10s %-20s %-25s %-15s\n" "ID" "类型" "实例标识" "描述" "端口"
    echo -e "-------------------------------------------------------------------------"
    for i in "${!instance_names[@]}"; do
        printf " %-3d [%-8s] %-20s %-25s %-15s\n" "$((i+1))" "${instance_types[$i]}" "${instance_names[$i]}" "${instance_descs[$i]}" "${instance_ports[$i]}"
    done
    echo -e "-------------------------------------------------------------------------"
    read -p " 请选择要配置的实例 ID: " idx
    
    if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt ${#instance_names[@]} ]; then
        msg_err "无效选择"; return
    fi

    local selected_name=${instance_names[$((idx-1))]}
    local ports_str=${instance_ports[$((idx-1))]}
    IFS=',' read -r -a ports_arr <<< "$ports_str"

    msg_ok "发现实例 $selected_name 共有 ${#ports_arr[@]} 个端口: $ports_str"
    msg_warn "请输入对应的子路径映射名 (用逗号隔开，顺序对应上述端口):"
    read -p "例如 vnc,cdp,api -> 输入 'vnc,cdp,api': " paths_str
    IFS=',' read -r -a paths_arr <<< "$paths_str"

    if [ ${#paths_arr[@]} -ne ${#ports_arr[@]} ]; then
        msg_err "数量不匹配！"; return
    fi

    # ── 核心逻辑：追加模式（支持多用户）──
    local domain_exists=0
    grep -q "^$main_domain {" "$CADDY_CONFIG" && domain_exists=1

    # 构建新路由块
    local new_routes=""
    for i in "${!ports_arr[@]}"; do
        local p=${ports_arr[$i]}
        local path=${paths_arr[$i]}

        # 如果路径已存在，先删除旧的（更新模式）
        if [ $domain_exists -eq 1 ]; then
            sed -i "/^$main_domain {/,/^}/ {
                /redir \/$path /d
            }" "$CADDY_CONFIG"
            # 删除对应的 handle_path 块
            sed -i "/^$main_domain {/,/^}/ {
                /handle_path \/$path\/\* {/,/^    }/d
            }" "$CADDY_CONFIG"
        fi

        # 拼接新路由
        new_routes+="    redir /$path /$path/ 308\n"
        new_routes+="    handle_path /$path/* {\n"
        # VNC 自动 rewrite 首页
        if [[ "$p" == "6080" ]] || [[ "$path" == *"vnc"* ]]; then
            new_routes+="        rewrite / /vnc.html\n"
        fi
        new_routes+="        reverse_proxy localhost:$p {\n"
        new_routes+="            header_up Host {upstream_hostport}\n"
        new_routes+="        }\n"
        new_routes+="    }\n"
    done

    if [ $domain_exists -eq 1 ]; then
        # 追加到现有域名块的闭合 } 之前
        # 找到该域名块的最后一个 } 并在其前插入
        sed -i "/^$main_domain {/,/^}/ {
            /^}/i\\
$(echo -e "$new_routes" | sed 's/$/\\/' | sed '$ s/\\$//')
        }" "$CADDY_CONFIG"
        msg_ok "✅ 路由已追加到现有域名 $main_domain (已有路由不受影响)"
    else
        # 创建新域名块
        echo -e "\n$main_domain {" >> "$CADDY_CONFIG"
        echo -e "$new_routes" >> "$CADDY_CONFIG"
        echo "}" >> "$CADDY_CONFIG"
        msg_ok "✅ 新域名 $main_domain 已创建"
    fi

    reload_caddy || msg_err "重载失败"

    msg_ok "---------------------------------------------------------"
    msg_ok "🚀 访问地址清单 (直接访问即可)："
    for i in "${!paths_arr[@]}"; do
        local path=${paths_arr[$i]}
        msg_info "   🔗 /$path → https://$main_domain/$path"
    done
    msg_ok "---------------------------------------------------------"
}

# 5.6 删除域名绑定
delete_domain_binding() {
    local domain=$1
    if [ -z "$domain" ]; then
        list_configs
        read -p "请输入要注销的域名: " domain
    fi
    [ -z "$domain" ] && return
    
    if ! grep -q "$domain {" "$CADDY_CONFIG"; then
        msg_err "未找到域名 $domain 的配置头。"
        return
    fi
    
    msg_warn "确认注销域名 $domain 并在配置文件中将其移除？(YES/NO): "
    read -r confirm
    if [ "$confirm" == "YES" ]; then
        # 匹配从域名开始到闭括号的块
        sed -i "/^$domain {/,/^}/d" "$CADDY_CONFIG"
        msg_ok "✅ 已移除域名配置: $domain"
        reload_caddy
    else
        msg_ok "操作已取消"
    fi
}

delete_domain_ui() {
    delete_domain_binding
}

# 4. 清理配置 (备份并清空或交互式清理)
clean_config() {
    local backup="${CADDY_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$CADDY_CONFIG" "$backup"
    msg_ok "📦 已创建备份: $backup"
    msg_warn "请输入 'YES' 确认清空当前 Caddyfile 重新开始："
    read -r confirm
    if [ "$confirm" == "YES" ]; then
        echo -e "# Caddy Config (Started by caddy_manager)\n{\n    email admin@example.com\n}\n" > "$CADDY_CONFIG"
        msg_ok "✅ 配置文件已初始化"
    else
        msg_ok "操作已取消"
    fi
}

# 5. 自动添加反代
add_proxy() {
    local domain=$1
    local local_port=$2
    local external_port=$3
    
    if [ -z "$domain" ] || [ -z "$local_port" ]; then
        msg_err "用法: add-proxy <域名> <本地端口> [外部端口]"
        return 1
    fi

    local entry="$domain"
    [ -n "$external_port" ] && entry="$domain:$external_port"

    # 检查是否已存在
    if grep -q "$entry" "$CADDY_CONFIG"; then
        msg_warn "域名配置 $entry 已存在，跳过添加"
        return
    fi

    cat >> "$CADDY_CONFIG" <<EOF

$entry {
    reverse_proxy localhost:$local_port
}
EOF
    msg_ok "✅ 已添加反代: $entry -> localhost:$local_port"
    msg_ok "🔄 正在重载配置..."
    reload_caddy || msg_err "重载失败，请检查 Caddy 状态"
}

# 主逻辑
case "$1" in
    seize) seize_ports ;;
    fix)   fix_conflicts ;;
    list)  list_configs ;;
    clean) clean_config ;;
    add-proxy) add_proxy "$2" "$3" "$4" ;;
    status) caddy fmt "$CADDY_CONFIG" && systemctl status caddy ;;
    install) install_caddy ;;
    uninstall) uninstall_caddy ;;
    check) check_env ;;
    auth) toggle_basic_auth ;;
    menu) show_menu ;;
    *) 
        if [ -z "$1" ]; then
            show_menu
        else
            echo "用法: $0 {check|fix|seize|list|clean|add-proxy|status|auth|menu}"
        fi
        ;;
esac
