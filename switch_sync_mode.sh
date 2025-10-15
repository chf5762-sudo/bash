#!/bin/bash

# 阿里云盘同步模式切换脚本
# 用法: ./switch_sync_mode.sh

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SERVICE_FILE="/etc/systemd/system/aliyunpan-sync.service"

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}请使用 root 用户或 sudo 运行此脚本${NC}"
    exit 1
fi

# 检查服务文件是否存在
if [ ! -f "$SERVICE_FILE" ]; then
    echo -e "${RED}未找到 aliyunpan-sync 服务文件!${NC}"
    echo "请先运行安装脚本"
    exit 1
fi

echo -e "${GREEN}=========================================="
echo "阿里云盘同步模式切换"
echo "==========================================${NC}"
echo ""

# 检查当前模式
CURRENT_MODE=$(grep "mode" $SERVICE_FILE | grep -oP '(?<=-mode )\w+')

echo -e "${YELLOW}当前同步模式: ${CURRENT_MODE}${NC}"
echo ""
echo "同步模式说明:"
echo "  1) download - 单向下载(云盘→VPS) ✅ 安全,云盘文件不会被删除"
echo "  2) upload   - 单向上传(VPS→云盘) ⚠️  VPS本地文件上传到云盘"
echo "  3) sync     - 双向同步 ⚠️  危险!删除操作会同步"
echo ""

read -p "请选择新的同步模式 (1/2/3): " choice

case $choice in
    1)
        NEW_MODE="download"
        ;;
    2)
        NEW_MODE="upload"
        ;;
    3)
        NEW_MODE="sync"
        echo ""
        echo -e "${RED}⚠️  警告: 双向同步模式下:${NC}"
        echo "  - VPS删除文件会同步删除云盘文件"
        echo "  - 云盘删除文件会同步删除VPS文件"
        echo "  - 可能导致数据丢失!"
        echo ""
        read -p "确认切换到双向同步模式? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo "已取消操作"
            exit 0
        fi
        ;;
    *)
        echo -e "${RED}无效的选择${NC}"
        exit 1
        ;;
esac

if [ "$CURRENT_MODE" == "$NEW_MODE" ]; then
    echo -e "${YELLOW}当前已经是 ${NEW_MODE} 模式,无需切换${NC}"
    exit 0
fi

echo ""
echo -e "${YELLOW}开始切换到 ${NEW_MODE} 模式...${NC}"

# 1. 停止同步服务
echo "1. 停止同步服务..."
systemctl stop aliyunpan-sync
aliyunpan sync stop 2>/dev/null || true

# 2. 修改配置文件
echo "2. 修改配置文件..."
sed -i "s/-mode ${CURRENT_MODE}/-mode ${NEW_MODE}/g" $SERVICE_FILE

# 3. 重新加载配置
echo "3. 重新加载配置..."
systemctl daemon-reload

# 4. 启动服务
echo "4. 启动同步服务..."
systemctl start aliyunpan-sync

# 等待服务启动
sleep 2

# 5. 检查状态
echo ""
if systemctl is-active --quiet aliyunpan-sync; then
    echo -e "${GREEN}✓ 切换成功!${NC}"
    echo ""
    echo -e "${GREEN}新的同步模式: ${NEW_MODE}${NC}"
    echo ""
    echo "查看同步日志: journalctl -u aliyunpan-sync -f"
    echo "查看服务状态: systemctl status aliyunpan-sync"
    echo "查看同步任务: aliyunpan sync status"
    
    # 如果是双向同步,显示测试命令
    if [ "$NEW_MODE" == "sync" ]; then
        echo ""
        echo -e "${YELLOW}测试双向同步:${NC}"
        echo "在VPS创建文件: echo 'test' > /root/AliyunDisk/test.txt"
        echo "几秒后在云盘App查看是否出现该文件"
    fi
else
    echo -e "${RED}✗ 服务启动失败${NC}"
    echo "请查看日志: journalctl -u aliyunpan-sync -n 50"
    exit 1
fi
