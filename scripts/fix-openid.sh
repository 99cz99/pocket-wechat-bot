#!/data/data/com.termux/files/usr/bin/bash
# fix-openid.sh — 从 cc-connect 日志自动提取 OpenID 并填入 CLAUDE.md
# 用法: 部署完成后给 bot 发一条微信消息，然后跑此脚本

LOG_FILE="$HOME/cc-connect/cc-connect.log"
CLAUDE_MD="$HOME/cc-connect/CLAUDE.md"

if [ ! -f "$LOG_FILE" ]; then
    echo "[!] 日志文件不存在: $LOG_FILE"
    echo "    请先启动 bot: bash ~/start-nene.sh"
    exit 1
fi

if [ ! -f "$CLAUDE_MD" ]; then
    echo "[!] CLAUDE.md 不存在: $CLAUDE_MD"
    exit 1
fi

if ! grep -q "<YOUR_WECHAT_OPENID>" "$CLAUDE_MD" 2>/dev/null; then
    echo "[*] CLAUDE.md 中无未替换的 OpenID 占位符（可能已配置）"
    exit 0
fi

# 从 cc-connect 日志提取 OpenID（格式: user=xxx@im.wechat）
OPENID=$(grep -oP 'user=\K[^@ ]*@im\.wechat' "$LOG_FILE" | head -1)

if [ -z "$OPENID" ]; then
    echo "[!] 日志中未检测到用户消息"
    echo "    请先在微信里给 bot 发一条消息，再运行此脚本"
    exit 1
fi

sed -i "s/<YOUR_WECHAT_OPENID>/$OPENID/g" "$CLAUDE_MD"
echo "[OK] OpenID 已自动填入: $OPENID"
echo "    文件: $CLAUDE_MD"
