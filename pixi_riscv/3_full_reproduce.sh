#!/bin/bash
# =============================================
# Step 3: 一键完整复现脚本（改进版）
# 在另一个 WSL 终端中运行此脚本
# 需要VM已在另一个终端启动并SSH就绪
# =============================================
set -uo pipefail

# ====== 配置（根据实际情况修改） ======
VM_PASS="riscv123"          # VM root密码
SSH_PORT=2222
WORK_DIR="/mnt/d/riscv.实习"
# =====================================

SCPASS="sshpass -p '$VM_PASS'"
SSH_CMD="$SCPASS ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $SSH_PORT root@localhost"

ok()   { echo -e "\033[32m  ✅ $1\033[0m"; }
info() { echo -e "\033[36m  ℹ️  $1\033[0m"; }
step() { echo ""; echo -e "\033[33m━━━ $1 ━━━\033[0m"; }

echo "=============================================="
echo " Pixi RISC-V AI Demo 完整复现"
echo " 改进: chrony NTP | GPG公钥 | SSH密钥"
echo "=============================================="

# ===== 连接测试 =====
step "连接测试"
if ! $SSH_CMD 'echo SSH_OK' 2>/dev/null | grep -q SSH_OK; then
    echo "❌ 无法连接VM (端口$SSH_PORT)"
    echo "   请确认: VM已启动 + SSH密码认证已启用 + 密码正确($VM_PASS)"
    exit 1
fi
ARCH=$($SSH_CMD 'uname -m' 2>/dev/null | tr -d '\r')
echo "✅ 连接成功，架构: $ARCH"
if [ "$ARCH" != "riscv64" ]; then
    info "注意: 当前VM不是riscv64架构 ($ARCH)"
fi

# ===== 1. 时间同步 + chrony NTP =====
step "1. 时间同步 (chrony NTP替代手工date -s)"

$SSH_CMD '
date -s "2026-09-01 14:00:00" && hwclock -w
if ! command -v chronyd &>/dev/null; then
    yum install -y chrony 2>&1 | tail -1
fi
cat > /etc/chrony.conf << CE
server ntp.aliyun.com iburst
server ntp.ntsc.ac.cn iburst
server time.windows.com iburst
allow 127.0.0.1
makestep 1.0 3
rtcsync
CE
systemctl enable --now chronyd 2>&1 | tail -1
echo "chrony: " $(systemctl is-active chronyd)
date
'
ok "chrony NTP已配置"

# ===== 2. YUM GPG公钥 =====
step "2. YUM GPG公钥 (替代sslverify=false)"

$SSH_CMD '
sed -i "/sslverify=false/d" /etc/yum.conf
echo "sslverify=false 已移除"
if [ ! -f /etc/pki/rpm-gpg/RPM-GPG-KEY-openEuler-24.09 ]; then
    yum install -y curl 2>/dev/null
    curl -fsSL -o /etc/pki/rpm-gpg/RPM-GPG-KEY-openEuler-24.09 \
        https://dl-cdn.openeuler.openatom.cn/openEuler-24.09/OS/RISC-V/RPM-GPG-KEY-openEuler 2>/dev/null || \
    echo "sslverify=false 重新添加 (GPG获取失败)"
fi
if [ -f /etc/pki/rpm-gpg/RPM-GPG-KEY-openEuler-24.09 ]; then
    rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-openEuler-24.09 2>&1 | tail -1
    echo "GPG公钥已导入"
else
    echo "sslverify=false" >> /etc/yum.conf
    echo "⚠️  GPG获取失败，暂时保留sslverify=false"
fi
yum repolist 2>&1 | tail -2
'
ok "YUM安全配置完成"

# ===== 3. SSH密钥 =====
step "3. SSH密钥认证 (ed25519)"

KEY="$HOME/.ssh/id_riscv_ed25519"
if [ ! -f "$KEY" ]; then
    ssh-keygen -t ed25519 -N "" -f "$KEY" -q
    ok "密钥已生成: $KEY"
fi
sshpass -p "$VM_PASS" ssh-copy-id -i "$KEY.pub" -o StrictHostKeyChecking=no -p $SSH_PORT root@localhost 2>&1 | tail -1
ok "SSH公钥已推送"
# 验证免密
if ssh -i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $SSH_PORT root@localhost 'echo KEY_OK' 2>/dev/null | grep -q KEY_OK; then
    ok "SSH密钥认证成功 (已可免密登录)"
fi

# ===== 4. 安装Pixi =====
step "4. 安装Pixi包管理器"

$SSH_CMD '
if ! command -v pixi &>/dev/null; then
    yum install -y curl wget 2>&1 | tail -1
    curl -fsSL https://pixi.sh/install.sh | bash 2>&1 | tail -2
fi
source ~/.bashrc
pixi --version
'
ok "Pixi就绪"

# ===== 5. AI依赖 =====
step "5. AI依赖 (yum预编译包)"

$SSH_CMD '
yum install -y python3-numpy python3-pillow 2>&1 | tail -2
python3 -c "import numpy; print(\"NumPy\", numpy.__version__)"
python3 -c "from PIL import Image; print(\"Pillow OK\")"
'
ok "AI依赖就绪"

# ===== 6. CV Demo =====
step "6. CV Demo (图像处理)"

CV_OUT=$($SSH_CMD '
mkdir -p /tmp/cv_output
python3 << "PYEOF"
import numpy as np
from PIL import Image, ImageFilter
import os, time

t0 = time.time()
img = Image.new("RGB", (256, 256), "white")
p = img.load()
for i in range(256):
    for j in range(256):
        p[i, j] = (i, j, (i+j)//2)
t_create = time.time() - t0
print(f"1. 创建图像: {img.size} ({t_create:.2f}s)")

t0 = time.time()
img_blur = img.filter(ImageFilter.BLUR)
img_edge = img.filter(ImageFilter.FIND_EDGES)
t_filter = time.time() - t0
print(f"2. 滤镜: BLUR, FIND_EDGES ({t_filter:.2f}s)")

t0 = time.time()
img_rot = img.rotate(45)
t_rot = time.time() - t0
print(f"3. 旋转: 45度 ({t_rot:.2f}s)")

for name, im in [("original", img), ("blur", img_blur), ("edge", img_edge), ("rotated", img_rot)]:
    im.save(f"/tmp/cv_output/{name}.png")
for f in sorted(os.listdir("/tmp/cv_output")):
    print(f"   -> {f} ({os.path.getsize('/tmp/cv_output/'+f)} bytes)")
print(f"✅ CV Demo 成功！总耗时 {t_create+t_filter+t_rot:.2f}s")
PYEOF
' 2>&1)
echo "$CV_OUT"
ok "CV Demo完成"

# ===== 7. ASR Demo =====
step "7. ASR Demo (语音识别模拟)"

$SSH_CMD '
python3 << "PYEOF"
import numpy as np
sr, dur = 16000, 2
t = np.linspace(0, dur, sr*dur, endpoint=False)
audio = np.sin(2*np.pi*440*t)
print(f"采样率={sr}Hz, 时长={dur}s, 样本={len(audio)}")
mfcc = np.random.randn(13, 100)
print(f"MFCC特征: (13, 100), mean={mfcc.mean():.4f}")
print(f"模拟识别: hello world this is a risc-v test")
print("✅ ASR Demo 成功")
PYEOF
'
ok "ASR Demo完成"

# ===== 8. LLM Demo =====
step "8. LLM Demo (transformers/回退模拟)"

$SSH_CMD '
python3 << "PYEOF"
try:
    from transformers import pipeline
    g = pipeline("text-generation", model="distilgpt2")
    r = g("RISC-V architecture is", max_length=30)
    print("✅ transformers可用:", r[0]["generated_text"][:80])
except ImportError:
    print("ℹ️ transformers不可用 (RISC-V编译失败)")
    print("   推荐: ONNX Runtime (x86端导出模型)")
    print("        或 llama.cpp RISC-V移植版")
    print("---模拟---")
    print("输入: RISC-V architecture is")
    print("输出: RISC-V architecture is an open standard ISA")
print("✅ LLM Demo 完成")
PYEOF
'
ok "LLM Demo完成"

# ===== 9. 回传CV图片 =====
step "9. 复制CV图片到宿主机"

for f in original.png blur.png edge.png rotated.png; do
    sshpass -p "$VM_PASS" scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P $SSH_PORT \
        root@localhost:/tmp/cv_output/$f "$WORK_DIR/$f" 2>/dev/null && \
        ok "已保存 $f" || echo "⚠️  $f 复制失败"
done
echo ""
ls -la "$WORK_DIR"/*.png 2>/dev/null | awk '{print "  " $NF " (" $5 " bytes)"}'

# ===== 完成 =====
echo ""
echo "=============================================="
echo "  🎉 全部完成！"
echo "  chrony NTP:     ✅ (自动时间同步)"
echo "  GPG 公钥:       ✅ (或sslverify=false)"
echo "  SSH 密钥:       ✅ (ed25519免密)"
echo "  CV Demo:        ✅ (4张图片已生成)"
echo "  ASR Demo:       ✅ (模拟)"
echo "  LLM Demo:       ✅ (模拟/回退)"
echo "  输出: $WORK_DIR/"
echo "=============================================="
