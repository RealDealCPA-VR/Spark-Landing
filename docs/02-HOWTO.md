# How-To Guide — operator procedures

Assumes: both Sparks unboxed, on LAN, kit cloned to the same path on both
nodes, `config/cluster.env` filled from the example.

## A. Delivery day (Day 0)

```bash
# 1. On EACH Spark — OS + firmware to floor, then reboot
sudo apt update && sudo apt dist-upgrade -y
sudo fwupdmgr refresh && sudo fwupdmgr upgrade && sudo reboot

# 2. On EACH Spark — gate the metal
./day0/01-preflight.sh                 # must end: 0 fail

# 3. Cable QSFP↔QSFP with the DAC, then on EACH Spark
./day0/02-network-fabric.sh --persist  # link 200000Mb/s, peer ping PASS

# 4. From Spark A only — fabric truth
./day0/03-nccl-validate.sh             # record per-node GID indexes,
                                       # BUSBW ≥ 15 GB/s before any cluster lane
# 5. On EACH Spark (recommended)
./day0/04-tailscale.sh
```

**Stop here if any gate is red.** Day 0 problems are cheap; Day 2 problems
are expensive.

## B. First serve (Day 1)

```bash
# Spark A                     # Spark B
lanes/solo-a-agent-brain/run.sh      lanes/solo-b-code-utility/run.sh
# first model pull is the slow one; watch:
docker logs -f vllm_brain | grep -E "KV cache size|startup"

# Gateway (on Spark A)
cd gateway && docker compose --env-file ../config/cluster.env up -d

# Gates, from any tailnet machine
eval/smoke.sh http://spark-a:4000
eval/bench_decode.py  --base-url http://spark-a:4000/v1 --model brain
eval/bench_decode.py  --base-url http://spark-a:4000/v1 --model coder
eval/behavior_suite.py --base-url http://spark-a:4000/v1 --model brain
eval/behavior_suite.py --base-url http://spark-a:4000/v1 --model coder
```

Record results per doc 03 evidence format. Solo mode is now the resting state.

## C. Cluster lane (Day 2) — condensed

Full procedure with gates: `lanes/cluster-dsv4-fleet/README.md`. Sequence:
license verdict → clone upstream + record commit → fill its env from
`cluster.env` (per-node GID!) → build → stage weights (head download, fabric
rsync) → launch at the **balanced profile** → Gates 2–5 → only then
uncomment `fleet` in `gateway/litellm-config.yaml` and restart gateway.

## D. Daily operations

| Task | Command |
|------|---------|
| Health check | `eval/smoke.sh` |
| Switch to cluster mode | `ops/swap-lane.sh cluster-dsv4` → launch per lane README |
| Back to daily mode | `ops/swap-lane.sh solo` |
| Everything off | `ops/swap-lane.sh down` |
| Read a lane's logs | `docker logs -f vllm_brain` / `vllm_coder` |
| Throughput spot-check | `eval/bench_decode.py --model <route>` (never trust a cold first request) |
| Free stuck launches | `docker rm -f <name>` on BOTH nodes, drop caches, retry |

## E. Common changes (each triggers doc 04 regression sets)

**Swap a lane's model (tenant):** follow doc 05 §4 — intake checklist,
shadow port, gates, promote via config, archive old tenant record.

**Bump a vLLM image:** change the tag in `cluster.env`, restart the lane,
run G2–G4 (G5 too if the lane serves long context). Record tag + digest.

**Change GMU / flags:** bracket GMU in 0.005 steps if boot is marginal;
re-run G2–G3; note the winning value in the lane's hermes-brain page.

**Add a utility service on B (Whisper, embeddings):** start it on its own
port, add a gateway route, smoke it. Keep it out of the coder's vLLM
process.

## F. Troubleshooting index (symptom → RUNBOOK rule)

| Symptom | Rule |
|---------|------|
| 100GB model takes forever to load | 8 (mmap) |
| Boot OOM / KV pool tiny | 7 (GMU bracket), 10 (desktop session) |
| `exec-script.sh: No such file` on multi-node launch | 14 (stale containers) |
| Tool calls arrive as plain text | 23 (parser ↔ emission format) |
| Client SDK errors on odd params | 24 (`drop_params`) |
| Hybrid-attention model misbehaves | 22 (V2 runner off) |
| Cluster slower than single node | 4 (lever stack), 12 (NCCL per class) |
| Numbers changed after "harmless" tweak | 18 (rebenchmark rule) |
