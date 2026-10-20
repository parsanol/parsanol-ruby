# SOTA roadmap — vision, tiers, execution laws

## The vision

parsanol's purpose, synthesized from what the project actually is:

1. **parslet semantics are the contract.** The Ruby DSL mirrors parslet;
   flatten rules are byte-for-byte ports; compatibility specs come from
   parslet's own suite; divergence claims are checked against the real
   gem before acceptance.
2. **Multi-engine execution is the implementation.** Ruby interpreter,
   Ruby bytecode VM, Rust packrat walker, Rust bytecode VM, wasm — one
   semantics, and the fast path must *beat* parslet, not match it.
3. **Compiled artifacts are the distribution.** PARG grammars compile to
   versioned, checksummed, provenance-stamped portable envelopes that
   every runtime consumes identically.
4. **Enforced cross-engine governance is the differentiator.** The
   conformance corpus, compile-parity, canonical equality, envelope
   self-tests, and shipped-artifact audits make "identical everywhere"
   an enforced property. This is rarer in the parsing world than any
   algorithm.

**Purpose in one sentence:** write a grammar once; compile it to a
verified portable artifact; get byte-identical trees, rich diagnostics,
and best-in-class performance on every runtime — parslet as the anchor,
conformance as the law.

## What is already SOTA-equivalent (do not rebuild)

- Portable-artifact distribution with provenance (the tree-sitter model:
  one grammar, many language runtimes).
- Governance discipline: conformance corpus + compile-parity + shipped
  audits + envelope self-tests. Most grammar tools have nothing like it.
- Cause-tree diagnostics (deepest failure, expected sets, wire format).
- Performance vs parslet: native ~7-13x, VM memoized, incremental
  sessions.

## Tiers and files

| Tier | File | Frontier |
|---|---|---|
| 1 | [1-error-recovery.md](1-error-recovery.md) | partial trees + recovery (tree-sitter) — the flagship gap |
| 1 | [2-sota-benchmarks.md](2-sota-benchmarks.md) | honest published benchmarks vs pest/tree-sitter/Lark |
| 1 | [3-parg-formal-spec.md](3-parg-formal-spec.md) | operational semantics of PARG derived from the corpus |
| 1 | [4-lsp-playground.md](4-lsp-playground.md) | finish the LSP; grammar playground on the Astro site |
| 2 | [5-left-recursion.md](5-left-recursion.md) | Warth/Medeiros/Tratt — owner gate (parslet extension) |
| 2 | [6-compact-packrat.md](6-compact-packrat.md) | Ford's compact packrat memory discipline |
| 2 | [7-incremental-treesitter-grade.md](7-incremental-treesitter-grade.md) | structure-sharing splice (TODO.max-perf/9) |
| 3 | [8-fuzzing-and-verified-core.md](8-fuzzing-and-verified-core.md) | cross-engine differential fuzzing; verified core research |

## Execution laws

Everything in CLAUDE.md and agent memory applies. The ones that shape
this roadmap specifically:

1. **Cross-engine lockstep**: a semantic feature ships on BOTH engines
   (parsanol-ruby interpreter+VM, parsanol-rs portable+VM, wasm
   re-vendored) in one release train. Never one engine ahead.
2. **Corpus lockstep** (the WPT rule): every behavior change lands with
   its conformance corpus cases in the same PR. rs CI runs the gate on
   corpus changes.
3. **PRs only**; required checks green before merge; the shipped-audit
   fires automatically after every Release run — verify it passed.
4. **Owner gates**: version numbers, library requirements/floors (MSRV
   1.86; sha2/proptest pins), and semantics forks (e.g. #5 is a
   deliberate parslet extension) are decisions to ASK, never to take.
5. **Honest benchmarks**: interleaved same-condition A/B with GC.start;
   median-of-N; no tiny-input ratios; criterion delta-lines are
   meaningless across machines.
6. **Definition of DONE** for every file below: implementation on both
   engines + corpus cases + specs (real objects, no doubles) + guide
   updates + this file's Status flipped with PR links + releases
   through the trains + registry verification.

## Status

| File | Status |
|---|---|
| 1-error-recovery | open |
| 2-sota-benchmarks | open |
| 3-parg-formal-spec | open |
| 4-lsp-playground | open (LSP diagnostics exist) |
| 5-left-recursion | open — owner gate |
| 6-compact-packrat | open |
| 7-incremental-treesitter-grade | open |
| 8-fuzzing-and-verified-core | open |
