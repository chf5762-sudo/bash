# KKFileView 4.x 部署与白名单修复总结

## ✅ 最终状态
经过多次调试，确认 `yimik/kkfileview:latest` (基于 4.4.0-beta) 存在**环境变量注入失效**及**通配符信任机制不稳定**的问题。

目前的解决方案已成功：
- ❌ **直接 URL 访问**：会报 500 错误（预期行为，强制要求 Base64）。
- ❌ **单纯使用 `*` 通配符**：在部分 Beta 版本中可能失效。
- ✅ **Base64 + 显式域名白名单**：成功绕过 "不受信任" 限制，服务正常运行。

## 🛠️ 核心问题回顾
1. **环境变量失效**：Docker 的 `-e KK_TRUST_HOST` 参数未能被 Spring Boot 正确读取。
2. **JVM 参数优先级**：必须通过 `java -Dtrust.host=...` 或启动参数 `--trust.host=...` 强制覆盖配置。
3. **URL 编码要求**：前端必须使用 `encodeURIComponent(Base64.encode(url))` 格式。

## 🚀 最终部署脚本 (生产可用)

为了确保稳健性，我们采用 **Shotgun (三重注入)** 策略：同时在「环境变量」、「系统属性」和「启动参数」中注入配置，并显式指定域名。

可以将此脚本保存为 `deploy_kkfileview.sh` 用于日后重装：

```bash
#!/usr/bin/env bash
set -e

# --- 配置区域 ---
CONTAINER_NAME="kkfileview"
IMAGE="yimik/kkfileview:latest"
HOST_PORT=8012

# 关键技巧：
# 1. 显式列出常用文件域名 (如 files.testfile.org, github.com 等)
# 2. 末尾保留 *, 以尝试兼容其他未知域名
TRUST_DOMAINS="files.testfile.org,gongxue.cn,github.com,*"
# ----------------

echo "🛑 清理旧容器..."
docker rm -f $CONTAINER_NAME 2>/dev/null || true

echo "🚀启动容器 (Triple Override Mode)..."
# 解释：
# -Dtrust.host : JVM 系统属性 (高优先级)
# --trust.host : Spring Boot 参数 (最高优先级)
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

echo "✅ 部署完成！等待约 20 秒服务启动。"
```

## 🔌 前端调用规范

前端代码必须严格遵循以下编码方式，否则会导致 500 错误或乱码：

```javascript
/**
 * 生成 KKFileView 预览链接
 * @param {string} fileUrl - 原始文件地址 (如 https://example.com/a.pdf)
 * @param {string} kkServer - KK服务器地址 (如 http://vps:8012)
 */
function getPreviewUrl(fileUrl, kkServer) {
    // 1. 使用兼容性最好的 Base64 编码 (处理中文)
    const b64 = window.btoa(unescape(encodeURIComponent(fileUrl)));
    
    // 2. 对 Base64 字符串再次进行 URL 编码
    const finalParam = encodeURIComponent(b64);
    
    // 3. 拼接
    return `${kkServer}/onlinePreview?url=${finalParam}`;
}
```

## 📝 维护备忘
- 如果未来需要添加新的文件源（如阿里云 OSS、WebDAV），请修改脚本中的 `TRUST_DOMAINS` 变量并重新运行部署脚本。
- 页面显示空白通常是因为文件加载慢或文件本身内容无法解析，只要不报错 "不受信任"，说明服务网关已打通。
