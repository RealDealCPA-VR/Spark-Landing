# Validation Requirements — gate specification

Gates are **contract checks, not model checks**: thresholds below are lane
minimums any tenant must meet. Reference-tenant numbers (in parentheses) are
what the build-date tenants achieved and are informational only.

No lane serves client work, and no route enters the gateway, without its
gate set green and evidenced.

## Gate definitions

### G0 — License (blocking, precedes download)
- **Procedure:** read the checkpoint's license/model card in full.
- **Pass:** commercial use permitted for a for-profit services firm; no
  restriction incompatible with client deliverables or future productization.
- **Evidence:** hermes-brain note — checkpoint id + revision, license name,
  verdict, quote-free summary of any conditions, date, reviewer.

### G1 — Fabric (cluster lanes only; once per cabling/firmware change)
- **Procedure:** `day0/03-nccl-validate.sh` from head.
- **Pass:** ssh head→worker; RoCE v2 GID identified **per node**; raw RDMA
  sane (~1–2 µs latency class); NCCL 2-node all-reduce bus BW **≥ 15 GB/s**.
- **Evidence:** per-node GID indexes, BUSBW value, date.

### G2 — Boot evidence (every lane, every config change)
- **Procedure:** start lane; inspect logs + `/v1/models`.
- **Pass:** advertised `max_model_len` matches intent; KV pool size logged
  and meets lane floor (doc 05); no OOM, no fallback warnings that disable
  intended paths; GMU recorded if bracketed.
- **Evidence:** the two log lines (KV cache size, max concurrency/model len),
  image tag+digest, model revision, full flag set.

### G3 — Warm decode (every lane, every config change)
- **Procedure:** `eval/bench_decode.py` (burns warmup automatically).
- **Pass:** ≥ lane floor — BRAIN **≥ 35 tok/s** (ref ~55–60); CODER
  **≥ 12 tok/s** at working context (ref 14–25); FLEET **≥ 30 tok/s**
  (ref 50–67). Stdev sane across runs.
- **Evidence:** mean ± stdev, gen length, date.

### G4 — Behavior suite (every lane, every tenant/engine/parser change)
- **Procedure:** `eval/behavior_suite.py`.
- **Pass:** schema ≥ 7/8; adherence ≥ 3/4; tool channel 2/2 on lanes that
  declare tool support (CODER: mandatory; BRAIN: mandatory if dispatch uses
  its tools; FLEET: mandatory). A tool call landing in `message.content`
  is an automatic fail regardless of other scores.
- **Evidence:** three scores + any miss transcripts.

### G5 — Needle at depth (any lane serving > 32K context to real work)
- **Procedure:** `eval/needle.py` at **the depths the lane will actually
  serve** — for firm work: 100K and 300K, depths 10/50/90.
- **Pass:** exact recall at every tested depth. Advertised context beyond
  the deepest passing test is treated as nonexistent.
- **Evidence:** per-depth pass table, context sizes, date. Re-run after any
  KV-dtype, context-target, or engine change.

### G6 — Gateway integration (per route)
- **Procedure:** `eval/smoke.sh` against the gateway; confirm fallback by
  stopping the local lane and repeating the route call.
- **Pass:** route answers; fallback route answers when lane is down;
  `drop_params` confirmed (an SDK call with a reasoning param succeeds).
- **Evidence:** smoke output, fallback demonstration note.

### G7 — Dispatch pilot (before a route carries production skills)
- **Procedure:** run one representative real skill end-to-end against the
  route with ground truth available (e.g., a categorizer batch with known
  answers).
- **Pass:** accuracy within the skill's existing acceptance threshold; no
  format-repair hacks added to make it pass.
- **Evidence:** skill name, sample size, accuracy vs threshold.

## Promotion sequence (strict order)

**G0 → (G1 if cluster) → G2 → G3 → G4 → (G5 if long-context) → G6 → G7.**
A red gate stops the sequence; do not run later gates "to see."

## Threshold change control

Floors in this doc change only by editing this doc with a dated rationale —
never inline in a test run, never by an agent to make a run pass
(doc 06 rule). If a floor is wrong, the fix is a diff with reasoning.

## Evidence hygiene

One hermes-brain page per lane; append gate runs chronologically; each entry
carries: date, operator (human/agent+session id), config fingerprint (image
digest, model revision, flags, GMU), results. This page is what makes a
reimaged node recoverable and a tenant swap auditable.
