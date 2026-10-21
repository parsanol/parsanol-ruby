# 2 — Published benchmarks vs the SOTA tools

Status: in progress — Tier 1. v1 shipped (#246): seeded JSON corpus,
genuine harnesses for tree-sitter/Lark/parsanol-artifact, methodology
and honest results in the root `BENCHMARKS.md`. All five harnesses
now exist: pest fixed (#247 was the grammar's missing-escape bug, not
unicode), parslet legacy baseline added, parsanol Ruby API in both
modes (:native and :ruby). Corpora: JSON, a nine-document pathological
set, the pubid ISO suite (vendored contract artifact with
provenance, 175 verified identifiers, harness `entry` argument;
parsanol-only because competitor grammars do not exist), the asciichem
suite (145 accepted fixtures replayed through the vendored artifact,
both engines), and the EXPRESS giants (two real ISO 10303 schemas,
637 KB and 4.2 MB, parsed through expressir's production DSL grammar
in both engines). Remaining: one quiet-host rerun to fill the pending
rows (the host has stayed at load >80 all session, spiking past 280).
Competitor grammar ports for asciichem/EXPRESS are tracked as future
work — no cross-tool ratio is claimed without them.

## Goal

A published, honest benchmark methodology comparing parsanol (native +
VM) against **pest** (Rust PEG), **tree-sitter** (C, error-tolerant),
and **Lark** (Python, Earley/LALR) on shared corpora — with parslet kept
as the legacy baseline.

## Corpora

1. pubid identifier suite (real-world structured identifiers)
2. asciichem (formulae, mid-size inputs)
3. JSON (machine grammar, high throughput)
4. EXPRESS giants (600 KB+ real files — the large-input case)
5. a backtracking-heavy pathological set (documented traps)

## Methodology laws (from measured lessons)

- Interleaved same-condition A/B with `GC.start` between runs; never
  sequential (GC-order bias measured 2.68x vs 3.88-4.36x fair).
- Median-of-N with warmup documented; report warm AND cold (VM
  memoization + artifact caches are warm-path).
- No tiny-input ratios — they flip on scheduler noise.
- Pin competitor versions; record machine + load conditions.
- The existing ci statistical perf-gate (benchmark/ci_gate.rb) is the
  regression harness; extend it to track the cross-tool baselines.

## Deliverables

- `BENCHMARKS.md` at the repo root: methodology, corpora, results,
  links to run scripts.
- `benchmark/sota/`: one harness per competitor, committed, runnable.
- Honest result publication: if a competitor wins a corpus, publish
  that too — the audit culture applies to marketing.

## Acceptance

Every claim in the README/guide traceable to a committed harness; no
ratio published without its methodology; SOTA gaps that the benchmarks
reveal become TODO items here, not embarrassment to hide.
