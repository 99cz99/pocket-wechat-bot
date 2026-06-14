const fs = require('fs');

// === Fix README.md ===
let readme = fs.readFileSync('README.md', 'utf-8');

// Renumber steps after the new proot step (was step 4, now step 5)
readme = readme.replace('### 4. 准备 proot 环境', '### 4. 准备 proot 环境');
readme = readme.replace('### 4. 配置', '### 5. 配置');
readme = readme.replace('### 5. 获取微信凭据', '### 6. 获取微信凭据');
readme = readme.replace('### 6. 创建 claude 包装器', '### 7. 创建 claude 包装器');
readme = readme.replace('### 7. 启动并保持后台', '### 8. 启动并保持后台');

// Add start-nene.sh copy to step 5 (配置)
readme = readme.replace(
  'cp CLAUDE.md ~/cc-connect/CLAUDE.md\n# 验证: ls ~/cc-connect/CLAUDE.md ~/.cc-connect/config.toml',
  'cp CLAUDE.md ~/cc-connect/CLAUDE.md\n\n# 启动脚本\ncp scripts/start-bot.sh ~/start-nene.sh\n# 验证: ls ~/cc-connect/CLAUDE.md ~/.cc-connect/config.toml ~/start-nene.sh'
);

fs.writeFileSync('README.md', readme, 'utf-8');
console.log('README.md fixed');

// === Fix deploy-from-zero.md ===
let md = fs.readFileSync('docs/deploy-from-zero.md', 'utf-8');

// Renumber: step 5→6, 6→7, 7→8, 8→9, 9→10, 10→11, 11→12, 12→13, 13→14
const renames = [
  ['## 5. 获取微信 token', '## 6. 获取微信 token'],
  ['## 6. 创建 claude-fast.js', '## 7. 创建 claude-fast.js'],
  ['## 7. 替换 /usr/bin/claude', '## 8. 替换 /usr/bin/claude'],
  ['## 8. 创建工作目录和 CLAUDE.md', '## 9. 创建工作目录和 CLAUDE.md'],
  ['## 9. 配置 cc-connect', '## 10. 配置 cc-connect'],
  ['## 10. 创建启动脚本', '## 11. 创建启动脚本'],
  ['## 11. 启动并后台常驻', '## 12. 启动并后台常驻'],
  ['## 12. 防止 Android 杀掉 Termux（重要）', '## 13. 防止 Android 杀掉 Termux（重要）'],
  ['## 13. PC 端管理配置（推荐）', '## 14. PC 端管理配置（推荐）'],
];

for (const [old, neu] of renames) {
  if (md.includes(old)) {
    md = md.replace(old, neu);
    console.log('Renamed:', old, '->', neu);
  } else {
    console.log('WARNING: not found:', old);
  }
}

// Fix step 9 CLAUDE.md: replace nano + stub with cp from repo
const oldStep9 = `## 9. 创建工作目录和 CLAUDE.md

\`\`\`bash
mkdir -p ~/cc-connect
# 创建 cc-connect 工作目录

nano ~/cc-connect/CLAUDE.md
# 编辑人设文件，把下面内容贴进去
\`\`\`

CLAUDE.md 内容：

\`\`\`markdown
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
\`\`\`

\`\`\`bash
ls -la ~/cc-connect/CLAUDE.md
# 确认文件存在

wc -l ~/cc-connect/CLAUDE.md
# 确认有内容（应显示 10+ 行）
\`\`\``;

const newStep9 = `## 9. 创建工作目录和人设文件

\`\`\`bash
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
\`\`\`

> 💡 仓库的 \`CLAUDE.md\` 包含完整的人格切换协议、信任阶梯和宁宁人格定义（400+ 行），远比下面的精简模板强大。如果你用的是自己创作的角色，替换 \`skills/nene/\` 为你的人格目录即可。`;

if (md.includes(oldStep9)) {
  md = md.replace(oldStep9, newStep9);
  console.log('Fixed step 9 CLAUDE.md');
} else {
  console.log('WARNING: oldStep9 not matched');
}

// Fix step 11: mention cp from repo for start-nene.sh
const oldCpNote = "> 💡 **推荐**：直接从仓库复制：`cp scripts/start-bot.sh ~/start-nene.sh`";
if (md.includes(oldCpNote)) {
  // Already has the note - good
  console.log('Step 11 cp note already present');
}

// Add proot-fs verification to step 5 (now step 5)
// Already done above

fs.writeFileSync('docs/deploy-from-zero.md', md, 'utf-8');
console.log('deploy-from-zero.md fixed');
console.log('All fixes applied.');
