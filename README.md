# VR Spark Landing Kit — v0.2 (2026-07-13)

Deployment kit for a 2× NVIDIA DGX Spark (GB10) cluster at VR Tax & Consulting.
Target end state: an OpenAI-compatible gateway on Tailscale fronting three lanes —
an always-on agent brain, an always-on code/utility node, and an on-demand
cluster lane that feels like frontier.

**Philosophy: gates, not vibes.** Every phase ends with a pass/fail check.
Nothing gets wired into vr-dispatch until it passes smoke + behavior + (for
long context) needle tests. The ecosystem is young; the kit assumes things
will fail and makes failures cheap and diagnosable.

---

## Architecture (as agreed)

```
                        Tailscale
                            │
                   ┌────────┴────────┐
                   │  LiteLLM :4000  │   ← single OpenAI-compatible endpoint
                   │  (gateway box   │      routes by model name, falls back
                   │   or Spark A)   │      to Claude API for frontier tasks
                   └───┬───────┬─────┘
        model=brain    │       │    model=coder / utility
                       │       │
              ┌────────┴──┐ ┌──┴────────┐
              │  SPARK A  │ │  SPARK B  │      RTX 6000 Ada box stays as-is:
              │ gpt-oss-  │ │ Qwen3.6-  │      dense ≤32B, latency-sensitive,
              │ 120b :8000│ │ 27B :8001 │      fine-tuning, intake classifier.
              │           │ │ +whisper  │
              └─────┬─────┘ └─────┬─────┘
                    └──── QSFP ───┘
                    200G RoCE, direct DAC
                    (dormant until a cluster lane runs)

CLUSTER LANE (on demand, replaces both solo lanes while active):
  DeepSeek-V4-Flash DSpark, TP=2, NVFP4 KV — profile 500K ctx / 4 seqs
  (tonyd2wild recipe; see lanes/cluster-dsv4-fleet/)
```

Why this shape: decode on GB10 is bandwidth-bound (273 GB/s), so the daily
drivers are small-active-param MoE models, one per node, run independently for
maximum aggregate throughput. The 200G link is a capability you invoke, not a
default state. Full reasoning lives in `ops/RUNBOOK.md`.

---

## Phases

| Phase | What happens | Gate to proceed |
|-------|--------------|-----------------|
| **Day 0 — metal** | Unbox, update firmware/OS, cable QSFP, static fabric IPs, validate NCCL once, Tailscale | `day0/01`–`03` all print `PASS` |
| **Day 1 — lanes** | Solo lane A (brain) and B (coder) up, gateway up | `eval/smoke.sh` green on all routes; `bench_decode.py` in expected range; `behavior_suite.py` ≥ thresholds |
| **Day 2 — fleet** | Cluster lane build + validation, wire into gateway as `fleet` | Boot-log KV pool sane; needle tests pass at your real depths; behavior suite passes |
| **Day 3+ — dispatch** | Point vr-dispatch at the gateway, migrate skills | Per-skill eval against ground truth |

## Quick start (Day 0, on each Spark)

```bash
cp config/cluster.env.example config/cluster.env   # edit values first
sudo apt update && sudo apt dist-upgrade -y
sudo fwupdmgr refresh && sudo fwupdmgr upgrade && sudo reboot
# after reboot:
./day0/01-preflight.sh          # on BOTH nodes
./day0/02-network-fabric.sh --persist   # on BOTH nodes (fabric IPs differ)
./day0/03-nccl-validate.sh      # from Spark A (head)
./day0/04-tailscale.sh          # optional but recommended
```

## Day 1 (lanes + gateway)

```bash
# Spark A:
lanes/solo-a-agent-brain/run.sh
# Spark B:
lanes/solo-b-code-utility/run.sh
# Gateway box (Spark A is fine):
cd gateway && docker compose --env-file ../config/cluster.env up -d
# Validate from anywhere on the tailnet:
eval/smoke.sh http://<gateway>:4000
eval/bench_decode.py --base-url http://<gateway>:4000/v1 --model brain
eval/behavior_suite.py --base-url http://<gateway>:4000/v1 --model brain
```

## Day 2 (cluster lane)

Read `lanes/cluster-dsv4-fleet/README.md` **including the license gate** before
downloading any weights.

---

## What "feels like frontier" honestly means here

- `brain` (gpt-oss-120b, MXFP4): ~55–60 tok/s single-stream, ~1.7k tok/s
  prefill, huge concurrency headroom. This is your workhorse.
- `coder` (Qwen3.6-27B-FP8): 256K context, tool-calling, MTP. Interactive for
  real repo work; frontier models still plan better — that's what the
  `frontier` fallback route is for.
- `fleet` (DeepSeek-V4-Flash, cluster): 50–67 tok/s single-stream, ~182 tok/s
  aggregate at 6-way, up to 1M advertised context. Closest thing to frontier
  feel that runs in your office — *after* it passes your needle tests. The 1M
  number is advertised, not retrieval-proven; the kit makes you prove it.

Local models execute; Claude plans. Route accordingly and this rig will feel
frontier where it matters and stay honest where it doesn't.

## Repo map

```
config/    cluster.env.example — every host/IP/token in one place
day0/      preflight, fabric, NCCL validation, tailscale
lanes/     one directory per serving lane; scripts are idempotent
gateway/   LiteLLM compose + config (drop_params: true is load-bearing)
eval/      smoke, decode benchmark, needle-at-depth, behavior suite
           + mock_openai_server.py / selftest.sh — rehearse all four gates offline
ops/       RUNBOOK.md (the gotcha compendium), swap-lane.sh, PINS.md (reverify
           pins on arrival), CHECKLIST.md (printable delivery runsheet),
           evidence/ templates, systemd/ weekly smoke, sessions/ (doc 06 state)
docs/      the docs package 00–07 — start at docs/INDEX.md
.gitignore blocks config/cluster.env — secrets never enter git
```

## Documentation

Full docs package in `docs/` — start at `docs/INDEX.md`. Session protocol
for agent work lives in `docs/06-HANDOFF-PICKUP.md`; state files in
`ops/sessions/`.
