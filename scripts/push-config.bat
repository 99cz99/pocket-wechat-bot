@echo off
REM push-config.bat — 从 PC 推送配置到手机并重启 bot
REM 需要: adb 已连接 + USB 调试已授权

echo [*] 推送 config.toml 到手机...
adb push "%~dp0..\config\config.toml" /sdcard/config.toml
if %errorlevel% neq 0 (
    echo [!] adb 推送失败，检查手机连接
    pause
    exit /b 1
)

adb shell "cat /sdcard/config.toml | run-as com.termux tee files/home/.cc-connect/config.toml > /dev/null"
adb shell "run-as com.termux pkill cc-connect 2>/dev/null"
adb shell "run-as com.termux rm -f files/home/.cc-connect/.config.toml.lock"

echo [*] 已推送并重启 bot
echo [*] 手机 Termux 里运行: bash start-nene.sh
pause
