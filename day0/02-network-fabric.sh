#!/usr/bin/env bash
# 02-network-fabric.sh — configure the direct QSFP (ConnectX-7) link.
# Run on EACH node. Reads config/cluster.env; assigns this node's fabric IP,
# verifies link speed, pings the peer. Writes a netplan file only with --persist.
set -euo pipefail
cd "$(dirname "$0")/.."
source config/cluster.env

HOST=$(hostname)
ARG1="${1:-}"
if [[ "$HOST" == "$SPARK_A_HOST" || "$ARG1" == "--as-a" ]]; then
  MY_IP=$SPARK_A_FABRIC_IP; PEER_IP=$SPARK_B_FABRIC_IP
else
  MY_IP=$SPARK_B_FABRIC_IP; PEER_IP=$SPARK_A_FABRIC_IP
fi
echo "== fabric setup on $HOST: $FABRIC_IFACE -> $MY_IP/$FABRIC_CIDR (peer $PEER_IP) =="

# Interface exists?
ip link show "$FABRIC_IFACE" >/dev/null || {
  echo "FAIL: $FABRIC_IFACE not found. Candidates:"; ip -br link | sed 's/^/  /'
  echo "Edit FABRIC_IFACE in config/cluster.env (QSFP port names vary)."; exit 1; }

sudo ip link set "$FABRIC_IFACE" up
# MTU 9000 in the ephemeral path too — 03's validation must run at production MTU.
sudo ip link set "$FABRIC_IFACE" mtu 9000
sudo ip addr replace "$MY_IP/$FABRIC_CIDR" dev "$FABRIC_IFACE"

# Link speed gate: expect 200000 Mb/s on a good DAC.
SPEED=$(ethtool "$FABRIC_IFACE" 2>/dev/null | awk -F': ' '/Speed/{print $2}')
echo "  link speed: ${SPEED:-unknown}"
[[ "$SPEED" == "200000Mb/s" ]] && echo "  PASS  200G link" \
  || echo "  WARN  expected 200000Mb/s — reseat the DAC / check port if this persists"

# RoCE device visible?
if command -v ibv_devinfo >/dev/null; then
  ibv_devinfo 2>/dev/null | grep -E "hca_id|state" | sed 's/^/  /'
else
  echo "  WARN  ibv_devinfo missing (apt install ibverbs-utils) — needed for 03"
fi

# Peer reachability (only meaningful once the OTHER node ran this too)
if ping -c 2 -W 2 -I "$FABRIC_IFACE" "$PEER_IP" >/dev/null 2>&1; then
  echo "  PASS  peer $PEER_IP reachable over fabric"
else
  echo "  ....  peer not reachable yet (run this script on the other node, then re-check)"
fi

# Optional persistence
if [[ "${1:-}" == "--persist" || "${2:-}" == "--persist" ]]; then
  NP=/etc/netplan/60-spark-fabric.yaml
  sudo tee "$NP" >/dev/null <<EOF
network:
  version: 2
  ethernets:
    $FABRIC_IFACE:
      addresses: ["$MY_IP/$FABRIC_CIDR"]
      mtu: 9000
EOF
  sudo netplan apply
  echo "  persisted to $NP (MTU 9000)"
else
  echo "  (address is ephemeral; re-run with --persist to write netplan)"
fi

echo "== next: run on the other node, then 03-nccl-validate.sh from Spark A =="
