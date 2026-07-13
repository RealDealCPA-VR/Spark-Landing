#!/usr/bin/env bash
# swap-lane.sh — run FROM SPARK A. Cleanly tears down serving on BOTH nodes
# (rule 14: stale containers eat launches), drops page caches (rule 7), then
# starts the requested mode.
#
#   ops/swap-lane.sh solo          # brain on A + coder on B (daily default)
#   ops/swap-lane.sh cluster-dsv4  # DSv4-Flash fleet lane (owns both GPUs)
#   ops/swap-lane.sh down          # everything off
set -euo pipefail
cd "$(dirname "$0")/.."
source config/cluster.env
MODE="${1:?usage: swap-lane.sh solo|cluster-dsv4|down}"

stop_all() {
  echo "-- stopping serving containers on both nodes --"
  local NAMES="vllm_brain vllm_coder vllm_node vllm-dspark"
  for n in $NAMES; do docker rm -f "$n" 2>/dev/null || true; done
  ssh "$SPARK_B_SSH" "for n in $NAMES; do docker rm -f \$n 2>/dev/null || true; done" || true
  sync && echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null
  ssh "$SPARK_B_SSH" "sync && echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null" || true
  echo "-- clean --"
}

case "$MODE" in
  down)
    stop_all ;;
  solo)
    stop_all
    lanes/solo-a-agent-brain/run.sh
    echo "-- starting coder on B --"
    # requires the kit present at the same path on B (rsync it once)
    ssh "$SPARK_B_SSH" "cd $(pwd) && lanes/solo-b-code-utility/run.sh"
    echo "-- solo mode up; gate with eval/smoke.sh --" ;;
  cluster-dsv4)
    stop_all
    echo "-- launch the DSv4 lane from its own checkout (worker-first handled"
    echo "   by its start script). See lanes/cluster-dsv4-fleet/README.md,"
    echo "   Gates 0-5. This kit intentionally does not blind-launch it. --"
    ;;
  *) echo "unknown mode: $MODE" >&2; exit 1 ;;
esac
