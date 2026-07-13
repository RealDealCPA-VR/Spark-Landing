#!/usr/bin/env bash
# smoke.sh — is every route alive and answering? Run from any tailnet machine.
# Usage: eval/smoke.sh [gateway_base]   (default http://localhost:4000)
set -uo pipefail
BASE="${1:-http://localhost:${GATEWAY_PORT:-4000}}"
FAILED=0

echo "== smoke against $BASE =="
curl -fsS "$BASE/v1/models" >/dev/null 2>&1 \
  && echo "  PASS  gateway /v1/models" \
  || { echo "  FAIL  gateway unreachable"; exit 1; }

for M in brain coder fleet frontier; do
  RESP=$(curl -fsS -m 120 "$BASE/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"$M\",\"max_tokens\":24,\"messages\":[{\"role\":\"user\",\"content\":\"Reply with exactly: OK $M\"}]}" 2>/dev/null) || RESP=""
  if echo "$RESP" | grep -q "OK $M"; then
    echo "  PASS  $M"
  elif [ -z "$RESP" ]; then
    echo "  ....  $M not configured/up (fine if intentional: fleet is on-demand)"
  else
    echo "  FAIL  $M answered but wrong shape:"; echo "$RESP" | head -c 300; echo
    FAILED=1
  fi
done
exit $FAILED
