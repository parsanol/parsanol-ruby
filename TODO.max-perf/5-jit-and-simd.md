# 5. JIT and SIMD token scanning (P2, research backlog)

## Why

After the bytecode VM (TODO.max-perf/4), the remaining levers match
the frontier: dynamic code generation per grammar and vectorized
byte classification. XGrammar-2 (arXiv:2601.04426) demonstrates 6x
compilation speedups and near-zero overhead with JIT + layered
caching; simdjson/Lemire's vectorized classification demonstrates
GB/s token scanning (tens of GB/s on ARM NEON).

## Design sketch

- **JIT**: compile the VM program to native code once per grammar
  with cranelift (no unsafe hand-rolled dynasm); cross-grammar
  substructure caching keyed on compiled-fragment hashes
  (XGrammar-2's Cross-Grammar Cache concept) so similar grammars
  share code.
- **SIMD**: lead-byte and token-class discrimination via vectorized
  256-entry table lookups across 16/32-byte blocks; the natural
  integration point is a `SCAN` opcode that strides over
  token-classes (identifiers, whitespace runs) instead of per-byte
  dispatch.
- Both build on the VM; landing them before it would duplicate work.

## Acceptance gates

- Differential parity unchanged; perf measured on the SRL corpus and
  `benches/large-input.rs`; memory bounded and freed with the
  grammar handle.

## Status

Superseded: SIMD shipped as parsanol-rs TODO.perf items 2+6;
shared-prefix split as item 3 (cranelift deferred with profile
evidence); see parsanol-rs TODO.perf/0-index.md.
