#!/usr/bin/env python3
"""needle.py — retrieval-at-depth gate for long context. Stdlib only.

Encodes the rule from the cluster-lane review: an ADVERTISED max_model_len is
not a retrieval guarantee. Before trusting any lane at depth D with client
work, it must recall an exact planted fact at that depth, at the start, and in
the middle. Run at the context sizes you actually use (a 300-page workpaper
bundle ~= 200-300K tokens), not at the marketing number.

Usage:
  eval/needle.py --base-url http://127.0.0.1:8888/v1 --model default \
                 --context-tokens 100000 --depths 10,50,90
Exit code 0 only if every depth passes.
"""
import argparse, json, random, string, sys, urllib.request

FILLER = (
    "The quarterly close process reconciles subledgers to the general ledger, "
    "reviews accrual reasonableness, and documents variances beyond threshold. "
    "Fixed asset rollforwards tie additions and disposals to source invoices. "
    "Payroll clearing accounts must net to zero after each cycle posts. "
)

def build_haystack(target_tokens: int, needle: str, depth_pct: int) -> str:
    words_needed = int(target_tokens / 1.33)          # rough tok->word
    unit = FILLER.split()
    reps = max(1, words_needed // len(unit) + 1)
    words = (unit * reps)[:words_needed]
    pos = min(len(words) - 1, max(0, int(len(words) * depth_pct / 100)))
    words.insert(pos, needle)
    return " ".join(words)

def ask(base, model, context, question, max_tokens=64, timeout=1800):
    req = urllib.request.Request(
        f"{base.rstrip('/')}/chat/completions",
        data=json.dumps({
            "model": model, "temperature": 0.0, "max_tokens": max_tokens,
            "messages": [
                {"role": "system", "content": "Answer with the exact requested value only."},
                {"role": "user", "content": context + "\n\n" + question},
            ]}).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        body = json.loads(r.read())
    # content can be null on reasoning models — never crash, let the gate judge
    return ((body.get("choices") or [{}])[0].get("message") or {}).get("content") or ""

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", required=True)
    ap.add_argument("--model", required=True)
    ap.add_argument("--context-tokens", type=int, default=100000)
    ap.add_argument("--depths", default="10,50,90")
    ap.add_argument("--max-tokens", type=int, default=64,
                    help="raise for reasoning-mode models that spend the budget thinking")
    a = ap.parse_args()

    failures = 0
    for depth in [int(d) for d in a.depths.split(",")]:
        code = "WT-" + "".join(random.choices(string.ascii_uppercase + string.digits, k=8))
        needle = f"[CONTROL NOTE] The wire transfer confirmation code for the Henderson estate is {code}."
        hay = build_haystack(a.context_tokens, needle, depth)
        try:
            ans = ask(a.base_url, a.model, hay,
                      "What is the wire transfer confirmation code for the Henderson estate?",
                      max_tokens=a.max_tokens)
        except Exception as e:
            print(f"  FAIL  depth {depth}%: request error: {e}")
            failures += 1
            continue
        if code in ans:
            print(f"  PASS  depth {depth}% @ ~{a.context_tokens} tok")
        else:
            hint = ("  (empty content: reasoning-mode models may need --max-tokens headroom)"
                    if not ans.strip() else "")
            print(f"  FAIL  depth {depth}% @ ~{a.context_tokens} tok -> got: {ans[:120]!r}{hint}")
            failures += 1

    print(f"== needle: {'PASS' if failures == 0 else f'{failures} FAIL'} "
          f"@ ~{a.context_tokens} tokens ==")
    if failures:
        print("   Do NOT use this lane at this depth for client work. Retest after")
        print("   any KV-dtype, context-target, or engine change.")
    sys.exit(1 if failures else 0)

if __name__ == "__main__":
    main()
