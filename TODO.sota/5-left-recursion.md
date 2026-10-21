# 5 — Left recursion in PARG (owner gate: deliberate parslet extension)

Status: done — owner approved the ANTLR-style rewrite (2026-10-21).
Direct left recursion is rewritten at compile time into left-folding
tier rules (C9 in docs/parg-semantics.md): branches in source order are
precedence tiers, earlier binding tighter; the non-recursive
alternatives are the primary; indirect recursion stays a compile error.
The artifact carries ordinary atoms, so every engine inherits the
semantics with no engine work; the fold value is the flattening of the
equivalent loop grammar (V1/V3). Corpus case `leftrec_arith` pins
tiered precedence, associativity, and fold shape.

**Gate: this is a deliberate extension of the
parslet contract (parslet cannot do left recursion), so it needs an
explicit owner decision before implementation.**

## SOTA reference points

- **Warth & Millstein** — packrat labelling: left-recursive rules grow
  their seed on repeated invocation (direct + indirect, general).
- **Medeiros & Tratt** — skeleton semantics for left-recursive PEGs;
  semantic analysis of which forms terminate.
- **ANTLR 4** — the engineering gold standard: rewrite direct
  left recursion into precedence climbing at build time; reject
  indirect with a precise error.

## Design

- **MVP (ANTLR-style rewrite)**: direct left recursion of the shape
  `e = e op t / t` (and a bounded chain of precedences) rewritten at
  compile time to a left-fold: match `t`, then loop on `op t`,
  associativity + precedence from declared levels. The rewrite happens
  in the compiler; the envelope carries the transformed atoms — the
  artifact contract is unchanged, so ALL engines get it without engine
  changes. Capture semantics of the fold (what `as` binds per level)
  must be specced in 3-parg-formal-spec first.
- **Full labelling (Warth)**: runtime growing-seed in the packrat
  engines for the general/indirect case — research-grade, only after the
  MVP proves demand.
- Lint upgrade: today's left-recursion rejection becomes a
  "left-recursive but not rewriteable" precise error.

## Acceptance

Corpus cases per precedence pattern; envelope atoms cross-engine
identical (compile-time rewrite = free parity); the differential vs
parslet documents the extension explicitly (parslet cannot run these
grammars at all).

## Owner-gate checklist

Semantics of `as` in folds; whether indirect recursion stays rejected;
whether the extension is documented as a parsanol feature or an
opt-in `recursive = true` grammar declaration.
