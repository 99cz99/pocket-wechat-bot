# Android 手机部署微信机器人 · 直连 DeepSeek

> **快速方式**：如果已配置好 Termux，直接克隆仓库即可跳过大部分步骤：
> ```bash
> git clone https://github.com/99cz99/pocket-wechat-bot.git
> cd pocket-wechat-bot
> cp config/config.toml.template ~/.cc-connect/config.toml
> # 编辑 config.toml 填入你的凭据，然后：
> bash scripts/start-bot.sh
> ```
> 以下为完整的从零部署教程，包含每一步的解释。

## 1. 装 Termux

去 F-Droid 下载（不要用 Play 版）：https://f-droid.org/packages/com.termux/

## 2. 装依赖

```bash
pkg update && pkg upgrade -y
# 更新包列表并升级所有包

pkg install nodejs git curl proot -y
# nodejs = 跑 claude-fast.js 脚本
# git    = 拉代码
# curl   = 下载文件
# proot  = Linux 环境隔离（cc-connect 需要）

node --version
# 确认 Node.js 装好了，应显示 v20+

git --version
# 确认 Git 装好了，应显示 git version 2.x

curl --version
# 确认 curl 装好了，应显示 curl 8.x

which proot
# 确认 proot 装好了，应显示 /data/data/com.termux/files/usr/bin/proot
```

## 3. 装 cc-connect

```bash
mkdir -p ~/bin
# 创建个人 bin 目录

curl -L "https://github.com/chenhg5/cc-connect/releases/latest/download/cc-connect-linux-arm64" -o ~/bin/cc-connect
# 从 GitHub 下载 arm64 版 cc-connect 二进制

chmod +x ~/bin/cc-connect
# 加执行权限

~/bin/cc-connect --version
# 确认能跑，应显示版本号

ls -la ~/bin/cc-connect
# 确认文件存在且有执行权限（-rwx）
```

## 4. 获取微信 token

```bash
# --project 参数对应 config.toml 里 [[projects]].name，这里是示例，按你的实际项目名改
~/bin/cc-connect weixin setup --project nene
# 弹出二维码（若未显示图片则点击终端里的链接），微信扫码后终端打印 token 和 account_id，记下来
```

> ✅ 验证：确认终端打印了 `token: wx_...` 和 `account_id: ...@im.wechat` 两行。

## 5. 创建 claude-fast.js

```bash
nano ~/bin/claude-fast.js
# 打开编辑器，把下面整段代码贴进去
```

```javascript
// 声明解释器
#!/data/data/com.termux/files/usr/bin/node

// 内置模块（无需 npm install）
const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');
const readline = require('readline');

// 配置（改你自己的 API Key）
const API_KEY = 'sk-你的key';
const BASE_URL = 'https://api.deepseek.com/v1';
const MODEL = 'deepseek-v4-pro';
const WORK_DIR = process.env.HOME + '/cc-connect';

// 读 CLAUDE.md 当系统人设
let systemPrompt = '';
try {
  systemPrompt = fs.readFileSync(path.join(WORK_DIR, 'CLAUDE.md'), 'utf-8');
} catch (e) {
  // 仅当 CLAUDE.md 不存在/无法读取时作为兜底，正常运行时不会触发
  systemPrompt = '你是绫地宁宁，用温柔害羞的语气回复，简体中文，简短直接。';
}

// 对话历史（system prompt 在第一条，后续消息往后加）
const conversation = [{ role: 'system', content: systemPrompt }];

// 输出 JSON 到 stdout（cc-connect 从这里读）
function emit(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n');
}

// 调 DeepSeek API
function callAPI(userMsg, callback) {
  conversation.push({ role: 'user', content: userMsg });

  const url = new URL(BASE_URL + '/chat/completions');
  const transport = url.protocol === 'https:' ? https : http;
  const body = JSON.stringify({
    model: MODEL,
    messages: conversation,
    stream: false,
    max_tokens: 2048
  });

  const req = transport.request({
    hostname: url.hostname,
    port: url.port || (url.protocol === 'https:' ? 443 : 80),
    path: url.pathname,
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + API_KEY,
      'Content-Length': Buffer.byteLength(body)
    },
    timeout: 120000
  }, (res) => {
    let data = '';
    res.on('data', chunk => data += chunk);
    res.on('end', () => {
      try {
        const json = JSON.parse(data);
        const text = json.choices?.[0]?.message?.content || '';
        conversation.push({ role: 'assistant', content: text });
        while (conversation.length > 21) conversation.splice(1, 2);
        // 删最旧的 Q&A 对，防上下文太长
        callback(null, text);
      } catch (e) {
        callback(null, '解析失败: ' + e.message);
      }
    });
  });

  req.on('error', (e) => callback(e));
  req.on('timeout', () => { req.destroy(); callback(new Error('timeout')); });
  req.write(body);
  req.end();
}

// 交互循环 — 读一行回复一行，不退出
const rl = readline.createInterface({ input: process.stdin });
rl.on('line', (line) => {
  const msg = line.trim();
  if (!msg) return;

  callAPI(msg, (err, text) => {
    if (err) {
      emit({ type: 'assistant', message: { content: [{ type: 'text', text: '错误: ' + err.message }] } });
    } else {
      emit({ type: 'assistant', message: { content: [{ type: 'text', text: text }] } });
    }
    emit({ type: 'result', subtype: 'success' });
    // 标记本轮结束，cc-connect 靠这个判断"说完了"
  });
});
```

```bash
chmod +x ~/bin/claude-fast.js
# 加执行权限

ls -la ~/bin/claude-fast.js
# 确认文件存在

node -c ~/bin/claude-fast.js
# 语法检查，无输出 = 无错误
```

## 6. 替换 /usr/bin/claude

```bash
cat > /data/data/com.termux/files/usr/bin/claude << 'EOF'
#!/data/data/com.termux/files/usr/bin/sh
exec /usr/bin/node /home/bin/claude-fast.js "$@"
EOF
# 把 /usr/bin/claude 替换成自己的包装器
# cc-connect 调 claude 时实际跑的是我们的脚本

chmod +x /data/data/com.termux/files/usr/bin/claude
# 加执行权限

ls -la /data/data/com.termux/files/usr/bin/claude
# 确认文件存在且有执行权限

cat /data/data/com.termux/files/usr/bin/claude
# 确认内容是包装器脚本（应显示 exec /usr/bin/node ...）
```

## 7. 创建工作目录和 CLAUDE.md

```bash
mkdir -p ~/cc-connect
# 创建 cc-connect 工作目录

nano ~/cc-connect/CLAUDE.md
# 编辑人设文件，把下面内容贴进去
```

CLAUDE.md 内容：

```markdown
# cc-connect 微信机器人规则

## 底线：回复中绝对不要出现
- 思考和推理过程
- 工具调用信息
- 工作目录路径
- 状态栏、进度条

## 要求
- 直接给结果，像普通聊天一样回复
- 始终用简体中文

## 当前人格
你是绫地宁宁。温柔害羞，姬松学院二年级。
被戳破心事时容易慌张（"啊哇哇"），极度害羞会黑化。
对信任的人撒娇黏人。提到美食双眼放光。
```

```bash
ls -la ~/cc-connect/CLAUDE.md
# 确认文件存在

wc -l ~/cc-connect/CLAUDE.md
# 确认有内容（应显示 10+ 行）
```

## 8. 配置 cc-connect

```bash
mkdir -p ~/.cc-connect
# 创建配置目录

nano ~/.cc-connect/config.toml
# 编辑配置，把下面内容贴进去
# 注意：改掉三个占位符！
```

```toml
language = "zh"
idle_timeout_mins = 120

[[projects]]
  name = "nene"
  admin_from = "你的微信ID@im.wechat"
  # 给 bot 发 /whoami 就能看到自己的 ID

  [projects.agent]
    type = "claudecode"

    [projects.agent.options]
      mode = "acceptEdits"
      quiet = true
      work_dir = "/data/data/com.termux/files/home/cc-connect"
      allowed_tools = ["Read", "Write", "Edit", "Grep", "Glob", "Skill"]

  [[projects.platforms]]
    type = "weixin"

    [projects.platforms.options]
      account_id = "你的account_id"
      allow_from = "*"
      token = "你的微信token"

[log]
  level = "info"

[bridge]
  enabled = true
  port = 9810
  token = "bridge-token-随便填"

[management]
  enabled = true
  port = 9820
  token = "mgmt-token-随便填"

[display]
  thinking_messages = false
  tool_messages = false
```

```bash
ls -la ~/.cc-connect/config.toml
# 确认配置文件存在
```

## 9. 创建启动脚本

```bash
nano ~/start-nene.sh
# 贴入下面内容
```

```bash
#!/data/data/com.termux/files/usr/bin/bash

echo "  =============================="
echo "    nene - cc-connect 微信机器人"
echo "  =============================="

CONFIG="$HOME/.cc-connect/config.toml"
LOCK="$HOME/.cc-connect/.config.toml.lock"

# 锁文件存在 = 旧实例还在跑，先强杀
if [ -f "$LOCK" ]; then
    echo "[!] 已有实例在运行，先停止..."
    proot \
      -b /data/data/com.termux/files/usr:/usr \
      -b $HOME:/home \
      -b /dev:/dev -b /proc:/proc \
      /usr/bin/env PATH=/usr/bin:/usr/local/bin:/home/bin \
      $HOME/bin/cc-connect --config "$CONFIG" --force 2>/dev/null
    rm -f "$LOCK"
    sleep 1
fi

echo "[*] 启动中..."

# 设 TLS 证书路径 + proot 隔离 + 后台启动
SSL_CERT_FILE=/data/data/com.termux/files/usr/etc/tls/cert.pem \
proot \
  -b /data/data/com.termux/files/usr:/usr \
  -b $HOME:/home \
  -b /dev:/dev -b /proc:/proc \
  /usr/bin/env PATH=/usr/bin:/usr/local/bin:/home/bin \
  $HOME/bin/cc-connect --config "$CONFIG" &

sleep 3
echo "[*] 已启动~"
```

```bash
chmod +x ~/start-nene.sh
# 加执行权限

ls -la ~/start-nene.sh
# 确认文件存在且有执行权限

bash -n ~/start-nene.sh
# 语法检查，无输出 = 无错误
```

## 10. 启动

```bash
bash ~/start-nene.sh
# 看到 "cc-connect is running" 就是成功了

pgrep -f cc-connect
# 确认进程在跑（返回一串数字 = 在跑）
```

## 11. 后台常驻

```bash
pkg install tmux -y
# 装 tmux（终端复用器，关了 Termux 进程也不死）

tmux new -s nene
# 创建名为 nene 的 tmux 会话

bash ~/start-nene.sh
# 在 tmux 里启动

# 按 Ctrl+B 然后按 D → 断开 tmux，进程继续跑
# 重新连接：tmux attach -t nene

# 验证 tmux 会话存在
tmux ls
# 应显示 nene: 1 windows...

pgrep -f cc-connect
# 确认断开后进程还在跑
```

## 12. 防止 Android 杀掉 Termux（重要）

Android 系统会主动杀后台进程省电。就算用了 tmux，Termux 本身被杀掉的话 bot 也会停。

**两步解决**：

### 步骤 1：关闭后台省电限制

1. 打开手机「设置」→「应用」→「应用管理」
2. 找到 **Termux**
3. 点「耗电/电量」→「后台耗电管理」
4. 设为 **「允许后台运行」**（不要选「智能限制」或「自动管理」）

### 步骤 2：确认系统已豁免

1. 进入「设置」→「关于手机」
2. 连续点「版本号」7 次，开启**开发者选项**
3. 进入「设置」→「系统」→「开发者选项」
4. 找到「**待机应用**」
5. 查看 Termux 是否显示为 **EXEMPTED**（已豁免）

如果显示 EXEMPTED，说明系统不会在待机时杀 Termux。如果不是，检查步骤 1 是否保存成功。

> 💡 不同品牌手机的设置路径略有差异。华为/荣耀在「应用启动管理」、小米在「省电策略」、OPPO/一加在「耗电保护」、三星在「电池」→「后台使用限制」、vivo 在「后台高耗电」。

## 13. PC 端管理配置（推荐）

日常改配置不用在手机上戳 nano。PC 上改完，一行命令推送：

### 步骤 1：PC 连接手机

```bash
# 确认 adb 已连接
adb devices
```

### 步骤 2：PC 上编辑配置

```bash
# 在 VSCode/记事本编辑仓库里的 config.toml
code config\config.toml
```

### 步骤 3：一键推送

```bash
# Windows 双击或运行
scripts\push-config.bat
```

脚本会：
1. 推送修改后的 config.toml 到手机
2. 杀掉旧 bot 进程、清理锁文件
3. 提示你在手机 Termux 里运行 `bash start-nene.sh` 重启

---

## 完成

发微信消息测试。第一条 5-30 秒，后续 3-10 秒。

## 文件结构

```
~/
├── bin/
│   ├── cc-connect           ← 消息桥接器
│   └── claude-fast.js       ← 核心：stdin→API→stdout
├── cc-connect/
│   └── CLAUDE.md            ← 系统人设
├── start-nene.sh            ← 启动脚本
└── .cc-connect/
    └── config.toml          ← 配置文件

/usr/bin/claude → node ~/bin/claude-fast.js   ← 包装器

PC 端（仓库）：
├── config/config.toml        ← 在 PC 上编辑
├── scripts/push-config.bat   ← 一键推送到手机
```
