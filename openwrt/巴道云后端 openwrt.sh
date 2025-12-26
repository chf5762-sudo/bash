#!/bin/sh

PRIVATE_KEY="3eb42d69d8b226abe22024d648975f8a"
TOPIC="ppt001"
MQTT_HOST="bemfa.com"
MQTT_PORT="9501"
PID_FILE="/var/run/bemfa_mqtt.pid"
LOG_FILE="/tmp/bemfa_messages.log"
SUBSCRIBE_LOG="/tmp/bemfa_subscribe.log"
MAX_LOG_LINES=100

# 检查mosquitto_sub进程是否在运行
is_running() {
    pgrep -f "mosquitto_sub.*$TOPIC" >/dev/null 2>&1
}

start() {
    if is_running; then
        echo "✓ 巴法云MQTT订阅已在运行"
        return 0
    fi
    
    echo "启动巴法云MQTT订阅..."
    touch "$LOG_FILE"
    touch "$SUBSCRIBE_LOG"
    
    # 后台运行
    sh -c "
        while true; do
            mosquitto_sub -h $MQTT_HOST -p $MQTT_PORT -i $PRIVATE_KEY -t '$TOPIC' -v 2>&1 | while IFS= read -r line; do
                TIMESTAMP=\"[\$(date '+%Y-%m-%d %H:%M:%S')]\"
                
                # 写入消息历史
                echo \"\$TIMESTAMP \$line\" >> '$LOG_FILE'
                tail -n $MAX_LOG_LINES '$LOG_FILE' > '${LOG_FILE}.tmp' && mv '${LOG_FILE}.tmp' '$LOG_FILE'
                
                # 写入订阅消息（只记录收到的消息，不含发送的）
                echo \"\$TIMESTAMP \$line\" >> '$SUBSCRIBE_LOG'
                tail -n $MAX_LOG_LINES '$SUBSCRIBE_LOG' > '${SUBSCRIBE_LOG}.tmp' && mv '${SUBSCRIBE_LOG}.tmp' '$SUBSCRIBE_LOG'
            done
            echo \"[\$(date '+%Y-%m-%d %H:%M:%S')] 连接断开,5秒后重连...\" >> '$LOG_FILE'
            sleep 5
        done
    " >/dev/null 2>&1 &
    
    MAIN_PID=$!
    echo $MAIN_PID > "$PID_FILE"
    sleep 2
    
    if is_running; then
        REAL_PID=$(pgrep -f "mosquitto_sub.*$TOPIC")
        echo "✓ 启动成功"
        echo "  主进程PID: $MAIN_PID"
        echo "  订阅进程PID: $REAL_PID"
        echo "  主题: $TOPIC"
        echo "  消息日志: $LOG_FILE"
        echo "  订阅日志: $SUBSCRIBE_LOG"
    else
        echo "✗ 启动失败,请检查mosquitto_sub是否已安装"
        rm -f "$PID_FILE"
        return 1
    fi
}

stop() {
    if ! is_running; then
        echo "✗ 未运行"
        rm -f "$PID_FILE"
        return 1
    fi
    
    echo "停止巴法云MQTT订阅..."
    
    # 杀死主进程
    if [ -f "$PID_FILE" ]; then
        kill $(cat "$PID_FILE") 2>/dev/null
    fi
    
    # 杀死所有相关进程
    pkill -f "mosquitto_sub.*$TOPIC"
    
    rm -f "$PID_FILE"
    sleep 1
    
    if is_running; then
        echo "✗ 停止失败,强制结束..."
        pkill -9 -f "mosquitto_sub.*$TOPIC"
    else
        echo "✓ 已停止"
    fi
}

status() {
    if is_running; then
        PID=$(pgrep -f "mosquitto_sub.*$TOPIC")
        MSG_COUNT=0
        SUB_COUNT=0
        [ -f "$LOG_FILE" ] && MSG_COUNT=$(wc -l < "$LOG_FILE")
        [ -f "$SUBSCRIBE_LOG" ] && SUB_COUNT=$(wc -l < "$SUBSCRIBE_LOG")
        
        echo "✓ 运行中"
        echo "  进程PID: $PID"
        echo "  主题: $TOPIC"
        echo "  服务器: $MQTT_HOST:$MQTT_PORT"
        echo "  消息历史: $MSG_COUNT 条"
        echo "  订阅消息: $SUB_COUNT 条"
        return 0
    else
        echo "✗ 未运行"
        rm -f "$PID_FILE"
        return 1
    fi
}

send() {
    if [ -z "$1" ]; then
        echo "用法: $0 send <消息内容>"
        return 1
    fi
    
    echo "发送消息: $1"
    mosquitto_pub -h $MQTT_HOST -p $MQTT_PORT -i $PRIVATE_KEY -t "$TOPIC" -m "$1"
    
    if [ $? -eq 0 ]; then
        echo "✓ 发送成功"
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [发送] $TOPIC $1" >> "$LOG_FILE"
    else
        echo "✗ 发送失败"
        return 1
    fi
}

show_log() {
    if [ -f "$LOG_FILE" ]; then
        cat "$LOG_FILE"
    else
        echo "日志文件不存在"
    fi
}

clear_log() {
    > "$LOG_FILE"
    > "$SUBSCRIBE_LOG"
    echo "✓ 日志已清空"
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        sleep 2
        start
        ;;
    status)
        status
        ;;
    send)
        send "$2"
        ;;
    log)
        show_log
        ;;
    clear)
        clear_log
        ;;
    *)
        echo "巴法云MQTT客户端管理脚本"
        echo ""
        echo "用法: $0 {start|stop|restart|status|send|log|clear}"
        echo ""
        echo "命令:"
        echo "  start           启动MQTT订阅"
        echo "  stop            停止MQTT订阅"
        echo "  restart         重启MQTT订阅"
        echo "  status          查看运行状态"
        echo "  send <消息>     发送消息到主题"
        echo "  log             查看消息日志"
        echo "  clear           清空消息日志"
        exit 1
        ;;
esac
