#!/usr/bin/env python3
"""mock_openai_server.py — offline stand-in for the gateway. Stdlib only (ADR-7).

Purpose: the four gates (smoke/bench/needle/behavior) must work FIRST TRY on
delivery day. This mock keys its responses on the request so each gate
exercises its real code path — and its fail modes prove each gate FAILS when
it should. A gate that can't fail is not a gate.

Driven by eval/selftest.sh. Not part of delivery-day validation itself.

Usage:
  python eval/mock_openai_server.py --port 8765
  MOCK_FAIL=needle python eval/mock_openai_server.py --port 8765

Fail modes (env MOCK_FAIL or --fail):
  needle  return a wrong recall code       -> needle.py must exit 1
  schema  return broken JSON               -> behavior_suite.py must exit 1
  tools   put the call in message.content  -> behavior_suite.py must exit 1
  down    500 every chat request           -> bench_decode.py must exit nonzero
"""
import argparse, json, os, re, sys, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

NEEDLE_RE = re.compile(r"WT-[A-Z0-9]{8}")
QUOTED_RE = re.compile(r"'([^']+)'")

BENCH_FILLER = (
    "Double-entry bookkeeping records every transaction twice, once as a debit "
    "and once as a credit, so the ledger stays in balance and errors surface as "
    "differences instead of silent drift across the trial balance. "
)

# One entry per behavior_suite.py SCHEMA_TASKS prompt: distinctive fragment ->
# object with the required keys, correctly typed. Keep in lockstep with the suite.
SCHEMA_ANSWERS = [
    ("Atlas Paving", {"name": "Atlas Paving LLC", "entity_type": "S-corp",
                      "fye": "12/31", "employee_count": 14}),
    ("Form 1065 preparation", {"description": "Form 1065 preparation",
                               "quantity": 1, "unit_price": 1850.00}),
    ("AMZN Mktp", {"payee": "AMZN Mktp", "amount": 214.66,
                   "suggested_account": "Supplies", "confidence": 0.72}),
    ("individual extension deadline", {"form": "4868", "tax_year": 2025,
                                       "due_date": "2026-10-15"}),
    ("ERC refund", {"topic": "ERC refund taxability", "action_required": True,
                    "owner": "staff"}),
    ("Payroll journal stub", {"gross": 12400.00, "employer_taxes": 948.60,
                              "net": 9377.15}),
    ("monthly bookkeeping", {"service": "monthly bookkeeping", "bank_accounts": 2,
                             "credit_cards": 1, "frequency": "monthly"}),
    ("CP2000", {"notice_type": "CP2000", "tax_year": 2024,
                "proposed_amount": 3214.0, "respond_by_priority": "high"}),
]

# One entry per behavior_suite.py ADHERENCE_TASKS prompt: fragment -> exact reply.
ADHERENCE_ANSWERS = [
    ("exactly one sentence",
     "The safe harbor lets you avoid an underpayment penalty by paying 100 "
     "percent of last year's tax or 90 percent of this year's tax."),
    ("single word ACKNOWLEDGED", "ACKNOWLEDGED"),
    ("comma-separated line", "straight-line, declining balance, units of production"),
    ("yes or no only", "yes"),
]


def classify(req, fail):
    """Return (kind, assistant message dict, finish_reason) for a chat request."""
    model = req.get("model", "unknown")
    text = "\n".join(str(m.get("content") or "") for m in (req.get("messages") or []))

    # tool channel: only the behavior tool tasks send "tools"
    if req.get("tools"):
        m = QUOTED_RE.search(text)
        args = json.dumps({"name": m.group(1) if m else "Atlas Paving LLC"})
        if fail == "tools":  # the classic broken parser: call leaks into content
            return "tools", {"role": "assistant",
                             "content": f"lookup_client({args})"}, "stop"
        return "tools", {"role": "assistant", "content": None,
                         "tool_calls": [{"id": "call_0", "type": "function",
                                         "function": {"name": "lookup_client",
                                                      "arguments": args}}]}, "tool_calls"

    # needle: planted code in the haystack -> perfect recall (or forced miss)
    m = NEEDLE_RE.search(text)
    if m:
        code = m.group(0)
        if fail == "needle":  # deterministic wrong recall, never collides
            code = code[:-1] + ("0" if code[-1] != "0" else "1")
        return "needle", {"role": "assistant", "content": code}, "stop"

    # smoke: echo the request's model, exactly as asked
    if "Reply with exactly:" in text:
        return "smoke", {"role": "assistant", "content": f"OK {model}"}, "stop"

    for frag, obj in SCHEMA_ANSWERS:
        if frag in text:
            content = '{"broken": ' if fail == "schema" else json.dumps(obj)
            return "schema", {"role": "assistant", "content": content}, "stop"

    for frag, ans in ADHERENCE_ANSWERS:
        if frag in text:
            return "adherence", {"role": "assistant", "content": ans}, "stop"

    # anything else is bench prose: honor max_tokens, 1 mock token == 1 word
    n = max(1, int(req.get("max_tokens") or 128))
    unit = BENCH_FILLER.split()
    words = (unit * (n // len(unit) + 1))[:n]
    return "bench", {"role": "assistant", "content": " ".join(words)}, "stop"


class Handler(BaseHTTPRequestHandler):
    fail = ""  # set in main()

    def log_message(self, fmt, *args):  # replaced by _log: one line per request
        pass

    def _log(self, kind, code):
        print(f"[mock] {self.command} {self.path} kind={kind} "
              f"fail={self.fail or '-'} -> {code}", file=sys.stderr, flush=True)

    def _json(self, code, obj, kind):
        body = json.dumps(obj).encode()
        try:
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except OSError:
            kind += " (client gone)"
        self._log(kind, code)

    def do_GET(self):
        if self.path.rstrip("/") == "/v1/models":
            data = [{"id": m, "object": "model", "owned_by": "mock"}
                    for m in ("brain", "coder", "fleet", "frontier")]
            self._json(200, {"object": "list", "data": data}, "models")
            return
        self._json(404, {"error": {"message": f"no route: {self.path}"}}, "unknown")

    def do_POST(self):
        if self.path.rstrip("/") != "/v1/chat/completions":
            self._json(404, {"error": {"message": f"no route: {self.path}"}}, "unknown")
            return
        try:
            n = int(self.headers.get("Content-Length") or 0)
            req = json.loads(self.rfile.read(n) or b"{}")
        except (ValueError, OSError):
            self._json(400, {"error": {"message": "bad request JSON"}}, "badreq")
            return
        if self.fail == "down":
            self._json(500, {"error": {"message": "mock forced down (MOCK_FAIL=down)"}},
                       "down")
            return
        kind, msg, finish = classify(req, self.fail)
        prompt_toks = sum(len(str(m.get("content") or "").split())
                          for m in (req.get("messages") or []))
        comp_toks = len((msg.get("content") or "").split())  # truthful for content replies
        self._json(200, {
            "id": "chatcmpl-mock", "object": "chat.completion",
            "created": int(time.time()), "model": req.get("model", "unknown"),
            "choices": [{"index": 0, "message": msg, "finish_reason": finish}],
            "usage": {"prompt_tokens": prompt_toks, "completion_tokens": comp_toks,
                      "total_tokens": prompt_toks + comp_toks},
        }, kind)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--fail", default=os.environ.get("MOCK_FAIL", ""),
                    choices=["", "needle", "schema", "tools", "down"],
                    help="force a failure the matching gate must catch")
    a = ap.parse_args()
    Handler.fail = a.fail
    srv = ThreadingHTTPServer(("127.0.0.1", a.port), Handler)
    srv.daemon_threads = True
    print(f"[mock] serving on 127.0.0.1:{a.port} fail={a.fail or '-'}",
          file=sys.stderr, flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
