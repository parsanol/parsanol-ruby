# 8 — Cross-engine differential fuzzing; verified core research

Status: **Track A done; Track B revised and open (B1/B2 build items).**
Track A: seeded random-grammar four-path differential (native / VM /
interpreter / wasm) with a wasm replay leg, nightly on schedule; first
runs green. Track B: the original Isabelle-first plan was superseded by
the owner's 2026-10-22 decision — a maintained second interpreter is
rejected; instead B1 (reference mode on the existing walker, memo/VM
off, as a fifth fuzz path), B2 (a one-shot validator written from the
semantics doc, run once, archived — never maintained), and B3
(generated Isabelle proofs, deferred with re-trigger conditions).

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

## Track B — verified core (revised 2026-10-22; owner-directed)

**Decision (owner, 2026-10-22):** the debugging value of an
independent reference is wanted; a *maintained* second interpreter is
not. The original Isabelle/M1 plan is superseded by three work items —

### B1 — Reference mode in the existing engine (build item)

A thin gate on the Rust walker: memoization off, optimizations off,
the plain recursive relation exactly as `docs/parg-semantics.md`
states it. No new interpreter — the same walker behind a
configuration flag (like the existing no-cache paths), so there is no
second implementation to maintain.

- Work: a `reference` constructor/config on `PortableParser` that
  disables the dense cache, the VM, dispatch tables, and any
  transformation that the spec calls an unobservable optimization
  (E1); a corpus replay through reference mode in CI beside the
  existing four-path fuzz.
- Acceptance: the whole conformance corpus passes identically in
  reference mode; the differential fuzz gains a fifth path; the gate
  costs nothing when off (a config check at construction).

### B2 — One-shot corpus validator (build-then-archive item)

A throwaway implementation of the match relation written *from the
document* (positions, terminals, combinators, captures, flatten laws
V1-V3, C1-C8, K1-K3 — no skip injection; skip is a compile-time
rewrite the artifact never sees). Run it against the corpus and the
fuzz fixtures once; every divergence is either an engine bug or a spec
bug — both closed. Then ARCHIVE it: it is deliberately NOT maintained.

- Work: the validator (its own directory, clearly marked disposable),
  a diff runner, a report; a re-run note in the semantics doc ("re-run
  the validator when the match relation changes").
- Acceptance: corpus + a fuzz-fixture batch replayed with a written
  report; every divergence triaged; the validator lands under
  `tools/` (or is attached to the report issue) and never in `lib/`.
- Re-trigger: the match relation in `docs/parg-semantics.md` changes
  materially (a new combinator, a changed flatten law).

### B3 — Generated proofs (deferred, conditions stated)

Isabelle/HOL extraction (Nipkow & Dilleda precedent) stays deferred:
it does not have the maintenance problem (extracted code is
generated), but it costs months of toolchain work for the same value
B1+B2 deliver now. Reconsider only when: (a) a regulatory/assurance
need for machine-checked semantics appears, or (b) B2's one-shot runs
keep surfacing spec-level ambiguities that human review cannot close.

### Non-goals

- A hand-written reference interpreter shipped in `lib/` and maintained
  alongside the engines — rejected by the owner (2026-10-22): every
  language change would need a second update site, and a buggy
  maintained oracle cannot arbitrate disagreements.
- Track A changes — the nightly four-path fuzz is the standing
  differential and stays as shipped.

## Acceptance

Track A: the fuzzer runs nightly with a dashboard; every minimized
disagreement becomes a closed issue with a regression seed. Track B:
B1 shipped (reference mode + fifth fuzz path), B2 run once with a
report and archived; B3 documented with its re-trigger conditions.
