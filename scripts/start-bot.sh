#!/data/data/com.termux/files/usr/bin/bash

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
      -b $HOME/proot-fs/etc/resolv.conf:/etc/resolv.conf \
      -b $HOME/proot-fs/etc/ssl:/etc/ssl \
      -b /data/data/com.termux/files/usr:/usr \
      -b $HOME:/home \
      -b /apex/com.android.runtime:/apex/com.android.runtime \
      -b /dev:/dev \
      -b /proc:/proc \
      /usr/bin/env PATH=/usr/bin:/usr/local/bin:/home/bin \
      $HOME/bin/cc-connect --config "$CONFIG" --force 2>/dev/null
    rm -f "$LOCK"
    sleep 1
fi

echo "[*] 启动中..."

SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem \
proot \
  -b $HOME/proot-fs/etc/resolv.conf:/etc/resolv.conf \
  -b $HOME/proot-fs/etc/ssl:/etc/ssl \
  -b /data/data/com.termux/files/usr:/usr \
  -b $HOME:/home \
  -b /apex/com.android.runtime:/apex/com.android.runtime \
  -b /dev:/dev \
  -b /proc:/proc \
  /usr/bin/env PATH=/usr/bin:/usr/local/bin:/home/bin \
  $HOME/bin/cc-connect --config "$CONFIG" &

sleep 2
echo "[*] 管理面板: http://127.0.0.1:9820"
echo "[*] 已启动~"
