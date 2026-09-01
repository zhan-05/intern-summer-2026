#!/bin/bash
# =============================================
# Step 2: 在VM控制台启用SSH密码认证
# 在VM控制台登录后，复制粘贴以下命令执行
# =============================================

echo "==== 在VM控制台里执行以下命令 ===="
echo ""
echo "# 1. 启用SSH密码认证"
echo "sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config"
echo "sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config"
echo "sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config"
echo "systemctl restart sshd"
echo "ss -tlnp | grep :22"
echo ""
echo "# 2. 确认root密码（如未设置或忘记，用passwd重置）"
echo "passwd root"
echo ""
echo "# 3. 记录一下当前VM的root密码，后面脚本要用"
echo "# 默认user-data里配置的是: riscv123"
echo ""
echo "# 完成后，在另一个WSL终端运行 Step 3 脚本"
