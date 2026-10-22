# Verified core — formalization scoping

*TODO.sota/8, Track B. This is a scoping document, not a proof. No proof work
starts until the scope below is accepted.*

> **Superseded in part (2026-10-22, owner-directed).** The debugging value of
> an independent reference is wanted, but a *maintained* second interpreter is
> rejected outright (every language change would need a second update site,
> and a buggy maintained oracle cannot arbitrate disagreements). The accepted
> plan in TODO.sota/8 now runs as B1 — a reference mode on the existing Rust
> walker (memoization and optimizations off) as a fifth differential path —
> and B2 — a one-shot validator written from this document's relation, run
> against the corpus once, reported, and archived, never maintained. The
> Isabelle milestones below (M1–M5) remain the basis for B3, deferred with
> re-trigger conditions in TODO.sota/8.

## Goal

Turn the normative rules in [parg-semantics.md](parg-semantics.md) into a
machine-checked definition of the portable engine's match relation, and use it
to validate the shipped engine. The value accrues even if the final
verification step is never reached: formalization forces every ambiguity in
the semantics into the open, where the corpus can pin it.

## What is in scope

The **artifact runtime**: given a `parsanol-tree/v2` portable grammar `G`, an
entry point, and an input byte string, the relation

```
(G, entry, w) ⇓ (p′, v)   or   ⊥(q, E)
```

as defined by M2/M3, V0–V4, T1–T6, C1–C8, K1–K3, F1, and the compile-time
obligations X1–X6 treated as assumptions about `G`.

Out of scope for the first proof:

- **The PARG frontend/compiler** (source parsing, `use` merges, skip
  injection, table expansion). The artifact is the contract; the compiler is
  covered by compile-parity and the corpus.
- **Bindings and preprocessing** (B1–B6). They are a post-parse data layer
  over the flattened tree, with no effect on acceptance.
- **Recovery** (E2): explicitly a superset journal, not part of the relation.
- **The `pest`-style extension tasks** (left recursion, task 5): the
  semantics assumes left recursion is rejected (X1).

## Why Isabelle/HOL first

Nipkow & Dilleda's verified packrat parser (Isabelle/HOL) is the closest
precedent: it formalizes PEG semantics relationally and extracts an
executable parser. Isabelle's `inductive` definitions map directly onto our
match relation, and code extraction gives a slow reference interpreter that
can be diffed against the engines — the same oracle idea as task 3's
stretch goal, but with proofs attached.

Coq is a viable alternative; the deciding factors are the existing PEG
library/hol precedent and code extraction ergonomics. The semantic model is
engine-independent, so the choice is not irreversible.

## Formalization plan

1. **Values and positions.** Byte positions, Unicode scalar matching for
   classes/`ANY`, text-as-value (representation erased), tagged
   sequence/repetition/maybe nodes. Prove the flattening laws V1–V3 as
   equations on values; the parslet-compatibility quirks (dropping non-map
   repetition iterations) are *obligations*, not conveniences.
2. **Terminals.** Literals, case-insensitive literals, classes, `%x`
   sequences, `ANY`, the zero-width marker. Each rule of T1–T6 becomes one
   inductive clause.
3. **Combinators.** M3 transactionality as an invariant on the relation
   (failure leaves no trace); C1–C6; C7 transparency (rule references add no
   tree level); C8 as a compiler-side property (no injection).
4. **Captures.** K1–K3 as a store threading through the relation, with a
   theorem that the store projection equals the capture tree the engines
   emit.
5. **Skip/trivia (S1–S6)** is a *source rewrite*. Prove the rewrite obligation
   instead of the runtime: an artifact compiled from a skip grammar is
   extensionally equal to the same grammar with explicit `skip?` inserted at
   the documented points. This mirrors how the implementation works and
   keeps the runtime relation small.
6. **Memoization transparency (E1).** Model the packrat cache as an
   unobservable auxiliary state; prove that cached and uncached runs produce
   the same relation result. This is the formal counterpart of the "engine
   decline is unobservable" rule.
7. **Extraction.** Extract a reference parser and a canonical-tree renderer;
   run it against the conformance corpus and the differential-fuzz fixtures.
   A mismatch is either an engine bug or a semantics bug — both are wins.

## Milestones and exit criteria

| Milestone | Deliverable | Exit criterion |
|---|---|---|
| M1 | Values, positions, terminals, combinators | Relation type-checks; corpus atoms_lexical/lookahead/rejects replayed on the extracted reference |
| M2 | Captures + flattening laws | Capture-tree projection theorem; repetition flatten laws proved |
| M3 | Memoization transparency | Cached/uncached equivalence theorem |
| M4 | Skip rewrite obligation | Rewrite-equivalence theorem for the skip corpus case |
| M5 (stretch) | Verified engine core | Extracted parser shipped as a slow oracle in CI |

## Risks and open questions

- **Bytes vs code points.** Positions are byte offsets, classes match code
  points. The model must state UTF-8 decoding as part of input well-formedness
  or carry an explicit byte/char boundary function.
- **Slice representation** is erased in V0; the engines' equality relies on
  canonicalization, so the model needs a canonicalization function and a
  theorem that engine trees and canonical trees agree.
- **Flattening quirks** (#231) look like bugs but are compatibility
  obligations; proving them keeps the temptation to "fix" them out of the
  engine.
- **Failure diagnostics** (F1) are only partly normative: the deepest
  position is specified, the message is not. The model should prove a lower
  bound on the reported position, not the rendered text.
- **Effort.** M1–M3 is a multi-month research effort; M4 depends on the skip
  rewrite formalization. No ship date is promised; M1's extracted reference
  is independently useful as the task-3 oracle.

## Prerequisite

The normative semantics document (task 3) must land and remain the single
source of truth. Every change to `docs/parg-semantics.md` that alters the
relation is a change to this scope.
