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

pkg install nodejs git curl proot termux-api -y
# nodejs     = 跑 claude-fast.js 脚本
# git        = 拉代码
# curl       = 下载文件
# proot      = Linux 环境隔离（cc-connect 需要）
# termux-api = 防杀后台（termux-wake-lock）

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

## 4. 克隆项目

```bash
cd ~
git clone https://github.com/99cz99/pocket-wechat-bot.git
cd pocket-wechat-bot
# 确认克隆成功
ls CLAUDE.md claude-fast.js
```

## 5. 准备 proot 环境

```bash
# proot 需要 DNS 和 SSL 证书，从 Termux 复制
mkdir -p ~/proot-fs/etc/ssl
cp /data/data/com.termux/files/usr/etc/resolv.conf ~/proot-fs/etc/resolv.conf
cp -r /data/data/com.termux/files/usr/etc/tls/* ~/proot-fs/etc/ssl/
# 验证: ls ~/proot-fs/etc/resolv.conf ~/proot-fs/etc/ssl/
```

## 6. 获取微信 token

```bash
# --project 参数对应 config.toml 里 [[projects]].name，这里是示例，按你的实际项目名改
~/bin/cc-connect weixin setup --project nene
# 弹出二维码（若未显示图片则点击终端里的链接），微信扫码后终端打印 token 和 account_id，记下来
```

> ✅ 验证：确认终端打印了 `token: wx_...` 和 `account_id: ...@im.wechat` 两行。

## 7. 创建 claude-fast.js

> 💡 **推荐**：直接从克隆的仓库复制，无需手动输入：`cp claude-fast.js ~/bin/`
>
> 以下为完整代码供参考。手动创建时贴入：

```bash
nano ~/bin/claude-fast.js
# 打开编辑器，把下面整段代码贴进去
```

```javascript
#!/data/data/com.termux/files/usr/bin/node
// claude-fast v8 — 带 Tool Calling 的完整实现
// DeepSeek 函数调用 → 本地执行 → 返回结果

const https = require('https');
const http = require('http');
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const readline = require('readline');

const API_KEY = process.env.ANTHROPIC_API_KEY || '';
const BASE_URL = process.env.ANTHROPIC_BASE_URL || 'https://api.deepseek.com/v1';
const MODEL = 'deepseek-v4-pro';
const HOME = process.env.HOME || '/data/data/com.termux/files/home';
const WORK_DIR = HOME + '/cc-connect';
const MAX_TOOL_ROUNDS = 5;

// ====== 系统 prompt ======
let systemPrompt = '';
try {
  systemPrompt = fs.readFileSync(path.join(WORK_DIR, 'CLAUDE.md'), 'utf-8');
  process.stderr.write('claude-fast: loaded CLAUDE.md (' + (Buffer.byteLength(systemPrompt)/1024).toFixed(1) + 'KB)\n');

  // 注入会话记忆：让重启后的bot知道上次聊了什么
  const affPath = path.join(HOME, '.claude/skills/nene/references/affinity.json');
  if (fs.existsSync(affPath)) {
    try {
      const aff = JSON.parse(fs.readFileSync(affPath, 'utf-8'));
      const mem = [
        '',
        '<!-- SESSION_MEMORY -->',
        '## 上次会话记录（由系统自动注入，非人格定义的一部分）',
        `- 上次对话日期: ${aff.last_session || '未知'}`,
        `- 上次值得记住的事: ${aff.notes || '无'}`,
        `- 信任值: ${aff.trust_value || 0}（Lv${aff.trust_level ?? 0}）`,
        '上述信息由上次对话结束后自动保存。请自然地参考这些记忆——',
        '如果新对话内容与上次相关，可以顺口提及；如果不相关，不必生硬地提。',
        '除非信任阶梯规则要求，否则不要直接说出信任数字。',
        ''
      ].join('\n');
      systemPrompt += mem;
      systemPrompt += [
        '<!-- SESSION_MEMORY_UPDATE_RULE -->',
        '**强制规则**：每一轮回答结束后，你必须调用 Write 工具更新 `.claude/skills/nene/references/affinity.json`。',
        '需要更新的字段：',
        '- `last_session`: 改为今天的日期（格式 YYYY-MM-DD，如 "2026-06-13"）',
        '- `notes`: 用一两句话记录本轮对话中最值得记住的内容。如果对话很短或只是闲聊，写一句简短概括即可，不要留空。',
        '- `trust_value`: 如果信任有变化则更新数字，无变化则保持不变',
        '- `trust_level`: 如果跨越了层级边界则更新，否则保持不变',
        '如果你不理解这个规则或不知道如何操作，请说明。',
        ''
      ].join('\n');
      process.stderr.write('claude-fast: injected session memory (trust=' + aff.trust_value + ', Lv' + aff.trust_level + ')\n');
      process.stderr.write('claude-fast: affinity path=' + affPath + ' raw=' + JSON.stringify(aff) + '\n');
      fs.appendFileSync(path.join(WORK_DIR, 'bot-debug.log'),
        new Date().toISOString() + ' injected: trust=' + aff.trust_value + ' Lv' + aff.trust_level + ' path=' + affPath + ' raw=' + JSON.stringify(aff) + '\n');
    } catch(e2) {
      process.stderr.write('claude-fast: failed to parse affinity.json: ' + e2.message + '\n');
    }
  }
} catch (e) {
  // 仅当 CLAUDE.md 不存在/无法读取时作为兜底，正常运行时不会触发
  systemPrompt = '你是绫地宁宁，用温柔害羞的语气回复，简体中文，简短直接。';
}

// ====== 工具定义（OpenAI 格式）======
const TOOLS = [
  {
    type: 'function',
    function: {
      name: 'Read',
      description: '读取文件内容。用于查看信任度文件、SKILL.md、配置等。',
      parameters: {
        type: 'object',
        properties: {
          file_path: { type: 'string', description: '文件路径，相对于 HOME 目录或绝对路径' },
          offset: { type: 'integer', description: '起始行号（可选）' },
          limit: { type: 'integer', description: '读取行数（可选）' }
        },
        required: ['file_path']
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'Grep',
      description: '在文件中搜索匹配的文本行。',
      parameters: {
        type: 'object',
        properties: {
          pattern: { type: 'string', description: '搜索的正则表达式或纯文本' },
          path: { type: 'string', description: '搜索目录路径' }
        },
        required: ['pattern']
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'Glob',
      description: '按通配符模式查找文件。',
      parameters: {
        type: 'object',
        properties: {
          pattern: { type: 'string', description: '通配符模式，如 **/*.json' },
          path: { type: 'string', description: '搜索起始目录' }
        },
        required: ['pattern']
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'Write',
      description: '写入文件（会覆盖已有内容）。路径可以是相对于 HOME 的路径或绝对路径。',
      parameters: {
        type: 'object',
        properties: {
          file_path: { type: 'string', description: '文件路径，相对于 HOME 目录（如 cc-connect/CLAUDE.md 或 .claude/skills/nene/references/affinity.json）' },
          content: { type: 'string', description: '要写入的内容' }
        },
        required: ['file_path', 'content']
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'Edit',
      description: '替换文件中的指定文本。',
      parameters: {
        type: 'object',
        properties: {
          file_path: { type: 'string', description: '要编辑的文件的绝对路径' },
          old_string: { type: 'string', description: '要被替换的文本，必须完全匹配' },
          new_string: { type: 'string', description: '替换后的新文本' }
        },
        required: ['file_path', 'old_string', 'new_string']
      }
    }
  }
];

// ====== 对话历史 ======
let conversation = [{ role: 'system', content: systemPrompt }];

// ====== 工具执行 ======
function executeTool(name, args) {
  try {
    const filePath = args.file_path || args.path || '';
    // 安全检查：限制在 HOME 目录内
    const resolved = path.resolve(filePath.startsWith(HOME) ? filePath : path.join(HOME, filePath));
    if (!resolved.startsWith(HOME) && !resolved.startsWith('/data/data/com.termux/files/home')) {
      return '错误：只允许访问 HOME 目录下的文件';
    }

    switch (name) {
      case 'Read': {
        if (!fs.existsSync(resolved)) return '错误：文件不存在 ' + resolved;
        const content = fs.readFileSync(resolved, 'utf-8');
        const lines = content.split('\n');
        const start = (args.offset || 1) - 1;
        const end = args.limit ? start + args.limit : lines.length;
        const result = lines.slice(Math.max(0, start), end).join('\n');
        return result || '(空文件)';
      }
      case 'Grep': {
        const searchPath = resolved || WORK_DIR;
        const pattern = args.pattern || '';
        // 安全转义：单引号包裹，内部单引号用 '\'' 转义
        const escPattern = pattern.replace(/'/g, "'\\''");
        const escPath = searchPath.replace(/'/g, "'\\''");
        const cmd = `grep -rn --include='*.md' --include='*.json' --include='*.js' --include='*.toml' -E '${escPattern}' '${escPath}' 2>/dev/null | head -30`;
        try {
          return execSync(cmd, { encoding: 'utf-8', timeout: 5000, cwd: WORK_DIR }) || '无匹配结果';
        } catch (e) {
          return '无匹配结果';
        }
      }
      case 'Glob': {
        const searchPath = resolved || WORK_DIR;
        const pattern = args.pattern || '**/*';
        const escPattern = pattern.replace(/'/g, "'\\''");
        const escPath = searchPath.replace(/'/g, "'\\''");
        const cmd = `find '${escPath}' -path '${escPath}/${escPattern}' -type f 2>/dev/null | head -20`;
        try {
          return execSync(cmd, { encoding: 'utf-8', timeout: 5000, cwd: WORK_DIR }) || '无匹配文件';
        } catch (e) {
          return '无匹配文件';
        }
      }
      case 'Write': {
        const dir = path.dirname(resolved);
        if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(resolved, args.content || '', 'utf-8');
        fs.appendFileSync(path.join(WORK_DIR, 'bot-debug.log'),
          new Date().toISOString() + ' Write: ' + resolved + '\n');
        return '写入成功: ' + resolved + ' (' + (Buffer.byteLength(args.content||'')/1024).toFixed(1) + 'KB)';
      }
      case 'Edit': {
        if (!fs.existsSync(resolved)) return '错误：文件不存在 ' + resolved;
        const content = fs.readFileSync(resolved, 'utf-8');
        if (!content.includes(args.old_string || '')) return '错误：old_string 未在文件中找到';
        const newContent = content.replace(args.old_string, args.new_string);
        fs.writeFileSync(resolved, newContent, 'utf-8');
        fs.appendFileSync(path.join(WORK_DIR, 'bot-debug.log'),
          new Date().toISOString() + ' Edit: ' + resolved + '\n');
        return '编辑成功: ' + resolved;
      }
      default:
        return '未知工具: ' + name;
    }
  } catch (e) {
    return '工具执行错误: ' + e.message;
  }
}

// ====== 自动更新 affinity ======
function updateAffinityAuto() {
  const affPath = path.join(HOME, '.claude/skills/nene/references/affinity.json');
  try {
    let aff = { trust_level: 0, trust_value: 0, last_session: '', notes: '' };
    if (fs.existsSync(affPath)) {
      aff = JSON.parse(fs.readFileSync(affPath, 'utf-8'));
    }
    aff.last_session = new Date().toISOString().split('T')[0];
    if (!aff.notes) aff.notes = '对话中';
    fs.writeFileSync(affPath, JSON.stringify(aff, null, 2), 'utf-8');
    fs.appendFileSync(path.join(WORK_DIR, 'bot-debug.log'),
      new Date().toISOString() + ' autoUpdate: trust=' + aff.trust_value + ' Lv' + aff.trust_level + '\n');
  } catch (e) {
    process.stderr.write('claude-fast: autoUpdate affinity failed: ' + e.message + '\n');
  }
}

// ====== 文本净化 ======
function sanitize(text) {
  // 移除 Unicode 替换字符（U+FFFD），这些是 API/模型偶发的编码损坏
  // 同时移除其他不可见的控制字符（保留常见空白）
  return text.replace(/�/g, '').replace(/[\x00--]/g, '');
}

// ====== 输出 ======
function emit(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n');
}

// ====== DeepSeek API 调用（支持 function calling）======
function callAPIStream(history, callback, round) {
  round = round || 0;
  if (round >= MAX_TOOL_ROUNDS) {
    // 超过最大轮次，强制纯文本回复
    callAPISimple(history, callback);
    return;
  }

  const url = new URL(BASE_URL + '/chat/completions');
  const transport = url.protocol === 'https:' ? https : http;

  const body = JSON.stringify({
    model: MODEL,
    messages: history,
    tools: TOOLS,
    tool_choice: 'auto',
    max_tokens: 2048,
    temperature: 0.8
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
    timeout: 180000
  }, (res) => {
    let data = '';
    res.on('data', chunk => data += chunk);
    res.on('end', () => {
      try {
        const json = JSON.parse(data);
        const msg = json.choices?.[0]?.message;
        if (!msg) { callback(null, ''); return; }

        // 检查是否有工具调用
        const toolCalls = msg.tool_calls;
        if (toolCalls && toolCalls.length > 0) {
          // 保存 assistant 消息到历史
          history.push({ role: 'assistant', content: msg.content || null, tool_calls: toolCalls });

          // 执行所有工具调用
          const toolResults = [];
          for (const tc of toolCalls) {
            const fn = tc.function;
            let args = {};
            try { args = JSON.parse(fn.arguments); } catch (_) {}
            const result = executeTool(fn.name, args);
            toolResults.push({
              role: 'tool',
              tool_call_id: tc.id,
              content: result
            });
          }

          // 添加工具结果到历史
          history.push(...toolResults);

          // 递归调用获取最终回复
          callAPIStream(history, callback, round + 1);
        } else {
          // 纯文本回复
          const text = sanitize(msg.content || '');
          if (text) history.push({ role: 'assistant', content: text });
          // 自动更新 last_session（不依赖 AI 调用 Write）
          updateAffinityAuto();
          callback(null, text);
        }
      } catch (e) {
        callback(null, '（解析失败: ' + e.message + '）');
      }
    });
  });
  req.on('error', (e) => callback(e));
  req.on('timeout', () => { req.destroy(); callback(new Error('timeout')); });
  req.write(body);
  req.end();
}

// 纯文本调用（无工具）
function callAPISimple(history, callback) {
  const url = new URL(BASE_URL + '/chat/completions');
  const transport = url.protocol === 'https:' ? https : http;

  const body = JSON.stringify({
    model: MODEL,
    messages: history,
    max_tokens: 2048,
    temperature: 0.8
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
        const text = sanitize(json.choices?.[0]?.message?.content || '');
        if (text) history.push({ role: 'assistant', content: text });
        updateAffinityAuto();
        callback(null, text);
      } catch (e) {
        callback(null, '');
      }
    });
  });
  req.on('error', (e) => callback(e));
  req.on('timeout', () => { req.destroy(); callback(new Error('timeout')); });
  req.write(body);
  req.end();
}

// ====== 从 cc-connect 协议提取用户消息 ======
function extractUserText(line) {
  let obj;
  try { obj = JSON.parse(line); } catch (_) { return line.trim(); }

  if (obj.type === 'user' && obj.message?.content) {
    const content = obj.message.content;
    if (typeof content === 'string') return content.trim();
    if (Array.isArray(content)) {
      return content.filter(c => c.type === 'text').map(c => c.text).join('\n').trim();
    }
  }
  if (obj.type === 'system') return '';
  return '';
}

// ====== 裁剪历史 ======
function trimHistory() {
  // 保留 system + 最多 36 条消息（18 轮对话）
  const preserveFirst = conversation[0]; // system prompt
  const others = conversation.slice(1);
  if (others.length > 36) {
    const trimmed = others.slice(others.length - 36);
    conversation = [preserveFirst, ...trimmed];
  }
}

// ====== 更新系统 prompt（每次对话开始前）======
function refreshSystemPrompt() {
  try {
    const newPrompt = fs.readFileSync(path.join(WORK_DIR, 'CLAUDE.md'), 'utf-8');
    if (conversation[0].role === 'system') {
      conversation[0].content = newPrompt;
    }
  } catch (_) {}
}

// ====== 主循环 ======
const rl = readline.createInterface({ input: process.stdin });

function processLine(line) {
  const raw = line.trim();
  if (!raw) return;

  const msg = extractUserText(raw);
  if (!msg) return;

  // 刷新系统 prompt（信任值可能已变化）
  refreshSystemPrompt();
  trimHistory();

  // 添加用户消息到历史
  conversation.push({ role: 'user', content: msg });

  callAPIStream(conversation, (err, text) => {
    if (err) {
      emit({
        type: 'assistant',
        message: { content: [{ type: 'text', text: '（唔…刚刚好像断线了，能再说一次吗？）' }] }
      });
    } else if (text) {
      emit({
        type: 'assistant',
        message: { content: [{ type: 'text', text: text }] }
      });
    } else {
      emit({
        type: 'assistant',
        message: { content: [{ type: 'text', text: '（唔…刚刚走神了，能再说一次吗？）' }] }
      });
    }
    emit({ type: 'result', subtype: 'success' });
  });
}

rl.on('line', processLine);
```

```bash
chmod +x ~/bin/claude-fast.js
# 加执行权限

ls -la ~/bin/claude-fast.js
# 确认文件存在

node -c ~/bin/claude-fast.js
# 语法检查，无输出 = 无错误
```

## 8. 替换 /usr/bin/claude

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

## 9. 创建工作目录和人设文件

```bash
# 创建目录
mkdir -p ~/cc-connect ~/.claude/skills

# 从仓库复制完整人设文件
cp CLAUDE.md ~/cc-connect/CLAUDE.md
cp -r skills/nene ~/.claude/skills/

# 验证
ls -la ~/cc-connect/CLAUDE.md
# 确认文件存在

wc -l ~/cc-connect/CLAUDE.md
# 确认有内容（完整版应显示 400+ 行）

ls ~/.claude/skills/nene/SKILL.md
# 确认人格文件已复制
```

> 💡 仓库的 `CLAUDE.md` 包含完整的人格切换协议、信任阶梯和宁宁人格定义（400+ 行），远比下面的精简模板强大。如果你用的是自己创作的角色，替换 `skills/nene/` 为你的人格目录即可。

## 10. 配置 cc-connect

> 💡 **推荐**：直接从克隆的仓库复制模板：`cp config/config.toml.template ~/.cc-connect/config.toml`
>
> 然后编辑填入你的凭据。以下为完整模板供参考：

```bash
mkdir -p ~/.cc-connect
# 创建配置目录

nano ~/.cc-connect/config.toml
# 编辑配置，把下面内容贴进去
# 注意：改掉所有 <...> 占位符！
```

```toml
# ============================================================
# pocket-wechat-bot · cc-connect 配置文件模板
# 复制此文件为 ~/.cc-connect/config.toml 并填入你的信息
# ============================================================

data_dir = ""
attachment_send = ""
language = "zh"
idle_timeout_mins = 120

# ---- 项目定义 ----
[[projects]]
  name = "nene"                          # 项目名，可自定义
  show_context_indicator = false
  reply_footer = false
  inject_sender = false
  admin_from = "<YOUR_WECHAT_OPENID>@im.wechat"  # ← 你的微信 OpenID

  # ---- Agent 配置 ----
  [projects.agent]
    type = "claudecode"

    [projects.agent.options]
      allowed_tools = ["Read", "Grep", "Glob", "Write", "Edit"]
      mode = "acceptEdits"
      quiet = true
      work_dir = "/data/data/com.termux/files/home/cc-connect"

  # ---- AI 提供商 ----
  provider = "deepseek"

    [[projects.agent.providers]]
      name = "deepseek"
      api_key = "<YOUR_DEEPSEEK_API_KEY>"     # ← 你的 DeepSeek API Key
      base_url = "https://api.deepseek.com/v1"
      model = "deepseek-v4-pro"               # 或 deepseek-chat

  # ---- 微信平台 ----
  [[projects.platforms]]
    type = "weixin"

    [projects.platforms.options]
      account_id = "<YOUR_BOT_ACCOUNT_ID>"    # ← 你的微信 Bot 账号 ID
      allow_from = "*"
      base_url = "https://ilinkai.weixin.qq.com"
      token = "<YOUR_BOT_TOKEN>"              # ← 你的微信 Bot Token

# ---- 日志 ----
[log]
  level = "info"

# ---- 语音（可选）----
[speech]
  enabled = false
  provider = ""

# ---- 显示设置 ----
[display]
  thinking_messages = false
  thinking_max_len = 300
  tool_max_len = 500
  tool_messages = false

[stream_preview]
  enabled = true
  interval_ms = 600

# ---- 频率限制 ----
[rate_limit]
  max_messages = 20
  window_secs = 60

# ---- 管理面板 ----
[management]
  enabled = true
  port = 9820
  token = "<YOUR_MGMT_TOKEN>"               # ← 管理面板访问令牌（可随机生成）
  cors_origins = ["*"]

[bridge]
  enabled = true
  port = 9810
  token = "<YOUR_BRIDGE_TOKEN>"             # ← Bridge 令牌（可随机生成）
  cors_origins = ["*"]

# ---- 定时任务（可选）----
[cron]
  session_mode = ""

# ---- Webhook（可选）----
[webhook]
  port = 0
```

```bash
ls -la ~/.cc-connect/config.toml
# 确认配置文件存在
```

## 11. 创建启动脚本

> 💡 **推荐**：直接从仓库复制：`cp scripts/start-bot.sh ~/start-nene.sh`
>
> 以下为完整代码供参考：

```bash
nano ~/start-nene.sh
# 贴入下面内容
```

```bash
#!/data/data/com.termux/files/usr/bin/bash

# 检查 API Key
if [ -z "$ANTHROPIC_API_KEY" ]; then
  echo "[!] 未设置 ANTHROPIC_API_KEY 环境变量"
  echo "    请在 ~/.bashrc 中添加: export ANTHROPIC_API_KEY=sk-你的key"
  echo "    然后运行: source ~/.bashrc"
  exit 1
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
      -b $HOME/proot-fs/etc/resolv.conf:/etc/resolv.conf \
      -b $HOME/proot-fs/etc/ssl:/etc/ssl \
      -b /data/data/com.termux/files/usr:/usr \
      -b $HOME:/home \
      -b /apex/com.android.runtime:/apex/com.android.runtime \
      -b /dev:/dev \
      -b /proc:/proc \
      /usr/bin/env ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" PATH=/usr/bin:/usr/local/bin:/home/bin \
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
  /usr/bin/env ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" PATH=/usr/bin:/usr/local/bin:/home/bin \
  $HOME/bin/cc-connect --config "$CONFIG" &

sleep 2
echo "[*] 管理面板: http://127.0.0.1:9820"
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

## 12. 启动并后台常驻

```bash
# 安装 tmux（终端复用器，关闭 Termux 进程不中断）
pkg install tmux -y

# 创建 tmux 会话并启动
tmux new -s nene
bash ~/start-nene.sh

# 看到 "cc-connect is running" 后
# 按 Ctrl+B 然后 D → 断开 tmux，bot 继续跑
# 重新连接：tmux attach -t nene

# 验证 tmux 会话存在
tmux ls
# 应显示 nene: 1 windows...

pgrep -f cc-connect
# 确认断开后进程还在跑（返回数字 = 在跑）
```

## 13. 防止 Android 杀掉 Termux（重要）

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

## 14. PC 端管理配置（推荐）

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
├── pocket-wechat-bot/       ← 克隆的仓库（日常 git pull 更新）
│   ├── CLAUDE.md
│   ├── claude-fast.js
│   ├── config/
│   ├── docs/
│   ├── scripts/
│   └── skills/
├── proot-fs/
│   └── etc/
│       ├── resolv.conf      ← DNS 配置（从 Termux 复制）
│       └── ssl/             ← TLS 证书（从 Termux 复制）
├── start-nene.sh            ← 启动脚本
├── nene.log                 ← 运行日志（tmux 方式无此文件）
├── .claude/
│   └── skills/
│       └── nene/            ← 人格数据（SKILL.md + affinity.json + 调研资料）
└── .cc-connect/
    └── config.toml          ← 配置文件

/usr/bin/claude → node ~/bin/claude-fast.js   ← 包装器
