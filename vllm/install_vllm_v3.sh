#!/bin/bash
# Install vllm-cpu using Tsinghua mirror (280x faster than default PyPI)
set -e
export HOME="/home/zhan-05"
source "$HOME/vllm-env/bin/activate"

TSINGHUA="https://pypi.tuna.tsinghua.edu.cn/simple"
PYTORCH_CPU="https://download.pytorch.org/whl/cpu"

echo "=== Step 1: Install torch 2.13.0 (unified wheel, works on CPU) from Tsinghua ==="
pip install --no-cache-dir -i $TSINGHUA "torch==2.13.0" 2>&1 | tail -8

echo ""
echo "=== Step 2: Install vllm-cpu 0.27.1 with --no-deps ==="
pip install --no-cache-dir --no-deps -i $TSINGHUA "vllm-cpu==0.27.1" 2>&1 | tail -5

echo ""
echo "=== Step 3: Install vllm-cpu's other dependencies (excluding torch) ==="
pip install --no-cache-dir -i $TSINGHUA \
    "regex" "cachetools" "psutil" "sentencepiece" "numpy" "requests>=2.26.0" \
    "tqdm" "blake3" "py-cpuinfo" "transformers>=5.5.3" "tokenizers>=0.21.1" \
    "safetensors>=0.6.2" \
    'protobuf!=6.30.*,!=6.31.*,!=6.32.*,!=6.33.0.*,!=6.33.1.*,!=6.33.2.*,!=6.33.3.*,!=6.33.4.*,>=5.29.6' \
    "fastapi[standard]>=0.133.0,<0.137.0" "starlette>=1.0.1" "aiohttp>=3.13.3" \
    "openai>=2.0.0" "pydantic>=2.12.0" "prometheus_client>=0.18.0" "pillow" \
    "prometheus-fastapi-instrumentator>=8.0.0" "tiktoken>=0.6.0" \
    "lm-format-enforcer==0.11.3" "llguidance>=1.7.0,<1.8.0" "outlines_core==0.2.14" \
    "lark==1.2.2" "xgrammar>=0.2.1,<1.0.0" "typing_extensions>=4.10" \
    "filelock>=3.16.1" "partial-json-parser" "jsonschema>=4.23.0" \
    "pyzmq>=25.0.0" "msgspec" "mistral_common[image]>=1.11.6" \
    "opencv-python-headless>=4.13.0" "pyyaml" "einops" \
    "compressed-tensors==0.17.0" "depyf==0.20.0" "cloudpickle" "watchfiles" \
    "python-json-logger" "ninja" "pybase64" "cbor2" "ijson" "setproctitle" \
    "openai-harmony>=0.0.3" "anthropic>=0.71.0" \
    "model-hosting-container-standards>=0.1.14,<1.0.0" "mcp" \
    "opentelemetry-sdk>=1.27.0" "opentelemetry-api>=1.27.0" \
    "opentelemetry-exporter-otlp>=1.27.0" \
    "opentelemetry-semantic-conventions-ai>=0.4.1" \
    "setuptools==77.0.3" "numba==0.65.0" \
    "torchaudio" "torchvision" "torchcodec>=0.14" \
    "intel-openmp==2024.2.1" \
    2>&1 | tail -15

echo ""
echo "=== Verify install ==="
pip list 2>/dev/null | grep -iE 'vllm|torch|transformers|numpy|tokenizers|numba' | head -10

echo ""
echo "=== Verify import ==="
python -c "import vllm; print('vLLM version:', vllm.__version__)" 2>&1 | tail -15
