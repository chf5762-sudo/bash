const TELEGRAPH_URL = 'vps2.chf5762.cloudns.org:8443';
const ADMIN_PASSWORD = 'password';
const MAX_HISTORY = 20;

addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request))
})

async function handleRequest(request) {
  const url = new URL(request.url);
  
  // Admin 管理页面路由
  if (url.pathname === '/admin') {
    return handleAdmin(request);
  }
  
  if (url.pathname === '/admin/api') {
    return handleAdminAPI(request);
  }
  
  // 原有反向代理功能
  return handleProxy(request);
}

// 原有的反向代理功能（保持不变）
async function handleProxy(request) {
  const url = new URL(request.url);
  
  // 从 KV 读取当前配置，如果没有则使用默认值
  let targetURL = TELEGRAPH_URL;
  try {
    const config = await PROXY_CONFIG.get('current_config');
    if (config) {
      const configData = JSON.parse(config);
      targetURL = configData.url;
    }
  } catch (e) {
    // 使用默认配置
  }
  
  url.host = targetURL.replace(/^https?:\/\//, '');

  const modifiedRequest = new Request(url.toString(), {
    headers: request.headers,
    method: request.method,
    body: request.body,
    redirect: 'follow'
  });

  const response = await fetch(modifiedRequest);
  const modifiedResponse = new Response(response.body, response);
  modifiedResponse.headers.set('Access-Control-Allow-Origin', '*');

  return modifiedResponse;
}

// Admin 页面处理
async function handleAdmin(request) {
  const url = new URL(request.url);
  const authToken = getCookie(request, 'admin_auth');
  
  // 检查是否已登录
  if (authToken !== ADMIN_PASSWORD) {
    return new Response(getLoginHTML(), {
      headers: { 'Content-Type': 'text/html;charset=UTF-8' }
    });
  }
  
  // 获取当前配置
  let currentConfig = { url: TELEGRAPH_URL };
  try {
    const config = await PROXY_CONFIG.get('current_config');
    if (config) {
      currentConfig = JSON.parse(config);
    }
  } catch (e) {}
  
  // 获取历史记录
  let history = [];
  try {
    const historyData = await PROXY_CONFIG.get('config_history');
    if (historyData) {
      history = JSON.parse(historyData);
    }
  } catch (e) {}
  
  return new Response(getAdminHTML(currentConfig, history), {
    headers: { 'Content-Type': 'text/html;charset=UTF-8' }
  });
}

// Admin API 处理
async function handleAdminAPI(request) {
  if (request.method === 'OPTIONS') {
    return new Response(null, {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
      }
    });
  }
  
  const authToken = getCookie(request, 'admin_auth');
  
  try {
    const data = await request.json();
    const { action } = data;
    
    // 登录处理
    if (action === 'login') {
      if (data.password === ADMIN_PASSWORD) {
        return jsonResponse({ success: true }, {
          'Set-Cookie': `admin_auth=${ADMIN_PASSWORD}; Path=/; HttpOnly; Max-Age=86400`
        });
      }
      return jsonResponse({ success: false, error: '密码错误' });
    }
    
    // 其他操作需要验证
    if (authToken !== ADMIN_PASSWORD) {
      return jsonResponse({ success: false, error: '未授权' }, {}, 401);
    }
    
    // 测试连接
    if (action === 'test') {
      const testResult = await testConnection(data.url);
      return jsonResponse(testResult);
    }
    
    // 保存配置
    if (action === 'save') {
      const newConfig = {
        url: data.url,
        timestamp: new Date().toISOString()
      };
      
      // 保存当前配置
      await PROXY_CONFIG.put('current_config', JSON.stringify(newConfig));
      
      // 添加到历史记录
      let history = [];
      try {
        const historyData = await PROXY_CONFIG.get('config_history');
        if (historyData) {
          history = JSON.parse(historyData);
        }
      } catch (e) {}
      
      history.unshift(newConfig);
      if (history.length > MAX_HISTORY) {
        history = history.slice(0, MAX_HISTORY);
      }
      
      await PROXY_CONFIG.put('config_history', JSON.stringify(history));
      
      return jsonResponse({ success: true, config: newConfig });
    }
    
    // 删除配置（恢复默认）
    if (action === 'delete') {
      await PROXY_CONFIG.delete('current_config');
      return jsonResponse({ success: true, message: '已恢复默认配置' });
    }
    
    // 清除历史
    if (action === 'clear_history') {
      await PROXY_CONFIG.delete('config_history');
      return jsonResponse({ success: true, message: '历史记录已清除' });
    }
    
    return jsonResponse({ success: false, error: '未知操作' });
    
  } catch (e) {
    return jsonResponse({ success: false, error: e.message }, {}, 500);
  }
}

// 测试连接
async function testConnection(url) {
  try {
    const testURL = url.startsWith('http') ? url : `https://${url}`;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 5000);
    
    const response = await fetch(testURL, {
      method: 'HEAD',
      signal: controller.signal
    });
    
    clearTimeout(timeout);
    
    return {
      success: true,
      status: response.status,
      statusText: response.statusText,
      time: new Date().toISOString()
    };
  } catch (e) {
    return {
      success: false,
      error: e.message
    };
  }
}

// 工具函数
function getCookie(request, name) {
  const cookie = request.headers.get('Cookie');
  if (!cookie) return null;
  const match = cookie.match(new RegExp(`(^| )${name}=([^;]+)`));
  return match ? match[2] : null;
}

function jsonResponse(data, headers = {}, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      ...headers
    }
  });
}

// 登录页面 HTML
function getLoginHTML() {
  return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>管理员登录</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      min-height: 100vh;
      display: flex;
      justify-content: center;
      align-items: center;
    }
    .login-box {
      background: white;
      padding: 40px;
      border-radius: 10px;
      box-shadow: 0 10px 40px rgba(0,0,0,0.2);
      width: 90%;
      max-width: 400px;
    }
    h1 { text-align: center; margin-bottom: 30px; color: #333; }
    input {
      width: 100%;
      padding: 12px;
      border: 2px solid #ddd;
      border-radius: 5px;
      font-size: 16px;
      margin-bottom: 15px;
    }
    input:focus { outline: none; border-color: #667eea; }
    button {
      width: 100%;
      padding: 12px;
      background: #667eea;
      color: white;
      border: none;
      border-radius: 5px;
      font-size: 16px;
      cursor: pointer;
      transition: background 0.3s;
    }
    button:hover { background: #5568d3; }
    .error { color: #e74c3c; text-align: center; margin-top: 10px; }
  </style>
</head>
<body>
  <div class="login-box">
    <h1>🔐 管理员登录</h1>
    <input type="password" id="password" placeholder="请输入密码" />
    <button onclick="login()">登录</button>
    <div class="error" id="error"></div>
  </div>
  <script>
    document.getElementById('password').addEventListener('keypress', e => {
      if (e.key === 'Enter') login();
    });
    
    async function login() {
      const password = document.getElementById('password').value;
      const res = await fetch('/admin/api', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'login', password })
      });
      const data = await res.json();
      if (data.success) {
        location.reload();
      } else {
        document.getElementById('error').textContent = data.error || '登录失败';
      }
    }
  </script>
</body>
</html>`;
}

// 管理页面 HTML
function getAdminHTML(currentConfig, history) {
  return `<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>反向代理管理</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #f5f6fa;
      padding: 20px;
    }
    .container { max-width: 1000px; margin: 0 auto; }
    .header {
      background: white;
      padding: 20px;
      border-radius: 10px;
      margin-bottom: 20px;
      box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    }
    h1 { color: #2c3e50; margin-bottom: 10px; }
    .current-config {
      background: #ecf0f1;
      padding: 10px 15px;
      border-radius: 5px;
      font-family: monospace;
      margin-top: 10px;
    }
    .card {
      background: white;
      padding: 25px;
      border-radius: 10px;
      margin-bottom: 20px;
      box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    }
    h2 { color: #34495e; margin-bottom: 15px; }
    .form-group { margin-bottom: 15px; }
    label { display: block; margin-bottom: 5px; color: #555; font-weight: 500; }
    input, select {
      width: 100%;
      padding: 10px;
      border: 2px solid #ddd;
      border-radius: 5px;
      font-size: 14px;
    }
    input:focus, select:focus { outline: none; border-color: #3498db; }
    .btn-group { display: flex; gap: 10px; margin-top: 20px; }
    button {
      flex: 1;
      padding: 12px;
      border: none;
      border-radius: 5px;
      font-size: 14px;
      cursor: pointer;
      transition: all 0.3s;
    }
    .btn-primary { background: #3498db; color: white; }
    .btn-primary:hover { background: #2980b9; }
    .btn-success { background: #2ecc71; color: white; }
    .btn-success:hover { background: #27ae60; }
    .btn-danger { background: #e74c3c; color: white; }
    .btn-danger:hover { background: #c0392b; }
    .btn-warning { background: #f39c12; color: white; }
    .btn-warning:hover { background: #d68910; }
    .history-item {
      background: #f8f9fa;
      padding: 15px;
      border-radius: 5px;
      margin-bottom: 10px;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .history-url { font-family: monospace; color: #2c3e50; }
    .history-time { color: #7f8c8d; font-size: 12px; }
    .message {
      padding: 12px;
      border-radius: 5px;
      margin-bottom: 15px;
      display: none;
    }
    .message.success { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
    .message.error { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
    .message.show { display: block; }
    .test-result {
      margin-top: 10px;
      padding: 10px;
      border-radius: 5px;
      font-size: 13px;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🚀 反向代理管理面板</h1>
      <div class="current-config">
        当前配置: <strong>${currentConfig.url}</strong>
      </div>
    </div>
    
    <div class="card">
      <h2>📝 配置管理</h2>
      <div id="message" class="message"></div>
      
      <div class="form-group">
        <label>协议</label>
        <select id="protocol">
          <option value="https://">HTTPS</option>
          <option value="http://">HTTP</option>
          <option value="">自动检测</option>
        </select>
      </div>
      
      <div class="form-group">
        <label>目标地址（域名:端口 或 IP:端口）</label>
        <input type="text" id="target" placeholder="例如: vps2.chf5762.cloudns.org:8443" />
      </div>
      
      <div id="testResult" class="test-result"></div>
      
      <div class="btn-group">
        <button class="btn-success" onclick="testConfig()">🔍 测试连接</button>
        <button class="btn-primary" onclick="saveConfig()">💾 保存配置</button>
        <button class="btn-danger" onclick="deleteConfig()">🗑️ 恢复默认</button>
      </div>
    </div>
    
    <div class="card">
      <div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px;">
        <h2 style="margin: 0;">📜 历史记录</h2>
        <button class="btn-warning" onclick="clearHistory()" style="flex: none; padding: 8px 15px;">清空历史</button>
      </div>
      <div id="history">
        ${history.length === 0 ? '<p style="color: #7f8c8d;">暂无历史记录</p>' : 
          history.map(h => `
            <div class="history-item">
              <div>
                <div class="history-url">${h.url}</div>
                <div class="history-time">${new Date(h.timestamp).toLocaleString('zh-CN')}</div>
              </div>
              <button class="btn-primary" style="padding: 6px 12px;" onclick="loadHistory('${h.url}')">使用</button>
            </div>
          `).join('')
        }
      </div>
    </div>
  </div>
  
  <script>
    function showMessage(msg, type = 'success') {
      const el = document.getElementById('message');
      el.textContent = msg;
      el.className = 'message ' + type + ' show';
      setTimeout(() => el.classList.remove('show'), 3000);
    }
    
    async function testConfig() {
      const protocol = document.getElementById('protocol').value;
      const target = document.getElementById('target').value.trim();
      if (!target) return showMessage('请输入目标地址', 'error');
      
      const url = protocol + target;
      const resultEl = document.getElementById('testResult');
      resultEl.innerHTML = '⏳ 测试中...';
      resultEl.style.background = '#fff3cd';
      resultEl.style.color = '#856404';
      
      const res = await fetch('/admin/api', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'test', url })
      });
      const data = await res.json();
      
      if (data.success) {
        resultEl.innerHTML = '✅ 连接成功！状态: ' + data.status + ' ' + data.statusText;
        resultEl.style.background = '#d4edda';
        resultEl.style.color = '#155724';
      } else {
        resultEl.innerHTML = '❌ 连接失败: ' + data.error;
        resultEl.style.background = '#f8d7da';
        resultEl.style.color = '#721c24';
      }
    }
    
    async function saveConfig() {
      const protocol = document.getElementById('protocol').value;
      const target = document.getElementById('target').value.trim();
      if (!target) return showMessage('请输入目标地址', 'error');
      
      const url = protocol + target;
      const res = await fetch('/admin/api', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'save', url })
      });
      const data = await res.json();
      
      if (data.success) {
        showMessage('✅ 配置已保存');
        setTimeout(() => location.reload(), 1000);
      } else {
        showMessage('❌ ' + data.error, 'error');
      }
    }
    
    async function deleteConfig() {
      if (!confirm('确定要恢复默认配置吗？')) return;
      
      const res = await fetch('/admin/api', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'delete' })
      });
      const data = await res.json();
      
      if (data.success) {
        showMessage('✅ 已恢复默认配置');
        setTimeout(() => location.reload(), 1000);
      } else {
        showMessage('❌ ' + data.error, 'error');
      }
    }
    
    async function clearHistory() {
      if (!confirm('确定要清空所有历史记录吗？')) return;
      
      const res = await fetch('/admin/api', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'clear_history' })
      });
      const data = await res.json();
      
      if (data.success) {
        showMessage('✅ 历史记录已清空');
        setTimeout(() => location.reload(), 1000);
      } else {
        showMessage('❌ ' + data.error, 'error');
      }
    }
    
    function loadHistory(url) {
      const parts = url.match(/^(https?:\/\/)?(.+)$/);
      if (parts) {
        document.getElementById('protocol').value = parts[1] || '';
        document.getElementById('target').value = parts[2];
      }
    }
  </script>
</body>
</html>`;
}