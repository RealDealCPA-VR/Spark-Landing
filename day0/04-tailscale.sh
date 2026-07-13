#!/usr/bin/env bash
# 04-tailscale.sh — put the node on your tailnet. Run on each Spark.
# Serving processes bind to LAN/localhost; Tailscale is how you (and only you)
# reach the gateway from anywhere. Never bind vLLM to a public interface.
set -euo pipefail

if ! command -v tailscale >/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
sudo tailscale up --ssh --hostname "$(hostname)"
tailscale status | head -5
echo
echo "PASS if this node shows in 'tailscale status' from your other devices."
echo "Gateway URL for clients becomes: http://$(hostname):\${GATEWAY_PORT:-4000}/v1"
