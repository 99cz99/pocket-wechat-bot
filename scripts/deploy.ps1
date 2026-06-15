# deploy.ps1 - 向导式部署微信 AI 机器人到 Android 手机
# 用法: 右键 -> 使用 PowerShell 运行
# 需要: adb + USB 连接 + 手机已装 Termux

$ErrorActionPreference = "Continue"
$Repo = Split-Path -Parent $PSScriptRoot
$Tgz = "$env:TEMP\pwb-deploy.tar"

# ============================================================
# 工具函数
# ============================================================

# 在手机上通过 run-as 执行命令，返回输出
function Invoke-Termux($Cmd) {
    $escaped = $Cmd -replace "'", "'\''"
    $result = adb shell "run-as com.termux sh -c 'export HOME=/data/data/com.termux/files/home; $escaped'" 2>&1
    $script:LastExitOk = ($LASTEXITCODE -eq 0)
    return $result
}

# 检查手机上的某个条件
function Test-Termux($Cmd) {
    $out = Invoke-Termux "$Cmd 2>/dev/null && echo YES || echo NO"
    return ($out -match "YES")
}

function Write-Step($num, $title) {
    Write-Host ""
    Write-Host "=============================================="
    Write-Host "  步骤 $num : $title"
    Write-Host "=============================================="
    Write-Host ""
}

function Write-OK($msg) {
    Write-Host "  [OK] $msg" -ForegroundColor Green
}

function Write-Fail($msg) {
    Write-Host "  [FAIL] $msg" -ForegroundColor Red
}

function Write-Warn($msg) {
    Write-Host "  [!!] $msg" -ForegroundColor Yellow
}

function Write-Info($msg) {
    Write-Host "  [..] $msg" -ForegroundColor Cyan
}

# ============================================================
# 横幅
# ============================================================
Write-Host ""
Write-Host "============================================="
Write-Host "  微信 AI 机器人 - 向导式部署"
Write-Host "============================================="
Write-Host ""

# ============================================================
# 步骤 1: 环境检查
# ============================================================
Write-Step 1 "环境检查"

# ADB
Write-Info "检查 ADB..."
if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
    Write-Fail "找不到 adb，请先安装 Android Platform Tools"
    Write-Host "    https://developer.android.com/studio/releases/platform-tools"
    Pause; exit 1
}
$devices = adb devices 2>$null | Select-String 'device$'
if (-not $devices) {
    Write-Fail "未检测到手机"
    Write-Host "    1. USB 已连接？"
    Write-Host "    2. 手机已开启 USB 调试？"
    Write-Host "    3. 手机上已授权此电脑？"
    Write-Host ""
    adb devices
    Pause; exit 1
}
Write-OK "ADB 连接正常"

# Termux
Write-Info "检查 Termux..."
$termux = adb shell pm list packages 2>&1 | Out-String
if ($termux -notmatch "com.termux") {
    Write-Fail "手机未安装 Termux"
    Write-Host "    请在 F-Droid 下载：https://f-droid.org/packages/com.termux/"
    Write-Host "    还需安装 Termux:API"
    Pause; exit 1
}
Write-OK "Termux 已安装"

# 存储空间
Write-Info "检查存储空间..."
$avail = Invoke-Termux "df -k /data/data/com.termux/files/home 2>/dev/null | tail -1 | awk '{print `$4}'"
if ($avail -and [int]$avail -lt 512000) {
    Write-Warn "剩余空间不足 500MB（当前 $([math]::Floor([int]$avail/1024))MB），部署可能失败"
}

# 检查是否曾经部署过
$isRerun = Test-Termux "test -f /data/data/com.termux/files/home/.pocket-bot-deploy-state"
if ($isRerun) {
    Write-Info "检测到已有部署记录，已完成步骤将自动跳过"
}

# ============================================================
# 步骤 2: 推送文件
# ============================================================
Write-Step 2 "推送文件到手机"

# --- 2.1 获取 cc-connect 二进制 ---
Write-Info "查找 cc-connect 二进制..."
$ccBin = $null
$ccUrl = "https://github.com/chenhg5/cc-connect/releases/latest/download/cc-connect-linux-arm64"
$desktopDir = [Environment]::GetFolderPath("Desktop")
$desktopFilePath = $null

# 检查桌面文件
$desktopFile = Get-ChildItem -Path $desktopDir -Filter "cc-connect*" | Where-Object {
    (-not $_.PSIsContainer) -and ($_.Name -match "^cc-connect") -and ($_.Name -notmatch "\.(md|txt)$")
} | Select-Object -First 1

if ($desktopFile) {
    $desktopFilePath = $desktopFile.FullName
    Write-Info "检测到桌面文件: $($desktopFile.Name)"
    $magic = [System.IO.File]::ReadAllBytes($desktopFilePath)[0..3]
    if ($magic[0] -eq 0x7f -and $magic[1] -eq 0x45) {
        $ccBin = $desktopFilePath
    } elseif ($desktopFilePath -match "\.(tar|gz|tgz|zip)$") {
        Write-Info "检测到压缩包，正在解压..."
        $extractDir = "$env:TEMP\cc-extract"
        Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
        try {
            tar -xf $desktopFilePath -C $extractDir 2>$null
            if ($LASTEXITCODE -ne 0) { throw "tar failed" }
        } catch {
            Write-Fail "解压失败，请手动解压后将二进制文件放到桌面"
            Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
            Pause; exit 1
        }
        $found = Get-ChildItem -Path $extractDir -Recurse -File | Where-Object {
            $m = [System.IO.File]::ReadAllBytes($_.FullName)[0..3]
            ($m[0] -eq 0x7f) -and ($m[1] -eq 0x45)
        } | Select-Object -First 1
        if ($found) {
            $ccBin = $found.FullName
            Write-OK "已提取: $($found.Name)"
        } else {
            Write-Fail "压缩包内未找到 ELF 二进制"
            Write-Host "    请确认下载的是 Assets 中的 cc-connect-linux-arm64.tar"
            Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
            Pause; exit 1
        }
    } else {
        Write-Fail "桌面文件无法识别（既非二进制也非压缩包）"
        Write-Host "    请从 GitHub Assets 下载 cc-connect-*-linux-arm64.tar"
        Write-Host "    https://github.com/chenhg5/cc-connect/releases/latest"
        Pause; exit 1
    }
}

# 自动下载
if (-not $ccBin) {
    Write-Info "尝试自动下载 cc-connect..."
    $ccBin = "$env:TEMP\cc-connect-linux-arm64"
    try {
        Invoke-WebRequest -Uri $ccUrl -OutFile $ccBin -TimeoutSec 60 -ErrorAction Stop
        Write-OK "下载完成"
    } catch {
        Remove-Item $ccBin -ErrorAction SilentlyContinue
        $ccBin = $null
        Write-Warn "自动下载失败（可能是网络问题）"
    }
}

# 手动下载指引
if (-not $ccBin) {
    Write-Host ""
    Write-Host "  请手动操作："
    Write-Host "  1. 浏览器打开: https://github.com/chenhg5/cc-connect/releases/latest"
    Write-Host "  2. 在 Assets 区域找到 cc-connect-*-linux-arm64.tar"
    Write-Host "  3. 下载到桌面（不要改名）"
    Write-Host "  4. 下载完成后重新运行本脚本（会自动解压）"
    Write-Host ""
    Pause; exit 1
}

# --- 2.2 推送 cc-connect 到手机 ---
Write-Info "推送 cc-connect 到手机..."
adb push $ccBin /sdcard/Download/cc-connect-linux-arm64 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Fail "推送失败，请检查 USB 连接和手机存储空间"
    Pause; exit 1
}

# 复制到 Termux 私有目录（run-as 访问不了 /sdcard/）
$pipeCmd = "cat /sdcard/Download/cc-connect-linux-arm64 | run-as com.termux sh -c 'cat > /data/data/com.termux/files/home/cc-connect-linux-arm64 && chmod +x /data/data/com.termux/files/home/cc-connect-linux-arm64'"
adb shell $pipeCmd 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Fail "复制到 Termux 失败"
    Pause; exit 1
}
Write-OK "cc-connect 已推送到手机"

# 清理临时文件
if ($ccBin -ne $desktopFilePath) {
    Remove-Item $ccBin -ErrorAction SilentlyContinue
}

# --- 2.3 打包并推送项目文件 ---
Write-Info "打包项目文件..."
Push-Location $Repo
try {
    git archive -o $Tgz HEAD 2>$null
    if ($LASTEXITCODE -ne 0) {
        git archive HEAD > $Tgz 2>$null
        if ($LASTEXITCODE -ne 0) { throw "git archive failed" }
    }
} catch {
    Write-Fail "打包失败，请确认 git 已安装"
    Pop-Location; Pause; exit 1
}
Pop-Location
Write-OK "打包完成"

Write-Info "推送到手机..."
adb push $Tgz /sdcard/Download/pwb-deploy.tar 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Fail "推送失败"
    Remove-Item $Tgz -ErrorAction SilentlyContinue
    Pause; exit 1
}

Write-Info "解压到手机..."
$extractCmd = "rm -rf /sdcard/Download/pocket-wechat-bot && mkdir -p /sdcard/Download/pocket-wechat-bot && cd /sdcard/Download/pocket-wechat-bot && tar xf /sdcard/Download/pwb-deploy.tar && rm /sdcard/Download/pwb-deploy.tar && find . -name '*.sh' -exec sed -i 's/\r`$//' {} \;"
adb shell $extractCmd 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Fail "解压失败"
    Remove-Item $Tgz -ErrorAction SilentlyContinue
    Pause; exit 1
}
Remove-Item $Tgz -ErrorAction SilentlyContinue

# 复制到 Termux
Write-Info "复制到 Termux 私有目录..."
$copyCmd = "cd /sdcard/Download && tar czf - pocket-wechat-bot/ 2>/dev/null | run-as com.termux sh -c 'export HOME=/data/data/com.termux/files/home && cd /data/data/com.termux/files/home && rm -rf pocket-wechat-bot && tar xzf -'"
adb shell $copyCmd 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "  -----------------------------------------"
    Write-Host "  自动复制失败，需要在手机上手动操作"
    Write-Host "  -----------------------------------------"
    Write-Host ""
    Write-Host "  拿起手机，打开 Termux，依次输入："
    Write-Host ""
    Write-Host "    cp -r /sdcard/Download/pocket-wechat-bot ~/"
    Write-Host "    cd ~/pocket-wechat-bot"
    Write-Host "    bash scripts/setup-phone.sh"
    Write-Host ""
    Write-Host "  然后按照手机端脚本提示完成部署。"
    Write-Host ""
    Pause
    exit 0
}
Write-OK "文件已推送到 Termux"

# ============================================================
# 步骤 3: 基础环境安装（全自动）
# ============================================================
Write-Step 3 "基础环境安装（全自动，约 2-5 分钟）"

Write-Info "正在手机上安装依赖和配置环境..."
Write-Info "（这步不需要你操作，稍等...）"
Write-Host ""

# 运行 setup-phone.sh
$setupCmd = "run-as com.termux sh -c 'export HOME=/data/data/com.termux/files/home && cd /data/data/com.termux/files/home/pocket-wechat-bot && chmod +x scripts/setup-phone.sh scripts/start-bot.sh && DEPLOY_NONINTERACTIVE=1 ./scripts/setup-phone.sh'"
$setupOutput = adb shell $setupCmd 2>&1

# 解析输出
$setupOutput -split "`n" | ForEach-Object {
    $line = $_
    if ($line -match '\[OK\]') {
        Write-Host "  $line" -ForegroundColor Green
    } elseif ($line -match '\[FAIL\]') {
        Write-Host "  $line" -ForegroundColor Red
    } elseif ($line -match '\[SKIP\]') {
        Write-Host "  $line" -ForegroundColor DarkGray
    } elseif ($line -match '\[\.\.\]') {
        Write-Host "  $line" -ForegroundColor Cyan
    } elseif ($line -match '\[!!\]') {
        Write-Host "  $line" -ForegroundColor Yellow
    }
}

Write-Host ""

# ============================================================
# 步骤 4: 配置 API Key（PC 端交互）
# ============================================================
Write-Step 4 "配置 DeepSeek API Key"

$apiKeySet = Test-Termux "grep -q 'ANTHROPIC_API_KEY=sk-' /data/data/com.termux/files/home/.bashrc"

if ($apiKeySet) {
    Write-OK "API Key 已配置"
} else {
    Write-Warn "API Key 未设置"
    Write-Host ""
    Write-Host "  DeepSeek API Key 获取方式："
    Write-Host "  打开 https://platform.deepseek.com/api_keys"
    Write-Host "  注册/登录后创建 API Key，复制 sk- 开头的一串字符"
    Write-Host ""

    $apiKey = $null
    do {
        $apiKey = Read-Host "  请输入 API Key（sk-...）"
        if (-not $apiKey -or $apiKey -notmatch '^sk-') {
            Write-Warn "格式不正确（应以 sk- 开头）"
            $apiKey = $null
        }
    } while (-not $apiKey)

    Write-Info "正在写入手机..."

    # 写入 bashrc
    $bashrcLine = "echo 'export ANTHROPIC_API_KEY=$apiKey' >> /data/data/com.termux/files/home/.bashrc"
    Invoke-Termux $bashrcLine | Out-Null

    # 更新 claude 包装器（用 base64 避免 shell 转义问题）
    $wrapperContent = @"
#!/data/data/com.termux/files/usr/bin/sh
export ANTHROPIC_API_KEY="$apiKey"
exec /usr/bin/node /home/bin/claude-fast.js "\$@"
"@
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($wrapperContent))
    $b64cmd = "echo '$b64' | base64 -d > /data/data/com.termux/files/usr/bin/claude && chmod +x /data/data/com.termux/files/usr/bin/claude"
    Invoke-Termux $b64cmd | Out-Null

    # 验证
    $apiKeySet = Test-Termux "grep -q 'ANTHROPIC_API_KEY=sk-' /data/data/com.termux/files/home/.bashrc"
    if ($apiKeySet) {
        Write-OK "API Key 已写入手机"
    } else {
        Write-Fail "写入失败，请手动在 Termux 中执行："
        Write-Host "    echo 'export ANTHROPIC_API_KEY=$apiKey' >> ~/.bashrc"
    }
}

# ============================================================
# 步骤 5: 配置 config.toml
# ============================================================
Write-Step 5 "配置文件（config.toml）"

# 获取 API Key
$apiKeyVal = Invoke-Termux "grep 'ANTHROPIC_API_KEY' /data/data/com.termux/files/home/.bashrc 2>/dev/null | tail -1 | sed 's/.*=//'"
$apiKeyVal = $apiKeyVal.Trim()

# 运行 step_config
$cfgCmd = "cd /data/data/com.termux/files/home/pocket-wechat-bot && DEPLOY_API_KEY='$apiKeyVal' bash -c 'source scripts/setup-phone.sh; step_config'"
$configOut = Invoke-Termux $cfgCmd
Write-Host $configOut

# 检查剩余占位符
$remaining = Invoke-Termux "grep -c '<YOUR_' /data/data/com.termux/files/home/.cc-connect/config.toml 2>/dev/null || echo 0"
$remaining = $remaining.Trim()

if ($remaining -eq "0") {
    Write-OK "config.toml 已完整生成"
} else {
    Write-Warn "config.toml 还有 $remaining 个占位符待填写"
    $placeholders = Invoke-Termux "grep '<YOUR_' /data/data/com.termux/files/home/.cc-connect/config.toml"
    Write-Host "  $placeholders"
    Write-Host ""
    Write-Host "  稍后会在下一步获取微信凭据，完成后自动填入。"
    Write-Host "  OpenID 可以在 bot 启动后发 /whoami 获取。"
}

# ============================================================
# 步骤 6: 微信凭据
# ============================================================
Write-Step 6 "微信扫码获取凭据"

$tokenOk = Test-Termux "grep -q 'token = `"wx_' /data/data/com.termux/files/home/.cc-connect/config.toml"

if ($tokenOk) {
    $token = Invoke-Termux "grep 'token = ' /data/data/com.termux/files/home/.cc-connect/config.toml | head -1 | sed 's/.*= `"//;s/`"//'"
    Write-OK "微信凭据已配置: $($token.Trim())"
} else {
    Write-Warn "微信凭据未配置"

    # DNS 预检：Go 在 Android 走 netd 而非 /etc/resolv.conf，提前修复
    Write-Info "检查 proot DNS..."
    $dnsOk = Test-Termux "timeout 3 /data/data/com.termux/files/usr/bin/nslookup ilinkai.weixin.qq.com 114.114.114.114 >/dev/null 2>&1"
    if (-not $dnsOk) {
        Write-Warn "DNS 可能异常，正在修复..."
        Invoke-Termux "echo 'nameserver 114.114.114.114' > /data/local/tmp/resolv.conf 2>/dev/null; echo 'nameserver 223.5.5.5' >> /data/local/tmp/resolv.conf 2>/dev/null; mkdir -p /data/data/com.termux/files/home/proot-fs/etc; cp /data/local/tmp/resolv.conf /data/data/com.termux/files/home/proot-fs/etc/resolv.conf 2>/dev/null || true" | Out-Null
        Write-OK "DNS 已修复（114.114.114.114 / 223.5.5.5）"
    } else {
        Write-OK "DNS 正常"
    }

    Write-Host ""
    Write-Host "  -----------------------------------------"
    Write-Host "  现在需要拿起手机操作"
    Write-Host "  -----------------------------------------"
    Write-Host ""
    Write-Host "  在手机 Termux 中运行以下命令："
    Write-Host ""
    Write-Host "    proot -b /data/local/tmp/resolv.conf:/etc/resolv.conf -b ~/proot-fs/etc/ssl:/etc/ssl -b /data/data/com.termux/files/usr:/usr -b ~/:/home /usr/bin/env PATH=/usr/bin:/usr/local/bin:/home/bin ~/bin/cc-connect weixin setup --project nene"
    Write-Host ""
    Write-Host "  会显示一个二维码链接。"
    Write-Host "  1. 在手机浏览器打开该链接"
    Write-Host "  2. 用你的微信小号扫描"
    Write-Host "  3. 扫码成功后，Termux 会显示 token 和 account_id"
    Write-Host ""

    do {
        Read-Host "  扫码完成后，按回车继续"

        $tokenCheck = Invoke-Termux "grep -o 'wx_[a-zA-Z0-9_-]*' /data/data/com.termux/files/home/.cc-connect/config.toml 2>/dev/null | head -1"
        $tokenCheck = $tokenCheck.Trim()

        if ($tokenCheck -and $tokenCheck -ne '<YOUR_BOT_TOKEN>') {
            Write-OK "检测到 token: $tokenCheck"
            $tokenOk = $true
            break
        }

        $scanToken = Invoke-Termux "cat /data/data/com.termux/files/home/cc-connect/cc-connect.log 2>/dev/null | grep -o 'wx_[a-zA-Z0-9_-]*' | head -1"
        $scanToken = $scanToken.Trim()
        if ($scanToken) {
            $sedCmd = "sed -i 's#<YOUR_BOT_TOKEN>#$scanToken#g' /data/data/com.termux/files/home/.cc-connect/config.toml"
            Invoke-Termux $sedCmd | Out-Null
            Write-OK "已从日志提取 token: $scanToken"
            $tokenOk = $true
            break
        }

        Write-Warn "尚未检测到 token"
        Write-Host "  请确认："
        Write-Host "    1. 已在 Termux 中运行了扫码命令"
        Write-Host "    2. 已用微信扫描了二维码"
        Write-Host "    3. 终端显示了 'token:' 和 'account_id:'"
        Write-Host ""

        $retry = Read-Host "  重试？按回车重试，输入 s 跳过 [s]"
        if ($retry -eq 's') {
            Write-Warn "已跳过。稍后可手动编辑 ~/.cc-connect/config.toml"
            break
        }
    } while ($true)
}

# ============================================================
# 步骤 7: 启动 Bot
# ============================================================
Write-Step 7 "启动 Bot"

Write-Info "部署启动脚本..."
$startOut = Invoke-Termux "cd /data/data/com.termux/files/home/pocket-wechat-bot && bash -c 'source scripts/setup-phone.sh; step_startup'"
Write-Host $startOut

Write-Info "正在启动 cc-connect..."
$launchOut = Invoke-Termux "cd /data/data/com.termux/files/home/pocket-wechat-bot && bash -c 'source scripts/setup-phone.sh; step_launch'"
Write-Host $launchOut

# 验证
$running = Test-Termux "pgrep -f cc-connect"
if ($running) {
    Write-OK "Bot 正在运行"
} else {
    Write-Warn "Bot 未能启动，可能因为缺少配置"
    Write-Host "  完成下方待办事项后重跑 deploy.bat 即可"
}

# ============================================================
# 步骤 8: OpenID 配置
# ============================================================
Write-Step 8 "配置 OpenID"

$openidOk = Test-Termux "test -f /data/data/com.termux/files/home/cc-connect/CLAUDE.md && ! grep -q '<YOUR_WECHAT_OPENID>' /data/data/com.termux/files/home/cc-connect/CLAUDE.md"

if ($openidOk) {
    Write-OK "OpenID 已配置"
} else {
    Write-Warn "OpenID 占位符未替换"
    Write-Host ""
    Write-Host "  请先在微信里给 Bot 发一条消息（任意内容）。"
    Write-Host ""

    do {
        Read-Host "  发完后按回车"

        $fixOut = Invoke-Termux "bash /data/data/com.termux/files/home/pocket-wechat-bot/scripts/fix-openid.sh"
        Write-Host $fixOut

        $openidOk = Test-Termux "test -f /data/data/com.termux/files/home/cc-connect/CLAUDE.md && ! grep -q '<YOUR_WECHAT_OPENID>' /data/data/com.termux/files/home/cc-connect/CLAUDE.md"
        if ($openidOk) {
            Write-OK "OpenID 已自动填入"
            break
        }

        Write-Warn "未能从日志提取 OpenID"
        Write-Host "  请确认已给 Bot 发送了消息"
        Write-Host "  也可以在 Termux 中手动运行: bash ~/pocket-wechat-bot/scripts/fix-openid.sh"

        $retry = Read-Host "  重试？按回车重试，输入 s 跳过 [s]"
        if ($retry -eq 's') {
            Write-Warn "已跳过。稍后可手动运行 fix-openid.sh"
            break
        }
    } while ($true)
}

# ============================================================
# 步骤 9: 收尾检查清单
# ============================================================
Write-Step 9 "部署后检查清单"

Write-Host ""
Write-Host "  --- 状态检查 ---"
Write-Host ""

# API Key
if (Test-Termux "grep -q 'ANTHROPIC_API_KEY=sk-' /data/data/com.termux/files/home/.bashrc") {
    Write-OK "API Key         已设置"
} else {
    Write-Fail "API Key         未设置"
    Write-Host "                   echo 'export ANTHROPIC_API_KEY=sk-你的key' >> ~/.bashrc"
}

# config.toml
$rem = Invoke-Termux "grep -c '<YOUR_' /data/data/com.termux/files/home/.cc-connect/config.toml 2>/dev/null || echo 0"
if ($rem.Trim() -eq "0") {
    Write-OK "config.toml     已填写完整"
} else {
    Write-Fail "config.toml     还有占位符"
    Write-Host "                   nano ~/.cc-connect/config.toml"
}

# 微信凭据
if (Test-Termux "grep -q 'token = `"wx_' /data/data/com.termux/files/home/.cc-connect/config.toml") {
    Write-OK "微信凭据        已配置"
} else {
    Write-Fail "微信凭据        未配置"
    Write-Host "                   proot -b /data/local/tmp/resolv.conf:/etc/resolv.conf -b ~/proot-fs/etc/ssl:/etc/ssl -b /data/data/com.termux/files/usr:/usr -b ~/:/home /usr/bin/env PATH=/usr/bin:/usr/local/bin:/home/bin ~/bin/cc-connect weixin setup --project nene"
}

# OpenID
if ($openidOk) {
    Write-OK "OpenID          已配置"
} else {
    Write-Fail "OpenID          未配置"
    Write-Host "                   发消息后运行: bash ~/pocket-wechat-bot/scripts/fix-openid.sh"
}

# Bot 运行
if ($running) {
    Write-OK "Bot 运行中       YES"
} else {
    Write-Fail "Bot 运行中       NO"
    Write-Host "                   完成配置后重跑 deploy.bat"
}

Write-Host ""
Write-Host "  --- 必须手动完成 ---"
Write-Host ""
Write-Host "  [ ] 关闭 Android 省电限制"
Write-Host "      设置 -> 应用 -> Termux -> 后台耗电管理 -> 允许后台运行"
Write-Host "      （不关的话 Android 可能随时杀掉 bot）"
Write-Host ""

Write-Host "  --- 常用操作 ---"
Write-Host "  查看日志:  cat ~/cc-connect/cc-connect.log"
Write-Host "  重启 bot:  pkill -f cc-connect && bash ~/start-nene.sh"
Write-Host "  管理面板:  http://127.0.0.1:9820"
Write-Host "  重新部署:  再次右键运行本脚本（已完成的步骤自动跳过）"
Write-Host ""

$allGood = $apiKeySet -and ($rem.Trim() -eq "0") -and $tokenOk -and $openidOk -and $running
if ($allGood) {
    Write-Host "=============================================" -ForegroundColor Green
    Write-Host "  全部就绪！微信给 Bot 发条消息试试吧~" -ForegroundColor Green
    Write-Host "=============================================" -ForegroundColor Green
} else {
    Write-Host "=============================================" -ForegroundColor Yellow
    Write-Host "  还有待办项。完成后重跑 deploy.bat 即可。" -ForegroundColor Yellow
    Write-Host "=============================================" -ForegroundColor Yellow
}

Write-Host ""
Pause
