# vLLM 框架 CPU 模式测试项目

> **测试日期：** 2026-08-17（基线轮）/ 2026-08-24（复测轮）
> **环境：** Windows 11 + WSL2 Ubuntu 26.04 LTS（无独立 GPU）
> **测试机器：** Intel i5-1155G7（4c/8t）+ 7.6 GB RAM
> **框架版本：** vLLM 0.27.1（vllm-cpu）+ PyTorch 2.13.0

## 项目概述

本项目对 vLLM 推理框架在无 GPU 环境下的端到端推理功能与性能进行系统性复现测试。以可复现的工程方法验证 vLLM 0.27.1 在纯 CPU + WSL 条件下的可用性、部署门槛、性能基线与质量边界。测试覆盖 5 类用例（模型加载、单提示生成、批量请求、对话生成、长文本生成），2 个模型（SmolLM2-135M、Qwen2.5-0.5B），2 轮独立执行，累计 20 个执行单元零失败。

## 文档导航

### 核心文档

| 文件 | 内容 | 说明 |
|---|---|---|
| [**vLLM学习与测试报告.pdf**](./vLLM学习与测试报告.pdf) | 完整学习与测试报告（PDF，A4 排版） | 主交付文档，含封面/目录/八章正文/附录 |
| [01_测试报告.md](./01_测试报告.md) | 复现报告（Markdown） | 含问题描述、环境配置、复现步骤、预期/实际结果、差异分析 |
| [vLLM测试报告.html](./vLLM测试报告.html) | PDF 排版源文件 | HTML 源文件，可用于重新生成 PDF |

### 测试数据与脚本

| 文件 | 内容 | 在复现流程中的步骤 |
|---|---|---|
| [results.json](./results.json) | 原始测试数据（JSON，复测轮全量明细） | 验证产物 |
| [vllm_test.py](./vllm_test.py) | 综合性能测试脚本（TC1-TC5） | 步骤 8：执行测试 |
| [install_vllm_v3.sh](./install_vllm_v3.sh) | vllm-cpu 安装脚本（清华镜像，最终版） | 步骤 3-6：安装依赖 |
| [download_model.py](./download_model.py) | 模型下载脚本（镜像 + 禁用 Xet） | 步骤 7：下载模型 |
| [setup_env.sh](./setup_env.sh) | Python venv 创建脚本 | 步骤 2：创建环境 |
| [verify_install.sh](./verify_install.sh) | 安装验证脚本 | 步骤 9：验证安装 |

## 快速复现

```bash
# 1. 在 WSL 中创建 venv 并安装
wsl -d Ubuntu -- bash /mnt/d/vLLM报告/setup_env.sh
wsl -d Ubuntu -- bash /mnt/d/vLLM报告/install_vllm_v3.sh

# 2. 下载测试模型
wsl -d Ubuntu -- bash -c "source ~/vllm-env/bin/activate && python /mnt/d/vLLM报告/download_model.py"

# 3. 运行测试
wsl -d Ubuntu -- bash -c "
  export HOME=/home/zhan-05
  source ~/vllm-env/bin/activate
  export HF_ENDPOINT=https://hf-mirror.com
  export HF_HUB_DISABLE_XET=1
  export VLLM_CPU_KVCACHE_SPACE=2
  export OMP_NUM_THREADS=4
  python /mnt/d/vLLM报告/vllm_test.py
"
```

## 核心结论

- ✅ vLLM 0.27.1 可在纯 CPU + WSL 环境运行，20/20 执行单元零失败
- 📊 Qwen2.5-0.5B 在 i5 CPU 上达 **9-11 tok/s**（长生成），批量 **13.5-16.8 tok/s**
- 📊 SmolLM2-135M 达 **17-30 tok/s**（长生成），但指令跟随质量差
- ⚠️ 部署存在 8 个需人工解决的问题（依赖声明、镜像、内存预算），非开箱即用
- ⚠️ 7.6 GB 内存是最低门槛，KV 缓存需控制在 2 GB 以内
- 💡 生产负载建议使用 GPU 或改用 llama.cpp

## 文件结构

```
d:\vLLM报告\
├── vLLM学习与测试报告.pdf   ← 主交付文档（PDF，勿修改）
├── vLLM测试报告.html        ← PDF 排版源文件
├── 01_测试报告.md           ← 复现报告（Markdown）
├── README.md                ← 项目导航（本文件）
├── results.json             ← 原始测试数据
├── vllm_test.py             ← 综合测试脚本
├── install_vllm_v3.sh       ← 安装脚本（最终版）
├── setup_env.sh             ← venv 创建脚本
├── verify_install.sh       ← 安装验证脚本
└── download_model.py        ← 模型下载脚本
```

共 10 个文件，无子目录。
