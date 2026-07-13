# Docs Index — spark-landing-kit v0.2

**Build receipt.** Assembled 2026-07-13 by Claude + VR from field-verified
GB10 deployment reports current as of that date. Integrity manifest:
`docs/MANIFEST.sha256`. Anything time-sensitive (image tags, model IDs,
reference throughput numbers) carries that date implicitly — reverify pins
the week hardware arrives.

## Reading order

| # | File | Read when |
|---|------|-----------|
| 00 | `00-PRD.md` | You want to know *why this exists* and what success is |
| 01 | `01-ARCHITECTURE.md` | You want to know *how it's shaped* and why |
| 02 | `02-HOWTO.md` | Hardware is in front of you |
| 03 | `03-VALIDATION.md` | Before promoting anything into service |
| 04 | `04-REGRESSION.md` | Before/after changing anything already in service |
| 05 | `05-MODEL-AGNOSTIC-SLOTS.md` | Before swapping or adding any model |
| 06 | `06-HANDOFF-PICKUP.md` | Starting or ending any agent work session |
| 07 | `07-DEFINITION-OF-DONE.md` | You want to know what's left |

## Ground rules that apply across all docs

1. **Source of truth is layered:** hardware behavior > `ops/RUNBOOK.md` >
   these docs > memory of any conversation. When they disagree, update
   downstream from the truth.
2. **Models are tenants, lanes are contracts** (doc 05). No doc names a model
   as load-bearing; reference tenants are examples that met the contract on
   the build date.
3. **Nothing enters service without its gates** (doc 03), and nothing changes
   in service without its regression set (doc 04).
4. **Every agent session ends with a handoff artifact** (doc 06). No
   exceptions, including sessions that "just looked around."
5. Mirror docs 03–07 into hermes-brain as living pages; this repo copy is the
   bootstrap.
