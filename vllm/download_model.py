#!/usr/bin/env python3
"""Download small models suitable for CPU inference testing."""
import os
import sys
import time

# Use HF mirror for faster downloads in China
os.environ["HF_ENDPOINT"] = "https://hf-mirror.com"
# Disable Xet (CAS-based) downloads which fail on the mirror with 401
os.environ["HF_HUB_DISABLE_XET"] = "1"
# Disable hf_transfer (use plain HTTP which is more reliable through mirror)
os.environ["HF_HUB_ENABLE_HF_TRANSFER"] = "0"

from huggingface_hub import snapshot_download

MODELS = [
    "Qwen/Qwen2.5-0.5B-Instruct",   # ~1GB, good quality
    "HuggingFaceTB/SmolLM2-135M-Instruct",  # ~270MB, smallest
]

for model_id in MODELS:
    print(f"\n{'='*60}")
    print(f"Downloading: {model_id}")
    print(f"{'='*60}")
    start = time.time()
    try:
        path = snapshot_download(
            repo_id=model_id,
            # Only download essential files (skip redundant .bin if .safetensors exists)
            allow_patterns=[
                "*.json",
                "*.safetensors",
                "*.txt",
                "tokenizer.model",
                "*.model",
            ],
        )
        elapsed = time.time() - start
        size = 0
        for root, _, files in os.walk(path):
            for f in files:
                size += os.path.getsize(os.path.join(root, f))
        print(f"  Downloaded to: {path}")
        print(f"  Size: {size/1024/1024:.1f} MB")
        print(f"  Time: {elapsed:.1f} seconds")
        print(f"  Speed: {size/1024/1024/elapsed:.1f} MB/s")
    except Exception as e:
        print(f"  ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

print("\n=== All models downloaded successfully ===")
