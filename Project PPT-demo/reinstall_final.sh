#!/usr/bin/env bash
set -e

# ==========================================
# KKFileView 终极救砖脚本 (Shotgun Mode)
# 策略：同时使用 环境变量 + 系统属性 + 启动参数 + 具体域名
# ==========================================

CONTAINER_NAME="kkfileview"
IMAGE="yimik/kkfileview:latest"
HOST_PORT=8012

# 关键：同时包含具体测试域名和通配符
# 注意：files.testfile.org 是你截图中报错的域名
# 更新：添加了用户的 WebDAV/Worker 域名
TRUST_DOMAINS="online-offcie.beundredig.eu.org,dark-sea-64ac.chf5762-32d.workers.dev,*.workers.dev,files.testfile.org,gongxue.cn,*"

echo "🛑 1. 清理旧环境..."
docker rm -f $CONTAINER_NAME 2>/dev/null || true

echo "🚀 2. 启动容器 (全方位参数覆盖)..."
# 解释：
# 1. -e KK_TRUST_HOST : 尝试覆盖配置文件里的 ${KK_TRUST_HOST}
# 2. -Dtrust.host     : 尝试通过 JVM 系统属性覆盖
# 3. --trust.host     : 尝试通过 Spring Boot 命令行参数覆盖 (优先级最高)
# 4. 同时指定了具体域名，防止 '*' 通配符在 Beta 版被禁用
docker run -d \
  --name $CONTAINER_NAME \
  -p $HOST_PORT:$HOST_PORT \
  -e KK_TRUST_HOST="$TRUST_DOMAINS" \
  --entrypoint "" \
  $IMAGE \
  sh -c "java -Dtrust.host=\"$TRUST_DOMAINS\" \
              -Dfile.encoding=UTF-8 \
              -Dspring.config.location=/opt/kkFileView-4.4.0-beta/config/application.properties \
              -jar /opt/kkFileView-4.4.0-beta/bin/kkFileView-4.4.0-beta.jar \
              --trust.host=\"$TRUST_DOMAINS\""

echo "⏳ 3. 等待服务启动 (15秒)..."
sleep 15

echo "🔎 4. 验证启动参数..."
PROCESS_INFO=$(docker exec $CONTAINER_NAME ps -ef | grep java)
echo "$PROCESS_INFO"

if echo "$PROCESS_INFO" | grep -q "files.testfile.org"; then
    echo "✅ 检测到 trust.host 参数已包含目标域名！"
else
    echo "❌ 警告：启动参数似乎未生效，请检查输出。"
fi

echo "========================================================"
echo "🎉 修复完成。请立刻测试："
echo "1. 使用 debug_kkfileview.html"
echo "2. URL 填入: https://files.testfile.org/PDF/10MB-TESTFILE.ORG.pdf"
echo "3. 点击 [方案 A] 生成链接"
echo "========================================================"
