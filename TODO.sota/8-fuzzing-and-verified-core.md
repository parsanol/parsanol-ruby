# 8 — Cross-engine differential fuzzing; verified core research

Status: open — Tier 3. Two independent tracks.

## Track A — cross-engine differential fuzzing (practical, do first)

**Claim**: for any grammar and any input, all engines agree on
acceptance and the canonical tree. Make it a tested property.

1. **Random grammar generator** (proptest is already a dev dep):
   generate bounded, terminating PARG grammars — every rule reachable,
   repetition bounds finite, no left recursion (until 5 ships),
   alternating shapes (captures/unnamed, reps of sequences — the #231
   class, maybe/nesting depth).
2. **Random input generator** per grammar (sample from the grammar's
   language where computable, else mutate corpus inputs).
3. **Differential assertion**: ruby interpreter == ruby VM == rs ==
   wasm on acceptance + canonical tree. A disagreement is a semantic
   drift bug with a minimized case (proptest shrinking) — file it, fix
   it, keep the seed as a regression.
4. Run in CI nightly (bounded budget), plus on-demand.

This would have caught the #36/#231/#90-class divergences at birth.

## Track B — verified core (research)

- Precedent: a machine-verified packrat parser exists in Isabelle/HOL
  (Nipkow & Dilleda). Path: formalize the portable engine's core match
  relation in Isabelle or Coq; prove the compiled artifact semantics
  match 3-parg-formal-spec; extract or validate.
- Honest framing: research-tier, no ship date; value accrues even from
  the formalization attempt (ambiguities in the semantics surface).
- Prerequisite: 3-parg-formal-spec must exist first.

## Acceptance

Track A: the fuzzer runs nightly with a dashboard; every minimized
disagreement becomes a closed issue with a regression seed. Track B: a
written formalization scoping document before any proof work.
