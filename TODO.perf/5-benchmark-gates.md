# 5 — Benchmark gates that keep performance excellent

Status: DONE (2026-09-22) — benchmark/ci_gate.rb + weekly
.github/workflows/perf-gate.yml: median-of-5 ips over the canonical
corpus, baseline = previous GREEN run (red runs cannot poison it),
fails on >25% median regression, 90-day artifacts + step summary.

## Problem

The perf specs in CI are wall-clock asserts on shared runners — this session
already produced a 0.79x-vs-0.80x flake. They catch order-of-magnitude
regressions only.

## Work items

1. Canonical corpus checked into `benchmark/inputs` (JSON, ERB, calc,
   issue #25 AsciiChem at 10B / 27KB sizes).
2. `benchmark/compare.rb`: runs parslet vs `mode: :ruby` vs native with
   benchmark-ips, prints the table used in PR descriptions.
3. Rust: criterion benches already exist in parsanol-rs `benches/`; add a
   `collapse_ast` + `parse_handle` micro-bench.
4. CI gate (weekly cron, not per-PR): run the corpus, store results as
   workflow artifacts, fail only on >25% regression vs the stored baseline
   (statistical, median-of-N, not single-shot).
5. Document the numbers in `HISTORY.txt`-style release notes so regressions
   are visible in diffs.
