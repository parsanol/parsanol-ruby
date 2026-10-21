# 1 — Error recovery: partial trees with annotated failures

Status: **R1 + R1.5 shipped** (R1: rs#249, ruby#241, ts#11, rs#253 wasm
binding; R1.5 partial trees: rs#274 + ruby#272 — the recovery envelope
carries the deepest repetition prefix shaped like the root, both
engines, zero success-path cost; the ruby side also fixed the two
recovery-offset expectations by reporting the deepest cause-tree
position, the rs failure-wire semantics). Remaining: R2 (resync — a
grammar addition, owner gate) and the wasm/ts propagation of the
`partial` key with the cross-engine canonical-equality differential.

## Findings that shaped the shipped scope (2026-10-20)

- The capture store's generational undo log empties the visible store
  on the failing branch — that rollback IS the correctness mechanism,
  so partial captures require an opt-in append-only journal (the rs
  recovery journal; ruby journals via the interpreter's diagnostic
  reparse).
- Rule-`as` captures are TREE-level in the portable engine and never
  reach the capture store: partial-TREE recovery (R1.5) requires the
  walker/VM to retain a best-partial-root — an engine capability, not
  a policy. Specced as the next engine work; R2 composes after it.

## SOTA reference points

- **tree-sitter**: cost-model-based recovery; every parse returns a tree
  with synthetic ERROR nodes; this is what makes editors possible.
- **ANTLR**: resynchronization sets + rule-level recovery strategies.
- **PEG error reporting** (the LabLua line — Maidl, Mascarenhas,
  Medeiros, Ierusalimschy): expected-set computation over PEG structure.
- parsanol already has the diagnostics half: deepest-failure cause
  trees, wire-format diagnostics, expected sets. Recovery is a *policy
  over* that machinery.

## Design (tiered — ship incrementally)

### R1 — root-level best-effort partial trees (MVP)

`parse(entry, input, recovery: :best_effort)` — on ParseFailed, instead
of raising: return the deepest viable partial result annotated with the
failure. Shape:

    { ok: false,
      partial: <tree of successful captures up to the failure>,
      error:   { offset:, expected:, cause: <cause tree> } }

- Locus: the portable parser already retains matched structure in its
  arena at failure time (failure diagnostics are computed from it) —
  expose the successful prefix as a shaped tree.
- Ruby interpreter: same via the existing cause-tracker pass.
- **Zero cost on success paths**: recovery only activates on failure.
  Assert with a benchmark (no perf regression on green inputs).

### R2 — skip-and-resync recovery

On failure, resync to a declared or inferred synchronization point and
continue, producing a tree with `error` nodes at the resync positions.
Cost model first-candidate: skip-to-line / skip-to-delimiter (mirrors
ANTLR); per-rule `resync <pattern>` declaration in PARG if warranted
(grammar-language addition = owner gate).

### R3 — integration

LSP diagnostics consume R1/R2 (parse-with-recovery on every keystroke);
corpus cases pin recovered shapes cross-engine; the guide documents the
recovery contract.

## Acceptance

- Cross-engine: ruby (interpreter + VM), rs portable, wasm — identical
  partial trees and error annotations (canonical equality, as usual).
- Corpus cases: truncated inputs, mid-rule failures, multi-error inputs
  (R2).
- Success-path benchmark: no measurable regression; recovery benchmark:
  bounded by input length.
- Specs with real objects; cause-tree output unchanged for
  non-recovery parses.

## Engine matrix

rs portable parser (source of truth) → ruby interpreter + VM → wasm
re-vendor → ts tests.
