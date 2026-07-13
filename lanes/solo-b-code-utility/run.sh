#!/usr/bin/env bash
# Lane B — code + utility node. Run ON SPARK B.
# Primary: Qwen/Qwen3.6-27B-FP8 at 256K context with reasoning + tools + MTP —
# the current community-validated "real coding agent" config on a single GB10
# (nvcr vLLM 26.06 image, qwen3_xml tool parser, V1 model runner).
# Co-located utility slots (Whisper, embeddings) ride the leftover memory.
set -euo pipefail
cd "$(dirname "$0")/../.."
source config/cluster.env

NAME=vllm_coder
docker rm -f $NAME 2>/dev/null || true

# CRITICAL: Qwen3.5/3.6 are hybrid-attention (GDN). vLLM's V2 model runner
# breaks hybrid-attention prefix caching — force it OFF. If boot fails on a
# pip-level issue, the known-good writeup pinned one package inside 26.06;
# check the lane notes.
docker run -d --name $NAME \
  --gpus all --network host --ipc host --restart unless-stopped \
  -v "$HF_CACHE":/root/.cache/huggingface \
  -e HF_TOKEN="$HF_TOKEN" \
  -e VLLM_USE_V2_MODEL_RUNNER=0 \
  "$VLLM_IMAGE_NV" \
  vllm serve Qwen/Qwen3.6-27B-FP8 \
    --host 0.0.0.0 --port "$CODER_PORT" \
    --gpu-memory-utilization "$CODER_GMU" \
    --max-model-len 262144 \
    --enable-prefix-caching \
    --enforce-eager \
    --enable-auto-tool-choice \
    --tool-call-parser qwen3_xml \
    --reasoning-parser qwen3

echo "coder starting on :$CODER_PORT"
echo "gate:  eval/smoke.sh, then behavior_suite.py --model coder (tool-call"
echo "       parse rate is THE gate here — parsers map to emission formats,"
echo "       not model families)."
echo
echo "utility slots on this node (start after coder is stable):"
echo "  - Faster-Whisper FastAPI app (existing) — pick a port, add to gateway"
echo "  - embedding model for hermes-brain retrieval — a small server fits in"
echo "    the remaining memory; keep it OFF this vLLM instance"
echo "  - intake classifier: keep dense qwen3:32b on the Ada (3.5x bandwidth);"
echo "    if it must live here, swap to a small-active MoE first"
