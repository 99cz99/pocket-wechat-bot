@echo off
setlocal enabledelayedexpansion

REM ============================================================
REM  deploy.bat - Pocket WeChat Bot One-Click Deploy (PC->Phone)
REM  Double-click to deploy. Needs: adb + USB + Termux on phone
REM ============================================================

set "REPO=%~dp0.."
set "TGZ=%TEMP%\pwb-deploy.tar"

echo.
echo  ==========================================
echo    Pocket WeChat Bot - Deploy to Phone
echo  ==========================================
echo.

REM ----- Check ADB -----
echo [*] ADB check...
where adb >nul 2>&1
if errorlevel 1 (
    echo [!] adb not found. Install Android Platform Tools.
    echo     https://developer.android.com/studio/releases/platform-tools
    pause
    exit /b 1
)
adb shell echo ok >nul 2>&1
if errorlevel 1 (
    echo [!] No device. Check USB + USB Debugging + authorization.
    adb devices
    pause
    exit /b 1
)
echo [*] ADB OK

REM ----- Check Termux -----
echo [*] Termux check...
adb shell "pm list packages com.termux" 2>nul | find "com.termux" >nul
if errorlevel 1 (
    echo [!] Termux not installed on phone.
    echo     Install: https://f-droid.org/packages/com.termux/
    echo     Also install Termux:API from F-Droid.
    pause
    exit /b 1
)
echo [*] Termux OK

REM ----- Package repo -----
echo [*] Packaging project...
pushd "%REPO%"
git archive -o "%TGZ%" HEAD 2>nul
if errorlevel 1 (
    git archive HEAD > "%TGZ%" 2>nul
    if errorlevel 1 (
        echo [!] git archive failed. Is git installed?
        popd
        pause
        exit /b 1
    )
)
popd
echo [*] Package OK

REM ----- Push to phone -----
echo [*] Pushing to phone...
adb push "%TGZ%" /sdcard/Download/pwb-deploy.tar
if errorlevel 1 (
    echo [!] Push failed.
    del "%TGZ%" 2>nul
    pause
    exit /b 1
)

echo [*] Extracting...
adb shell "rm -rf /sdcard/Download/pocket-wechat-bot && mkdir -p /sdcard/Download/pocket-wechat-bot && cd /sdcard/Download/pocket-wechat-bot && tar xf /sdcard/Download/pwb-deploy.tar && rm /sdcard/Download/pwb-deploy.tar"
if errorlevel 1 (
    echo [!] Extract failed on phone.
    del "%TGZ%" 2>nul
    pause
    exit /b 1
)
del "%TGZ%" 2>nul
echo [*] Files pushed

REM ----- Copy into Termux -----
echo [*] Copying into Termux...
adb shell "cd /sdcard/Download && tar czf - pocket-wechat-bot/ 2>/dev/null | run-as com.termux sh -c 'cd ~ && rm -rf pocket-wechat-bot && tar xzf -'" 2>nul
if errorlevel 1 (
    echo.
    echo  [!] Cannot auto-copy into Termux
    echo      (run-as not available - Android 14+ / non-Debug Termux)
    echo.
    echo  Files are at: /sdcard/Download/pocket-wechat-bot/
    echo.
    echo  Run these commands in Termux to finish:
    echo    cp -r /sdcard/Download/pocket-wechat-bot ~/
    echo    cd ~/pocket-wechat-bot ^&^& bash scripts/setup-phone.sh
    echo.
    goto done
)

REM ----- Build env vars for setup -----
set "ENV="
if defined DEPLOY_API_KEY set "ENV=DEPLOY_API_KEY=%DEPLOY_API_KEY%"
if defined DEPLOY_OPENID (
    if defined ENV (set "ENV=%ENV% DEPLOY_OPENID=%DEPLOY_OPENID%") else (set "ENV=DEPLOY_OPENID=%DEPLOY_OPENID%")
)
if defined ENV (set "ENV=%ENV% DEPLOY_NONINTERACTIVE=1") else (set "ENV=DEPLOY_NONINTERACTIVE=1")

REM ----- Run setup-phone.sh -----
echo [*] Running setup-phone.sh on phone...
echo.
echo  ----------------------------------------
echo    Phone output:
echo  ----------------------------------------
echo.
adb shell "run-as com.termux sh -c 'cd ~/pocket-wechat-bot && %ENV% bash scripts/setup-phone.sh'"
echo.
echo  ----------------------------------------
echo    Phone output end
echo  ----------------------------------------

REM ----- Done -----
:done
echo.
echo  ==========================================
echo    Next steps (manual):
echo  ==========================================
echo.
echo  1. WeChat QR scan:
echo     ~/bin/cc-connect weixin setup --project nene
echo.
echo  2. Fill token/account_id into config:
echo     nano ~/.cc-connect/config.toml
echo.
echo  3. Disable battery optimization:
echo     Settings ^> Apps ^> Termux ^> Battery
echo.
echo  4. Test: send WeChat msg to your bot
echo.
pause
