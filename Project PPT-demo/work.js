// ============================================
// WebDAV 网盘 + MQTT演示系统 (Cloudflare Worker)
// 整合了 demoppt.txt 和 mqtt interface.txt
// ============================================

const CONFIG = {
    WEBDAV: {
        URL: "https://ajiro.infini-cloud.net/dav/",
        USER: "chf5762",
        PASS: "piNdCJ4EPiw5Wtgn"
    },
    PREVIEW_TOKEN: "Allow_Public_Preview_Access_2025"
};

export default {
    async fetch(request, env, ctx) {
        const url = new URL(request.url);

        if (request.method === "OPTIONS") {
            return new Response(null, { status: 204, headers: corsHeaders() });
        }

        try {
            if (url.pathname === "/api/list") return await handleList(request);
            if (url.pathname === "/api/upload") return await handleUpload(request);
            if (url.pathname === "/api/download") return await handleDownload(request);
            if (url.pathname === "/api/delete") return await handleDelete(request);
            if (url.pathname === "/api/mkdir") return await handleMkdir(request);
            if (url.pathname === "/api/move") return await handleMove(request);
            if (url.pathname === "/api/copy") return await handleCopy(request);
            if (url.pathname === "/api/create-link") return await handleCreateLink(request);
            // 允许 /api/file-proxy/xxx.ppt 这种带后缀的路径
            if (url.pathname.startsWith("/api/file-proxy")) return await handleFileProxy(request);

            // kkfileview代理 - 解决HTTPS/HTTP混合内容问题
            if (url.pathname.startsWith("/api/kkfileview")) return await handleKKFileViewProxy(request);

            // 返回主页面
            return new Response(HTML_PAGE, {
                headers: { "Content-Type": "text/html; charset=utf-8", ...corsHeaders() }
            });
        } catch (e) {
            return new Response(JSON.stringify({ error: e.message }), {
                status: 500,
                headers: { "Content-Type": "application/json", ...corsHeaders() }
            });
        }
    }
};

function getAuthHeader() { return "Basic " + btoa(CONFIG.WEBDAV.USER + ":" + CONFIG.WEBDAV.PASS); }
function corsHeaders() {
    return {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, COPY, MOVE, OPTIONS, PROPFIND, MKCOL",
        "Access-Control-Allow-Headers": "Content-Type, Authorization, Depth, Destination, Overwrite"
    };
}

async function handleList(request) {
    const url = new URL(request.url);
    const dir = url.searchParams.get("path") || "";
    const response = await fetch(CONFIG.WEBDAV.URL + dir, {
        method: "PROPFIND",
        headers: { "Authorization": getAuthHeader(), "Depth": "1" }
    });
    return new Response(await response.text(), { headers: { "Content-Type": "application/xml", ...corsHeaders() } });
}

async function handleUpload(request) {
    const url = new URL(request.url);
    const path = url.searchParams.get("path");
    const response = await fetch(CONFIG.WEBDAV.URL + path, {
        method: "PUT",
        headers: { "Authorization": getAuthHeader() },
        body: request.body
    });
    return new Response(JSON.stringify({ success: response.ok }), { headers: { "Content-Type": "application/json", ...corsHeaders() } });
}

async function handleDownload(request) {
    const url = new URL(request.url);
    const path = url.searchParams.get("path");
    const isInline = url.searchParams.get("inline") === "true";
    const response = await fetch(CONFIG.WEBDAV.URL + path, { method: "GET", headers: { "Authorization": getAuthHeader() } });

    const filename = path.split('/').pop();
    const ext = filename.split('.').pop().toLowerCase();
    const mimeMap = {
        'txt': 'text/plain', 'html': 'text/html', 'js': 'application/javascript', 'css': 'text/css',
        'json': 'application/json', 'pdf': 'application/pdf', 'jpg': 'image/jpeg', 'png': 'image/png',
        'mp4': 'video/mp4', 'ppt': 'application/vnd.ms-powerpoint',
        'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
        'doc': 'application/msword',
        'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
        'xls': 'application/vnd.ms-excel',
        'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    };
    const mimeType = mimeMap[ext] || 'application/octet-stream';
    const disposition = isInline ? 'inline' : 'attachment';

    return new Response(response.body, {
        headers: { "Content-Type": mimeType, "Content-Disposition": `${disposition}; filename="${filename}"`, ...corsHeaders() }
    });
}

async function handleDelete(request) {
    const url = new URL(request.url);
    const path = url.searchParams.get("path");
    const response = await fetch(CONFIG.WEBDAV.URL + path, { method: "DELETE", headers: { "Authorization": getAuthHeader() } });
    return new Response(JSON.stringify({ success: response.ok }), { headers: { "Content-Type": "application/json", ...corsHeaders() } });
}

async function handleMkdir(request) {
    const url = new URL(request.url);
    const path = url.searchParams.get("path");
    const fullPath = CONFIG.WEBDAV.URL + path + (path.endsWith('/') ? '' : '/');
    const response = await fetch(fullPath, { method: "MKCOL", headers: { "Authorization": getAuthHeader() } });
    return new Response(JSON.stringify({ success: response.ok || response.status === 405 }), { headers: { "Content-Type": "application/json", ...corsHeaders() } });
}

async function handleMove(request) {
    const url = new URL(request.url);
    const source = url.searchParams.get("source");
    const dest = url.searchParams.get("dest");
    const response = await fetch(CONFIG.WEBDAV.URL + source, {
        method: "MOVE",
        headers: { "Authorization": getAuthHeader(), "Destination": CONFIG.WEBDAV.URL + dest, "Overwrite": "T" }
    });
    return new Response(JSON.stringify({ success: response.ok }), { headers: { "Content-Type": "application/json", ...corsHeaders() } });
}

async function handleCopy(request) {
    const url = new URL(request.url);
    const source = url.searchParams.get("source");
    const dest = url.searchParams.get("dest");
    const response = await fetch(CONFIG.WEBDAV.URL + source, {
        method: "COPY",
        headers: { "Authorization": getAuthHeader(), "Destination": CONFIG.WEBDAV.URL + dest, "Overwrite": "T" }
    });
    return new Response(JSON.stringify({ success: response.ok }), { headers: { "Content-Type": "application/json", ...corsHeaders() } });
}

async function handleCreateLink(request) {
    const url = new URL(request.url);
    const path = url.searchParams.get("path");
    const targetUrl = await request.text();
    const response = await fetch(CONFIG.WEBDAV.URL + path, {
        method: "PUT", headers: { "Authorization": getAuthHeader(), "Content-Type": "text/plain" }, body: targetUrl
    });
    return new Response(JSON.stringify({ success: response.ok }), { headers: { "Content-Type": "application/json", ...corsHeaders() } });
}

// kkfileview代理 - 解决HTTPS/HTTP混合内容安全问题
async function handleKKFileViewProxy(request) {
    const url = new URL(request.url);
    const KKFILEVIEW_SERVER = "http://vps1.beundredig.eu.org:8012";

    // 构建目标URL：/api/kkfileview/xxx -> http://kkfileview:8012/xxx
    const targetPath = url.pathname.replace('/api/kkfileview', '');
    const targetUrl = KKFILEVIEW_SERVER + targetPath + url.search;

    try {
        const response = await fetch(targetUrl, {
            method: request.method,
            headers: request.headers,
            body: request.body
        });

        // 复制响应，添加CORS头
        const newHeaders = new Headers(response.headers);
        Object.entries(corsHeaders()).forEach(([key, value]) => {
            newHeaders.set(key, value);
        });

        // 关键修复：混合内容(Mixed Content)处理
        // 如果响应是 HTML/Text，需要将内部的 http://vps... 替换为 worker 的 https 代理地址
        const contentType = newHeaders.get("Content-Type") || "";
        if (contentType.includes("text/html") || contentType.includes("application/javascript") || contentType.includes("text/css")) {
            let bodyText = await response.text();

            // 将 KKFileView 的原始地址替换为 Worker 代理地址
            // 示例: http://vps1.beundredig.eu.org:8012 -> https://online-offcie.beundredig.eu.org/api/kkfileview
            const workerOrigin = new URL(request.url).origin;
            const proxyBase = workerOrigin + "/api/kkfileview";

            // 全局替换 (处理 http 和 https 两种可能，防止漏网)
            bodyText = bodyText.replaceAll(KKFILEVIEW_SERVER, proxyBase);

            // 某些相对路径资源也可能需要修正，但 KKFileView 通常使用绝对路径或相对路径
            // 这里主要解决 iframe src 或 js 中写死的 base url

            // 注入控制脚本：让 Iframe 内部监听 postMessage，实现精确翻页
            if (contentType.includes("text/html")) {
                console.log("[Worker] Injecting control script into HTML response...");
                const injectScript = `
                <script>
                    console.log("[Iframe] Control script loaded successfully! Location:", window.location.href);
                    
                    // 查找 PDF.js Viewer Application
                    function findPDFViewerApp() {
                        // 直接在当前窗口查找
                        if (typeof PDFViewerApplication !== 'undefined') return PDFViewerApplication;
                        // 在 window.wrappedJSObject 查找 (Firefox)
                        if (window.wrappedJSObject && window.wrappedJSObject.PDFViewerApplication) return window.wrappedJSObject.PDFViewerApplication;
                        return null;
                    }
                    
                    // 核心翻页函数
                    function goToPage(pageNum) {
                        console.log('[Iframe] Attempting to go to page:', pageNum);
                        
                        // 方法1: PDF.js API
                        const pdfApp = findPDFViewerApp();
                        if (pdfApp && pdfApp.pdfViewer) {
                            const totalPages = pdfApp.pagesCount || pdfApp.pdfViewer.pagesCount || 999;
                            const targetPage = Math.max(1, Math.min(pageNum, totalPages));
                            pdfApp.page = targetPage;
                            console.log('[Iframe] PDF.js API: Set page to', targetPage, '/', totalPages);
                            return { success: true, page: targetPage, total: totalPages };
                        }
                        
                        // 方法2: 查找 PDF.js input[type="number"] 页码输入框并触发
                        const pageInput = document.querySelector('input#pageNumber, input.toolbarField[type="number"]');
                        if (pageInput) {
                            pageInput.value = pageNum;
                            pageInput.dispatchEvent(new Event('change', { bubbles: true }));
                            console.log('[Iframe] Input field method: Set page to', pageNum);
                            return { success: true, page: pageNum };
                        }
                        
                        // 方法3: 点击 PDF.js 翻页按钮
                        const nextBtn = document.querySelector('#next, button[title="Next Page"], .toolbarButton.pageDown');
                        const prevBtn = document.querySelector('#previous, button[title="Previous Page"], .toolbarButton.pageUp');
                        if (nextBtn || prevBtn) {
                            console.log('[Iframe] Found PDF.js navigation buttons');
                            return { success: true, hasButtons: true, nextBtn: !!nextBtn, prevBtn: !!prevBtn };
                        }
                        
                        return { success: false };
                    }
                    
                    // 点击翻页按钮
                    function clickNavButton(direction) {
                        const selector = direction === 'next' 
                            ? '#next, button[title="Next Page"], .toolbarButton.pageDown'
                            : '#previous, button[title="Previous Page"], .toolbarButton.pageUp';
                        const btn = document.querySelector(selector);
                        if (btn) {
                            btn.click();
                            console.log('[Iframe] Clicked', direction, 'button');
                            return true;
                        }
                        return false;
                    }
                    
                    window.addEventListener('message', function(e) {
                         if (!e.data || !e.data.action) return;
                         
                         console.log("[Iframe] Message received:", e.data);
                         let handled = false;
                         let result = null;
                         
                         switch(e.data.action) {
                             case 'goto':
                                 result = goToPage(e.data.page);
                                 handled = result.success;
                                 break;
                             case 'next':
                                 // 先尝试 API，再尝试按钮
                                 const pdfApp = findPDFViewerApp();
                                 if (pdfApp && pdfApp.pdfViewer) {
                                     pdfApp.page = (pdfApp.page || 1) + 1;
                                     handled = true;
                                 } else {
                                     handled = clickNavButton('next');
                                 }
                                 break;
                             case 'prev':
                                 const pdfApp2 = findPDFViewerApp();
                                 if (pdfApp2 && pdfApp2.pdfViewer) {
                                     pdfApp2.page = Math.max(1, (pdfApp2.page || 1) - 1);
                                     handled = true;
                                 } else {
                                     handled = clickNavButton('prev');
                                 }
                                 break;
                             case 'scroll':
                                 // 兼容旧的滚动方式
                                 window.scrollTo(0, e.data.top);
                                 handled = true;
                                 break;
                         }
                         
                         // 递归传递给子 Iframe
                         const childFrames = document.querySelectorAll('iframe');
                         if (childFrames.length > 0) {
                             console.log('[Iframe] Forwarding message to ' + childFrames.length + ' child iframes...');
                             childFrames.forEach(ifr => {
                                 try {
                                     ifr.contentWindow.postMessage(e.data, '*');
                                 } catch(err) {
                                     console.error('Failed to forward to child iframe:', err);
                                 }
                             });
                         }
                         
                         if (!handled && childFrames.length === 0) {
                             console.warn('[Iframe] Command not handled and no child iframes!');
                         }
                    });
                </script>
                `;
                bodyText = bodyText.replace('</body>', injectScript + '</body>');
            }

            return new Response(bodyText, {
                status: response.status,
                statusText: response.statusText,
                headers: newHeaders
            });
        }

        return new Response(response.body, {
            status: response.status,
            statusText: response.statusText,
            headers: newHeaders
        });
    } catch (e) {
        return new Response(JSON.stringify({ error: "kkfileview proxy error: " + e.message }), {
            status: 500,
            headers: { "Content-Type": "application/json", ...corsHeaders() }
        });
    }
}

// 文件代理 - 让kkfileview能够访问需要认证的WebDAV文件
async function handleFileProxy(request) {
    const url = new URL(request.url);
    const path = url.searchParams.get("path");
    const token = url.searchParams.get("token");

    // 验证token
    if (token !== CONFIG.PREVIEW_TOKEN) {
        return new Response("Unauthorized", { status: 401 });
    }

    if (!path) {
        return new Response("Missing path parameter", { status: 400 });
    }

    try {
        // 从WebDAV获取文件
        const response = await fetch(CONFIG.WEBDAV.URL + path, {
            method: "GET",
            headers: { "Authorization": getAuthHeader() }
        });

        if (!response.ok) {
            return new Response(`File not found: ${path}`, { status: 404 });
        }

        // 获取文件类型
        const filename = path.split('/').pop();
        const ext = filename.split('.').pop().toLowerCase();
        const mimeMap = {
            'pdf': 'application/pdf',
            'ppt': 'application/vnd.ms-powerpoint',
            'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
            'doc': 'application/msword',
            'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'xls': 'application/vnd.ms-excel',
            'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
        };
        const contentType = mimeMap[ext] || response.headers.get("Content-Type") || "application/octet-stream";

        // 返回文件，允许跨域访问（让kkfileview可以访问）
        return new Response(response.body, {
            headers: {
                "Content-Type": contentType,
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "GET, OPTIONS",
                "Access-Control-Allow-Headers": "Content-Type",
                "Cache-Control": "public, max-age=3600"
            }
        });
    } catch (e) {
        return new Response(JSON.stringify({ error: "File proxy error: " + e.message }), {
            status: 500,
            headers: { "Content-Type": "application/json", ...corsHeaders() }
        });
    }
}


// HTML页面内容 (完整的index.html嵌入)
const HTML_PAGE = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>WebDAV网盘 + MQTT演示系统</title>
    <script src="https://unpkg.com/mqtt@5.3.4/dist/mqtt.min.js"><\/script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js"><\/script>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #f4f6f8; margin: 0; padding: 20px; color: #333; height: 100vh; box-sizing: border-box; display: flex; flex-direction: column; }
        .container { flex: 1; background: white; padding: 0; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,0,0,0.08); display: flex; flex-direction: column; overflow: hidden; }
        .header { padding: 15px 20px; border-bottom: 1px solid #eee; display: flex; justify-content: space-between; align-items: center; background: #fff; }
        .title { font-size: 18px; font-weight: bold; color: #2c3e50; }
        .mqtt-status { font-size: 12px; display: flex; align-items: center; gap: 8px; }
        .mqtt-indicator { width: 10px; height: 10px; border-radius: 50%; background: #e74c3c; transition: all 0.3s; }
        .mqtt-indicator.connected { background: #4caf50; box-shadow: 0 0 0 4px rgba(76, 175, 80, 0.3); animation: pulse 2s infinite; }
        @keyframes pulse { 0%, 100% { box-shadow: 0 0 0 0 rgba(76, 175, 80, 0.7); } 50% { box-shadow: 0 0 0 8px rgba(76, 175, 80, 0); } }
        .toolbar { padding: 10px 20px; background: #fafafa; border-bottom: 1px solid #eee; display: flex; gap: 8px; flex-wrap: wrap; align-items: center; }
        button { padding: 6px 12px; border: 1px solid #dcdfe6; border-radius: 4px; background: white; cursor: pointer; transition: 0.2s; font-size: 13px; color: #606266; }
        button:hover { color: #409eff; border-color: #c6e2ff; background-color: #ecf5ff; }
        button.primary { background: #409eff; color: white; border-color: #409eff; }
        button.primary:hover { background: #66b1ff; }
        button.success { background: #67c23a; color: white; border-color: #67c23a; }
        button.success:hover { background: #85ce61; }
        button.danger { color: #f56c6c; border-color: #fbc4c4; background: #fef0f0; }
        .sort-group { display: flex; align-items: center; gap: 5px; margin-left: auto; }
        .sort-group select { padding: 4px 8px; border: 1px solid #dcdfe6; border-radius: 4px; font-size: 13px; outline: none; cursor: pointer; }
        .main-content { display: flex; flex: 1; overflow: hidden; }
        .left-panel { width: 320px; display: flex; flex-direction: column; border-right: 1px solid #eee; background: #fff; flex-shrink: 0; }
        .breadcrumb { padding: 10px 15px; font-size: 12px; color: #909399; background: #fff; border-bottom: 1px solid #f0f0f0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        .file-list { flex: 1; overflow-y: auto; }
        .file-item { display: flex; align-items: center; padding: 10px 15px; border-bottom: 1px solid #f9f9f9; cursor: pointer; transition: 0.1s; position: relative; user-select: none; }
        .file-item:hover { background: #f5f7fa; }
        .file-item.selected { background: #ecf5ff; color: #409eff; }
        .file-item.drag-over { background: #e1f3d8; border: 2px dashed #67c23a; }
        .file-item.dragging { opacity: 0.5; }
        .file-item.drag-over-top { border-top: 3px solid #409eff; }
        .file-item.drag-over-bottom { border-bottom: 3px solid #409eff; }
        .file-icon { font-size: 20px; margin-right: 10px; width: 24px; text-align: center; }
        .file-name { font-size: 13px; flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        .file-badge { font-size: 10px; background: #67c23a; color: white; padding: 2px 6px; border-radius: 3px; margin-left: 5px; }
        .right-panel { flex: 1; display: flex; flex-direction: column; background: #fff; overflow: hidden; position: relative; }
        .preview-header { height: 45px; border-bottom: 1px solid #eee; display: flex; align-items: center; justify-content: space-between; padding: 0 20px; font-weight: 500; font-size: 14px; background: #fafafa; }
        .preview-body { flex: 1; overflow: auto; position: relative; background: #fdfdfd; display: flex; flex-direction: column; }
        .preview-msg { margin: auto; color: #909399; text-align: center; }
        .preview-iframe { flex: 1; width: 100%; height: 100%; border: none; }
        .preview-video { width: 100%; max-height: 100%; outline: none; background: black; }
        .preview-img { max-width: 100%; margin: 20px auto; display: block; }
        #editor-textarea { flex: 1; width: 100%; box-sizing: border-box; padding: 20px; font-family: Consolas, Monaco, monospace; font-size: 14px; line-height: 1.6; border: none; outline: none; resize: none; color: #333; background: #fff; }
        .link-bar { background: #fffbe8; color: #e6a23c; padding: 10px; border-bottom: 1px solid #faecd8; font-size: 13px; display: flex; justify-content: space-between; align-items: center; }
        .ctx-menu { display: none; position: absolute; z-index: 9999; background: white; border: 1px solid #e4e7ed; box-shadow: 0 2px 12px 0 rgba(0,0,0,0.1); border-radius: 4px; padding: 5px 0; min-width: 120px; }
        .ctx-item { padding: 8px 15px; font-size: 13px; color: #606266; cursor: pointer; transition: 0.1s; display: flex; align-items: center; gap: 8px; }
        .ctx-item:hover { background: #ecf5ff; color: #409eff; }
        .ctx-item.danger { color: #f56c6c; }
        .ctx-item.danger:hover { background: #fef0f0; }
        .modal { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.5); justify-content: center; align-items: center; z-index: 2000; }
        .modal.show { display: flex; }
        .modal-box { background: white; padding: 25px; border-radius: 8px; width: 350px; box-shadow: 0 4px 12px rgba(0,0,0,0.15); }
        .modal input { width: 100%; padding: 8px 10px; margin-bottom: 15px; border: 1px solid #dcdfe6; border-radius: 4px; outline: none; box-sizing: border-box; }
        .modal-footer { text-align: right; gap: 10px; display: flex; justify-content: flex-end; }
        .modal-label { font-size: 12px; color: #909399; margin-bottom: 5px; display: block; }
        .presentation-mode { position: fixed; top: 0; left: 0; width: 100vw; height: 100vh; background: black; z-index: 10000; display: none; flex-direction: column; }
        .presentation-mode.active { display: flex; }
        .presentation-header { height: 50px; background: rgba(0,0,0,0.8); color: white; display: flex; align-items: center; justify-content: space-between; padding: 0 20px; font-size: 14px; }
        .presentation-controls { display: flex; gap: 10px; align-items: center; }
        .presentation-controls button { background: rgba(255,255,255,0.2); color: white; border: 1px solid rgba(255,255,255,0.3); }
        .presentation-controls button:hover { background: rgba(255,255,255,0.3); }
        .presentation-iframe { flex: 1; width: 100%; border: none; background: white; }
        .presentation-canvas-container { flex: 1; display: flex; justify-content: center; align-items: center; overflow: auto; background: #525659; }
        .presentation-canvas { max-width: 100%; max-height: 100%; box-shadow: 0 4px 20px rgba(0,0,0,0.5); }
        .presentation-loading { color: white; font-size: 18px; display: flex; flex-direction: column; align-items: center; gap: 15px; }
        .presentation-loading .spinner { width: 40px; height: 40px; border: 4px solid rgba(255,255,255,0.3); border-top-color: white; border-radius: 50%; animation: spin 1s linear infinite; }
        @keyframes spin { to { transform: rotate(360deg); } }
        .page-info { background: rgba(0,0,0,0.6); color: white; padding: 4px 12px; border-radius: 4px; font-size: 12px; }
    <\/style>
<\/head>
<body>
    <div class="container">
        <div class="header">
            <div class="title">WebDAV 网盘 + MQTT演示系统<\/div>
            <div class="mqtt-status">
                <div class="mqtt-indicator" id="mqtt-indicator"><\/div>
                <span id="mqtt-status-text">MQTT: 未连接<\/span>
            <\/div>
        <\/div>
        <div class="toolbar">
            <button class="primary" onclick="triggerUpload()">📤 上传<\/button>
            <button onclick="openModal('mkdir')">📁 建目录<\/button>
            <button style="color:#67c23a; border-color:#e1f3d8; background:#f0f9eb;" onclick="openModal('link')">🔗 存链接<\/button>
            <div style="width:1px; height:20px; background:#eee; margin:0 5px;"><\/div>
            <button onclick="refresh()">🔄 刷新<\/button>
            <div class="sort-group">
                <span style="font-size:12px; color:#909399;">排序:<\/span>
                <select id="sort-select" onchange="applySortAndRender()">
                    <option value="custom">自定义排序<\/option>
                    <option value="name">名称<\/option>
                    <option value="type">类型<\/option>
                    <option value="date">日期<\/option>
                    <option value="folder">文件夹优先<\/option>
                <\/select>
            <\/div>
        <\/div>
        <div class="main-content">
            <div class="left-panel" id="drop-zone">
                <div class="breadcrumb">📍 <span id="current-path">/<\/span><\/div>
                <div class="file-list" id="file-list"><\/div>
            <\/div>
            <div class="right-panel">
                <div class="preview-header">
                    <span id="preview-title">预览区<\/span>
                    <button id="btn-save" class="success" style="display:none; padding:4px 12px;" onclick="saveFile()">💾 保存修改<\/button>
                <\/div>
                <div class="preview-body" id="preview-container">
                    <div class="preview-msg">
                        <div style="font-size:48px; margin-bottom:10px;">🖱️<\/div>
                        <div>在左侧文件上 <b>右键单击<\/b><\/div>
                        <div style="font-size:12px; margin-top:5px;">或 <b>拖拽文件<\/b> 到文件夹移动<\/div>
                        <div style="font-size:12px; margin-top:5px;">点击 <b>演示文件<\/b> 进入全屏演示<\/div>
                    <\/div>
                <\/div>
            <\/div>
        <\/div>
    <\/div>
    <div class="presentation-mode" id="presentation-mode">
        <div class="presentation-header">
            <div>
                <span id="presentation-filename">演示文稿<\/span>
                <span class="page-info" id="page-info">页码: 1 / ?<\/span>
            <\/div>
            <div class="presentation-controls">
                <button onclick="prevPage()">⬅️ 上一页<\/button>
                <button onclick="nextPage()">下一页 ➡️<\/button>
                <button onclick="exitPresentation()">❌ 退出<\/button>
            <\/div>
        <\/div>
        <div class="presentation-canvas-container" id="presentation-canvas-container">
            <div class="presentation-loading" id="presentation-loading">
                <div class="spinner"><\/div>
                <div>正在加载文档...</div>
            <\/div>
            <canvas class="presentation-canvas" id="presentation-canvas" style="display:none;"><\/canvas>
        <\/div>
    <\/div>
    <input type="file" id="upload-input" multiple style="display:none" onchange="handleUpload(this.files)">
    <div id="ctx-menu" class="ctx-menu">
        <div class="ctx-item" onclick="ctxAction('open')">👁️ 打开/预览<\/div>
        <div class="ctx-item" onclick="ctxAction('present')">🎬 全屏演示<\/div>
        <div class="ctx-item" onclick="ctxAction('download')">📥 下载<\/div>
        <div class="ctx-item" onclick="ctxAction('share')">🔗 分享链接<\/div>
        <div style="height:1px; background:#eee; margin:4px 0;"><\/div>
        <div class="ctx-item" onclick="ctxAction('copy')">📋 复制到...<\/div>
        <div class="ctx-item" onclick="ctxAction('move')">🚚 移动到...<\/div>
        <div class="ctx-item" onclick="ctxAction('rename')">✏️ 重命名<\/div>
        <div style="height:1px; background:#eee; margin:4px 0;"><\/div>
        <div class="ctx-item danger" onclick="ctxAction('delete')">🗑️ 删除<\/div>
    <\/div>
    <div id="modal-mkdir" class="modal"><div class="modal-box"><h3>新建文件夹<\/h3><input type="text" id="input-mkdir"><div class="modal-footer"><button onclick="closeModal('mkdir')">取消<\/button><button class="primary" onclick="submitMkdir()">创建<\/button><\/div><\/div><\/div>
    <div id="modal-link" class="modal"><div class="modal-box"><h3>新建视频链接<\/h3><input type="text" id="input-link-name" placeholder="名称 (如: 电影.url)"><input type="text" id="input-link-url" placeholder="网址"><div class="modal-footer"><button onclick="closeModal('link')">取消<\/button><button class="primary" onclick="submitLink()">创建<\/button><\/div><\/div><\/div>
    <div id="modal-rename" class="modal"><div class="modal-box"><h3>重命名<\/h3><input type="text" id="input-rename"><div class="modal-footer"><button onclick="closeModal('rename')">取消<\/button><button class="primary" onclick="submitRename()">确定<\/button><\/div><\/div><\/div>
    <div id="modal-movecopy" class="modal"><div class="modal-box"><h3 id="movecopy-title">移动到<\/h3><span class="modal-label">目标路径 (文件夹必须存在)<\/span><input type="text" id="input-movecopy-dest"><div class="modal-footer"><button onclick="closeModal('movecopy')">取消<\/button><button class="primary" onclick="submitMoveCopy()">确定<\/button><\/div><\/div><\/div>
    <script>
        const CONFIG = {
            WEBDAV: { URL: "https://ajiro.infini-cloud.net/dav/", USER: "chf5762", PASS: "piNdCJ4EPiw5Wtgn" },
            KKFILEVIEW: { URL: window.location.origin + "/api/kkfileview" },  // 使用Worker代理
            MQTT: { BEMFA_KEY: '3eb42d69d8b226abe22024d648975f8a', BROKER: 'wss://bemfa.com:9504/wss', TOPIC: 'PPT-001', STATUS_TOPIC: 'PPT-001-status' },
            PREVIEW_TOKEN: "Allow_Public_Preview_Access_2025"
        };
        
        // 核心工具：Unicode 兼容的 Base64 编码
        function utf8_to_b64(str) {
            return window.btoa(unescape(encodeURIComponent(str)));
        }

        let currentPath = "", selectedFile = null, ctxFile = null, moveCopyMode = "", filesList = [], draggedFile = null, customOrders = {}, mqttClient = null, presentationFile = null, currentPage = 1, totalPages = 0, mqttStats = { sent: 0, received: 0 };
        function initMQTT() {
            try {
                console.log('正在连接MQTT...', CONFIG.MQTT.BROKER);
                mqttClient = mqtt.connect(CONFIG.MQTT.BROKER, { clientId: CONFIG.MQTT.BEMFA_KEY, clean: true, connectTimeout: 4000, reconnectPeriod: 5000, protocolVersion: 4 });
                mqttClient.on('connect', () => {
                    console.log('✅ MQTT连接成功!');
                    document.getElementById('mqtt-indicator').classList.add('connected');
                    document.getElementById('mqtt-status-text').textContent = 'MQTT: 已连接';
                    mqttClient.subscribe(CONFIG.MQTT.TOPIC, { qos: 0 }, (err) => {
                        if (!err) { console.log('✅ 成功订阅主题:', CONFIG.MQTT.TOPIC); publishStatus('idle'); }
                        else { console.error('❌ 订阅失败:', err); }
                    });
                });
                mqttClient.on('message', (topic, message) => { mqttStats.received++; if (topic === CONFIG.MQTT.TOPIC) { handleMQTTCommand(message.toString()); } });
                mqttClient.on('error', (err) => { console.error('❌ MQTT错误:', err); document.getElementById('mqtt-status-text').textContent = 'MQTT: 错误'; });
                mqttClient.on('close', () => { console.log('MQTT连接关闭'); document.getElementById('mqtt-indicator').classList.remove('connected'); document.getElementById('mqtt-status-text').textContent = 'MQTT: 断开'; });
                mqttClient.on('reconnect', () => { console.log('MQTT重连中...'); document.getElementById('mqtt-status-text').textContent = 'MQTT: 重连中...'; });
            } catch (e) { console.error('MQTT初始化失败:', e); }
        }
        function handleMQTTCommand(messageStr) {
            try {
                const cmd = JSON.parse(messageStr);
                console.log('⬇️ 收到MQTT命令:', cmd);
                if (!presentationFile) { console.log('当前未在演示模式'); return; }
                switch(cmd.action) {
                    case 'next': nextPage(); break;
                    case 'prev': prevPage(); break;
                    case 'goto': if (cmd.page) { gotoPage(cmd.page); } break;
                    case 'exit': exitPresentation(); break;
                }
            } catch (e) { console.error('解析MQTT命令失败:', e); }
        }
        function publishStatus(status) {
            if (!mqttClient || !mqttClient.connected) return;
            const statusMsg = { fileName: presentationFile ? presentationFile.name : "", filePath: presentationFile ? presentationFile.path : "", currentPage: currentPage, totalPages: totalPages, status: status, timestamp: Date.now() };
            mqttClient.publish(CONFIG.MQTT.STATUS_TOPIC, JSON.stringify(statusMsg), { qos: 0 }, (err) => {
                if (!err) { mqttStats.sent++; console.log('⬆️ 发布状态:', statusMsg); }
                else { console.error('发布状态失败:', err); }
            });
        }
        function startPresentation(file) {
            presentationFile = file; currentPage = 1; totalPages = 0;
            pdfDoc = null; // 重置 PDF 文档对象
            
            // 显示演示模式和加载提示
            document.getElementById('presentation-filename').textContent = file.name;
            document.getElementById('presentation-mode').classList.add('active');
            document.getElementById('presentation-loading').style.display = 'flex';
            document.getElementById('presentation-canvas').style.display = 'none';
            
            // 判断文件类型
            const ext = file.name.split('.').pop().toLowerCase();
            let pdfUrl;
            
            if (ext === 'pdf') {
                // PDF 文件直接使用 file-proxy
                pdfUrl = \`\${window.location.origin}/api/file-proxy/\${encodeURIComponent(file.name)}?path=\${encodeURIComponent(file.path)}&token=\${CONFIG.PREVIEW_TOKEN}\`;
                console.log('[PDF.js] Loading PDF directly:', pdfUrl);
                loadPdfWithPdfJs(pdfUrl);
            } else {
                // Office 文件需要通过 kkfileview 转换
                // 先获取转换后的 PDF 地址
                const proxyUrl = \`\${window.location.origin}/api/file-proxy/\${encodeURIComponent(file.name)}?path=\${encodeURIComponent(file.path)}&token=\${CONFIG.PREVIEW_TOKEN}\`;
                const b64 = utf8_to_b64(proxyUrl);
                
                // 使用 kkfileview 的 PDF 下载接口
                // KKFileView 转换后会生成 PDF，我们需要获取这个 PDF 的 URL
                pdfUrl = \`\${CONFIG.KKFILEVIEW.URL}/getPdfUrl?url=\${encodeURIComponent(b64)}&fullfilename=\${encodeURIComponent(file.name)}\`;
                
                console.log('[PDF.js] Office file, using kkfileview conversion...');
                console.log('Proxy URL:', proxyUrl);
                
                // 先请求 kkfileview 进行转换，然后获取 PDF
                fetch(\`\${CONFIG.KKFILEVIEW.URL}/onlinePreview?url=\${encodeURIComponent(b64)}&fullfilename=\${encodeURIComponent(file.name)}&officePreviewType=pdf\`)
                    .then(response => response.text())
                    .then(html => {
                        // 从返回的 HTML 中提取 PDF URL 或直接使用代理的 PDF 地址
                        // kkfileview 通常会将转换后的 PDF 放在 /demo/xxx.pdf
                        const pdfMatch = html.match(/src=["']([^"']*\\.pdf[^"']*)["']/i) || 
                                         html.match(/file=["']([^"']*\\.pdf[^"']*)["']/i) ||
                                         html.match(/['"](https?:\\/\\/[^"']*\\.pdf[^"']*)["']/i);
                        
                        if (pdfMatch && pdfMatch[1]) {
                            let extractedPdfUrl = pdfMatch[1];
                            // 如果是相对路径，补全为绝对路径
                            if (extractedPdfUrl.startsWith('/')) {
                                extractedPdfUrl = CONFIG.KKFILEVIEW.URL + extractedPdfUrl;
                            }
                            console.log('[PDF.js] Extracted PDF URL from HTML:', extractedPdfUrl);
                            loadPdfWithPdfJs(extractedPdfUrl);
                        } else {
                            // 如果无法从 HTML 提取，尝试直接使用代理 URL
                            // 很多情况下 kkfileview 会返回一个包含 PDF 的 iframe
                            console.warn('[PDF.js] Could not extract PDF URL from HTML, trying proxy directly');
                            // 尝试从 getCorsFile 接口获取
                            const corsFileUrl = \`\${CONFIG.KKFILEVIEW.URL}/getCorsFile?urlPath=\${encodeURIComponent(b64)}\`;
                            loadPdfWithPdfJs(corsFileUrl);
                        }
                    })
                    .catch(err => {
                        console.error('[PDF.js] Failed to get converted PDF:', err);
                        showPresentationError('文档转换失败: ' + err.message);
                    });
            }
            
            // 全屏
            const elem = document.getElementById('presentation-mode');
            if (elem.requestFullscreen) { elem.requestFullscreen().catch(err => console.log('全屏失败:', err)); }
            
            updatePageInfo(); 
            publishStatus('presenting');
        }
        
        // PDF.js 加载和渲染
        let pdfDoc = null;
        
        function loadPdfWithPdfJs(url) {
            console.log('[PDF.js] Loading PDF from:', url);
            
            // 设置 PDF.js worker
            pdfjsLib.GlobalWorkerOptions.workerSrc = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';
            
            pdfjsLib.getDocument({
                url: url,
                withCredentials: false
            }).promise.then(pdf => {
                pdfDoc = pdf;
                totalPages = pdf.numPages;
                currentPage = 1;
                console.log('[PDF.js] PDF loaded successfully! Total pages:', totalPages);
                
                // 隐藏加载提示，显示 canvas
                document.getElementById('presentation-loading').style.display = 'none';
                document.getElementById('presentation-canvas').style.display = 'block';
                
                // 渲染第一页
                renderPage(currentPage);
                updatePageInfo();
                publishStatus('presenting');
            }).catch(err => {
                console.error('[PDF.js] Failed to load PDF:', err);
                showPresentationError('PDF 加载失败: ' + err.message);
            });
        }
        
        function renderPage(pageNum) {
            if (!pdfDoc) return;
            
            pdfDoc.getPage(pageNum).then(page => {
                const canvas = document.getElementById('presentation-canvas');
                const ctx = canvas.getContext('2d');
                
                // 计算合适的缩放比例，使页面适应容器
                const container = document.getElementById('presentation-canvas-container');
                const containerWidth = container.clientWidth - 40; // 留一些边距
                const containerHeight = container.clientHeight - 40;
                
                const viewport = page.getViewport({ scale: 1 });
                const scaleX = containerWidth / viewport.width;
                const scaleY = containerHeight / viewport.height;
                const scale = Math.min(scaleX, scaleY, 2); // 最大2倍缩放
                
                const scaledViewport = page.getViewport({ scale: scale });
                
                canvas.width = scaledViewport.width;
                canvas.height = scaledViewport.height;
                
                const renderContext = {
                    canvasContext: ctx,
                    viewport: scaledViewport
                };
                
                page.render(renderContext).promise.then(() => {
                    console.log('[PDF.js] Page', pageNum, 'rendered successfully');
                }).catch(err => {
                    console.error('[PDF.js] Page render failed:', err);
                });
            });
        }
        
        function showPresentationError(message) {
            const loadingEl = document.getElementById('presentation-loading');
            loadingEl.innerHTML = \`<div style="color: #ff6b6b;">❌ \${message}</div><button onclick="exitPresentation()" style="margin-top:15px;">关闭</button>\`;
        }

function exitPresentation() {
    document.getElementById('presentation-mode').classList.remove('active');
    // 重置 canvas
    const canvas = document.getElementById('presentation-canvas');
    const ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    // 重置加载提示
    document.getElementById('presentation-loading').innerHTML = '<div class="spinner"></div><div>正在加载文档...</div>';
    
    pdfDoc = null;
    presentationFile = null; 
    currentPage = 1; 
    totalPages = 0; 
    publishStatus('idle');
    if (document.fullscreenElement) { document.exitFullscreen(); }
}

function nextPage() { 
    if (!pdfDoc || currentPage >= totalPages) return;
    currentPage++; 
    renderPage(currentPage);
    updatePageInfo(); 
    publishStatus('presenting');
}

function prevPage() { 
    if (!pdfDoc || currentPage <= 1) return;
    currentPage--; 
    renderPage(currentPage);
    updatePageInfo(); 
    publishStatus('presenting');
}

function gotoPage(page) { 
    if (!pdfDoc) return;
    page = parseInt(page);
    if (page < 1) page = 1;
    if (page > totalPages) page = totalPages;
    currentPage = page; 
    renderPage(currentPage);
    updatePageInfo(); 
    publishStatus('presenting');
}
        function updatePageInfo() { document.getElementById('page-info').textContent = \`页码: \${currentPage}\${totalPages ? ' / ' + totalPages : ''}\`; }
        document.addEventListener('keydown', (e) => {
            if (!presentationFile) return;
            if (e.key === 'ArrowRight' || e.key === 'PageDown') { e.preventDefault(); nextPage(); }
            else if (e.key === 'ArrowLeft' || e.key === 'PageUp') { e.preventDefault(); prevPage(); }
            else if (e.key === 'Escape') { e.preventDefault(); exitPresentation(); }
        });
        function getAuthHeader() { return "Basic " + btoa(CONFIG.WEBDAV.USER + ":" + CONFIG.WEBDAV.PASS); }
        function getFileDownloadUrl(path, inline = false) {
            const baseUrl = window.location.origin;
            const disposition = inline ? '&inline=true' : '';
            return \`\${baseUrl}/api/download?path=\${encodeURIComponent(path)}&token=\${CONFIG.PREVIEW_TOKEN}\${disposition}\`;
        }
        function isPresentationFile(filename) {
            const ext = filename.split('.').pop().toLowerCase();
            return ['ppt', 'pptx', 'pdf', 'xls', 'xlsx', 'doc', 'docx'].includes(ext);
        }
        try { const saved = localStorage.getItem('webdav_custom_orders'); if (saved) customOrders = JSON.parse(saved); } catch(e) {}
        loadFiles(""); initMQTT();
        document.addEventListener('click', () => { document.getElementById('ctx-menu').style.display = 'none'; });
        document.getElementById('file-list').addEventListener('contextmenu', e => { e.preventDefault(); });
        function setupDragDrop(item, fileObj, index) {
            item.setAttribute('draggable', 'true');
            item.addEventListener('dragstart', (e) => { draggedFile = fileObj; item.classList.add('dragging'); e.dataTransfer.effectAllowed = 'move'; e.dataTransfer.setData('text/plain', index); });
            item.addEventListener('dragend', (e) => { item.classList.remove('dragging'); document.querySelectorAll('.drag-over, .drag-over-top, .drag-over-bottom').forEach(el => { el.classList.remove('drag-over', 'drag-over-top', 'drag-over-bottom'); }); });
            const sortMode = document.getElementById('sort-select').value;
            if (sortMode === 'custom') {
                item.addEventListener('dragover', (e) => { if (!draggedFile || draggedFile.path === fileObj.path) return; e.preventDefault(); e.dataTransfer.dropEffect = 'move'; const rect = item.getBoundingClientRect(); const midY = rect.top + rect.height / 2; item.classList.remove('drag-over-top', 'drag-over-bottom'); if (e.clientY < midY) { item.classList.add('drag-over-top'); } else { item.classList.add('drag-over-bottom'); } });
                item.addEventListener('dragleave', (e) => { item.classList.remove('drag-over-top', 'drag-over-bottom'); });
                item.addEventListener('drop', (e) => { e.preventDefault(); item.classList.remove('drag-over-top', 'drag-over-bottom'); if (!draggedFile || draggedFile.path === fileObj.path) return; const draggedIndex = filesList.findIndex(f => f.path === draggedFile.path); const targetIndex = filesList.findIndex(f => f.path === fileObj.path); if (draggedIndex === -1 || targetIndex === -1) return; const [removed] = filesList.splice(draggedIndex, 1); const rect = item.getBoundingClientRect(); const midY = rect.top + rect.height / 2; let insertIndex = targetIndex; if (draggedIndex < targetIndex && e.clientY > midY) { insertIndex = targetIndex; } else if (draggedIndex < targetIndex && e.clientY < midY) { insertIndex = targetIndex; } else if (draggedIndex > targetIndex && e.clientY < midY) { insertIndex = targetIndex; } else if (draggedIndex > targetIndex && e.clientY > midY) { insertIndex = targetIndex + 1; } filesList.splice(insertIndex, 0, removed); saveCustomOrder(); renderSortedList(); });
            } else if (fileObj.isDir) {
                item.addEventListener('dragover', (e) => { if (draggedFile && draggedFile.path !== fileObj.path) { e.preventDefault(); e.dataTransfer.dropEffect = 'move'; item.classList.add('drag-over'); } });
                item.addEventListener('dragleave', (e) => { item.classList.remove('drag-over'); });
                item.addEventListener('drop', async (e) => { e.preventDefault(); item.classList.remove('drag-over'); if (!draggedFile || draggedFile.path === fileObj.path) return; const fileName = draggedFile.name; const destPath = fileObj.path + '/' + fileName; try { const res = await fetch('/api/move?source=' + encodeURIComponent(draggedFile.path) + '&dest=' + encodeURIComponent(destPath)); if (res.ok) { loadFiles(currentPath); document.getElementById("preview-container").innerHTML = '<div class="preview-msg">文件已移动到 ' + fileObj.name + '<\/div>'; } else { alert('移动失败'); } } catch(e) { alert('操作出错'); } });
            }
        }
        function applySortAndRender() { const sortType = document.getElementById('sort-select').value; sortFiles(sortType); renderSortedList(); }
        function sortFiles(type) {
            switch(type) {
                case 'custom': loadCustomOrder(); break;
                case 'name': filesList.sort((a, b) => a.name.localeCompare(b.name)); break;
                case 'type': filesList.sort((a, b) => { const extA = a.name.split('.').pop().toLowerCase(); const extB = b.name.split('.').pop().toLowerCase(); return extA.localeCompare(extB) || a.name.localeCompare(b.name); }); break;
                case 'date': filesList.sort((a, b) => new Date(b.modTime || 0) - new Date(a.modTime || 0)); break;
                case 'folder': filesList.sort((a, b) => { if (a.isDir && !b.isDir) return -1; if (!a.isDir && b.isDir) return 1; return a.name.localeCompare(b.name); }); break;
            }
        }
        function saveCustomOrder() { const order = filesList.map(f => f.path); customOrders[currentPath || '/'] = order; try { localStorage.setItem('webdav_custom_orders', JSON.stringify(customOrders)); } catch(e) {} }
        function loadCustomOrder() { try { const saved = localStorage.getItem('webdav_custom_orders'); if (saved) customOrders = JSON.parse(saved); } catch(e) {} const order = customOrders[currentPath || '/']; if (!order) return; const ordered = []; order.forEach(path => { const file = filesList.find(f => f.path === path); if (file) ordered.push(file); }); filesList.forEach(file => { if (!ordered.find(f => f.path === file.path)) { ordered.push(file); } }); filesList = ordered; }
        function renderSortedList() {
            const listEl = document.getElementById("file-list"); listEl.innerHTML = "";
            if (currentPath) { const back = document.createElement("div"); back.className = "file-item"; back.innerHTML = '<div class="file-icon">↩️<\/div><div class="file-name">..<\/div>'; back.onclick = () => loadFiles(currentPath.split("/").slice(0, -1).join("/")); listEl.appendChild(back); }
            filesList.forEach((fileObj, index) => {
                const item = document.createElement("div"); item.className = "file-item";
                const badge = isPresentationFile(fileObj.name) && !fileObj.isDir ? '<span class="file-badge">演示<\/span>' : '';
                item.innerHTML = \`<div class="file-icon">\${getIcon(fileObj.name, fileObj.isDir)}<\/div><div class="file-name">\${fileObj.name}<\/div>\${badge}\`;
                item.onclick = () => { document.querySelectorAll(".file-item").forEach(el => el.classList.remove("selected")); item.classList.add("selected"); selectedFile = fileObj; if(!fileObj.isDir) { if (isPresentationFile(fileObj.name)) { startPresentation(fileObj); } else { previewFile(fileObj); } } };
                item.ondblclick = () => { if (fileObj.isDir) loadFiles(fileObj.path); };
                item.oncontextmenu = (e) => showCtxMenu(e, fileObj);
                setupDragDrop(item, fileObj, index);
                listEl.appendChild(item);
            });
        }
        async function loadFiles(path) { try { const res = await fetch('/api/list?path=' + encodeURIComponent(path)); const text = await res.text(); parseFileList(text, path); currentPath = path; document.getElementById('current-path').textContent = path || "/"; selectedFile = null; applySortAndRender(); } catch (e) { console.error(e); } }
        function parseFileList(xmlString, path) {
            const parser = new DOMParser(); const xml = parser.parseFromString(xmlString, "text/xml"); filesList = [];
            xml.querySelectorAll("response").forEach(resp => {
                const href = resp.querySelector("href").textContent;
                let name = decodeURIComponent(href.replace(/\\/$/, "").split("/").pop());
                if (!name || (path && name === path.split("/").pop())) return;
                const isDir = resp.querySelector("collection") !== null;
                const modTimeEl = resp.querySelector("getlastmodified");
                const modTime = modTimeEl ? modTimeEl.textContent : null;
                const fullPath = path ? path + "/" + name : name;
                filesList.push({ path: fullPath, name: name, isDir: isDir, modTime: modTime });
            });
        }
        function showCtxMenu(e, file) { e.preventDefault(); e.stopPropagation(); ctxFile = file; document.querySelectorAll(".file-item").forEach(el => el.classList.remove("selected")); e.currentTarget.classList.add("selected"); selectedFile = file; const menu = document.getElementById('ctx-menu'); menu.style.display = 'block'; menu.style.left = e.pageX + 'px'; menu.style.top = e.pageY + 'px'; }
        async function ctxAction(action) {
            if (!ctxFile) return; const file = ctxFile;
            switch(action) {
                case 'open': if (file.isDir) loadFiles(file.path); else previewFile(file); break;
                case 'present': if (!file.isDir && isPresentationFile(file.name)) { startPresentation(file); } else { alert('此文件不支持演示模式'); } break;
                case 'download': if (file.isDir) return alert("文件夹不支持直接下载"); window.open('/api/download?path=' + encodeURIComponent(file.path)); break;
                case 'share': const shareUrl = window.location.origin + '/api/download?path=' + encodeURIComponent(file.path) + '&token=' + CONFIG.PREVIEW_TOKEN; try { await navigator.clipboard.writeText(shareUrl); alert("✅ 分享链接已复制到剪贴板!"); } catch(e) { alert("复制失败: " + shareUrl); } break;
                case 'delete': if (!confirm("确定删除 " + file.name + " 吗?")) return; await fetch("/api/delete?path=" + encodeURIComponent(file.path)); loadFiles(currentPath); break;
                case 'rename': document.getElementById("input-rename").value = file.name; openModal('rename'); break;
                case 'move': moveCopyMode = 'move'; openMoveCopyModal(); break;
                case 'copy': moveCopyMode = 'copy'; openMoveCopyModal(); break;
            }
        }
        function openMoveCopyModal() { document.getElementById('movecopy-title').textContent = moveCopyMode === 'move' ? '移动到...' : '复制到...'; document.getElementById('input-movecopy-dest').value = ctxFile.path; openModal('movecopy'); }
        async function submitMoveCopy() {
            const destPath = document.getElementById('input-movecopy-dest').value.trim();
            if (!destPath || !ctxFile) return; if (destPath === ctxFile.path) return closeModal('movecopy');
            const endpoint = moveCopyMode === 'move' ? '/api/move' : '/api/copy';
            const btn = document.querySelector('#modal-movecopy .primary'); const originalText = btn.textContent; btn.textContent = "执行中..."; btn.disabled = true;
            try { const res = await fetch(endpoint + '?source=' + encodeURIComponent(ctxFile.path) + '&dest=' + encodeURIComponent(destPath)); if (res.ok) { closeModal('movecopy'); loadFiles(currentPath); if (moveCopyMode === 'move') { document.getElementById("preview-container").innerHTML = '<div class="preview-msg">文件已移动<\/div>'; document.getElementById('btn-save').style.display = 'none'; } } else { alert("操作失败 (可能是目标文件夹不存在)"); } } catch (e) { alert("网络错误"); }
            btn.textContent = originalText; btn.disabled = false;
        }
        async function previewFile(file) {
            const container = document.getElementById("preview-container"); const title = document.getElementById("preview-title"); const btnSave = document.getElementById("btn-save");
            btnSave.style.display = 'none'; container.innerHTML = '<div class="preview-msg">加载中...<\/div>'; title.textContent = file.name;
            const ext = file.name.split('.').pop().toLowerCase(); const fileUrl = getFileDownloadUrl(file.path, true);
            if (ext === 'url') { try { const res = await fetch(fileUrl); let targetUrl = (await res.text()).trim(); renderExternalLink(targetUrl, container); } catch(e) { container.innerHTML = '链接无效'; } return; }
            if (['txt', 'js', 'json', 'css', 'html', 'xml', 'md', 'py', 'java', 'log'].includes(ext)) { try { const res = await fetch(fileUrl); const text = await res.text(); container.innerHTML = \`<textarea id="editor-textarea" spellcheck="false">\${escapeHtml(text)}<\/textarea>\`; btnSave.style.display = 'block'; } catch(e) { container.innerHTML = '文本加载失败'; } return; }
            if (['jpg', 'jpeg', 'png', 'gif', 'svg'].includes(ext)) { container.innerHTML = \`<img src="\${fileUrl}" class="preview-img">\`; return; }
            if (ext === 'pdf') { container.innerHTML = \`<iframe src="\${fileUrl}" class="preview-iframe"><\/iframe>\`; return; }
            if (['mp4', 'webm'].includes(ext)) { container.innerHTML = \`<video src="\${fileUrl}" controls autoplay class="preview-video"><\/video>\`; return; }
            if (['doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx'].includes(ext)) { const officeUrl = 'https://view.officeapps.live.com/op/embed.aspx?src=' + encodeURIComponent(fileUrl); container.innerHTML = \`<iframe src="\${officeUrl}" class="preview-iframe" onload="this.style.display='block'" onerror="this.parentElement.innerHTML='<div class=\\\\"preview-msg\\\\">Office在线预览失败<br><br>请下载后查看<\/div>'"><\/iframe>\`; return; }
            container.innerHTML = '<div class="preview-msg">不支持预览<br><br>请使用右键下载<\/div>';
        }
        function renderExternalLink(url, container) { let embedUrl = url; if (url.includes('bilibili.com')) embedUrl = 'https://player.bilibili.com/player.html?bvid=' + url.match(/BV[a-zA-Z0-9]+/)[0] + '&high_quality=1'; else if (url.includes('youtube.com')) embedUrl = 'https://www.youtube.com/embed/' + url.split('v=')[1].split('&')[0]; else if (url.match(/\\.(mp4|webm)$/)) { container.innerHTML = \`<video src="\${url}" controls autoplay class="preview-video"><\/video>\`; return; } container.innerHTML = \`<div class="link-bar"><span>⚠️ 外部视频<\/span><a href="\${url}" target="_blank" style="background:#e6a23c;color:white;text-decoration:none;padding:4px 10px;border-radius:4px">跳转观看<\/a><\/div><iframe src="\${embedUrl}" class="preview-iframe"><\/iframe>\`; }
        async function saveFile() { if (!selectedFile) return; const content = document.getElementById("editor-textarea").value; const btn = document.getElementById("btn-save"); btn.textContent = "保存中..."; await fetch('/api/upload?path=' + encodeURIComponent(selectedFile.path), { method: 'PUT', body: content }); btn.textContent = "✅ 已保存"; setTimeout(() => { btn.textContent = "💾 保存修改"; }, 2000); }
        async function submitRename() { const name = document.getElementById("input-rename").value.trim(); if (!name || !ctxFile) return; const pathArr = ctxFile.path.split("/"); pathArr.pop(); const newPath = (pathArr.length ? pathArr.join("/") + "/" : "") + name; await fetch('/api/move?source=' + encodeURIComponent(ctxFile.path) + '&dest=' + encodeURIComponent(newPath)); closeModal('rename'); loadFiles(currentPath); }
        async function submitMkdir() { const name = document.getElementById("input-mkdir").value.trim(); if (!name) return; await fetch("/api/mkdir?path=" + encodeURIComponent(currentPath ? currentPath+"/"+name : name)); closeModal('mkdir'); loadFiles(currentPath); }
        async function submitLink() { let name = document.getElementById("input-link-name").value.trim(); const url = document.getElementById("input-link-url").value.trim(); if (!name.endsWith('.url')) name += '.url'; const path = currentPath ? currentPath + "/" + name : name; await fetch('/api/create-link?path=' + encodeURIComponent(path), { method: 'POST', body: url }); closeModal('link'); loadFiles(currentPath); }
        function triggerUpload() { document.getElementById("upload-input").click(); }
        async function handleUpload(files) { for (let file of files) { const path = currentPath ? currentPath + "/" + file.name : file.name; await fetch("/api/upload?path=" + encodeURIComponent(path), { method: "POST", body: file }); } loadFiles(currentPath); }
        function refresh() { loadFiles(currentPath); }
        function openModal(type) { document.querySelectorAll('input').forEach(i => i.value=''); document.getElementById('modal-'+type).classList.add('show'); }
        function closeModal(type) { document.getElementById('modal-'+type).classList.remove('show'); }
        function escapeHtml(text) { return text.replace(/[&<>"']/g, function(m) { return {'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;'}[m]; }); }
        function getIcon(name, isDir) { if(isDir) return '📁'; const ext = name.split('.').pop().toLowerCase(); if (ext === 'url') return '🔗'; if (['ppt','pptx'].includes(ext)) return '📊'; if (['pdf'].includes(ext)) return '📕'; if (['xls','xlsx'].includes(ext)) return '📗'; if (['doc','docx'].includes(ext)) return '📘'; if (['jpg','png','gif'].includes(ext)) return '🖼️'; if (['mp4','webm'].includes(ext)) return '🎬'; if (['txt','js','md','json'].includes(ext)) return '📝'; return '📄'; }
    <\/script>
<\/body>
<\/html>`;
