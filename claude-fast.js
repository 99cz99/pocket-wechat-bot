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
const MODEL = process.env.MODEL || 'deepseek-v4-pro';
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
        '- `last_session`: 改为今天的日期（格式 YYYYY-MM-DD，如 "2026-06-13"）',
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
    if (!resolved.startsWith(HOME)) {
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
        callback(null, '（解析失败: ' + e.message + '）');
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
