#!/usr/bin/env python3
"""behavior_suite.py — the gate that catches what capability benchmarks miss.

Rationale (from the pruning discussion, but it applies to every quantized /
compressed / spec-decoded checkpoint): shallow behaviors regress first —
schema adherence, format discipline, tool-call validity, instruction
following under a long system prompt. In this stack those are load-bearing:
a model that drifts on JSON or emits tool calls into message.content is an
ops incident before it's an accuracy number.

Checks (stdlib only):
  1. JSON schema compliance x8   (parseable + required keys + types)
  2. Instruction adherence x4    (hard word limits, forbidden tokens)
  3. Tool-call channel x2        (tool_calls populated, arguments parse;
                                  SKIPPED cleanly if lane lacks tool support)
Gates: schema >= 7/8, adherence >= 3/4, tools 2/2 when applicable.

Usage: eval/behavior_suite.py --base-url http://gw:4000/v1 --model coder
Exit 0 only if all applicable gates pass. Re-run after ANY checkpoint swap.
"""
import argparse, json, sys, urllib.request

def post(base, payload, timeout=300):
    req = urllib.request.Request(
        f"{base.rstrip('/')}/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read())

SYS = ("You are the structured-output worker in an accounting automation "
       "pipeline. Output exactly what is asked. When asked for JSON, output "
       "only a single JSON object: no prose, no code fences.")

SCHEMA_TASKS = [
    ("Client record for 'Atlas Paving LLC', an S-corp with fiscal year end 12/31 "
     "and 14 employees.", ["name", "entity_type", "fye", "employee_count"],
     {"employee_count": int}),
    ("Invoice line: 'Form 1065 preparation', quantity 1, unit price 1850.00.",
     ["description", "quantity", "unit_price"], {"quantity": int, "unit_price": (int, float)}),
    ("Categorize this transaction: 'AMZN Mktp 4411 - $214.66' for a landscaping "
     "company. Keys: payee, amount, suggested_account, confidence (0-1).",
     ["payee", "amount", "suggested_account", "confidence"], {"confidence": (int, float)}),
    ("Deadline record: individual extension deadline for tax year 2025. Keys: "
     "form, tax_year, due_date (YYYY-MM-DD).", ["form", "tax_year", "due_date"], {}),
    ("Summarize: 'Client emailed asking whether the ERC refund is taxable.' "
     "Keys: topic, action_required (boolean), owner.",
     ["topic", "action_required", "owner"], {"action_required": bool}),
    ("Payroll journal stub: gross 12400.00, employer taxes 948.60, net 9377.15. "
     "Keys: gross, employer_taxes, net.", ["gross", "employer_taxes", "net"], {}),
    ("Engagement scope: monthly bookkeeping, 2 bank accounts, 1 credit card. "
     "Keys: service, bank_accounts, credit_cards, frequency.",
     ["service", "bank_accounts", "credit_cards", "frequency"], {"bank_accounts": int}),
    ("Notice triage: 'IRS CP2000 for 2024, proposed change $3,214.' Keys: "
     "notice_type, tax_year, proposed_amount, respond_by_priority (high/med/low).",
     ["notice_type", "tax_year", "proposed_amount", "respond_by_priority"], {}),
]

ADHERENCE_TASKS = [
    ("Explain estimated tax safe harbor in exactly one sentence.",
     lambda t: t.count(".") <= 2 and len(t.split()) <= 60),
    ("Reply with the single word ACKNOWLEDGED.",
     lambda t: t.strip().strip(".").upper() == "ACKNOWLEDGED"),
    ("List three depreciation methods as a comma-separated line, no other text.",
     lambda t: "\n" not in t.strip() and t.count(",") >= 2),
    ("Answer yes or no only: is Form 7004 an extension form?",
     lambda t: t.strip().strip(".").lower() in ("yes", "no")),
]

TOOLS = [{"type": "function", "function": {
    "name": "lookup_client",
    "description": "Look up a client record by business name",
    "parameters": {"type": "object",
                   "properties": {"name": {"type": "string"}},
                   "required": ["name"]}}}]

def strip_fences(t):
    t = t.strip()
    if t.startswith("```"):
        t = t.split("\n", 1)[-1]
        t = t.rsplit("```", 1)[0]
    return t.strip()

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--model", required=True)
    a = ap.parse_args()
    print(f"== behavior suite: {a.model} @ {a.base_url} ==")

    # 1. schema
    s_ok = 0
    for prompt, keys, types in SCHEMA_TASKS:
        try:
            body = post(a.base_url, {"model": a.model, "temperature": 0.0,
                                     "max_tokens": 300,
                                     "messages": [{"role": "system", "content": SYS},
                                                  {"role": "user", "content": prompt}]})
            obj = json.loads(strip_fences(body["choices"][0]["message"]["content"]))
            assert all(k in obj for k in keys)
            for k, ty in types.items():
                assert isinstance(obj[k], ty), f"{k} wrong type"
            s_ok += 1
        except Exception as e:
            print(f"  schema miss: {prompt[:48]!r}... ({e})")
    print(f"  schema compliance: {s_ok}/{len(SCHEMA_TASKS)}  (gate >= 7)")

    # 2. adherence
    a_ok = 0
    for prompt, check in ADHERENCE_TASKS:
        try:
            body = post(a.base_url, {"model": a.model, "temperature": 0.0,
                                     "max_tokens": 120,
                                     "messages": [{"role": "user", "content": prompt}]})
            if check(body["choices"][0]["message"]["content"]):
                a_ok += 1
            else:
                print(f"  adherence miss: {prompt[:48]!r}")
        except Exception as e:
            print(f"  adherence error: {e}")
    print(f"  instruction adherence: {a_ok}/{len(ADHERENCE_TASKS)}  (gate >= 3)")

    # 3. tool channel — THE silent-failure catcher. A wrong parser puts the
    # call in message.content and every agent downstream breaks quietly.
    t_ok, t_applicable = 0, True
    for q in ["Look up the client 'Brevard Marine Supply'.",
              "Find the record for 'Suntree Dental PA' using your tool."]:
        try:
            body = post(a.base_url, {"model": a.model, "temperature": 0.0,
                                     "max_tokens": 200, "tools": TOOLS,
                                     "tool_choice": "auto",
                                     "messages": [{"role": "user", "content": q}]})
            msg = body["choices"][0]["message"]
            calls = msg.get("tool_calls") or []
            if calls and json.loads(calls[0]["function"]["arguments"]).get("name"):
                t_ok += 1
            else:
                print(f"  tool miss: no tool_calls; content was: "
                      f"{(msg.get('content') or '')[:80]!r}")
        except urllib.error.HTTPError as e:
            print(f"  tool channel unsupported on this lane (HTTP {e.code}) — skipping gate")
            t_applicable = False
            break
        except Exception as e:
            print(f"  tool error: {e}")
    if t_applicable:
        print(f"  tool-call channel: {t_ok}/2  (gate = 2)")

    passed = s_ok >= 7 and a_ok >= 3 and (not t_applicable or t_ok == 2)
    print(f"== behavior suite: {'PASS' if passed else 'FAIL'} ==")
    if not passed:
        print("   Do not wire this lane into vr-dispatch. Fix parser/config or"
              " swap checkpoints, then re-run.")
    sys.exit(0 if passed else 1)

if __name__ == "__main__":
    main()
