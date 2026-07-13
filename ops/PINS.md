# PINS — every time-sensitive value, one table

Receipt date for everything here: **2026-07-13** (kit v0.2 build date). The
ecosystem moves weekly; the kit doesn't. Reverify the week hardware arrives —
anything newer wins (doc 07 Level 2). Floors move only via a dated doc 03
diff; a pin change updates this table AND the file that owns the value, then
triggers its doc 04 matrix row.

| What | Where it lives | Pinned value | Receipt | Reverify on arrival |
|---|---|---|---|---|
| NVIDIA driver floor | `day0/01-preflight.sh` | `580.95.05` | 2026-07-13 | `nvidia-smi --query-gpu=driver_version --format=csv,noheader` after dist-upgrade; floor came from Ollama's Spark guidance — check whether it moved before trusting an older driver |
| NVIDIA vLLM image | `config/cluster.env.example` → `VLLM_IMAGE_NV` | `nvcr.io/nvidia/vllm:26.06-py3` | 2026-07-13 | newer tag at https://catalog.ngc.nvidia.com/orgs/nvidia/containers/vllm/tags; after pull, record digest: `docker inspect --format '{{index .RepoDigests 0}}' nvcr.io/nvidia/vllm:26.06-py3` |
| Community vLLM image | `config/cluster.env.example` → `VLLM_IMAGE_COMMUNITY` | `eugr/spark-vllm:latest` — bootstrap convenience only; **MUST be digest-pinned on arrival** | 2026-07-13 | `docker pull eugr/spark-vllm:latest && docker inspect --format '{{index .RepoDigests 0}}' eugr/spark-vllm:latest` → write `eugr/spark-vllm@sha256:…` into `config/cluster.env` |
| LiteLLM gateway image | `gateway/docker-compose.yaml` | `ghcr.io/berriai/litellm:main-stable` | 2026-07-13 | https://github.com/BerriAI/litellm/releases; record pulled digest on the gateway's evidence page (same `docker inspect` pattern) |
| BRAIN reference tenant | `lanes/solo-a-agent-brain/run.sh` + `gateway/litellm-config.yaml` | `openai/gpt-oss-120b` (MXFP4) | 2026-07-13 | re-read the model card at https://huggingface.co/openai/gpt-oss-120b — license unchanged (else re-run G0); record the revision actually pulled at G0 |
| CODER reference tenant | `lanes/solo-b-code-utility/run.sh` + `gateway/litellm-config.yaml` | `Qwen/Qwen3.6-27B-FP8` | 2026-07-13 | https://huggingface.co/Qwen/Qwen3.6-27B-FP8 — license + revision at G0; hybrid-attention, so confirm the V2-runner kill switch is still required on the current image (RUNBOOK 22) |
| FLEET recipe repo | `lanes/cluster-dsv4-fleet/README.md` | `github.com/tonyd2wild/DeepSeek-v4-Flash-DSpark-1M-NVFP4-KV-2x-DGX-Spark` | 2026-07-13 | `git ls-remote https://github.com/tonyd2wild/DeepSeek-v4-Flash-DSpark-1M-NVFP4-KV-2x-DGX-Spark HEAD` — reachable + note drift since receipt; the deployed commit gets recorded in `PINNED_COMMIT.txt` at clone (RUNBOOK 15: pinned refs rot) |
| Frontier Claude model | `gateway/litellm-config.yaml` (`model_name: frontier`) — the single source; deliberately not restated here | see the config | 2026-07-13 | model strings move — verify the current one at https://docs.claude.com/en/api/overview before touching the config; a change is a LiteLLM config change (doc 04 row → G6) |
| Reference throughput | `README.md` + `docs/03-VALIDATION.md` (parenthesized refs) + `lanes/cluster-dsv4-fleet/README.md` (the ~182 @ 6-way figure) | BRAIN ~55–60 tok/s (floor 35) · CODER ref 14–25 (floor 12 @ working ctx) · FLEET 50–67 single / ~182 @ 6-way (floor 30) | 2026-07-13 | references are informational — your own G3 numbers supersede them; the floors themselves change only via a dated doc 03 diff, never to make a run pass |
| NCCL bus-BW floor | `docs/03-VALIDATION.md` G1 + `day0/03-nccl-validate.sh` | ≥ 15 GB/s (2-node all-reduce) | 2026-07-13 | run `day0/03-nccl-validate.sh` on the real fabric; raw RDMA reference ~24 GB/s / ~1–2 µs on a healthy 200G link |
| Engine quirk pins (July 2026) | `lanes/solo-b-code-utility/run.sh`, RUNBOOK 22–23 | `VLLM_USE_V2_MODEL_RUNNER=0` on hybrid-attention lanes; tool parser `qwen3_xml` + reasoning parser `qwen3` | 2026-07-13 | re-check vLLM release notes on ANY image bump — quirks rot both ways; G4's tool gate is the detector for silent parser breakage |

## Reverify-on-arrival checklist

Executes doc 07 Level 2's "Pins reverified against ecosystem (image tags,
model IDs, floors)" box. Run it BEFORE Day 0 gates; anything newer than
2026-07-13 wins.

- [ ] Driver floor still `580.95.05` (or a higher published floor) — update `day0/01-preflight.sh` if moved
- [ ] NGC vLLM: is `26.06-py3` still the supported tag? Bump deliberately (doc 04 row: image bump → G2–G4, +G5 on long-context lanes)
- [ ] `eugr/spark-vllm` pulled and **digest-pinned** in `config/cluster.env` — `:latest` does not survive delivery day
- [ ] LiteLLM `main-stable` pulled; digest recorded on the gateway's evidence page
- [ ] BRAIN + CODER model cards re-read: license unchanged (else G0 re-runs), revision recorded
- [ ] FLEET recipe repo reachable; upstream changes since receipt noted — don't auto-adopt (doc 04 §3)
- [ ] Frontier model string in `gateway/litellm-config.yaml` checked against https://docs.claude.com/en/api/overview
- [ ] Reference throughputs sanity-checked against current community numbers; doc 03 floors untouched unless a dated doc 03 diff says otherwise
- [ ] Any pin that changed → its doc 04 matrix row runs before Day 1 promotion
