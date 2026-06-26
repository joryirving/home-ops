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
) -> dict:
    """Measure TTFT, decode window, and tokens via SSE. Returns absolute perf_counter stamps."""
    start = time.perf_counter()
    first_token = 0.0
    tokens = 0
    first = True

    usage_tokens = 0
    async with client.stream(
        "POST",
        f"{base_url}/chat/completions",
        json={
            "model": model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": max_tokens,
            "temperature": temperature,
            "stream": True,
            "stream_options": {"include_usage": True},
            "cache_prompt": False,
        },
        headers={"Authorization": f"Bearer {api_key}"},
    ) as resp:
        async for line in resp.aiter_lines():
            if not line.startswith("data: "):
                continue
            data = line[6:]
            if data.strip() == "[DONE]":
                break
            try:
                chunk = json.loads(data)
            except json.JSONDecodeError:
                continue
            if chunk.get("usage"):
                usage_tokens = chunk["usage"].get("completion_tokens", 0)
            delta = (chunk.get("choices") or [{}])[0].get("delta", {})
            # reasoning models stream think tokens under reasoning_content
            if delta.get("content") or delta.get("reasoning_content"):
                if first:
                    first_token = time.perf_counter()
                    first = False
                tokens += 1

    end = time.perf_counter()
    tokens = usage_tokens or tokens
    ttft = (first_token - start) if not first else (end - start)
    return {
        "ttft": ttft,
        "total_time": end - start,
        "first_token": first_token if not first else end,
        "end": end,
        "tokens": tokens or max_tokens,
    }


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


async def run_round(client, base_url, api_key, model, max_tokens, concurrency):
    """Fire `concurrency` requests at once; return per-request results + batch window."""
    t0 = time.perf_counter()
    results = await asyncio.gather(*[
        measure_latency(client, base_url, api_key, model, PROMPT, max_tokens)
        for _ in range(concurrency)
    ])
    t1 = time.perf_counter()
    return results, t0, t1


def summarize(results, t0, t1):
    """Per-request decode tok/s + system aggregate over the overlapping decode window."""
    per_req = []
    for r in results:
        decode_time = max(r["end"] - r["first_token"], 1e-3)
        per_req.append(r["tokens"] / decode_time)
    total_tokens = sum(r["tokens"] for r in results)
    decode_window = max(r["end"] for r in results) - min(r["first_token"] for r in results)
    aggregate = total_tokens / max(decode_window, 1e-3)
    avg_ttft = sum(r["ttft"] for r in results) / len(results)
    return {
        "per_req_avg": sum(per_req) / len(per_req),
        "per_req_min": min(per_req),
        "per_req_max": max(per_req),
        "aggregate": aggregate,
        "avg_ttft": avg_ttft,
        "wall": t1 - t0,
    }


async def main():
    import argparse

    parser = argparse.ArgumentParser(description="Benchmark concurrent-slot throughput")
    parser.add_argument("--api-key", default="none", help="API key (any value for raw llama-server)")
    parser.add_argument("--base-url", default="http://localhost:8088/v1", help="OpenAI-compatible base URL")
    parser.add_argument("--model", default="self-hosted", help="Model/alias name")
    parser.add_argument("--max-tokens", type=int, default=256, help="Max output tokens per request")
    parser.add_argument("--iterations", type=int, default=2, help="Rounds per concurrency level (averaged)")
    parser.add_argument("--concurrency", type=int, nargs="+", default=[1, 2], help="Concurrency levels to compare")
    args = parser.parse_args()

    print(f"\nBenchmark config:")
    print(f"  Endpoint:  {args.base_url}  (model={args.model})")
    print(f"  Max tokens: {args.max_tokens}   Rounds/level: {args.iterations}")
    print(f"  Prompt: ~{len(PROMPT)//4} tokens   Concurrency levels: {args.concurrency}\n")

    async with httpx.AsyncClient(
        timeout=600.0,
        limits=httpx.Limits(keepalive_expiry=300, max_keepalive_connections=16),
    ) as client:
        summaries = {}
        for c in args.concurrency:
            print(f"{'#'*60}\n# concurrency={c}\n{'#'*60}")
            rounds = []
            for i in range(1, args.iterations + 1):
                results, t0, t1 = await run_round(
                    client, args.base_url, args.api_key, args.model, args.max_tokens, c
                )
                s = summarize(results, t0, t1)
                rounds.append(s)
                print(f"  [{i}/{args.iterations}] per-req(avg)={s['per_req_avg']:.1f}  "
                      f"aggregate={s['aggregate']:.1f} tok/s  TTFT(avg)={s['avg_ttft']:.2f}s")
            summaries[c] = {
                k: sum(r[k] for r in rounds) / len(rounds) for k in rounds[0]
            }

    print(f"\n{'='*72}\n  CONCURRENCY SCALING ({args.model})\n{'='*72}")
    print(f"  {'concurrency':<14}{'per-req tok/s':>16}{'aggregate tok/s':>18}{'TTFT(s)':>12}")
    print("-" * 72)
    base = summaries.get(args.concurrency[0])
    for c in args.concurrency:
        s = summaries[c]
        print(f"  {c:<14}{s['per_req_avg']:>16.1f}{s['aggregate']:>18.1f}{s['avg_ttft']:>12.2f}")
    if base and len(args.concurrency) > 1:
        top = summaries[args.concurrency[-1]]
        slow = (1 - top["per_req_avg"] / base["per_req_avg"]) * 100
        gain = top["aggregate"] / base["aggregate"]
        print("-" * 72)
        print(f"  per-request slowdown at c={args.concurrency[-1]}: {slow:.0f}%")
        print(f"  aggregate throughput gain:    {gain:.2f}x")


if __name__ == "__main__":
    asyncio.run(main())
