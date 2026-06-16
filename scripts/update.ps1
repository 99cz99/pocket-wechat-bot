# update.ps1 — 快速更新手机上的项目文件并重启 bot
# 用法: 右键 -> 使用 PowerShell 运行，或 deploy.bat 完成后日常使用

$ErrorActionPreference = "Continue"
chcp 65001 > $null 2>&1
$OutputEncoding = [Text.Encoding]::UTF8
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$Repo = Split-Path -Parent $PSScriptRoot
$PhoneRepo = "/data/data/com.termux/files/home/pocket-wechat-bot"
$PhoneBash = "/data/data/com.termux/files/usr/bin/bash"

function Invoke-Termux($Cmd) {
    $escaped = $Cmd -replace "'", "'\''"
    $result = adb shell "run-as com.termux sh -c 'export HOME=/data/data/com.termux/files/home PATH=/data/data/com.termux/files/usr/bin:`$PATH; $escaped'" 2>&1
    $script:LastExitOk = ($LASTEXITCODE -eq 0)
    return $result
}
function Test-Termux($Cmd) {
    $out = Invoke-Termux "$Cmd 2>/dev/null && echo YES || echo NO"
    return ($out -match "YES")
}

Write-Host "============================================="
Write-Host "  快速更新 nene bot"
Write-Host "============================================="
Write-Host ""

# 1. 检查 ADB
if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
    Write-Host "[FAIL] 找不到 adb" -ForegroundColor Red
    Pause; exit 1
}
$devices = adb devices 2>$null | Select-String 'device$'
if (-not $devices) {
    Write-Host "[FAIL] 手机未连接" -ForegroundColor Red
    Pause; exit 1
}

# 2. 版本比较
$currentHash = (git -C $Repo rev-parse --short HEAD 2>$null) -replace '\s', ''
if (-not $currentHash) { $currentHash = "unknown" }

$phoneHash = Invoke-Termux "cat $PhoneRepo/.deploy-version 2>/dev/null"
if ($phoneHash) { $phoneHash = $phoneHash.Trim() }

if ($phoneHash -eq $currentHash) {
    Write-Host "[OK] 手机文件已是最新 ($currentHash)，无需推送" -ForegroundColor Green
} else {
    Write-Host "[..] 版本 $phoneHash -> $currentHash，正在更新..." -ForegroundColor Cyan

    # 打包
    $Tgz = "$env:TEMP\pwb-update.tar"
    Push-Location $Repo
    git archive -o $Tgz HEAD 2>$null
    if ($LASTEXITCODE -ne 0) {
        git archive HEAD > $Tgz 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[FAIL] git archive 失败" -ForegroundColor Red
            Pop-Location; Pause; exit 1
        }
    }
    Pop-Location

    # 推送
    adb push $Tgz /sdcard/Download/pwb-update.tar 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FAIL] 推送失败" -ForegroundColor Red
        Remove-Item $Tgz -ErrorAction SilentlyContinue
        Pause; exit 1
    }

    # 解压到 /sdcard/
    $extractCmd = "rm -rf /sdcard/Download/pocket-wechat-bot && mkdir -p /sdcard/Download/pocket-wechat-bot && cd /sdcard/Download/pocket-wechat-bot && tar xf /sdcard/Download/pwb-update.tar && rm /sdcard/Download/pwb-update.tar && find . -name '*.sh' -exec sed -i 's/\r$//' {} \;"
    adb shell $extractCmd 2>$null

    # 复制到 Termux
    $copyCmd = "cd /sdcard/Download && tar czf - pocket-wechat-bot/ 2>/dev/null | run-as com.termux sh -c 'export HOME=/data/data/com.termux/files/home && cd /data/data/com.termux/files/home && rm -rf pocket-wechat-bot && tar xzf -'"
    adb shell $copyCmd 2>$null

    Remove-Item $Tgz -ErrorAction SilentlyContinue

    # 验证
    if (Test-Termux "test -f $PhoneRepo/scripts/setup-phone.sh") {
        Write-Host "[OK] 文件已更新" -ForegroundColor Green
        Invoke-Termux "echo '$currentHash' > $PhoneRepo/.deploy-version" | Out-Null
    } else {
        Write-Host "[FAIL] 更新失败，请运行 deploy.bat 完整部署" -ForegroundColor Red
        Pause; exit 1
    }
}

# 3. 同步运行时代码
Write-Host "[..] 同步运行时代码..." -ForegroundColor Cyan
# claude-fast.js：bot 实际执行的 API 包装器，必须同步到 ~/bin/
Invoke-Termux "cp $PhoneRepo/claude-fast.js /data/data/com.termux/files/home/bin/claude-fast.js" | Out-Null
Write-Host "[OK] claude-fast.js 已同步" -ForegroundColor Green
# start-bot.sh：启动脚本，同步到 ~/start-nene.sh
Invoke-Termux "cp $PhoneRepo/scripts/start-bot.sh /data/data/com.termux/files/home/start-nene.sh && chmod +x /data/data/com.termux/files/home/start-nene.sh" | Out-Null
Write-Host "[OK] start-nene.sh 已同步" -ForegroundColor Green
# CLAUDE.md 和 skills：bot 读取的人格文件
Invoke-Termux "cp $PhoneRepo/CLAUDE.md /data/data/com.termux/files/home/cc-connect/CLAUDE.md" | Out-Null
if (Test-Termux "test -d $PhoneRepo/skills/nene") {
    Invoke-Termux "mkdir -p /data/data/com.termux/files/home/skills/nene && cp -r $PhoneRepo/skills/nene/* /data/data/com.termux/files/home/skills/nene/" | Out-Null
}
Write-Host "[OK] 人格文件已同步" -ForegroundColor Green

# 4. 重启 bot
Write-Host "[..] 重启 bot..." -ForegroundColor Cyan
$running = Test-Termux "pgrep -f cc-connect"
if ($running) {
    Invoke-Termux "pkill -f cc-connect 2>/dev/null; sleep 1" | Out-Null
    Write-Host "[..] 旧进程已停止" -ForegroundColor Cyan
}

Invoke-Termux "cd /data/data/com.termux/files/home && nohup bash start-nene.sh > /dev/null 2>&1 &" | Out-Null
Start-Sleep -Seconds 3

if (Test-Termux "pgrep -f cc-connect") {
    Write-Host "[OK] Bot 已重启" -ForegroundColor Green
} else {
    Write-Host "[!!] Bot 启动失败，请在手机 Termux 手动运行: bash ~/start-nene.sh" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================="
Write-Host "  更新完成"
Write-Host "============================================="
Write-Host ""
Pause
