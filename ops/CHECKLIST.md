# Delivery-day runsheet — print this

Order is `docs/02-HOWTO.md`, verbatim. One box per step; expected PASS output
inline; gate (doc 03 G0–G7) or doc section each box satisfies.

**Stop-if-red rule: a red gate stops the day.** Promotion order is strict
(doc 03) — do not run later gates "to see." Day 0 problems are cheap; Day 2
problems are expensive (doc 02 §A).

## Before Day 0 (doc 02 assumptions + doc 07 Level 2)

- [ ] `cp config/cluster.env.example config/cluster.env` — every value edited (doc 02 header)
- [ ] Kit rsynced to the SAME path on BOTH nodes (doc 07 L2; swap-lane.sh assumes it)
- [ ] Pins reverified per `ops/PINS.md` checklist — receipt 2026-07-13; newer wins (doc 07 L2)

## Day 0 — metal (doc 02 §A)

- [ ] EACH Spark: `sudo apt update && sudo apt dist-upgrade -y` then
      `sudo fwupdmgr refresh && sudo fwupdmgr upgrade && sudo reboot`
      → PASS: clean reboot; `nvidia-smi` driver ≥ 580.95.05 (doc 02 §A.1)
- [ ] EACH Spark: `./day0/01-preflight.sh`
      → PASS: ends `== result: N pass / 0 fail ==` (doc 02 §A.2)
- [ ] Cable QSFP↔QSFP with the DAC, then EACH Spark: `./day0/02-network-fabric.sh --persist`
      → PASS: `PASS  200G link` + `PASS  peer <ip> reachable over fabric` (doc 02 §A.3)
- [ ] Spark A only: `./day0/03-nccl-validate.sh`
      → PASS: ssh PASS; PER-NODE GID indexes RECORDED (they may differ);
      `NCCL_ALLREDUCE_BUSBW_GBPS=` ≥ 15 — **G1**
- [ ] EACH Spark: `./day0/04-tailscale.sh`
      → PASS: node visible in `tailscale status` from another device (doc 02 §A.5)

**STOP here if any gate is red** (doc 02 §A).

- [ ] Record evidence per `ops/evidence/` — driver, GIDs, BUSBW, dates.

## Day 1 — first serve (doc 02 §B; promotion order doc 03)

- [ ] Read `openai/gpt-oss-120b` license IN FULL before the first pull; log
      verdict + revision — **G0** (blocking, precedes download)
- [ ] Same for `Qwen/Qwen3.6-27B-FP8` — **G0**
- [ ] Spark A: `lanes/solo-a-agent-brain/run.sh` · Spark B: `lanes/solo-b-code-utility/run.sh`
      (first model pull is the slow one) (doc 02 §B)
- [ ] `docker logs -f vllm_brain | grep -E "KV cache size|startup"`
      → PASS: KV pool logged ≥ lane floor; max_model_len 131072; no OOM /
      path-disabling fallback. Record tag+digest, model rev, full flags — **G2** (brain)
- [ ] Same on B: `docker logs -f vllm_coder | grep -E "KV cache size|startup"`
      → PASS: max_model_len 262144; same records — **G2** (coder)
- [ ] Gateway on A: `cd gateway && docker compose --env-file ../config/cluster.env up -d`
      (doc 02 §B)
- [ ] `eval/smoke.sh http://spark-a:4000`
      → PASS: gateway + brain + coder PASS; frontier PASS if ANTHROPIC_API_KEY
      set (else `....`); fleet `....` (on-demand, intentional) — **G6** (partial)
- [ ] `eval/bench_decode.py --base-url http://spark-a:4000/v1 --model brain`
      → PASS: ≥ 35 tok/s (ref ~55–60), stdev sane — **G3**
- [ ] `eval/bench_decode.py --base-url http://spark-a:4000/v1 --model coder`
      → PASS: ≥ 12 tok/s at working context (ref 14–25) — **G3**
- [ ] `eval/behavior_suite.py --base-url http://spark-a:4000/v1 --model brain`
      → PASS: schema ≥ 7/8; adherence ≥ 3/4; tools 2/2 if dispatch uses brain's
      tools — **G4**
- [ ] `eval/behavior_suite.py --base-url http://spark-a:4000/v1 --model coder`
      → PASS: schema ≥ 7/8; adherence ≥ 3/4; tools 2/2 MANDATORY — a call in
      `message.content` is an automatic FAIL — **G4**
- [ ] Fallback demo: `docker stop vllm_brain`; repeat the brain route call →
      frontier answers; `docker start vllm_brain`; repeat for coder — **G6** (complete)
- [ ] Record evidence per `ops/evidence/` (doc 03 format). Solo mode is now
      the resting state.

## Day 2 — cluster lane (doc 02 §C; full procedure `lanes/cluster-dsv4-fleet/README.md`)

- [ ] Read the DeepSeek-V4-Flash model card license IN FULL before downloading
      a single byte; log verdict + date — **G0**
- [ ] G1 went green Day 0 — copy the PER-NODE GID indexes into the recipe's
      `.env.dspark` — **G1** (evidence reuse)
- [ ] `git clone https://github.com/tonyd2wild/DeepSeek-v4-Flash-DSpark-1M-NVFP4-KV-2x-DGX-Spark dsv4-lane && cd dsv4-lane && git rev-parse HEAD | tee ../PINNED_COMMIT.txt`
      → PASS: commit recorded (RUNBOOK 15: pinned refs rot)
- [ ] `cp .env.dspark.example .env.dspark`, fill from `config/cluster.env`:
      WORKER_HOST, MASTER_ADDR (fabric IP of A), NCCL_IB_HCA,
      NCCL_SOCKET_IFNAME, per-node NCCL_IB_GID_INDEX, HF_CACHE
- [ ] `./build-dspark-vllm-runtime.sh` → PASS: build completes
- [ ] `./prepare-dspark-model-cache.sh` → stage on A, rsync to B over fabric
      (~4 min for 224GB — RUNBOOK 13)
- [ ] `./start-deepseek-v4-flash-dspark.sh` at the **balanced profile
      500K / max_num_seqs=4** (the 1M/6 profile is for later, after gates)
- [ ] `curl -fsS http://127.0.0.1:8888/v1/models | grep max_model_len` and
      `docker compose --env-file .env.dspark -f docker-compose.dspark.yml logs vllm-dspark | grep -E "GPU KV cache size|Maximum concurrency"`
      → PASS: KV pool ~1.9–2.0M tokens; if GMU knife-edges, bracket in 0.005
      steps and record the winner — **G2**
- [ ] `../../eval/bench_decode.py --base-url http://127.0.0.1:8888/v1 --model default`
      → PASS: ≥ 30 tok/s (ref 50–67 single-stream) — **G3**
- [ ] `../../eval/behavior_suite.py --base-url http://127.0.0.1:8888/v1 --model default`
      → PASS: schema ≥ 7/8; adherence ≥ 3/4; tools 2/2 — **G4**
- [ ] `../../eval/needle.py --base-url http://127.0.0.1:8888/v1 --model default --context-tokens 100000 --depths 10,50,90`
      then again with `--context-tokens 300000`
      → PASS: exact recall at EVERY depth — **G5**
      (lane README numbers needle/behavior locally as Gates 4/5; doc 03's
      strict G4→G5 order governs)
- [ ] Uncomment the `fleet` block in `gateway/litellm-config.yaml`;
      `docker compose restart` the gateway; `eval/smoke.sh` → fleet PASS,
      plus fallback demo — **G6**
- [ ] Record evidence per `ops/evidence/` — PINNED_COMMIT, GIDs, GMU,
      profile, all gate results.

G7 (dispatch pilot) is Day 3+: one representative real skill with ground
truth, before any route carries production volume (doc 03). Not on this
runsheet by design.
