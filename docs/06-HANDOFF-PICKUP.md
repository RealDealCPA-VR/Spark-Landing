# Handoff & Pickup — protocol for long-running coding tasks

For any work on this platform that spans more than one sitting or more than
one agent/model session (Claude Code, local coder lane, Iron Jarvis, or VR
himself in two weeks). Context windows die; **state lives in files or it
doesn't exist.**

## 1. Principles

1. **Verified ≠ written.** Every handoff separates *verified-by-running*
   from *written-but-unverified*. A pickup session treats unverified items
   as hypotheses and re-verifies before building on them.
2. **Smallest-diff discipline.** One concern per change; runnable state
   between changes; never park the system broken at session end without
   saying so in red letters.
3. **Gates are law for agents too.** No agent edits thresholds, disables a
   failing test, or retries-until-green. A failing gate is a *finding* —
   escalate in the handoff.
4. **Destructive commands are opt-in.** `docker rm -f`, cache drops, netplan
   writes, weight deletions: check current state first, and never re-run a
   prior session's destructive step just because it's in the log.
5. **Record knife-edges immediately.** Any discovered magic value (GMU,
   GID index, working flag combo) goes into the session log the moment it's
   found, and into the lane's evidence page at handoff — not "later."

## 2. Artifacts & layout

```
ops/sessions/
├── STATE.md                     # ONE living file: current truth
├── DECISIONS.md                 # append-only ADR-lite log
└── 2026-07-13T2130-claude.md    # one handoff file per session (template §4)
```

- `STATE.md` is rewritten (not appended) at each handoff to reflect *now*:
  active mode, lane tenants + ports, in-flight task, environment deltas from
  repo defaults.
- `DECISIONS.md` gains a line whenever a choice forecloses alternatives
  ("chose X over Y because Z").
- Handoff files are immutable once written.

## 3. Session lifecycle

**PICKUP (first 10 minutes, in order):**
1. Read `STATE.md`, then the most recent handoff file, then `DECISIONS.md`
   tail. Skim `ops/RUNBOOK.md` diff if the repo changed.
2. **Verify reality matches STATE:** `git status && git log -3`,
   `docker ps` on both nodes, `eval/smoke.sh`. Note any mismatch in your
   session log *before* fixing anything.
3. Re-verify anything the last handoff marked unverified *if your task
   builds on it*; otherwise leave it flagged.
4. Restate the task in one sentence in your session file. If it doesn't
   match the last handoff's "next actions," reconcile explicitly.

**DURING:** keep a running log in your session file (commands that mattered,
values discovered, dead ends with cause). Commit early with `wip:` prefixes;
one logical change per commit; never force-push.

**HANDOFF (last 10 minutes, non-negotiable even for "just looked around"):**
1. Fill the template (§4) completely — empty sections say `none`.
2. Rewrite `STATE.md`.
3. Leave the system in a *declared* state: serving normally, or explicitly
   `DEGRADED:` with what's down and why.
4. If a gate/regression row was triggered by your changes and not completed,
   the first "next action" is completing it.

## 4. Handoff template (copy verbatim)

```markdown
# Handoff — <ISO datetime> — <agent/human id>
## Task
<one sentence; link to DoD item or issue>
## System state at exit
mode: solo|cluster|down|DEGRADED(<what/why>)
branch/commit: <git ref>   uncommitted: yes/no(<what>)
lanes: BRAIN=<tenant@port up/down> CODER=<…> FLEET=<…> gateway=<up/down>
## Done this session (verified by running)
- <item — how it was verified (command/gate)>
## Written but NOT verified
- <item — exactly what verification is missing>
## Discovered values / landmines
- <e.g., GMU 0.847 boots, 0.85 OOMs on B with Whisper resident>
- DO NOT: <thing that looks safe but isn't, and why>
## Gates & regression status
- <matrix row triggered> → <gates run: results> ; outstanding: <list|none>
## Dead ends (so nobody repeats them)
- <approach — why it failed>
## Next actions (ordered, max 5)
1. <smallest next runnable step>
## Open questions for VR
- <decision needed|none>
```

## 5. Multi-agent etiquette

One writer at a time per node: check `STATE.md` for an `ACTIVE SESSION`
header before starting; set it at pickup, clear it at handoff. If a stale
lock is older than the last handoff timestamp, note it and take over.
Frontier agents plan and review; local lanes execute bulk edits — either
way, the artifact trail above is identical, which is what makes the
*maintainers* of this system as swappable as its models.

## 6. Definition of a good handoff

A stranger with this repo, hermes-brain access, and your handoff file can:
(a) reproduce your environment state, (b) know exactly what to trust,
(c) start productive work inside 15 minutes. If any of the three fails,
the handoff isn't done.
