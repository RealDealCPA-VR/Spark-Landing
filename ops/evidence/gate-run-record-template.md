# Gate-run record — fill-in template (doc 04 §5 format)

Append the completed record to the lane's evidence page
(`ops/evidence/lane-page-template.md`). A red gate stops the sequence — do
not run later gates "to see" (doc 03). Fixing the test, loosening a
threshold, or retrying until green are prohibited moves (doc 04 §4);
escalate in the handoff instead.

## Record format (doc 04 §5, verbatim shape)

```
[<YYYY-MM-DD HH:MM>] REGRESSION <change> <LANE>: candidate <id@rev>
  trigger: <change type>   matrix row: <doc 04 §1 row>
  G0 pass (license: <name>, commercial OK)
  G2 pass (KV pool <n> tok @ GMU <v>, digest sha256:<…>)
  G3 pass (<mean> ± <stdev> tok/s, floor <lane floor>)
  G4 pass (<schema>/8, <adherence>/4, tools <n>/2)
  G5 pass (<ctx sizes> @ <depths>)
  G6 pass (route + fallback demo)
  G7 pass (<skill> n=<samples>, <acc>% vs <floor>% floor)
  verdict: <PROMOTED | REJECTED | ESCALATED>; previous tenant archived to <page>
```

Include only the gates the doc 04 §1 matrix row demands; a
not-required gate is omitted, a failed gate ends the record right there.

## Per-gate blanks (pass criteria from doc 03)

### G0 — License (blocking, precedes download)
Pass: commercial use permitted for a for-profit services firm; no restriction
incompatible with client deliverables or future productization.

```
G0 ____ (license: ______, commercial ____)
   checkpoint: ______ @ rev ______   conditions: ______
   reviewer: ______   date: ______
```

### G1 — Fabric (cluster lanes only; once per cabling/firmware change)
Pass: ssh head→worker; RoCE v2 GID identified PER NODE; raw RDMA ~1–2 µs
latency class; NCCL 2-node all-reduce bus BW ≥ 15 GB/s.

```
G1 ____ (BUSBW ____ GB/s, floor 15)
   GID index A=____ B=____ (may differ — record both)
   raw RDMA: ____ µs / ____ MB/s @64KiB   date: ______
```

### G2 — Boot evidence (every lane, every config change)
Pass: advertised max_model_len matches intent; KV pool logged and ≥ lane
floor (doc 05); no OOM, no fallback warnings that disable intended paths.

```
G2 ____ (KV pool ______ tok @ GMU ______, digest sha256:______)
   max_model_len: ______ (intent: ______)   max concurrency (log line): ______
   model rev: ______   fallback warnings: none | ______   flags: ______
```

### G3 — Warm decode (every lane, every config change)
Pass: ≥ lane floor — BRAIN ≥ 35 tok/s · CODER ≥ 12 @ working ctx ·
FLEET ≥ 30; stdev sane across runs.

```
G3 ____ (______ ± ______ tok/s, floor ______)
   gen length: ______   runs: ______   date: ______
```

### G4 — Behavior suite (every lane, every tenant/engine/parser change)
Pass: schema ≥ 7/8; adherence ≥ 3/4; tools 2/2 where the lane declares tool
support. A tool call landing in `message.content` is an automatic fail.

```
G4 ____ (____/8, ____/4, tools ____/2)
   miss transcripts: none | attached
```

### G5 — Needle at depth (any lane serving > 32K to real work)
Pass: exact recall at every tested depth; advertised context beyond the
deepest passing test is treated as nonexistent.

```
G5 ____ (____K & ____K @ 10/50/90)
   per-depth pass table: attached   date: ______
```

### G6 — Gateway integration (per route)
Pass: route answers; fallback route answers with the lane stopped;
drop_params confirmed (an SDK call with a reasoning param succeeds).

```
G6 ____ (route + fallback demo)
   route: ______   fallback demonstrated: yes | no   drop_params check: ____
   smoke output: attached (doc 03 requires the actual output, not a summary)
```

### G7 — Dispatch pilot (before a route carries production skills)
Pass: accuracy within the skill's existing acceptance threshold; no
format-repair hacks added to make it pass.

```
G7 ____ (______ n=____, ____% vs ____% floor)
   ground truth source: ______   date: ______
```
