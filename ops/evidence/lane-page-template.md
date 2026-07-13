# Lane evidence — <LANE: BRAIN | CODER | FLEET | UTILITY-*>

Hermes-brain lane page skeleton — one page per lane, per doc 03 "Evidence
hygiene". Copy this file per lane, mirror to hermes-brain (repo copy is the
bootstrap). Gate runs append chronologically and are immutable once written.
This page is what makes a reimaged node recoverable and a tenant swap
auditable (RUNBOOK 27).

## Lane contract

- contract: doc 05 §2, column <BRAIN | CODER | FLEET | UTILITY-*>
- node / port: <spark-a:8000 | spark-b:8001 | head:8888 | …>
- gateway route: <brain | coder | fleet | registered utility route>

## Current tenant fingerprint

Rewrite on promote; the outgoing fingerprint moves to ARCHIVED below —
never overwrite it away.

- tenant: <org/model-id> @ revision <hf commit>
- image: <tag> @ <sha256:…>
- flags: <full `vllm serve` flag set, verbatim>
- GMU: <value> (<bracketed | default — bracket in 0.005 steps before trusting>)
- NCCL env: <per-node NCCL_IB_GID_INDEX, NCCL_IB_HCA, NCCL_SOCKET_IFNAME — cluster lanes only, else n/a>
- promoted: <date> by <operator>

## Gate runs (chronological, append-only)

Each entry carries: date, operator (human/agent + session id), config
fingerprint (image tag+digest, model revision, full flags, GMU, NCCL env
where relevant), results. Record body per doc 04 §5 — fill-in blanks in
`ops/evidence/gate-run-record-template.md`.

### [<YYYY-MM-DD HH:MM>] <G# | REGRESSION <change>> — <human|agent id + session id>

- fingerprint: image <tag>@<sha256:…> · model rev <…> · flags <verbatim> · GMU <…>
- NCCL env: <where relevant, else n/a>
- results: <doc 04 §5 record>
- verdict: PASS | FAIL (<escalated where — a red gate stops the sequence>)

<!-- append the next entry below; entries are immutable once written -->

## Candidate intake (doc 05 §3 — open BEFORE touching a Spark)

### <candidate org/model-id> — <date>

- class fit: <total/active params, serving precision, weight GiB vs envelope>
- G0 license: <name, verdict, conditions summary, reviewer, date>
- engine support: <vLLM path on aarch64/sm_121; tool-emission format → parser flag; reasoning parser; hybrid-attention → V2-runner kill switch; native quant>
- known quirks: <ten-minute GB10 issues/forum pass — findings or "none found">
- spec-decode (FLEET candidates only): <drafter/MTP path | scoped batch-only>

## ARCHIVED tenants (doc 05 §4 step 5)

Rollback = redeploy the fingerprint. Full fingerprint or it isn't archived.

### ARCHIVED <YYYY-MM-DD> — <org/model-id>

- served: <from> → <to> · replaced by: <new tenant> · why: <one line>
- fingerprint: image <tag>@<sha256:…> · model rev <…> · flags <verbatim> · GMU <…> · NCCL env <…>
- last green gates: <G# list + dates>
