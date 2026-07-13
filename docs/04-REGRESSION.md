# Regression Testing — triggers, sets, cadence

Regression here means: **re-running the gate subset that a change can
plausibly break, before the change carries client work.** The matrix is the
policy; when in doubt, run the superset. All results append to the lane's
evidence page (doc 03).

## 1. Change-trigger matrix

| Change | G0 | G1 | G2 | G3 | G4 | G5 | G6 | G7 |
|---|---|---|---|---|---|---|---|---|
| New tenant (model swap) into a lane | ● | | ● | ● | ● | ◐¹ | ● | ● |
| Model *revision* bump (same family) | ◐² | | ● | ● | ● | ◐¹ | ● | |
| vLLM image tag bump | | | ● | ● | ● | ◐¹ | ● | |
| Engine flag / parser / sampling change | | | ● | ● | ● | ◐¹ | | |
| GMU / max_model_len / max_num_seqs change | | | ● | ● | | ●³ | | |
| KV dtype or spec-decode config change | | | ● | ● | ● | ● | | |
| Driver / firmware / kernel update | | ●⁴ | ● | ● | ◐ | | | |
| Fabric change (cable, NIC, IPs, NCCL env) | | ● | ●⁴ | ●⁴ | | | | |
| LiteLLM config change | | | | | | | ● | |
| New utility service on a node | | | ●⁵ | ●⁵ | | | ● | |
| OS `dist-upgrade` (routine) | | | ● | ● | | | ● | |

● required · ◐ conditional · blank not required
¹ if the lane serves >32K context · ² only if license text changed with the
revision · ³ at the *new* context target · ⁴ cluster lanes only ·
⁵ co-resident lane on that node (memory pressure check)

## 2. Known-fragile areas (assume regression until proven otherwise)

1. **Hybrid-attention models × engine model-runner versions** (RUNBOOK 22).
2. **Tool-call parsers** after any tenant or template change — the failure
   is silent (RUNBOOK 23); G4's tool gate exists for this.
3. **GMU knife edges** — margins measured in tens of MB; any memory-adjacent
   change re-brackets (RUNBOOK 7).
4. **Pinned upstream recipes** — refs and dependency anchors rot
   (RUNBOOK 15); rebuilds are regressions by definition.
5. **NCCL tunings across model classes** — never carry forward (RUNBOOK 12).
6. **Spec-decode acceptance vs workload** — throughput numbers don't
   transfer between prose and structured output; benchmark both if a lane
   serves both.

## 3. Cadence (calendar-driven, independent of changes)

- **Weekly (automatable):** `eval/smoke.sh` all routes; alert on any FAIL.
- **Monthly:** G3 on all active lanes (drift catch); review upstream repos
  of adopted recipes for breaking changes — note, don't auto-adopt.
- **Quarterly:** full G2–G6 pass on every active lane; G5 at all served
  depths; restore-from-docs drill on one node's *config* (not a reimage —
  verify the hermes-brain page actually reproduces the lane).
- **After any incident:** the matrix row matching the fix, plus G7 for any
  route the incident touched.

## 4. Regression discipline for agents (binding, see doc 06)

- Run the matrix row **before** declaring a change complete; paste results
  into the session handoff.
- A failing regression is a finding, not an obstacle: fixing the test,
  loosening a threshold, or retrying until green are all prohibited moves.
  Escalate in the handoff instead.
- If a change spans sessions, the *pickup* session re-runs the last green
  gate before building further (unverified prior claims are hypotheses).

## 5. Record format (append to lane evidence page)

```
[2026-07-13 14:20] REGRESSION model-swap BRAIN: candidate <id@rev>
  trigger: tenant swap   matrix row: 1
  G0 pass (license: <name>, commercial OK)
  G2 pass (KV pool 41,300 tok @ GMU 0.850, digest sha256:…)
  G3 pass (52.4 ± 1.1 tok/s, floor 35)
  G4 pass (8/8, 4/4, tools 2/2)
  G5 pass (100K & 300K @ 10/50/90)
  G6 pass (route + fallback demo)
  G7 pass (qbo-categorizer n=120, 96.7% vs 95% floor)
  verdict: PROMOTED; previous tenant archived to <page>
```
