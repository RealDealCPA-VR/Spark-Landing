#!/usr/bin/env bash
# 01-preflight.sh — run on EACH Spark after apt dist-upgrade + fwupdmgr upgrade.
# Gates the node on: arch, driver/firmware floor, docker+nvidia runtime,
# unified memory, disk headroom. Exits nonzero on any FAIL.
set -uo pipefail
cd "$(dirname "$0")/.."
# Guarded — preflight must run before cluster.env exists; without it the disk check falls back to $HOME.
[[ -f config/cluster.env ]] && source config/cluster.env

PASS=0; FAIL=0
ok()   { echo "  PASS  $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }
info() { echo "  ....  $1"; }

echo "== Spark preflight: $(hostname) =="

# 1. Architecture
[[ "$(uname -m)" == "aarch64" ]] && ok "aarch64 (GB10)" || bad "not aarch64 — wrong box?"

# 2. GPU + driver floor. Ollama's Spark guidance sets 580.95.05 as the floor;
#    anything older has known perf/stability issues. Update via DGX Dashboard
#    or: apt dist-upgrade + fwupdmgr refresh/upgrade + reboot.
if command -v nvidia-smi >/dev/null; then
  DRV=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1)
  info "driver: ${DRV:-unknown}"
  FLOOR="580.95.05"
  if [[ -n "${DRV:-}" && "$(printf '%s\n%s\n' "$FLOOR" "$DRV" | sort -V | head -1)" == "$FLOOR" ]]; then
    ok "driver >= $FLOOR"
  else
    bad "driver < $FLOOR — run: sudo apt update && sudo apt dist-upgrade && sudo fwupdmgr refresh && sudo fwupdmgr upgrade && sudo reboot"
  fi
  nvidia-smi -L | sed 's/^/  ....  /'
else
  bad "nvidia-smi missing"
fi

# 3. Docker + NVIDIA container runtime
if command -v docker >/dev/null; then
  ok "docker present"
  if docker info 2>/dev/null | grep -qi nvidia; then
    ok "nvidia container runtime registered"
  else
    bad "nvidia runtime not in 'docker info' — check nvidia-container-toolkit"
  fi
  if docker run --rm --gpus all "${VLLM_TEST_IMAGE:-ubuntu:24.04}" true 2>/dev/null; then
    ok "docker --gpus all smoke"
  else
    info "docker --gpus all smoke skipped/failed (fine if offline; retry when online)"
  fi
else
  bad "docker missing"
fi

# 4. Unified memory: expect ~121 GiB usable of 128
MEM_GIB=$(awk '/MemTotal/ {printf "%d", $2/1048576}' /proc/meminfo)
info "MemTotal: ${MEM_GIB} GiB"
[[ "$MEM_GIB" -ge 115 ]] && ok "unified memory sane" || bad "unified memory low (${MEM_GIB} GiB) — desktop session or leak eating it?"

# 5. Disk headroom: gpt-oss-120b ~66G, Qwen3.6-27B ~30G, DSv4-Flash cache is
#    hundreds of GB. Demand 600G free before we start pulling weights.
FREE_G=$(df -BG --output=avail "${HF_CACHE:-$HOME}" 2>/dev/null | tail -1 | tr -dc '0-9')
info "free on model volume: ${FREE_G:-?} G"
[[ "${FREE_G:-0}" -ge 600 ]] && ok "disk headroom >= 600G" || bad "free space < 600G — clear space or point HF_CACHE elsewhere"

# 6. Desktop session check — Xorg/gnome/browser eat GBs of unified memory.
if pgrep -x Xorg >/dev/null || pgrep -f gnome-shell >/dev/null; then
  info "desktop session running — fine for setup; consider headless (multi-user.target) for serving"
fi

echo "== result: $PASS pass / $FAIL fail =="
[[ $FAIL -eq 0 ]] || { echo "GATE: fix FAILs before proceeding to 02-network-fabric.sh"; exit 1; }
