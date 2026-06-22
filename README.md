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
                               skills/nene/ + skills/meguru/ (角色数据)
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

### 一键部署 🚀

1. **克隆仓库到 PC**：
   ```bash
   git clone https://github.com/99cz99/pocket-wechat-bot.git
   ```
2. **手机开启 USB 调试**：设置 → 关于手机 → 连点「版本号」打开开发者选项 → 返回 → 开发者选项 → 开启 **USB 调试**
3. **手机用 USB 连接 PC**，在 PC 上打开 `pocket-wechat-bot\scripts\` 文件夹，双击 `deploy.bat`，按照指引操作

脚本自动完成：环境检查 → 文件推送 → 依赖安装 → 配置生成 → 扫码 → 启动。支持中断续跑（幂等）。

**日常更新**：改完代码后，PC 上双击 `scripts\update.bat`，30 秒推文件+重启 bot（版本未变自动跳过）。

> 没有 PC？手机 Termux 里直接跑也行：`git clone https://github.com/99cz99/pocket-wechat-bot.git && cd pocket-wechat-bot && bash scripts/setup-phone.sh`
>
> 详细步骤见 [部署教程](docs/deploy-from-zero.md)。

### 无脑部署 🤖（让 AI 帮你）

**把以下链接丢给你的 PC 端 AI，让它帮你搞定一切：**

```
https://github.com/99cz99/pocket-wechat-bot.git
```

> USB 连接手机 → 把链接 +「照教程帮我部署」发给 Claude Code（或任何能执行命令的 AI）→ AI 自己读文档、敲命令、部署。过程中 AI 会提示你何时需要手动操作（授权 USB 调试、微信扫码等），照着做即可。

详细教程见 [docs/deploy-from-zero.md](docs/deploy-from-zero.md)

---

## 人格系统

目前已有人格：

| 人格 | 目录 | 说明 |
|------|------|------|
| **宁宁（nene）** | `skills/nene/` | 绫地宁宁，出自柚子社《魔女的夜宴》。7 个核心人格模型、完整表达 DNA、六层信任阶梯 |
| **巡（meguru）** | `skills/meguru/` | 因幡巡，出自柚子社《魔女的夜宴》。6 个核心人格模型、完整表达 DNA、元气系学妹 |

**角色介绍页**：[在线预览](https://99cz99.github.io/pocket-wechat-bot/nene-skill-intro.html) · [本地](docs/nene-skill-intro.html)

### 创作你自己的角色

参考 [docs/create-your-own-skill.md](docs/create-your-own-skill.md) 从头写一个属于你的 AI 角色。

---

## 文档索引

| 文档 | 说明 |
|------|------|
| [usage.md](docs/usage.md) | 使用指南 · 命令与交互 |
| [deploy-from-zero.md](docs/deploy-from-zero.md) | 从零部署完整教程 |
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
