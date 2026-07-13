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
