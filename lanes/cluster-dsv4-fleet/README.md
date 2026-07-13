# Cluster lane — DeepSeek-V4-Flash DSpark (fleet mode)

The on-demand lane that makes the pair feel frontier: TP=2 across both Sparks,
DSpark speculative decoding, NVFP4 KV on sparse MLA. Community-validated at
50-67 tok/s single-stream and ~182 tok/s aggregate at 6-way concurrency with a
1M-token *advertised* ceiling.

**This lane replaces both solo lanes while it runs** (it owns both GPUs).
Use `ops/swap-lane.sh cluster-dsv4` / `ops/swap-lane.sh solo` to switch.

We deliberately do **not** vendor the recipe here. It's a fast-moving,
deep-dependency stack (vLLM overlay → DSpark integration → Keys' concurrency
patch, all pinned); vendoring a snapshot would rot silently. Instead: clone
upstream at a commit you record, and run OUR gates on top.

## Gate 0 — license (do this before downloading a single byte)

Read the DeepSeek-V4-Flash model card license in full. DeepSeek's prior
releases were MIT, but verify **this** checkpoint — the M3 lesson applies
(MiniMax-M3 weights carry non-commercial constraints, which is why M3 is not a
lane in this kit). Nothing with unresolved commercial terms touches client
work or anything RealDealCPA-shaped. Log the verdict + date in hermes-brain.

## Gate 1 — fabric

`day0/03-nccl-validate.sh` must have passed. Record the per-node
`NCCL_IB_GID_INDEX` values — the recipe's `.env` needs them and they may
differ between your two nodes.

## Build + launch (upstream, pinned)

```bash
git clone https://github.com/tonyd2wild/DeepSeek-v4-Flash-DSpark-1M-NVFP4-KV-2x-DGX-Spark dsv4-lane
cd dsv4-lane && git rev-parse HEAD | tee ../PINNED_COMMIT.txt
cp .env.dspark.example .env.dspark
# fill from ../../config/cluster.env: WORKER_HOST, MASTER_ADDR (fabric IP of A),
# NCCL_IB_HCA, NCCL_SOCKET_IFNAME (fabric iface), per-node NCCL_IB_GID_INDEX, HF_CACHE
./build-dspark-vllm-runtime.sh
./prepare-dspark-model-cache.sh          # stage on A, rsync to B over fabric
./start-deepseek-v4-flash-dspark.sh      # worker-first launch; API on :8888
```

**Profile: start at 500K / max_num_seqs=4** — the balanced middle of the
author's own ladder, and it matches realistic dispatch parallelism and your
document sizes. The 1M/6 profile is for later, after gates pass. The KV pool
is shared on demand (ceilings, not reservations): the real constraint is
`sum(live tokens across active requests) <= pool (~1.9M NVFP4 tokens)`.

## Gate 2 — boot evidence

```bash
curl -fsS http://127.0.0.1:8888/v1/models | grep max_model_len
docker compose --env-file .env.dspark -f docker-compose.dspark.yml logs vllm-dspark \
  | grep -E "GPU KV cache size|Maximum concurrency"
```
KV pool should be ~1.9-2.0M tokens. If GMU knife-edges: bracket in 0.005 steps
(the reference deployment landed on 0.929 after 0.93 failed by 0.02 GiB).

## Gate 3 — burn the warmup, then measure

Never benchmark the first request (JIT warmup). Then:

```bash
../../eval/bench_decode.py --base-url http://127.0.0.1:8888/v1 --model default
```
Expect ~50-67 tok/s single-stream. Structured JSON tends to run FASTER than
prose here — spec-decode acceptance is higher on predictable tokens — so your
extraction workloads sit on the favorable side.

## Gate 4 — behavior suite

```bash
../../eval/behavior_suite.py --base-url http://127.0.0.1:8888/v1 --model default
```
Schema-compliance and format gates apply to this lane like any other — more
so, since the KV path is experimental (Stage C padded NVFP4 envelope).

## Gate 5 — needle tests at YOUR depths (non-negotiable)

The 1M figure is advertised max_model_len with speed probes — **not** a
retrieval/correctness benchmark. Before any deep-context client work:

```bash
../../eval/needle.py --base-url http://127.0.0.1:8888/v1 --model default \
  --context-tokens 100000 --depths 10,50,90
../../eval/needle.py ... --context-tokens 300000 --depths 10,50,90
```
Pass = exact recall at every depth you intend to use. A 300-page workpaper
bundle is ~200-300K tokens; test there, not at 1M, unless you'll use 1M.

## Wire into the gateway

Only after Gates 0-5: uncomment the `fleet` block in
`gateway/litellm-config.yaml` and `docker compose restart` the gateway.
Rebenchmark whenever you change sampling, batching, context target, or any
`VLLM_DSPARK_*` / projection flag — results are configuration-specific.
