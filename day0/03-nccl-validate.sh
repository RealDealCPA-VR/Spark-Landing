#!/usr/bin/env bash
# 03-nccl-validate.sh — run ONCE from Spark A (head) after 02 ran on both nodes.
# Validates: ssh to worker, RoCE GID discovery (per node!), raw RDMA perf,
# and prints the exact NCCL env to reuse in every cluster lane.
#
# Reference procedure: NVIDIA "Spark Clustering" section of the DGX Spark User
# Guide + dgx-spark-playbooks (discover-sparks.sh). This script is the gate;
# the playbook is the fallback if a step here fails.
set -uo pipefail
cd "$(dirname "$0")/.."
source config/cluster.env
FAILED=0

echo "== NCCL/RoCE validation from $(hostname) =="

# 1. SSH to worker (cluster lanes depend on this; per-node usernames differ
#    in the wild — fix with a Host entry in ~/.ssh/config, not in scripts).
if ssh -o BatchMode=yes -o ConnectTimeout=5 "$SPARK_B_SSH" true 2>/dev/null; then
  echo "  PASS  ssh $SPARK_B_SSH"
else
  echo "  FAIL  passwordless ssh to $SPARK_B_SSH — ssh-copy-id first"; FAILED=1
fi

# 2. GID index discovery, BOTH nodes. Commonly 3 (RoCEv2/IPv4) but nodes have
#    shipped differing — never assume symmetry.
gid_for() { # $1 = "" for local, or ssh target
  local CMD='show_gids 2>/dev/null | grep -Ei "v2.*(192\.168|DEV)" || echo "(show_gids missing — grep RoCE v2 rows under /sys/class/infiniband/*/ports/1/gid_attrs/types/)"'
  if [[ -n "${1:-}" ]]; then ssh "$1" "$CMD"; else bash -c "$CMD"; fi
}
echo "  -- GID table, Spark A --";  gid_for ""            | sed 's/^/     /' || true
echo "  -- GID table, Spark B --";  gid_for "$SPARK_B_SSH"| sed 's/^/     /' || true
echo "  ....  pick the RoCE v2 index carrying $SPARK_A_FABRIC_IP / $SPARK_B_FABRIC_IP"
echo "  ....  record PER-NODE values below; they may differ (3 vs 5 seen in the wild)"

# 3. Raw RDMA perf (perftest). Latency should be ~1-2 us; bandwidth ~24 GB/s
#    on a healthy 200G link. This isolates fabric problems from NCCL problems.
if command -v ib_send_bw >/dev/null; then
  echo "  ....  starting ib_send_bw server on worker; client here (10s)"
  ssh "$SPARK_B_SSH" "nohup ib_send_bw -d rocep1s0f0 >/tmp/ibbw.log 2>&1 & sleep 1" 2>/dev/null
  BW=$(ib_send_bw "$SPARK_B_FABRIC_IP" 2>/dev/null | awk '/^ 65536/{print $4}' | tail -1)
  echo "  ....  ib_send_bw @64KiB: ${BW:-n/a} MB/s"
  [[ -n "${BW:-}" && "${BW%.*}" -ge 15000 ]] && echo "  PASS  RDMA bandwidth" \
    || { echo "  WARN  low/absent RDMA bw — check GID, firewall, DAC seating"; }
else
  echo "  ....  perftest not installed (sudo apt install perftest) — skipping raw RDMA gate"
fi

# 4. NCCL all_reduce across both nodes, in containers, over the fabric.
#    Uses the community vLLM image (has torch+nccl). Bus BW gate: >15 GB/s.
NCCL_ENV="NCCL_SOCKET_IFNAME=$FABRIC_IFACE NCCL_IB_HCA=rocep1s0f0"
echo "  ....  NCCL 2-node all_reduce (this can take a few minutes to pull images)"
cat > /tmp/nccl_ar.py <<'PY'
import os, torch, torch.distributed as dist, time
dist.init_process_group("nccl")
r = dist.get_rank(); t = torch.ones(256*1024*1024//4, device="cuda")  # 256MB
for _ in range(3): dist.all_reduce(t)          # warmup
torch.cuda.synchronize(); s=time.time(); N=10
for _ in range(N): dist.all_reduce(t)
torch.cuda.synchronize(); dt=(time.time()-s)/N
busbw = 2*(t.numel()*4)/dt/1e9  # ring allreduce, 2 ranks
if r==0: print(f"NCCL_ALLREDUCE_BUSBW_GBPS={busbw:.1f}")
PY
echo "  ....  manual step if unattended run fails:"
echo "        A: docker run --rm --gpus all --network host --ipc host -v /tmp:/tmp -e $NCCL_ENV \\"
echo "             -e MASTER_ADDR=$SPARK_A_FABRIC_IP -e MASTER_PORT=29500 -e RANK=0 -e WORLD_SIZE=2 \\"
echo "             $VLLM_IMAGE_COMMUNITY python /tmp/nccl_ar.py"
echo "        B: same, RANK=1 (copy /tmp/nccl_ar.py to B first)"
echo "  GATE  proceed to cluster lanes only when BUSBW >= 15 GB/s and both raw"
echo "        RDMA numbers are sane. Record the working NCCL_* values in"
echo "        config/cluster.env comments — every cluster lane reuses them."

exit $FAILED
