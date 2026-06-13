# pocket-wechat-bot

> 一部手机 = 一个 AI 角色。微信即界面，零云成本。

基于 [cc-connect](https://github.com/chenhg5/cc-connect) 的 Android 微信 AI 机器人，运行在 Termux + proot 上，使用 DeepSeek API 驱动角色人格。不需要云主机，不需要公网 IP——你的旧安卓手机就是服务器。

---

## 架构

```
你的微信 → 微信开放平台 Bot → cc-connect (Termux/proot)
                                     ↓
                               claude-fast.js → DeepSeek API
                                     ↓
                               CLAUDE.md (人格定义)
                               skills/nene/ (角色数据)
```

---

## 特性

- **手机即主机**：Android 5.0+，Termux + proot 沙箱，后台常驻
- **微信即界面**：在微信里和你的 AI 角色对话，像聊天一样自然
- **人格系统**：基于 Claude Code Skill 格式的角色定义框架，可热切换
- **信任阶梯**：六层好感度系统，AI 会根据信任层级调整回应深度
- **会话记忆**：重启后记得上次聊了什么
- **管理面板**：Web 界面查看日志、管理会话

---

## 快速开始

### 1. 准备环境

在 Android 手机上安装 [Termux](https://f-droid.org/packages/com.termux/)，然后：

```bash
pkg update && pkg upgrade
pkg install proot nodejs git curl -y
```

### 2. 下载 cc-connect

```bash
mkdir -p ~/bin
curl -L "https://github.com/chenhg5/cc-connect/releases/latest/download/cc-connect-linux-arm64" -o ~/bin/cc-connect
chmod +x ~/bin/cc-connect
```

### 3. 克隆项目

```bash
cd ~
git clone https://github.com/99cz99/pocket-wechat-bot.git
cd pocket-wechat-bot
```

### 4. 配置

```bash
# 创建工作目录
mkdir -p ~/cc-connect ~/.cc-connect ~/.claude/skills

# 配置文件
cp config/config.toml.template ~/.cc-connect/config.toml
nano ~/.cc-connect/config.toml      # 填入 API Key 和微信凭据

# 人格文件和系统提示词
cp -r skills/nene ~/.claude/skills/
cp CLAUDE.md ~/cc-connect/CLAUDE.md
```

### 5. 获取微信凭据

```bash
# 扫码获取 token 和 account_id
~/bin/cc-connect weixin setup --project nene
# 把输出的 token 和 account_id 填入 ~/.cc-connect/config.toml
```

### 6. 创建 claude 包装器

cc-connect 通过调用 `/usr/bin/claude` 来启动 AI 进程：

```bash
# 创建包装器（proot 内 /usr/bin/claude 即 Termux 真实 /usr/bin/claude）
cat > /data/data/com.termux/files/usr/bin/claude << 'EOF'
#!/data/data/com.termux/files/usr/bin/sh
exec /usr/bin/node /home/bin/claude-fast.js "$@"
EOF
chmod +x /data/data/com.termux/files/usr/bin/claude

# 安装 claude-fast.js
cp claude-fast.js ~/bin/claude-fast.js
```

### 7. 启动并保持后台

```bash
# 安装 tmux（终端复用器，关闭 Termux 进程不中断）
pkg install tmux -y

# 创建 tmux 会话并启动
tmux new -s nene
bash scripts/start-bot.sh

# 看到 "cc-connect is running" 后
# 按 Ctrl+B 然后 D → 断开 tmux，bot 继续跑
# 重新连接：tmux attach -t nene
```

> ⚠️ **重要**：Android 系统可能杀 Termux 后台进程。需在手机设置中允许 Termux 后台运行，详见 [部署教程第 12 步](docs/deploy-from-zero.md#12-防止-android-杀掉-termux重要)

详细教程见 [docs/deploy-from-zero.md](docs/deploy-from-zero.md)

---

## 人格系统

### 宁宁（nene）— 展示角色

绫地宁宁，出自柚子社《魔女的夜宴》（2015）。基于 30+ 来源深度调研提炼的人格操作系统：

- 7 个核心人格模型（完美面具、自爆式坦白、幻想检验、当下的勇气……）
- 9 条行为启发式
- 完整表达 DNA（日常模式、害羞自爆、契约代价、黑化崩坏）
- 六层信任阶梯（Lv0 陌生人 → Lv5 完全归属）

**角色介绍页**：[docs/nene-skill-intro.html](docs/nene-skill-intro.html)

### 创作你自己的角色

参考 [docs/create-your-own-skill.md](docs/create-your-own-skill.md) 从头写一个属于你的 AI 角色。

---

## 文档索引

| 文档 | 说明 |
|------|------|
| [deploy-from-zero.md](docs/deploy-from-zero.md) | 从零部署完整教程 |
| [deploy-guide.html](docs/deploy-guide.html) | 部署教程（精美 HTML 版） |
| [nene-skill-intro.html](docs/nene-skill-intro.html) | 宁宁 Skill 角色介绍 |
| [android-claude-code-fix.md](docs/android-claude-code-fix.md) | Android/Termux 兼容性排障 |
| [create-your-own-skill.md](docs/create-your-own-skill.md) | 自定义人格创作指南 |

---

## 环境变量

`claude-fast.js` 需要的环境变量：

| 变量 | 说明 |
|------|------|
| `ANTHROPIC_API_KEY` | DeepSeek API Key（启动脚本中设置） |

---

## 归属与致谢

- **cc-connect** — [chenhg5/cc-connect](https://github.com/chenhg5/cc-connect)
- **宁宁角色** — 柚子社《魔女的夜宴》（サノバウィッチ，2015）
- **宁宁 Skill** — [花叔](https://x.com/AlchainHust) · [女娲 Skill造人术](https://github.com/alchaincyf/nuwa-skill)
- **AI 驱动** — [DeepSeek](https://deepseek.com)

---

## 内容提醒

本项目的 `skills/nene/` 目录包含对原作成人内容的文学分析（角色心理层面，见 `references/research/08-adult-content.md`），以及基于信任层级系统的亲密角色扮演框架。不包含游戏画面、音频或完整脚本。如果你对这类内容敏感，请在使用前阅读相关文件说明。

---

## 免责声明

- 本项目为**非官方粉丝作品**，与柚子社、腾讯微信、DeepSeek、Anthropic 无任何关联
- 宁宁（绫地宁宁）是柚子社的虚构角色，本项目中的角色分析为文学研究性质
- **仅供个人学习使用**。使用者需自行承担 API 费用、微信开放平台政策合规等责任
- 请勿用于违法用途

---

## License

MIT · [LICENSE](LICENSE)
