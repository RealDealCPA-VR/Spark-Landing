# RUNBOOK — GB10 pair operating rules

The distilled field knowledge behind this kit. Sources: NVIDIA's Spark
guidance, the eugr/a3refaat/tonyd2wild vLLM-on-Spark lineage, Spark Arena
community benchmarks, and validated deployment writeups (as of 2026-07-13).
When something here conflicts with what your hardware does: your hardware
wins — update this file. Mirror it into hermes-brain.

## Model policy

1. **MoE with small active params, always.** Decode is bandwidth-bound at
   273 GB/s per node. Dense 70B ≈ 2.6 tok/s; dense 31B ≈ 3.7 tok/s. MoE with
   3-12B active runs 30-70 tok/s. No dense model >~10B serves from a Spark.
2. **Dense ≤32B belongs on the Ada** (3.5x the bandwidth). The qwen3:32b
   intake classifier stays there.
3. **The pair's superpower is batch.** Single-stream ~33-60 tok/s, but
   throughput scales near-linearly with concurrency (gpt-oss-120b measured
   to ~860 tok/s aggregate). Shape firm workloads as concurrent jobs.
4. **Clustering buys capacity by default, speed only with the full lever
   stack** (4-bit weights + 4-bit KV + speculative decoding). Plain TP=2 can
   be SLOWER than one node (llama.cpp RPC measured 47 vs 57 tok/s on
   gpt-oss-120b). Cluster via vLLM/SGLang with NCCL over RoCE, never RPC.
5. **Speculative decode throughput is workload-dependent** — acceptance is
   higher on predictable tokens, so structured JSON runs faster than prose.
   Benchmark with YOUR workload shape.
6. **License gate before weights download.** MiniMax-M3: non-commercial
   constraints — not for client work. Verify every checkpoint's card; log
   verdict + date in hermes-brain. Commercial firm rules apply everywhere.

## Memory

7. **GMU knife-edge procedure:** when a boot OOMs or the KV pool comes up
   short, bracket gpu-memory-utilization in **0.005 steps** and record the
   winner per lane. (Reference case: 0.93 failed by 0.02 GiB; 0.929 booted
   with ~100 MB margin.) Boot state matters — drop page caches first:
   `sync && echo 3 | sudo tee /proc/sys/vm/drop_caches`.
8. **mmap is slow on Spark.** vLLM: `--load-format fastsafetensors`.
   llama.cpp: `--no-mmap`. Without these, 100GB+ loads take many minutes.
9. **KV knobs are ceilings, not reservations.** Pool is shared on demand:
   `sum(live tokens across active requests) <= pool`. max_model_len caps one
   request; max_num_seqs caps concurrency; vLLM never pre-allocates
   seqs × len. Size fleets on real traffic, not worst case.
10. **Desktop sessions eat unified memory** (Xorg + browser can burn 1-2 GB
    and cause swapping at the margin). Serve headless.

## Cluster ops

11. **Per-node GID indexes can differ** (3 vs 5 observed on one pair). Detect
    per node in day0/03; never copy one node's NCCL env to the other blind.
12. **NCCL tuning is model-class-dependent.** `NCCL_PROTO=LL` gained on a 32B
    dense stream and LOST 5-9% on a 428B MoE on the same fabric. A/B per
    deployment; never copy tunings across model sizes.
13. **Weight staging:** download once on the head, `rsync` to the worker over
    the fabric (~4 min for 224GB vs a second internet download).
14. **Stale containers eat launches.** After any aborted multi-node start:
    `docker rm -f <name>` on BOTH nodes before retrying. Symptom:
    `exec-script.sh: No such file`.
15. **Pinned refs rot.** Vendored community recipes have died on unreachable
    git refs and on dependency drift (a patch's anchor already upstreamed).
    Record the exact commit you deployed; expect to patch on rebuild.
16. **Worker-first startup** for multi-node `mp` backend launches.

## Benchmarking & promotion

17. **Never benchmark the first request** — it pays JIT warmup (~60s on b12x
    paths). bench_decode.py burns one for you.
18. **Rebenchmark after ANY change** to sampling, batching, context target,
    KV dtype, projection/scheduler flags, or image tag. Results are
    configuration-specific, and partial-flag folklore doesn't reproduce.
19. **Promotion gates for every lane, in order:** license → boot evidence
    (KV pool + max_model_len in logs) → warm decode in expected range →
    behavior suite (schema / adherence / tool channel) → needle-at-depth for
    any long-context claim → only then wire into the gateway/dispatch.
20. **Advertised context ≠ retrieval.** A booted 1M max_model_len with speed
    probes proves memory math, not recall. needle.py at YOUR working depths
    (workpaper bundle ≈ 200-300K tokens) is the gate.
21. **Behavior regresses before capability** on compressed/pruned/spec-decoded
    checkpoints — schema discipline, tool-call validity, instruction
    following under long system prompts, refusal calibration in both
    directions. That's why behavior_suite.py runs on every checkpoint swap,
    not just new model families.

## Engine quirks (July 2026)

22. **vLLM V2 model runner breaks hybrid-attention models** (Qwen3.5/3.6,
    MiniMax M2 family, Mamba/GDN). Force `VLLM_USE_V2_MODEL_RUNNER=0` on
    those lanes.
23. **Tool parsers map to emission formats, not model families**
    (e.g. `qwen3_xml`). The failure is silent: the call lands in
    message.content. behavior_suite.py's tool gate exists for this.
24. **`drop_params: true` in LiteLLM is load-bearing.** Client SDKs pass
    divergent reasoning params; upstreams reject unknowns; without it,
    failures masquerade as model bugs.
25. **Bind serving to localhost/LAN; reach it over Tailscale.** Exposing a
    vLLM port beyond the tailnet is a deliberate decision, made never.

## Security & data

26. Client documents flow only to lanes that passed promotion gates, on
    hardware you own, reachable only on the tailnet. The frontier fallback
    route is for planning/hard reasoning — keep PII-heavy extraction on
    local lanes or scrub before fallback, consistent with firm policy.
27. Record in hermes-brain per lane: image tag + digest, model revision,
    flags, GMU, NCCL env, gate results + dates. Reproducibility is a feature
    you build, not a property you hope for.
