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
if [ -z "${REPO_DIR:-}" ]; then
    REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
fi
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
# 重复文件 / 旧路径检测 & 清理
# ============================================================
cleanup_duplicates() {
    section "重复文件/旧路径检测"

    local cleaned=0
    local issues=0

    # 1. 检测重复的 affinity 文件（旧名 affinity.json + 新名 affinity-*.json）
    local aff_count
    aff_count=$(find "$HOME" \( -name "affinity.json" -o -name "affinity-*.json" \) -type f 2>/dev/null | wc -l)
    if [ "$aff_count" -gt 1 ]; then
        warn "发现 $aff_count 个 affinity 文件（仅在 cc-connect/references/ 下保留）："
        find "$HOME" \( -name "affinity.json" -o -name "affinity-*.json" \) -type f 2>/dev/null | while read -r f; do
            echo "    $f"
        done
        # 保留 cc-connect/references/ 下的，删除其余
        find "$HOME" -path "*/cc-connect/references/affinity*" -prune -o \( -name "affinity.json" -o -name "affinity-*.json" \) -type f -print | while read -r f; do
            info "  删除多余: $f"
            rm -f "$f"
            cleaned=$((cleaned+1))
        done
        issues=$((issues+1))
    else
        ok "affinity 文件（$aff_count 个）"
    fi

    # 2. 检测 .claude/skills 残留
    if [ -d "$HOME/.claude/skills" ]; then
        warn "发现旧路径残留: ~/.claude/skills/"
        rm -rf "$HOME/.claude/skills" 2>/dev/null
        rmdir "$HOME/.claude" 2>/dev/null || true
        ok "已清理 ~/.claude/skills/（旧路径，不再使用）"
        cleaned=$((cleaned+1))
        issues=$((issues+1))
    else
        ok "无 .claude/skills 残留"
    fi

    # 3. 检测多余的 skills 复制（非 repo 源也非 ~/skills/）
    local skills_dirs
    skills_dirs=$(find "$HOME" -maxdepth 3 -path "*/skills/nene" -type d 2>/dev/null | grep -v "pocket-wechat-bot")
    local skills_count
    skills_count=$(echo "$skills_dirs" | grep -c nene 2>/dev/null || true)
    if [ "$skills_count" -gt 1 ]; then
        warn "发现多个 skills/nene/ 目录（应有 2 个：repo 源 + 运行时）："
        echo "$skills_dirs" | while read -r d; do
            echo "    $d"
        done
        # 保留 ~/skills/nene/，删除其余非 repo 副本
        echo "$skills_dirs" | grep -v "^$HOME/skills" | grep -v "pocket-wechat-bot" | while read -r d; do
            info "  删除多余: $d"
            rm -rf "$d"
            cleaned=$((cleaned+1))
        done
        issues=$((issues+1))
    else
        ok "skills/nene/ 目录（$skills_count 个副本）"
    fi

    # 4. 校验关键路径存在
    local path_ok=1
    check_path() {
        if [ ! -e "$1" ] && [ ! -d "$(dirname "$1")" ]; then
            warn "缺失: $1"
            path_ok=0
        fi
    }
    # 仅检查已部署后的路径，避免首次部署误报
    if [ -f "$STATE_FILE" ]; then
        check_path "$HOME/cc-connect/CLAUDE.md"
        check_path "$HOME/cc-connect/references"
        check_path "$HOME/skills/nene/SKILL.md"
        check_path "$HOME/bin/claude-fast.js"
        check_path "$TERMUX_USR/bin/claude"
        check_path "$HOME/.cc-connect/config.toml"
        if [ "$path_ok" -eq 1 ]; then
            ok "所有关键路径存在"
        else
            issues=$((issues+1))
        fi
    fi

    if [ "$issues" -eq 0 ]; then
        ok "路径检测通过，无异常"
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

    # 优先从 PC 推送的路径加载
    # deploy.ps1 会通过 run-as 将二进制复制到 $HOME/（/sdcard/ 在 run-as 下不可访问）
    local pc_pushed_home="$HOME/cc-connect-linux-arm64"
    local pc_pushed_sdcard="/sdcard/Download/cc-connect-linux-arm64"
    local pushed=""
    if [ -f "$pc_pushed_home" ]; then
        pushed="$pc_pushed_home"
        info "检测到 PC 已推送 cc-connect（HOME），直接安装..."
    elif [ -f "$pc_pushed_sdcard" ]; then
        pushed="$pc_pushed_sdcard"
        info "检测到 PC 已推送 cc-connect（SD），直接安装..."
    fi
    if [ -n "$pushed" ]; then
        cp "$pushed" "$HOME/bin/cc-connect"
        chmod +x "$HOME/bin/cc-connect"
		rm -f "$pc_pushed_home"  # 安装后清理临时文件
    elif [ "$NONINTERACTIVE" != "1" ]; then
        # 交互模式：手机直接下载（需要能访问 GitHub）
        info "从 GitHub Releases 下载..."
        curl -L --connect-timeout 15 --max-time 120 --retry 2 --retry-delay 5 \
            "https://github.com/chenhg5/cc-connect/releases/latest/download/cc-connect-linux-arm64" \
            -o "$HOME/bin/cc-connect" 2>/dev/null || true
        if [ -s "$HOME/bin/cc-connect" ]; then
            chmod +x "$HOME/bin/cc-connect"
        fi
    fi

    if [ -x "$HOME/bin/cc-connect" ] && "$HOME/bin/cc-connect" --version 2>/dev/null; then
        mark_done "cc_connect_binary"
        ok "cc-connect 安装完成"
    elif [ "$NONINTERACTIVE" = "1" ]; then
        err "PC 未推送 cc-connect 或推送失败，请检查 adb 连接后重新运行 deploy.bat"
    else
        err "cc-connect 下载失败，请检查网络（手机需能访问 GitHub）"
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
    # 同时写入 proot-fs 供 GODEBUG=netdns=go 使用
    mkdir -p "$HOME/proot-fs/etc"
    cp "$resolv" "$HOME/proot-fs/etc/resolv.conf" 2>/dev/null || true

    mark_done "proot_env"
    ok "proot 环境配置完成"
}

# ============================================================
# Step 4: 部署 claude-fast.js
# ============================================================
step_claude_fast() {
    section "Step 4: 部署 claude-fast.js"

    # 用 md5 判断是否需要更新
    local js_src="$REPO_DIR/claude-fast.js"
    local js_dst="$HOME/bin/claude-fast.js"
    local js_unchanged=false
    if [ -f "$js_src" ] && [ -f "$js_dst" ]; then
        local src_md5 dst_md5
        src_md5=$(md5sum "$js_src" | cut -d' ' -f1)
        dst_md5=$(md5sum "$js_dst" | cut -d' ' -f1)
        [ "$src_md5" = "$dst_md5" ] && js_unchanged=true
    fi

    if step_done "claude_fast_js" && [ -f "$HOME/bin/claude-fast.js" ] && $js_unchanged; then
        skip "claude-fast.js 已部署（内容一致）"
        return
    fi
    if step_done "claude_fast_js"; then
        if ! $js_unchanged; then
            warn "repo 已更新，重新部署 claude-fast.js..."
        else
            warn "状态文件记录已部署，但 claude-fast.js 缺失，重新部署..."
        fi
        sed -i '/claude_fast_js/d' "$STATE_FILE" 2>/dev/null || true
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

    if step_done "claude_wrapper" && [ -x "$TERMUX_USR/bin/claude" ] \
       && grep -q "# cc-wrapper-v3" "$TERMUX_USR/bin/claude" 2>/dev/null; then
        skip "claude 包装器已创建（版本一致）"
        return
    fi
    if step_done "claude_wrapper"; then
        if [ -x "$TERMUX_USR/bin/claude" ] && ! grep -q "# cc-wrapper-v3" "$TERMUX_USR/bin/claude" 2>/dev/null; then
            warn "repo 已更新（包装器模板版本升级），重新创建..."
        else
            warn "状态文件记录已部署，但 claude 包装器缺失，重新创建..."
        fi
        sed -i '/claude_wrapper/d' "$STATE_FILE" 2>/dev/null || true
    fi

    local wrapper="$TERMUX_USR/bin/claude"

    cat > "$wrapper" << 'WRAPPER_EOF'
#!/data/data/com.termux/files/usr/bin/sh
exec /usr/bin/node /home/bin/claude-fast.js "$@"
# cc-wrapper-v3
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

    # 检测 CLAUDE.md 是否变更（归一化 OpenID 后再比 md5，避免 fix-openid 干扰）
    local claude_unchanged=false
    if [ -f "$REPO_DIR/CLAUDE.md" ] && [ -f "$HOME/cc-connect/CLAUDE.md" ]; then
        local repo_claude_md5 run_claude_md5
        repo_claude_md5=$(md5sum "$REPO_DIR/CLAUDE.md" | cut -d' ' -f1)
        # 将运行时 CLAUDE.md 中的真实 OpenID 替换为占位符后再比 md5
        run_claude_md5=$(sed 's/[a-zA-Z0-9_-]\+@im\.wechat/<YOUR_WECHAT_OPENID>/g' "$HOME/cc-connect/CLAUDE.md" | md5sum | cut -d' ' -f1)
        [ "$repo_claude_md5" = "$run_claude_md5" ] && claude_unchanged=true
    fi

    # 检测 skills/nene/ 目录是否变更（全目录联合 md5，而非只看 SKILL.md）
    local skills_unchanged=false
    if [ -d "$REPO_DIR/skills/nene" ] && [ -d "$HOME/skills/nene" ]; then
        local repo_skills_md5 run_skills_md5
        repo_skills_md5=$(find "$REPO_DIR/skills/nene" -type f | sort | xargs md5sum | md5sum | cut -d' ' -f1)
        run_skills_md5=$(find "$HOME/skills/nene" -type f | sort | xargs md5sum | md5sum | cut -d' ' -f1)
        [ "$repo_skills_md5" = "$run_skills_md5" ] && skills_unchanged=true
    fi

    if step_done "personality_files" && $claude_unchanged && $skills_unchanged; then
        skip "人格文件已部署（内容一致）"
        return
    fi
    if step_done "personality_files"; then
        local reasons=""
        if ! $claude_unchanged; then reasons="$reasons CLAUDE.md"; fi
        if ! $skills_unchanged; then reasons="$reasons skills/nene/"; fi
        if [ -n "$reasons" ]; then
            warn "文件已变更：$reasons，重新部署..."
        else
            warn "状态文件记录已部署，但文件缺失，重新部署..."
        fi
        sed -i '/personality_files/d' "$STATE_FILE" 2>/dev/null || true
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

    # skills/nene/ → ~/skills/nene/（AI Read 工具从此路径读取）
    # 注意：scripts/ 是 PC 侧开发工具，不部署到手机
    if [ -d "$REPO_DIR/skills/nene" ]; then
        mkdir -p "$HOME/skills/nene"
        cp -r "$REPO_DIR/skills/nene/"* "$HOME/skills/nene/"
        rm -rf "$HOME/skills/nene/scripts"
        ok "skills/nene/ → ~/skills/nene/"
        # 清理旧的多余路径（以前部署会复制多份）
        rm -rf "$HOME/.claude/skills" 2>/dev/null || true
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
        # 复查：旧版可能把带占位符的也标记为完成
        local cfg="$HOME/.cc-connect/config.toml"
        local remaining
        remaining=$(grep -c "<YOUR_" "$cfg" 2>/dev/null || true)
        if [ "${remaining:-0}" -eq 0 ]; then
            skip "config.toml 已生成（无占位符）"
            return
        fi
        warn "config.toml 已存在但有 $remaining 个占位符未填，重新生成..."
        # 清除旧标记，重新走配置流程
        sed -i '/config_toml/d' "$STATE_FILE" 2>/dev/null || true
    fi

    mkdir -p "$HOME/.cc-connect"

    local cfg="$HOME/.cc-connect/config.toml"
    local tpl="$REPO_DIR/config/config.toml.template"

    if [ ! -f "$tpl" ]; then
        if [ -f "$cfg" ]; then
            warn "找不到 config.toml.template，使用现有 config.toml"
        else
            err "找不到 config.toml.template（路径：$tpl），且 config.toml 也不存在"
        fi
    fi

    if [ -f "$tpl" ] && [ ! -f "$cfg" ]; then
        cp "$tpl" "$cfg"
    elif [ -f "$tpl" ] && [ -f "$cfg" ]; then
        info "config.toml 已存在，跳过覆盖"
    fi

    # 收集值：环境变量优先，其次从 bashrc 提取
    local api_key="${DEPLOY_API_KEY:-}"
    local openid="${DEPLOY_OPENID:-}"
    if [ -z "$api_key" ]; then
        api_key=$(grep "ANTHROPIC_API_KEY" "$HOME/.bashrc" 2>/dev/null | tail -1 | sed 's/.*=//' | tr -d '"' | tr -d "'")
        [ -n "$api_key" ] && info "从 ~/.bashrc 提取到 API Key"
    fi
    local mgmt_token=$(openssl rand -hex 16 2>/dev/null || echo "change-me-$(date +%s)")
    local bridge_token=$(openssl rand -hex 16 2>/dev/null || echo "change-me-$(date +%s)")

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
        # 不标记完成——占位符清空才算完成
    else
        mark_done "config_toml"
    fi
}

# ============================================================
# Step 8: 设置 API Key 环境变量
# ============================================================
step_apikey() {
    section "Step 8: 设置 API Key 环境变量"

    if step_done "api_key_bashrc"; then
        # 复查：旧版可能把空 key 也标记为完成
        if grep -q "ANTHROPIC_API_KEY=sk-" "$HOME/.bashrc" 2>/dev/null; then
            # 即使标记完成，也必须确保包装器注入了 API Key
            # （旧版 step_claude_wrapper 创建时没有注入 key）
            local existing_val
            existing_val=$(grep "ANTHROPIC_API_KEY" "$HOME/.bashrc" | tail -1 | sed 's/.*=//')
            if ! grep -q "ANTHROPIC_API_KEY=sk-" "$TERMUX_USR/bin/claude" 2>/dev/null; then
                info "检测到包装器缺失 API Key，正在修复..."
                cat > "$TERMUX_USR/bin/claude" << WRAPPER_EOF
#!/data/data/com.termux/files/usr/bin/sh
export ANTHROPIC_API_KEY="$existing_val"
exec /usr/bin/node /home/bin/claude-fast.js "\$@"
# cc-wrapper-v3
WRAPPER_EOF
                chmod +x "$TERMUX_USR/bin/claude"
                ok "claude 包装器已修复"
            fi
            skip "API Key 环境变量已设置"
            return
        fi
        warn "API Key 标记已完成但未找到有效 key，重新配置..."
        sed -i '/api_key_bashrc/d' "$STATE_FILE" 2>/dev/null || true
    fi

    # 从 config.toml 中提取已填入的 key
    local cfg="$HOME/.cc-connect/config.toml"
    local existing_key=""
    if [ -f "$cfg" ]; then
        existing_key=$(grep "api_key" "$cfg" | head -1 | sed 's/.*= "//;s/"//' | tr -d ' ')
    fi

    # 检查是否已在 bashrc 中且非空
    if grep -q "ANTHROPIC_API_KEY=sk-" "$HOME/.bashrc" 2>/dev/null; then
        ok "ANTHROPIC_API_KEY 已在 ~/.bashrc 中"
        # 同步更新包装器
        local wrapper="$TERMUX_USR/bin/claude"
        local existing_val
        existing_val=$(grep "ANTHROPIC_API_KEY" "$HOME/.bashrc" | tail -1 | sed 's/.*=//')
        cat > "$wrapper" << WRAPPER_EOF
#!/data/data/com.termux/files/usr/bin/sh
export ANTHROPIC_API_KEY="$existing_val"
exec /usr/bin/node /home/bin/claude-fast.js "\$@"
# cc-wrapper-v3
WRAPPER_EOF
        chmod +x "$wrapper"
        mark_done "api_key_bashrc"
        return
    fi

    local key="${DEPLOY_API_KEY:-}"
    # 非交互模式：也尝试从 config.toml 提取已填写的 key
    if [ -z "$key" ] && [ -n "$existing_key" ] && [ "$existing_key" != "<YOUR_DEEPSEEK_API_KEY>" ]; then
        key="$existing_key"
        info "从 config.toml 提取到 API Key"
    fi
    # 交互模式：提示输入
    if [ -z "$key" ] && [ "$NONINTERACTIVE" != "1" ]; then
        echo -ne "  DeepSeek API Key（sk-...）："
        read -r key
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
# cc-wrapper-v3
WRAPPER_EOF
        chmod +x "$wrapper"
        ok "包装器已注入 API Key: $wrapper"
        mark_done "api_key_bashrc"
    else
        warn "未提供 API Key，请稍后手动设置："
        echo '      echo "export ANTHROPIC_API_KEY=sk-你的key" >> ~/.bashrc'
        echo '      source ~/.bashrc'
        # 不标记完成——下次重跑会再次尝试
    fi
}

# ============================================================
# Step 9: 微信扫码获取凭据
# ============================================================
step_wechat() {
    section "Step 9: 微信扫码获取凭据"

    if step_done "wechat_setup"; then
        # 复查：确认 token 真的有值
        local cfg="$HOME/.cc-connect/config.toml"
        local token
        token=$(grep 'token = ' "$cfg" 2>/dev/null | head -1 | sed 's/.*= "//;s/"//' | tr -d ' ')
        if [ -n "$token" ] && [ "$token" != "<YOUR_BOT_TOKEN>" ]; then
            skip "微信凭据已配置"
            return
        fi
        warn "微信凭据标记已完成但 token 无效，重新获取..."
        sed -i '/wechat_setup/d' "$STATE_FILE" 2>/dev/null || true
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
        warn "未获取微信凭据，请稍后在手机 Termux 中手动执行："
        echo "     proot -b /data/local/tmp/resolv.conf:/etc/resolv.conf -b ~/proot-fs/etc/ssl:/etc/ssl -b /data/data/com.termux/files/usr:/usr -b ~/:/home /usr/bin/env PATH=/usr/bin:/usr/local/bin:/home/bin ~/bin/cc-connect weixin setup --project nene"
        echo "     扫码后 token 和 account_id 会自动填入 config.toml"
        return
    fi

    if [ ! -x "$HOME/bin/cc-connect" ]; then
        warn "cc-connect 不可用，跳过。先完成之前步骤"
        return
    fi

    echo ""
    info "即将获取微信凭据。请准备好微信扫描二维码。"

    echo ""
    info "正在获取微信凭据（请在手机上扫码）..."
    local setup_output
    setup_output=$(proot -b /data/local/tmp/resolv.conf:/etc/resolv.conf -b "$HOME/proot-fs/etc/ssl:/etc/ssl" -b /data/data/com.termux/files/usr:/usr -b "$HOME:/home" /usr/bin/env PATH=/usr/bin:/usr/local/bin:/home/bin "$HOME/bin/cc-connect" weixin setup --project nene 2>&1) || true
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
        mark_done "wechat_setup"
    elif [ -n "$token" ]; then
        sed -i "s|<YOUR_BOT_TOKEN>|$token|g" "$cfg"
        ok "token 已自动填入（account_id 未识别，需手动编辑）"
        echo "    token: $token"
        # account_id 缺失不标记完成
    else
        warn "未能自动识别凭据。请手动复制上方输出填入："
        echo "    nano $cfg"
    fi
}

# ============================================================
# Step 10: 部署启动脚本
# ============================================================
step_startup() {
    section "Step 10: 部署启动脚本"

    # 用 md5 判断是否需要更新（同 step_personality / step_claude_fast 模式）
    local startup_src="$REPO_DIR/scripts/start-bot.sh"
    local startup_dst="$HOME/start-nene.sh"
    local startup_unchanged=false
    if [ -f "$startup_src" ] && [ -f "$startup_dst" ]; then
        local src_md5 dst_md5
        src_md5=$(md5sum "$startup_src" | cut -d' ' -f1)
        dst_md5=$(md5sum "$startup_dst" | cut -d' ' -f1)
        [ "$src_md5" = "$dst_md5" ] && startup_unchanged=true
    fi

    if step_done "start_script" && [ -f "$startup_dst" ] && $startup_unchanged; then
        skip "启动脚本已部署（内容一致）"
        return
    fi
    if step_done "start_script"; then
        if ! $startup_unchanged; then
            warn "repo 已更新，重新部署启动脚本..."
        else
            warn "状态文件记录已部署，但 start-nene.sh 缺失，重新部署..."
        fi
        sed -i '/start_script/d' "$STATE_FILE" 2>/dev/null || true
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
# Step 11: 启动 bot
# ============================================================
step_launch() {
    section "Step 11: 启动 bot"

    if step_done "bot_launched"; then
        skip "bot 已启动（按部署记录）"
        if pgrep -f cc-connect >/dev/null 2>&1; then
            ok "cc-connect 正在运行"
        else
            warn "cc-connect 未运行！请重新部署或手动启动：bash ~/start-nene.sh"
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
    # 加载 API Key
    if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
        if grep -q "ANTHROPIC_API_KEY=sk-" "$HOME/.bashrc" 2>/dev/null; then
            export ANTHROPIC_API_KEY=$(grep "ANTHROPIC_API_KEY" "$HOME/.bashrc" | tail -1 | sed 's/.*=//')
        fi
    fi
    if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
        warn "未设置 ANTHROPIC_API_KEY，无法启动。请先设置 API Key 再重试"
        return
    fi

    # 后台启动
    local log_file="$HOME/cc-connect/cc-connect.log"
    info "正在后台启动 cc-connect..."
    bash "$HOME/start-nene.sh" > "$log_file" 2>&1 &
    sleep 3
    if pgrep -f cc-connect >/dev/null 2>&1; then
        ok "cc-connect 已在后台启动"
        ok "日志: $log_file"
        mark_done "bot_launched"
    else
        err "bot 启动失败，查看日志：cat $log_file"
    fi

    echo ""
    echo "  ──────────────────────────────"
    echo "  提示：日常重启 bot 请执行："
    echo "    pkill -f cc-connect"
    echo "    rm -f ~/.cc-connect/.config.toml.lock"
    echo "    bash ~/start-nene.sh"
    echo "  ──────────────────────────────"
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
        "skills:$([ -d "$HOME/skills/nene" ] && echo OK || echo MISSING)"
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
# 动态待办清单（部署完成后检查缺什么，打印精确修复命令）
# ============================================================
print_todo() {
    local cfg="$HOME/.cc-connect/config.toml"
    local claude_md="$HOME/cc-connect/CLAUDE.md"
    local bashrc="$HOME/.bashrc"
    local todo=0

    echo "╔══════════════════════════════════════════════╗"
    echo "║  部署后检查                                 ║"
    echo "╚══════════════════════════════════════════════╝"
    echo ""

    # 1. API Key
    if grep -q "ANTHROPIC_API_KEY=sk-" "$bashrc" 2>/dev/null; then
        ok "API Key          已设置"
    else
        warn "API Key          未设置"
        echo "   修复: echo 'export ANTHROPIC_API_KEY=sk-你的key' >> ~/.bashrc && source ~/.bashrc"
        todo=$((todo + 1))
    fi

    # 2. config.toml 占位符
    if [ -f "$cfg" ]; then
        local remaining
        remaining=$(grep -c "<YOUR_" "$cfg" 2>/dev/null || true)
        if [ "${remaining:-0}" -gt 0 ]; then
            warn "config.toml      还有 $remaining 个占位符"
            grep "<YOUR_" "$cfg" | sed 's/^/      /'
            echo "   修复: nano ~/.cc-connect/config.toml"
            todo=$((todo + 1))
        else
            ok "config.toml      已填写完整"
        fi
    else
        warn "config.toml      不存在"
        echo "   修复: cp ~/pocket-wechat-bot/config/config.toml.template ~/.cc-connect/config.toml && nano ~/.cc-connect/config.toml"
        todo=$((todo + 1))
    fi

    # 3. CLAUDE.md OpenID
    if [ -f "$claude_md" ]; then
        if grep -q "<YOUR_WECHAT_OPENID>" "$claude_md" 2>/dev/null; then
            warn "CLAUDE.md        OpenID 占位符未替换"
            echo "   修复: 微信给 bot 发一条消息，然后运行："
            echo "         bash ~/pocket-wechat-bot/scripts/fix-openid.sh"
            todo=$((todo + 1))
        else
            ok "CLAUDE.md        OpenID 已配置"
        fi
    fi

    # 4. 微信凭据（token + account_id）
    if [ -f "$cfg" ]; then
        local token account_id
        token=$(grep 'token = ' "$cfg" | head -1 | sed 's/.*= "//;s/"//' | tr -d ' ')
        account_id=$(grep 'account_id = ' "$cfg" | head -1 | sed 's/.*= "//;s/"//' | tr -d ' ')
        if [ -z "$token" ] || [ "$token" = "<YOUR_BOT_TOKEN>" ] || [ -z "$account_id" ] || [ "$account_id" = "<YOUR_BOT_ACCOUNT_ID>" ]; then
            warn "微信凭据         未配置"
            echo "   修复: ~/bin/cc-connect weixin setup --project nene"
            echo "         扫码后把 token 和 account_id 填入 ~/.cc-connect/config.toml"
            todo=$((todo + 1))
        else
            ok "微信凭据         已配置"
        fi
    fi

    echo ""
    if [ "$todo" -eq 0 ]; then
        ok "全部检查通过！无需额外操作。"
        echo ""
    else
        echo "  以上 $todo 项需手动完成，完成后重跑 deploy.bat 即可自动启动"
        echo "  （已完成的步骤会自动跳过）"
        echo ""
    fi

    # 总是显示常用操作
    echo "  ─── 常用操作 ───"
    echo "  查看日志:  cat ~/cc-connect/cc-connect.log"
    echo "  前台运行:  bash ~/start-nene.sh"
    echo "  重启 bot:  pkill -f cc-connect && rm -f ~/.cc-connect/.config.toml.lock && bash ~/start-nene.sh"
    echo "  管理面板:  http://127.0.0.1:9820"
    echo "  更新项目:  cd ~/pocket-wechat-bot && git pull && cp claude-fast.js ~/bin/"
    echo ""
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
    echo ""

    preflight
    cleanup_duplicates
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

    # -------- 动态待办清单 --------
    echo ""
    print_todo
}

# 仅在直接执行时运行 main，source 时只加载函数
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
