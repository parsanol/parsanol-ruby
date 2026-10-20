# 6 — Compact packrat memory discipline

Status: open — Tier 2.

## SOTA reference point

**Ford's compact packrat**: never DROP a parse result — spill to
secondary storage instead, keeping O(n) time with bounded memory. The
academic bound the practical work here has approximated.

## Current state (do not rebuild)

- All atoms memoized (rs#71); cache caps + recycle-at-cap (rs#120-era);
  snapshot tier for incremental sessions (32 MiB budget guard);
  DenseCache experiments with measured negatives on record (dense
  preallocation 1.8x regression — TODO.perf/7).

## Task

1. Formalize the current policy's memory bound (what IS the worst case
   today?) and document it next to the code.
2. Spill tier for giant inputs: cache entries beyond the cap go to a
   compact serialized form (the program-artifact cache already has a
   versioned format to reuse) instead of being recycled; measure
   expressir-giant inputs (600 KB+) end-to-end.
3. Benchmark memory-vs-time against the recycle policy; ship only on a
   measured win (the dense-memo negative result is the precedent —
   honest negatives stay documented).

## Acceptance

Documented bound; spill tier behind a flag until it proves itself;
regression pins for the giants; no regression on the
zero-backtracking micro-grammar class (+11-27% memoization overhead
known trade-off unchanged or better).
