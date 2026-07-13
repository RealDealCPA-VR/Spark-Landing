#!/usr/bin/env python3
"""bench_decode.py — single-stream decode tok/s, warmup-aware. Stdlib only.

Rule this encodes: NEVER benchmark the first request. JIT-compiled kernel
paths (b12x etc.) pay ~60s on first touch; cold numbers are lies.

Usage:
  eval/bench_decode.py --base-url http://gw:4000/v1 --model brain
  eval/bench_decode.py --base-url http://127.0.0.1:8888/v1 --model default --runs 5
"""
import argparse, json, statistics, time, urllib.request

def chat(base, model, prompt, max_tokens, temperature=0.0, timeout=600):
    req = urllib.request.Request(
        f"{base.rstrip('/')}/chat/completions",
        data=json.dumps({
            "model": model, "temperature": temperature, "max_tokens": max_tokens,
            "messages": [{"role": "user", "content": prompt}],
        }).encode(),
        headers={"Content-Type": "application/json"})
    t0 = time.time()
    with urllib.request.urlopen(req, timeout=timeout) as r:
        body = json.loads(r.read())
    dt = time.time() - t0
    toks = (body.get("usage") or {}).get("completion_tokens")
    return toks, dt, body

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--gen-tokens", type=int, default=256)
    ap.add_argument("--runs", type=int, default=3)
    a = ap.parse_args()

    print(f"== bench {a.model} @ {a.base_url} ==")
    print("  warmup (uncounted)...")
    chat(a.base_url, a.model, "Write one sentence about ledgers.", 64)

    prompt = ("Write a detailed, plain-prose explanation of double-entry "
              "bookkeeping for a new staff accountant. No lists.")
    rates = []
    for i in range(a.runs):
        toks, dt, _ = chat(a.base_url, a.model, prompt, a.gen_tokens)
        if not toks:
            print("  WARN  server returned no usage.completion_tokens; timing only")
            toks = a.gen_tokens
        r = toks / dt
        rates.append(r)
        print(f"  run {i+1}: {toks} tok in {dt:.2f}s -> {r:.1f} tok/s")
    print(f"  mean {statistics.mean(rates):.1f} tok/s"
          + (f"  (stdev {statistics.stdev(rates):.1f})" if len(rates) > 1 else ""))
    print("  reference (single-stream): brain ~50-60 | coder ~15-25 under load,"
          " higher unloaded | fleet ~50-67. Investigate large misses before"
          " wiring dispatch; re-run after ANY config change.")

if __name__ == "__main__":
    main()
