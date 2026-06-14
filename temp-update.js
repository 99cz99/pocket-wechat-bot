const fs = require('fs');

let content = fs.readFileSync('docs/deploy-from-zero.md', 'utf-8');

const claudeFast = fs.readFileSync('claude-fast.js', 'utf-8').trim();
const configToml = fs.readFileSync('config/config.toml.template', 'utf-8').trim();
const startBot = fs.readFileSync('scripts/start-bot.sh', 'utf-8').trim();

// 1. Replace step 6: claude-fast.js
const oldStep6Start = '## 6. 创建 claude-fast.js';
const oldStep7Start = '## 7. 替换 /usr/bin/claude';
const step6Idx = content.indexOf(oldStep6Start);
const step7Idx = content.indexOf(oldStep7Start, step6Idx);

const newStep6 = [
'## 6. 创建 claude-fast.js',
'',
'> 💡 **推荐**：直接从克隆的仓库复制，无需手动输入：`cp claude-fast.js ~/bin/`',
'>',
'> 以下为完整代码供参考。手动创建时贴入：',
'',
'```bash',
'nano ~/bin/claude-fast.js',
'# 打开编辑器，把下面整段代码贴进去',
'```',
'',
'```javascript',
claudeFast,
'```',
'',
'```bash',
'chmod +x ~/bin/claude-fast.js',
'# 加执行权限',
'',
'ls -la ~/bin/claude-fast.js',
'# 确认文件存在',
'',
'node -c ~/bin/claude-fast.js',
'# 语法检查，无输出 = 无错误',
'```',
'',
''
].join('\n');

content = content.slice(0, step6Idx) + newStep6 + content.slice(step7Idx);

// 2. Replace step 9: config.toml
const oldStep9Start = '## 9. 配置 cc-connect';
const oldStep10Start = '## 10. 创建启动脚本';
const step9Idx = content.indexOf(oldStep9Start);
const step10Idx = content.indexOf(oldStep10Start, step9Idx);

const newStep9 = [
'## 9. 配置 cc-connect',
'',
'> 💡 **推荐**：直接从克隆的仓库复制模板：`cp config/config.toml.template ~/.cc-connect/config.toml`',
'>',
'> 然后编辑填入你的凭据。以下为完整模板供参考：',
'',
'```bash',
'mkdir -p ~/.cc-connect',
'# 创建配置目录',
'',
'nano ~/.cc-connect/config.toml',
'# 编辑配置，把下面内容贴进去',
'# 注意：改掉所有 <...> 占位符！',
'```',
'',
'```toml',
configToml,
'```',
'',
'```bash',
'ls -la ~/.cc-connect/config.toml',
'# 确认配置文件存在',
'```',
'',
''
].join('\n');

content = content.slice(0, step9Idx) + newStep9 + content.slice(step10Idx);

// 3. Replace step 10: start-nene.sh
const oldStep10Heading = '## 10. 创建启动脚本';
const oldStep11Heading = '## 11. 启动';
const step10hIdx = content.indexOf(oldStep10Heading);
const step11hIdx = content.indexOf(oldStep11Heading, step10hIdx);

const newStep10 = [
'## 10. 创建启动脚本',
'',
'> 💡 **推荐**：直接从仓库复制：`cp scripts/start-bot.sh ~/start-nene.sh`',
'>',
'> 以下为完整代码供参考：',
'',
'```bash',
'nano ~/start-nene.sh',
'# 贴入下面内容',
'```',
'',
'```bash',
startBot,
'```',
'',
'```bash',
'chmod +x ~/start-nene.sh',
'# 加执行权限',
'',
'ls -la ~/start-nene.sh',
'# 确认文件存在且有执行权限',
'',
'bash -n ~/start-nene.sh',
'# 语法检查，无输出 = 无错误',
'```',
'',
''
].join('\n');

content = content.slice(0, step10hIdx) + newStep10 + content.slice(step11hIdx);

// 4. Merge step 11 (启动) and 12 (后台常驻)
const oldStep11Full = '## 11. 启动';
const oldStep13Start = '## 13. 防止 Android 杀掉 Termux';
const step11fIdx = content.indexOf(oldStep11Full);
const step13sIdx = content.indexOf(oldStep13Start, step11fIdx);

const newStep11 = [
'## 11. 启动并后台常驻',
'',
'```bash',
'# 安装 tmux（终端复用器，关闭 Termux 进程不中断）',
'pkg install tmux -y',
'',
'# 创建 tmux 会话并启动',
'tmux new -s nene',
'bash ~/start-nene.sh',
'',
'# 看到 "cc-connect is running" 后',
'# 按 Ctrl+B 然后 D → 断开 tmux，bot 继续跑',
'# 重新连接：tmux attach -t nene',
'',
'# 验证 tmux 会话存在',
'tmux ls',
'# 应显示 nene: 1 windows...',
'',
'pgrep -f cc-connect',
'# 确认断开后进程还在跑（返回数字 = 在跑）',
'```',
'',
''
].join('\n');

content = content.slice(0, step11fIdx) + newStep11 + content.slice(step13sIdx);

// 5. Re-number remaining steps: 13→12, 14→13
content = content.replace('## 13. 防止 Android 杀掉 Termux（重要）', '## 12. 防止 Android 杀掉 Termux（重要）');
content = content.replace('## 14. PC 端管理配置（推荐）', '## 13. PC 端管理配置（推荐）');

fs.writeFileSync('docs/deploy-from-zero.md', content, 'utf-8');
console.log('Done. Steps 1-13.');
console.log('Length:', content.length, 'chars');
