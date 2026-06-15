#!/data/data/com.termux/files/usr/bin/bash
# fix-openid.sh — 从多个来源自动提取微信 OpenID 并填入 CLAUDE.md + config.toml
# 用法: 给 bot 发一条微信消息后跑此脚本

CLAUDE_MD="$HOME/cc-connect/CLAUDE.md"
CONFIG_TOML="$HOME/.cc-connect/config.toml"
OPENID=""

echo "[*] 正在查找你的微信 OpenID..."

# ---- 来源1: cc-connect.log（start-bot.sh 的 tee 输出） ----
if [ -f "$HOME/cc-connect/cc-connect.log" ]; then
    OPENID=$(grep -oP 'user=\K[a-zA-Z0-9_-]+@im\.wechat' "$HOME/cc-connect/cc-connect.log" 2>/dev/null | head -1)
    [ -n "$OPENID" ] && echo "[*] 从 cc-connect.log 找到"
fi

# ---- 来源2: session 文件 ----
if [ -z "$OPENID" ] && [ -d "$HOME/.cc-connect/sessions" ]; then
    for f in "$HOME/.cc-connect/sessions/"*.json; do
        [ -f "$f" ] || continue
        OPENID=$(grep -oP '[a-zA-Z0-9_-]+@im\.wechat' "$f" 2>/dev/null | head -1)
        [ -n "$OPENID" ] && { echo "[*] 从 session 文件找到"; break; }
    done
fi

# ---- 来源3: cc-connect 进程的 stdout（通过 /proc） ----
if [ -z "$OPENID" ]; then
    CC_PID=$(pgrep -f 'bin/cc-connect' 2>/dev/null | head -1)
    if [ -n "$CC_PID" ]; then
        OPENID=$(strings /proc/$CC_PID/fd/1 2>/dev/null | grep -oP 'user=[a-zA-Z0-9_-]+@im\.wechat' | head -1 | cut -d= -f2)
        [ -n "$OPENID" ] && echo "[*] 从 cc-connect 进程输出找到"
    fi
fi

# ---- 来源4: logcat（Android 系统日志） ----
if [ -z "$OPENID" ] && command -v logcat >/dev/null 2>&1; then
    OPENID=$(logcat -d 2>/dev/null | grep -oP '[a-zA-Z0-9_-]+@im\.wechat' | head -1)
    [ -n "$OPENID" ] && echo "[*] 从 logcat 找到"
fi

# ---- 所有来源都失败 ----
if [ -z "$OPENID" ]; then
    echo "[!] 未能自动提取 OpenID"
    echo ""
    echo "  请手动操作："
    echo "  1. 确保 bot 在运行:  bash ~/start-nene.sh"
    echo "  2. 给 bot 发一条微信消息"
    echo "  3. 观察终端输出中的 user=xxx@im.wechat"
    echo "  4. 运行: sed -i 's/<YOUR_WECHAT_OPENID>/你的OpenID/g' ~/cc-connect/CLAUDE.md"
    echo "  5. 运行: sed -i 's/<YOUR_WECHAT_OPENID>/你的OpenID/g' ~/.cc-connect/config.toml"
    exit 1
fi

echo ""
echo "  OpenID: $OPENID"

# ---- 填入文件 ----
changed=0

if [ -f "$CLAUDE_MD" ] && grep -q "<YOUR_WECHAT_OPENID>" "$CLAUDE_MD" 2>/dev/null; then
    sed -i "s/<YOUR_WECHAT_OPENID>/$OPENID/g" "$CLAUDE_MD"
    echo "[OK] CLAUDE.md 已更新"
    changed=1
fi

if [ -f "$CONFIG_TOML" ] && grep -q "<YOUR_WECHAT_OPENID>" "$CONFIG_TOML" 2>/dev/null; then
    sed -i "s|<YOUR_WECHAT_OPENID>|$OPENID|g" "$CONFIG_TOML"
    echo "[OK] config.toml admin_from 已更新"
    changed=1
fi

if [ $changed -eq 0 ]; then
    echo "[*] 文件无需更新（可能已配置）"
fi
