#!/bin/bash
# 离线挂载qcow2修改密码+sshd_config
# 用sudo执行
set -e

IMAGE="/mnt/d/riscv-images/openeuler-riscv64.qcow2"
MNT="/mnt/vm-edit"

echo "1. 加载NBD内核模块..."
sudo modprobe nbd max_part=8

echo "2. 挂载qcow2到/dev/nbd0..."
sudo qemu-nbd --connect=/dev/nbd0 "$IMAGE"
sleep 3

echo "3. 查看分区表..."
ls -la /dev/nbd0*
sudo fdisk -l /dev/nbd0 2>/dev/null | head -10 || true

echo "4. 创建挂载点并挂载分区..."
sudo mkdir -p "$MNT"

# 尝试不同的分区路径
for part in /dev/nbd0p1 /dev/nbd0p2 /dev/nbd0; do
    if sudo mount "$part" "$MNT" 2>/dev/null; then
        echo "✅ 成功挂载: $part"
        break
    fi
done

if ! mountpoint -q "$MNT"; then
    echo "❌ 挂载失败，尝试guestmount..."
    sudo guestmount -a "$IMAGE" -i "$MNT" 2>/dev/null || {
        echo "guestmount也失败了"
        echo "尝试apt安装..."
        sudo apt-get install -y guestmount 2>&1 | tail -2
        sudo guestmount -a "$IMAGE" -i "$MNT" || exit 1
    }
fi

echo ""
echo "5. 查看挂载内容..."
ls "$MNT"

echo ""
echo "6. 修改root密码..."
if [ -f "$MNT/etc/shadow" ]; then
    # 生成新的密码哈希
    HASH=$(openssl passwd -1 'riscv123')
    # 替换root的密码哈希
    sudo sed -i "s|^root:[^:]*:|root:${HASH}:|" "$MNT/etc/shadow"
    echo "✅ root密码已重置为 riscv123"
    echo "验证:"
    sudo grep '^root:' "$MNT/etc/shadow" | head -1
else
    echo "⚠️  /etc/shadow 未找到"
    find "$MNT" -name "shadow" 2>/dev/null
fi

echo ""
echo "7. 修改sshd_config..."
if [ -f "$MNT/etc/ssh/sshd_config" ]; then
    SSHD="$MNT/etc/ssh/sshd_config"
    sudo sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' "$SSHD"
    sudo sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' "$SSHD"
    sudo sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' "$SSHD"
    echo "✅ sshd_config 已修改"
    echo "关键配置:"
    grep -E "^(PasswordAuth|PubkeyAuth)" "$SSHD"
else
    echo "⚠️  sshd_config 未找到"
    find "$MNT" -name "sshd_config" 2>/dev/null
fi

echo ""
echo "8. 确保sshd开机自启..."
if [ -d "$MNT/etc/systemd/system/multi-user.target.wants" ]; then
    sudo ln -sf /usr/lib/systemd/system/sshd.service \
        "$MNT/etc/systemd/system/multi-user.target.wants/sshd.service" 2>/dev/null || true
    echo "✅ sshd.service 已链接到开机启动"
fi

echo ""
echo "9. 卸载镜像..."
sudo umount "$MNT" 2>/dev/null || true
sudo guestunmount "$MNT" 2>/dev/null || true
sleep 2
sudo qemu-nbd --disconnect /dev/nbd0 2>/dev/null || true
rmdir "$MNT" 2>/dev/null || true

echo ""
echo "======================================"
echo "✅ 镜像修改完成！"
echo "   密码: riscv123"
echo "   SSH:  已启用密码认证"
echo "   下次启动VM即可直接SSH登录"
echo "======================================"
