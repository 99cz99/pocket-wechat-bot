@echo off
chcp 65001 >nul 2>nul
REM deploy.bat — PC 端一键部署 pocket-wechat-bot 到 Android 手机
REM 用法：USB 连接手机 → 双击此文件
REM 前置：adb 已安装并在 PATH 中，手机已授权 USB 调试，Termux 已安装
REM
REM 可选：运行前 set 环境变量跳过交互
REM   set DEPLOY_API_KEY=sk-xxx
REM   set DEPLOY_OPENID=xxx
REM   deploy.bat
REM ============================================================

setlocal enabledelayedexpansion

echo.
echo   ╔══════════════════════════════════════╗
echo   ║  pocket-wechat-bot · PC 端一键部署  ║
echo   ╚══════════════════════════════════════╝
echo.

REM ---- 1. 检查 ADB ----
echo [*] 检查 ADB 连接...

where adb >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] 未找到 adb 命令
    echo     下载 Android Platform Tools 并加入 PATH:
    echo     https://developer.android.com/studio/releases/platform-tools
    pause
    exit /b 1
)

REM 列出设备
adb devices 2>nul | findstr "device$" >nul
if %errorlevel% neq 0 (
    echo [!] 未检测到已连接的 Android 设备
    echo.
    echo   请确认：
    echo   1. USB 已连接，手机上已授权「USB 调试」
    echo   2. 运行 adb devices 能看到设备
    echo.
    adb devices
    pause
    exit /b 1
)

for /f "tokens=1" %%d in ('adb devices 2^>nul ^| findstr "device$"') do set DEVICE=%%d
echo [*] 设备: %DEVICE%

REM ---- 2. 打包项目（排除 .git）----
echo.
echo [*] 打包项目文件...

set SCRIPT_DIR=%~dp0
set REPO_DIR=%SCRIPT_DIR%..
set TAR_FILE=%TEMP%\pocket-wechat-bot-deploy.tar

pushd "%REPO_DIR%"
REM git archive 打包 HEAD（不含 .git，不含未提交文件）
git archive -o "%TAR_FILE%" HEAD 2>nul
if %errorlevel% neq 0 (
    echo [!] git archive 失败，尝试 format=tar...
    git archive --format=tar HEAD > "%TAR_FILE%" 2>nul
    if %errorlevel% neq 0 (
        echo [!] 无法打包项目（git 不可用？），回退到 adb push 目录
        echo [*] 使用 adb push（含 .git，约 1-2 分钟）...
        popd
        goto push_fallback
    )
)
popd
echo [*] 打包完成: %TAR_FILE%

REM ---- 3. 推送 tar 到手机并解压 ----
echo [*] 推送 %TAR_FILE% 到手机 (/sdcard/Download/)...
adb push "%TAR_FILE%" /sdcard/Download/pocket-wechat-bot.tar
if %errorlevel% neq 0 (
    echo [!] 推送失败，回退到 adb push 目录...
    goto push_fallback
)

echo [*] 在手机上解压...
adb shell "mkdir -p /sdcard/Download/pocket-wechat-bot && cd /sdcard/Download/pocket-wechat-bot && tar xf /sdcard/Download/pocket-wechat-bot.tar && rm /sdcard/Download/pocket-wechat-bot.tar"

if %errorlevel% neq 0 (
    echo [!] 解压失败，回退到 adb push...
    adb shell "rm -rf /sdcard/Download/pocket-wechat-bot" 2>nul
    goto push_fallback
)
goto files_ready

:push_fallback
REM 回退方案：直接用 adb push 推送目录（含 .git，约 1-2 分钟）
pushd "%REPO_DIR%"
echo [*] adb push 整个目录到 /sdcard/Download/pocket-wechat-bot/ ...
echo     这可能需要 1-2 分钟，请耐心等待...
adb push . /sdcard/Download/pocket-wechat-bot/
if %errorlevel% neq 0 (
    echo [!] 推送失败！检查 USB 连接和存储空间
    popd
    pause
    exit /b 1
)
popd

:files_ready
echo [*] 项目文件已推送到手机

REM ---- 4. 复制到 Termux 并执行 ----
echo.
echo [*] 复制到 Termux 并执行部署脚本...

REM 尝试 run-as（直接写入 Termux 私有目录）
adb shell "rm -rf /sdcard/Download/pocket-wechat-bot/.git" 2>nul
adb shell "cd /sdcard/Download && tar czf - pocket-wechat-bot/ 2>/dev/null | run-as com.termux sh -c 'cd ~ && rm -rf pocket-wechat-bot && tar xzf -'" 2>nul

if %errorlevel% neq 0 (
    REM run-as 不可用，提示手动操作
    echo.
    echo   [!] 无法自动写入 Termux（非 Debug 版 Termux / Android 14+）
    echo.
    echo   项目文件已在 /sdcard/Download/pocket-wechat-bot/
    echo   请在手机 Termux 中执行以下两条命令完成部署：
    echo.
    echo     cp -r /sdcard/Download/pocket-wechat-bot ~/
    echo     cd ~/pocket-wechat-bot ^&^& bash scripts/setup-phone.sh
    echo.
    goto epilogue
)

REM run-as 成功，远程执行脚本
echo [*] 正在执行手机端部署...
echo.
echo   ─────────────────────────────────────
echo     手机端输出：
echo   ─────────────────────────────────────
echo.

REM 构建环境变量
set ENV_PREFIX=
if defined DEPLOY_API_KEY (
    set ENV_PREFIX=DEPLOY_API_KEY=!DEPLOY_API_KEY!
)
if defined DEPLOY_OPENID (
    if defined ENV_PREFIX (
        set ENV_PREFIX=!ENV_PREFIX! DEPLOY_OPENID=!DEPLOY_OPENID!
    ) else (
        set ENV_PREFIX=DEPLOY_OPENID=!DEPLOY_OPENID!
    )
)
REM 从 PC 端部署时默认非交互
if defined ENV_PREFIX (
    set ENV_PREFIX=!ENV_PREFIX! DEPLOY_NONINTERACTIVE=1
) else (
    set ENV_PREFIX=DEPLOY_NONINTERACTIVE=1
)

REM 在 Termux 中运行部署脚本
adb shell "run-as com.termux sh -c 'cd ~/pocket-wechat-bot && !ENV_PREFIX! bash scripts/setup-phone.sh'"

echo.
echo   ─────────────────────────────────────
echo     手机端输出结束
echo   ─────────────────────────────────────

REM ---- 5. 收尾 ----
:epilogue
echo.
echo   ╔══════════════════════════════════════════╗
echo   ║  还需手动完成：                          ║
echo   ╠══════════════════════════════════════════╣
echo   ║                                          ║
echo   ║  1. 微信扫码获取 token：                 ║
echo   ║     ~/bin/cc-connect weixin setup \      ║
echo   ║       --project nene                     ║
echo   ║     扫码后把 token/account_id 填入      ║
echo   ║     ~/.cc-connect/config.toml           ║
echo   ║                                          ║
echo   ║  2. 关闭电池优化：                       ║
echo   ║     设置 → 应用 → Termux → 电池         ║
echo   ║     → 允许后台运行                      ║
echo   ║                                          ║
echo   ║  3. 发微信消息测试                       ║
echo   ║                                          ║
echo   ╚══════════════════════════════════════════╝
echo.
echo   管理面板: http://127.0.0.1:9820
echo   查看日志: cat ~/cc-connect/bot-debug.log
echo   重新部署: 再次运行此脚本或手机端 bash setup-phone.sh
echo.

pause
