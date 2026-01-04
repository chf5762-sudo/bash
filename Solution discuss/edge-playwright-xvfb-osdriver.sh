#!/bin/bash

# 1. 准备工作：创建目录并进入
mkdir -p ~/playwright_service && cd ~/playwright_service

# 2. 编写 Dockerfile (整合 pip3、图形组件及路径修复)
cat <<EOF > Dockerfile
FROM mcr.microsoft.com/playwright:v1.49.0-noble

# 安装核心组件
RUN apt-get update && apt-get install -y \\
    python3-pip \\
    xvfb x11vnc fluxbox novnc websockify \\
    && apt-get clean

# 修复 Python 环境依赖
RUN pip3 install playwright --break-system-packages

WORKDIR /app

# 设置 VNC 访问密码
RUN mkdir -p ~/.vnc && x11vnc -storepasswd password ~/.vnc/passwd

ENV DISPLAY=:99
ENV PYTHONUNBUFFERED=1

# 核心启动指令：清理 X 锁文件并启动所有服务
CMD ["sh", "-c", "rm -f /tmp/.X99-lock; Xvfb :99 -screen 0 1280x720x24 & sleep 2 && fluxbox & x11vnc -display :99 -forever -rfbauth ~/.vnc/passwd -listen 0.0.0.0 -rfbport 5900 & /usr/share/novnc/utils/novnc_proxy --vnc localhost:5900 --listen 6080 & python3 main.py"]
EOF

# 3. 编写 docker-compose.yml (支持开机自启与状态挂载)
cat <<EOF > docker-compose.yml
services:
  browser_bot:
    build: .
    container_name: playwright_robot
    restart: always
    shm_size: '2gb'
    ports:
      - "6080:6080"
    volumes:
      - .:/app
EOF

# 4. 编写 main.py (包含 4 窗口自动开启与登录保持逻辑)
cat <<EOF > main.py
import time
from playwright.sync_api import sync_playwright

def run_task():
    with sync_playwright() as p:
        print(">>> 正在启动持久化浏览器实例...")
        # 配置持久化目录以保存登录状态
        context = p.chromium.launch_persistent_context(
            user_data_dir="/app/user_data",
            headless=False,
            viewport={'width': 1280, 'height': 720}
        )
        
        # 默认启动的 4 个标签页
        urls = [
            "https://www.google.com", 
            "https://www.youtube.com", 
            "https://github.com", 
            "https://duckduckgo.com"
        ]
        
        # 获取首个页面并额外开启 3 个
        pages = context.pages
        all_tabs = [pages[0]]
        for _ in range(1, 4):
            all_tabs.append(context.new_page())
        
        # 循环加载页面
        for i, page in enumerate(all_tabs):
            try:
                print(f">>> 标签页 {i+1} 正在访问: {urls[i]}")
                page.goto(urls[i], timeout=60000)
            except Exception as e:
                print(f"窗口 {i+1} 加载失败: {e}")
        
        print(">>> [成功] 环境就绪！请访问域名:6080/vnc.html")
        
        # 保持运行 (1小时循环一次以维护 Session)
        time.sleep(3600)
        context.close()

if __name__ == "__main__":
    while True:
        try:
            run_task()
        except Exception as e:
            print(f"主程序异常: {e}")
            time.sleep(10)
EOF

# 5. 启动部署
sudo docker-compose up -d --build

# 6. 放行本地防火墙端口
sudo iptables -I INPUT -p tcp --dport 6080 -j ACCEPT
sudo apt-get install iptables-persistent -y && sudo netfilter-persistent save

echo "===================================================="
echo "🎉 部署完成！"
echo "1. 访问地址: http://XXX.beundredig.eu.org:6080/vnc.html"
echo "2. VNC 密码: password"
echo "3. 登录状态保存位置: ~/playwright_service/user_data"
echo "===================================================="
