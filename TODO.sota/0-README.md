# SOTA roadmap — vision, tiers, execution laws

## The vision

parsanol's purpose, synthesized from what the project actually is:

1. **parslet semantics are the migration contract — not the mission.**
   The Ruby DSL mirrors parslet and the flatten rules are byte-for-byte
   ports so existing users migrate without tree surprises; the mission
   itself is beyond parslet: PARG replaces ABNF as the grammar language
   of record and ANTLR as the parser generator (TODO.sota/9). The
   contract is corpus-enforced, which is exactly what lets the language
   evolve past its anchor safely.
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

## Tier 9 — the language evolution program

The active program that takes PARG beyond the parslet anchor: brace
bodies, core rules, opt-in modern capture, unicode-native engines, the
ABNF/ANTLR replacement importers, grammar semver tooling, bindings v2,
and the Rust frontend behind the wasm compiler. Scope and owner
decisions: TODO.sota/9-language-evolution.md.

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
| 1-error-recovery | done — R1, R1.5 partial trees, R2 inferred + declared resync on all runtimes; shipped |
| 2-sota-benchmarks | done — seven-tool table measured in one session (ruby#280/#281) |
| 3-parg-formal-spec | done — docs/parg-semantics.md |
| 4-lsp-playground | done — LSP #250; playground live |
| 5-left-recursion | done — owner approved the C9 compile-time rewrite (ruby#262) |
| 6-compact-packrat | done (bound + pins; spill not shipped, measured) |
| 7-incremental-treesitter-grade | done — splice chain from the spine trace; both gaps fixed and released |
| 8-fuzzing-and-verified-core | done — nightly four-path fuzz + wasm; B1 reference mode shipped; B2 run once and archived; B3 deferred |
