#!/usr/bin/env python3
"""Benchmark llama.cpp with partial GPU offload to find optimal config."""

import asyncio
import time
import json
import httpx


async def measure_latency(
    client: httpx.AsyncClient,
    base_url: str,
    api_key: str,
    model: str,
    prompt: str,
    max_tokens: int,
    temperature: float = 0.1,
) -> tuple[float, float]:
    """Measure TTFT and total time via SSE."""
    start = time.perf_counter()
    ttft = 0.0
    first = True

    resp = await client.post(
        f"{base_url}/chat/completions",
        json={
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": max_tokens,
            "temperature": temperature,
            "stream": True,
        },
        headers={"Authorization": f"Bearer {api_key}"},
    )

    async for line in resp.aiter_lines():
        if not line.startswith("data: "):
            continue
        data = line[6:]
        if data.strip() == "[DONE]":
            break
        try:
            chunk = json.loads(data)
            if first:
                ttft = time.perf_counter() - start
                first = False
        except json.JSONDecodeError:
            continue

    total_time = time.perf_counter() - start
    return ttft, total_time


# Large prompt for meaningful prefill measurement
PROMPT = (
    "Write an extensive technical analysis of distributed systems architecture for serving large language models at scale. "
    "Cover the following topics in detail:\n\n"
    "1. Model sharding strategies: tensor parallelism, pipeline parallelism, and sequence parallelism. "
    "Explain how each approach partitions the model workload across multiple GPUs and the communication overhead involved.\n\n"
    "2. KV cache management: techniques for optimizing key-value cache memory usage including PagedAttention, "
    "quantization, eviction policies, and cross-attention optimization. Discuss the tradeoffs between memory efficiency "
    "and generation quality.\n\n"
    "3. Request scheduling and batching: dynamic batching strategies, continuous batching, priority queues, "
    "and how to maximize GPU utilization while minimizing latency tail percentiles. Include discussion of "
    "speculative decoding and its impact on throughput.\n\n"
    "4. Serving infrastructure: model loading strategies, warm pools, autoscaling policies, and the role of "
    "request routing in distributed LLM serving. Compare monolithic vs microservice architectures for model serving.\n\n"
    "5. Memory optimization: techniques like quantization (INT8, INT4, FP8), low-rank adaptation (LoRA) for "
    "multi-tenant serving, and speculative decoding. Discuss the accuracy-throughput tradeoffs of each approach.\n\n"
    "Provide concrete examples, mathematical formulations where relevant, and reference real-world systems like "
    "vLLM, TGI, and TensorRT-LLM."
)


async def benchmark_config(
    api_key: str,
    litellm_base_url: str,
    model: str,
    max_tokens: int,
    iterations: int,
):
    """Benchmark a single model/config."""
    print(f"\n{'#'*60}")
    print(f"# {model}")
    print(f"{'#'*60}")

    async with httpx.AsyncClient(
        timeout=600.0,
        limits=httpx.Limits(
            keepalive_expiry=300,
            max_keepalive_connections=5,
        ),
    ) as client:
        results = []
        for i in range(1, iterations + 1):
            print(f"  [{i}/{iterations}] Request ({max_tokens} tokens)...", end=" ", flush=True)
            ttft, total_time = await measure_latency(
                client, litellm_base_url, api_key, model, PROMPT, max_tokens
            )
            results.append({"ttft": ttft, "total_time": total_time})
            
            decode_time = max(total_time - ttft, 0.001)
            tps = max_tokens / decode_time if decode_time > 0 else 0
            print(f"TTFT={ttft:.2f}s  Decode={tps:.1f} tok/s  Total={total_time:.1f}s")

    first_ttft = results[0]["ttft"] if results else 0
    cached_ttfts = [r["ttft"] for r in results[1:]] if len(results) > 1 else []
    avg_cached_ttft = sum(cached_ttfts) / len(cached_ttfts) if cached_ttfts else 0
    wall_time = sum(r["total_time"] for r in results)

    print(f"\n{'-'*60}")
    print(f"  {model}")
    print(f"{'-'*60}")
    print(f"  First TTFT (prefill):     {first_ttft:.3f}s")
    if cached_ttfts:
        print(f"  Cached TTFT (avg):        {avg_cached_ttft:.3f}s")
        print(f"  Prefill overhead:         ~{first_ttft - avg_cached_ttft:.1f}s per request")
    print(f"  Wall time:                {wall_time:.1f}s")

    return {
        "model": model,
        "first_ttft": first_ttft,
        "cached_ttft": avg_cached_ttft if cached_ttfts else first_ttft,
        "wall_time": wall_time,
    }


async def main():
    import argparse

    parser = argparse.ArgumentParser(description="Benchmark partial GPU offload")
    parser.add_argument("--api-key", required=True, help="LiteLLM API key")
    parser.add_argument("--litellm-url", default="https://litellm.jory.dev/v1", help="LiteLLM base URL")
    parser.add_argument("--max-tokens", type=int, default=512, help="Max output tokens")
    parser.add_argument("--iterations", type=int, default=3, help="Iterations per model")
    args = parser.parse_args()

    print(f"\nBenchmark config:")
    print(f"  Max output tokens: {args.max_tokens}")
    print(f"  Iterations: {args.iterations}")
    print(f"  Prompt: ~{len(PROMPT)//4} tokens (long)\n")
    print("NOTE: To test partial offload, you need to update the HelmRelease --n-gpu-layers")
    print("      value and redeploy, then run this script with the same model name.\n")

    # Run both models
    all_results = []
    for model_name in ["intel", "ryzen"]:
        result = await benchmark_config(
            api_key=args.api_key,
            litellm_base_url=args.litellm_url,
            model=model_name,
            max_tokens=args.max_tokens,
            iterations=args.iterations,
        )
        all_results.append(result)

    # Summary
    print(f"\n{'='*80}")
    print(f"  COMPARISON: FULL GPU OFFLOAD")
    print(f"{'='*80}")
    
    models = [r["model"] for r in all_results]
    print(f"\n{'Metric':<35}", end="")
    for m in models:
        print(f" {m:>25}", end="")
    print()
    print("-" * 80)

    rows = [
        ("First TTFT - prefill (s)", lambda r: f"{r['first_ttft']:.3f}"),
        ("Cached TTFT - decode (s)", lambda r: f"{r['cached_ttft']:.3f}"),
        ("Wall time (s)", lambda r: f"{r['wall_time']:.1f}"),
    ]

    for label, fn in rows:
        print(f"  {label:<35}", end="")
        for r in all_results:
            print(f" {fn(r):>25}", end="")
        print()

    print(f"\nTo test partial offload on llama-ryzen:")
    print(f"  1. Edit kubernetes/apps/base/llm/litellm/llama-ryzen/helmrelease.yaml")
    print(f"  2. Change --n-gpu-layers from 99 to a lower value (e.g., 50, 30, 10)")
    print(f"  3. Commit and wait for Flux to deploy")
    print(f"  4. Re-run this benchmark")
    print(f"\nSuggested configs to test:")
    print(f"  --n-gpu-layers 99   (current - everything on GPU)")
    print(f"  --n-gpu-layers 50   (half on GPU, half on CPU)")
    print(f"  --n-gpu-layers 20   (mostly CPU)")
    print(f"  --n-gpu-layers 0    (all CPU - baseline)")


if __name__ == "__main__":
    asyncio.run(main())
