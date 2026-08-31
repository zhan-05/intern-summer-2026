#!/bin/bash
# vLLM CPU environment setup script
set -e

# Fix HOME that gets polluted by Windows
export HOME="/home/zhan-05"
echo "HOME=$HOME"
echo "USER=$(whoami)"

# Create venv
if [ ! -d "$HOME/vllm-env" ]; then
    echo "--- Creating Python venv at $HOME/vllm-env ---"
    python3 -m venv "$HOME/vllm-env"
fi

# Activate and upgrade pip
source "$HOME/vllm-env/bin/activate"
echo "--- Python version ---"
python --version
pip install --upgrade pip wheel setuptools 2>&1 | tail -3
echo "--- pip version ---"
pip --version

# Save activation script for later use
echo "source $HOME/vllm-env/bin/activate" > "$HOME/activate_vllm.sh"
echo "--- Done. Activation script saved to $HOME/activate_vllm.sh ---"
