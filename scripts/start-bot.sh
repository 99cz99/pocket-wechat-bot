#!/data/data/com.termux/files/usr/bin/bash

# 检查 API Key
if [ -z "$ANTHROPIC_API_KEY" ]; then
  echo "[!] 未设置 ANTHROPIC_API_KEY 环境变量"
  echo "    请在 ~/.bashrc 中添加: export ANTHROPIC_API_KEY=sk-你的key"
  echo "    然后运行: source ~/.bashrc"
  exit 1
fi

# 检查 proot SSL 证书目录
if [ ! -d "$HOME/proot-fs/etc/ssl" ] || [ -z "$(ls -A "$HOME/proot-fs/etc/ssl" 2>/dev/null)" ]; then
    echo "[!] proot SSL 证书目录不存在或为空: $HOME/proot-fs/etc/ssl"
    echo "    请先运行: mkdir -p ~/proot-fs/etc/ssl && cp -r /data/data/com.termux/files/usr/etc/tls/* ~/proot-fs/etc/ssl/"
    echo "    如果 tls/ 目录也不存在，请安装 ca-certificates: pkg install ca-certificates -y"
    exit 1
fi

# DNS 修复：Android 不走 /etc/resolv.conf，Go 二进制需要它
# DNS 值与此仓库 scripts/termux-resolv.conf 模板保持同步；海外用户可改 8.8.8.8 / 1.1.1.1
RESOLV_CONF="/data/local/tmp/resolv.conf"
if [ ! -f "$RESOLV_CONF" ]; then
    echo "[*] 写入 DNS 配置到 $RESOLV_CONF ..."
    echo "nameserver 114.114.114.114" > "$RESOLV_CONF" 2>/dev/null || {
        echo "[!] 无法写入 $RESOLV_CONF（Android 11+ 权限限制）"
        echo "    请在 Termux 里手动执行: echo 'nameserver 114.114.114.114' > /data/local/tmp/resolv.conf"
        exit 1
    }
    echo "nameserver 223.5.5.5" >> "$RESOLV_CONF"
    # 海外用户可将以上 DNS 替换为 8.8.8.8 / 1.1.1.1
fi

# 防止 Android 杀后台
if command -v termux-wake-lock > /dev/null 2>&1; then
    termux-wake-lock 2>/dev/null
    echo "[*] wake-lock 已激活"
fi

echo ""
echo "  =============================="
echo "    nene - cc-connect 微信机器人"
echo "  =============================="
echo ""

CONFIG="$HOME/.cc-connect/config.toml"
LOCK="$HOME/.cc-connect/.config.toml.lock"

if [ -f "$LOCK" ]; then
    echo "[!] 已有实例在运行，先停止..."
    proot \
      -b /data/local/tmp/resolv.conf:/etc/resolv.conf \
      -b $HOME/proot-fs/etc/ssl:/etc/ssl \
      -b /data/data/com.termux/files/usr:/usr \
      -b $HOME:/home \
      -b /apex/com.android.runtime:/apex/com.android.runtime \
      -b /dev:/dev \
      -b /proc:/proc \
      /usr/bin/env ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" PATH=/usr/bin:/usr/local/bin:/home/bin \
      $HOME/bin/cc-connect --config "$CONFIG" --force 2>/dev/null
    if [ $? -eq 0 ]; then
        rm -f "$LOCK"
        echo "[*] 旧实例已停止"
    else
        echo "[!] 无法停止旧实例，请手动检查: pgrep -f cc-connect"
        echo "    如果旧实例已不存在，手动删除锁文件: rm -f $LOCK"
        exit 1
    fi
    sleep 1
fi

echo "[*] 启动中..."

SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem \
proot \
  -b /data/local/tmp/resolv.conf:/etc/resolv.conf \
  -b $HOME/proot-fs/etc/ssl:/etc/ssl \
  -b /data/data/com.termux/files/usr:/usr \
  -b $HOME:/home \
  -b /apex/com.android.runtime:/apex/com.android.runtime \
  -b /dev:/dev \
  -b /proc:/proc \
  /usr/bin/env ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" PATH=/usr/bin:/usr/local/bin:/home/bin \
  $HOME/bin/cc-connect --config "$CONFIG" &

sleep 2

# 健康检查
if pgrep -f cc-connect > /dev/null 2>&1; then
    echo "[*] cc-connect 进程已启动 (PID: $(pgrep -f cc-connect | head -1))"
    echo "[*] 管理面板: http://127.0.0.1:9820"
    echo "[*] 已启动~"
else
    echo "[!] 警告：cc-connect 进程未检测到！可能启动失败。"
    echo "    检查日志: cat ~/cc-connect/bot-debug.log"
    echo "    检查配置: cat ~/.cc-connect/config.toml"
    echo "    手动前台运行测试: cd ~ && SSL_CERT_FILE=... proot ... ~/bin/cc-connect --config ~/.cc-connect/config.toml"
fi
