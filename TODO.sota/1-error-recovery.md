# 1 — Error recovery: partial trees with annotated failures

Status: open — Tier 1 flagship. The one SOTA frontier where parsanol has
zero presence.

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
