# Definition of Done — and the master TODO

Three completion levels. Each level's boxes must ALL be checked, with
evidence on the relevant hermes-brain pages, before claiming the level.

## Level 1 — Kit-complete (build artifact) ✅ 2026-07-13

- [x] Day-0 gate scripts (preflight, fabric, NCCL, tailscale)
- [x] Solo lane scripts A/B with known-good engine flags
- [x] Cluster lane adoption guide with Gates 0–5
- [x] Gateway (routes, fallbacks, drop_params)
- [x] Eval suite: smoke / bench / needle / behavior (stdlib-only)
- [x] Mode switcher with clean two-node teardown
- [x] RUNBOOK (27 rules) + this docs package (00–07)
- [x] Shell/Python syntax verified; YAML validated
- [ ] ~~Executed on GB10 silicon~~ → deferred to Level 2 by definition

## Level 1.5 — Pre-delivery hardening (no hardware required) ✅ 2026-07-13

Critique of Level 1 that motivated this level: "Shell/Python syntax verified"
is not "verified" — nothing in the kit had ever been *executed*, the gateway
config contained an interpolation pattern that cannot route, the NCCL gate's
bus-bandwidth formula was wrong for 2 ranks, and the repo wasn't a git repo
despite doc 06 requiring one. Everything below is executable before the
Sparks arrive, and shrinks delivery-day risk to hardware-only unknowns.

### A. Correctness fixes (kit was wrong as shipped)

- [x] A1 Gateway: LiteLLM `api_base` env interpolation fixed (full-URL env
      vars via compose; inline `http://os.environ/...` never resolved)
- [x] A2 NCCL validate: 2-rank all-reduce busbw formula corrected (was 2×
      optimistic — a failing fabric could pass the 15 GB/s gate); `-e` flag
      applied per env var in printed manual command; RoCE device name
      parameterized
- [x] A3 Eval suite: reasoning-model tolerance (reasoning_content, token
      headroom), explicit imports, exit codes verified
- [x] A4 Script hygiene: 01-preflight sources cluster.env (HF_CACHE disk
      check was checking $HOME); fabric MTU set in ephemeral path too;
      lane env parity
- [x] A5 Pins current as of hardening date: frontier Claude model string,
      image tags; `:latest` contradiction resolved or documented
- [x] A6 Gateway auth: optional LITELLM_MASTER_KEY wired (LAN-open gateway
      could spend frontier API credits)

### B. Test the testers (gates must be proven runnable before hardware day)

- [x] B1 `eval/mock_openai_server.py` (stdlib) + self-test that runs smoke /
      bench / needle / behavior against the mock — all four gates exercised
      end-to-end, pass and fail paths both demonstrated
- [x] B2 Static pass recorded: `bash -n` every .sh, `py_compile` every .py,
      YAML parsed

### C. Delivery-day ergonomics

- [x] C1 `ops/PINS.md` — every pinned value in one table with a
      reverify-on-arrival checklist (Level 2's "pins reverified" now has a
      concrete artifact to execute against)
- [x] C2 `ops/evidence/` templates — lane evidence page + gate-run record
      in the exact doc 03/04 formats (no format invention on delivery day)
- [x] C3 `ops/CHECKLIST.md` — printable Day 0/1/2 runsheet, one checkbox
      per gate, maps 1:1 to docs 02/03
- [x] C4 `ops/systemd/` — weekly-smoke timer + service examples (Level 3
      monitoring becomes a copy, not a design task)

### D. Repo integrity

- [x] D1 Git repo initialized; v0.2 baseline committed; `.gitignore` blocks
      `config/cluster.env` (doc 06's protocol is now actually executable)
- [x] D2 MANIFEST covers all kit files (not just docs) + `ops/manifest.sh`
      to regenerate/verify; regenerated last after all edits
- [x] D3 Cross-file consistency sweep green: README repo map, INDEX, ports,
      container names, gate references, paths

## Level 2 — Deployment-complete (hardware serving)

**Gate: `smoke.sh` green in solo mode + all Day-1 gate evidence recorded.**

- [ ] `config/cluster.env` filled; kit rsynced to both nodes at same path
- [ ] Pins reverified against ecosystem (image tags, model IDs, floors) —
      receipt date is 2026-07-13; anything newer wins
- [ ] Day 0: preflight PASS both nodes (firmware ≥ floor)
- [ ] Day 0: fabric 200G link + peer ping, persisted
- [ ] Day 0: NCCL BUSBW ≥ 15 GB/s; per-node GID indexes recorded
- [ ] Tailscale on both nodes; gateway reachable from phone/laptop
- [ ] BRAIN tenant: G0, G2, G3, G4 green; evidence page created
- [ ] CODER tenant: G0, G2, G3, G4 (tool gate 2/2) green; evidence page
- [ ] Gateway up; G6 incl. fallback demonstration for brain & coder
- [ ] `swap-lane.sh solo|down|solo` round-trip exercised cleanly
- [ ] hermes-brain: lane pages seeded with config fingerprints (rule 27)

## Level 3 — Production-complete (the firm runs on it)

**Gate: 7 consecutive days in solo mode with weekly smoke green and no
manual intervention, AND at least one production skill migrated via G7.**

- [ ] FLEET lane: license verdict (G0) logged → adopted at recorded commit
      → G1–G5 green at 100K & 300K depths → wired as `fleet` route
- [ ] G7 pilots: ≥ 2 dispatch skills migrated to gateway routes with
      accuracy vs ground truth recorded (suggest: qbo-feed-categorizer,
      one document-extraction skill)
- [ ] vr-dispatch config: zero hardcoded model endpoints remain (G4 of PRD)
- [ ] UTILITY slots registered: Whisper route; embeddings route for
      hermes-brain retrieval
- [ ] Staff surface: Open WebUI (or equivalent) on the tailnet → gateway
- [ ] Monitoring: weekly smoke automated (cron/systemd timer) with a
      notification path; monthly G3 calendarized; quarterly full pass
      calendarized (doc 04 §3)
- [ ] Ops hardening: lane containers survive node reboot
      (restart policies verified by an actual reboot test, both nodes)
- [ ] Backup/restore: `cluster.env` + lane fingerprints + docs mirrored to
      hermes-brain; **config-restore drill passed** (rebuild one lane from
      records alone)
- [ ] Docs 03–07 live as hermes-brain pages; repo copies marked as bootstrap
- [ ] Session protocol proven: ≥ 1 real multi-session task completed under
      doc 06 with clean pickup by a different session

## Backlog (valuable, not blocking any level)

- [ ] llama-swap or equivalent for multi-tenant hot-swap on Spark B
- [ ] dcgm-exporter + Prometheus/Grafana if weekly smoke proves insufficient
- [ ] Second DAC cable + spare QSFP on the shelf (fabric single point)
- [ ] UPS sizing for both nodes (~240W each) + graceful-shutdown hook
- [ ] Batch scheduler: overnight distress-radar / categorizer sweeps pinned
      to idle lanes
- [ ] Candidate bench: next BRAIN/CODER tenants shortlisted via doc 05 §3
      intake (kept warm for swap-day)
- [ ] REAP self-pruning pilot for a UTILITY-class specialist (calibration
      from real dispatch traffic; behavior suite before/after)
- [ ] Anonymized write-up of the platform for the podcast / RealDealCPA
      collateral — after Level 3, not before

## The one-line test for "complete"

*A new Spark pair, this repo, and hermes-brain reproduce the entire platform
without this conversation existing.* Until that sentence is true, it's not
done — and doc 06 is how every session in between leaves the trail.
