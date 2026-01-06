# 1. 设置执行权限
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# 2. 检查并创建配置文件所在的文件夹
$profileDir = Split-Path $PROFILE
if (!(Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force }

# 3. 将代理配置代码直接写入配置文件 (覆盖模式)
$configContent = @'
# 自动设置 10808 代理
$env:HTTP_PROXY = "http://127.0.0.1:10808"
$env:HTTPS_PROXY = "http://127.0.0.1:10808"
$env:ALL_PROXY = "socks5://127.0.0.1:10808"

# 设置窗口标题
$host.ui.RawUI.WindowTitle = "PowerShell (Proxy On: 10808)"

# 快捷函数
function proxy_on {
    $env:HTTP_PROXY = "http://127.0.0.1:10808"; $env:HTTPS_PROXY = "http://127.0.0.1:10808"
    $env:ALL_PROXY = "socks5://127.0.0.1:10808"
    $host.ui.RawUI.WindowTitle = "PowerShell (Proxy On: 10808)"
    Write-Host "代理已开启" -ForegroundColor Green
}
function proxy_off {
    $env:HTTP_PROXY = $null; $env:HTTPS_PROXY = $null; $env:ALL_PROXY = $null
    $host.ui.RawUI.WindowTitle = "PowerShell (Proxy Off)"
    Write-Host "代理已关闭" -ForegroundColor Red
}
'@

Set-Content -Path $PROFILE -Value $configContent -Encoding utf8

Write-Host "--- 配置完成！请重新打开 PowerShell 即可生效 ---" -ForegroundColor Cyan
