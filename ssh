#!/bin/bash

set -e

CADDY_DIR="$HOME/caddy"
CADDYFILE="$CADDY_DIR/Caddyfile"
PORTS_FILE="$CADDY_DIR/ports.conf"

# 初始化
init_caddy() {
    mkdir -p $CADDY_DIR
    
    # 如果是第一次部署，询问域名并停止旧服务
    if [ ! -f "$PORTS_FILE" ]; then
        echo "=========================================="
        echo "Caddy Docker 多端口管理脚本 - 首次部署"
        echo "=========================================="
        echo ""
        
        read -p "请输入你的域名 (例如: vps1.chf5762.cloudns.org): " DOMAIN
        echo "$DOMAIN" > $CADDY_DIR/domain.conf
        
        echo ""
        echo "[初始化] 停止现有的 Caddy 服务..."
        sudo systemctl stop caddy 2>/dev/null || true
        sudo systemctl disable caddy 2>/dev/null || true
        sleep 2
        
        echo "[初始化] 创建 Docker 卷..."
        docker volume create caddy_data 2>/dev/null || true
        docker volume create caddy_config 2>/dev/null || true
        
        echo "[初始化] 停止旧的 Caddy 容器..."
        docker stop caddy 2>/dev/null || true
        docker rm caddy 2>/dev/null || true
        sleep 2
        
        touch $PORTS_FILE
        echo "[初始化] 完成！"
    fi
}

# 获取域名
get_domain() {
    if [ -f "$CADDY_DIR/domain.conf" ]; then
        cat $CADDY_DIR/domain.conf
    else
        echo "域名未配置"
        exit 1
    fi
}

# 生成 Caddyfile
generate_caddyfile() {
    local domain=$(get_domain)
    > $CADDYFILE
    
    if [ -f "$PORTS_FILE" ]; then
        while IFS=':' read -r port service; do
            if [ ! -z "$port" ] && [ ! -z "$service" ]; then
                cat >> $CADDYFILE << EOF
$domain:$port {
    tls internal
    reverse_proxy $service
}

EOF
            fi
        done < $PORTS_FILE
    fi
}

# 启动或重启容器
start_caddy() {
    generate_caddyfile
    
    if [ ! -s "$CADDYFILE" ]; then
        echo "✗ 错误：Caddyfile 为空，请先添加端口"
        return 1
    fi
    
    echo "启动 Caddy 容器..."
    docker stop caddy 2>/dev/null || true
    docker rm caddy 2>/dev/null || true
    sleep 1
    
    docker run -d \
      --name caddy \
      --restart unless-stopped \
      --network host \
      -v $CADDYFILE:/etc/caddy/Caddyfile \
      -v caddy_data:/data \
      -v caddy_config:/config \
      caddy:latest
    
    sleep 3
    
    if docker ps | grep -q caddy; then
        echo "✓ Caddy 容器已启动"
        sleep 5
        docker logs caddy | tail -20
        return 0
    else
        echo "✗ 启动失败"
        docker logs caddy
        return 1
    fi
}

# 添加端口
add_port() {
    local port=$1
    local service=$2
    
    if grep -q "^$port:" $PORTS_FILE 2>/dev/null; then
        echo "✗ 端口 $port 已存在"
        return 1
    fi
    
    echo "$port:$service" >> $PORTS_FILE
    echo "✓ 已添加：端口 $port -> $service"
    
    if start_caddy; then
        docker exec caddy caddy reload --config /etc/caddy/Caddyfile
        echo "✓ 配置已生效"
    fi
}

# 删除端口
delete_port() {
    local port=$1
    
    if ! grep -q "^$port:" $PORTS_FILE 2>/dev/null; then
        echo "✗ 端口 $port 不存在"
        return 1
    fi
    
    grep -v "^$port:" $PORTS_FILE > $PORTS_FILE.tmp
    mv $PORTS_FILE.tmp $PORTS_FILE
    echo "✓ 已删除：端口 $port"
    
    if start_caddy; then
        docker exec caddy caddy reload --config /etc/caddy/Caddyfile
        echo "✓ 配置已生效"
    fi
}

# 列出所有端口
list_ports() {
    local domain=$(get_domain)
    echo ""
    echo "=========================================="
    echo "已配置的端口列表"
    echo "=========================================="
    echo "域名: $domain"
    echo ""
    
    if [ ! -f "$PORTS_FILE" ] || [ ! -s "$PORTS_FILE" ]; then
        echo "暂无配置的端口"
        return
    fi
    
    echo "端口号 | 后端服务地址"
    echo "------|---------------"
    
    while IFS=':' read -r port service; do
        if [ ! -z "$port" ] && [ ! -z "$service" ]; then
            printf "%-6s | %s\n" "$port" "$service"
            echo "       访问地址: https://$domain:$port"
        fi
    done < $PORTS_FILE
    
    echo ""
}

# 显示使用帮助
show_help() {
    cat << EOF
=========================================="
Caddy Docker 多端口管理脚本"
=========================================="

使用方法：
  $0 [命令] [参数]

命令：
  add <端口号> <服务地址>     添加新端口 (例: add 4444 localhost:4444)
  del <端口号>              删除指定端口 (例: del 4444)
  list                      列出所有已配置的端口
  help                      显示此帮助信息

示例：
  $0 add 4444 localhost:4444
  $0 add 5555 localhost:5555
  $0 add 6666 localhost:6666
  $0 list
  $0 del 5555
  $0 list

常用 Docker 命令：
  docker logs -f caddy                              查看实时日志
  docker restart caddy                              重启容器
  docker exec caddy caddy reload --config /etc/caddy/Caddyfile  重新加载配置

EOF
}

# 主程序
init_caddy

case "$1" in
    add)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "✗ 用法: $0 add <端口号> <服务地址>"
            echo "  例如: $0 add 4444 localhost:4444"
            exit 1
        fi
        add_port "$2" "$3"
        ;;
    del|delete)
        if [ -z "$2" ]; then
            echo "✗ 用法: $0 del <端口号>"
            echo "  例如: $0 del 4444"
            exit 1
        fi
        delete_port "$2"
        ;;
    list)
        list_ports
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_help
        exit 1
        ;;
esac
