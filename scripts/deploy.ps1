# deploy.ps1 - 一键部署微信 AI 机器人到 Android 手机
# 用法: 右键 -> 使用 PowerShell 运行
# 需要: adb + USB 连接 + 手机已装 Termux

$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent $PSScriptRoot
$Tgz = "$env:TEMP\pwb-deploy.tar"

Write-Host ""
Write-Host "╔══════════════════════════════════════╗"
Write-Host "║  微信 AI 机器人 - PC 端一键部署      ║"
Write-Host "╚══════════════════════════════════════╝"
Write-Host ""

# ----- 检查 ADB -----
Write-Host "[*] 检查 ADB 连接..."
if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
    Write-Host "[!] 找不到 adb，请先安装 Android Platform Tools"
    Write-Host "    https://developer.android.com/studio/releases/platform-tools"
    Pause; exit 1
}
$devices = adb devices 2>$null | Select-String 'device$'
if (-not $devices) {
    Write-Host "[!] 未检测到手机，请确认："
    Write-Host "    1. USB 已连接"
    Write-Host "    2. 手机已开启 USB 调试"
    Write-Host "    3. 手机上已授权此电脑"
    Write-Host ""
    adb devices
    Pause; exit 1
}
Write-Host "[*] ADB 连接正常"

# ----- 检查 Termux -----
Write-Host "[*] 检查 Termux..."
$termux = adb shell pm list packages 2>&1 | Out-String
if ($termux -notmatch "com.termux") {
    Write-Host "[!] 手机未安装 Termux，请先在 F-Droid 下载："
    Write-Host "    https://f-droid.org/packages/com.termux/"
    Write-Host "    还需安装 Termux:API"
    Pause; exit 1
}
Write-Host "[*] Termux 已安装"

# ----- 打包项目 -----
Write-Host "[*] 正在打包项目文件..."
Push-Location $Repo
try {
    git archive -o $Tgz HEAD 2>$null
    if ($LASTEXITCODE -ne 0) {
        git archive HEAD > $Tgz 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "git archive failed"
        }
    }
} catch {
    Write-Host "[!] 打包失败，请确认 git 已安装"
    Pop-Location; Pause; exit 1
}
Pop-Location
Write-Host "[*] 打包完成"

# ----- 推送到手机 -----
Write-Host "[*] 正在推送到手机..."
adb push $Tgz /sdcard/Download/pwb-deploy.tar
if ($LASTEXITCODE -ne 0) {
    Write-Host "[!] 推送失败，请检查 USB 连接和手机存储空间"
    Remove-Item $Tgz -ErrorAction SilentlyContinue
    Pause; exit 1
}

Write-Host "[*] 正在解压..."
adb shell "rm -rf /sdcard/Download/pocket-wechat-bot && mkdir -p /sdcard/Download/pocket-wechat-bot && cd /sdcard/Download/pocket-wechat-bot && tar xf /sdcard/Download/pwb-deploy.tar && rm /sdcard/Download/pwb-deploy.tar && find . -name '*.sh' -exec sed -i 's/\r$//' {} \;"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[!] 解压失败"
    Remove-Item $Tgz -ErrorAction SilentlyContinue
    Pause; exit 1
}
Remove-Item $Tgz -ErrorAction SilentlyContinue
Write-Host "[*] 文件已推送到手机"

# ----- 复制到 Termux -----
Write-Host "[*] 正在复制到 Termux..."
adb shell "cd /sdcard/Download && tar czf - pocket-wechat-bot/ 2>/dev/null | run-as com.termux sh -c 'export HOME=/data/data/com.termux/files/home && cd /data/data/com.termux/files/home && rm -rf pocket-wechat-bot && tar xzf -'" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════╗"
    Write-Host "║  需要在手机上完成最后一步                    ║"
    Write-Host "╚══════════════════════════════════════════════╝"
    Write-Host ""
    Write-Host "现在拿起手机，打开 Termux 应用。"
    Write-Host "你会看到一个命令行终端。"
    Write-Host "依次输入以下 3 条命令（输完一条按回车）："
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════╗"
    Write-Host "║                                              ║"
    Write-Host "║  cp -r /sdcard/Download/pocket-wechat-bot ~/ ║"
    Write-Host "║                                              ║"
    Write-Host "║  cd ~/pocket-wechat-bot                      ║"
    Write-Host "║                                              ║"
    Write-Host "║  bash scripts/setup-phone.sh                 ║"
    Write-Host "║                                              ║"
    Write-Host "╚══════════════════════════════════════════════╝"
    Write-Host ""
    Write-Host "第 3 条命令运行后，脚本会自动安装依赖、配置环境、"
    Write-Host "部署人格文件。过程中会问你几个问题："
    Write-Host "  - DeepSeek API Key"
    Write-Host "  - 微信 OpenID（可先填 *）"
    Write-Host "  - 微信扫码获取 token"
    Write-Host "扫码后 token 会自动填入，不用手动编辑。"
    Write-Host "整个过程大约 3-5 分钟。"
    Write-Host ""
    Pause
    exit 0
}

# ----- 构建环境变量 -----
$env:DEPLOY_NONINTERACTIVE = "1"

# ----- 远程执行 setup-phone.sh -----
Write-Host "[*] 正在手机上运行部署脚本..."
Write-Host ""
Write-Host "----------------------------------------"
Write-Host "  手机端输出："
Write-Host "----------------------------------------"
Write-Host ""
adb shell "run-as com.termux sh -c 'export HOME=/data/data/com.termux/files/home && cd /data/data/com.termux/files/home/pocket-wechat-bot && chmod +x scripts/setup-phone.sh scripts/start-bot.sh && DEPLOY_NONINTERACTIVE=1 ./scripts/setup-phone.sh'"
$exitCode = $LASTEXITCODE
Write-Host ""
Write-Host "----------------------------------------"
Write-Host "  手机端输出结束（退出码: $exitCode）"
Write-Host "----------------------------------------"

# ----- 收尾 -----
if ($exitCode -ne 0) {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════╗"
    Write-Host "║  部署失败！请查看上方手机端输出定位问题      ║"
    Write-Host "╚══════════════════════════════════════════════╝"
    Write-Host ""
    Write-Host "常见原因："
    Write-Host "  - 网络问题：手机无法访问 GitHub/DeepSeek"
    Write-Host "  - 存储不足：手机剩余空间 < 1GB"
    Write-Host "  - 权限问题：USB 调试授权已过期"
    Write-Host ""
    Write-Host "修复后重新运行本脚本即可（支持断点续跑）。"
    Write-Host ""
    Pause
    exit 1
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════════╗"
Write-Host "║  部署完成！还需手动完成以下 3 步：            ║"
Write-Host "╚══════════════════════════════════════════════╝"
Write-Host ""
Write-Host "第 1 步：关闭 Android 对 Termux 的省电限制"
Write-Host '  设置 -> 应用 -> 应用管理 -> Termux'
Write-Host '  -> 耗电/电量 -> 后台耗电管理'
Write-Host '  -> 改为 允许后台运行'
Write-Host "  （不关的话 Android 可能随时杀掉 bot）"
Write-Host ""
Write-Host "第 2 步：在微信里给 bot 发一条消息测试"
Write-Host "  第一条回复 5-30 秒，后续 3-10 秒"
Write-Host ""
Write-Host "第 3 步：配置 admin OpenID（人格切换等功能需要）"
Write-Host "  微信给 bot 发一条消息（任意内容）"
Write-Host "  然后手机 Termux 里: bash ~/pocket-wechat-bot/scripts/fix-openid.sh"
Write-Host "  （脚本会自动从日志提取 OpenID 并填入，无需手动编辑）"
Write-Host ""
Write-Host "管理面板：http://127.0.0.1:9820"
Write-Host "查看日志：cat ~/cc-connect/bot-debug.log"
Write-Host "重新部署：再次右键运行本脚本"
Write-Host ""
Pause
