@echo off
REM deploy.bat — One-click deploy pocket-wechat-bot to Android
REM Usage: USB connect phone -> double-click this file
REM Prerequisites: adb in PATH, USB debugging authorized, Termux installed
REM
REM Optional env vars (set before running):
REM   set DEPLOY_API_KEY=sk-xxx
REM   set DEPLOY_OPENID=xxx
REM   deploy.bat
REM ============================================================

setlocal enabledelayedexpansion

set SCRIPT_DIR=%~dp0
set REPO_DIR=%SCRIPT_DIR%..
set LOG_FILE=%REPO_DIR%\deploy-log.txt
set TAR_FILE=%TEMP%\pocket-wechat-deploy.tar

REM Clear old log
echo. > "%LOG_FILE%" 2>nul

echo.
echo   ==========================================
echo     pocket-wechat-bot - PC One-Click Deploy
echo   ==========================================
echo.
echo   Log: %LOG_FILE%
echo.

REM ---- Log helper ----
set "LOGGER=>>"%LOG_FILE%" 2>&1"

REM ---- 1. Check ADB ----
echo [*] Checking ADB connection...
echo [*] Checking ADB connection... %LOGGER%

where adb >nul 2>&1
if %errorlevel% neq 0 (
    echo [!] adb not found in PATH
    echo      Download Android Platform Tools:
    echo      https://developer.android.com/studio/releases/platform-tools
    echo [!] adb not found %LOGGER%
    pause
    exit /b 1
)

adb devices 2>nul | findstr "device$" >nul
if %errorlevel% neq 0 (
    echo [!] No Android device detected
    echo.
    echo     Check:
    echo     1. USB cable connected
    echo     2. Developer Options -> USB Debugging ON
    echo     3. Authorized this PC on phone
    echo     4. adb devices shows a device
    echo.
    adb devices
    echo [!] No device detected %LOGGER%
    pause
    exit /b 1
)

for /f "tokens=1" %%d in ('adb devices 2^>nul ^| findstr "device$"') do set DEVICE=%%d
echo [*] Device: %DEVICE%
echo [*] Device: %DEVICE% %LOGGER%

REM ---- 2. Check Termux installed ----
echo [*] Checking Termux on phone...
adb shell "pm list packages com.termux" 2>nul | findstr "com.termux" >nul
if %errorlevel% neq 0 (
    echo [!] Termux not found on phone!
    echo      Install from F-Droid: https://f-droid.org/packages/com.termux/
    echo [!] Termux not installed %LOGGER%
    pause
    exit /b 1
)
echo [*] Termux OK
echo [*] Termux OK %LOGGER%

REM ---- 3. Package repo (exclude .git) ----
echo.
echo [*] Packaging project files...
echo [*] Packaging project... %LOGGER%

pushd "%REPO_DIR%"
git archive -o "%TAR_FILE%" HEAD 2>nul
if %errorlevel% neq 0 (
    git archive --format=tar HEAD > "%TAR_FILE%" 2>nul
    if %errorlevel% neq 0 (
        echo [!] git archive failed, fallback to adb push...
        echo [!] git archive failed %LOGGER%
        popd
        goto push_fallback
    )
)
popd
echo [*] Package OK (%TAR_FILE%)
echo [*] Package OK %LOGGER%

REM ---- 4. Push tar to phone ----
echo [*] Pushing to phone /sdcard/Download/ ...
echo [*] Pushing %TAR_FILE% to /sdcard/Download/ %LOGGER%
adb push "%TAR_FILE%" /sdcard/Download/pocket-wechat-deploy.tar
if %errorlevel% neq 0 (
    echo [!] Push failed, fallback to adb push...
    echo [!] adb push tar failed %LOGGER%
    goto push_fallback
)

echo [*] Extracting on phone...
echo [*] Extracting on phone... %LOGGER%
adb shell "mkdir -p /sdcard/Download/pocket-wechat-bot && cd /sdcard/Download/pocket-wechat-bot && tar xf /sdcard/Download/pocket-wechat-deploy.tar && rm /sdcard/Download/pocket-wechat-deploy.tar"
if %errorlevel% neq 0 (
    echo [!] Extract failed, fallback to adb push...
    echo [!] Extract failed %LOGGER%
    adb shell "rm -rf /sdcard/Download/pocket-wechat-bot" 2>nul
    goto push_fallback
)
goto files_ready

:push_fallback
REM Fallback: adb push entire directory (includes .git, slower)
pushd "%REPO_DIR%"
echo [*] Pushing entire directory via adb push (may take 1-2 min)...
echo [*] adb push fallback... %LOGGER%
adb push . /sdcard/Download/pocket-wechat-bot/
if %errorlevel% neq 0 (
    echo [!] adb push failed! Check USB and storage.
    echo [!] adb push failed %LOGGER%
    popd
    pause
    exit /b 1
)
popd

:files_ready
REM Clean up .git in pushed directory
adb shell "rm -rf /sdcard/Download/pocket-wechat-bot/.git" 2>nul
echo [*] Files on phone: /sdcard/Download/pocket-wechat-bot/
echo [*] Files ready %LOGGER%

REM ---- 5. Copy to Termux and run ----
echo.
echo [*] Copying to Termux and running setup...
echo [*] Copy to Termux... %LOGGER%

adb shell "cd /sdcard/Download && tar czf - pocket-wechat-bot/ 2>/dev/null | run-as com.termux sh -c 'cd ~ && rm -rf pocket-wechat-bot && tar xzf -'" 2>nul

if %errorlevel% neq 0 (
    echo.
    echo   [!] Cannot auto-copy to Termux (run-as not available)
    echo       Common on: non-Debug Termux or Android 14+
    echo.
    echo   Files are at /sdcard/Download/pocket-wechat-bot/
    echo   Run these 2 commands in Termux to finish:
    echo.
    echo     cp -r /sdcard/Download/pocket-wechat-bot ~/
    echo     cd ~/pocket-wechat-bot ^&^& bash scripts/setup-phone.sh
    echo.
    echo [!] run-as unavailable %LOGGER%
    goto epilogue
)

REM ---- 6. Execute setup-phone.sh remotely ----
echo [*] Running setup-phone.sh on phone...
echo.
echo   ----------------------------------------
echo     Phone output:
echo   ----------------------------------------
echo.

REM Build env prefix
set ENV_PREFIX=
if defined DEPLOY_API_KEY set "ENV_PREFIX=DEPLOY_API_KEY=!DEPLOY_API_KEY!"
if defined DEPLOY_OPENID (
    if defined ENV_PREFIX (set "ENV_PREFIX=!ENV_PREFIX! DEPLOY_OPENID=!DEPLOY_OPENID!") else (set "ENV_PREFIX=DEPLOY_OPENID=!DEPLOY_OPENID!")
)
if defined ENV_PREFIX (set "ENV_PREFIX=!ENV_PREFIX! DEPLOY_NONINTERACTIVE=1") else (set "ENV_PREFIX=DEPLOY_NONINTERACTIVE=1")

REM Run and capture output
set TMP_OUT=%TEMP%\phone-deploy-output.txt
adb shell "run-as com.termux sh -c 'cd ~/pocket-wechat-bot && !ENV_PREFIX! bash scripts/setup-phone.sh'" > "%TMP_OUT%" 2>&1
set RC=%errorlevel%

REM Show and save output
type "%TMP_OUT%"
type "%TMP_OUT%" >> "%LOG_FILE%"

echo.
echo   ----------------------------------------
echo     Phone output end
echo   ----------------------------------------

if %RC% neq 0 (
    echo [!] setup-phone.sh returned error code %RC%
    echo [!] Check log: %LOG_FILE%
    echo [!] setup-phone.sh exit=%RC% %LOGGER%
)

REM ---- 7. Epilogue ----
:epilogue
del "%TAR_FILE%" 2>nul
del "%TMP_OUT%" 2>nul

echo.
echo   ============================================
echo     Post-deployment checklist:
echo   ============================================
echo.
echo   1. WeChat QR scan (if not done yet):
echo      ~/bin/cc-connect weixin setup --project nene
echo.
echo   2. Fill token/account_id into config:
echo      nano ~/.cc-connect/config.toml
echo.
echo   3. Disable battery optimization for Termux:
echo      Settings -> Apps -> Termux -> Battery -> Allow background
echo.
echo   4. Test: send a message to your bot on WeChat
echo.
echo   Management panel: http://127.0.0.1:9820
echo   View logs:        cat ~/cc-connect/bot-debug.log
echo   Redeploy:         run this script again
echo.
echo   Full deploy log:  %LOG_FILE%
echo.

pause
