# pocket-wechat-bot

> 一部手机 = 一个 AI 角色。微信即界面，零云成本。

基于 [cc-connect](https://github.com/chenhg5/cc-connect) 的 Android 微信 AI 机器人，运行在 Termux + proot 上，使用 DeepSeek API 驱动角色人格。不需要云主机，不需要公网 IP——你的安卓手机就是服务器。

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

- **手机即主机**：Android 7.0+（arm64），Termux + proot 沙箱，后台常驻
- **微信即界面**：在微信里和你的 AI 角色对话，像聊天一样自然
- **人格系统**：基于 Claude Code Skill 格式的角色定义框架，可热切换
- **信任阶梯**：六层好感度系统，AI 会根据信任层级调整回应深度
- **会话记忆**：重启后记得上次聊了什么
- **管理面板**：Web 界面查看日志、管理会话

---

> ⚠️ **部署方式**：本项目通过 `git clone` 部署，日常更新用 `git pull`。GitHub Release 仅做版本快照备份，不要从 Release 下载。

## 快速开始

### 无脑部署 🤖

**把以下链接丢给你的 PC 端 AI，让它帮你搞定一切：**

```
https://github.com/99cz99/pocket-wechat-bot.git
```

> USB 连接手机 → 把链接 +「照教程帮我部署」发给 Claude Code（或任何能执行命令的 AI）→ AI 自己读文档、敲命令、部署。过程中 AI 会提示你何时需要手动操作（授权 USB 调试、微信扫码等），照着做即可。

不想依赖 AI？按下面手动来：

### 1. 准备环境

在 Android 手机上安装 [Termux](https://f-droid.org/packages/com.termux/) 和 **Termux:API**（F-Droid 搜「Termux:API」安装，提供后台保活），然后：

```bash
# 请确保手机剩余存储空间 > 1GB（运行 df -h ~ 查看）
# 如果下载慢，先切国内镜像：termux-change-repo（选 mirrors.ustc.edu.cn 或 mirrors.tuna.tsinghua.edu.cn）
pkg update && pkg upgrade -y
pkg install proot nodejs git curl termux-api ca-certificates tmux bash nano procps openssl-tool -y
# 验证: node --version（应 v20+）、git --version、which proot
```

### 2. 下载 cc-connect

```bash
mkdir -p ~/bin
curl -L "https://github.com/chenhg5/cc-connect/releases/latest/download/cc-connect-linux-arm64" -o ~/bin/cc-connect
chmod +x ~/bin/cc-connect
# 验证: ~/bin/cc-connect --version（应显示版本号）
```

### 3. 克隆项目

```bash
cd ~
git clone https://github.com/99cz99/pocket-wechat-bot.git
cd pocket-wechat-bot
```

### 4. 准备 proot 环境

```bash
# proot 需要 SSL 证书
mkdir -p ~/proot-fs/etc/ssl
cp -r /data/data/com.termux/files/usr/etc/tls/* ~/proot-fs/etc/ssl/
# DNS 由 start-bot.sh 自动写入 /data/local/tmp/resolv.conf，无需手动创建
```

### 5. 配置

```bash
# 创建工作目录
mkdir -p ~/cc-connect ~/.cc-connect ~/.claude/skills

# 配置文件
cp ~/pocket-wechat-bot/config/config.toml.template ~/.cc-connect/config.toml
nano ~/.cc-connect/config.toml      # 填入 API Key 和微信凭据
# ⚠️ token 和 account_id 先留空！下一步获取微信 token 后再回来填
# ⚠️ admin_from 可以先填 "*"，等 bot 跑起来发 /whoami 获取真实 OpenID 后再改
# ⚠️ MGMT_TOKEN 和 BRIDGE_TOKEN 也要改！可运行 openssl rand -hex 16 随机生成

# 设置 API Key 环境变量（写入 bashrc 持久化）
# 提示：命令前加空格可避免进入 bash history（如 HISTCONTROL=ignorespace）
echo 'export ANTHROPIC_API_KEY=sk-你的key' >> ~/.bashrc
source ~/.bashrc
# ⚠️ 虽然变量名是 ANTHROPIC_API_KEY，但请填 DeepSeek API Key！
```

### 6. 获取微信凭据

```bash
# 扫码获取 token 和 account_id
# --project 参数对应 config.toml 里 [[projects]].name，这里是示例，按你的实际项目名改
~/bin/cc-connect weixin setup --project nene
# 把输出的 token 和 account_id 填入 ~/.cc-connect/config.toml
```

> 💡 如果终端没有直接显示二维码，而是显示了一个链接——点击那个链接，在浏览器里打开二维码。

### 7. 部署人格文件

```bash
# 人格文件和系统提示词
cp -r ~/pocket-wechat-bot/skills/nene ~/.claude/skills/
cp ~/pocket-wechat-bot/CLAUDE.md ~/cc-connect/CLAUDE.md

# ⚠️ 必须编辑！替换 <YOUR_WECHAT_OPENID> 为你的微信 OpenID（通过 /whoami 获取）
nano ~/cc-connect/CLAUDE.md

# 启动脚本
cp ~/pocket-wechat-bot/scripts/start-bot.sh ~/start-nene.sh
# 验证: ls ~/cc-connect/CLAUDE.md ~/.cc-connect/config.toml ~/start-nene.sh
```

### 8. 创建 claude 包装器

cc-connect 通过调用 `/usr/bin/claude` 来启动 AI 进程：

```bash
# 创建包装器（proot 内 /usr/bin/claude 即 Termux 真实 /usr/bin/claude）
cat > /data/data/com.termux/files/usr/bin/claude << 'EOF'
#!/data/data/com.termux/files/usr/bin/sh
exec /usr/bin/node /home/bin/claude-fast.js "$@"
EOF
chmod +x /data/data/com.termux/files/usr/bin/claude

# 安装 claude-fast.js
cp ~/pocket-wechat-bot/claude-fast.js ~/bin/claude-fast.js
# 验证: node -c ~/bin/claude-fast.js（无输出=语法正确）
```

### 9. 启动并保持后台

```bash
# 创建 tmux 会话并启动
tmux new -s nene
bash ~/start-nene.sh

# 看到 "cc-connect 进程已启动 (PID: ...)" 后
# 按 Ctrl+B 然后 D → 断开 tmux，bot 继续跑
# 重新连接：tmux attach -t nene
# 验证: pgrep -f cc-connect（返回数字=在跑）、tmux ls
```

> ⚠️ **重要**：Android 系统可能杀 Termux 后台进程。需在手机设置中允许 Termux 后台运行，详见 [部署教程第 13 步](docs/deploy-from-zero.md#13-防止-android-杀掉-termux重要)

详细教程见 [docs/deploy-from-zero.md](docs/deploy-from-zero.md)

---

## 人格系统

目前已有人格：

| 人格 | 目录 | 说明 |
|------|------|------|
| **宁宁（nene）** | `skills/nene/` | 绫地宁宁，出自柚子社《魔女的夜宴》。7 个核心人格模型、完整表达 DNA、六层信任阶梯 |

**角色介绍页**：[docs/nene-skill-intro.html](docs/nene-skill-intro.html)

### 创作你自己的角色

参考 [docs/create-your-own-skill.md](docs/create-your-own-skill.md) 从头写一个属于你的 AI 角色。

---

## 文档索引

| 文档 | 说明 |
|------|------|
| [usage.md](docs/usage.md) | 使用指南 · 命令与交互 |
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
