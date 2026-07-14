# ⚡ Spark Landing Kit

**Two DGX Sparks arrive in a box. This repo turns them into a private, OpenAI-compatible inference platform in one day — and can prove every step worked.**

![status](https://img.shields.io/badge/status-awaiting_silicon-orange) ![gates](https://img.shields.io/badge/promotion_gates-G0%E2%80%93G7-blue) ![eval](https://img.shields.io/badge/eval_suite-stdlib_only-green) ![selftest](https://img.shields.io/badge/gate_self--test-passing-brightgreen) ![hardware](https://img.shields.io/badge/target-2%C3%97_DGX_Spark_GB10-76b900) ![license](https://img.shields.io/badge/license-MIT-lightgrey)

Deployment kit for a 2× NVIDIA DGX Spark (GB10) cluster at RealDealCPA:
an OpenAI-compatible LiteLLM gateway on Tailscale fronting three serving lanes —
an always-on **agent brain**, an always-on **code/utility node**, and an
on-demand **cluster lane** that feels like frontier. Operable by one person,
safe for client financial data, and model-agnostic within its size class: any
checkpoint that meets a lane's contract can move in without redesign.

> **Philosophy: gates, not vibes.** Every phase ends with a pass/fail check.
> Nothing serves client work until it passes license → boot-evidence → warm
> decode → behavior → (for long context) needle-at-depth gates. The ecosystem
> is young; the kit assumes things will fail and makes failures cheap and
> diagnosable.

---

## Architecture

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

**Why this shape — the physics.** Decode on GB10 is bandwidth-bound at
273 GB/s per node: a dense 70B crawls at ~2.6 tok/s while an MoE with 3–12B
active parameters runs 30–70 tok/s. So the daily drivers are
small-active-param MoE models, one per node, run *independently* for maximum
aggregate throughput — the pair's real superpower is concurrency
(gpt-oss-120b measured to ~860 tok/s aggregate). The 200G link is a
capability you invoke, not a default state: plain TP=2 can be *slower* than
one node; clustering only buys speed with the full lever stack (4-bit
weights + 4-bit KV + speculative decoding). All 27 field-derived operating
rules live in [`ops/RUNBOOK.md`](ops/RUNBOOK.md).

## The three lanes — what "feels like frontier" honestly means

| Route | Tenant (swappable) | Reality |
|---|---|---|
| `brain` | gpt-oss-120b (MXFP4) | ~55–60 tok/s single-stream, ~1.7k tok/s prefill, huge concurrency headroom. The workhorse for structured/batch dispatch work. |
| `coder` | Qwen3.6-27B-FP8 | 256K context, tool-calling, MTP. Interactive for real repo work; frontier models still plan better — that's what the `frontier` fallback route is for. |
| `fleet` | DeepSeek-V4-Flash DSpark (TP=2) | 50–67 tok/s single-stream, ~182 tok/s aggregate at 6-way, up to **1M advertised** context. Closest thing to frontier feel that runs in the office — *after* it passes your needle tests. Advertised ≠ retrieval-proven; the kit makes you prove it. |
| `frontier` | Claude API (fallback) | One-way: local falls back to frontier, never the reverse. Local models execute; Claude plans. |

Lanes are **contracts**; models are **tenants** ([doc 05](docs/05-MODEL-AGNOSTIC-SLOTS.md)).
Swapping a tenant is one config diff + one gate pass — zero script or doc changes.

## The gate ladder

No lane serves client work, and no route enters the gateway, without its
gates green and evidenced ([doc 03](docs/03-VALIDATION.md)):

```
G0 license → G1 fabric → G2 boot evidence → G3 warm decode
   → G4 behavior suite → G5 needle-at-depth → G6 gateway → G7 dispatch pilot
```

The behavior suite (G4) is the silent-failure catcher: a wrong tool parser
puts calls in `message.content` and every downstream agent breaks *quietly*.
The needle gate (G5) is the honesty enforcer: a booted 1M `max_model_len`
proves memory math, not recall — recall gets proven at the depths a 300-page
workpaper bundle actually needs (200–300K tokens).

## Tested before the hardware exists

The gates themselves are code — so the kit ships a **stdlib-only mock OpenAI
server** and a self-test that rehearses all four gate tools offline, on any
machine, including their failure paths:

```bash
bash eval/selftest.sh
#   PASS smoke passes                         want=pass exit=0
#   PASS bench passes                         want=pass exit=0
#   PASS needle passes                        want=pass exit=0
#   PASS behavior passes                      want=pass exit=0
#   PASS needle catches wrong recall          want=fail exit=1
#   PASS behavior catches broken JSON         want=fail exit=1
#   PASS behavior catches tools-in-content    want=fail exit=1
#   PASS bench dies on 500s                   want=fail exit=1
```

Delivery day must not depend on pip, luck, or untested scripts. The
pre-delivery hardening pass (doc 07, Level 1.5) also caught — before any
hardware could suffer them — a gateway config that couldn't route, an NCCL
bus-bandwidth gate that was 2× optimistic for 2 ranks, and a disk check
looking at the wrong volume. Verified ≠ written.

---

## Quick start

### Day 0 — metal (on each Spark)

```bash
cp config/cluster.env.example config/cluster.env   # edit values first
sudo apt update && sudo apt dist-upgrade -y
sudo fwupdmgr refresh && sudo fwupdmgr upgrade && sudo reboot
# after reboot:
./day0/01-preflight.sh                  # on BOTH nodes
./day0/02-network-fabric.sh --persist   # on BOTH nodes (fabric IPs differ)
./day0/03-nccl-validate.sh              # from Spark A (head)
./day0/04-tailscale.sh                  # optional but recommended
```

Stop if any gate is red. Day 0 problems are cheap; Day 2 problems are
expensive. The full printable runsheet — one checkbox per gate — is
[`ops/CHECKLIST.md`](ops/CHECKLIST.md), and [`ops/PINS.md`](ops/PINS.md)
lists every time-sensitive pin to reverify the week hardware arrives.

### Day 1 — lanes + gateway

```bash
# Spark A:                          # Spark B:
lanes/solo-a-agent-brain/run.sh     lanes/solo-b-code-utility/run.sh
# Gateway (Spark A is fine):
cd gateway && docker compose --env-file ../config/cluster.env up -d
# Validate from anywhere on the tailnet:
eval/smoke.sh http://<gateway>:4000
eval/bench_decode.py  --base-url http://<gateway>:4000/v1 --model brain
eval/behavior_suite.py --base-url http://<gateway>:4000/v1 --model brain
```

### Day 2 — cluster lane

Read [`lanes/cluster-dsv4-fleet/README.md`](lanes/cluster-dsv4-fleet/README.md)
**including the license gate** before downloading a single byte of weights.

| Phase | Gate to proceed |
|---|---|
| **Day 0 — metal** | `day0/01`–`03` all print `PASS` |
| **Day 1 — lanes** | `smoke.sh` green on all routes; decode in range; behavior ≥ thresholds |
| **Day 2 — fleet** | KV pool sane in boot logs; needle passes at *your* depths; behavior passes |
| **Day 3+ — dispatch** | Per-skill eval against ground truth (G7) |

---

## Operational discipline

- **Security:** serving binds localhost/LAN only; the tailnet is the only
  ingress; `.gitignore` blocks `config/cluster.env` so secrets never enter
  git; client documents only touch lanes that passed promotion gates.
- **Reproducibility:** image digests, model revisions, flags, GMU, and NCCL
  env are recorded per lane ([`ops/evidence/`](ops/evidence/) templates); a
  reimaged node returns to serving from this repo + the records alone.
- **Regression policy:** every change type maps to the gate subset it can
  plausibly break ([doc 04](docs/04-REGRESSION.md)); weekly smoke is a
  `systemd` timer away ([`ops/systemd/`](ops/systemd/)).
- **Integrity:** `bash ops/manifest.sh --verify` checks every kit file
  against `docs/MANIFEST.sha256`; regenerate after intentional edits.
- **Agent-maintainable:** long-running work follows the handoff protocol in
  [doc 06](docs/06-HANDOFF-PICKUP.md) — state lives in files
  (`ops/sessions/`) or it doesn't exist. The maintainers of this system are
  as swappable as its models.

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

## Status

**v0.2 + Level 1.5 pre-delivery hardening (2026-07-13).** Everything provable
without silicon is proven; what remains is hardware-gated by definition. The
full ledger — including what is deliberately *not* done yet — is
[`docs/07-DEFINITION-OF-DONE.md`](docs/07-DEFINITION-OF-DONE.md).

The one-line test for "complete": *a new Spark pair, this repo, and the
firm's system of record reproduce the entire platform without the original
conversation existing.*

## Documentation

Start at [`docs/INDEX.md`](docs/INDEX.md) — PRD, architecture, how-to,
validation spec, regression policy, model-agnostic slot contracts, and the
agent handoff protocol, in reading order.
