# 2 — Published benchmarks vs the SOTA tools

Status: **done — Tier 1.** All five corpora committed with harnesses
(JSON, traps, pubid, asciichem, EXPRESS giants) and the full results
table measured: session 2 (2026-10-22, load 10-21, N=50) put ALL
SEVEN rows in one session — tree-sitter, pest, Lark, parsanol-native,
parslet, and both parsanol-ruby engines — so the within-session
ratios are the meaningful numbers, and they match session 1's partial
ratios. Headline: parsanol-native beats parslet 3.6x on large and
both parsanol-ruby engines beat it ~1.35x; tree-sitter (~62x) and
pest (~58x) quantify the gap that motivates the codegen direction.
parsanol-only rows (pubid/asciichem/EXPRESS) carry their load
conditions in BENCHMARKS.md. Competitor grammar ports for
pubid/asciichem/EXPRESS remain future work — no cross-tool ratio is
claimed without them.

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
