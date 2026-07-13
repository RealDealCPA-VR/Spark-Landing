#!/usr/bin/env bash
# Lane A — agent brain. Run ON SPARK A.
# Model: openai/gpt-oss-120b (MXFP4, ~5.1B active). The best-documented
# high-throughput model on GB10: ~55-60 tok/s single stream via vLLM,
# ~1.7k tok/s prefill, near-linear throughput scaling with concurrency.
# This lane is the default target for vr-dispatch structured/batch work.
set -euo pipefail
cd "$(dirname "$0")/../.."
source config/cluster.env

NAME=vllm_brain
docker rm -f $NAME 2>/dev/null || true

# Notes on flags (details in ops/RUNBOOK.md):
# --load-format fastsafetensors : mmap on Spark is slow; this is the fix.
# --swap-space 16               : community-standard on GB10.
# GMU $BRAIN_GMU                : starting point; bracket in 0.005 steps if
#                                 boot OOMs or KV pool comes up short.
# max-model-len 131072          : plenty for the brain role; raise only after
#                                 a needle test at the new depth.
docker run -d --name $NAME \
  --gpus all --network host --ipc host --restart unless-stopped \
  -v "$HF_CACHE":/root/.cache/huggingface \
  -e HF_TOKEN="$HF_TOKEN" -e HF_HUB_OFFLINE="${HF_HUB_OFFLINE:-0}" \
  "$VLLM_IMAGE_COMMUNITY" \
  vllm serve openai/gpt-oss-120b \
    --host 0.0.0.0 --port "$BRAIN_PORT" \
    --gpu-memory-utilization "$BRAIN_GMU" \
    --load-format fastsafetensors \
    --swap-space 16 \
    --max-model-len 131072 \
    --enable-prefix-caching

echo "brain starting on :$BRAIN_PORT — first load is the slow one."
echo "watch:   docker logs -f $NAME | grep -E 'KV cache size|Application startup'"
echo "gate:    eval/smoke.sh   then   eval/bench_decode.py --model brain"
echo "         (expect roughly 50-60 tok/s single-stream; investigate if <40)"
echo "note:    tool-calling for gpt-oss goes through its native format — run"
echo "         eval/behavior_suite.py BEFORE wiring any agent harness. A wrong"
echo "         parser fails silently with calls landing in message.content."
