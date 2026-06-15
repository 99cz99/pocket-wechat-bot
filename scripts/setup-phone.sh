#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# pocket-wechat-bot · 一键部署脚本（手机端）
# 在 Termux 中运行：
#   git clone https://github.com/99cz99/pocket-wechat-bot.git
#   cd pocket-wechat-bot && bash setup-phone.sh
# 或从 PC 通过 ADB 调用（deploy.bat 自动处理）
#
# 幂等设计 — 中断后可续跑，已完成步骤自动跳过
# 环境变量跳过交互：DEPLOY_API_KEY / DEPLOY_OPENID / DEPLOY_NONINTERACTIVE
# ============================================================
set -uo pipefail
# 注意：不用 set -e，因为 grep/pgrep 在"未找到"时返回非零是正常行为
# 需要显式退出的地方使用 err() 函数

# 确保 Termux 二进制在 PATH 中（run-as 环境不加载 .bashrc）
export PATH="/data/data/com.termux/files/usr/bin:/data/data/com.termux/files/usr/bin/applets:$PATH"

# ---- 颜色 ----
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
skip() { echo -e "${CYAN}[SKIP]${NC} $1"; }
info() { echo -e "${YELLOW}[..]${NC} $1"; }
warn() { echo -e "${RED}[!!]${NC} $1"; }
err()  { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
pause_msg() { echo -e "\n${BOLD}>>> $1${NC}\n"; }
section() { echo -e "\n${BOLD}═══ $1 ═══${NC}"; }

# ---- 路径常量 ----
STATE_FILE="$HOME/.pocket-bot-deploy-state"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TERMUX_USR="/data/data/com.termux/files/usr"
TERMUX_HOME="/data/data/com.termux/files/home"

# ---- 状态管理 ----
step_done() { grep -qxF "$1" "$STATE_FILE" 2>/dev/null; }
# 返回 0=已完成（grep 找到），非0=未完成（grep 未找到或文件不存在）
mark_done() { echo "$1" >> "$STATE_FILE"; }

# ---- 环境变量 ----
NONINTERACTIVE="${DEPLOY_NONINTERACTIVE:-0}"

# ---- 预检 ----
preflight() {
    section "预检"

    # 确保在 Termux 中
    if ! echo "$HOME" | grep -q "com.termux"; then
        warn "这看起来不是 Termux 环境（HOME=$HOME）"
        warn "请确认你在 Termux 中运行此脚本"
    fi

    # 存储空间检查
    local avail
    avail=$(df -k "${HOME:-/data/data/com.termux/files/home}" 2>/dev/null | tail -1 | awk '{print $4}')
    [ -z "$avail" ] && avail=9999999  # df 失败则跳过检查
    if [ "${avail:-0}" -lt 512000 ] 2>/dev/null; then
        warn "剩余存储空间不足 500MB（当前 $(($avail/1024))MB），部署可能失败"
        echo "    建议先清理不需要的文件"
        if [ "$NONINTERACTIVE" = "1" ]; then
            info "非交互模式，继续..."
        else
            echo -ne "    是否继续？[y/N] "
            read -r ans
            [ "$ans" != "y" ] && [ "$ans" != "Y" ] && exit 0
        fi
    else
        ok "存储空间充足（$(($avail/1024))MB）"
    fi

    # 检查 Termux:API
    if ! command -v termux-wake-lock >/dev/null 2>&1; then
        warn "未检测到 Termux:API（termux-wake-lock 不可用）"
        warn "Android 可能会杀后台进程！"
        echo "    请在 F-Droid 搜索安装 Termux:API"
        echo "    https://f-droid.org/packages/com.termux.api/"
    else
        ok "Termux:API 已安装"
    fi
}

# ============================================================
# Step 1: 安装依赖包
# ============================================================
step_pkg() {
    section "Step 1: 安装依赖包"

    if step_done "pkg_deps"; then
        skip "依赖包已安装"
        return
    fi

    info "更新包列表..."
    pkg update -y

    info "安装依赖（nodejs git curl proot termux-api ca-certificates tmux bash nano procps openssl-tool）..."
    pkg install nodejs git curl proot termux-api ca-certificates tmux bash nano procps openssl-tool -y

    # 验证关键依赖
    node --version && ok "node $(node --version)"
    git --version  && ok "git $(git --version | awk '{print $NF}')"
    which proot    && ok "proot: $(which proot)"
    which tmux     && ok "tmux: $(which tmux)"

    mark_done "pkg_deps"
    ok "依赖包安装完成"
}

# ============================================================
# Step 2: 下载 cc-connect 二进制
# ============================================================
step_cc_connect() {
    section "Step 2: 下载 cc-connect"

    if step_done "cc_connect_binary"; then
        skip "cc-connect 已安装"
        if [ -x "$HOME/bin/cc-connect" ]; then
            "$HOME/bin/cc-connect" --version 2>/dev/null || true
        fi
        return
    fi

    mkdir -p "$HOME/bin"

    # 如果已存在且可执行，跳过下载
    if [ -x "$HOME/bin/cc-connect" ]; then
        ok "cc-connect 已存在，验证版本..."
        "$HOME/bin/cc-connect" --version 2>/dev/null && mark_done "cc_connect_binary" && return
        info "现有 cc-connect 无法执行，重新下载..."
    fi

    info "从 GitHub Releases 下载..."
    curl -L --retry 3 --retry-delay 3 \
        "https://github.com/chenhg5/cc-connect/releases/latest/download/cc-connect-linux-arm64" \
        -o "$HOME/bin/cc-connect"

    chmod +x "$HOME/bin/cc-connect"

    if "$HOME/bin/cc-connect" --version 2>/dev/null; then
        mark_done "cc_connect_binary"
        ok "cc-connect 安装完成"
    else
        err "cc-connect 安装后无法执行，请检查网络或手动下载"
    fi
}

# ============================================================
# Step 3: proot 环境（SSL 证书 + DNS）
# ============================================================
step_proot() {
    section "Step 3: proot 环境"

    if step_done "proot_env"; then
        skip "proot 环境已配置"
        return
    fi

    # SSL 证书
    info "复制 SSL 证书..."
    mkdir -p "$HOME/proot-fs/etc/ssl"
    if [ -d "$TERMUX_USR/etc/tls" ] && [ -n "$(ls -A "$TERMUX_USR/etc/tls" 2>/dev/null)" ]; then
        cp -r "$TERMUX_USR/etc/tls/"* "$HOME/proot-fs/etc/ssl/"
        ok "SSL 证书已复制"
    else
        warn "Termux TLS 目录为空，确保已安装 ca-certificates"
        pkg install ca-certificates -y
        cp -r "$TERMUX_USR/etc/tls/"* "$HOME/proot-fs/etc/ssl/" 2>/dev/null || true
    fi

    # DNS（start-bot.sh 会自动处理，这里预创建避免首次启动失败）
    local resolv="/data/local/tmp/resolv.conf"
    if [ ! -s "$resolv" ]; then
        info "写入 DNS 配置..."
        echo "nameserver 114.114.114.114" > "$resolv" 2>/dev/null || {
            warn "无法写入 $resolv（Android 11+ 权限限制）"
            warn "start-bot.sh 启动时会自动尝试写入"
        }
        echo "nameserver 223.5.5.5" >> "$resolv" 2>/dev/null || true
        ok "DNS 配置已写入"
    else
        ok "DNS 配置已存在"
    fi

    mark_done "proot_env"
    ok "proot 环境配置完成"
}

# ============================================================
# Step 4: 部署 claude-fast.js
# ============================================================
step_claude_fast() {
    section "Step 4: 部署 claude-fast.js"

    if step_done "claude_fast_js"; then
        skip "claude-fast.js 已部署"
        return
    fi

    local src="$REPO_DIR/claude-fast.js"
    if [ ! -f "$src" ]; then
        err "找不到 claude-fast.js（路径：$src）"
    fi

    mkdir -p "$HOME/bin"
    cp "$src" "$HOME/bin/claude-fast.js"
    chmod +x "$HOME/bin/claude-fast.js"

    # 语法检查
    if node -c "$HOME/bin/claude-fast.js" 2>/dev/null; then
        ok "语法检查通过"
    else
        warn "claude-fast.js 语法检查未通过（可能不影响运行）"
    fi

    mark_done "claude_fast_js"
    ok "claude-fast.js 部署完成"
}

# ============================================================
# Step 5: 创建 /usr/bin/claude 包装器
# ============================================================
step_claude_wrapper() {
    section "Step 5: 创建 /usr/bin/claude 包装器"

    if step_done "claude_wrapper"; then
        skip "claude 包装器已创建"
        return
    fi

    local wrapper="$TERMUX_USR/bin/claude"

    cat > "$wrapper" << 'WRAPPER_EOF'
#!/data/data/com.termux/files/usr/bin/sh
exec /usr/bin/node /home/bin/claude-fast.js "$@"
WRAPPER_EOF
    chmod +x "$wrapper"

    # 验证
    if [ -x "$wrapper" ]; then
        ok "包装器已创建: $wrapper"
        head -2 "$wrapper"
    else
        err "包装器创建失败"
    fi

    mark_done "claude_wrapper"
}

# ============================================================
# Step 6: 部署人格文件
# ============================================================
step_personality() {
    section "Step 6: 部署人格文件"

    if step_done "personality_files"; then
        skip "人格文件已部署"
        return
    fi

    # 工作目录
    mkdir -p "$HOME/cc-connect"

    # CLAUDE.md
    if [ -f "$REPO_DIR/CLAUDE.md" ]; then
        cp "$REPO_DIR/CLAUDE.md" "$HOME/cc-connect/CLAUDE.md"
        ok "CLAUDE.md → ~/cc-connect/CLAUDE.md"
    else
        err "找不到 CLAUDE.md（路径：$REPO_DIR/CLAUDE.md）"
    fi

    # skills/nene/ → 两个位置都部署（兼容 claude-fast.js 硬编码路径和 CLAUDE.md 相对路径）
    if [ -d "$REPO_DIR/skills/nene" ]; then
        mkdir -p "$HOME/.claude/skills/nene" "$HOME/skills/nene"
        cp -r "$REPO_DIR/skills/nene/"* "$HOME/.claude/skills/nene/"
        cp -r "$REPO_DIR/skills/nene/"* "$HOME/skills/nene/"
        ok "skills/nene/ → ~/.claude/skills/nene/ & ~/skills/nene/"
    else
        warn "找不到 skills/nene/ 目录，人格文件未部署"
    fi

    # 提示替换 OpenID
    if grep -q "<YOUR_WECHAT_OPENID>" "$HOME/cc-connect/CLAUDE.md" 2>/dev/null; then
        warn "CLAUDE.md 仍含占位符 <YOUR_WECHAT_OPENID>"
        echo "    bot 启动后，在微信里发 /whoami 获取你的 OpenID"
        echo "    然后用 nano ~/cc-connect/CLAUDE.md 替换占位符"
    fi

    mark_done "personality_files"
    ok "人格文件部署完成"
}

# ============================================================
# Step 7: 生成 config.toml
# ============================================================
step_config() {
    section "Step 7: 配置 config.toml"

    if step_done "config_toml"; then
        skip "config.toml 已生成"
        return
    fi

    mkdir -p "$HOME/.cc-connect"

    local cfg="$HOME/.cc-connect/config.toml"
    local tpl="$REPO_DIR/config/config.toml.template"

    if [ ! -f "$tpl" ]; then
        err "找不到 config.toml.template（路径：$tpl）"
    fi

    if [ -f "$cfg" ]; then
        info "config.toml 已存在，跳过覆盖"
    else
        cp "$tpl" "$cfg"
    fi

    # 收集需要填入的值
    local api_key="${DEPLOY_API_KEY:-}"
    local openid="${DEPLOY_OPENID:-}"
    local mgmt_token=""
    local bridge_token=""

    if [ "$NONINTERACTIVE" = "1" ]; then
        info "非交互模式：使用环境变量 DEPLOY_API_KEY 和 DEPLOY_OPENID"
        if [ -z "$api_key" ]; then
            warn "未设置 DEPLOY_API_KEY，config.toml 需要手动编辑"
        fi
        mgmt_token=$(openssl rand -hex 16 2>/dev/null || echo "change-me-$(date +%s)")
        bridge_token=$(openssl rand -hex 16 2>/dev/null || echo "change-me-$(date +%s)")
    else
        echo ""
        echo "  接下来需要填入配置信息。按 Enter 跳过则该项保持占位符（稍后可手动编辑）"
        echo ""

        echo -ne "  DeepSeek API Key（sk-...）："
        read -r api_key

        echo -ne "  微信 OpenID（发 /whoami 获取，可先留空填 *）："
        read -r openid

        mgmt_token=$(openssl rand -hex 16 2>/dev/null || echo "change-me-$(date +%s)")
        bridge_token=$(openssl rand -hex 16 2>/dev/null || echo "change-me-$(date +%s)")
    fi

    # 替换占位符
    [ -n "$api_key" ] && sed -i "s|<YOUR_DEEPSEEK_API_KEY>|$api_key|g" "$cfg"
    [ -n "$openid" ]  && sed -i "s|<YOUR_WECHAT_OPENID>|$openid|g" "$cfg"

    # 随机生成管理令牌
    sed -i "s|<YOUR_MGMT_TOKEN>|$mgmt_token|g" "$cfg"
    sed -i "s|<YOUR_BRIDGE_TOKEN>|$bridge_token|g" "$cfg"

    ok "config.toml 已生成: $cfg"

    # 展示未填的占位符
    local remaining
    remaining=$(grep -c "<YOUR_" "$cfg" 2>/dev/null || true)
    if [ "${remaining:-0}" -gt 0 ]; then
        warn "还有 $remaining 个占位符需手动填写："
        grep "<YOUR_" "$cfg" | sed 's/^/      /'
        echo "    编辑: nano $cfg"
    fi

    mark_done "config_toml"
}

# ============================================================
# Step 8: 设置 API Key 环境变量
# ============================================================
step_apikey() {
    section "Step 8: 设置 API Key 环境变量"

    if step_done "api_key_bashrc"; then
        skip "API Key 环境变量已设置"
        return
    fi

    # 从 config.toml 中提取已填入的 key
    local cfg="$HOME/.cc-connect/config.toml"
    local existing_key=""
    if [ -f "$cfg" ]; then
        existing_key=$(grep "api_key" "$cfg" | head -1 | sed 's/.*= "//;s/"//' | tr -d ' ')
    fi

    # 检查是否已在 bashrc 中
    if grep -q "ANTHROPIC_API_KEY" "$HOME/.bashrc" 2>/dev/null; then
        ok "ANTHROPIC_API_KEY 已在 ~/.bashrc 中"
        mark_done "api_key_bashrc"
        return
    fi

    local key="${DEPLOY_API_KEY:-}"
    if [ -z "$key" ] && [ "$NONINTERACTIVE" != "1" ]; then
        if [ -n "$existing_key" ] && [ "$existing_key" != "<YOUR_DEEPSEEK_API_KEY>" ]; then
            info "检测到 config.toml 中已有 API Key，使用该值"
            key="$existing_key"
        else
            echo -ne "  DeepSeek API Key（sk-...）："
            read -r key
        fi
    fi

    if [ -n "$key" ]; then
        # 写入 bashrc（HISTCONTROL=ignorespace 避免进 bash history）
        echo "export ANTHROPIC_API_KEY=$key" >> "$HOME/.bashrc"
        export ANTHROPIC_API_KEY="$key"
        ok "API Key 已写入 ~/.bashrc"
        # 同步更新 /usr/bin/claude 包装器（cc-connect 不传递环境变量给子进程）
        local wrapper="$TERMUX_USR/bin/claude"
        cat > "$wrapper" << WRAPPER_EOF
#!/data/data/com.termux/files/usr/bin/sh
export ANTHROPIC_API_KEY="$key"
exec /usr/bin/node /home/bin/claude-fast.js "\$@"
WRAPPER_EOF
        chmod +x "$wrapper"
        ok "包装器已注入 API Key: $wrapper"
    else
        info "跳过（未提供 API Key），请手动添加："
        echo '      echo "export ANTHROPIC_API_KEY=sk-你的key" >> ~/.bashrc'
        echo '      source ~/.bashrc'
    fi

    mark_done "api_key_bashrc"
}

# ============================================================
# Step 9: 微信扫码获取凭据
# ============================================================
step_wechat() {
    section "Step 9: 微信扫码获取凭据"

    if step_done "wechat_setup"; then
        skip "微信凭据已配置"
        return
    fi

    # 检查 token 是否已填入
    local cfg="$HOME/.cc-connect/config.toml"
    if [ -f "$cfg" ]; then
        local token
        token=$(grep 'token = ' "$cfg" | head -1 | sed 's/.*= "//;s/"//' | tr -d ' ')
        if [ -n "$token" ] && [ "$token" != "<YOUR_BOT_TOKEN>" ]; then
            ok "微信 token 已配置，跳过扫码"
            mark_done "wechat_setup"
            return
        fi
    fi

    if [ "$NONINTERACTIVE" = "1" ]; then
        warn "非交互模式：无法扫码，请稍后手动执行："
        echo "     ~/bin/cc-connect weixin setup --project nene"
        return
    fi

    if [ ! -x "$HOME/bin/cc-connect" ]; then
        warn "cc-connect 不可用，跳过。先完成之前步骤"
        return
    fi

    echo ""
    pause_msg "即将弹出微信扫码二维码。扫码后凭据会自动填入 config.toml。"
    echo "请准备好微信扫描。"
    echo -ne "准备好了？[Y/n] "
    read -r ans
    [ "$ans" = "n" ] || [ "$ans" = "N" ] && { info "跳过，稍后手动执行：~/bin/cc-connect weixin setup --project nene"; return; }

    echo ""
    info "正在获取微信凭据（请在手机上扫码）..."
    local setup_output
    setup_output=$("$HOME/bin/cc-connect" weixin setup --project nene 2>&1) || true
    echo "$setup_output"

    # 自动解析 token 和 account_id
    local token account_id
    token=$(echo "$setup_output" | grep -oE 'wx_[a-zA-Z0-9_-]+' | head -1)
    [ -z "$token" ] && token=$(echo "$setup_output" | grep -oE 'token[=: ]+["\047]?[a-zA-Z0-9_-]+' | grep -oE '[a-zA-Z0-9_-]+$' | head -1)
    account_id=$(echo "$setup_output" | grep -oE '[a-zA-Z0-9_-]+@im\.wechat' | head -1)

    if [ -n "$token" ] && [ -n "$account_id" ]; then
        sed -i "s|<YOUR_BOT_TOKEN>|$token|g" "$cfg"
        sed -i "s|<YOUR_BOT_ACCOUNT_ID>|$account_id|g" "$cfg"
        ok "token 和 account_id 已自动填入 config.toml"
        echo "    token:      $token"
        echo "    account_id: $account_id"
    elif [ -n "$token" ]; then
        sed -i "s|<YOUR_BOT_TOKEN>|$token|g" "$cfg"
        ok "token 已自动填入（account_id 未识别，需手动编辑）"
        echo "    token: $token"
    else
        warn "未能自动识别凭据。请手动复制上方输出填入："
        echo "    nano $cfg"
    fi

    mark_done "wechat_setup"
}

# ============================================================
# Step 10: 部署启动脚本
# ============================================================
step_startup() {
    section "Step 10: 部署启动脚本"

    if step_done "start_script"; then
        skip "启动脚本已部署"
        return
    fi

    if [ -f "$REPO_DIR/scripts/start-bot.sh" ]; then
        cp "$REPO_DIR/scripts/start-bot.sh" "$HOME/start-nene.sh"
        chmod +x "$HOME/start-nene.sh"
    else
        warn "找不到 scripts/start-bot.sh，将在下一步自动生成"

        # 兜底：生成最小启动脚本
        cat > "$HOME/start-nene.sh" << 'STARTUP_EOF'
#!/data/data/com.termux/files/usr/bin/bash
export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:?请先设置 ANTHROPIC_API_KEY}"
SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem
exec proot \
  -b /data/local/tmp/resolv.conf:/etc/resolv.conf \
  -b $HOME/proot-fs/etc/ssl:/etc/ssl \
  -b /data/data/com.termux/files/usr:/usr \
  -b $HOME:/home \
  -b /apex/com.android.runtime:/apex/com.android.runtime \
  -b /dev:/dev \
  -b /proc:/proc \
  /usr/bin/env ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" SSL_CERT_FILE="$SSL_CERT_FILE" PATH=/usr/bin:/usr/local/bin:/home/bin \
  $HOME/bin/cc-connect --config "$HOME/.cc-connect/config.toml"
STARTUP_EOF
        chmod +x "$HOME/start-nene.sh"
    fi

    # 语法检查
    bash -n "$HOME/start-nene.sh" 2>/dev/null && ok "语法检查通过" || warn "语法检查未通过"

    mark_done "start_script"
    ok "启动脚本部署完成: ~/start-nene.sh"
}

# ============================================================
# Step 11: 启动 bot（tmux）
# ============================================================
step_launch() {
    section "Step 11: 启动 bot"

    if step_done "bot_launched"; then
        skip "bot 已启动（按部署记录）"
        # 但仍检查运行状态
        if pgrep -f cc-connect >/dev/null 2>&1; then
            ok "cc-connect 正在运行"
        else
            warn "cc-connect 未运行！可能需要重新启动"
            echo "     tmux attach -t nene 或 bash ~/start-nene.sh"
        fi
        return
    fi

    # 预检
    if [ ! -f "$HOME/.cc-connect/config.toml" ]; then
        err "config.toml 不存在，请先完成 Step 7"
    fi
    if [ ! -x "$HOME/bin/cc-connect" ]; then
        err "cc-connect 不存在，请先完成 Step 2"
    fi
    if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
        # 尝试从 bashrc 加载
        if grep -q "ANTHROPIC_API_KEY" "$HOME/.bashrc" 2>/dev/null; then
            source "$HOME/.bashrc" 2>/dev/null || true
        fi
        if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
            err "未设置 ANTHROPIC_API_KEY，请先完成 Step 8"
        fi
    fi

    if [ "$NONINTERACTIVE" = "1" ]; then
        info "非交互模式：直接后台启动（不使用 tmux）"
        local log_file="$HOME/cc-connect/cc-connect.log"
        bash "$HOME/start-nene.sh" > "$log_file" 2>&1 &
        sleep 3
        if pgrep -f cc-connect >/dev/null 2>&1; then
            ok "cc-connect 已在后台启动"
            ok "日志已保存: $log_file"
            mark_done "bot_launched"
        else
            warn "bot 启动失败，检查日志：cat $log_file"
        fi
        return
    fi

    echo ""
    pause_msg "即将在 tmux 会话中启动 bot。"

    # 检查是否已在 tmux 中
    if [ -n "${TMUX:-}" ]; then
        info "检测到已在 tmux 会话中，直接启动..."
        bash "$HOME/start-nene.sh"
        mark_done "bot_launched"
        return
    fi

    # 检查是否已有 nene 会话
    if tmux has-session -t nene 2>/dev/null; then
        info "tmux 会话 'nene' 已存在"
        echo "  重新连接: tmux attach -t nene"
        echo "  或新建:   tmux new -s nene2 && bash ~/start-nene.sh"
        mark_done "bot_launched"
        return
    fi

    echo "  创建 tmux 会话并启动..."
    tmux new -s nene "bash ~/start-nene.sh; echo ''; echo 'Bot 已停止。按 Enter 关闭...'; read -r _"

    echo ""
    info "bot 已停止（或你断开了 tmux）。"
    echo "  重新连接: tmux attach -t nene"
    echo "  重新启动: tmux new -s nene && bash ~/start-nene.sh"

    mark_done "bot_launched"
}

# ============================================================
# Step 12: 验证
# ============================================================
step_verify() {
    section "Step 12: 验证部署"

    local all_ok=true

    echo ""
    echo "  检查项                         状态"
    echo "  ─────────────────────────────────────"

    local checks=(
        "node:$(command -v node >/dev/null 2>&1 && echo OK || echo MISSING)"
        "git:$(command -v git >/dev/null 2>&1 && echo OK || echo MISSING)"
        "proot:$(command -v proot >/dev/null 2>&1 && echo OK || echo MISSING)"
        "tmux:$(command -v tmux >/dev/null 2>&1 && echo OK || echo MISSING)"
        "cc-connect:$([ -x "$HOME/bin/cc-connect" ] && echo OK || echo MISSING)"
        "claude-fast.js:$([ -f "$HOME/bin/claude-fast.js" ] && echo OK || echo MISSING)"
        "claude-wrapper:$([ -x "$TERMUX_USR/bin/claude" ] && echo OK || echo MISSING)"
        "CLAUDE.md:$([ -f "$HOME/cc-connect/CLAUDE.md" ] && echo OK || echo MISSING)"
        "config.toml:$([ -f "$HOME/.cc-connect/config.toml" ] && echo OK || echo MISSING)"
        "skills:$([ -d "$HOME/.claude/skills/nene" ] && echo OK || echo MISSING)"
        "API Key:$([ -n "${ANTHROPIC_API_KEY:-}" ] && echo SET || echo UNSET)"
        "bot running:$(pgrep -f cc-connect >/dev/null 2>&1 && echo YES || echo NO)"
    )

    for check in "${checks[@]}"; do
        local name="${check%%:*}"
        local status="${check##*:}"
        local icon="  ✓"
        [ "$status" != "OK" ] && [ "$status" != "SET" ] && [ "$status" != "YES" ] && { icon="  ✗"; all_ok=false; }
        printf "  %s  %-28s %s\n" "$icon" "$name" "$status"
    done

    echo ""

    if $all_ok; then
        ok "全部检查通过！bot 应该已在运行。"
        echo ""
        echo "  发一条微信消息测试吧~"
        echo "  管理面板: http://127.0.0.1:9820"
    else
        warn "部分检查未通过，查看上方 ✗ 项并修复"
        echo ""
        echo "  常见修复："
        echo "  - 缺依赖:   pkg install nodejs git curl proot termux-api ca-certificates tmux -y"
        echo "  - 缺 config: nano ~/.cc-connect/config.toml"
        echo "  - 缺 API Key: echo 'export ANTHROPIC_API_KEY=sk-xxx' >> ~/.bashrc && source ~/.bashrc"
        echo "  - bot 没启动: bash ~/start-nene.sh"
    fi
}

# ============================================================
# 主流程
# ============================================================
main() {
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║  pocket-wechat-bot · 一键部署       ║${NC}"
    echo -e "${BOLD}║  Android / Termux + DeepSeek        ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo "  仓库: $REPO_DIR"
    echo "  状态: $STATE_FILE"
    echo "  模式: $([ "$NONINTERACTIVE" = "1" ] && echo '非交互' || echo '交互')"
    echo ""

    if [ "$NONINTERACTIVE" = "1" ]; then
        info "非交互模式：自动执行所有步骤，需要输入的步骤将被跳过"
    fi

    preflight
    step_pkg
    step_cc_connect
    step_proot
    step_claude_fast
    step_claude_wrapper
    step_personality
    step_config
    step_apikey
    step_wechat
    step_startup

    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║  部署完成！                         ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════╝${NC}"
    echo ""

    step_launch
    step_verify

    echo ""
    echo "  后续操作："
    echo "  ─────────"
    echo "  第1步: 微信给 bot 发一条消息（任意内容）"
    echo "         然后: bash ~/pocket-wechat-bot/scripts/fix-openid.sh"
    echo "         脚本会自动从日志提取 OpenID 并填入 CLAUDE.md"
    echo ""
    echo "  查看状态:  bash ~/start-nene.sh（前台运行）"
    echo "  重新连接:  tmux attach -t nene"
    echo "  查看日志:  cat ~/cc-connect/cc-connect.log"
    echo "  重启 bot:  pkill -f cc-connect && bash ~/start-nene.sh"
    echo "  管理面板:  http://127.0.0.1:9820"
    echo "  更新项目:  cd ~/pocket-wechat-bot && git pull"
    echo ""
}

main "$@"
