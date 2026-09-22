# 10 — Interface performance: Rust and Ruby boundary costs

Status: CLOSED (2026-09-17/22) — 1: honest negative (batch decode for
the extension tier measured slower, reverted rs #64); 2: DONE (cause
trees 1.3.23); 3: PARTIAL-honest (MRI dispatch floor, see item); 4:
DONE by design; 5: DONE (zero-copy guarded handle API); 6: DONE.

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
3. **VM per-step cost** (~500ns): PARTIAL (2026-09-17) — FAIL now
   dispatches through the case table (one fewer comparison per step)
   and the trace/env lookups hoisted out of the hot loop. Measured on
   a loaded machine: molecule ruby stays 1.7–1.8x parslet; the gain is
   within noise. Honest conclusion: MRI case-dispatch floors out
   around this cost; the remaining per-step levers (operand prefetch,
   flat bt/frames arrays) are each <10% and touch every opcode site at
   once. The next pure-Ruby speedup must come from algorithmic work
   (fewer steps per byte), not dispatch micro-optimization.
4. **Slice allocation diet**: DONE BY DESIGN — materialize already
   creates Slices only for Integer spans and NamedValue hashes; unnamed
   runs are joined into single packed spans by REP_EXIT/SEQ before
   materialize ever sees them. No per-char Slice allocation remains on
   the VM path.
5. **Handle-tier input copy**: `parse_handle` borrows zero-copy only
   when no Dynamic atoms; extend the guard to Lookahead bodies that
   capture (currently falls back to copying).
6. **FFI tier buffer reuse**: DONE (2026-09-16). One persistent
   `FFI::MemoryPointer`, grown geometrically — steady-state ffi parses
   allocate nothing. Validated: 1191 specs; pubid ffi differential
   7576/7621 identical.

## Step-cost findings (2026-09-16, molecule-grammar micro-bench)

Per-parse breakdown at "H_2O" (20k iterations): VM.run 37.5µs,
materialize included; finalize (CanFlatten re-walk) 8.7µs; program_for
gate 0.35µs; full parse 48.5µs — the wrapper is already thin.
finalize is NOT redundant: for unnamed-array roots it performs the
parslet slice-joining the tree contract requires; only Hash roots
would pass through untouched. The remaining lever for item 3 is the
executor loop itself (~375ns/step measured): flat backtrack/frame
arrays with manual index arithmetic instead of Array#<< chains, and
operand prefetch per case branch. Both are mechanical but touch every
opcode site at once — do them as a single dedicated change with the
differential harnesses as the gate.

## Non-goals

- No per-parse grammar work anywhere: all tiers already register once
  and reuse handles.
