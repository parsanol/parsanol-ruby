# 3 — Formal operational semantics of PARG

Status: open — Tier 1. The conformance corpus already behaves like a
spec; make the derivation explicit.

## Goal

`docs/parg-semantics.md`: a small-step operational semantics of the PARG
core (sequence, ordered choice, repetition, maybe, predicates, char
classes, skip/trivia injection, capture, bindings application,
preprocess) written as normative rules — the document that defines what
every engine MUST do, of which the guide is the friendly edition.

## Method

1. One rule per construct: match relation, capture semantics, failure
   semantics, diagnostics obligation.
2. **Coverage matrix**: every corpus case cites the semantic rule(s) it
   pins; every rule cites its cases. Gaps in either direction are TODO
   corpus cases (rule 3 of the corpus: the red case is the issue
   tracker).
3. Known sharp edges get explicit rules, not prose: the repetition
   flatten laws (parslet parity, #231), skip injection vs atomic rules,
   trivia capture attachment (#152), VM decline conditions, uncaptured
   sequence propagation.

## Stretch

A reference interpreter of the semantics (straightforward Ruby from the
rules) as a cross-check oracle: fuzz random grammars, compare the
reference interpreter against all engines (feeds 8-fuzzing). The
reference interpreter is SLOW by design — it is the spec, executable.

## Acceptance

- Every current corpus case mapped to rules; no unmapped behavior.
- New corpus PRs fail review without rule citations (README rule).
- The guide links the semantics doc; both stay in sync via the corpus
  gate.
