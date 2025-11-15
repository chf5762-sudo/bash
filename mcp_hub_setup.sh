#!/bin/bash

#==============================================================================
# MCP Hub 一键安装脚本
# 适用于 Ubuntu 系统
# 功能：自动安装 Node.js, MCP Hub, 配置环境, 启动服务
#==============================================================================

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置变量
INSTALL_DIR="$HOME/mcp-hub"
MCP_PORT=8081
WEBUI_PORT=8080
INSTALL_PM2="yes"

#==============================================================================
# 辅助函数
#==============================================================================

print_header() {
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║           MCP Hub 一键安装脚本 v1.0                       ║"
    echo "║           自动安装和配置 MCP Hub 管理平台                 ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() {
    echo -e "${BLUE}[步骤]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

print_info() {
    echo -e "${CYAN}[信息]${NC} $1"
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 等待用户按键
press_any_key() {
    read -n 1 -s -r -p "按任意键继续..."
    echo
}

#==============================================================================
# 系统检查
#==============================================================================

check_system() {
    print_step "检查系统环境..."
    
    # 检查操作系统
    if [[ ! -f /etc/os-release ]]; then
        print_error "无法识别操作系统"
        exit 1
    fi
    
    source /etc/os-release
    print_info "操作系统: $NAME $VERSION"
    
    # 检查是否为 Ubuntu
    if [[ "$ID" != "ubuntu" ]]; then
        print_warning "此脚本为 Ubuntu 优化，其他系统可能需要调整"
    fi
    
    # 检查内存
    total_mem=$(free -m | awk 'NR==2{print $2}')
    if [[ $total_mem -lt 2048 ]]; then
        print_warning "系统内存少于 2GB，可能影响性能"
    else
        print_info "可用内存: ${total_mem}MB"
    fi
    
    # 检查磁盘空间
    available_space=$(df -BM "$HOME" | awk 'NR==2{print $4}' | sed 's/M//')
    if [[ $available_space -lt 5000 ]]; then
        print_warning "可用磁盘空间少于 5GB"
    else
        print_info "可用磁盘空间: ${available_space}MB"
    fi
    
    print_success "系统检查完成"
    echo
}

#==============================================================================
# 安装 Node.js
#==============================================================================

install_nodejs() {
    print_step "安装 Node.js..."
    
    if command_exists node; then
        node_version=$(node --version)
        print_info "检测到已安装 Node.js $node_version"
        read -p "是否重新安装？(y/N): " reinstall
        if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
            print_info "跳过 Node.js 安装"
            return
        fi
    fi
    
    # 安装 NVM
    if [[ ! -d "$HOME/.nvm" ]]; then
        print_info "安装 NVM..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        
        # 加载 NVM
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    else
        print_info "NVM 已安装"
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    fi
    
    # 安装 Node.js LTS
    print_info "安装 Node.js LTS 版本..."
    nvm install --lts
    nvm use --lts
    
    # 获取当前 LTS 版本号并设置为默认
    CURRENT_NODE=$(nvm current)
    nvm alias default "$CURRENT_NODE"
    
    # 验证安装
    node_version=$(node --version)
    npm_version=$(npm --version)
    print_success "Node.js $node_version 安装成功"
    print_success "npm $npm_version 安装成功"
    echo
}

#==============================================================================
# 安装 PM2
#==============================================================================

install_pm2() {
    if [[ "$INSTALL_PM2" != "yes" ]]; then
        return
    fi
    
    print_step "安装 PM2 进程管理器..."
    
    if command_exists pm2; then
        print_info "PM2 已安装"
    else
        npm install -g pm2
        print_success "PM2 安装成功"
    fi
    echo
}

#==============================================================================
# 创建目录结构
#==============================================================================

create_directories() {
    print_step "创建目录结构..."
    
    if [[ -d "$INSTALL_DIR" ]]; then
        print_warning "目录 $INSTALL_DIR 已存在"
        read -p "是否删除并重新创建？(y/N): " recreate
        if [[ "$recreate" =~ ^[Yy]$ ]]; then
            rm -rf "$INSTALL_DIR"
        else
            print_info "使用现有目录"
            return
        fi
    fi
    
    mkdir -p "$INSTALL_DIR"/{config,logs,mcp-servers,scripts}
    
    print_success "目录结构创建完成: $INSTALL_DIR"
    echo
}

#==============================================================================
# 安装 MCP Hub
#==============================================================================

install_mcp_hub() {
    print_step "安装 MCP Hub..."
    
    # 注意：这里使用 npx 方式，因为 ravitemer/mcp-hub 可能需要特定安装方式
    # 如果有全局安装包，可以使用: npm install -g mcp-hub
    
    print_info "准备 MCP Hub 环境..."
    
    # 创建一个本地项目来管理依赖
    cd "$INSTALL_DIR"
    
    if [[ ! -f package.json ]]; then
        npm init -y
        npm install express cors body-parser
    fi
    
    print_success "MCP Hub 环境准备完成"
    echo
}

#==============================================================================
# 生成配置文件
#==============================================================================

generate_config() {
    print_step "生成配置文件..."
    
    cat > "$INSTALL_DIR/config/hub-config.json" << 'EOF'
{
  "hub": {
    "port": 8081,
    "host": "0.0.0.0",
    "webUI": {
      "enabled": true,
      "port": 8080
    },
    "logging": {
      "level": "info",
      "file": "logs/hub.log",
      "console": true
    }
  },
  "routing": {
    "strategy": "namespace",
    "autoPrefix": true,
    "separator": ":",
    "conflictResolution": "error"
  },
  "servers": {
    "train": {
      "command": "node",
      "args": ["mcp-servers/train-mcp/server.js"],
      "autoStart": true,
      "group": "travel",
      "description": "车票查询服务"
    },
    "time": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-time"],
      "autoStart": true,
      "group": "information",
      "description": "时间服务"
    }
  },
  "groups": {
    "travel": {
      "name": "交通出行",
      "description": "车票、机票等交通相关服务",
      "color": "#4CAF50"
    },
    "information": {
      "name": "信息查询",
      "description": "时间、天气等信息服务",
      "color": "#2196F3"
    }
  }
}
EOF
    
    print_success "配置文件生成完成: $INSTALL_DIR/config/hub-config.json"
    echo
}

#==============================================================================
# 创建车票查询 MCP 示例
#==============================================================================

create_train_mcp() {
    print_step "创建车票查询 MCP 示例..."
    
    mkdir -p "$INSTALL_DIR/mcp-servers/train-mcp"
    cd "$INSTALL_DIR/mcp-servers/train-mcp"
    
    # 创建 package.json
    cat > package.json << 'EOF'
{
  "name": "train-mcp-server",
  "version": "1.0.0",
  "description": "车票查询 MCP 服务器",
  "main": "server.js",
  "type": "module",
  "dependencies": {
    "@modelcontextprotocol/sdk": "^1.0.0"
  }
}
EOF
    
    # 安装依赖
    npm install
    
    print_success "车票查询 MCP 创建完成"
    print_info "位置: $INSTALL_DIR/mcp-servers/train-mcp"
    echo
}

#==============================================================================
# 创建启动脚本
#==============================================================================

create_start_script() {
    print_step "创建启动脚本..."
    
    # 使用 PM2 的启动脚本
    cat > "$INSTALL_DIR/scripts/start-hub.sh" << 'EOF'
#!/bin/bash

# 加载 NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

INSTALL_DIR="$HOME/mcp-hub"
cd "$INSTALL_DIR"

echo "启动 MCP Hub..."

# 检查是否安装了 PM2
if command -v pm2 >/dev/null 2>&1; then
    # 使用 PM2 启动
    pm2 start scripts/hub-server.js --name "mcp-hub"
    pm2 save
    echo "MCP Hub 已在后台启动"
    echo "使用 'pm2 logs mcp-hub' 查看日志"
    echo "使用 'pm2 status' 查看状态"
else
    # 直接启动
    echo "直接启动 MCP Hub（前台运行）"
    node scripts/hub-server.js
fi
EOF
    
    # 停止脚本
    cat > "$INSTALL_DIR/scripts/stop-hub.sh" << 'EOF'
#!/bin/bash

echo "停止 MCP Hub..."

if command -v pm2 >/dev/null 2>&1; then
    pm2 stop mcp-hub
    pm2 delete mcp-hub
    echo "MCP Hub 已停止"
else
    pkill -f "hub-server.js"
    echo "MCP Hub 进程已终止"
fi
EOF
    
    chmod +x "$INSTALL_DIR/scripts/start-hub.sh"
    chmod +x "$INSTALL_DIR/scripts/stop-hub.sh"
    
    print_success "启动脚本创建完成"
    echo
}

#==============================================================================
# 创建简单的 Hub 服务器
#==============================================================================

create_hub_server() {
    print_step "创建 MCP Hub 服务器..."
    
    cat > "$INSTALL_DIR/scripts/hub-server.js" << 'EOF'
import express from 'express';
import cors from 'cors';
import bodyParser from 'body-parser';
import { spawn } from 'child_process';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const MCP_PORT = 8081;
const WEBUI_PORT = 8080;

app.use(cors());
app.use(bodyParser.json());

// 读取配置
const configPath = path.join(__dirname, '../config/hub-config.json');
let config = {};

try {
    const configData = fs.readFileSync(configPath, 'utf8');
    config = JSON.parse(configData);
    console.log('✓ 配置文件加载成功');
} catch (error) {
    console.error('× 配置文件加载失败:', error.message);
    process.exit(1);
}

// 存储 MCP 进程
const mcpProcesses = {};

// 启动 MCP 服务器
function startMCPServer(name, serverConfig) {
    console.log(`启动 MCP 服务器: ${name}`);
    
    try {
        const proc = spawn(serverConfig.command, serverConfig.args, {
            cwd: path.join(__dirname, '..'),
            stdio: ['pipe', 'pipe', 'pipe']
        });
        
        proc.stdout.on('data', (data) => {
            console.log(`[${name}] ${data.toString().trim()}`);
        });
        
        proc.stderr.on('data', (data) => {
            console.error(`[${name}] ERROR: ${data.toString().trim()}`);
        });
        
        proc.on('close', (code) => {
            console.log(`[${name}] 进程退出，代码: ${code}`);
            delete mcpProcesses[name];
        });
        
        mcpProcesses[name] = {
            process: proc,
            config: serverConfig,
            status: 'running',
            startTime: new Date()
        };
        
        console.log(`✓ MCP 服务器 ${name} 启动成功`);
    } catch (error) {
        console.error(`× MCP 服务器 ${name} 启动失败:`, error.message);
    }
}

// 启动所有自动启动的 MCP
Object.entries(config.servers || {}).forEach(([name, serverConfig]) => {
    if (serverConfig.autoStart) {
        startMCPServer(name, serverConfig);
    }
});

// API 路由

// 获取所有 MCP 服务器状态
app.get('/api/servers', (req, res) => {
    const servers = {};
    
    Object.entries(config.servers || {}).forEach(([name, serverConfig]) => {
        const process = mcpProcesses[name];
        servers[name] = {
            name,
            group: serverConfig.group,
            description: serverConfig.description,
            status: process ? process.status : 'stopped',
            startTime: process ? process.startTime : null,
            config: serverConfig
        };
    });
    
    res.json({ servers });
});

// 启动 MCP 服务器
app.post('/api/servers/:name/start', (req, res) => {
    const { name } = req.params;
    const serverConfig = config.servers[name];
    
    if (!serverConfig) {
        return res.status(404).json({ error: '服务器不存在' });
    }
    
    if (mcpProcesses[name]) {
        return res.status(400).json({ error: '服务器已在运行' });
    }
    
    startMCPServer(name, serverConfig);
    res.json({ message: `服务器 ${name} 启动成功` });
});

// 停止 MCP 服务器
app.post('/api/servers/:name/stop', (req, res) => {
    const { name } = req.params;
    const mcpProcess = mcpProcesses[name];
    
    if (!mcpProcess) {
        return res.status(404).json({ error: '服务器未运行' });
    }
    
    mcpProcess.process.kill();
    delete mcpProcesses[name];
    
    res.json({ message: `服务器 ${name} 已停止` });
});

// Web UI (简单的 HTML 页面)
app.get('/', (req, res) => {
    res.send(`
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MCP Hub 管理界面</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        .header {
            background: white;
            padding: 30px;
            border-radius: 15px;
            margin-bottom: 30px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
        }
        h1 { 
            color: #333;
            font-size: 32px;
            margin-bottom: 10px;
        }
        .subtitle {
            color: #666;
            font-size: 16px;
        }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        .stat-card {
            background: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        .stat-value {
            font-size: 36px;
            font-weight: bold;
            color: #667eea;
        }
        .stat-label {
            color: #666;
            margin-top: 5px;
        }
        .servers {
            background: white;
            padding: 30px;
            border-radius: 15px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.1);
        }
        .server-item {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 20px;
            border: 1px solid #e0e0e0;
            border-radius: 10px;
            margin-bottom: 15px;
            transition: all 0.3s;
        }
        .server-item:hover {
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
            transform: translateY(-2px);
        }
        .server-info {
            flex: 1;
        }
        .server-name {
            font-size: 18px;
            font-weight: bold;
            color: #333;
            margin-bottom: 5px;
        }
        .server-desc {
            color: #666;
            font-size: 14px;
        }
        .server-status {
            display: inline-block;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: bold;
            margin-right: 10px;
        }
        .status-running {
            background: #4CAF50;
            color: white;
        }
        .status-stopped {
            background: #f44336;
            color: white;
        }
        button {
            padding: 8px 20px;
            border: none;
            border-radius: 5px;
            cursor: pointer;
            font-size: 14px;
            transition: all 0.3s;
        }
        .btn-start {
            background: #4CAF50;
            color: white;
        }
        .btn-stop {
            background: #f44336;
            color: white;
        }
        button:hover {
            opacity: 0.8;
        }
        .loading {
            text-align: center;
            padding: 50px;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 MCP Hub 管理界面</h1>
            <p class="subtitle">集中管理您的所有 MCP 服务器</p>
        </div>
        
        <div class="stats">
            <div class="stat-card">
                <div class="stat-value" id="total-servers">-</div>
                <div class="stat-label">总服务器数</div>
            </div>
            <div class="stat-card">
                <div class="stat-value" id="running-servers">-</div>
                <div class="stat-label">运行中</div>
            </div>
            <div class="stat-card">
                <div class="stat-value" id="stopped-servers">-</div>
                <div class="stat-label">已停止</div>
            </div>
        </div>
        
        <div class="servers">
            <h2 style="margin-bottom: 20px; color: #333;">MCP 服务器列表</h2>
            <div id="server-list" class="loading">加载中...</div>
        </div>
    </div>
    
    <script>
        async function loadServers() {
            try {
                const response = await fetch('/api/servers');
                const data = await response.json();
                
                const servers = Object.values(data.servers);
                const running = servers.filter(s => s.status === 'running').length;
                const stopped = servers.filter(s => s.status === 'stopped').length;
                
                document.getElementById('total-servers').textContent = servers.length;
                document.getElementById('running-servers').textContent = running;
                document.getElementById('stopped-servers').textContent = stopped;
                
                const listHtml = servers.map(server => `
                    <div class="server-item">
                        <div class="server-info">
                            <div class="server-name">${server.name}</div>
                            <div class="server-desc">${server.description || '无描述'}</div>
                        </div>
                        <div>
                            <span class="server-status status-${server.status}">
                                ${server.status === 'running' ? '运行中' : '已停止'}
                            </span>
                            ${server.status === 'running' 
                                ? '<button class="btn-stop" onclick="stopServer(\'' + server.name + '\')">停止</button>'
                                : '<button class="btn-start" onclick="startServer(\'' + server.name + '\')">启动</button>'
                            }
                        </div>
                    </div>
                `).join('');
                
                document.getElementById('server-list').innerHTML = listHtml;
            } catch (error) {
                document.getElementById('server-list').innerHTML = 
                    '<div style="color: red;">加载失败: ' + error.message + '</div>';
            }
        }
        
        async function startServer(name) {
            try {
                await fetch(\`/api/servers/\${name}/start\`, { method: 'POST' });
                loadServers();
            } catch (error) {
                alert('启动失败: ' + error.message);
            }
        }
        
        async function stopServer(name) {
            try {
                await fetch(\`/api/servers/\${name}/stop\`, { method: 'POST' });
                loadServers();
            } catch (error) {
                alert('停止失败: ' + error.message);
            }
        }
        
        loadServers();
        setInterval(loadServers, 5000);
    </script>
</body>
</html>
    `);
});

// 启动 MCP API 服务器
app.listen(MCP_PORT, '0.0.0.0', () => {
    console.log(`
╔════════════════════════════════════════════════════════════╗
║           MCP Hub 启动成功！                               ║
╠════════════════════════════════════════════════════════════╣
║  MCP API:    http://localhost:${MCP_PORT}                     ║
║  Web UI:     http://localhost:${WEBUI_PORT}                     ║
╚════════════════════════════════════════════════════════════╝
    `);
});

// 启动 Web UI 服务器
const webUIApp = express();
webUIApp.use(cors());
webUIApp.use(bodyParser.json());

// 重定向所有请求到主应用
webUIApp.all('*', (req, res) => {
    res.redirect(`http://localhost:${MCP_PORT}${req.url}`);
});

webUIApp.listen(WEBUI_PORT, '0.0.0.0', () => {
    console.log(`✓ Web UI 服务器运行在端口 ${WEBUI_PORT}`);
});
EOF
    
    print_success "Hub 服务器创建完成"
    echo
}

#==============================================================================
# 创建 README
#==============================================================================

create_readme() {
    print_step "创建使用文档..."
    
    cat > "$INSTALL_DIR/README.md" << 'EOF'
# MCP Hub 使用文档

## 🚀 快速开始

### 启动 MCP Hub

```bash
cd ~/mcp-hub
./scripts/start-hub.sh
```

### 访问 Web UI

浏览器打开: http://localhost:8080

### 停止 MCP Hub

```bash
cd ~/mcp-hub
./scripts/stop-hub.sh
```

## 📁 目录结构

```
~/mcp-hub/
├── config/              # 配置文件
│   └── hub-config.json  # 主配置
├── logs/                # 日志文件
├── mcp-servers/         # MCP 服务器
│   └── train-mcp/       # 车票查询示例
├── scripts/             # 脚本文件
│   ├── start-hub.sh     # 启动脚本
│   ├── stop-hub.sh      # 停止脚本
│   └── hub-server.js    # Hub 服务器
└── README.md            # 本文档
```

## ⚙️ 配置说明

编辑配置文件: `~/mcp-hub/config/hub-config.json`

### 添加新的 MCP 服务器

```json
{
  "servers": {
    "your-mcp-name": {
      "command": "node",
      "args": ["path/to/your/mcp/server.js"],
      "autoStart": true,
      "group": "your-group",
      "description": "你的 MCP 描述"
    }
  }
}
```

## 🔧 常用命令

### 查看日志

```bash
# 使用 PM2
pm2 logs mcp-hub

# 或直接查看日志文件
tail -f ~/mcp-hub/logs/hub.log
```

### 重启服务

```bash
pm2 restart mcp-hub
```

### 查看状态

```bash
pm2 status
```

## 📚 开发指南

### 创建自定义 MCP 服务器

1. 在 `mcp-servers/` 目录下创建新文件夹
2. 创建 `package.json` 和 `server.js`
3. 在 `hub-config.json` 中添加配置
4. 重启 Hub

## 🆘 故障排除

### 端口被占用

如果端口 37373 或 8080 被占用，编辑配置文件修改端口。

### MCP 服务器无法启动

检查日志: `tail -f ~/mcp-hub/logs/hub.log`

### Web UI 无法访问

确认防火墙设置，允许端口 8080。

## 📞 支持

遇到问题？请检查:
- 日志文件
- 配置文件格式
- Node.js 版本

EOF
    
    print_success "使用文档创建完成: $INSTALL_DIR/README.md"
    echo
}

#==============================================================================
# 显示安装总结
#==============================================================================

show_summary() {
    echo
    echo -e "${GREEN}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                  🎉 安装完成！                             ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    
    echo -e "${CYAN}📁 安装位置:${NC} $INSTALL_DIR"
    echo -e "${CYAN}🌐 MCP API:${NC} http://localhost:$MCP_PORT"
    echo -e "${CYAN}🖥️  Web UI:${NC} http://localhost:$WEBUI_PORT"
    echo
    echo -e "${YELLOW}🚀 快速启动命令:${NC}"
    echo -e "   cd $INSTALL_DIR"
    echo -e "   ./scripts/start-hub.sh"
    echo
    echo -e "${YELLOW}📖 查看文档:${NC}"
    echo -e "   cat $INSTALL_DIR/README.md"
    echo
    echo -e "${YELLOW}🔍 查看日志:${NC}"
    echo -e "   pm2 logs mcp-hub"
    echo
    echo -e "${GREEN}✨ 提示: 重启终端或运行以下命令加载 Node.js:${NC}"
    echo -e "   source ~/.bashrc"
    echo
}

#==============================================================================
# 主函数
#==============================================================================

main() {
    print_header
    
    echo "此脚本将安装以下组件："
    echo "  • Node.js (通过 NVM)"
    echo "  • PM2 进程管理器"
    echo "  • MCP Hub 管理平台"
    echo "  • 车票查询 MCP 示例"
    echo
    echo "安装位置: $INSTALL_DIR"
    echo "MCP 端口: $MCP_PORT"
    echo "Web UI 端口: $WEBUI_PORT"
    echo
    
    read -p "是否继续安装？(Y/n): " confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo "安装已取消"
        exit 0
    fi
    
    echo
    echo "开始安装..."
    echo
    
    # 执行安装步骤
    check_system
    install_nodejs
    install_pm2
    create_directories
    install_mcp_hub
    generate_config
    create_train_mcp
    create_hub_server
    create_start_script
    create_readme
    
    # 显示总结
    show_summary
    
    # 询问是否立即启动
    echo
    read -p "是否立即启动 MCP Hub？(Y/n): " start_now
    if [[ ! "$start_now" =~ ^[Nn]$ ]]; then
        print_step "启动 MCP Hub..."
        cd "$INSTALL_DIR"
        
        # 加载 NVM
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
        
        if command_exists pm2; then
            pm2 start scripts/hub-server.js --name "mcp-hub"
            pm2 save
            echo
            print_success "MCP Hub 已在后台启动！"
            echo
            print_info "访问 Web UI: http://localhost:$WEBUI_PORT"
            print_info "查看日志: pm2 logs mcp-hub"
        else
            print_warning "PM2 未安装，请手动启动："
            print_info "cd $INSTALL_DIR && node scripts/hub-server.js"
        fi
    fi
    
    echo
    print_success "安装流程全部完成！🎉"
    echo
}

# 运行主函数
main