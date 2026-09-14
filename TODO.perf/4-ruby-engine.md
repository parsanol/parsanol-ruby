# 4 — Ruby-engine allocation optimizations (pure `mode: :ruby`)

Status: DONE for the items below (2026-09-14); protocol-level items parked

## Context

The pure-Ruby path is the universal fallback (JRuby/TruffleRuby today, any
Ruby without the extension) and must beat parslet — it sits at ~1.2–1.3x.
Profiling (stackprof, object + cpu) shows the remaining cost is allocation
churn in the flatten/fold machinery and the repetition buffers, not
matching.

## Completed items

1. Lazy pool filling (no 16k preallocated objects per parse) — earlier
   session; this was the 15x → 1.3x turnaround.
2. Backtracking-triggered packrat caching (size heuristic was 1.7x slower
   on deterministic grammars).
3. `BufferPool#select_size_class` while-loop instead of `Enumerable#find`.
4. Memo table without per-position Hash allocation.
5. `Array#compact` / `select` in `CanFlatten` (`foldl`,
   `flatten_repetition`, `flatten_sequence` hash filtering) replaced with
   single-pass loops that skip nils in place — kills the intermediate array
   per fold call.
6. `LazyResult`/`Buffer#to_a` double materialization: repetition results
   now build the result Array directly instead of Buffer→push→to_a copy.

## Parked (protocol-level, only if we need >2x)

- `Base#ok` allocates `[true, value]` per success — same protocol as
  parslet; changing it means reworking every atom's contract. Measure first.
- Byte-set fast path in `Re#try` (bitmap of the char class's first set to
  skip the regex on failure) — semantics risk with multi-char patterns;
  needs the FirstSet analysis to be provably exact before use.
- `Source#consume` single-char fast path (`scanner.get_byte`) — encoding
  pitfalls; only worth it if `consume` resurfaces in profiles.

## Rule

Every change here must keep `mode: :ruby` output byte-identical
(1187-example suite + parity bench assert it).
