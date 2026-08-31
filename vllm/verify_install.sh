#!/bin/bash
# Install six and verify vllm + torch
export HOME="/home/zhan-05"
source "$HOME/vllm-env/bin/activate"

echo "=== Install six ==="
pip install -i https://pypi.tuna.tsinghua.edu.cn/simple six 2>&1 | tail -3

echo ""
echo "=== Verify vllm ==="
python -c "import vllm; print('vLLM version:', vllm.__version__)"

echo ""
echo "=== Verify torch (CPU mode) ==="
python -c "import torch; print('torch:', torch.__version__); print('CUDA available:', torch.cuda.is_available()); print('Num threads:', torch.get_num_threads())"

echo ""
echo "=== Disk usage of venv ==="
du -sh "$HOME/vllm-env"

echo ""
echo "=== Configure HF mirror (for model downloads) ==="
# Use HF mirror for faster model downloads in China
export HF_ENDPOINT="https://hf-mirror.com"
echo "HF_ENDPOINT=$HF_ENDPOINT"
echo 'export HF_ENDPOINT="https://hf-mirror.com"' >> "$HOME/.bashrc"
echo "Added to .bashrc"
