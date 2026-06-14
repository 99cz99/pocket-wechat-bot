@echo off
REM push-config.bat — 从 PC 推送配置到手机并重启 bot
REM 需要: adb 已连接 + USB 调试已授权
REM 首次使用前: 复制 config.toml.template → config.toml 并填入凭据（config.toml 在 .gitignore 中）
REM 注意: Android 14+ 或非 Debug 版 Termux 可能不支持 run-as，届时需在手机上手动操作

echo [*] 推送 config.toml 到手机...

REM 检查 config.toml 是否存在
if not exist "%~dp0..\config\config.toml" (
    echo [!] config\config.toml 不存在，请先复制模板并填入凭据：
    echo     copy config\config.toml.template config\config.toml
    echo     然后编辑 config\config.toml 填入 API Key 和微信凭据
    pause
    exit /b 1
)

adb push "%~dp0..\config\config.toml" /sdcard/Download/config.toml
if %errorlevel% neq 0 (
    echo [!] adb 推送失败，检查手机连接
    pause
    exit /b 1
)

REM 尝试通过 run-as 直接写入 Termux 私有目录（需要 Debug 版 Termux 或 Android <14）
adb shell "cat /sdcard/Download/config.toml | run-as com.termux sh -c 'cat > /data/data/com.termux/files/home/.cc-connect/config.toml'" 2>nul
if %errorlevel% neq 0 (
    echo [!] run-as 失败（可能非 Debug 版 Termux 或 Android 14+）
    echo [*] 文件已推到 /sdcard/Download/config.toml
    echo [*] 请在手机 Termux 里手动执行：
    echo     cp /sdcard/Download/config.toml ~/.cc-connect/config.toml
    echo     pkill -f cc-connect
    echo     rm -f ~/.cc-connect/.config.toml.lock
    echo     bash ~/start-nene.sh
    pause
    exit /b 0
)

REM 重启 bot
adb shell "run-as com.termux pkill -f cc-connect 2>/dev/null"
adb shell "run-as com.termux rm -f /data/data/com.termux/files/home/.cc-connect/.config.toml.lock"

echo [*] 已推送并重启 bot
echo [*] 手机 Termux 里运行: bash ~/start-nene.sh
pause
