# 10 — Interface performance: Rust and Ruby boundary costs

Status: PLANNED (2026-09-15) — baselines measured, items ranked by leverage

## Measured baselines (2026-09-15, this machine)

| path | cost | note |
|---|---|---|
| molecule-large native | 0.19s / 20 × 9KB | 10.7x parslet; near-pure Rust |
| asciichem corpus Rust-only (`_parse_handle`) | 0.13s | 15x parslet |
| asciichem corpus full `Native.parse` | 2.69s | transform+fallback dominates |
| asciichem valid inputs (16) parse+decode | 0.25s | 7x parslet |
| asciichem invalid inputs (2) | ~6ms each | failure path (below) |
| pubid native | 0.028s / 250 ids | 6.9x parslet |
| VM step | ~180-500ns | pure-Ruby dispatch loop |

## Work items (ranked)

1. **Consolidate the two native decode paths** (correctness + perf).
   The extension tier does `transform_ast` (Rust folds) then Ruby
   AstTransformer heuristics; the ffi tier does raw flatten → one
   Ruby decode. The ffi path already achieves full tree parity with
   ONE decode and no Rust-side guessing. Port the extension tier onto
   the same raw-batch protocol: one decoder, one set of semantics,
   and the Rust side stops building Ruby objects per node (batch
   encoding is memcpy-cheap).
2. **Failure path**: build the parslet cause tree IN Rust (deepest
   failure tracking during backtracking) per TODO.perf/8 — removes the
   ~6ms-per-invalid-input interpreter fallback entirely.
3. **VM per-step cost** (~500ns): reorder the dispatch `case` by
   measured opcode frequency; split the hot prefix (STR/RE/RUN_*) into
   a dedicated loop before the general case table; avoid re-fetching
   `ops[pc+1..3]` individually by fetching once. Target 250-300ns/step
   → pure-Ruby reaches ~1.3-1.5x parslet on the real grammars.
4. **Slice allocation diet**: per-char Slices remain the interpreter's
   biggest allocator; only named captures need Slices (unnamed runs
   already join). Apply the same rule inside `materialize`.
5. **Handle-tier input copy**: `parse_handle` borrows zero-copy only
   when no Dynamic atoms; extend the guard to Lookahead bodies that
   capture (currently falls back to copying).
6. **FFI tier buffer reuse**: one `FFI::MemoryPointer` per thread,
   grown geometrically, instead of per-parse allocation.

## Non-goals

- No per-parse grammar work anywhere: all tiers already register once
  and reuse handles.
