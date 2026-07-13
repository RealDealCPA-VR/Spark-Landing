# Architecture — spark-landing-kit

## 1. Topology

```
                                TAILNET (only ingress)
                                        │
                              ┌─────────┴──────────┐
                              │  LiteLLM gateway   │ :4000
                              │  routes by name:   │
                              │  brain│coder│fleet │──────────► Claude API
                              └───┬──────────┬─────┘   frontier   (fallback,
                     model=brain  │          │  model=coder        one-way)
                          ┌───────┴───┐  ┌───┴───────┐
                          │  SPARK A  │  │  SPARK B  │
              solo mode:  │ BRAIN slot│  │ CODER slot│
                          │   :8000   │  │   :8001   │
                          │           │  │ +UTILITY  │
                          └─────┬─────┘  └─────┬─────┘
                                └── QSFP DAC ──┘
                                200G RoCE fabric (192.168.100.0/24)
                                dormant in solo mode
          cluster mode:  ┌─────────────────────────────┐
                         │  FLEET slot  (TP=2)  :8888  │  replaces both solo
                         └─────────────────────────────┘  lanes while active

          adjacent:      RTX 6000 Ada box — dense ≤32B, latency-sensitive,
                         fine-tuning, intake classifier. Unchanged by this kit.
```

## 2. Planes

- **LAN plane** (10GbE RJ45): node management, gateway↔lane traffic,
  weight downloads.
- **Fabric plane** (QSFP, static IPs, MTU 9000): NCCL/RDMA for cluster
  lanes + weight rsync between nodes. Nothing else rides it.
- **Tailnet plane:** the only path clients use. Serving never binds beyond
  localhost/LAN.

## 3. Components

| Component | Placement | Role |
|-----------|-----------|------|
| vLLM (per lane) | Spark A / B / both | Engine. Community aarch64/sm_121 images |
| LiteLLM | Spark A (or any always-on box) | Single endpoint, routing, `drop_params`, fallbacks |
| Lane scripts | `lanes/*/run.sh` | Idempotent start of one slot's tenant |
| swap-lane.sh | head node | Mode transitions with clean teardown on BOTH nodes |
| Eval suite | anywhere on tailnet | Gates (doc 03) — the model-agnostic enforcement layer |
| hermes-brain | existing | System of record for gate evidence, lane configs, decisions |
| vr-dispatch | existing | Consumer; talks only to gateway routes |

## 4. Slots, not models

Lanes are **contracts** (memory envelope, architecture policy, capability
gates, throughput floors — formalized in doc 05). Checkpoints are **tenants**.
The kit's scripts reference tenants through config; the eval suite verifies
contract compliance regardless of tenant. This is the mechanism that keeps
the build identical across models of the class.

## 5. Operating modes & transitions

`solo` (default) → maximum aggregate throughput, both lanes independent.
`cluster` → both GPUs to the FLEET slot for frontier-feel or >solo-context
work. `down` → clean stop. All transitions go through `swap-lane.sh`, which
enforces: teardown on both nodes, page-cache drop, then start. Gateway
fallbacks carry traffic for whichever solo lanes are down.

## 6. State & config

- Runtime config: `config/cluster.env` (never committed with secrets).
- Tenancy + flags per lane: lane scripts read env; changes are diffs, not
  edits to logic.
- Evidence & provenance: hermes-brain pages per lane (RUNBOOK rule 27).
- Session state for agent work: `ops/sessions/` per doc 06.
- Weights: HF cache on each node's NVMe; head downloads, fabric rsyncs.

## 7. Failure domains

One Spark down in solo mode ⇒ the other lane and the gateway keep serving;
affected route fails over to `frontier`. Gateway down ⇒ all programmatic
consumers down (accepted: single-operator tool; restart is one compose
command). Fabric down ⇒ cluster mode unavailable, solo unaffected. Tailnet
down ⇒ local LAN access still works from the office.

## 8. Decision records (ADR, condensed)

- **ADR-1 Two independent nodes by default, cluster on demand.** Decode is
  bandwidth-bound; independence doubles aggregate throughput and halves
  blast radius. Clustering is reserved for capacity or the full lever stack
  (4-bit weights + 4-bit KV + speculative decoding).
- **ADR-2 vLLM as engine.** Concurrent batching + best-documented GB10 path;
  Ollama kept only for casual/desktop use, llama.cpp available but not the
  serving default (RPC clustering measured slower than single node).
- **ADR-3 LiteLLM as gateway.** Route-by-name gives model-agnosticism at the
  consumer boundary; `drop_params` is load-bearing; one-way frontier
  fallback keeps the dependency graph acyclic.
- **ADR-4 Don't vendor the cluster recipe.** Deep pinned-dependency stacks
  rot; adopt upstream at a recorded commit and enforce our own gates on top.
- **ADR-5 Gates over trust.** Advertised specs (context length, tok/s) are
  claims; promotion requires local evidence. This is also what makes tenant
  swaps safe.
- **ADR-6 Dense ≤32B stays on the Ada.** 3.5× the bandwidth; the Sparks'
  physics punish dense decode.
- **ADR-7 Stdlib-only eval suite.** Delivery day must not depend on pip.
