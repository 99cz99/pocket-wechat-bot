#!/data/data/com.termux/files/usr/bin/sh
unset LD_PRELOAD
exec /data/data/com.termux/files/usr/bin/proot -b /data/data/com.termux/files/home/proot-fs/lib:/lib /data/data/com.termux/files/usr/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe "$@"
