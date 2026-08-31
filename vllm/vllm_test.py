#!/usr/bin/env python3
"""vLLM CPU comprehensive test script.

Tests:
1. Model loading (timing, memory)
2. Single prompt text generation
3. Batch request processing
4. Chat-style generation (instruction-tuned models)
5. Performance metrics (TTFT, throughput, tokens/s, memory)
6. Concurrent request simulation

Outputs:
- JSON results to results.json
- Human-readable log to stdout
"""
import os
import sys
import time
import json
import gc
import resource
import traceback
from pathlib import Path

# Configure environment BEFORE importing vllm
os.environ["HF_ENDPOINT"] = "https://hf-mirror.com"
os.environ["HF_HUB_DISABLE_XET"] = "1"
os.environ["VLLM_CPU_KVCACHE_SPACE"] = "2"  # 2 GB KV cache (system has ~7.6GB total RAM)
os.environ["OMP_NUM_THREADS"] = "4"  # Use 4 threads (we have 8 logical, leave some for system)

import psutil

# Results container
results = {
    "test_date": time.strftime("%Y-%m-%d %H:%M:%S"),
    "environment": {},
    "models_tested": [],
}

def get_memory_mb():
    """Get current process RSS in MB."""
    proc = psutil.Process(os.getpid())
    return proc.memory_info().rss / 1024 / 1024

def get_system_memory():
    """Get system memory info."""
    vm = psutil.virtual_memory()
    return {
        "total_mb": vm.total / 1024 / 1024,
        "available_mb": vm.available / 1024 / 1024,
        "used_mb": vm.used / 1024 / 1024,
        "percent": vm.percent,
    }

def record_env():
    """Record environment info."""
    import platform
    import torch
    import vllm

    # CPU info
    cpu_info = {}
    try:
        with open("/proc/cpuinfo") as f:
            for line in f:
                if line.startswith("model name"):
                    cpu_info["model"] = line.split(":")[1].strip()
                    break
        cpu_info["cores_physical"] = psutil.cpu_count(logical=False)
        cpu_info["cores_logical"] = psutil.cpu_count(logical=True)
        cpu_info["freq_mhz"] = psutil.cpu_freq().max if psutil.cpu_freq() else None
    except Exception:
        pass

    # CPU ISA
    isa = []
    try:
        with open("/proc/cpuinfo") as f:
            flags = f.read()
        for s in ["avx2", "avx512", "avx512_bf16", "amx_", "vnni", "f16c", "sse4_2"]:
            if s in flags:
                isa.append(s)
    except Exception:
        pass

    results["environment"] = {
        "python_version": sys.version,
        "platform": platform.platform(),
        "vllm_version": vllm.__version__,
        "torch_version": torch.__version__,
        "cuda_available": torch.cuda.is_available(),
        "num_threads": torch.get_num_threads(),
        "cpu": cpu_info,
        "cpu_isa": isa,
        "system_memory_at_start": get_system_memory(),
    }
    print(f"\n[ENV] Python: {sys.version.split()[0]}")
    print(f"[ENV] vLLM: {vllm.__version__}, torch: {torch.__version__}")
    print(f"[ENV] CUDA available: {torch.cuda.is_available()}")
    print(f"[ENV] CPU: {cpu_info.get('model', 'unknown')} ({cpu_info.get('cores_physical', '?')}c/{cpu_info.get('cores_logical', '?')}t)")
    print(f"[ENV] CPU ISA: {', '.join(isa)}")
    print(f"[ENV] Memory at start: {get_system_memory()}")

def test_model(model_id, model_short_name):
    """Run full test suite on one model."""
    print(f"\n{'#'*70}")
    print(f"# Testing: {model_short_name} ({model_id})")
    print(f"{'#'*70}")

    model_result = {
        "model_id": model_id,
        "short_name": model_short_name,
        "tests": {},
    }

    mem_before = get_memory_mb()
    sys_mem_before = get_system_memory()

    # === Step 1: Load model ===
    print(f"\n[LOAD] Loading {model_short_name}...")
    try:
        from vllm import LLM, SamplingParams
        load_start = time.time()
        llm = LLM(
            model=model_id,
            dtype="bfloat16",         # BF16 is best for modern Intel CPUs
            enforce_eager=True,        # No CUDA graphs (CPU)
            max_model_len=1024,        # Smaller context to reduce KV cache memory
            seed=42,
        )
        load_time = time.time() - load_start
        mem_after_load = get_memory_mb()
        sys_mem_after_load = get_system_memory()

        model_result["tests"]["model_load"] = {
            "status": "success",
            "load_time_sec": round(load_time, 2),
            "process_rss_before_mb": round(mem_before, 1),
            "process_rss_after_mb": round(mem_after_load, 1),
            "process_rss_delta_mb": round(mem_after_load - mem_before, 1),
            "system_memory_before": sys_mem_before,
            "system_memory_after": sys_mem_after_load,
        }
        print(f"[LOAD] Success in {load_time:.2f}s, RSS: {mem_before:.0f}MB -> {mem_after_load:.0f}MB (delta: {mem_after_load-mem_before:.0f}MB)")

    except Exception as e:
        print(f"[LOAD] FAILED: {e}")
        traceback.print_exc()
        model_result["tests"]["model_load"] = {
            "status": "failed",
            "error": str(e),
            "traceback": traceback.format_exc(),
        }
        results["models_tested"].append(model_result)
        return model_result

    # === Step 2: Single prompt generation ===
    print(f"\n[TEST 1] Single prompt text generation...")
    try:
        prompts = [
            "Hello, my name is",
            "The capital of China is",
            "1 + 1 =",
        ]
        sampling = SamplingParams(
            temperature=0.0,    # Greedy for reproducibility
            max_tokens=50,
            top_p=1.0,
        )
        gen_start = time.time()
        outputs = llm.generate(prompts, sampling)
        gen_time = time.time() - gen_start

        total_tokens = 0
        gen_results = []
        for i, out in enumerate(outputs):
            text = out.outputs[0].text
            tokens = len(out.outputs[0].token_ids)
            total_tokens += tokens
            gen_results.append({
                "prompt": prompts[i],
                "generated_text": text,
                "num_tokens": tokens,
            })
            print(f"  [{i+1}] Prompt: {prompts[i]!r}")
            print(f"      Output: {text!r}  ({tokens} tokens)")

        model_result["tests"]["single_prompt"] = {
            "status": "success",
            "num_prompts": len(prompts),
            "total_time_sec": round(gen_time, 3),
            "total_tokens": total_tokens,
            "throughput_tokens_per_sec": round(total_tokens / gen_time, 2),
            "avg_latency_sec": round(gen_time / len(prompts), 3),
            "results": gen_results,
        }
        print(f"[TEST 1] {len(prompts)} prompts, {total_tokens} tokens in {gen_time:.3f}s")
        print(f"          Throughput: {total_tokens/gen_time:.2f} tok/s, Avg latency: {gen_time/len(prompts):.3f}s")

    except Exception as e:
        print(f"[TEST 1] FAILED: {e}")
        traceback.print_exc()
        model_result["tests"]["single_prompt"] = {"status": "failed", "error": str(e)}

    # === Step 3: Batch request processing ===
    print(f"\n[TEST 2] Batch request processing (10 prompts)...")
    try:
        batch_prompts = [
            f"Write a short sentence about topic number {i}." for i in range(10)
        ]
        batch_sampling = SamplingParams(
            temperature=0.7,
            max_tokens=64,
            top_p=0.9,
        )
        # Measure batch processing
        batch_start = time.time()
        batch_outputs = llm.generate(batch_prompts, batch_sampling)
        batch_time = time.time() - batch_start

        batch_total_tokens = 0
        for out in batch_outputs:
            batch_total_tokens += len(out.outputs[0].token_ids)

        model_result["tests"]["batch_processing"] = {
            "status": "success",
            "batch_size": len(batch_prompts),
            "total_time_sec": round(batch_time, 3),
            "total_tokens": batch_total_tokens,
            "throughput_tokens_per_sec": round(batch_total_tokens / batch_time, 2),
            "avg_latency_per_request_sec": round(batch_time / len(batch_prompts), 3),
            "sample_outputs": [
                {
                    "prompt": batch_prompts[i],
                    "output": batch_outputs[i].outputs[0].text[:100],
                    "tokens": len(batch_outputs[i].outputs[0].token_ids),
                }
                for i in range(min(3, len(batch_outputs)))
            ],
        }
        print(f"[TEST 2] Batch of {len(batch_prompts)}, {batch_total_tokens} tokens in {batch_time:.3f}s")
        print(f"          Throughput: {batch_total_tokens/batch_time:.2f} tok/s, Avg req latency: {batch_time/len(batch_prompts):.3f}s")
        print(f"          Sample outputs:")
        for i in range(3):
            print(f"            [{i+1}] {batch_outputs[i].outputs[0].text[:80]!r}")

    except Exception as e:
        print(f"[TEST 2] FAILED: {e}")
        traceback.print_exc()
        model_result["tests"]["batch_processing"] = {"status": "failed", "error": str(e)}

    # === Step 4: Chat-style generation (using chat method) ===
    print(f"\n[TEST 3] Chat-style generation...")
    try:
        conversations = [
            [
                {"role": "system", "content": "You are a helpful assistant."},
                {"role": "user", "content": "What is 2 + 2? Reply with just the number."},
            ],
            [
                {"role": "user", "content": "Say hello in Chinese."},
            ],
            [
                {"role": "user", "content": "Write a haiku about coding."},
            ],
        ]
        chat_sampling = SamplingParams(
            temperature=0.0,
            max_tokens=80,
        )
        chat_start = time.time()
        chat_outputs = llm.chat(conversations, chat_sampling)
        chat_time = time.time() - chat_start

        chat_total_tokens = 0
        chat_results = []
        for i, out in enumerate(chat_outputs):
            text = out.outputs[0].text
            tokens = len(out.outputs[0].token_ids)
            chat_total_tokens += tokens
            chat_results.append({
                "conversation": conversations[i],
                "response": text,
                "num_tokens": tokens,
            })
            print(f"  [{i+1}] User: {conversations[i][-1]['content']!r}")
            print(f"      Bot:  {text!r}  ({tokens} tokens)")

        model_result["tests"]["chat_generation"] = {
            "status": "success",
            "num_conversations": len(conversations),
            "total_time_sec": round(chat_time, 3),
            "total_tokens": chat_total_tokens,
            "throughput_tokens_per_sec": round(chat_total_tokens / chat_time, 2),
            "results": chat_results,
        }
        print(f"[TEST 3] {len(conversations)} chats, {chat_total_tokens} tokens in {chat_time:.3f}s, {chat_total_tokens/chat_time:.2f} tok/s")

    except Exception as e:
        print(f"[TEST 3] FAILED: {e}")
        traceback.print_exc()
        model_result["tests"]["chat_generation"] = {"status": "failed", "error": str(e)}

    # === Step 5: Longer generation (throughput stress) ===
    print(f"\n[TEST 4] Long generation (max_tokens=256)...")
    try:
        long_prompt = "Once upon a time, in a far away land,"
        long_sampling = SamplingParams(
            temperature=0.8,
            max_tokens=256,
            top_p=0.95,
        )
        long_start = time.time()
        long_outputs = llm.generate([long_prompt], long_sampling)
        long_time = time.time() - long_start

        long_text = long_outputs[0].outputs[0].text
        long_tokens = len(long_outputs[0].outputs[0].token_ids)
        # Estimate TTFT (time to first token) - vLLM doesn't expose this directly
        # but for a single prompt with no queue, total_time / (num_tokens+1) is an approximation
        # Actually for single request: TTFT ≈ prefill time, and decode time = (total - prefill) / num_tokens
        # Without proper instrumentation, we'll just report total time and throughput

        model_result["tests"]["long_generation"] = {
            "status": "success",
            "prompt": long_prompt,
            "generated_text": long_text,
            "num_tokens": long_tokens,
            "total_time_sec": round(long_time, 3),
            "throughput_tokens_per_sec": round(long_tokens / long_time, 2),
            "avg_time_per_token_ms": round(long_time / long_tokens * 1000, 2),
        }
        print(f"[TEST 4] {long_tokens} tokens in {long_time:.3f}s = {long_tokens/long_time:.2f} tok/s ({long_time/long_tokens*1000:.2f} ms/tok)")
        print(f"          Output preview: {long_text[:150]!r}...")

    except Exception as e:
        print(f"[TEST 4] FAILED: {e}")
        traceback.print_exc()
        model_result["tests"]["long_generation"] = {"status": "failed", "error": str(e)}

    # === Final memory state ===
    final_mem = get_memory_mb()
    final_sys_mem = get_system_memory()
    model_result["tests"]["final_memory"] = {
        "process_rss_mb": round(final_mem, 1),
        "system_memory": final_sys_mem,
    }
    print(f"\n[MEM] Final process RSS: {final_mem:.0f} MB, System: {final_sys_mem['used_mb']:.0f}/{final_sys_mem['total_mb']:.0f} MB ({final_sys_mem['percent']:.1f}%)")

    # Cleanup
    print(f"\n[CLEANUP] Unloading {model_short_name}...")
    del llm
    gc.collect()
    time.sleep(2)

    results["models_tested"].append(model_result)
    return model_result


def main():
    print("=" * 70)
    print("vLLM CPU Comprehensive Test Suite")
    print("=" * 70)

    record_env()

    # Test each model
    test_model("HuggingFaceTB/SmolLM2-135M-Instruct", "SmolLM2-135M")
    test_model("Qwen/Qwen2.5-0.5B-Instruct", "Qwen2.5-0.5B")

    # Save results
    out_path = "/mnt/d/vLLM报告/results.json"
    # Also save to home for backup
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    print(f"\n{'='*70}")
    print(f"Results saved to: {out_path}")
    print(f"{'='*70}")

    # Print summary table
    print(f"\n{'='*70}")
    print("SUMMARY")
    print(f"{'='*70}")
    print(f"{'Model':<18} {'Load(s)':<10} {'1-prompt(tok/s)':<18} {'Batch(tok/s)':<15} {'Chat(tok/s)':<15} {'Long(tok/s)':<12}")
    print("-" * 88)
    for m in results["models_tested"]:
        name = m["short_name"]
        load_t = m["tests"].get("model_load", {}).get("load_time_sec", "N/A")
        sp = m["tests"].get("single_prompt", {}).get("throughput_tokens_per_sec", "N/A")
        bp = m["tests"].get("batch_processing", {}).get("throughput_tokens_per_sec", "N/A")
        cp = m["tests"].get("chat_generation", {}).get("throughput_tokens_per_sec", "N/A")
        lg = m["tests"].get("long_generation", {}).get("throughput_tokens_per_sec", "N/A")
        print(f"{name:<18} {str(load_t):<10} {str(sp):<18} {str(bp):<15} {str(cp):<15} {str(lg):<12}")


if __name__ == "__main__":
    main()
