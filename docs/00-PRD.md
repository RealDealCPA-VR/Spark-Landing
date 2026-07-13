# PRD — Private Inference Platform on 2× DGX Spark

**Owner:** VR · **Version:** 0.2 · **Date:** 2026-07-13 · **Status:** Approved for build

## 1. Problem

VR Tax & Consulting runs agentic automation (vr-dispatch, Iron Jarvis, skills
pipelines) over sensitive client financial data. Cloud frontier models are the
quality ceiling but are metered, rate-limited, and involve data egress
decisions per workload. The existing RTX 6000 Ada (48GB) caps model class.
Two DGX Sparks (GB10, 128GB unified each, 200G interconnect) are inbound and
must become a dependable inference platform — not a science project.

## 2. Product

A self-hosted, OpenAI-compatible inference platform with three serving lanes
behind one gateway, operable by one person, safe for client data, and
**model-agnostic within its size class**: any checkpoint meeting a lane's
contract (doc 05) can be promoted into it without redesign.

## 3. Users

- **VR** — operator and primary power user (coding sessions, planning).
- **vr-dispatch agents** — programmatic consumers; highest request volume;
  structured outputs and tool calls.
- **Long-running coding agents** (Claude Code / local) — build, extend, and
  maintain the platform itself under the handoff protocol (doc 06).
- **Staff (later)** — chat access via a web UI on the tailnet.

## 4. Goals

| ID | Goal | Metric |
|----|------|--------|
| G1 | Data sovereignty for firm workloads | PII-bearing pipelines runnable with zero external egress |
| G2 | Frontier-feel available locally | Cluster lane passes needle at working depths (200–300K tok) at ≥30 tok/s |
| G3 | Fleet backbone for automation | ≥300 tok/s aggregate on the batch lane at 8-way concurrency |
| G4 | One endpoint, many models | All consumers use gateway routes (`brain`/`coder`/`fleet`/`frontier`); zero hardcoded model URLs in skills |
| G5 | Operable and reproducible | Delivery→serving in ≤1 day via gates; every lane's exact config recoverable from hermes-brain |
| G6 | Model-agnostic | Swapping a lane tenant touches env/config only; gates, scripts, docs unchanged |

## 5. Non-goals (v1)

Training/fine-tuning on the Sparks (Ada's job); public or multi-tenant
serving; productized RealDealCPA.ai packaging (informed by, not built by,
this project); Kubernetes or any orchestration heavier than docker + scripts;
five-nines availability (this is a firm tool, not a carrier).

## 6. Functional requirements

- FR-1 Gateway exposes OpenAI-compatible `/v1` on the tailnet; routes by
  model name; falls back local→frontier, never frontier→local.
- FR-2 Two operating modes: **solo** (independent lanes on A and B, default)
  and **cluster** (both GPUs to one fleet lane, on demand); mode switch is
  one command (`ops/swap-lane.sh`) and is safe to run repeatedly.
- FR-3 Every lane is health-checkable (`/v1/models`), benchmarkable
  (`eval/bench_decode.py`), and gate-testable (docs 03) without touching
  other lanes.
- FR-4 Lane tenancy is declared in config, not code (doc 05 swap procedure).
- FR-5 Evidence of every gate run is recordable in hermes-brain in the
  formats given in doc 03.
- FR-6 Agent maintenance sessions follow doc 06; state survives context loss.

## 7. Non-functional requirements

- NFR-1 **Security:** serving binds localhost/LAN only; reachability is
  tailnet-only; no credentials in repo (env-file pattern); client documents
  only touch lanes that passed promotion gates.
- NFR-2 **Licensing:** commercial-use verification (Gate 0) precedes any
  weight download; verdicts logged with date.
- NFR-3 **Performance floors** are lane-contract properties (doc 05), not
  model properties. Physics envelope: 273 GB/s/node ⇒ MoE-only on Sparks,
  active params ≤ ~12B for interactive lanes.
- NFR-4 **Reproducibility:** image tags + digests, model revisions, flags,
  GMU, and NCCL env recorded per lane (RUNBOOK rule 27).
- NFR-5 **Recoverability:** any node reimaged from scratch returns to
  serving using only this repo + hermes-brain records + weight re-stage.

## 8. Constraints & assumptions

GB10 aarch64/sm_121 (community images required); ~121 GiB usable/node;
bandwidth-bound decode; ecosystem drifts monthly (pins rot — regression doc
exists for this reason); single operator; Ada box remains for dense ≤32B and
fine-tuning; Tailscale already in use.

## 9. Risks

| Risk | Mitigation |
|------|-----------|
| Pinned refs/images rot before delivery | Reverify pins on arrival (INDEX receipt note); regression triggers (doc 04) |
| Cluster lane's experimental KV path misbehaves at depth | Needle gate at working depths is mandatory, 1M treated as advertised only |
| Checkpoint swap silently breaks tool calls | Behavior suite tool gate is blocking (doc 03, G4) |
| License terms block commercial use late | Gate 0 ordering: license before download |
| Operator becomes single point of knowledge | This docs package + hermes-brain mirror + handoff protocol |

## 10. Success = Definition of Done, doc 07.
