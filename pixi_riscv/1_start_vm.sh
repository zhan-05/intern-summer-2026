#!/bin/bash
# =============================================
# Step 1: 启动 RISC-V VM
# 在一个 WSL 终端中运行此脚本
# 保持窗口打开（此终端就是VM的控制台）
# =============================================

IMAGE="/mnt/d/riscv-images/openeuler-riscv64.qcow2"
UEFI_CODE="/mnt/d/riscv-images/uefi/RISCV_VIRT_CODE.fd"
UEFI_VARS="/mnt/d/riscv-images/uefi/RISCV_VIRT_VARS.fd"

qemu-system-riscv64 \
  -nographic \
  -machine virt,pflash0=pflash0,pflash1=pflash1,acpi=off \
  -smp 4 -m 4G \
  -blockdev node-name=pflash0,driver=file,read-only=on,filename="$UEFI_CODE" \
  -blockdev node-name=pflash1,driver=file,filename="$UEFI_VARS" \
  -drive file="$IMAGE",format=qcow2,if=none,id=hd0 \
  -object rng-random,filename=/dev/urandom,id=rng0 \
  -device virtio-rng-device,rng=rng0 \
  -device virtio-blk-device,drive=hd0 \
  -device virtio-net-device,netdev=usernet \
  -netdev user,id=usernet,hostfwd=tcp::2222-:22
