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
    echo     Install from F-Droid: https://f-droid.org/packages/com.termux/
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
    echo  +--------------------------------------------------+
    echo  ^|  Phone-side setup needed                         ^|
    echo  +--------------------------------------------------+
    echo.
    echo  Now pick up your phone and open the Termux app.
    echo  You'll see a terminal with a $ prompt.
    echo  Type these 3 commands, one by one:
    echo.
    echo  +--------------------------------------------------+
    echo  ^|                                                  ^|
    echo  ^|  cp -r /sdcard/Download/pocket-wechat-bot ~/     ^|
    echo  ^|                                                  ^|
    echo  ^|  cd ~/pocket-wechat-bot                          ^|
    echo  ^|                                                  ^|
    echo  ^|  bash scripts/setup-phone.sh                     ^|
    echo  ^|                                                  ^|
    echo  +--------------------------------------------------+
    echo.
    echo  The setup script will install everything and ask
    echo  you a few questions along the way. Takes 3-5 min.
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
echo  +--------------------------------------------------+
echo  ^|  Almost done. 3 more things to do on the phone:  ^|
echo  +--------------------------------------------------+
echo.
echo  In Termux, run this to scan a QR code with WeChat:
echo.
echo    ~/bin/cc-connect weixin setup --project nene
echo.
echo  After scanning, fill the token into config:
echo.
echo    nano ~/.cc-connect/config.toml
echo.
echo  Finally, stop Android from killing the bot:
echo    Phone Settings ^> Apps ^> Termux ^> Battery
echo    Set to "Allow background running"
echo.
echo  Then send a WeChat message to your bot to test!
echo.
pause
