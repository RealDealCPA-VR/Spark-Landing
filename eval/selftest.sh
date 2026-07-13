#!/usr/bin/env bash
# selftest.sh — prove the four gates against eval/mock_openai_server.py, offline.
# The gates must work FIRST TRY on delivery day; this is the rehearsal. Asserts
# each gate PASSES against a healthy mock AND exits NONZERO against the matching
# fail mode (a gate that can't fail is not a gate). No hardware, no pip (ADR-7).
# Git-Bash/Windows friendly: plain `python`, background PID, fresh port per mock.
# Usage: eval/selftest.sh          Exit 0 only if every assertion holds.
set -uo pipefail
EVAL_DIR="$(cd "$(dirname "$0")" && pwd)"
PY="${PYTHON:-python}"
BASE_PORT="${SELFTEST_PORT:-8765}"
LOGDIR="$(mktemp -d "${TMPDIR:-/tmp}/spark-selftest.XXXXXX")"
MOCK_PID=""
PORT=""
STARTS=0
FAILED=0

stop_mock() {
  if [ -n "$MOCK_PID" ]; then
    kill "$MOCK_PID" 2>/dev/null
    wait "$MOCK_PID" 2>/dev/null
    MOCK_PID=""
  fi
}
trap stop_mock EXIT

start_mock() {  # $1 = fail mode ("" = healthy). Fresh port each start: no
                # TIME_WAIT / half-dead-process roulette on Windows.
  stop_mock
  PORT=$((BASE_PORT + STARTS)); STARTS=$((STARTS + 1))
  MOCK_FAIL="${1:-}" "$PY" "$EVAL_DIR/mock_openai_server.py" --port "$PORT" \
    2>>"$LOGDIR/mock.log" &
  MOCK_PID=$!
  for _ in $(seq 1 50); do
    curl -fsS -m 2 "http://127.0.0.1:$PORT/v1/models" >/dev/null 2>&1 && return 0
    sleep 0.2
  done
  echo "FATAL: mock did not come up on :$PORT (see $LOGDIR/mock.log)"
  exit 2
}

check() {  # $1 name, $2 want (pass|fail), $3.. command. Records a table row.
  local name="$1" want="$2" rc=0 verdict
  shift 2
  local log="$LOGDIR/${name// /_}.log"
  "$@" >"$log" 2>&1 || rc=$?
  if { [ "$want" = pass ] && [ "$rc" -eq 0 ]; } \
     || { [ "$want" = fail ] && [ "$rc" -ne 0 ]; }; then
    verdict="PASS"
  else
    verdict="FAIL"; FAILED=1
    echo "-- $name: expected $want, got exit $rc; tail of $log:"
    tail -n 12 "$log"
  fi
  printf '  %-4s %-36s want=%-4s exit=%s\n' "$verdict" "$name" "$want" "$rc" \
    >>"$LOGDIR/table"
}

echo "== gate self-test against mock (offline, stdlib-only) =="

# 1. healthy mock: all four gates must pass
start_mock ""
check "smoke passes"    pass bash "$EVAL_DIR/smoke.sh" "http://127.0.0.1:$PORT"
check "bench passes"    pass "$PY" "$EVAL_DIR/bench_decode.py" \
  --base-url "http://127.0.0.1:$PORT/v1" --model brain --runs 2 --gen-tokens 32
check "needle passes"   pass "$PY" "$EVAL_DIR/needle.py" \
  --base-url "http://127.0.0.1:$PORT/v1" --model brain --context-tokens 2000 --depths 10,50,90
check "behavior passes" pass "$PY" "$EVAL_DIR/behavior_suite.py" \
  --base-url "http://127.0.0.1:$PORT/v1" --model brain

# 2. each fail mode: the matching gate must exit nonzero
start_mock needle
check "needle catches wrong recall" fail "$PY" "$EVAL_DIR/needle.py" \
  --base-url "http://127.0.0.1:$PORT/v1" --model brain --context-tokens 2000 --depths 10,50,90
start_mock schema
check "behavior catches broken JSON" fail "$PY" "$EVAL_DIR/behavior_suite.py" \
  --base-url "http://127.0.0.1:$PORT/v1" --model brain
start_mock tools
check "behavior catches tools-in-content" fail "$PY" "$EVAL_DIR/behavior_suite.py" \
  --base-url "http://127.0.0.1:$PORT/v1" --model brain
start_mock down
check "bench dies on 500s" fail "$PY" "$EVAL_DIR/bench_decode.py" \
  --base-url "http://127.0.0.1:$PORT/v1" --model brain --runs 1 --gen-tokens 16
stop_mock

echo
echo "== selftest results =="
cat "$LOGDIR/table"
if [ "$FAILED" -eq 0 ]; then
  echo "== selftest: PASS (gate logs: $LOGDIR) =="
else
  echo "== selftest: FAIL — do NOT trust the gates on delivery day. Logs: $LOGDIR =="
fi
exit $FAILED
