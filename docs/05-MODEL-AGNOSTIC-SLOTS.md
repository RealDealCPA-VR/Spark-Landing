# Model-Agnostic Slots — lane contracts & tenant swaps

The mechanism that makes this build work the same for any model of the class:
**a lane is a contract; a model is a tenant.** Scripts, gateway routes, gates,
and docs bind to the contract. Tenants are named only in config and in
evidence pages.

## 1. The size class (what "models of this size" means, in physics)

GB10 node: ~121 GiB usable unified memory, 273 GB/s bandwidth. Therefore:

- **Single-node tenant envelope:** weights ≤ **100 GiB** at serving
  precision (leaves ≥ 15 GiB KV + engine overhead); **MoE with ≤ ~12B
  active parameters** for interactive lanes (dense decode craters:
  ~2.6 tok/s at 70B). Dense tenants ≤ ~10B only, and prefer the Ada.
- **Cluster tenant envelope (TP=2):** weights ≤ **230 GiB** total at serving
  precision; per-node share ≤ 115 GiB; KV floor per contract below. The
  full lever stack (≤4-bit weights, 4-bit KV, speculative decoding) is what
  buys interactive speed at this size — treat tenants lacking a validated
  spec-decode path as batch-only until proven.

Any checkpoint inside the envelope is a **candidate**; candidates become
tenants only by passing gates.

## 2. Slot contracts

| Contract item | BRAIN (Spark A) | CODER (Spark B) | FLEET (cluster) | UTILITY-* (Spark B/Ada) |
|---|---|---|---|---|
| Purpose | dispatch reasoning, structured/batch work | interactive coding agent | frontier-feel, deep context | STT, embeddings, classify |
| Envelope | single-node | single-node, ≤ ~70 GiB weights (leaves room for utilities) | cluster | small; must not evict host lane |
| Context floor | 64K served, KV pool ≥ 128K tokens | 128K served | ≥ 200K served; pool ≥ 4× typical request | n/a |
| Decode floor (warm, single-stream) | ≥ 35 tok/s | ≥ 12 tok/s at working ctx | ≥ 30 tok/s | task-specific |
| Concurrency floor | ≥ 300 tok/s aggregate @ 8-way | 2-way interactive | ≥ 100 tok/s aggregate @ 4-way | n/a |
| G4 tool gate | mandatory if dispatch uses tools here | **mandatory** | mandatory | n/a |
| G5 needle | at served depths | at served depths | **mandatory, at working depths** | n/a |
| License | commercial-verified | commercial-verified | commercial-verified | commercial-verified |
| Interface | OpenAI-compat `/v1`; documented tool-emission format | same | same | HTTP; registered gateway route |

Reference tenants on build date (informational, replaceable): BRAIN
gpt-oss-120b · CODER Qwen3.6-27B-FP8 · FLEET DeepSeek-V4-Flash DSpark
recipe · UTILITY Faster-Whisper app + embedding model (TBD).

## 3. Candidate intake checklist (before touching a Spark)

1. **Class fit:** total + active params, serving precision, computed weight
   footprint inside the envelope. MoE for interactive slots.
2. **License:** G0 procedure; verdict logged first.
3. **Engine support:** confirmed vLLM path on aarch64/sm_121 (community
   image notes, model card `vllm serve` example, or a field report).
   Identify: tool-emission format → parser flag; reasoning parser if any;
   hybrid-attention? → V2-runner kill switch; native quant format.
4. **Known quirks search:** one pass over the model's issues/forum threads
   for GB10-specific reports. Ten minutes here saves a day later.
5. **Spec-decode availability** (FLEET candidates): a drafter or MTP path
   exists, or the tenant is scoped batch-only.

## 4. Tenant swap procedure (zero-redesign guarantee)

1. Intake checklist above; open a candidate entry on the lane's evidence page.
2. **Shadow deploy** on a spare port on the target node (copy the lane's
   `run.sh`, change model + port + container name; do not stop the incumbent
   for single-node lanes with memory headroom — otherwise schedule a window).
3. Run the promotion sequence (doc 03) **against the shadow port**.
4. Promote: update the lane's model reference + parser flags in config /
   lane script; point the gateway route; restart lane; re-run G6.
5. Archive: incumbent's full config fingerprint moves to the evidence page
   with an `ARCHIVED <date>` header. Rollback = redeploy the fingerprint.
6. G7 with a real skill before the route carries production volume.

Swap cost when the contract is honored: **one config diff, one gate pass,
zero script/doc changes.** If a swap requires editing eval thresholds or
lane logic, the candidate fails the contract — stop and reassess.

## 5. Contract evolution

Contracts may change (e.g., raising the FLEET context floor once needle
passes deeper). Changes are diffs to this doc with dated rationale, and they
trigger the doc-04 matrix for every affected lane. Contracts never change
mid-swap to admit a struggling candidate.

## 6. Portability note

Nothing above is DGX-Spark-exclusive except the envelope numbers in §1.
Re-derive §1 from any node's usable memory + bandwidth (and re-run all
gates) and the same kit governs different hardware — the same discipline
applies if this stack is ever packaged for other firms.
