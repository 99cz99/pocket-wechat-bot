@echo off
chcp 65001 >nul 2>nul
setlocal enabledelayedexpansion

REM ============================================================
REM  deploy.bat - 一键部署微信 AI 机器人到 Android 手机
REM  用法: USB 连接手机 -> 双击此文件
REM  需要: adb + 手机已授权 USB 调试 + 手机已安装 Termux
REM ============================================================

set "REPO=%~dp0.."
set "TGZ=%TEMP%\pwb-deploy.tar"

echo.
echo  ╔══════════════════════════════════════╗
echo  ║  微信 AI 机器人 - PC 端一键部署      ║
echo  ╚══════════════════════════════════════╝
echo.

REM ----- 检查 ADB -----
echo [*] 检查 ADB 连接...
where adb >nul 2>&1
if errorlevel 1 (
    echo [!] 找不到 adb，请先安装 Android Platform Tools
    echo     https://developer.android.com/studio/releases/platform-tools
    pause
    exit /b 1
)
adb shell echo ok >nul 2>&1
if errorlevel 1 (
    echo [!] 未检测到手机，请确认：
    echo     1. USB 已连接
    echo     2. 手机已开启 USB 调试
    echo     3. 手机上已授权此电脑
    echo.
    adb devices
    pause
    exit /b 1
)
echo [*] ADB 连接正常

REM ----- 检查 Termux -----
echo [*] 检查 Termux...
adb shell "pm list packages com.termux" 2>nul | find "com.termux" >nul
if errorlevel 1 (
    echo [!] 手机未安装 Termux，请先在 F-Droid 下载：
    echo     https://f-droid.org/packages/com.termux/
    echo     还需安装 Termux:API（F-Droid 搜索）
    pause
    exit /b 1
)
echo [*] Termux 已安装

REM ----- 打包项目 -----
echo [*] 正在打包项目文件...
pushd "%REPO%"
git archive -o "%TGZ%" HEAD 2>nul
if errorlevel 1 (
    git archive HEAD > "%TGZ%" 2>nul
    if errorlevel 1 (
        echo [!] 打包失败，请确认 git 已安装
        popd
        pause
        exit /b 1
    )
)
popd
echo [*] 打包完成

REM ----- 推送到手机 -----
echo [*] 正在推送到手机...
adb push "%TGZ%" /sdcard/Download/pwb-deploy.tar
if errorlevel 1 (
    echo [!] 推送失败，请检查 USB 连接和手机存储空间
    del "%TGZ%" 2>nul
    pause
    exit /b 1
)

echo [*] 正在解压...
adb shell "rm -rf /sdcard/Download/pocket-wechat-bot && mkdir -p /sdcard/Download/pocket-wechat-bot && cd /sdcard/Download/pocket-wechat-bot && tar xf /sdcard/Download/pwb-deploy.tar && rm /sdcard/Download/pwb-deploy.tar"
if errorlevel 1 (
    echo [!] 解压失败
    del "%TGZ%" 2>nul
    pause
    exit /b 1
)
del "%TGZ%" 2>nul
echo [*] 文件已推送到手机

REM ----- 复制到 Termux -----
echo [*] 正在复制到 Termux...
adb shell "cd /sdcard/Download && tar czf - pocket-wechat-bot/ 2>/dev/null | run-as com.termux sh -c 'cd ~ && rm -rf pocket-wechat-bot && tar xzf -'" 2>nul
if errorlevel 1 (
    echo.
    echo  ╔══════════════════════════════════════════════╗
    echo  ║  需要在手机上完成最后一步                    ║
    echo  ╚══════════════════════════════════════════════╝
    echo.
    echo  现在拿起手机，打开 Termux 应用。
    echo  你会看到一个命令行终端。
    echo  依次输入以下 3 条命令（输完一条按回车）：
    echo.
    echo  ╔══════════════════════════════════════════════╗
    echo  ║                                              ║
    echo  ║  cp -r /sdcard/Download/pocket-wechat-bot ~/ ║
    echo  ║                                              ║
    echo  ║  cd ~/pocket-wechat-bot                      ║
    echo  ║                                              ║
    echo  ║  bash scripts/setup-phone.sh                 ║
    echo  ║                                              ║
    echo  ╚══════════════════════════════════════════════╝
    echo.
    echo  第 3 条命令运行后，脚本会自动安装依赖、配置环境、
    echo  部署人格文件。过程中会问你几个问题：
    echo    - DeepSeek API Key
    echo    - 微信 OpenID（可先填 *）
    echo    - 微信扫码获取 token
    echo  扫码后 token 会自动填入，不用手动编辑。
    echo  整个过程大约 3-5 分钟。
    echo.
    goto done
)

REM ----- 构建环境变量 -----
set "ENV="
if defined DEPLOY_API_KEY set "ENV=DEPLOY_API_KEY=%DEPLOY_API_KEY%"
if defined DEPLOY_OPENID (
    if defined ENV (set "ENV=%ENV% DEPLOY_OPENID=%DEPLOY_OPENID%") else (set "ENV=DEPLOY_OPENID=%DEPLOY_OPENID%")
)
if defined ENV (set "ENV=%ENV% DEPLOY_NONINTERACTIVE=1") else (set "ENV=DEPLOY_NONINTERACTIVE=1")

REM ----- 远程执行 setup-phone.sh -----
echo [*] 正在手机上运行部署脚本...
echo.
echo  ----------------------------------------
echo    手机端输出：
echo  ----------------------------------------
echo.
adb shell "run-as com.termux sh -c 'cd ~/pocket-wechat-bot && %ENV% bash scripts/setup-phone.sh'"
echo.
echo  ----------------------------------------
echo    手机端输出结束
echo  ----------------------------------------

REM ----- 收尾 -----
:done
echo.
echo  ╔══════════════════════════════════════════════╗
echo  ║  部署完成！还需手动完成以下 2 步：            ║
echo  ╚══════════════════════════════════════════════╝
echo.
echo  第 1 步：关闭 Android 对 Termux 的省电限制
echo    设置 ^> 应用 ^> 应用管理 ^> Termux
echo    ^> 耗电/电量 ^> 后台耗电管理
echo    ^> 改为"允许后台运行"
echo    （不关的话 Android 可能随时杀掉 bot）
echo.
echo  第 2 步：在微信里给 bot 发一条消息测试
echo    第一条回复 5-30 秒，后续 3-10 秒
echo.
echo  管理面板：http://127.0.0.1:9820
echo  查看日志：cat ~/cc-connect/bot-debug.log
echo  重新部署：再次双击本脚本
echo.
pause
