@echo off
chcp 65001 >nul
echo ========================================
echo Cloudflare 管理工具 - 项目初始化脚本
echo ========================================
echo.

REM 设置项目目录名
set PROJECT_DIR=cloudflare_manager

REM 检查目录是否存在
if exist "%PROJECT_DIR%" (
    echo [警告] 目录 %PROJECT_DIR% 已存在!
    set /p continue="是否删除并重新创建? (Y/N): "
    if /i "%continue%"=="Y" (
        rd /s /q "%PROJECT_DIR%"
        echo [完成] 已删除旧目录
    ) else (
        echo [取消] 操作已取消
        pause
        exit /b
    )
)

REM 创建项目目录
echo.
echo [1/5] 创建项目目录...
mkdir "%PROJECT_DIR%"
cd "%PROJECT_DIR%"
echo [完成] 目录创建成功: %PROJECT_DIR%

REM 创建空文件
echo.
echo [2/5] 创建 Python 文件...
type nul > constants.py
type nul > config.py
type nul > api_client.py
type nul > main.py
echo [完成] 已创建 4 个 Python 文件

REM 创建 requirements.txt
echo.
echo [3/5] 创建 requirements.txt...
(
echo requests==2.31.0
) > requirements.txt
echo [完成] requirements.txt 创建成功

REM 创建 README.txt
echo.
echo [4/5] 创建 README.txt...
(
echo ========================================
echo Cloudflare 管理工具
echo ========================================
echo.
echo 文件说明:
echo   constants.py  - API 常量定义
echo   config.py     - 配置管理
echo   api_client.py - API 客户端
echo   main.py       - 主程序GUI
echo.
echo 安装依赖:
echo   pip install -r requirements.txt
echo.
echo 运行程序:
echo   python main.py
echo.
echo 打包成 exe:
echo   pip install pyinstaller
echo   pyinstaller --onefile --windowed --name=CloudflareManager main.py
echo.
echo 使用步骤:
echo   1. 复制代码到对应的 .py 文件中
echo   2. 安装依赖: pip install requests
echo   3. 运行: python main.py
echo   4. 输入 Cloudflare Token 并保存
echo   5. 开始管理你的 Cloudflare 资源
echo.
) > README.txt
echo [完成] README.txt 创建成功

REM 创建打包脚本
echo.
echo [5/5] 创建打包脚本 build.bat...
(
echo @echo off
echo chcp 65001 ^>nul
echo echo ========================================
echo echo 打包 Cloudflare 管理工具
echo echo ========================================
echo echo.
echo.
echo echo [检查] 检查 PyInstaller...
echo pip show pyinstaller ^>nul 2^>^&1
echo if errorlevel 1 (
echo     echo [安装] 正在安装 PyInstaller...
echo     pip install pyinstaller
echo ^)
echo.
echo echo [打包] 开始打包程序...
echo pyinstaller --onefile --windowed --name=CloudflareManager --icon=NONE main.py
echo.
echo if errorlevel 0 (
echo     echo.
echo     echo [成功] 打包完成!
echo     echo [位置] 可执行文件: dist\CloudflareManager.exe
echo     echo.
echo ^) else (
echo     echo.
echo     echo [错误] 打包失败!
echo     echo.
echo ^)
echo.
echo pause
) > build.bat
echo [完成] build.bat 创建成功

echo.
echo ========================================
echo 初始化完成!
echo ========================================
echo.
echo 项目目录: %CD%
echo.
echo 文件列表:
echo   ├─ constants.py       (待复制代码)
echo   ├─ config.py          (待复制代码)
echo   ├─ api_client.py      (待复制代码)
echo   ├─ main.py            (待复制代码)
echo   ├─ requirements.txt   (已完成)
echo   ├─ README.txt         (已完成)
echo   └─ build.bat          (已完成)
echo.
echo 下一步操作:
echo   1. 复制 constants.py 的代码到 constants.py 文件
echo   2. 复制 config.py 的代码到 config.py 文件
echo   3. 复制 api_client.py 的代码到 api_client.py 文件
echo   4. 复制 main.py 的代码到 main.py 文件
echo   5. 运行: pip install -r requirements.txt
echo   6. 运行: python main.py
echo.
echo 打包成 EXE:
echo   双击运行 build.bat
echo.
pause

REM 打开项目目录
explorer .