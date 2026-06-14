# ⚠️ 历史文档 · 方案已废弃

> **当前项目使用 `claude-fast.js`（一个纯 Node.js 脚本）替代原生 Claude Code。**
> 本文档描述的是另一种已被放弃的方案（在 Android 上运行真正的 Claude Code 二进制）。
> 如果你只是在部署 pocket-wechat-bot，**不需要阅读本文档**。
> 保留此文仅供技术参考。
>
> ---

# Android/Termux 运行 Claude Code 原生二进制完全指南

## 问题背景

在 Android 手机 Termux 环境中通过 `cc-connect` 启动微信机器人时，发送消息后报错：

```
fork/exec /data/data/com.termux/files/usr/bin/claude: no such file or directory
```

`cc-connect` 的 `claudecode` agent 类型需要调用 `claude` 命令行工具。虽然通过 `npm install -g @anthropic-ai/claude-code` 安装了包，但原生二进制无法在 Android 上运行。

## 核心技术挑战

Android 与标准 Linux 之间存在三层不兼容：

| 层次 | Linux | Android | 影响 |
|------|-------|---------|------|
| **libc** | glibc | Bionic | 动态链接器不兼容 |
| **ELF 加载** | 支持 ET_EXEC | 强制 PIE (ET_DYN) | 非 PIE 二进制拒绝执行 |
| **TLS 对齐** | 8 字节即可 | 强制 ≥64 字节 | TLS 段校验失败 |

Claude Code 的原生二进制（`linux-arm64` 版本）是：
- 编译为 **ET_EXEC**（固定地址可执行文件）
- 链接到 **glibc**
- TLS 段对齐为 **8 字节**

三项全部不兼容。

## 解决方案总览

```
┌─────────────────────────────────────────────────────┐
│  Android/Termux                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │  proot (外层，启动 cc-connect)                 │  │
│  │  -b proot-fs/lib:/lib  ← 真 glibc 库          │  │
│  │  ┌─────────────────────────────────────────┐  │  │
│  │  │  cc-connect → fork/exec claude          │  │  │
│  │  │  claude = shell wrapper                 │  │  │
│  │  │  ┌───────────────────────────────────┐  │  │  │
│  │  │  │  proot (内层)                     │  │  │  │
│  │  │  │  unset LD_PRELOAD                 │  │  │  │
│  │  │  │  → claude.exe (DYN patched)       │  │  │  │
│  │  │  │  → ld-linux-aarch64.so.1 (glibc)  │  │  │  │
│  │  │  └───────────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

## 具体步骤

### Step 1：获取原生二进制

Claude Code 通过 npm 发布，`linux-arm64` 原生包是可选依赖。npm 检测到 `android` 平台后拒绝安装。

**绕过方案**：直接从 npm registry 下载 tarball。

```bash
cd ~
curl -L "https://registry.npmjs.org/@anthropic-ai/claude-code-linux-arm64/-/claude-code-linux-arm64-2.1.175.tgz" \
  --output ca.tar.gz
tar xzf ca.tar.gz
# 得到 package/claude (ELF 64-bit ARM executable)
```

### Step 2：修补 ELF 头——绕过 PIE 强制

Android 内核在 `execve` 系统调用中强制检查 PIE（Position-Independent Executable）。原始二进制类型为 `ET_EXEC`（固定地址），必须改为 `ET_DYN`（共享对象 / PIE）。

```bash
# 将 ELF header 中 e_type 字段从 0x0002 (EXEC) 改为 0x0003 (DYN)
# e_type 位于 ELF header 偏移 16 (0x10)，2 字节小端
printf '\x03' | dd of=package/claude bs=1 seek=16 count=1 conv=notrunc
```

**验证**：
```bash
$ readelf -h package/claude | grep Type
  Type:                              DYN (Shared object file)   # 原来是 EXEC
```

> ⚠️ **失败尝试**：还尝试过修改 TLS 段的 `p_align` 从 8 到 64（绕过 Android Bionic 的 TLS 对齐检查），但这导致 Bun 运行时 segfault。原因是修改 TLS 对齐后内存布局异常。仅在 glibc 环境下（非 Bionic），内核不会触发 TLS 检查，所以不需要此 patch。

### Step 3：获取真 glibc——替换 Bionic 符号链接

手机的 `~/proot-fs/lib/` 目录中所谓的 "glibc" 全是符号链接，指向 Android Bionic：

```bash
$ ls -la ~/proot-fs/lib/
ld-linux-aarch64.so.1 -> /apex/com.android.runtime/bin/linker64  # Android 链接器!
libc.so.6 -> /data/data/com.termux/files/usr/lib/libc.so          # Bionic libc!
libdl.so.2 -> /data/data/com.termux/files/usr/lib/libdl.so
libm.so.6 -> /data/data/com.termux/files/usr/lib/libm.so
libpthread.so.0 -> /data/data/com.termux/files/usr/lib/libpthread.so
librt.so.1 -> /data/data/com.termux/files/usr/lib/librt.so
```

**解决方案**：从 Debian arm64 软件源提取真 glibc。

```bash
# 在 PC 上下载 Debian 12 (Bookworm) arm64 libc6 包
curl -sL "https://mirrors.ustc.edu.cn/debian/pool/main/g/glibc/libc6_2.36-9+deb12u14_arm64.deb" \
  -o libc6_arm64.deb

# 解压 (7z 可处理 .deb ar 归档)
7z x libc6_arm64.deb          # 得到 data.tar
tar xf data.tar -C glibc-push \
  ./lib/aarch64-linux-gnu/ld-linux-aarch64.so.1 \
  ./lib/aarch64-linux-gnu/libc.so.6 \
  ./lib/aarch64-linux-gnu/libdl.so.2 \
  ./lib/aarch64-linux-gnu/libm.so.6 \
  ./lib/aarch64-linux-gnu/libpthread.so.0 \
  ./lib/aarch64-linux-gnu/librt.so.1 \
  ./lib/ld-linux-aarch64.so.1

# 推到手机并替换符号链接
adb push glibc-real.tar.gz /sdcard/Download/
# 在 Termux 中：
rm ~/proot-fs/lib/*.so*           # 删除旧符号链接
tar xzf /sdcard/Download/glibc-real.tar.gz -C ~/proot-fs/lib/

# 创建惯用符号链接
cd ~/proot-fs/lib
ln -sf libc.so.6 libc.so
ln -sf libdl.so.2 libdl.so
ln -sf libm.so.6 libm.so
ln -sf libpthread.so.0 libpthread.so
ln -sf librt.so.1 librt.so
```

**验证**：
```bash
$ file ~/proot-fs/lib/ld-linux-aarch64.so.1
# ELF 64-bit LSB shared object, ARM aarch64
# (不是符号链接，是真实文件)
```

### Step 4：创建 claude 包装器脚本

npm 的 `claude` 命令位于 `/data/data/com.termux/files/usr/bin/claude`。需要替换为一个 shell 脚本，在 proot 隔离环境中启动二进制。

**关键点**：必须 `unset LD_PRELOAD`，否则 Termux 的 `libtermux-exec-ld-preload.so` 会注入到 glibc 环境，导致 `version 'LIBC' not found` 错误（Bionic 的版本符号在 glibc 中不存在）。

```bash
#!/data/data/com.termux/files/usr/bin/sh
unset LD_PRELOAD
exec /data/data/com.termux/files/usr/bin/proot \
  -b /data/data/com.termux/files/home/proot-fs/lib:/lib \
  /data/data/com.termux/files/usr/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe "$@"
```

**放置位置**：`/data/data/com.termux/files/usr/bin/claude`（替换 npm 创建的 stub）

### Step 5：更新 start-nene.sh——外层 proot 绑定 glibc

在原有的 proot 命令中添加 `-b $PROOT_FS/lib:/lib`，使 cc-connect 进程也能找到 glibc：

```diff
 proot \
   -b $PROOT_FS/etc/resolv.conf:/etc/resolv.conf \
   -b $PROOT_FS/etc/ssl:/etc/ssl \
+  -b $PROOT_FS/lib:/lib \
   -b /data/data/com.termux/files/usr:/usr \
   -b $HOME:/home \
   ...
```

## 踩过的坑

| # | 尝试 | 结果 | 原因 |
|---|------|------|------|
| 1 | `npm install -g @anthropic-ai/claude-code` | postinstall 失败 | npm 检测到 `android` 平台，不在支持列表中 |
| 2 | `npm install @anthropic-ai/claude-code-linux-arm64` | EBADPLATFORM | npm os/cpu/libc 校验拒绝 android |
| 3 | qemu-aarch64 用户态模拟 | PIE 错误 | QEMU 10.x 在 Android host 上也强制 PIE |
| 4 | 修改 ELF e_type + TLS p_align | segfault @ 0x102 | TLS 对齐修改破坏了 Bun 运行时内存布局 |
| 5 | 仅修改 ELF e_type，使用真 glibc | `libc.so: not found` | 缺少 `libc.so` → `libc.so.6` 符号链接 |
| 6 | 添加符号链接后 | `version 'LIBC' not found` | Termux 的 LD_PRELOAD 注入了 Bionic 库到 glibc 环境 |
| 7 | `unset LD_PRELOAD` | ✅ 成功 | 干净隔离 glibc 和 Bionic |

## 最终文件结构

```
~/proot-fs/lib/           # 真 glibc（从 Debian arm64 提取）
├── ld-linux-aarch64.so.1  # glibc 动态链接器 (202KB)
├── libc.so.6              # glibc C 库 (1.6MB)
├── libc.so -> libc.so.6
├── libdl.so.2             # (67KB)
├── libdl.so -> libdl.so.2
├── libm.so.6              # (592KB)
├── libm.so -> libm.so.6
├── libpthread.so.0        # (67KB)
├── libpthread.so -> libpthread.so.0
├── librt.so.1             # (67KB)
└── librt.so -> librt.so.1

/usr/bin/claude            # Shell 包装器脚本
                            # unset LD_PRELOAD → proot → claude.exe

/usr/lib/node_modules/
  @anthropic-ai/claude-code/
    bin/claude.exe          # 修补后的原生二进制 (ET_DYN)
    cli-wrapper.cjs         # (未使用)
```

## 环境依赖

- **Termux**：提供 Node.js、proot、curl、tar
- **proot**：提供 Linux 命名空间隔离（外层 + 内层）
- **glibc 2.36**：从 Debian 12 Bookworm arm64 提取
- **Claude Code 2.1.175**：linux-arm64 原生二进制（Bun 运行时内嵌）

## ADB 交互技巧

在 PC 上通过 ADB 操作 Termux 私有目录（无需用户在手机上输入命令）：

```bash
# run-as com.termux 可进入 Termux 的 Linux UID
adb shell "run-as com.termux <command>"

# 推送文件到 Termux（Termux 无法直接读 /sdcard）
adb shell "cat /sdcard/file | run-as com.termux sh -c 'cat > /data/data/.../dest'"

# adb push 路径需双斜线避免 E:/Git/ 前缀
adb push file //sdcard//Download//file
```

## 局限与后续

1. **非 PIE 二进制修补**：仅修改 ELF e_type，未处理可能的位置相关代码。在 ARM64 上因 PC-relative 寻址自然兼容，x86 上不可行。
2. **Claude Code 版本更新**：npm 包升级后需重新下载原生包并修补。
3. **性能**：双层 proot + ARM CPU + 大型 CLAUDE.md（46KB），首次消息响应较慢（30-60s），后续消息因 session 复用会显著加快。
4. **TLS 对齐**：未修改。Android 内核在加载 glibc 链接的 DYN 二进制时未触发该检查（仅在 Bionic linker 路径触发）。
