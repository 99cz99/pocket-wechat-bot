# deploy.ps1 - 鍚戝寮忛儴缃插井淇?AI 鏈哄櫒浜哄埌 Android 鎵嬫満
# 鐢ㄦ硶: 鍙抽敭 -> 浣跨敤 PowerShell 杩愯
# 闇€瑕? adb + USB 杩炴帴 + 鎵嬫満宸茶 Termux

$ErrorActionPreference = "Continue"
$Repo = Split-Path -Parent $PSScriptRoot
$Tgz = "$env:TEMP\pwb-deploy.tar"

# ============================================================
# 宸ュ叿鍑芥暟
# ============================================================

# 鍦ㄦ墜鏈轰笂閫氳繃 run-as 鎵ц鍛戒护锛岃繑鍥炶緭鍑?function Invoke-Termux($Cmd) {
    $escaped = $Cmd -replace "'", "'\''"
    $result = adb shell "run-as com.termux sh -c 'export HOME=/data/data/com.termux/files/home; $escaped'" 2>&1
    $script:LastExitOk = ($LASTEXITCODE -eq 0)
    return $result
}

# 妫€鏌ユ墜鏈轰笂鐨勬煇涓潯浠讹紝杩斿洖 $true / $false
function Test-Termux($Cmd) {
    $out = Invoke-Termux "$Cmd 2>/dev/null && echo YES || echo NO"
    return ($out -match "YES")
}

function Write-Step($num, $title) {
    Write-Host ""
    Write-Host "鈺斺晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晽"
    Write-Host ("鈺? 姝ラ {0}: {1}" -f $num, $title.PadRight(39)) -NoNewline
    Write-Host "鈺?
    Write-Host "鈺氣晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨暆"
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
# 妯箙
# ============================================================
Write-Host ""
Write-Host "鈺斺晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晽"
Write-Host "鈺? 寰俊 AI 鏈哄櫒浜?- 鍚戝寮忛儴缃?       鈺?
Write-Host "鈺氣晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨暆"
Write-Host ""

# ============================================================
# 姝ラ 1: 鐜妫€鏌?# ============================================================
Write-Step 1 "鐜妫€鏌?

# ADB
Write-Info "妫€鏌?ADB..."
if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
    Write-Fail "鎵句笉鍒?adb锛岃鍏堝畨瑁?Android Platform Tools"
    Write-Host "    https://developer.android.com/studio/releases/platform-tools"
    Pause; exit 1
}
$devices = adb devices 2>$null | Select-String 'device$'
if (-not $devices) {
    Write-Fail "鏈娴嬪埌鎵嬫満"
    Write-Host "    1. USB 宸茶繛鎺ワ紵"
    Write-Host "    2. 鎵嬫満宸插紑鍚?USB 璋冭瘯锛?
    Write-Host "    3. 鎵嬫満涓婂凡鎺堟潈姝ょ數鑴戯紵"
    Write-Host ""
    adb devices
    Pause; exit 1
}
Write-OK "ADB 杩炴帴姝ｅ父"

# Termux
Write-Info "妫€鏌?Termux..."
$termux = adb shell pm list packages 2>&1 | Out-String
if ($termux -notmatch "com.termux") {
    Write-Fail "鎵嬫満鏈畨瑁?Termux"
    Write-Host "    璇峰湪 F-Droid 涓嬭浇锛歨ttps://f-droid.org/packages/com.termux/"
    Write-Host "    杩橀渶瀹夎 Termux:API"
    Pause; exit 1
}
Write-OK "Termux 宸插畨瑁?

# 瀛樺偍绌洪棿
Write-Info "妫€鏌ュ瓨鍌ㄧ┖闂?.."
$avail = Invoke-Termux "df -k /data/data/com.termux/files/home 2>/dev/null | tail -1 | awk '{print \$4}'"
if ($avail -and [int]$avail -lt 512000) {
    Write-Warn "鍓╀綑绌洪棿涓嶈冻 500MB锛堝綋鍓?$([math]::Floor([int]$avail/1024))MB锛夛紝閮ㄧ讲鍙兘澶辫触"
}

# 妫€鏌ユ槸鍚︽浘缁忛儴缃茶繃锛堟湁鐘舵€佹枃浠讹級
$isRerun = Test-Termux "test -f /data/data/com.termux/files/home/.pocket-bot-deploy-state"
if ($isRerun) {
    Write-Info "妫€娴嬪埌宸叉湁閮ㄧ讲璁板綍锛屽凡瀹屾垚姝ラ灏嗚嚜鍔ㄨ烦杩?
}

# ============================================================
# 姝ラ 2: 鎺ㄩ€佹枃浠?# ============================================================
Write-Step 2 "鎺ㄩ€佹枃浠跺埌鎵嬫満"

# --- 2.1 鑾峰彇 cc-connect 浜岃繘鍒?---
Write-Info "鏌ユ壘 cc-connect 浜岃繘鍒?.."
$ccBin = $null
$ccUrl = "https://github.com/chenhg5/cc-connect/releases/latest/download/cc-connect-linux-arm64"
$desktopDir = [Environment]::GetFolderPath("Desktop")
$desktopFile = $null

# 妫€鏌ユ闈㈡枃浠?$desktopFile = Get-ChildItem -Path $desktopDir -Filter "cc-connect*" | Where-Object {
    -not $_.PSIsContainer -and $_.Name -match "^cc-connect" -and $_.Name -notmatch "\.(md|txt)$"
} | Select-Object -First 1

if ($desktopFile) {
    $desktopFilePath = $desktopFile.FullName
    Write-Info "妫€娴嬪埌妗岄潰鏂囦欢: $($desktopFile.Name)"
    $magic = [System.IO.File]::ReadAllBytes($desktopFilePath)[0..3]
    if ($magic[0] -eq 0x7f -and $magic[1] -eq 0x45) {
        $ccBin = $desktopFilePath
    } elseif ($desktopFilePath -match "\.(tar|gz|tgz|zip)$") {
        Write-Info "妫€娴嬪埌鍘嬬缉鍖咃紝姝ｅ湪瑙ｅ帇..."
        $extractDir = "$env:TEMP\cc-extract"
        Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
        try {
            tar -xf $desktopFilePath -C $extractDir 2>$null
            if ($LASTEXITCODE -ne 0) { throw "tar failed" }
        } catch {
            Write-Fail "瑙ｅ帇澶辫触锛岃鎵嬪姩瑙ｅ帇鍚庡皢浜岃繘鍒舵枃浠舵斁鍒版闈?
            Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
            Pause; exit 1
        }
        $found = Get-ChildItem -Path $extractDir -Recurse -File | Where-Object {
            $m = [System.IO.File]::ReadAllBytes($_.FullName)[0..3]
            $m[0] -eq 0x7f -and $m[1] -eq 0x45
        } | Select-Object -First 1
        if ($found) {
            $ccBin = $found.FullName
            Write-OK "宸叉彁鍙? $($found.Name)"
        } else {
            Write-Fail "鍘嬬缉鍖呭唴鏈壘鍒?ELF 浜岃繘鍒?
            Write-Host "    璇风‘璁や笅杞界殑鏄?Assets 涓殑 cc-connect-linux-arm64.tar"
            Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
            Pause; exit 1
        }
    } else {
        Write-Fail "妗岄潰鏂囦欢鏃犳硶璇嗗埆锛堟棦闈炰簩杩涘埗涔熼潪鍘嬬缉鍖咃級"
        Write-Host "    璇蜂粠 GitHub Assets 涓嬭浇 cc-connect-*-linux-arm64.tar"
        Write-Host "    https://github.com/chenhg5/cc-connect/releases/latest"
        Pause; exit 1
    }
}

# 鑷姩涓嬭浇
if (-not $ccBin) {
    Write-Info "灏濊瘯鑷姩涓嬭浇 cc-connect..."
    $ccBin = "$env:TEMP\cc-connect-linux-arm64"
    try {
        Invoke-WebRequest -Uri $ccUrl -OutFile $ccBin -TimeoutSec 60 -ErrorAction Stop
        Write-OK "涓嬭浇瀹屾垚"
    } catch {
        Remove-Item $ccBin -ErrorAction SilentlyContinue
        $ccBin = $null
        Write-Warn "鑷姩涓嬭浇澶辫触锛堝彲鑳芥槸缃戠粶闂锛?
    }
}

# 鎵嬪姩涓嬭浇鎸囧紩
if (-not $ccBin) {
    Write-Host ""
    Write-Host "  璇锋墜鍔ㄦ搷浣滐細"
    Write-Host "  1. 娴忚鍣ㄦ墦寮€: https://github.com/chenhg5/cc-connect/releases/latest"
    Write-Host "  2. 鍦?Assets 鍖哄煙鎵惧埌 cc-connect-*-linux-arm64.tar"
    Write-Host "  3. 涓嬭浇鍒版闈紙涓嶈鏀瑰悕锛?
    Write-Host "  4. 涓嬭浇瀹屾垚鍚庨噸鏂拌繍琛屾湰鑴氭湰锛堜細鑷姩瑙ｅ帇锛?
    Write-Host ""
    Pause; exit 1
}

# --- 2.2 鎺ㄩ€?cc-connect 鍒版墜鏈?---
Write-Info "鎺ㄩ€?cc-connect 鍒版墜鏈?.."
adb push $ccBin /sdcard/Download/cc-connect-linux-arm64 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Fail "鎺ㄩ€佸け璐ワ紝璇锋鏌?USB 杩炴帴鍜屾墜鏈哄瓨鍌ㄧ┖闂?
    Pause; exit 1
}

# 澶嶅埗鍒?Termux 绉佹湁鐩綍锛坮un-as 璁块棶涓嶄簡 /sdcard/锛?adb shell "cat /sdcard/Download/cc-connect-linux-arm64 | run-as com.termux sh -c 'cat > /data/data/com.termux/files/home/cc-connect-linux-arm64 && chmod +x /data/data/com.termux/files/home/cc-connect-linux-arm64'" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Fail "澶嶅埗鍒?Termux 澶辫触"
    Pause; exit 1
}
Write-OK "cc-connect 宸叉帹閫佸埌鎵嬫満"

# 娓呯悊涓存椂鏂囦欢
if ($ccBin -ne $desktopFilePath) {
    Remove-Item $ccBin -ErrorAction SilentlyContinue
}

# --- 2.3 鎵撳寘骞舵帹閫侀」鐩枃浠?---
Write-Info "鎵撳寘椤圭洰鏂囦欢..."
Push-Location $Repo
try {
    git archive -o $Tgz HEAD 2>$null
    if ($LASTEXITCODE -ne 0) {
        git archive HEAD > $Tgz 2>$null
        if ($LASTEXITCODE -ne 0) { throw "git archive failed" }
    }
} catch {
    Write-Fail "鎵撳寘澶辫触锛岃纭 git 宸插畨瑁?
    Pop-Location; Pause; exit 1
}
Pop-Location
Write-OK "鎵撳寘瀹屾垚"

Write-Info "鎺ㄩ€佸埌鎵嬫満..."
adb push $Tgz /sdcard/Download/pwb-deploy.tar 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Fail "鎺ㄩ€佸け璐?
    Remove-Item $Tgz -ErrorAction SilentlyContinue
    Pause; exit 1
}

Write-Info "瑙ｅ帇..."
adb shell "rm -rf /sdcard/Download/pocket-wechat-bot && mkdir -p /sdcard/Download/pocket-wechat-bot && cd /sdcard/Download/pocket-wechat-bot && tar xf /sdcard/Download/pwb-deploy.tar && rm /sdcard/Download/pwb-deploy.tar && find . -name '*.sh' -exec sed -i 's/\r$//' {} \;" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Fail "瑙ｅ帇澶辫触"
    Remove-Item $Tgz -ErrorAction SilentlyContinue
    Pause; exit 1
}
Remove-Item $Tgz -ErrorAction SilentlyContinue

# 澶嶅埗鍒?Termux
Write-Info "澶嶅埗鍒?Termux 绉佹湁鐩綍..."
adb shell "cd /sdcard/Download && tar czf - pocket-wechat-bot/ 2>/dev/null | run-as com.termux sh -c 'export HOME=/data/data/com.termux/files/home && cd /data/data/com.termux/files/home && rm -rf pocket-wechat-bot && tar xzf -'" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "  鈹屸攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?
    Write-Host "  鈹? 鑷姩澶嶅埗澶辫触锛岄渶瑕佸湪鎵嬫満涓婃墜鍔ㄦ搷浣?         鈹?
    Write-Host "  鈹斺攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?
    Write-Host ""
    Write-Host "  鎷胯捣鎵嬫満锛屾墦寮€ Termux锛屼緷娆¤緭鍏ワ細"
    Write-Host ""
    Write-Host "    cp -r /sdcard/Download/pocket-wechat-bot ~/"
    Write-Host "    cd ~/pocket-wechat-bot"
    Write-Host "    bash scripts/setup-phone.sh"
    Write-Host ""
    Write-Host "  鐒跺悗鎸夌収鎵嬫満绔剼鏈彁绀哄畬鎴愰儴缃层€?
    Write-Host ""
    Pause
    exit 0
}
Write-OK "鏂囦欢宸叉帹閫佸埌 Termux"

# ============================================================
# 姝ラ 3: 鍩虹鐜瀹夎锛堝叏鑷姩锛?# ============================================================
Write-Step 3 "鍩虹鐜瀹夎锛堝叏鑷姩锛岀害 2-5 鍒嗛挓锛?

Write-Info "姝ｅ湪鎵嬫満涓婂畨瑁呬緷璧栧拰閰嶇疆鐜..."
Write-Info "锛堣繖姝ヤ笉闇€瑕佷綘鎿嶄綔锛岀◢绛?..锛?
Write-Host ""

# 杩愯 setup-phone.sh锛堝畠浼氳嚜鍔ㄨ烦杩囧凡瀹屾垚鐨勬楠わ級
$setupOutput = adb shell "run-as com.termux sh -c 'export HOME=/data/data/com.termux/files/home && cd /data/data/com.termux/files/home/pocket-wechat-bot && chmod +x scripts/setup-phone.sh scripts/start-bot.sh && DEPLOY_NONINTERACTIVE=1 ./scripts/setup-phone.sh'" 2>&1
$setupExit = $LASTEXITCODE

# 瑙ｆ瀽杈撳嚭涓殑鍏抽敭鐘舵€佽
$setupOutput -split "`n" | ForEach-Object {
    $line = $_
    if ($line -match '^\s*\[OK\]') {
        Write-Host "  $line" -ForegroundColor Green
    } elseif ($line -match '^\s*\[FAIL\]') {
        Write-Host "  $line" -ForegroundColor Red
    } elseif ($line -match '^\s*\[SKIP\]') {
        Write-Host "  $line" -ForegroundColor DarkGray
    } elseif ($line -match '^\s*\[\.\.\]') {
        Write-Host "  $line" -ForegroundColor Cyan
    } elseif ($line -match '^\s*\[!!\]') {
        Write-Host "  $line" -ForegroundColor Yellow
    }
}

Write-Host ""

# ============================================================
# 姝ラ 4: 閰嶇疆 API Key锛圥C 绔氦浜掞級
# ============================================================
Write-Step 4 "閰嶇疆 DeepSeek API Key"

$apiKeySet = Test-Termux "grep -q 'ANTHROPIC_API_KEY=sk-' /data/data/com.termux/files/home/.bashrc"

if ($apiKeySet) {
    Write-OK "API Key 宸查厤缃?
} else {
    Write-Warn "API Key 鏈缃?
    Write-Host ""
    Write-Host "  DeepSeek API Key 鑾峰彇鏂瑰紡锛?
    Write-Host "  鎵撳紑 https://platform.deepseek.com/api_keys"
    Write-Host "  娉ㄥ唽/鐧诲綍鍚庡垱寤?API Key锛屽鍒?sk- 寮€澶寸殑涓€涓插瓧绗?
    Write-Host ""

    do {
        $apiKey = Read-Host "  璇疯緭鍏?API Key锛坰k-...锛?
        if (-not $apiKey -or $apiKey -notmatch '^sk-') {
            Write-Warn "鏍煎紡涓嶆纭紙搴斾互 sk- 寮€澶达級"
            $apiKey = $null
        }
    } while (-not $apiKey)

    Write-Info "姝ｅ湪鍐欏叆鎵嬫満..."

    # 鍐欏叆 bashrc
    $bashrcLine = "export ANTHROPIC_API_KEY=$apiKey"
    Invoke-Termux "echo '$bashrcLine' >> /data/data/com.termux/files/home/.bashrc" | Out-Null

    # 鏇存柊 claude 鍖呰鍣紙cc-connect 涓嶄紶閫掔幆澧冨彉閲忥級
    $wrapper = @"
#!/data/data/com.termux/files/usr/bin/sh
export ANTHROPIC_API_KEY="$apiKey"
exec /usr/bin/node /home/bin/claude-fast.js "\$@"
"@
    # 鐢?base64 閬垮厤 shell 杞箟闂
    $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($wrapper))
    Invoke-Termux "echo '$b64' | base64 -d > /data/data/com.termux/files/usr/bin/claude && chmod +x /data/data/com.termux/files/usr/bin/claude" | Out-Null

    # 楠岃瘉
    $verify = Test-Termux "grep -q 'ANTHROPIC_API_KEY=sk-' /data/data/com.termux/files/home/.bashrc"
    if ($verify) {
        Write-OK "API Key 宸插啓鍏ユ墜鏈?
    } else {
        Write-Fail "鍐欏叆澶辫触锛岃鎵嬪姩鍦?Termux 涓墽琛岋細"
        Write-Host "    echo 'export ANTHROPIC_API_KEY=$apiKey' >> ~/.bashrc"
    }
}

# ============================================================
# 姝ラ 5: 閰嶇疆 config.toml
# ============================================================
Write-Step 5 "閰嶇疆鏂囦欢锛坈onfig.toml锛?

# 鑾峰彇 API Key锛堜互渚垮～鍏?config.toml 妯℃澘锛?$apiKeyVal = Invoke-Termux "grep 'ANTHROPIC_API_KEY' /data/data/com.termux/files/home/.bashrc 2>/dev/null | tail -1 | sed 's/.*=//'"
$apiKeyVal = $apiKeyVal.Trim()

# 杩愯 step_config锛堝畠浼氱敤 bashrc 涓殑 key 鑷姩濉崰浣嶇锛?$configOut = Invoke-Termux "cd /data/data/com.termux/files/home/pocket-wechat-bot && DEPLOY_API_KEY='$apiKeyVal' bash -c 'source scripts/setup-phone.sh; step_config'"
Write-Host $configOut

# 妫€鏌ュ墿浣欏崰浣嶇
$remaining = Invoke-Termux "grep -c '<YOUR_' /data/data/com.termux/files/home/.cc-connect/config.toml 2>/dev/null || echo 0"
$remaining = $remaining.Trim()

if ($remaining -eq "0") {
    Write-OK "config.toml 宸插畬鏁寸敓鎴?
} else {
    Write-Warn "config.toml 杩樻湁 $remaining 涓崰浣嶇寰呭～鍐?
    $placeholders = Invoke-Termux "grep '<YOUR_' /data/data/com.termux/files/home/.cc-connect/config.toml"
    Write-Host "  $placeholders"
    Write-Host ""
    Write-Host "  绋嶅悗浼氬湪涓嬩竴姝ヨ幏鍙栧井淇″嚟鎹紝瀹屾垚鍚庤嚜鍔ㄥ～鍏ャ€?
    Write-Host "  OpenID 鍙互鍦?bot 鍚姩鍚庡彂 /whoami 鑾峰彇銆?
}

# ============================================================
# 姝ラ 6: 寰俊鍑嵁
# ============================================================
Write-Step 6 "寰俊鎵爜鑾峰彇鍑嵁"

$tokenOk = Test-Termux "grep -q 'token = \"wx_' /data/data/com.termux/files/home/.cc-connect/config.toml"

if ($tokenOk) {
    $token = Invoke-Termux "grep 'token = ' /data/data/com.termux/files/home/.cc-connect/config.toml | head -1 | sed 's/.*= \"//;s/\"//'"
    Write-OK "寰俊鍑嵁宸查厤缃? $($token.Trim())"
} else {
    Write-Warn "寰俊鍑嵁鏈厤缃?

    Write-Host ""
    Write-Host "  鈹屸攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?
    Write-Host "  鈹? 鐜板湪闇€瑕佹嬁璧锋墜鏈烘搷浣?                       鈹?
    Write-Host "  鈹斺攢鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹?
    Write-Host ""
    Write-Host "  鍦ㄦ墜鏈?Termux 涓繍琛屼互涓嬪懡浠わ細"
    Write-Host ""
    Write-Host "    ~/bin/cc-connect weixin setup --project nene"
    Write-Host ""
    Write-Host "  浼氭樉绀轰竴涓簩缁寸爜閾炬帴銆?
    Write-Host "  1. 鍦ㄦ墜鏈烘祻瑙堝櫒鎵撳紑璇ラ摼鎺?
    Write-Host "  2. 鐢ㄤ綘鐨勫井淇″皬鍙锋壂鎻?
    Write-Host "  3. 鎵爜鎴愬姛鍚庯紝Termux 浼氭樉绀?token 鍜?account_id"
    Write-Host ""

    do {
        Read-Host "  鎵爜瀹屾垚鍚庯紝鎸夊洖杞︾户缁?

        # 妫€鏌?token 鏄惁宸茶嚜鍔ㄥ～鍏?config.toml
        # (cc-connect 鎵爜鎴愬姛鍚庝細鍒锋柊 config.toml)
        $tokenCheck = Invoke-Termux "grep -o 'wx_[a-zA-Z0-9_-]*' /data/data/com.termux/files/home/.cc-connect/config.toml 2>/dev/null | head -1"
        $tokenCheck = $tokenCheck.Trim()

        if ($tokenCheck -and $tokenCheck -ne '<YOUR_BOT_TOKEN>') {
            Write-OK "妫€娴嬪埌 token: $tokenCheck"
            break
        }

        # 灏濊瘯浠庢壂鎻忔棩蹇楁彁鍙?        $scanToken = Invoke-Termux "cat /data/data/com.termux/files/home/.cc-connect/cc-connect.log 2>/dev/null | grep -o 'wx_[a-zA-Z0-9_-]*' | head -1"
        $scanToken = $scanToken.Trim()
        if ($scanToken) {
            # 鑷姩濉叆 config.toml
            Invoke-Termux "sed -i 's|<YOUR_BOT_TOKEN>|$scanToken|g' /data/data/com.termux/files/home/.cc-connect/config.toml" | Out-Null
            Write-OK "宸蹭粠鏃ュ織鎻愬彇 token: $scanToken"
            break
        }

        Write-Warn "灏氭湭妫€娴嬪埌 token"
        Write-Host "  璇风‘璁わ細"
        Write-Host "    1. 宸插湪 Termux 涓繍琛屼簡鎵爜鍛戒护"
        Write-Host "    2. 宸茬敤寰俊鎵弿浜嗕簩缁寸爜"
        Write-Host "    3. 缁堢鏄剧ず浜?'token:' 鍜?'account_id:'"
        Write-Host ""

        $retry = Read-Host "  閲嶈瘯锛熸寜鍥炶溅閲嶈瘯锛岃緭鍏?s 璺宠繃 [s]"
        if ($retry -eq 's') {
            Write-Warn "宸茶烦杩囥€傜◢鍚庡彲鎵嬪姩缂栬緫 ~/.cc-connect/config.toml"
            break
        }
    } while ($true)
}

# ============================================================
# 姝ラ 7: 鍚姩 Bot
# ============================================================
Write-Step 7 "鍚姩 Bot"

Write-Info "閮ㄧ讲鍚姩鑴氭湰..."
$startOut = Invoke-Termux "cd /data/data/com.termux/files/home/pocket-wechat-bot && bash -c 'source scripts/setup-phone.sh; step_startup'"
Write-Host $startOut

Write-Info "姝ｅ湪鍚姩 cc-connect..."
$launchOut = Invoke-Termux "cd /data/data/com.termux/files/home/pocket-wechat-bot && bash -c 'source scripts/setup-phone.sh; step_launch'"
Write-Host $launchOut

# 楠岃瘉
$running = Test-Termux "pgrep -f cc-connect"
if ($running) {
    Write-OK "Bot 姝ｅ湪杩愯"
} else {
    Write-Warn "Bot 鏈兘鍚姩锛屽彲鑳藉洜涓虹己灏戦厤缃?
    Write-Host "  瀹屾垚涓嬫柟寰呭姙浜嬮」鍚庨噸璺?deploy.bat 鍗冲彲"
}

# ============================================================
# 姝ラ 8: OpenID 閰嶇疆
# ============================================================
Write-Step 8 "閰嶇疆 OpenID"

$openidOk = Test-Termux "test -f /data/data/com.termux/files/home/cc-connect/CLAUDE.md && ! grep -q '<YOUR_WECHAT_OPENID>' /data/data/com.termux/files/home/cc-connect/CLAUDE.md"

if ($openidOk) {
    Write-OK "OpenID 宸查厤缃?
} else {
    Write-Warn "OpenID 鍗犱綅绗︽湭鏇挎崲"
    Write-Host ""
    Write-Host "  璇峰厛鍦ㄥ井淇￠噷缁?Bot 鍙戜竴鏉℃秷鎭紙浠绘剰鍐呭锛夈€?
    Write-Host ""

    do {
        Read-Host "  鍙戝畬鍚庢寜鍥炶溅"

        # 杩愯 fix-openid.sh
        $fixOut = Invoke-Termux "bash /data/data/com.termux/files/home/pocket-wechat-bot/scripts/fix-openid.sh"
        Write-Host $fixOut

        $openidOk = Test-Termux "test -f /data/data/com.termux/files/home/cc-connect/CLAUDE.md && ! grep -q '<YOUR_WECHAT_OPENID>' /data/data/com.termux/files/home/cc-connect/CLAUDE.md"
        if ($openidOk) {
            Write-OK "OpenID 宸茶嚜鍔ㄥ～鍏?
            break
        }

        Write-Warn "鏈兘浠庢棩蹇楁彁鍙?OpenID"
        Write-Host "  璇风‘璁ゅ凡缁?Bot 鍙戦€佷簡娑堟伅"
        Write-Host "  涔熷彲浠ュ湪 Termux 涓墜鍔ㄨ繍琛? bash ~/pocket-wechat-bot/scripts/fix-openid.sh"

        $retry = Read-Host "  閲嶈瘯锛熸寜鍥炶溅閲嶈瘯锛岃緭鍏?s 璺宠繃 [s]"
        if ($retry -eq 's') {
            Write-Warn "宸茶烦杩囥€傜◢鍚庡彲鎵嬪姩杩愯 fix-openid.sh"
            break
        }
    } while ($true)
}

# ============================================================
# 姝ラ 9: 鏀跺熬妫€鏌ユ竻鍗?# ============================================================
Write-Step 9 "閮ㄧ讲鍚庢鏌ユ竻鍗?

Write-Host ""
Write-Host "  鈹€鈹€鈹€ 鐘舵€佹鏌?鈹€鈹€鈹€"
Write-Host ""

# API Key
if (Test-Termux "grep -q 'ANTHROPIC_API_KEY=sk-' /data/data/com.termux/files/home/.bashrc") {
    Write-OK "API Key         宸茶缃?
} else {
    Write-Fail "API Key         鏈缃?
    Write-Host "                   echo 'export ANTHROPIC_API_KEY=sk-浣犵殑key' >> ~/.bashrc"
}

# config.toml
$rem = Invoke-Termux "grep -c '<YOUR_' /data/data/com.termux/files/home/.cc-connect/config.toml 2>/dev/null || echo 0"
if ($rem.Trim() -eq "0") {
    Write-OK "config.toml     宸插～鍐欏畬鏁?
} else {
    Write-Fail "config.toml     杩樻湁鍗犱綅绗?
    Write-Host "                   nano ~/.cc-connect/config.toml"
}

# 寰俊鍑嵁
if (Test-Termux "grep -q 'token = \"wx_' /data/data/com.termux/files/home/.cc-connect/config.toml") {
    Write-OK "寰俊鍑嵁        宸查厤缃?
} else {
    Write-Fail "寰俊鍑嵁        鏈厤缃?
    Write-Host "                   ~/bin/cc-connect weixin setup --project nene"
}

# OpenID
if ($openidOk) {
    Write-OK "OpenID          宸查厤缃?
} else {
    Write-Fail "OpenID          鏈厤缃?
    Write-Host "                   鍙戞秷鎭悗杩愯: bash ~/pocket-wechat-bot/scripts/fix-openid.sh"
}

# Bot 杩愯
if ($running) {
    Write-OK "Bot 杩愯涓?      YES"
} else {
    Write-Fail "Bot 杩愯涓?      NO"
    Write-Host "                   瀹屾垚閰嶇疆鍚庨噸璺?deploy.bat"
}

Write-Host ""
Write-Host "  鈹€鈹€鈹€ 蹇呴』鎵嬪姩瀹屾垚 鈹€鈹€鈹€"
Write-Host ""
Write-Host "  [ ] 鍏抽棴 Android 鐪佺數闄愬埗"
Write-Host "      璁剧疆 -> 搴旂敤 -> Termux -> 鍚庡彴鑰楃數绠＄悊 -> 鍏佽鍚庡彴杩愯"
Write-Host "      锛堜笉鍏崇殑璇?Android 鍙兘闅忔椂鏉€鎺?bot锛?
Write-Host ""

Write-Host "  鈹€鈹€鈹€ 甯哥敤鎿嶄綔 鈹€鈹€鈹€"
Write-Host "  鏌ョ湅鏃ュ織:  cat ~/cc-connect/cc-connect.log"
Write-Host "  鍓嶅彴杩愯:  bash ~/start-nene.sh"
Write-Host "  閲嶅惎 bot:  pkill -f cc-connect && bash ~/start-nene.sh"
Write-Host "  绠＄悊闈㈡澘:  http://127.0.0.1:9820"
Write-Host "  閲嶆柊閮ㄧ讲:  鍐嶆鍙抽敭杩愯鏈剼鏈紙宸插畬鎴愮殑姝ラ鑷姩璺宠繃锛?
Write-Host ""

$allGood = $apiKeySet -and ($rem.Trim() -eq "0") -and $tokenOk -and $openidOk -and $running
if ($allGood) {
    Write-Host "鈺斺晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晽" -ForegroundColor Green
    Write-Host "鈺? 鍏ㄩ儴灏辩华锛佸井淇＄粰 Bot 鍙戞潯娑堟伅璇曡瘯鍚       鈺? -ForegroundColor Green
    Write-Host "鈺氣晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨暆" -ForegroundColor Green
} else {
    Write-Host "鈺斺晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晽" -ForegroundColor Yellow
    Write-Host "鈺? 杩樻湁寰呭姙椤广€傚畬鎴愬悗閲嶈窇 deploy.bat 鍗冲彲銆?   鈺? -ForegroundColor Yellow
    Write-Host "鈺氣晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨暆" -ForegroundColor Yellow
}

Write-Host ""
Pause
