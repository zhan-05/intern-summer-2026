# Pixi RISC-V AI Demo 问题复现说明

## 一、项目概述

本项目旨在验证 **Pixi 包管理器在 RISC-V 架构上的原生支持**，并完成 AI 相关 Demo（CV/ASR/LLM）的可复现性验证。基于 openEuler 24.09 RISC-V（QEMU 模拟）环境，在之前手动复现的基础上，整合社区专家提出的 4 项关键改进（chrony NTP、YUM GPG 公钥、SSH 密钥认证、transformers 替代方案），提供一套完整、安全、自动化的复现流程。

**改进前 vs 改进后对比**

| 改进项 | 改进前（手动） | 改进后（自动化） |
|--------|----------------|------------------|
| VM 时间同步 | 每次重启 `date -s` 手工校准 | chrony NTP 自动同步 |
| YUM SSL 安全 | `sslverify=false` 全局禁用（有安全风险） | 导入 openEuler GPG 公钥 |
| SSH 认证 | 密码登录（易暴力破解） | ed25519 密钥免密登录 |
| LLM Demo | 纯文本模拟打印 | 推荐 ONNX Runtime / llama.cpp 真实推理 |

---

## 二、环境要求

### 2.1 硬件

| 项目 | 要求 |
|------|------|
| 宿主机 CPU | Intel/AMD x86_64 四核及以上 |
| 内存 | ≥ 8GB |
| 磁盘空间 | ≥ 20GB 可用 |
| 网络 | 可访问 PyPI、Pixi、openEuler 仓库 |

### 2.2 软件

| 软件 | 版本 | 说明 |
|------|------|------|
| Windows | 10/11 | 宿主机 |
| WSL2 | Ubuntu 22.04+ | 推荐发行版 |
| QEMU | 10.2+ | RISC-V 模拟器 |
| QEMU UEFI | `RISCV_VIRT_CODE.fd` + `RISCV_VIRT_VARS.fd` | 位于 `/usr/share/qemu-efi-riscv64/` |
| openEuler 镜像 | 24.09 RISC-V qcow2 | 约 2.6GB |
| sshpass | 1.09+ | SSH 密码工具 |

### 2.3 准备工作

```bash
# 在 WSL2 中安装依赖
sudo apt update
sudo apt install -y qemu-system-riscv qemu-efi-riscv64 qemu-utils sshpass cloud-localds

# 下载 openEuler 24.09 RISC-V 镜像到 /mnt/d/riscv-images/
# 下载地址: https://dl-cdn.openeuler.openatom.cn/openEuler-24.09/virtual_machine_img/riscv64/
# 文件名: openEuler-24.09-riscv64.qcow2.xz
xz -d openEuler-24.09-riscv64.qcow2.xz

# 复制 UEFI 固件到可写目录（解决 VARS 写入权限问题）
mkdir -p /mnt/d/riscv-images/uefi
cp /usr/share/qemu-efi-riscv64/RISCV_VIRT_CODE.fd /mnt/d/riscv-images/uefi/
cp /usr/share/qemu-efi-riscv64/RISCV_VIRT_VARS.fd /mnt/d/riscv-images/uefi/
chmod 644 /mnt/d/riscv-images/uefi/*
```

---

## 三、复现步骤（共 3 步，需 2 个 WSL 终端）

> **重要提示**：需同时打开 2 个 WSL 终端
> - **终端 A**：运行 VM（保持打开，不能关闭）
> - **终端 B**：执行自动化脚本

### Step 1：启动 RISC-V VM（终端 A）

```bash
cd /mnt/d/riscv.实习
chmod +x 1_start_vm.sh
./1_start_vm.sh
```

**观察现象**：
- 终端输出 `RISC-V EDK2 firmware version ...` 启动 UEFI
- 然后 `Loading Linux ...` 加载 openEuler 内核
- 最终显示 `localhost login:` 登录提示符（约需 60-90 秒）

**预期结果**：VM 成功启动，到达 openEuler tty 登录界面

### Step 2：在 VM 控制台启用 SSH（终端 A 继续）

在刚刚启动的 VM 控制台里执行：

```
localhost login: root
Password: riscv123
```

登录成功后，在 root 提示符下执行：

```bash
# 启用 SSH 密码认证
sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
systemctl restart sshd

# 确认 sshd 正在监听
ss -tlnp | grep :22
```

**观察现象**：
- `systemctl restart sshd` 无报错
- `ss -tlnp` 输出中看到 `:22` 端口 LISTEN 状态

**预期结果**：SSHD 正在监听 22 端口，可通过 SSH 连接

### Step 3：一键完整复现（终端 B）

打开**另一个** WSL 终端，执行：

```bash
cd /mnt/d/riscv.实习
chmod +x 3_full_reproduce.sh
./3_full_reproduce.sh
```

脚本会自动完成以下 **9 个关键步骤**：

| 步骤 | 内容 | 关键改进 |
|------|------|----------|
| 连接测试 | 验证 SSH 可达，确认架构为 riscv64 | - |
| **1. 时间同步** | chrony NTP 自动校准（替代手工 `date -s`） | ✅ 改进 |
| **2. YUM 安全** | 导入 openEuler GPG 公钥（替代 `sslverify=false`） | ✅ 改进 |
| **3. SSH 密钥** | 生成 ed25519 密钥并推送，配置免密登录 | ✅ 改进 |
| 4. Pixi 安装 | 官方脚本安装 Pixi 0.74.0 | - |
| 5. AI 依赖 | yum 预编译包安装 NumPy 1.24.3 + Pillow 10.3.0 | - |
| 6. CV Demo | 图像创建 + BLUR/FIND_EDGES 滤镜 + 45° 旋转 | - |
| 7. ASR Demo | NumPy 生成音频 + MFCC 特征提取（模拟） | - |
| 8. LLM Demo | 尝试 transformers → 不可用则回退模拟 | - |
| 9. 回传结果 | SCP 复制 4 张 CV 图片到宿主机根目录 | - |

---

## 四、关键操作节点详解

### 节点 1：时间同步（改进项）

**问题背景**：QEMU RISC-V VM 不支持自动 RTC 时间同步，每次重启后系统时间漂移数月，导致 `SSL certificate is not yet valid` 错误。

**改进方案**：启用 chrony NTP 服务

```bash
# 一次性配置，永久生效
yum install -y chrony
cat > /etc/chrony.conf << 'EOF'
server ntp.aliyun.com iburst
server ntp.ntsc.ac.cn iburst
server time.windows.com iburst
allow 127.0.0.1
makestep 1.0 3
rtcsync
EOF
systemctl enable --now chronyd
```

| 对比项 | 手工 `date -s` | chrony NTP |
|--------|---------------|------------|
| 操作 | 每次重启手动执行 | 永久启用，自动同步 |
| 时间漂移 | 严重 | 自动维持，毫秒级精度 |

### 节点 2：YUM SSL（改进项）

**问题背景**：原方案全局禁用 SSL 验证（`sslverify=false`），存在中间人攻击风险。

**改进方案**：导入仓库 GPG 公钥

```bash
curl -o /etc/pki/rpm-gpg/RPM-GPG-KEY-openEuler-24.09 \
  https://dl-cdn.openeuler.openatom.cn/openEuler-24.09/OS/RISC-V/RPM-GPG-KEY-openEuler
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-openEuler-24.09
sed -i '/sslverify=false/d' /etc/yum.conf
```

| 对比项 | `sslverify=false` | GPG 公钥导入 |
|--------|-------------------|-------------|
| 安全性 | ⚠️ 禁用 HTTPS 验证 | ✅ 包签名验证 |
| 中间人攻击 | 无防护 | 可检测 |

### 节点 3：SSH 密钥（改进项）

**问题背景**：原方案用固定密码登录，存在暴力破解风险。

**改进方案**：ed25519 密钥认证

```bash
# WSL 宿主机执行（一次性）
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_riscv_ed25519
ssh-copy-id -p 2222 root@localhost   # 首次需密码
# 之后即可免密登录
ssh -p 2222 root@localhost
```

| 对比项 | 密码认证 | ed25519 密钥 |
|--------|----------|-------------|
| 暴力破解 | 高风险 | 极低风险 |
| 自动化 | 需 sshpass | 原生支持 |

### 节点 4：transformers（改进项）

**问题背景**：原方案中 `transformers` 库 pip 编译在 RISC-V 上失败，LLM Demo 退化为纯文本打印。

**可行方案**（按推荐优先级）：

| 方案 | 复杂度 | 实施路径 |
|------|--------|----------|
| **ONNX Runtime** ⭐ 推荐 | ⭐⭐ | 1. x86 端 `optimum-cli export onnx -m distilgpt2 ./model`<br>2. VM 装 onnxruntime<br>3. 用 ORT 推理 API |
| **社区预编译 wheel** | ⭐ | GitHub 搜索 `transformers riscv64 wheel`<br>或 openKylin conda 渠道 |
| **llama.cpp RISC-V** | ⭐⭐⭐ | 1. 克隆 llama.cpp<br>2. `make all`<br>3. 转换权重为 ggml 格式 |

---

## 五、观察结果与现象

### 5.1 环境验证结果

| 检查项 | 预期 | 状态 |
|--------|------|------|
| QEMU 启动至登录 | openEuler tty（60-90 秒） | 🔵 预期 PASS |
| SSH 连接 localhost:2222 | 密码登录成功 | 🔵 预期 PASS（需镜像已修改密码） |
| VM 架构 | riscv64 | 🔵 预期 PASS |
| `pixi --version` | 0.74.0（riscv64 原生） | 🔵 预期 PASS |
| NumPy 安装 | yum 1.24.3 预编译包 | 🔵 预期 PASS |
| Pillow 安装 | yum 10.3.0 预编译包 | 🔵 预期 PASS |
| chrony NTP | systemd active（开机自启） | 🔵 预期 PASS |
| sshd 密码认证 | PasswordAuthentication yes | 🔵 预期 PASS |

> **注**：以上结果基于 openEuler 24.09 RISC-V 已验证环境（见 `Pixi_RISC-V_复现报告.md` 第九章）。改进版脚本（chrony/GPG/SSH密钥/transformers 替代方案）在之前成功复现的基础上升级，逻辑经过检查，但需在当前环境重新执行确认。

### 5.2 CV Demo 输出

| 文件 | 内容 | 大小 | 生成耗时 |
|------|------|------|----------|
| `original.png` | 256×256 RGB 渐变 (R=i, G=j, B=(i+j)//2) | ~864B | ~2.0s |
| `blur.png` | PIL BLUR 高斯模糊滤镜 | ~864B | <0.1s |
| `edge.png` | PIL FIND_EDGES 边缘检测 | ~1.8KB | <0.1s |
| `rotated.png` | 45° 中心旋转，四角黑边填充 | ~6.3KB | <0.1s |

### 5.3 踩坑现象

| 现象 | 原因 | 解决 |
|------|------|------|
| VM 启动卡在 UEFI | UEFI 固件路径错误 | 固件从 `/usr/share/qemu-efi-riscv64/` 复制到可写目录 |
| `SSL certificate is not yet valid` | VM 系统时间重置 | 修复时间 + 启用 chrony NTP |
| SSH `Permission denied` | openEuler 默认禁用密码认证 | `sed` 修改 sshd_config + `systemctl restart sshd` |
| pip `ModuleNotFoundError` | RISC-V 上编译 C 扩展失败 | 改用 `yum install python3-*` 预编译包 |
| `QEMU 进程启动后消失` | 外层 Shell 退出时 SIGHUP 杀掉子进程 | 用 tmux/nohup 保持，或在独立窗口启动 |

---

## 六、补充说明

### 6.1 前置条件

- QEMU RISC-V 模拟器及 UEFI 固件已安装
- openEuler 24.09 RISC-V qcow2 镜像已下载
- WSL2 中已安装 sshpass 工具
- VM root 密码已知（默认 `riscv123`）

### 6.2 目录结构（扁平化）

所有文件直接放置于根目录，无子目录：

```
riscv.实习/
├── README.md                     ← 本文档（问题复现说明）
├── Pixi_RISC-V_复现报告.md       ← 详细技术报告
├── offline_fix.sh                ← 可选：离线修改qcow2镜像密码/sshd
├── user-data                     ← Cloud-init 配置（密码/SSH）
├── 1_start_vm.sh                 ← Step 1: 启动 VM
├── 2_vm_setup.sh                 ← Step 2: VM 控制台设置参考
├── 3_full_reproduce.sh           ← Step 3: 完整一键复现脚本
├── original.png / blur.png / edge.png / rotated.png  ← CV Demo 输出
```

### 6.3 注意事项

1. **VM 窗口必须保持打开**：关闭终端 A 的 VM 窗口等于关闭 VM
2. **密码不一致**：如果 SSH 连接失败，可能是 VM root 密码不是 `riscv123`，需要在 VM 控制台执行 `passwd root` 重置
3. **时间修复**：chrony 安装前需要先手工 `date -s` 校准时间到 2024+，否则 HTTPS 证书验证失败
4. **GPG 获取失败**：部分网络环境下 openEuler GPG 公钥下载失败，脚本会自动回退到 `sslverify=false`（临时方案，待网络恢复后可手动导入）
5. **LLM Demo 限制**：transformers 在 RISC-V 上 pip 编译失败，当前脚本自动回退到模拟演示。如需真实推理，参见第三节节点 4 的 ONNX Runtime 方案
6. **重启 VM 后**：SSH 密码认证配置会保留（写在磁盘上的 sshd_config），但时间需要 chrony 重新校准（启动后 1-2 分钟内自动完成）

### 6.4 输出文件位置

所有 CV Demo 生成的图片和脚本产出均直接输出到项目根目录：
- CV 图片：`D:\riscv.实习\*.png`
- 日志：VM 内 `/tmp/cv_output/`
- 报告：`Pixi_RISC-V_复现报告.md`

### 6.5 快速排查表

| 现象 | 立即检查 | 解决 |
|------|----------|------|
| `Connection refused` | `pgrep -f qemu-system` | 重新启动 VM (Step 1) |
| `Permission denied` | VM 控制台密码登录 | `passwd root` 重置密码，修改脚本里的 `VM_PASS` |
| SSL 证书错误 | VM 内 `date` | 等 chrony 同步完成，或手工 `date -s` |
| `command not found: sshpass` | `which sshpass` | `sudo apt install sshpass` |
| `chrony: FAIL` | VM 内 `systemctl status chronyd` | 检查 chrony.conf 服务器地址可达性 |

---

